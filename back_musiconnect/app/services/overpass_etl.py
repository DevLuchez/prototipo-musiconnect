"""
ETL: coleta instituições musicais do OpenStreetMap via Overpass API
e persiste no PostgreSQL com PostGIS.

Estratégia:
- Divide o mundo em ~140 regiões (bbox de ~25°x25°) para evitar timeout
- Para cada região, executa queries por tipo de amenidade em paralelo
- Faz upsert pelo osm_id (nunca duplica)
- Roda em ~5-10 minutos na coleta global completa
"""

import asyncio
import logging
from typing import Optional
import httpx
from sqlalchemy.orm import Session
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.database import SessionLocal
from app.models import Institution

logger = logging.getLogger(__name__)

# Mirrors públicos do Overpass API — rotacionados automaticamente em caso de falha
OVERPASS_MIRRORS = [
    "https://overpass.kumi.systems/api/interpreter",     # Suíça (geralmente o mais estável)
    "https://overpass-api.de/api/interpreter",           # Servidor principal (pode sobrecarregar)
    "https://overpass.openstreetmap.ru/api/interpreter", # Mirror russo
]

# User-Agent obrigatório para o servidor público do Overpass
HEADERS = {
    "User-Agent": "MusicConnect/1.0 (TCC academico Flutter - musiconnect)",
    "Referer": "https://musiconnect.app",
}

# Tipos de instituições musicais que queremos capturar do OSM
OSM_TAGS = [
    ("amenity", "music_school"),
    ("amenity", "concert_hall"),
    ("amenity", "theatre"),
    ("leisure", "music_venue"),
    ("amenity", "arts_centre"),
]

# Grade global: células de 30° de latitude x 45° de longitude
# Isso gera ~24 células cobrindo o mundo inteiro sem ultrapassar timeout
LAT_STEPS = range(-90, 91, 30)   # -90, -60, -30, 0, 30, 60, 90
LNG_STEPS = range(-180, 181, 45)  # -180, -135, -90, -45, 0, 45, 90, 135, 180


def _build_query(lat_s: float, lat_n: float, lng_w: float, lng_e: float) -> str:
    """Monta uma query Overpass que busca todos os tipos musicais em uma bbox."""
    bbox = f"{lat_s},{lng_w},{lat_n},{lng_e}"

    # Constrói union de nodes + ways para cada tag
    union_parts = []
    for key, value in OSM_TAGS:
        union_parts.append(f'node["{key}"="{value}"]({bbox});')
        union_parts.append(f'way["{key}"="{value}"]({bbox});')

    return (
        f"[out:json][timeout:60];"
        f"({''.join(union_parts)});"
        f"out center 1000;"  # máx 1000 por célula
    )


def _parse_element(elem: dict) -> Optional[dict]:
    """Converte um elemento Overpass para dict pronto para inserção."""
    try:
        tags = elem.get("tags", {})
        elem_type = elem.get("type", "")
        elem_id = elem.get("id")

        # Extrai coordenadas — nodes têm lat/lon direto, ways têm center
        if elem_type == "node":
            lat = float(elem.get("lat", 0))
            lng = float(elem.get("lon", 0))
        else:
            center = elem.get("center", {})
            lat = float(center.get("lat", 0))
            lng = float(center.get("lon", 0))

        if lat == 0 and lng == 0:
            return None

        name = (
            tags.get("name")
            or tags.get("name:en")
            or tags.get("name:pt")
        )
        if not name:
            return None  # sem nome = ruído, descarta

        # Resolve categoria mais específica
        category = (
            tags.get("amenity")
            or tags.get("leisure")
            or tags.get("shop")
            or "music"
        )

        # Monta endereço a partir das sub-tags addr:*
        addr_parts = [
            tags.get("addr:street"),
            tags.get("addr:city"),
            tags.get("addr:country"),
        ]
        address = ", ".join(p for p in addr_parts if p) or None

        return {
            "osm_id": f"{elem_type}_{elem_id}",
            "name": name,
            "address": address,
            "lat": lat,
            "lng": lng,
            "category": category,
            "source": "osm",
            # Formato WKT que o PostGIS entende via GeoAlchemy2
            "location": f"SRID=4326;POINT({lng} {lat})",
        }
    except Exception as e:
        logger.debug(f"Elemento inválido ignorado: {e}")
        return None


