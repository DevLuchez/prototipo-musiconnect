"""
ETL: coleta instituições musicais do OpenStreetMap e persiste no
PostgreSQL com PostGIS.

Fonte: QLever (https://qlever.dev/api/osm-planet), da Universidade de
Freiburg — uma cópia do planeta OSM inteiro consultável por SPARQL.
Substituiu o Overpass em 10/2026: o Overpass público exigia dividir o mundo
numa grade de células de 30°x45°, que estouravam o timeout do servidor
(células inteiras puladas, inclusive todo o Brasil), cortava cada célula em
1000 resultados e, quando estourava o tempo no servidor, devolvia lista
vazia com HTTP 200 — o ETL só trazia ~16 mil das ~80 mil instituições.

Estratégia:
- Uma busca por tipo de instituição (OSM_TAGS), sem grade geográfica
- Pinos (centróide calculado no servidor) e tags em consultas separadas:
  juntar as duas numa consulta só, com muitos OPTIONAL, trava o servidor
- Paginada (ORDER BY + LIMIT/OFFSET): respostas longas demais são cortadas
  pelo servidor; o QLever guarda o resultado em cache entre as páginas
- Faz upsert pelo osm_id (nunca duplica)
- Roda em ~3 minutos para os pinos do mundo todo; os contatos (que testam
  se cada site responde) levam mais, mas só para quem ainda não tem site
"""

import asyncio
import logging
from typing import Optional

import httpx
from sqlalchemy.orm import Session
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.database import SessionLocal
from app.models import Institution
from app.services.osm_contacts import extract_contacts, save_contacts

logger = logging.getLogger(__name__)

QLEVER_ENDPOINT = "https://qlever.dev/api/osm-planet"
QLEVER_HEADERS = {
    "Accept": "application/sparql-results+json",
    "User-Agent": "MusicConnect/1.0 (TCC academico Flutter - musiconnect)",
}
QLEVER_TIMEOUT = 400  # segundos — a 1ª página calcula o resultado inteiro

# IRIs do OSM no QLever: objetos são https://www.openstreetmap.org/node/123
# e tags são https://www.openstreetmap.org/wiki/Key:<tag>
OSM_IRI = "https://www.openstreetmap.org/"
OSM_KEY_IRI = f"{OSM_IRI}wiki/Key:"

PAGE_SIZE = 10000
UPSERT_BATCH_SIZE = 2000
CONTACTS_BATCH_SIZE = 500

# Espera entre tentativas de uma mesma página
RETRY_WAITS = [10, 30, 60, 120]

# Tipos de instituições musicais que queremos capturar do OSM
OSM_TAGS = [
    ("amenity", "music_school"),
    ("amenity", "concert_hall"),
    ("amenity", "theatre"),
    ("leisure", "music_venue"),
    ("amenity", "arts_centre"),
]

# Tags lidas por _parse_element/extract_contacts
WANTED_TAGS = [
    "name", "name:en", "name:pt",
    "amenity", "leisure", "shop",
    "addr:street", "addr:city", "addr:country",
    "website", "contact:website", "url",
    "email", "contact:email",
]

# Correções manuais sobre o OSM — aplicadas a cada coleta, então não se perdem
# quando o ETL roda de novo.
# Objetos ignorados: pins que duplicam outro na prática (mesmo lugar, outro
# objeto no OSM).
OSM_IGNORED_IDS: set[str] = set()
# Nomes exibidos no lugar do nome do OSM.
OSM_NAME_OVERRIDES = {
    # No OSM é "Teatro Scar" (polígono do prédio). Até 10/2026 a SCAR eram
    # dois pontos (node_6331636363 e o duplicado node_6331636362), apagados
    # do OSM quando o prédio foi desenhado.
    "way_256649111": "SCAR – Sociedade Cultura Artística",
}

_PREFIXES = f"""
PREFIX osmkey: <{OSM_KEY_IRI}>
PREFIX geo: <http://www.opengis.net/ont/geosparql#>
PREFIX geof: <http://www.opengis.net/def/function/geosparql/>
"""


