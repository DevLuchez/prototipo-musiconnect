"""
Scraper do Musical Chairs — musicalchairs.info

Estratégia em duas etapas:
  1. Descoberta — o RSS por instrumento (https://www.musicalchairs.info/rss/en/{instrumento})
     lista as oportunidades recentes, mas traz só título + um resumo solto
     (sem campos de instituição, local ou prazo).
  2. Detalhe — para cada oportunidade nova (source_url ainda não visto no banco),
     a página individual é visitada uma única vez para extrair os campos
     estruturados que o RSS não tem: instituição, local e prazo de inscrição
     (classes CSS estáveis: post_item_name/post_item_location/post_item_closingdate).
     Só oportunidades novas são buscadas — as já conhecidas não são revisitadas
     a cada execução, para não sobrecarregar o site.

Tipos inferidos pela URL da vaga — allowlist: só os segmentos abaixo são
aceitos, qualquer outro (/sales/, /stolen/, ou qualquer tipo novo que o
site venha a criar) é descartado por padrão. Evita repetir o que
aconteceu com /stolen/ (furto de instrumento), que caiu num padrão antigo
"desconhecido → edital" e virou oportunidade por engano, com um layout de
página totalmente diferente do esperado.
  /jobs/{id}          → 'audicao'
  /competitions/{id}  → 'competicao'
  /courses/{id}       → 'curso'
  /degree-courses/{id} → 'curso' (dias abertos/divulgação de programas de
                          graduação — mais próximo de "curso" entre as
                          categorias existentes, mesmo não sendo uma
                          masterclass de curta duração como os demais)
  /teaching-jobs/{id} → 'emprego'
  /admin-jobs/{id}    → 'emprego'
"""

import asyncio
import hashlib
import logging
import xml.etree.ElementTree as ET
from datetime import date, datetime, timezone
from html.parser import HTMLParser
from typing import Optional
from urllib.parse import urlparse

import httpx
from bs4 import BeautifulSoup

logger = logging.getLogger("scrapers.musical_chairs")

# Máximo de páginas de detalhe buscadas simultaneamente — cortesia com o site.
_DETAIL_CONCURRENCY = 5

# ── Instrumentos a consultar ──────────────────────────────────────────────────
# Padrão: https://www.musicalchairs.info/rss/en/{slug}
INSTRUMENTS = [
    # Cordas
    "violin", "viola", "cello", "double-bass", "harp",
    # Madeiras
    "flute", "oboe", "clarinet", "bassoon",
    # Metais
    "horn", "trumpet", "trombone", "tuba",
    # Teclas
    "piano", "organ",
    # Outros
    "guitar", "percussion", "voice", "conducting", "composition",
    # Feed geral de performance jobs (sem instrumento específico)
    # NB: teste com musicalchairs.info/rss/en/all — se 404, remover
]

RSS_BASE = "https://www.musicalchairs.info/rss/en/{instrument}"

# Tipos por segmento de URL
_TYPE_MAP = {
    "/jobs/":          "audicao",
    "/competitions/":  "competicao",
    "/courses/":       "curso",
    "/degree-courses/": "curso",
    "/teaching-jobs/": "emprego",
    "/admin-jobs/":    "emprego",
}
def _classify_type(url: str) -> Optional[str]:
    """
    Retorna o tipo de oportunidade com base no path da URL, ou None se o
    segmento não for reconhecido (allowlist — ver docstring do módulo).
    """
    path = urlparse(url).path
    for segment, opp_type in _TYPE_MAP.items():
        if segment in path:
            return opp_type
    logger.debug(f"[MC] Segmento de URL não reconhecido, descartando: {path}")
    return None


def _guid_to_id(url: str) -> str:
    """Hash curto do GUID para uso como source_url normalizado."""
    return hashlib.md5(url.encode()).hexdigest()[:12]


def _strip_html(html_text: str) -> str:
    """Remove tags HTML, retorna texto limpo para o LLM processar."""
    class _Stripper(HTMLParser):
        def __init__(self):
            super().__init__()
            self._parts: list[str] = []
        def handle_data(self, d: str):
            s = d.strip()
            if s:
                self._parts.append(s)
        def get_text(self) -> str:
            return " ".join(self._parts)

    stripper = _Stripper()
    stripper.feed(html_text)
    return stripper.get_text()


