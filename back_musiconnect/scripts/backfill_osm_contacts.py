"""
Backfill de site e e-mail das instituições já gravadas no banco, a partir
das tags do OpenStreetMap (website/contact:website/url e
email/contact:email) — campos que o ETL passou a ler depois que essas
instituições já tinham sido importadas.

Consulta o Overpass só pelos osm_id que já existem (em lotes), em vez de
refazer a varredura global do ETL. Cobre também as instituições criadas
pelo resolvedor de oportunidades (source='pipeline'), que têm osm_id real
vindo do Nominatim.

Mesmas regras do ETL (ver app/services/osm_contacts.py): site só onde ainda
não há nenhum e só se o link responde; e-mail se tiver formato válido.

Uso:
    python -m scripts.backfill_osm_contacts             ← aplica e salva
    python -m scripts.backfill_osm_contacts --dry-run   ← só mostra o que mudaria
"""

import argparse
import asyncio
import logging
import os
import re
import sys

import httpx
from sqlalchemy import text

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.database import SessionLocal
from app.services.osm_contacts import extract_contacts, save_contacts
from app.services.overpass_etl import HEADERS, OVERPASS_MIRRORS

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
logging.getLogger("httpx").setLevel(logging.WARNING)
logger = logging.getLogger("scripts.backfill_osm_contacts")

BATCH_SIZE = 500

# Consulta por ID é leve — o servidor principal responde em ~1s. O ETL
# prioriza o kumi.systems (melhor para a varredura pesada por região), mas
# ele costuma travar com 504 por minutos; aqui ele fica por último.
_MIRRORS = sorted(OVERPASS_MIRRORS, key=lambda m: "overpass-api.de" not in m)
_OSM_ID_RE = re.compile(r"^(node|way|relation)_(\d+)$")


async def _fetch_tags(client: httpx.AsyncClient, ids: list[str]) -> dict[str, dict]:
    """osm_id → tags, para um lote de IDs no formato 'node_123'."""
    by_type: dict[str, list[str]] = {"node": [], "way": [], "relation": []}
    for osm_id in ids:
        kind, num = _OSM_ID_RE.match(osm_id).groups()
        by_type[kind].append(num)
    selectors = "".join(
        f"{kind}(id:{','.join(nums)});" for kind, nums in by_type.items() if nums
    )
    query = f"[out:json][timeout:120];({selectors});out tags;"

    for mirror in _MIRRORS:
        for wait in (10, 30, None):
            try:
                resp = await client.post(mirror, data={"data": query}, headers=HEADERS, timeout=90)
                resp.raise_for_status()
                return {
                    f"{e['type']}_{e['id']}": e.get("tags", {})
                    for e in resp.json().get("elements", [])
                }
            except Exception as exc:
                logger.warning(f"  Falha em {mirror}: {exc}")
                if wait is None:
                    break  # próximo mirror
                await asyncio.sleep(wait)
    raise RuntimeError("Todos os mirrors do Overpass falharam para este lote")


async def main(dry_run: bool) -> None:
    db = SessionLocal()
    try:
        ids = [
            row.osm_id
            for row in db.execute(text("SELECT osm_id FROM institutions ORDER BY osm_id"))
            if _OSM_ID_RE.match(row.osm_id)
        ]
        logger.info(f"{len(ids)} instituições com osm_id do OpenStreetMap")

        total_sites = total_emails = total_dead = 0
        batches = -(-len(ids) // BATCH_SIZE)
        async with httpx.AsyncClient() as client:
            for n, start in enumerate(range(0, len(ids), BATCH_SIZE), start=1):
                batch = ids[start:start + BATCH_SIZE]
                tags_by_id = await _fetch_tags(client, batch)
                contacts = {
                    osm_id: extract_contacts(tags_by_id.get(osm_id, {})) for osm_id in batch
                }
                sites, emails, dead = await save_contacts(db, contacts, dry_run=dry_run)
                total_sites += sites
                total_emails += emails
                total_dead += dead
                logger.info(
                    f"Lote {n}/{batches}: +{sites} sites, +{emails} e-mails, {dead} sites fora do ar "
                    f"| total: {total_sites} sites, {total_emails} e-mails, {total_dead} fora do ar"
                )
                await asyncio.sleep(2)  # gentileza com o servidor público do Overpass
    finally:
        db.close()

    verb = "seriam gravados" if dry_run else "gravados"
    logger.info(
        f"Concluído: {total_sites} sites e {total_emails} e-mails {verb}; "
        f"{total_dead} sites descartados por estarem fora do ar."
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--dry-run", action="store_true", help="só mostra o que mudaria")
    asyncio.run(main(parser.parse_args().dry_run))
