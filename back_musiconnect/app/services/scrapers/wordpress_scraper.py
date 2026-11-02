"""
Scraper de sites em WordPress de instituições da região da SCAR — a
cliente inicial do MusiConnect — pela API pública do WordPress
(/wp-json/wp/v2/posts), sem raspar HTML.

Fontes:
  SCAR   — scar.art.br (Sociedade Cultura Artística, Jaraguá do Sul):
           audições da Orquestra Jovem e da Filarmônica de Jaraguá,
           inscrições em projetos (Música Para Todos, Big Band...).
  FEMUSC — femusc.com.br (Festival de Música de Santa Catarina, Jaraguá
           do Sul): a chamada anual de alunos.

Os sites publicam sobretudo notícias (apresentações, prêmios, fotos). Por
isso:
  1. Só os posts recentes (POST_WINDOW) entram.
  2. Só os que parecem chamada (inscrições, audição, seleção, vagas, bolsa,
     edital...) viram oportunidade bruta — o resto nem chega ao Gemini.
  3. O Gemini confirma se é mesmo uma chamada aberta a músicos
     (`is_open_call`) e extrai tipo, instrumentos e prazo; notícia ou
     chamada de outra área (dança, teatro) é desativada por ele.

Post sem prazo some do app depois de NO_DEADLINE_MAX_AGE; post apagado do
site (404) é desativado — mesma regra do Musical Chairs.

Páginas fixas do FEMUSC (02/11/2026): o FEMUSC publica as chamadas nas
páginas de cada programa (FEMUSC Jovem, Concurso Scheherazade, vagas
remanescentes), não em notícias. As páginas que parecem chamada entram;
voltam ao Gemini quando o texto muda (a edição seguinte entra sozinha) e
saem se a página sumir ou deixar de parecer chamada. Sem prazo, saem
NO_DEADLINE_MAX_AGE depois da última atualização da página (a entrada da
oportunidade é a data dessa atualização) — página abandonada não fica no
app para sempre.

Cursos de música da SCAR (decisão da Laura, 01/11/2026): os cursos
regulares da escola (Cordas, Piano, Metais...) entram como "curso" sem
prazo — a matrícula é contínua. Ficam no app enquanto estiverem na página
de cursos de música do site; são conferidos uma vez por mês
(COURSES_REFRESH) e só voltam ao Gemini se o texto da página mudou (preço,
professor...).
"""

import asyncio
import logging
import re
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from html import unescape
from typing import Optional

import httpx
from bs4 import BeautifulSoup

from app.models import Institution, Opportunity

logger = logging.getLogger("scrapers.wordpress")

_HEADERS = {"User-Agent": "MusiConnectBot/1.0 (+https://musiconnect.app.br)"}

# Posts mais antigos que isso não são coletados (as chamadas costumam ficar
# abertas por poucas semanas).
POST_WINDOW = timedelta(days=45)

# Oportunidade sem prazo informado sai do app depois disso (contado da
# publicação do post) — post de blog não avisa quando a chamada fecha.
NO_DEADLINE_MAX_AGE = timedelta(days=45)

# Palavras que indicam uma chamada (título ou começo do texto).
_CALL_PATTERN = re.compile(
    r"inscri|audi[çc]|sele[çc]|vagas?\b|matr[íi]cula|bolsa|edital|"
    r"chamada|convoca|processo seletivo|oficina|masterclass|workshop|concurso",
    re.IGNORECASE,
)

# Posts que citam essas palavras mas não são chamada: álbuns de fotos,
# convocação de assembleia da associação, balanço de inscrições.
_NOT_CALL_TITLE = re.compile(r"\[fotos\]|assembleia|recorde", re.IGNORECASE)

# Cursos de música da SCAR: a página que lista os cursos e o intervalo
# entre as conferências.
SCAR_MUSIC_COURSES_PAGE = "https://scar.art.br/cursos-musica/"
_COURSE_URL_PREFIX = "https://scar.art.br/cursos/"
COURSES_REFRESH = timedelta(days=30)

# Máximo de páginas (de 50 posts) lidas por fonte em cada execução.
_MAX_PAGES = 4


