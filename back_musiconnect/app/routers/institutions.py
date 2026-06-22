from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text
from typing import List

from app.database import get_db
from app.models import Institution
from app.schemas import InstitutionOut

router = APIRouter(prefix="/api/institutions", tags=["institutions"])


@router.get("/nearby", response_model=List[InstitutionOut])
def get_nearby_institutions(
    lat: float = Query(..., description="Latitude do centro da busca"),
    lng: float = Query(..., description="Longitude do centro da busca"),
    radius_m: int = Query(50_000, ge=1_000, le=500_000, description="Raio em metros (1km a 500km)"),
    limit: int = Query(500, ge=1, le=2000, description="Máximo de resultados"),
    db: Session = Depends(get_db),
) -> List[InstitutionOut]:
    """
    Retorna instituições musicais dentro de um raio ao redor de lat/lng.

    Usa ST_DWithin do PostGIS com índice GIST — busca em ~millisegundos
    mesmo com 100k+ registros no banco. Independente de zoom.
    """
    if not (-90 <= lat <= 90) or not (-180 <= lng <= 180):
        raise HTTPException(status_code=422, detail="Coordenadas inválidas.")

    # ST_DWithin com Geography calcula distância real em metros (não graus)
    sql = text("""
        SELECT
            osm_id, name, address, lat, lng, category, source
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
    return [InstitutionOut(**row._mapping) for row in rows]


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
