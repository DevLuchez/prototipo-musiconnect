from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text
from typing import List, Optional
import hashlib
import httpx

from app.database import get_db
from app.models import Institution
from app.schemas import InstitutionOut, InstitutionCreate

router = APIRouter(prefix="/api/institutions", tags=["institutions"])


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

    sql = text("""
        SELECT
            osm_id, name, address, lat, lng, category, source,
            verified, website, description, mb_id, wikidata_id
        FROM institutions
        WHERE ST_DWithin(
            location,
            ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography,
            :radius_m
        )
        ORDER BY location <-> ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography
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
    """
    sql = text("""
        SELECT osm_id, name, address, lat, lng, category, source,
               verified, website, description, mb_id, wikidata_id
        FROM institutions
        ORDER BY name
        LIMIT :limit
    """)
    rows = db.execute(sql, {"limit": limit})
    return [InstitutionOut(**row) for row in rows.mappings()]


@router.get("/stats")
def get_stats(db: Session = Depends(get_db)) -> dict:
    """Retorna estatísticas do banco (total, por categoria, última atualização)."""
    total = db.query(Institution).count()
    by_category = db.execute(
        text("SELECT category, COUNT(*) as count FROM institutions GROUP BY category ORDER BY count DESC")
    ).fetchall()
    last_update = db.execute(
        text("SELECT MAX(updated_at) FROM institutions")
    ).scalar()

    return {
        "total": total,
        "by_category": {row.category: row.count for row in by_category},
        "last_etl_run": str(last_update) if last_update else None,
    }


@router.get("/search", response_model=List[InstitutionOut])
def search_institutions(
    name: str = Query(..., description="Nome (busca parcial, case-insensitive)"),
    db: Session = Depends(get_db),
) -> List[InstitutionOut]:
    """
    Busca instituições por nome usando ILIKE (case-insensitive, correspondência parcial).
    Usado pela tela de detalhes de oportunidade ao clicar em 'Ver no mapa'.
    """
    rows = db.execute(
        text("""
            SELECT osm_id, name, address, lat, lng, category, source,
                   verified, website, description, mb_id, wikidata_id
            FROM institutions
            WHERE LOWER(name) LIKE LOWER(:pattern)
            ORDER BY name
            LIMIT 5
        """),
        {"pattern": f"%{name}%"},
    ).mappings()
    return [InstitutionOut(**row) for row in rows]


@router.post("/create", response_model=InstitutionOut, status_code=201)
async def create_institution(
    data: InstitutionCreate,
    db: Session = Depends(get_db),
) -> InstitutionOut:
    """
    Cria uma nova instituição musiconnect:
    1. Geocodifica via Nominatim (OpenStreetMap) usando nome + cidade + país.
    2. Salva na tabela institutions com source='musiconnect'.
    3. Retorna o registro criado.
    """
    # Gera osm_id único baseado no nome normalizado
    osm_id = f"mc_{hashlib.md5(data.name.lower().encode()).hexdigest()[:10]}"

    # Verifica se já existe
    existing = db.query(Institution).filter(Institution.osm_id == osm_id).first()
    if existing:
        return existing

    # Geocodifica via Nominatim
    query = ", ".join(filter(None, [data.name, data.city, data.country]))
    try:
        async with httpx.AsyncClient(
            headers={"User-Agent": "MusiConnect/1.0 (musiconnect.app)"}
        ) as client:
            resp = await client.get(
                "https://nominatim.openstreetmap.org/search",
                params={"q": query, "format": "json", "limit": 1},
                timeout=10,
            )
        results = resp.json()
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Geocodificação falhou: {e}")

    if not results:
        raise HTTPException(
            status_code=404,
            detail="Não foi possível geocodificar a instituição. Verifique o nome e a localização.",
        )

    geo = results[0]
    lat = float(geo["lat"])
    lng = float(geo["lon"])
    display_address = data.address or geo.get("display_name", query)

    institution = Institution(
        osm_id=osm_id,
        name=data.name,
        address=display_address,
        lat=lat,
        lng=lng,
        category=data.category,
        source="musiconnect",
        location=f"POINT({lng} {lat})",
        verified=False,
    )
    db.add(institution)
    db.commit()
    db.refresh(institution)
    return institution