@dataclass(frozen=True)
class WordPressSource:
    name: str               # source_name das oportunidades
    base_url: str           # sem barra no fim
    city: str
    state: str
    institution: str
    # Pino do mapa da instituição (osm_id), quando ela já está no mapa.
    institution_id: Optional[str] = None
    # Ler também as páginas fixas do site (onde ficam as chamadas).
    read_pages: bool = False


SOURCES = [
    WordPressSource(
        name="SCAR",
        base_url="https://scar.art.br",
        city="Jaraguá do Sul",
        state="SC",
        institution="SCAR – Sociedade Cultura Artística",
        institution_id="way_256649111",
    ),
    WordPressSource(
        name="FEMUSC",
        base_url="https://femusc.com.br",
        city="Jaraguá do Sul",
        state="SC",
        institution="FEMUSC – Festival de Música de Santa Catarina",
        read_pages=True,
    ),
]

# Marca o link das oportunidades que vêm de páginas fixas (o app abre a
# página normalmente; o "#" só as distingue das notícias).
_PAGE_MARK = "#pagina"

# Páginas institucionais, nunca chamada.
_SKIP_PAGE_SLUGS = {
    "contato", "politica-de-privacidade", "galeria-de-fotos", "alojamentos",
    "partituras", "locais-de-apresentacao", "noticias", "como-apoiar",
    "teste-pt", "sobre-o-festival", "programacao", "cursos", "quadro-de-avisos",
    "selecionados", "matriculas",
}


def _text(html_text: str) -> str:
    soup = BeautifulSoup(html_text or "", "html.parser")
    # Páginas de construtor visual trazem CSS dentro do conteúdo.
    for tag in soup(["style", "script"]):
        tag.decompose()
    return re.sub(r"\s+", " ", unescape(soup.get_text(" "))).strip()


def looks_like_call(title: str, content: str) -> bool:
    """O post anuncia algo em que dá para se inscrever? (filtro barato,
    antes do Gemini)."""
    if _NOT_CALL_TITLE.search(title):
        return False
    return bool(_CALL_PATTERN.search(f"{title} {content[:600]}"))


def _published_at(post: dict) -> Optional[datetime]:
    """Data de publicação em UTC, sem fuso (como as colunas do banco)."""
    try:
        return datetime.fromisoformat(post.get("date_gmt") or "")
    except ValueError:
        return None


def _parse_posts(posts: list[dict], source: WordPressSource) -> list[dict]:
    records = []
    for post in posts:
        # Site com tradução (FEMUSC): só a versão em português — as outras
        # repetiriam a mesma chamada.
        if post.get("lang") not in (None, "pt"):
            continue
        link = (post.get("link") or "").strip()
        title = _text((post.get("title") or {}).get("rendered", ""))
        content = _text((post.get("content") or {}).get("rendered", ""))
        if not link or not title or not looks_like_call(title, content):
            continue
        published = (post.get("date") or "")[:10]
        record = {
            "title":          title,
            "description":    content[:500],
            # A data de publicação ajuda o Gemini a saber o ano de prazos
            # como "até 20 de julho".
            "raw_text":       (
                f"Título: {title}\n\nPublicado em: {published}\n\n"
                f"Local: {source.city}, {source.state}, Brasil\n\nTexto:\n{content}"
            ),
            "type":           None,  # o Gemini decide (audição, curso...)
            "instruments":    [],
            "source_name":    source.name,
            "source_url":     link,
            "institution":    source.institution,
            "institution_id": source.institution_id,
            "country":        "Brasil",
            "state":          source.state,
            "city":           source.city,
            "deadline":       None,
            "is_active":      True,
            "llm_confidence": 0.0,  # preenchido pelo LLM enricher
            "scraped_at":     datetime.now(timezone.utc),
        }
        # Entrada = publicação: post antigo não vira "nova oportunidade"
        # (Início, notificações) e a validade sem prazo conta dali.
        published_at = _published_at(post)
        if published_at:
            record["created_at"] = published_at
        records.append(record)
    return records


