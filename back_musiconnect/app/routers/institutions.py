from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text
from typing import List, Optional

from app.database import get_db
from app.models import Institution, Opportunity, User
from app.schemas import InstitutionOut, OpportunityOut
from app.routers.auth import get_current_user_optional
from app.routers.opportunities import _apply_filters, _only_open
from app.services.matching import compute_match_breakdown

router = APIRouter(prefix="/api/institutions", tags=["institutions"])

# Oportunidades visíveis no app (mesmo critério da aba Matcher: ativa,
# confiança >= 0.80 e prazo vigente), contadas por pino do mapa.
_ACTIVE_OPPORTUNITIES_JOIN = """
    LEFT JOIN (
        SELECT institution_id, COUNT(*) AS n
        FROM opportunities
        WHERE institution_id IS NOT NULL
          AND is_active
          AND llm_confidence >= 0.80
          AND (deadline IS NULL OR deadline >= CURRENT_DATE)
        GROUP BY institution_id
    ) oc ON oc.institution_id = i.osm_id
"""

_INSTITUTION_COLUMNS = """
    i.osm_id, i.name, i.address, i.lat, i.lng, i.category, i.source,
    i.verified, i.website, i.email, i.mb_id, i.wikidata_id,
    COALESCE(oc.n, 0) AS active_opportunities_count
"""


@router.get("/nearby", response_model=List[InstitutionOut])
def get_nearby_institutions(
    lat: float = Query(..., description="Latitude do centro da busca"),
    lng: float = Query(..., description="Longitude do centro da busca"),
    radius_m: int = Query(50_000, ge=1_000, le=500_000, description="Raio em metros (1km a 500km)"),
    limit: int = Query(500, ge=1, le=5000, description="Máximo de resultados"),
    db: Session = Depends(get_db),
) -> List[InstitutionOut]:
    """
    Retorna instituições musicais dentro de um raio ao redor de lat/lng.

    Usa ST_DWithin do PostGIS com índice GIST — busca em ~millisegundos
    mesmo com 100k+ registros no banco. Independente de zoom.
    """
    if not (-90 <= lat <= 90) or not (-180 <= lng <= 180):
        raise HTTPException(status_code=422, detail="Coordenadas inválidas.")

    sql = text(f"""
        SELECT {_INSTITUTION_COLUMNS}
        FROM institutions i
        {_ACTIVE_OPPORTUNITIES_JOIN}
        WHERE ST_DWithin(
            i.location,
            ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography,
            :radius_m
        )
        ORDER BY i.location <-> ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography
        LIMIT :limit
    """)

    rows = db.execute(sql, {"lat": lat, "lng": lng, "radius_m": radius_m, "limit": limit})
    return [InstitutionOut(**row) for row in rows.mappings()]


@router.get("/all", response_model=List[InstitutionOut])
def get_all_institutions(
    limit: int = Query(10000, ge=1, le=100000, description="Máximo de resultados (padrão: 10000)"),
    db: Session = Depends(get_db),
) -> List[InstitutionOut]:
    """
    Retorna TODAS as instituições do banco, sem filtro geoespacial.

    Usado pela carga inicial do mapa Flutter para exibir todos os marcadores
    imediatamente ao abrir o app, independentemente de zoom ou posição.
    As que têm oportunidades abertas vêm primeiro, para nunca ficarem de
    fora do corte por `limit`.
    """
    sql = text(f"""
        SELECT {_INSTITUTION_COLUMNS}
        FROM institutions i
        {_ACTIVE_OPPORTUNITIES_JOIN}
        ORDER BY (oc.n IS NULL), i.name
        LIMIT :limit
    """)
    rows = db.execute(sql, {"limit": limit})
    return [InstitutionOut(**row) for row in rows.mappings()]