def _build_geo_query(key: str, value: str) -> str:
    """Pinos de um tipo: objeto + centróide (ways são polígonos)."""
    return _PREFIXES + f"""
SELECT ?o ?lat ?lng WHERE {{
  ?o osmkey:{key} "{value}" ; geo:hasGeometry/geo:asWKT ?wkt .
  BIND(geof:centroid(?wkt) AS ?c)
  BIND(geof:latitude(?c) AS ?lat) BIND(geof:longitude(?c) AS ?lng)
}} ORDER BY ?o"""


def _build_tags_query(key: str, value: str) -> str:
    """Tags que interessam dos objetos de um tipo (uma linha por tag)."""
    values = " ".join(f"osmkey:{tag}" for tag in WANTED_TAGS)
    return _PREFIXES + f"""
SELECT ?o ?p ?v WHERE {{
  ?o osmkey:{key} "{value}" ; ?p ?v .
  VALUES ?p {{ {values} }}
}} ORDER BY ?o ?p"""


async def _fetch_all_pages(client: httpx.AsyncClient, query: str, label: str) -> list[dict]:
    """Busca todas as páginas de uma consulta, com retry por página.

    Erro de consulta do QLever volta como JSON com status ERROR (HTTP 4xx/5xx);
    resposta cortada no meio falha no parse do JSON — os dois caem no retry.
    """
    rows: list[dict] = []
    offset = 0
    while True:
        paged = f"{query} LIMIT {PAGE_SIZE} OFFSET {offset}"
        for attempt, wait in enumerate(RETRY_WAITS + [None], start=1):
            try:
                resp = await client.get(
                    QLEVER_ENDPOINT,
                    params={"query": paged},
                    headers=QLEVER_HEADERS,
                    timeout=QLEVER_TIMEOUT,
                )
                resp.raise_for_status()
                page = resp.json()["results"]["bindings"]
                break
            except Exception as e:
                if wait is None:
                    raise RuntimeError(
                        f"QLever falhou para {label} (offset {offset}) "
                        f"após {attempt} tentativas: {e!r}"
                    ) from e
                logger.warning(
                    f"  {label} offset {offset}: {e!r} — tentativa "
                    f"{attempt}/{len(RETRY_WAITS)}, aguardando {wait}s..."
                )
                await asyncio.sleep(wait)
        rows += page
        if len(page) < PAGE_SIZE:
            return rows
        offset += PAGE_SIZE


def _build_elements(geo_rows: list[dict], tag_rows: list[dict]) -> list[dict]:
    """Junta pinos e tags no formato de elemento do OSM (o mesmo do Overpass)
    que o _parse_element lê. Mantém só nodes e ways."""
    tags_by_iri: dict[str, dict] = {}
    for row in tag_rows:
        tags = tags_by_iri.setdefault(row["o"]["value"], {})
        # Tag com vários valores vira várias linhas: fica a primeira
        tags.setdefault(row["p"]["value"].removeprefix(OSM_KEY_IRI), row["v"]["value"])

    elements = []
    for row in geo_rows:
        iri = row["o"]["value"]
        try:
            elem_type, elem_id = iri.removeprefix(OSM_IRI).split("/")
            lat, lng = float(row["lat"]["value"]), float(row["lng"]["value"])
            elem_id = int(elem_id)
        except (KeyError, ValueError):
            continue  # sem centróide ou IRI fora do padrão
        if elem_type not in ("node", "way"):
            continue

        elem = {"type": elem_type, "id": elem_id, "tags": tags_by_iri.get(iri, {})}
        if elem_type == "node":
            elem.update(lat=lat, lon=lng)
        else:
            elem["center"] = {"lat": lat, "lon": lng}
        elements.append(elem)
    return elements