async def _fetch_posts(client: httpx.AsyncClient, source: WordPressSource,
                       now: datetime) -> list[dict]:
    after = (now - POST_WINDOW).strftime("%Y-%m-%dT%H:%M:%S")
    posts: list[dict] = []
    page = 1
    try:
        while page <= _MAX_PAGES:
            response = await client.get(
                f"{source.base_url}/wp-json/wp/v2/posts",
                params={"after": after, "per_page": 50, "page": page,
                        "_fields": "date,date_gmt,link,title,content,lang"},
                timeout=30,
            )
            response.raise_for_status()
            posts.extend(response.json())
            if page >= int(response.headers.get("X-WP-TotalPages", "1")):
                break
            page += 1
    except (httpx.HTTPError, ValueError) as exc:
        logger.warning(f"[WP] {source.name}: falha ao buscar os posts: {exc}")
    return posts


async def scrape_wordpress_sources(now: Optional[datetime] = None) -> list[dict]:
    """Chamadas recentes de todas as fontes (SCAR, FEMUSC)."""
    now = now or datetime.now(timezone.utc)
    async with httpx.AsyncClient(headers=_HEADERS, follow_redirects=True) as client:
        results = await asyncio.gather(*(_fetch_posts(client, s, now) for s in SOURCES))
    records = []
    for source, posts in zip(SOURCES, results):
        found = _parse_posts(posts, source)
        pin = _pin_if_on_map(source.institution_id)
        for rec in found:
            rec["institution_id"] = pin
        logger.info(f"[WP] {source.name}: {len(posts)} posts recentes, {len(found)} parecem chamada")
        records.extend(found)
    return records


def _pin_if_on_map(osm_id: Optional[str]) -> Optional[str]:
    """O pino só é usado se existir no mapa (num banco novo, ou se o ETL o
    tirar, gravar o vínculo falharia) — sem ele, a etapa de resolução
    procura a instituição pelo nome."""
    if not osm_id:
        return None
    from app.database import SessionLocal

    db = SessionLocal()
    try:
        return osm_id if db.get(Institution, osm_id) else None
    finally:
        db.close()


# ── Cursos de música da SCAR ─────────────────────────────────────────────

def _course_links(html_text: str) -> list[str]:
    """Links dos cursos na página de cursos de música (sem repetir)."""
    soup = BeautifulSoup(html_text, "html.parser")
    main = soup.select_one("main") or soup
    links: list[str] = []
    for a in main.select(f'a[href^="{_COURSE_URL_PREFIX}"]'):
        href = a["href"].split("#")[0]
        if href not in links:
            links.append(href)
    return links


def _course_text(html_text: str) -> str:
    """Texto da página do curso, sem o menu e o rodapé."""
    soup = BeautifulSoup(html_text, "html.parser")
    main = soup.select_one("main") or soup
    text = re.sub(r"\s+", " ", main.get_text(" ", strip=True))
    return text.split("CURSOS POR CATEGORIA")[0].strip()


def _course_name(html_text: str) -> str:
    """Nome do curso (título da página), ex: "Cordas"."""
    soup = BeautifulSoup(html_text, "html.parser")
    heading = (soup.select_one("main") or soup).find(["h1", "h2"])
    return heading.get_text(" ", strip=True) if heading else ""


def _course_raw_text(name: str, text: str) -> str:
    # O nome no título deixa os 8 cursos com títulos no mesmo padrão.
    title = f'Use como título: "Curso de {name} na SCAR".\n\n' if name else ""
    return (
        "Curso regular de música da SCAR – Sociedade Cultura Artística, em "
        "Jaraguá do Sul (SC). Matrícula contínua, sem data de encerramento "
        "(não há prazo de inscrição).\n\n"
        f"{title}Local: Jaraguá do Sul, SC, Brasil\n\nPágina do curso:\n{text}"
    )


def _known_courses() -> dict[str, tuple[Optional[str], Optional[datetime]]]:
    from app.database import SessionLocal

    db = SessionLocal()
    try:
        rows = db.query(Opportunity).filter(
            Opportunity.source_url.like(f"{_COURSE_URL_PREFIX}%")
        ).all()
        return {o.source_url: (o.raw_text, o.scraped_at) for o in rows}
    finally:
        db.close()


