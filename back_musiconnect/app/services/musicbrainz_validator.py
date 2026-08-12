"""
Validação cruzada com MusicBrainz.

Estratégia:
- Para cada instituição não verificada no banco, busca na API do MusicBrainz
  usando nome + tipo de lugar (mapeado da categoria OSM).
- Faz match por similaridade de nome (>= 75%) e proximidade geográfica (<= 500m).
- Taxa: 1 req/segundo (obrigatório por ToS do MusicBrainz).
- Instituições confirmadas recebem verified=True, mb_id e website.
"""

import asyncio
import difflib
import logging
import math
from typing import Optional

import httpx
from sqlalchemy import text

from app.database import SessionLocal

logger = logging.getLogger(__name__)

MB_SEARCH_URL = "https://musicbrainz.org/ws/2/place"
MB_HEADERS = {
    "User-Agent": "MusicConnect/1.0 (TCC academico - laura.luchez@catolicasc.edu.br)",
}

# Mapeamento das categorias OSM para tipos de lugar no MusicBrainz
CATEGORY_TO_MB_TYPE: dict[str, Optional[str]] = {
    "music_school": "School",
    "concert_hall": "Concert hall",
    "theatre": "Theatre",
    "music_venue": "Venue",
    "arts_centre": None,  # Sem tipo direto — busca só por nome
}


def _haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Distância em metros entre dois pontos geográficos (fórmula Haversine)."""
    R = 6_371_000
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _name_similarity(a: str, b: str) -> float:
    return difflib.SequenceMatcher(None, a.lower().strip(), b.lower().strip()).ratio()


async def _search_mb_places(
    client: httpx.AsyncClient,
    name: str,
    mb_type: Optional[str],
) -> list[dict]:
    """Busca lugares no MusicBrainz por nome (e tipo opcional)."""
    query = f'name:"{name}"'
    if mb_type:
        query += f' AND type:"{mb_type}"'

    try:
        resp = await client.get(
            MB_SEARCH_URL,
            params={"query": query, "fmt": "json", "limit": 5},
            headers=MB_HEADERS,
            timeout=15,
        )
        if resp.status_code == 200:
            return resp.json().get("places", [])
        if resp.status_code in (429, 503):
            logger.warning("MusicBrainz rate-limit/sobrecarga — aguardando 5s...")
            await asyncio.sleep(5)
        return []
    except Exception as e:
        logger.debug(f"Erro ao buscar '{name}': {e}")
        return []


def _best_match(
    places: list[dict],
    name: str,
    lat: float,
    lng: float,
) -> Optional[dict]:
    """Retorna o melhor place do MusicBrainz que corresponde ao nome e coordenadas."""
    best, best_score = None, 0.0

    for place in places:
        sim = _name_similarity(name, place.get("name", ""))
        if sim < 0.75:
            continue

        coords = place.get("coordinates")
        if coords and coords.get("latitude") and coords.get("longitude"):
            # MusicBrainz retorna coordenadas como string — converter para float
            dist = _haversine_m(lat, lng, float(coords["latitude"]), float(coords["longitude"]))
            if dist > 500:
                continue
            score = sim * 0.7 + (1 - min(dist, 500) / 500) * 0.3
        else:
            score = sim * 0.7  # sem coords, confia mais no nome

        if score > best_score:
            best_score, best = score, place

    return best if best_score >= 0.6 else None


def _extract_website(place: dict) -> Optional[str]:
    """Extrai URL do site oficial das relações do place MusicBrainz."""
    for rel in place.get("relations", []):
        if rel.get("type") == "official homepage":
            return rel.get("url", {}).get("resource")
    return None


async def run_musicbrainz_validation() -> dict:
    """
    Valida instituições não verificadas contra o MusicBrainz.
    Rate-limited a 1 req/segundo conforme ToS.

    Returns:
        dict com total processado e total verificado.
    """
    logger.info("=== Iniciando validação MusicBrainz ===")

    db = SessionLocal()
    rows = db.execute(
        text(
            "SELECT osm_id, name, lat, lng, category "
            "FROM institutions WHERE verified = FALSE AND category IN ('concert_hall', 'music_venue') ORDER BY name"
        )
    ).fetchall()

    total = len(rows)
    verified_count = 0
    logger.info(f"Instituições a validar: {total}")

    async with httpx.AsyncClient() as client:
        for i, (osm_id, name, lat, lng, category) in enumerate(rows):
            mb_type = CATEGORY_TO_MB_TYPE.get(category)
            places = await _search_mb_places(client, name, mb_type)

            if places:
                match = _best_match(places, name, lat, lng)
                if match:
                    mb_id = match.get("id")
                    website = _extract_website(match)

                    # Tenta setar mb_id; se já existir em outro registro, só marca verified
                    try:
                        db.execute(
                            text("""
                                UPDATE institutions
                                SET verified = TRUE,
                                    mb_id = :mb_id,
                                    website = COALESCE(website, :website)
                                WHERE osm_id = :osm_id AND mb_id IS NULL
                            """),
                            {"osm_id": osm_id, "mb_id": mb_id, "website": website},
                        )
                    except Exception:
                        db.rollback()
                        db.execute(
                            text("""
                                UPDATE institutions
                                SET verified = TRUE,
                                    website = COALESCE(website, :website)
                                WHERE osm_id = :osm_id
                            """),
                            {"osm_id": osm_id, "website": website},
                        )
                    db.commit()
                    verified_count += 1
                    logger.info(f"  ✓ '{name}' → '{match.get('name')}' ({mb_id})")

            if (i + 1) % 100 == 0:
                logger.info(f"  Progresso: {i + 1}/{total} | verificados: {verified_count}")

            # Rate limit obrigatório: 1 req/seg
            await asyncio.sleep(1.1)

    db.close()
    logger.info(f"=== MusicBrainz concluído: {verified_count}/{total} verificados ===")
    return {"total": total, "verified": verified_count}
