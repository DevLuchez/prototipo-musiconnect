"""
Scraper da Revista CONCERTO — página "Cursos e outros eventos"
(concerto.com.br), a melhor lista de oportunidades de música no Brasil:
concursos, editais de orquestra, academias, processos seletivos, festivais,
master classes. É uma página única, atualizada pela redação, com um
parágrafo por item, em seções:

  SÃO PAULO      — itens da capital paulista
  BRASIL         — "Cidade, UF / NOME . texto"
  INTERNACIONAL  — "CIDADE, PAÍS / NOME . texto"

No topo, um bloco com os itens recentes ("[NOVO]") repete o que está na
lista completa — fica a última ocorrência de cada um (a da lista completa).

A página mistura oportunidades com temporadas de concertos, assinaturas e
exposições: os casos óbvios são descartados aqui; o resto o Gemini decide
(`is_open_call`).

source_url = endereço da página + "#" + o nome do item: o link do app leva à
CONCERTO (crédito à revista) e cada item tem um endereço próprio. Item que
sai da página sai do app; item cujo texto mudou volta ao Gemini.
"""

import logging
import re
import unicodedata
from datetime import datetime, timezone
from typing import Optional

import httpx
from bs4 import BeautifulSoup

from app.models import Opportunity

logger = logging.getLogger("scrapers.concerto")

_HEADERS = {"User-Agent": "MusiConnectBot/1.0 (+https://musiconnect.app.br)"}

PAGE_URL = "https://www.concerto.com.br/noticias/brasil/cursos-e-outros-eventos"
SOURCE_NAME = "Revista CONCERTO"

_SECTIONS = {"SÃO PAULO", "BRASIL", "INTERNACIONAL"}

# Itens da lista que não são oportunidade para músicos (para o público).
_NOT_OPPORTUNITY = re.compile(
    r"temporada \d{4}|assinatura|exposi[çc][ãa]o|marketplace", re.IGNORECASE
)

_TAGS = re.compile(r"\[(NOVO|ON-LINE)\]\s*", re.IGNORECASE)


def _slug(text: str) -> str:
    """Identificador do item: as 6 primeiras palavras do nome — os dois
    blocos da página às vezes escrevem o fim do nome de jeitos diferentes
    ("Franz Liszt, 140 anos" / "FRANZ LISZT (1811-1886), 140 anos")."""
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    words = re.findall(r"[a-z0-9]+", text.lower())
    return "-".join(words[:6])


def _split_item(text: str, section: str) -> tuple[str, Optional[str]]:
    """(nome do item, local informado pela revista)."""
    text = _TAGS.sub("", text).strip()
    place = None
    if section != "SÃO PAULO" and " / " in text.split(" . ")[0]:
        place, text = text.split(" / ", 1)
    elif section == "SÃO PAULO":
        place = "São Paulo, SP"
        if " / " in text.split(" . ")[0]:  # ex: "Santo André, SP / PESQUISA..."
            place, text = text.split(" / ", 1)
    name = text.split(" . ")[0].strip()
    return name, (place.strip() if place else None)


def parse_page(html_text: str) -> list[dict]:
    """Itens da página (sem repetidos), já como oportunidade bruta."""
    soup = BeautifulSoup(html_text, "html.parser")
    body = soup.select_one("article .field--type-text-with-summary")
    if body is None:
        return []

    section = None
    items: dict[str, dict] = {}
    for p in body.find_all("p"):
        text = re.sub(r"\s+", " ", p.get_text(" ", strip=True))
        if not text or text.startswith("Última atualização"):
            continue
        if text.upper() in _SECTIONS:
            section = text.upper()
            continue
        if section is None:
            continue
        name, place = _split_item(text, section)
        if not name or _NOT_OPPORTUNITY.search(name) or _NOT_OPPORTUNITY.search(text[:200]):
            continue
        links = [a["href"] for a in p.find_all("a", href=True) if a["href"].startswith("http")]
        key = _slug(name)
        clean = _TAGS.sub("", text)
        items[key] = {  # a última ocorrência (lista completa) prevalece
            "title":          name,  # o Gemini reescreve (título em português)
            "description":    clean[:500],
            "raw_text":       (
                f"Título: {name}\n\nLocal (segundo a revista): "
                f"{place or ('Internacional' if section == 'INTERNACIONAL' else 'não informado')}"
                f"\n\nTexto da Revista CONCERTO:\n{clean}"
                + (f"\n\nLinks: {' '.join(links[:3])}" if links else "")
            ),
            "type":           None,  # o Gemini decide
            "instruments":    [],
            "source_name":    SOURCE_NAME,
            "source_url":     f"{PAGE_URL}#{key}",
            "country":        None if section == "INTERNACIONAL" else "Brasil",
            "deadline":       None,
            "is_active":      True,
            "llm_confidence": 0.0,
        }
    return list(items.values())


def _save(records: list[dict], now: datetime) -> dict:
    """Novos entram; os de texto mudado voltam ao Gemini; os que saíram da
    página saem do app."""
    from app.database import SessionLocal

    stats = {"new": 0, "changed": 0, "removed": 0}
    by_url = {r["source_url"]: r for r in records}
    db = SessionLocal()
    try:
        known = {
            o.source_url: o
            for o in db.query(Opportunity).filter(Opportunity.source_name == SOURCE_NAME)
        }
        for url, rec in by_url.items():
            opp = known.get(url)
            if opp is None:
                db.add(Opportunity(**rec, scraped_at=now))
                stats["new"] += 1
                continue
            if opp.raw_text != rec["raw_text"]:
                # Continua visível com os dados antigos até o Gemini refazer.
                opp.raw_text = rec["raw_text"]
                opp.enriched_at = None
                stats["changed"] += 1
            opp.scraped_at = now
        for url, opp in known.items():
            if url not in by_url and opp.is_active:
                opp.is_active = False
                stats["removed"] += 1
        db.commit()
    finally:
        db.close()
    return stats


async def sync_concerto(now: Optional[datetime] = None) -> Optional[dict]:
    """Lê a página e atualiza as oportunidades da CONCERTO. Devolve None se
    a página falhou ou veio sem itens (layout mudou?) — nada é desativado
    nesse caso."""
    now = (now or datetime.now(timezone.utc)).replace(tzinfo=None)
    try:
        async with httpx.AsyncClient(headers=_HEADERS, follow_redirects=True) as client:
            response = await client.get(PAGE_URL, timeout=30)
            response.raise_for_status()
    except httpx.HTTPError as exc:
        logger.warning(f"[CONCERTO] Falha ao ler a página: {exc}")
        return None
    records = parse_page(response.text)
    if not records:
        logger.warning("[CONCERTO] Nenhum item na página (o layout mudou?) — nada alterado")
        return None
    stats = _save(records, now)
    logger.info(
        f"[CONCERTO] {len(records)} itens na página, {stats['new']} novos, "
        f"{stats['changed']} com texto mudado, {stats['removed']} saíram da página"
    )
    return stats