def _sync_static(records: dict[str, dict], url_filter, now: datetime) -> dict:
    """Grava páginas que não são notícia (cursos, páginas fixas): novas
    entram, as de texto mudado voltam ao Gemini (continuam visíveis com os
    dados antigos até ele refazer), as que saíram são desativadas.
    `url_filter` escolhe, no banco, as oportunidades desse grupo."""
    from app.database import SessionLocal

    stats = {"new": 0, "changed": 0, "removed": 0}
    db = SessionLocal()
    try:
        known = {o.source_url: o for o in db.query(Opportunity).filter(url_filter)}
        for url, record in records.items():
            opp = known.get(url)
            if opp is None:
                db.add(Opportunity(**record, source_url=url, scraped_at=now))
                stats["new"] += 1
                continue
            if opp.raw_text != record["raw_text"]:
                opp.raw_text = record["raw_text"]
                opp.enriched_at = None
                # Texto novo (ex: a edição seguinte): volta ao app e a
                # entrada passa a ser a da atualização.
                opp.is_active = True
                if record.get("created_at"):
                    opp.created_at = record["created_at"]
                stats["changed"] += 1
            opp.scraped_at = now
        for url, opp in known.items():
            if url not in records and opp.is_active:
                opp.is_active = False
                stats["removed"] += 1
        db.commit()
    finally:
        db.close()
    return stats


def _save_courses(pages: dict[str, tuple[str, str]], now: datetime) -> dict:
    """Grava os cursos lidos (ver _sync_static)."""
    pin = _pin_if_on_map(SOURCES[0].institution_id)
    records = {
        url: dict(
            title=f"Curso de {name} na SCAR" if name else url,
            description=text[:500], raw_text=_course_raw_text(name, text),
            type="curso", instruments=[], source_name="SCAR",
            institution="SCAR – Sociedade Cultura Artística",
            institution_id=pin, country="Brasil", state="SC",
            city="Jaraguá do Sul", is_active=True, llm_confidence=0.0,
        )
        for url, (name, text) in pages.items()
    }
    return _sync_static(records, Opportunity.source_url.like(f"{_COURSE_URL_PREFIX}%"), now)


async def sync_scar_courses(now: Optional[datetime] = None) -> Optional[dict]:
    """Confere os cursos de música da SCAR, no máximo uma vez a cada
    COURSES_REFRESH. Devolve None quando não era hora (ou o site falhou —
    nada é desativado nesse caso)."""
    now = (now or datetime.now(timezone.utc)).replace(tzinfo=None)
    known = _known_courses()
    if known and all(scraped and scraped >= now - COURSES_REFRESH
                     for _, scraped in known.values()):
        return None

    async with httpx.AsyncClient(headers=_HEADERS, follow_redirects=True) as client:
        try:
            listing = await client.get(SCAR_MUSIC_COURSES_PAGE, timeout=30)
            listing.raise_for_status()
            links = _course_links(listing.text)
            pages = {}
            for url in links:
                page = await client.get(url, timeout=30)
                page.raise_for_status()
                pages[url] = (_course_name(page.text), _course_text(page.text))
        except httpx.HTTPError as exc:
            logger.warning(f"[WP] Cursos da SCAR: falha ao ler o site: {exc}")
            return None
    if not pages:
        logger.warning("[WP] Cursos da SCAR: nenhum curso na página — nada alterado")
        return None
    stats = _save_courses(pages, now)
    logger.info(
        f"[WP] Cursos da SCAR: {len(pages)} na página, {stats['new']} novos, "
        f"{stats['changed']} com texto mudado, {stats['removed']} saíram do site"
    )
    return stats


# ── Páginas fixas (FEMUSC) ───────────────────────────────────────────────

def _parse_pages(pages: list[dict], source: WordPressSource) -> dict[str, dict]:
    """Páginas que parecem chamada, já como oportunidade bruta."""
    records = {}
    for page in pages:
        if page.get("lang") not in (None, "pt") or page.get("slug") in _SKIP_PAGE_SLUGS:
            continue
        link = (page.get("link") or "").strip()
        if link.rstrip("/") == source.base_url:  # página inicial: vitrine, muda sempre
            continue
        title = _text((page.get("title") or {}).get("rendered", ""))
        content = _text((page.get("content") or {}).get("rendered", ""))
        if not link or _NOT_CALL_TITLE.search(title) or not _CALL_PATTERN.search(
                f"{title} {content}"):
            continue
        updated = (page.get("modified") or "")[:10]
        record = dict(
            title=title, description=content[:500],
            raw_text=(
                f"Página do site do {source.name} (atualizada em {updated}).\n\n"
                f"Título: {title}\n\nLocal: {source.city}, {source.state}, Brasil"
                f"\n\nTexto:\n{content}"
            ),
            type=None, instruments=[], source_name=source.name,
            institution=source.institution,
            institution_id=_pin_if_on_map(source.institution_id),
            country="Brasil", state=source.state, city=source.city,
            is_active=True, llm_confidence=0.0,
        )
        # Entrada = última atualização da página (ver NO_DEADLINE_MAX_AGE).
        try:
            record["created_at"] = datetime.fromisoformat(page.get("modified_gmt") or "")
        except ValueError:
            pass
        records[link + _PAGE_MARK] = record
    return records


