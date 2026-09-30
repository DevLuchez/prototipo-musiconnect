"""
Site e e-mail das instituições, a partir das tags do OpenStreetMap.

Ponto único usado pelos três caminhos que gravam contatos:
  - ETL noturno (overpass_etl.run_etl)
  - backfill das instituições já existentes (scripts/backfill_osm_contacts.py)
  - resolvedor de oportunidades, ao criar a instituição
    (institution_factory.get_or_create_institution, via extratags do Nominatim)

Regras (as mesmas nos três caminhos):
  - Site só é gravado se a instituição ainda não tem um (preserva o que veio
    do Wikidata/MusicBrainz) E se o link responde — o OSM tem muitos links
    antigos de domínios expirados (~20% numa amostra de 2026-09). Bloqueio de
    robô (401/403/429/503) conta como válido: abre normalmente no celular.
  - E-mail é gravado se tiver formato válido (não dá para testar sem enviar).
"""

import asyncio
import logging
import re
from typing import Optional

import httpx
from sqlalchemy import text
from sqlalchemy.orm import Session

logger = logging.getLogger("services.osm_contacts")

_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

# Respostas de sites que existem mas recusam robôs (Cloudflare, Instagram…)
_BLOCKED_BUT_ALIVE = {401, 403, 405, 429, 503}

_SITE_CHECK_CONCURRENCY = 20
_SITE_CHECK_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36"
    ),
}


def _first_value(value: Optional[str]) -> Optional[str]:
    """Tags do OSM podem ter vários valores separados por ';' — usa o primeiro."""
    if not value:
        return None
    first = value.split(";")[0].strip()
    return first or None


def extract_contacts(tags: dict) -> tuple[Optional[str], Optional[str]]:
    """(site, e-mail) a partir das tags do OSM, já normalizados.

    Aceita as variantes website / contact:website / url e email /
    contact:email. Site sem esquema ganha "https://"; e-mail inválido é
    descartado. Não testa se o site responde — isso é feito em save_contacts.
    """
    website = _first_value(
        tags.get("website") or tags.get("contact:website") or tags.get("url")
    )
    if website:
        website = website.replace(" ", "")
        if not re.match(r"^https?://", website, re.IGNORECASE):
            website = f"https://{website}"
        if "." not in website:
            website = None

    email = _first_value(tags.get("email") or tags.get("contact:email"))
    if email:
        email = re.sub(r"^mailto:", "", email, flags=re.IGNORECASE)
        if not _EMAIL_RE.match(email):
            email = None

    return website, email


async def _site_is_alive(client: httpx.AsyncClient, url: str) -> bool:
    try:
        # stream: só lê o cabeçalho da resposta, sem baixar a página inteira
        async with client.stream("GET", url, headers=_SITE_CHECK_HEADERS) as resp:
            return resp.status_code < 400 or resp.status_code in _BLOCKED_BUT_ALIVE
    except Exception:
        return False  # DNS inexistente, conexão recusada, timeout, SSL inválido


async def _alive_sites(urls: set[str]) -> set[str]:
    semaphore = asyncio.Semaphore(_SITE_CHECK_CONCURRENCY)
    async with httpx.AsyncClient(follow_redirects=True, timeout=15) as client:

        async def check(url: str) -> Optional[str]:
            async with semaphore:
                return url if await _site_is_alive(client, url) else None

        results = await asyncio.gather(*(check(u) for u in urls))
    return {u for u in results if u}


async def save_contacts(
    db: Session,
    contacts: dict[str, tuple[Optional[str], Optional[str]]],
    *,
    dry_run: bool = False,
) -> tuple[int, int, int]:
    """Grava site/e-mail do OSM nas instituições (osm_id → (site, e-mail)).

    Retorna (sites gravados, e-mails gravados, sites descartados por estarem
    fora do ar). Só testa os sites das instituições que ainda não têm um.
    """
    contacts = {k: v for k, v in contacts.items() if v[0] or v[1]}
    if not contacts:
        return 0, 0, 0

    current = {
        row.osm_id: (row.website, row.email)
        for row in db.execute(
            text("SELECT osm_id, website, email FROM institutions WHERE osm_id = ANY(:ids)"),
            {"ids": list(contacts)},
        )
    }
    candidate_sites = {
        site for osm_id, (site, _) in contacts.items()
        if site and osm_id in current and not current[osm_id][0]
    }
    alive = await _alive_sites(candidate_sites)

    sites = emails = 0
    for osm_id, (site, email) in contacts.items():
        if osm_id not in current:
            continue
        old_site, old_email = current[osm_id]
        new_site = site if (site in alive and not old_site) else None
        new_email = email if (email and email != old_email) else None
        if not (new_site or new_email):
            continue
        sites += bool(new_site)
        emails += bool(new_email)
        if dry_run:
            logger.info(f"  {osm_id}: site={new_site or '-'} email={new_email or '-'}")
            continue
        db.execute(
            text("""
                UPDATE institutions SET
                    website = COALESCE(website, :website),
                    email   = COALESCE(:email, email)
                WHERE osm_id = :osm_id
            """),
            {"osm_id": osm_id, "website": new_site, "email": new_email},
        )
    if not dry_run:
        db.commit()
    return sites, emails, len(candidate_sites) - len(alive)
