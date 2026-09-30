"""
Geocodificação e criação de instituições fora do ETL.

Usado pelo resolvedor (institution_resolver.py) quando a organizadora de
uma oportunidade ainda não existe no mapa. Substitui o antigo
`POST /api/institutions/create`, que era disparado pelo próprio usuário.

Geocodificação via Nominatim (OpenStreetMap) — política de uso exige
User-Agent identificável e no máximo 1 requisição por segundo.
"""

import asyncio
import hashlib
import logging
import re
import time
import unicodedata
from typing import Optional

import httpx
from sqlalchemy.orm import Session

from app.models import Institution
from app.services.osm_contacts import extract_contacts, save_contacts

logger = logging.getLogger("services.institution_factory")

NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"
NOMINATIM_HEADERS = {"User-Agent": "MusiConnect/1.0 (musiconnect.app)"}
_NOMINATIM_INTERVAL_S = 1.1

# Resultados que não podem ser a instituição: a cidade/região/rua em si
# (criaria um pino "genérico" no centro da cidade), paradas de transporte
# e comércio — ex: "Kunstuniversität Graz" casava com uma parada de bonde
# homônima e "IDEA" (Milão) com um salão de cabeleireiro.
_REJECTED_NOMINATIM_CATEGORIES = {
    "boundary", "place", "highway", "landuse", "natural", "waterway",
    "railway", "public_transport", "aeroway", "shop",
}

VALID_CATEGORIES = {"music_school", "music_org", "concert_hall", "theatre", "music_venue"}
DEFAULT_CATEGORY = "music_org"

# Tipo do objeto OSM devolvido pelo Nominatim → categoria do mapa. Quando o
# lugar existe no OSM com um tipo conhecido, ele prevalece sobre o palpite
# do LLM (mesma regra das instituições do ETL).
_OSM_TYPE_TO_CATEGORY = {
    "music_school": "music_school",
    "university": "music_school",
    "college": "music_school",
    "conservatory": "music_school",
    "theatre": "theatre",
    "concert_hall": "concert_hall",
    "arts_centre": "arts_centre",
    "music_venue": "music_venue",
    "nightclub": "music_venue",
}

_last_request_at = 0.0
_rate_lock = asyncio.Lock()


def normalize_name(value: Optional[str]) -> str:
    """Minúsculas, sem acentos, sem pontuação e com espaços simples.

    'ORQUESTRA SINFÔNICA  de S.C.' → 'orquestra sinfonica de s c'
    """
    if not value:
        return ""
    decomposed = unicodedata.normalize("NFKD", value)
    no_accents = "".join(c for c in decomposed if not unicodedata.combining(c))
    return re.sub(r"[^a-z0-9]+", " ", no_accents.lower()).strip()


def _fallback_id(name: str, city: Optional[str], country: Optional[str]) -> str:
    """ID para quando o Nominatim não devolve o objeto OSM de origem.

    Inclui cidade e país — só o nome fazia duas "Orquestra Municipal" de
    cidades diferentes colidirem no mesmo registro.
    """
    key = "|".join(normalize_name(p) for p in (name, city, country))
    return f"pl_{hashlib.md5(key.encode()).hexdigest()[:12]}"


async def geocode(client: httpx.AsyncClient, query: str) -> Optional[dict]:
    """Primeiro resultado do Nominatim para `query`, ou None.

    Descarta resultados que sejam a própria cidade/região (ver
    _REJECTED_NOMINATIM_CATEGORIES).
    """
    global _last_request_at
    async with _rate_lock:
        wait = _NOMINATIM_INTERVAL_S - (time.monotonic() - _last_request_at)
        if wait > 0:
            await asyncio.sleep(wait)
        try:
            resp = await client.get(
                NOMINATIM_URL,
                # extratags: devolve as tags do OSM (site, e-mail…) na mesma
                # consulta — usadas ao criar a instituição
                params={"q": query, "format": "jsonv2", "limit": 1, "extratags": 1},
                headers=NOMINATIM_HEADERS,
                timeout=15,
            )
            resp.raise_for_status()
            results = resp.json()
        except Exception as exc:
            logger.warning(f"[Geocode] Falha em '{query}': {exc}")
            return None
        finally:
            _last_request_at = time.monotonic()

    if not results:
        return None
    return results[0]


async def geocode_place(client: httpx.AsyncClient, query: str) -> Optional[dict]:
    """Como `geocode`, mas só aceita resultados que sejam um lugar específico."""
    result = await geocode(client, query)
    if result and result.get("category") in _REJECTED_NOMINATIM_CATEGORIES:
        return None
    return result


async def get_or_create_institution(
    db: Session,
    client: httpx.AsyncClient,
    *,
    name: str,
    city: Optional[str],
    country: Optional[str],
    category: Optional[str],
) -> Optional[str]:
    """Geocodifica a organizadora e devolve o osm_id do pino correspondente.

    - Se o Nominatim achar um objeto OSM que o ETL já importou (mesmo
      formato de ID, ex: 'node_123'), reaproveita esse registro.
    - Senão, cria a instituição com source='pipeline'.
    - Se não achar um lugar específico, devolve None — nunca inventa
      coordenadas nem cria pino genérico de cidade.
    """
    query = ", ".join(p for p in (name, city, country) if p)
    geo = await geocode_place(client, query)
    if not geo:
        return None

    if geo.get("osm_type") and geo.get("osm_id"):
        osm_id = f"{geo['osm_type']}_{geo['osm_id']}"
    else:
        osm_id = _fallback_id(name, city, country)

    existing = db.get(Institution, osm_id)
    if existing:
        return existing.osm_id

    lat = float(geo["lat"])
    lng = float(geo["lon"])
    db.add(Institution(
        osm_id=osm_id,
        name=name,
        address=geo.get("display_name"),
        lat=lat,
        lng=lng,
        category=(
            _OSM_TYPE_TO_CATEGORY.get(geo.get("type"))
            or (category if category in VALID_CATEGORIES else DEFAULT_CATEGORY)
        ),
        source="pipeline",
        location=f"SRID=4326;POINT({lng} {lat})",
        verified=False,
    ))
    db.commit()
    logger.info(f"[Factory] Instituição criada: '{name}' ({osm_id})")

    # Site/e-mail do OSM, com a mesma validação do ETL e do backfill
    await save_contacts(db, {osm_id: extract_contacts(geo.get("extratags") or {})})
    return osm_id