async def sync_wordpress_pages(now: Optional[datetime] = None) -> dict:
    """Confere as páginas fixas das fontes com `read_pages` (todo dia: é uma
    consulta por site, e o Gemini só roda se uma página mudar). Site fora do
    ar não desativa nada."""
    now = (now or datetime.now(timezone.utc)).replace(tzinfo=None)
    totals = {}
    async with httpx.AsyncClient(headers=_HEADERS, follow_redirects=True) as client:
        for source in (s for s in SOURCES if s.read_pages):
            try:
                response = await client.get(
                    f"{source.base_url}/wp-json/wp/v2/pages",
                    params={"per_page": 100,
                            "_fields": "link,slug,modified,modified_gmt,title,content,lang"},
                    timeout=30,
                )
                response.raise_for_status()
                pages = response.json()
            except (httpx.HTTPError, ValueError) as exc:
                logger.warning(f"[WP] {source.name}: falha ao ler as páginas: {exc}")
                continue
            records = _parse_pages(pages, source)
            stats = _sync_static(
                records,
                (Opportunity.source_name == source.name)
                & Opportunity.source_url.like(f"%{_PAGE_MARK}"),
                now,
            )
            logger.info(
                f"[WP] {source.name}: {len(pages)} páginas, {len(records)} parecem chamada — "
                f"{stats['new']} novas, {stats['changed']} com texto mudado, "
                f"{stats['removed']} saíram"
            )
            totals[source.name] = stats
    return totals


# ── Saída do app ─────────────────────────────────────────────────────────

def _active_from_sources() -> list[tuple[str, Optional[date], Optional[datetime]]]:
    from app.database import SessionLocal

    db = SessionLocal()
    try:
        return (
            db.query(Opportunity.source_url, Opportunity.deadline, Opportunity.created_at)
            .filter(
                Opportunity.is_active.is_(True),
                Opportunity.source_name.in_([s.name for s in SOURCES]),
            )
            .all()
        )
    finally:
        db.close()


def _deactivate(urls: list[str]) -> None:
    from app.database import SessionLocal

    db = SessionLocal()
    try:
        (
            db.query(Opportunity)
            .filter(Opportunity.source_url.in_(urls))
            .update({Opportunity.is_active: False}, synchronize_session=False)
        )
        db.commit()
    finally:
        db.close()


async def deactivate_stale_posts(now: Optional[datetime] = None) -> int:
    """
    Desativa as oportunidades dessas fontes que saíram do ar: post apagado
    (404) ou sem prazo há mais de NO_DEADLINE_MAX_AGE. As de prazo vencido
    já somem do app pela data. Devolve quantas foram desativadas.
    """
    now = (now or datetime.now(timezone.utc)).replace(tzinfo=None)
    rows = _active_from_sources()
    # Cursos não têm prazo de propósito (matrícula contínua): só saem se
    # sumirem do site (ver _sync_static).
    expired = [
        url for url, deadline, created in rows
        if deadline is None and created and created < now - NO_DEADLINE_MAX_AGE
        and not url.startswith(_COURSE_URL_PREFIX)
    ]
    to_check = [url for url, deadline, _ in rows
                if url not in expired and (deadline is None or deadline >= now.date())]

    gone = []
    if to_check:
        async with httpx.AsyncClient(headers=_HEADERS, follow_redirects=True) as client:
            for url in to_check:
                try:
                    response = await client.get(url, timeout=30)
                    if response.status_code == 404:
                        gone.append(url)
                except httpx.HTTPError:
                    pass  # falha de rede não desativa

    removed = expired + gone
    if removed:
        _deactivate(removed)
        for url in removed:
            logger.info(f"[WP] Saiu do ar ou ficou velha, desativando: {url}")
    return len(removed)
