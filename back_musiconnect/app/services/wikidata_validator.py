"""
Validação cruzada com Wikidata via SPARQL.

Estratégia:
- Ao invés de consultar item por item (como MusicBrainz), busca TODOS os itens
  de cada tipo musical no Wikidata de uma vez (query global por categoria).
- Faz o match localmente por proximidade geográfica (<= 500m) + similaridade
  de nome (>= 65%).
- Muito mais eficiente: apenas 5 queries SPARQL para o mundo inteiro.
- Enriquece com: website (quando a instituição ainda não tem um).
"""

import asyncio
import difflib
import logging
import math
import re
from typing import Optional

import httpx
from sqlalchemy import text

from app.database import SessionLocal

logger = logging.getLogger(__name__)

SPARQL_URL = "https://query.wikidata.org/sparql"
SPARQL_HEADERS = {
    "User-Agent": "MusicConnect/1.0 (TCC academico - laura.luchez@catolicasc.edu.br)",
    "Accept": "application/sparql-results+json",
}

# Q-IDs Wikidata por categoria OSM
CATEGORY_TO_WIKIDATA: dict[str, list[str]] = {
    "music_school":  ["Q9842"],            # escola de música
    "concert_hall":  ["Q8503"],            # sala de concerto
    "theatre":       ["Q24354", "Q153562"], # teatro, casa de ópera
    "music_venue":   ["Q207694"],           # local de música ao vivo
    "arts_centre":   ["Q1497375"],          # centro cultural/artístico
}


def _haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    R = 6_371_000
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _parse_wkt_point(wkt: str) -> Optional[tuple[float, float]]:
    """Converte 'Point(-46.63 -23.55)' em (lat, lon)."""
    m = re.match(r"Point\(\s*([+-]?\d+\.?\d*)\s+([+-]?\d+\.?\d*)\s*\)", wkt, re.IGNORECASE)
    if m:
        return float(m.group(2)), float(m.group(1))  # lat, lon
    return None


def _name_similarity(a: str, b: str) -> float:
    return difflib.SequenceMatcher(None, a.lower().strip(), b.lower().strip()).ratio()


def _build_sparql(q_ids: list[str]) -> str:
    values = " ".join(f"wd:{q}" for q in q_ids)
    return f"""
SELECT DISTINCT ?item ?name ?coords ?website WHERE {{
  VALUES ?type {{ {values} }}
  ?item wdt:P31 ?type .
  ?item wdt:P625 ?coords .
  ?item rdfs:label ?name .
  FILTER(LANG(?name) IN ("pt", "en", "es", "fr", "de"))
  OPTIONAL {{ ?item wdt:P856 ?website }}
}}
LIMIT 10000
"""


async def _fetch_wikidata(client: httpx.AsyncClient, q_ids: list[str]) -> list[dict]:
    """Executa query SPARQL e retorna lista de instituições com coordenadas."""
    query = _build_sparql(q_ids)
    try:
        resp = await client.post(
            SPARQL_URL,
            data={"query": query},
            headers=SPARQL_HEADERS,
            timeout=60,
        )
        resp.raise_for_status()
        bindings = resp.json().get("results", {}).get("bindings", [])

        items = []
        for b in bindings:
            coords = _parse_wkt_point(b.get("coords", {}).get("value", ""))
            if not coords:
                continue
            items.append({
                "wikidata_id": b["item"]["value"].split("/")[-1],
                "name":        b.get("name", {}).get("value", ""),
                "lat":         coords[0],
                "lng":         coords[1],
                "website":     b.get("website", {}).get("value"),
            })
        return items

    except Exception as e:
        logger.warning(f"Erro SPARQL para {q_ids}: {e}")
        return []


async def run_wikidata_validation() -> dict:
    """
    Valida instituições não verificadas contra o Wikidata via SPARQL.

    Returns:
        dict com total verificado por categoria.
    """
    logger.info("=== Iniciando validação Wikidata ===")

    db = SessionLocal()
    total_verified = 0

    async with httpx.AsyncClient() as client:
        for category, q_ids in CATEGORY_TO_WIKIDATA.items():
            logger.info(f"  Categoria '{category}' ({', '.join(q_ids)})...")

            wd_items = await _fetch_wikidata(client, q_ids)
            logger.info(f"    → {len(wd_items)} itens no Wikidata")

            if not wd_items:
                continue

            db_rows = db.execute(
                text(
                    "SELECT osm_id, name, lat, lng FROM institutions "
                    "WHERE verified = FALSE AND category = :cat"
                ),
                {"cat": category},
            ).fetchall()

            logger.info(f"    → {len(db_rows)} não verificadas no banco")

            matched = 0
            for osm_id, name, lat, lng in db_rows:
                best, best_score = None, 0.0

                for wd in wd_items:
                    dist = _haversine_m(lat, lng, wd["lat"], wd["lng"])
                    if dist > 500:
                        continue
                    sim = _name_similarity(name, wd["name"])
                    if sim < 0.65:
                        continue
                    score = sim * 0.6 + (1 - min(dist, 500) / 500) * 0.4
                    if score > best_score:
                        best_score, best = score, wd

                if best and best_score >= 0.55:
                    try:
                        db.execute(
                            text("""
                                UPDATE institutions SET
                                    verified     = TRUE,
                                    wikidata_id  = :wid,
                                    website      = COALESCE(website, :website)
                                WHERE osm_id = :osm_id AND wikidata_id IS NULL
                            """),
                            {
                                "osm_id":  osm_id,
                                "wid":     best["wikidata_id"],
                                "website": best.get("website"),
                            },
                        )
                    except Exception:
                        db.rollback()
                        db.execute(
                            text("""
                                UPDATE institutions SET
                                    verified    = TRUE,
                                    website     = COALESCE(website, :website)
                                WHERE osm_id = :osm_id
                            """),
                            {"osm_id": osm_id, "website": best.get("website")},
                        )
                    db.commit()
                    matched += 1
                    logger.info(f"    ✓ '{name}' → '{best['name']}' ({best['wikidata_id']})")

            total_verified += matched
            logger.info(f"    '{category}': {matched}/{len(db_rows)} verificados")

            # Pausa entre categorias para não sobrecarregar o Wikidata
            await asyncio.sleep(3)

    db.close()
    logger.info(f"=== Wikidata concluído: {total_verified} verificados ===")
    return {"verified": total_verified}