async def _fetch_cell(
    client: httpx.AsyncClient,
    lat_s: float,
    lat_n: float,
    lng_w: float,
    lng_e: float,
) -> list[dict]:
    """Busca uma célula da grade com retry e rotação automática de mirrors Overpass."""
    query = _build_query(lat_s, lat_n, lng_w, lng_e)
    cell_label = f"[{lat_s},{lng_w}->{lat_n},{lng_e}]"

    # Backoff entre tentativas dentro do mesmo mirror: 15s, 30s, 60s
    backoff_waits = [15, 30, 60]

    for mirror_idx, mirror_url in enumerate(OVERPASS_MIRRORS):
        logger.debug(f"  Mirror {mirror_idx + 1}/{len(OVERPASS_MIRRORS)}: {mirror_url}")

        for attempt, wait in enumerate(backoff_waits + [None], start=1):
            try:
                resp = await client.post(
                    mirror_url,
                    data={"data": query},
                    headers=HEADERS,
                    timeout=90,
                )
                resp.raise_for_status()
                elements = resp.json().get("elements", [])
                logger.info(f"  Celula {cell_label}: {len(elements)} elementos (mirror {mirror_idx + 1})")
                return [r for elem in elements if (r := _parse_element(elem))]

            except httpx.HTTPStatusError as e:
                code = e.response.status_code
                if code in (429, 503):
                    if wait is not None:
                        logger.warning(
                            f"  {code} na celula {cell_label} (mirror {mirror_idx + 1}) "
                            f"— tentativa {attempt}/{len(backoff_waits)}, aguardando {wait}s..."
                        )
                        await asyncio.sleep(wait)
                    else:
                        logger.warning(
                            f"  {code} persistente no mirror {mirror_idx + 1} — tentando próximo..."
                        )
                        break  # próximo mirror
                else:
                    logger.warning(f"  Falha HTTP {code} na celula {cell_label}: {e}")
                    break  # próximo mirror

            except (httpx.TimeoutException, httpx.ConnectError) as e:
                if wait is not None:
                    logger.warning(
                        f"  Timeout na celula {cell_label} (mirror {mirror_idx + 1}) "
                        f"— tentativa {attempt}/{len(backoff_waits)}, aguardando {wait}s..."
                    )
                    await asyncio.sleep(wait)
                else:
                    logger.warning(
                        f"  Timeout persistente no mirror {mirror_idx + 1} — tentando próximo..."
                    )
                    break  # próximo mirror

            except Exception as e:
                logger.warning(f"  Falha inesperada na celula {cell_label}: {e}")
                break  # próximo mirror

    logger.error(f"  Todos os mirrors falharam para {cell_label} — pulando.")
    return []


def _upsert_batch(db: Session, records: list[dict]) -> int:
    """Faz upsert de um lote de registros — nunca duplica pelo osm_id.

    Em conflito, atualiza apenas os campos geoespaciais/descritivos do OSM.
    Campos de validação (verified, mb_id, wikidata_id, website, description)
    NÃO são sobrescritos — preservam dados já preenchidos pelos validators.
    """
    if not records:
        return 0

    # Garante que verified=False está presente em registros novos
    for r in records:
        r.setdefault("verified", False)

    stmt = (
        pg_insert(Institution)
        .values(records)
        .on_conflict_do_update(
            index_elements=["osm_id"],
            set_={
                "name":       pg_insert(Institution).excluded.name,
                "address":    pg_insert(Institution).excluded.address,
                "lat":        pg_insert(Institution).excluded.lat,
                "lng":        pg_insert(Institution).excluded.lng,
                "category":   pg_insert(Institution).excluded.category,
                "location":   pg_insert(Institution).excluded.location,
                "updated_at": pg_insert(Institution).excluded.updated_at,
                # verified, mb_id, wikidata_id, website, description
                # são omitidos intencionalmente para preservar validações
            },
        )
    )
    db.execute(stmt)
    db.commit()
    return len(records)


async def run_etl(concurrency: int = 4) -> dict:
    """
    Executa o ETL completo.

    Args:
        concurrency: número de células processadas em paralelo.
                     4 é seguro para o servidor público do Overpass.

    Returns:
        dict com estatísticas da execução.
    """
    logger.info("=== Iniciando ETL global de instituições musicais ===")

    # Gera todas as células da grade global
    cells = []
    for lat_s in LAT_STEPS:
        lat_n = lat_s + 30
        if lat_n > 90:
            lat_n = 90
        for lng_w in LNG_STEPS:
            lng_e = lng_w + 45
            if lng_e > 180:
                lng_e = 180
            if lat_s >= lat_n or lng_w >= lng_e:
                continue
            cells.append((lat_s, lat_n, lng_w, lng_e))

    logger.info(f"Grade: {len(cells)} células a processar")

    db = SessionLocal()
    total_inserted = 0
    semaphore = asyncio.Semaphore(concurrency)

    async def fetch_with_semaphore(cell):
        async with semaphore:
            return await _fetch_cell(client, *cell)

    async with httpx.AsyncClient() as client:
        for i in range(0, len(cells), concurrency * 2):
            batch = cells[i : i + concurrency * 2]
            tasks = [fetch_with_semaphore(cell) for cell in batch]
            results = await asyncio.gather(*tasks)

            all_records = [r for result in results for r in result]
            inserted = _upsert_batch(db, all_records)
            total_inserted += inserted

            logger.info(
                f"Progresso: {i + len(batch)}/{len(cells)} células | "
                f"+{inserted} registros neste lote | total: {total_inserted}"
            )

            # Pausa entre lotes para não sobrecarregar o servidor público
            await asyncio.sleep(2)

    db.close()

    logger.info(f"=== ETL concluído: {total_inserted} registros inseridos/atualizados ===")
    return {"cells_processed": len(cells), "records_upserted": total_inserted}