@router.get("/stats")
def get_stats(db: Session = Depends(get_db)) -> dict:
    """Retorna estatísticas do banco (total, por categoria, com oportunidades, última atualização)."""
    total = db.query(Institution).count()
    by_category = db.execute(
        text("SELECT category, COUNT(*) as count FROM institutions GROUP BY category ORDER BY count DESC")
    ).fetchall()
    last_update = db.execute(
        text("SELECT MAX(updated_at) FROM institutions")
    ).scalar()
    with_opportunities = db.execute(
        text(f"SELECT COUNT(*) FROM institutions i {_ACTIVE_OPPORTUNITIES_JOIN} WHERE oc.n > 0")
    ).scalar()

    return {
        "total": total,
        "by_category": {row.category: row.count for row in by_category},
        "with_active_opportunities": with_opportunities,
        "last_etl_run": str(last_update) if last_update else None,
    }


@router.get("/search", response_model=List[InstitutionOut])
def search_institutions(
    q: str = Query(..., min_length=2, description="Trecho do nome ou do endereço"),
    limit: int = Query(8, ge=1, le=50),
    db: Session = Depends(get_db),
) -> List[InstitutionOut]:
    """
    Busca da barra do mapa em TODAS as instituições do banco — o app só
    carrega parte delas em memória (carga inicial + arredores da câmera),
    então buscar só no que está carregado deixava ~2/3 de fora.

    Sem diferenciar maiúsculas nem acentos. Ordem: nome que começa com o
    termo, depois nome que contém, depois endereço; dentro de cada grupo,
    as com oportunidades abertas primeiro.

    Precisa vir ANTES de /{osm_id} no router.
    """
    sql = text(f"""
        SELECT {_INSTITUTION_COLUMNS}
        FROM institutions i
        {_ACTIVE_OPPORTUNITIES_JOIN}
        WHERE unaccent(lower(i.name)) LIKE unaccent(lower(:contains))
           OR unaccent(lower(coalesce(i.address, ''))) LIKE unaccent(lower(:contains))
        ORDER BY
            CASE
                WHEN unaccent(lower(i.name)) LIKE unaccent(lower(:prefix)) THEN 0
                WHEN unaccent(lower(i.name)) LIKE unaccent(lower(:contains)) THEN 1
                ELSE 2
            END,
            (oc.n IS NULL),
            i.name
        LIMIT :limit
    """)
    # Escapa curingas do LIKE digitados pelo usuário
    term = q.strip().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    rows = db.execute(sql, {"contains": f"%{term}%", "prefix": f"{term}%", "limit": limit})
    return [InstitutionOut(**row) for row in rows.mappings()]


@router.get("/{osm_id}", response_model=InstitutionOut)
def get_institution(osm_id: str, db: Session = Depends(get_db)) -> InstitutionOut:
    """
    Uma instituição pelo osm_id — usado pelo botão "Ver no mapa" da
    oportunidade quando o pino ainda não foi carregado pelo mapa.

    Precisa vir DEPOIS de /nearby, /all e /stats no router — senão o
    FastAPI casaria esses caminhos como osm_id.
    """
    row = db.execute(
        text(f"""
            SELECT {_INSTITUTION_COLUMNS}
            FROM institutions i
            {_ACTIVE_OPPORTUNITIES_JOIN}
            WHERE i.osm_id = :osm_id
        """),
        {"osm_id": osm_id},
    ).mappings().first()
    if not row:
        raise HTTPException(status_code=404, detail="Instituição não encontrada")
    return InstitutionOut(**row)


@router.get("/{osm_id}/opportunities", response_model=List[OpportunityOut])
def get_institution_opportunities(
    osm_id: str,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user_optional),
):
    """Oportunidades visíveis no app vinculadas a esta instituição (prazo mais próximo primeiro)."""
    items = (
        _only_open(_apply_filters(db.query(Opportunity)))
        .filter(Opportunity.institution_id == osm_id)
        .order_by(Opportunity.deadline.asc().nulls_last())
        .all()
    )
    if current_user:
        for opp in items:
            breakdown = compute_match_breakdown(current_user, opp)
            opp.match_percentage = breakdown.total
            opp.match_breakdown = breakdown
    return items