def _parse_feed(xml_text: str, instrument: str) -> list[dict]:
    """Parseia um RSS feed do Musical Chairs e retorna lista de registros brutos."""
    records = []
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError as e:
        logger.warning(f"[MC] Erro ao parsear XML ({instrument}): {e}")
        return records

    channel = root.find("channel")
    if channel is None:
        return records

    for item in channel.findall("item"):
        title = (item.findtext("title") or "").strip()
        description = (item.findtext("description") or "").strip()
        pub_date_raw = (item.findtext("pubDate") or "").strip()
        link = (item.findtext("link") or "").strip()
        guid = (item.findtext("guid") or link).strip()

        if not link or not title:
            continue

        opp_type = _classify_type(link)
        if opp_type is None:
            # Fora da allowlist (venda/furto de instrumento, ou tipo desconhecido)
            continue

        # Normaliza a URL de origem (remove parâmetros ?ref=)
        source_url = link.split("?")[0]

        # Mapeia instrumento consultado como lista
        instrument_pretty = instrument.replace("-", " ").title()

        # Texto limpo para o LLM (sem HTML)
        desc_clean = _strip_html(description) if description else ""

        records.append({
            "title":        title,
            "description":  desc_clean,
            "raw_text":     f"Título: {title}\n\nDescrição:\n{desc_clean}",
            "type":         opp_type,
            "instruments":  [instrument_pretty],
            "source_name":  "Musical Chairs",
            "source_url":   source_url,
            "institution":  None,   # preenchido na Etapa 2 (página de detalhe), se nova
            "deadline":     None,   # idem
            "is_active":    True,
            "llm_confidence": 0.0,  # será preenchido pelo LLM enricher
            "scraped_at":   datetime.now(timezone.utc),
        })

    return records


async def _fetch_feed(client: httpx.AsyncClient, instrument: str) -> list[dict]:
    """Faz GET do RSS de um instrumento e parseia os resultados."""
    url = RSS_BASE.format(instrument=instrument)
    try:
        response = await client.get(url, timeout=20)
        if response.status_code == 404:
            logger.debug(f"[MC] Feed não encontrado: {instrument}")
            return []
        response.raise_for_status()
        return _parse_feed(response.text, instrument)
    except httpx.HTTPError as e:
        logger.warning(f"[MC] Erro HTTP ao buscar {instrument}: {e}")
        return []


def _merge_and_deduplicate(all_records: list[list[dict]]) -> list[dict]:
    """
    Consolida listas de vários instrumentos em uma lista única,
    sem duplicatas (por source_url). Quando a mesma vaga aparece
    em feeds de instrumentos diferentes, unifica a lista de instrumentos.
    """
    merged: dict[str, dict] = {}
    for records in all_records:
        for rec in records:
            key = rec["source_url"]
            if key not in merged:
                merged[key] = rec
            else:
                # Adiciona instrumentos que ainda não estão na lista
                existing_instruments = set(merged[key]["instruments"])
                for instr in rec["instruments"]:
                    if instr not in existing_instruments:
                        merged[key]["instruments"].append(instr)
    return list(merged.values())


def _parse_site_date(text: str) -> Optional[date]:
    """Converte datas do site ('01 Dec 2026') para objeto date."""
    text = " ".join(text.split())
    try:
        return datetime.strptime(text, "%d %b %Y").date()
    except ValueError:
        return None


def _parse_detail_page(html_text: str) -> dict:
    """
    Extrai os campos estruturados da página individual do anúncio
    (ausentes no resumo RSS): instituição, local e prazo de inscrição.

    Instituição só existe estruturalmente em páginas de vaga/emprego
    (jobs, teaching-jobs, admin-jobs): lá, post_item_name embrulha um <h2>
    e post_item_info (o <h1>) é o título. Em competições/cursos é o
    inverso — post_item_name é o <h1> (título) e não há instituição
    identificada na página; nesse caso retornamos None e deixamos o LLM
    tentar como fallback best-effort.
    """
    soup = BeautifulSoup(html_text, "html.parser")
    result: dict = {"institution": None, "location_raw": None, "deadline": None, "description": None}

    location_div = soup.find("div", class_="post_item_location")
    if location_div:
        result["location_raw"] = location_div.get_text(strip=True) or None

    name_div = soup.find("div", class_="post_item_name")
    if name_div and name_div.find("h2"):
        institution = name_div.get_text(strip=True)
        result["institution"] = institution or None

    closing_div = soup.find("div", class_="post_item_closingdate")
    if closing_div:
        text = closing_div.get_text(" ", strip=True).replace("Closing date:", "").strip()
        result["deadline"] = _parse_site_date(text)

    desc_div = soup.find("div", class_="post_item_desc")
    if desc_div:
        result["description"] = desc_div.get_text(" ", strip=True) or None

    return result


