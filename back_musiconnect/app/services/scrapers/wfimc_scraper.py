"""
Scraper da WFIMC — World Federation of International Music Competitions
(wfimc.org), a federação dos grandes concursos internacionais de música
(Queen Elisabeth, Van Cliburn, Paganini, ARD...).

A página de prazos (/member-competitions/application-deadlines) lista, num
cartão por concurso: prazo de inscrição (<time datetime>, às vezes um
intervalo — vale a data final), disciplinas, "Cidade - Nome", país e o link
da página do concurso. Os dados do cartão já vêm estruturados; a página do
concurso (lida só uma vez, quando ele aparece) traz o texto que o Gemini
usa para descrição, instrumentos e local.

O mesmo concurso pode aparecer duas vezes, com prazos de edições
diferentes: source_url = link + "#" + prazo. Concurso que também está no
Musical Chairs (mesmo prazo e mesmo nome) não entra de novo. Cartão que sai
da página sai do app.
"""

import logging
import re
from datetime import date, datetime, timezone
from typing import Optional

import httpx
from bs4 import BeautifulSoup

from app.models import Opportunity

logger = logging.getLogger("scrapers.wfimc")

_HEADERS = {"User-Agent": "MusiConnectBot/1.0 (+https://musiconnect.app.br)"}

PAGE_URL = "https://www.wfimc.org/member-competitions/application-deadlines"
SOURCE_NAME = "WFIMC"

# Palavras genéricas, fora da comparação de nomes entre fontes.
_GENERIC = {
    "international", "competition", "competitions", "concours", "concorso",
    "internacional", "concurso", "music", "musical", "musique", "premio",
    "prize", "festival", "young", "award",
}


def _words(text: str) -> set[str]:
    return set(re.findall(r"[a-zà-ÿ]{5,}", (text or "").lower())) - _GENERIC


def parse_page(html_text: str) -> list[dict]:
    """Cartões da página de prazos, já como oportunidade bruta."""
    soup = BeautifulSoup(html_text, "html.parser")
    records: dict[str, dict] = {}
    for card in soup.select(".views-row-inner"):
        link = card.select_one(".cmp-title a[href]")
        times = card.select("time[datetime]")
        if not link or not times:
            continue
        try:
            deadline = date.fromisoformat(times[-1]["datetime"][:10])
        except ValueError:
            continue
        full_name = link.get_text(" ", strip=True)
        city, _, name = full_name.partition(" - ")
        if not name:
            city, name = "", full_name
        disciplines = [d.get_text(" ", strip=True) for d in card.select(".cmp-discipline")]
        country_el = card.select_one(".cmp-title ~ p")
        country = country_el.get_text(" ", strip=True) if country_el else None
        url = link["href"].split("#")[0]
        source_url = f"{url}#{deadline.isoformat()}"
        records[source_url] = {
            "title":          name,
            "description":    f"{name} ({city}, {country}). Disciplinas: {', '.join(disciplines)}.",
            "raw_text":       (
                f"Título: {name}\n\nTipo: concurso internacional de música (membro da WFIMC)"
                f"\n\nLocal: {city}, {country}\n\nDisciplinas: {', '.join(disciplines)}"
                f"\n\nPrazo de inscrição: {deadline.strftime('%d/%m/%Y')}"
            ),
            "type":           "competicao",
            "instruments":    [],
            "institution":    name,
            "source_name":    SOURCE_NAME,
            "source_url":     source_url,
            "city":           city or None,
            "country":        country,
            "deadline":       deadline,
            "is_active":      True,
            "llm_confidence": 0.0,
            "_page":          url,
        }
    return list(records.values())


def _page_text(html_text: str) -> str:
    """Texto da página do concurso (sem menu nem rodapé), para o Gemini."""
    soup = BeautifulSoup(html_text, "html.parser")
    main = soup.select_one("main") or soup
    return re.sub(r"\s+", " ", main.get_text(" ", strip=True))[:2500]


def _is_duplicate(rec: dict, others: list[Opportunity]) -> bool:
    """Mesmo concurso já vindo de outra fonte: mesmo prazo e nome parecido."""
    words = _words(rec["title"])
    return any(
        o.deadline == rec["deadline"]
        and len(words & _words(f"{o.title} {o.institution or ''}")) >= 2
        for o in others
    )


def _save(records: list[dict], pages: dict[str, str], now: datetime) -> dict:
    from app.database import SessionLocal

    stats = {"new": 0, "duplicates": 0, "removed": 0}
    by_url = {r["source_url"]: r for r in records}
    db = SessionLocal()
    try:
        known = {
            o.source_url: o
            for o in db.query(Opportunity).filter(Opportunity.source_name == SOURCE_NAME)
        }
        others = (
            db.query(Opportunity)
            .filter(
                Opportunity.source_name != SOURCE_NAME,
                Opportunity.is_active.is_(True),
                Opportunity.type == "competicao",
            )
            .all()
        )
        for url, rec in by_url.items():
            if url in known:
                known[url].scraped_at = now
                continue
            if _is_duplicate(rec, others):
                stats["duplicates"] += 1
                continue
            data = {k: v for k, v in rec.items() if not k.startswith("_")}
            page = pages.get(rec["_page"])
            if page:
                data["raw_text"] += f"\n\nPágina do concurso:\n{page}"
            db.add(Opportunity(**data, scraped_at=now))
            stats["new"] += 1
        for url, opp in known.items():
            if url not in by_url and opp.is_active:
                opp.is_active = False
                stats["removed"] += 1
        db.commit()
    finally:
        db.close()
    return stats


def _known_urls() -> set[str]:
    from app.database import SessionLocal

    db = SessionLocal()
    try:
        rows = db.query(Opportunity.source_url).filter(Opportunity.source_name == SOURCE_NAME)
        return {url for (url,) in rows}
    finally:
        db.close()


async def sync_wfimc(now: Optional[datetime] = None) -> Optional[dict]:
    """Lê a página de prazos e atualiza os concursos da WFIMC. Devolve None
    se a página falhou ou veio sem cartões — nada é desativado nesse caso."""
    now = (now or datetime.now(timezone.utc)).replace(tzinfo=None)
    async with httpx.AsyncClient(headers=_HEADERS, follow_redirects=True) as client:
        try:
            response = await client.get(PAGE_URL, timeout=30)
            response.raise_for_status()
        except httpx.HTTPError as exc:
            logger.warning(f"[WFIMC] Falha ao ler a página de prazos: {exc}")
            return None
        records = parse_page(response.text)
        if not records:
            logger.warning("[WFIMC] Nenhum concurso na página (o layout mudou?) — nada alterado")
            return None
        # A página ainda mostra concursos cujo prazo acabou de passar.
        records = [r for r in records if r["deadline"] >= now.date()]

        # Página de cada concurso novo — só uma vez, como no Musical Chairs.
        known = _known_urls()
        pages: dict[str, str] = {}
        tried: set[str] = set()
        for rec in records:
            if rec["source_url"] in known or rec["_page"] in tried:
                continue
            tried.add(rec["_page"])
            try:
                page = await client.get(rec["_page"], timeout=30)
                page.raise_for_status()
                pages[rec["_page"]] = _page_text(page.text)
            except httpx.HTTPError:
                pass  # entra só com os dados do cartão

    stats = _save(records, pages, now)
    logger.info(
        f"[WFIMC] {len(records)} concursos na página, {stats['new']} novos, "
        f"{stats['duplicates']} já vindos de outra fonte, {stats['removed']} saíram da página"
    )
    return stats