def _parse_element(elem: dict) -> Optional[dict]:
    """Converte um elemento do OSM para dict pronto para inserção."""
    try:
        tags = elem.get("tags", {})
        elem_type = elem.get("type", "")
        elem_id = elem.get("id")
        osm_id = f"{elem_type}_{elem_id}"
        if osm_id in OSM_IGNORED_IDS:
            return None

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
            OSM_NAME_OVERRIDES.get(osm_id)
            or tags.get("name")
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
        website, email = extract_contacts(tags)

        return {
            "osm_id": osm_id,
            "name": name,
            "address": address,
            "lat": lat,
            "lng": lng,
            "category": category,
            "website": website,
            "email": email,
            "source": "osm",
            # Formato WKT que o PostGIS entende via GeoAlchemy2
            "location": f"SRID=4326;POINT({lng} {lat})",
        }
    except Exception as e:
        logger.debug(f"Elemento inválido ignorado: {e}")
        return None


def _upsert_batch(db: Session, records: list[dict]) -> int:
    """Faz upsert de um lote de registros — nunca duplica pelo osm_id.

    Em conflito, atualiza apenas os campos geoespaciais/descritivos do OSM.
    Campos de validação/contato (verified, mb_id, wikidata_id, website, email)
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
                # verified, mb_id, wikidata_id, website, email
                # são omitidos intencionalmente para preservar validações
            },
        )
    )
    db.execute(stmt)
    db.commit()
    return len(records)


async def _collect_records(client: httpx.AsyncClient) -> dict[str, dict]:
    """Busca todos os tipos de OSM_TAGS e devolve osm_id → registro."""
    records: dict[str, dict] = {}
    for key, value in OSM_TAGS:
        geo_rows = await _fetch_all_pages(client, _build_geo_query(key, value), f"{value} (pinos)")
        tag_rows = await _fetch_all_pages(client, _build_tags_query(key, value), f"{value} (tags)")
        new = 0
        for elem in _build_elements(geo_rows, tag_rows):
            record = _parse_element(elem)
            # O mesmo objeto pode ter duas tags musicais: fica o primeiro tipo
            if record and record["osm_id"] not in records:
                records[record["osm_id"]] = record
                new += 1
        logger.info(
            f"  {key}={value}: {len(geo_rows)} pinos, {new} instituições "
            f"| acumulado: {len(records)}"
        )
    return records


async def run_etl() -> dict:
    """
    Executa o ETL completo.

    Returns:
        dict com estatísticas da execução.
    """
    logger.info("=== Iniciando ETL global de instituições musicais (QLever) ===")

    async with httpx.AsyncClient(follow_redirects=True) as client:
        records = await _collect_records(client)

    # Site/e-mail não entram no upsert: passam por save_contacts,
    # que só grava site que responde (links mortos do OSM ficam fora).
    contacts = {
        osm_id: (r.pop("website"), r.pop("email")) for osm_id, r in records.items()
    }
    batch = list(records.values())

    db = SessionLocal()
    try:
        total_upserted = 0
        for i in range(0, len(batch), UPSERT_BATCH_SIZE):
            total_upserted += _upsert_batch(db, batch[i : i + UPSERT_BATCH_SIZE])
        logger.info(f"Pinos gravados: {total_upserted}")

        with_contacts = [k for k, (site, email) in contacts.items() if site or email]
        sites = emails = dead = 0
        for i in range(0, len(with_contacts), CONTACTS_BATCH_SIZE):
            chunk = {k: contacts[k] for k in with_contacts[i : i + CONTACTS_BATCH_SIZE]}
            s, e, d = await save_contacts(db, chunk)
            sites, emails, dead = sites + s, emails + e, dead + d
        logger.info(f"  Contatos: +{sites} sites, +{emails} e-mails, {dead} sites fora do ar")
    finally:
        db.close()

    logger.info(f"=== ETL concluído: {total_upserted} registros inseridos/atualizados ===")
    return {"types_processed": len(OSM_TAGS), "records_upserted": total_upserted}