async def _fetch_detail(
    client: httpx.AsyncClient, url: str, sem: asyncio.Semaphore
) -> Optional[dict]:
    """
    Busca e parseia a página individual de uma oportunidade.

    Um 404 significa que a fonte removeu o anúncio (vaga preenchida,
    competição/curso encerrado) — é diferente de uma falha transitória de
    rede, então é sinalizado explicitamente via `not_found` para quem
    chamou decidir o que fazer (descartar se for registro novo, desativar
    se já existir no banco).
    """
    async with sem:
        try:
            response = await client.get(url, timeout=20)
            if response.status_code == 404:
                return {"not_found": True}
            response.raise_for_status()
            return _parse_detail_page(response.text)
        except httpx.HTTPError as e:
            logger.warning(f"[MC] Erro ao buscar página de detalhe {url}: {e}")
            return None


def _fetch_known_source_urls(urls: list[str]) -> set[str]:
    """
    Retorna quais dos source_urls informados já existem no banco.
    Usado para buscar a página de detalhe apenas de oportunidades novas —
    as já conhecidas não precisam ser revisitadas a cada execução.
    """
    if not urls:
        return set()

    from app.database import SessionLocal
    from app.models import Opportunity

    db = SessionLocal()
    try:
        rows = (
            db.query(Opportunity.source_url)
            .filter(Opportunity.source_url.in_(urls))
            .all()
        )
        return {row[0] for row in rows}
    finally:
        db.close()


async def _enrich_with_details(
    client: httpx.AsyncClient, records: list[dict]
) -> set[str]:
    """
    Para cada registro cujo source_url ainda não existe no banco, busca a
    página individual e preenche institution/deadline/description/raw_text
    com os dados estruturados de lá (muito mais confiáveis que o resumo RSS).
    Modifica `records` in-place.

    Retorna o conjunto de source_urls que já vieram mortas (404) — o anúncio
    foi removido entre o RSS listar e a página de detalhe ser buscada. Essas
    nunca chegam a ser gravadas como oportunidade (quem chama deve excluí-las
    da lista antes do upsert).
    """
    all_urls = [r["source_url"] for r in records]
    known = _fetch_known_source_urls(all_urls)
    new_records = [r for r in records if r["source_url"] not in known]

    if not new_records:
        return set()

    logger.info(f"[MC] {len(new_records)} oportunidades novas — buscando página de detalhe...")

    sem = asyncio.Semaphore(_DETAIL_CONCURRENCY)
    details = await asyncio.gather(
        *(_fetch_detail(client, r["source_url"], sem) for r in new_records)
    )

    dead_urls: set[str] = set()

    for rec, detail in zip(new_records, details):
        if not detail:
            continue

        if detail.get("not_found"):
            logger.info(f"[MC] Anúncio já removido da fonte, descartando: {rec['source_url']}")
            dead_urls.add(rec["source_url"])
            continue

        if detail.get("institution"):
            rec["institution"] = detail["institution"]
        if detail.get("deadline"):
            rec["deadline"] = detail["deadline"]

        full_desc = detail.get("description") or rec["description"]
        rec["description"] = full_desc
        rec["raw_text"] = (
            f"Título: {rec['title']}\n\n"
            f"Local: {detail.get('location_raw') or 'não informado'}\n\n"
            f"Descrição:\n{full_desc}"
        )

    return dead_urls


async def scrape_musical_chairs() -> list[dict]:
    """
    Busca oportunidades do Musical Chairs.

    Etapa 1 — RSS por instrumento: descobre quais oportunidades existem.
    Etapa 2 — página de detalhe (só para oportunidades novas): preenche
    instituição, local e prazo com os campos estruturados do site.

    Retorna lista de dicts prontos para upsert na tabela opportunities
    (o restante do enrichment — título traduzido, tipo, nível, etc. —
    continua a cargo do llm_enricher).
    """
    logger.info("[MC] Iniciando scraping do Musical Chairs...")

    async with httpx.AsyncClient(
        headers={
            "User-Agent": (
                "Mozilla/5.0 (compatible; MusiConnectBot/1.0; "
                "+https://musiconnect.app)"
            )
        }
    ) as client:
        tasks = [_fetch_feed(client, instr) for instr in INSTRUMENTS]
        results = await asyncio.gather(*tasks)

        all_records = _merge_and_deduplicate(list(results))

        logger.info(
            f"[MC] Encontradas {len(all_records)} oportunidades únicas "
            f"em {len(INSTRUMENTS)} feeds de instrumentos."
        )

        dead_urls = await _enrich_with_details(client, all_records)

    if dead_urls:
        all_records = [r for r in all_records if r["source_url"] not in dead_urls]

    return all_records
