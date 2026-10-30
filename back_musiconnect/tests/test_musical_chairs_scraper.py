"""
Scraper do Musical Chairs (services/scrapers/musical_chairs_scraper.py):
RSS por instrumento → só tipos permitidos → deduplicação → página de
detalhe apenas das oportunidades novas.

O site é simulado (httpx.MockTransport) — nenhum teste acessa a rede.
"""

import asyncio
from datetime import date

import httpx
import pytest

import app.services.scrapers.musical_chairs_scraper as mc

BASE = "https://www.musicalchairs.info"


def _feed(*items):
    body = "".join(
        f"<item><title>{title}</title><link>{BASE}{path}</link>"
        f"<description>&lt;p&gt;{desc}&lt;/p&gt;</description></item>"
        for title, path, desc in items
    )
    return f'<?xml version="1.0"?><rss><channel>{body}</channel></rss>'


DETAIL_111 = """
<div class="post_item_name"><h2>Tampere Philharmonic Orchestra</h2></div>
<div class="post_item_location">Tampere, Finland</div>
<div class="post_item_closingdate">Closing date: 01 Dec 2026</div>
<div class="post_item_desc">Full description of the cello job.</div>
"""


# ── Partes isoladas ──────────────────────────────────────────────────────

@pytest.mark.parametrize(
    "path,expected",
    [
        ("/jobs/1", "audicao"),
        ("/competitions/1", "competicao"),
        ("/courses/1", "curso"),
        ("/degree-courses/1", "curso"),
        ("/teaching-jobs/1", "emprego"),
        ("/admin-jobs/1", "emprego"),
        ("/stolen/1", None),  # furto de instrumento: não é oportunidade
        ("/sales/1", None),
    ],
)
def test_so_tipos_permitidos_viram_oportunidade(path, expected):
    assert mc._classify_type(BASE + path) == expected


def test_leitura_do_rss():
    xml = _feed(
        ("Principal Cello", "/jobs/111?ref=rss", "Resumo"),
        ("Vendo violino", "/sales/222", "Barato"),
    )

    records = mc._parse_feed(xml, "double-bass")

    assert len(records) == 1  # a venda foi descartada
    rec = records[0]
    assert rec["source_url"] == f"{BASE}/jobs/111"  # sem ?ref=
    assert rec["type"] == "audicao"
    assert rec["instruments"] == ["Double Bass"]
    assert rec["description"] == "Resumo"  # HTML removido
    assert rec["source_name"] == "Musical Chairs"


def test_rss_invalido_nao_quebra():
    assert mc._parse_feed("isso não é xml", "violin") == []


def test_mesma_vaga_em_dois_instrumentos_junta_os_instrumentos():
    violin = mc._parse_feed(_feed(("Vaga", "/jobs/1", "x")), "violin")
    viola = mc._parse_feed(_feed(("Vaga", "/jobs/1", "x")), "viola")

    merged = mc._merge_and_deduplicate([violin, viola])

    assert len(merged) == 1
    assert merged[0]["instruments"] == ["Violin", "Viola"]


# ── Coleta completa, com o site simulado ─────────────────────────────────

@pytest.fixture
def fake_site(monkeypatch):
    feeds = {
        "/rss/en/violin": _feed(("Principal Cello", "/jobs/111", "Resumo")),
        "/rss/en/cello": _feed(
            ("Principal Cello", "/jobs/111", "Resumo"),
            ("Vaga já conhecida", "/jobs/333", "Resumo"),
            ("Vaga removida", "/jobs/444", "Resumo"),
        ),
    }
    details = {"/jobs/111": DETAIL_111}
    requested = []

    def handler(request):
        path = request.url.path
        requested.append(path)
        if path in feeds:
            return httpx.Response(200, text=feeds[path])
        if path in details:
            return httpx.Response(200, text=details[path])
        return httpx.Response(404)

    real_client = httpx.AsyncClient
    monkeypatch.setattr(
        mc.httpx, "AsyncClient",
        lambda **kw: real_client(transport=httpx.MockTransport(handler), **kw),
    )
    # "harp" não tem feed (404) — o scraper segue com os outros.
    monkeypatch.setattr(mc, "INSTRUMENTS", ["violin", "cello", "harp"])
    monkeypatch.setattr(mc, "_fetch_known_source_urls", lambda urls: {f"{BASE}/jobs/333"})
    return requested


def test_coleta_completa(fake_site):
    records = {r["source_url"]: r for r in asyncio.run(mc.scrape_musical_chairs())}

    # 444 foi removida do site (404 na página) e não entra.
    assert set(records) == {f"{BASE}/jobs/111", f"{BASE}/jobs/333"}

    nova = records[f"{BASE}/jobs/111"]
    assert nova["instruments"] == ["Violin", "Cello"]
    assert nova["institution"] == "Tampere Philharmonic Orchestra"
    assert nova["deadline"] == date(2026, 12, 1)
    assert nova["description"] == "Full description of the cello job."
    assert "Local: Tampere, Finland" in nova["raw_text"]

    # A já conhecida não é revisitada (cortesia com o site).
    assert "/jobs/333" not in fake_site
    assert records[f"{BASE}/jobs/333"]["institution"] is None


# ── Falhas e casos de borda ──────────────────────────────────────────────

def test_rss_sem_canal_ou_com_itens_incompletos():
    assert mc._parse_feed("<rss></rss>", "violin") == []
    sem_link = '<rss><channel><item><title>Sem link</title></item></channel></rss>'
    assert mc._parse_feed(sem_link, "violin") == []


def _with_client(handler, coro_fn):
    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await coro_fn(client)
    return asyncio.run(run())


def test_feed_com_erro_http_ou_sem_rede_vira_lista_vazia():
    assert _with_client(lambda r: httpx.Response(500),
                        lambda c: mc._fetch_feed(c, "violin")) == []

    def offline(request):
        raise httpx.ConnectError("sem rede")
    assert _with_client(offline, lambda c: mc._fetch_feed(c, "violin")) == []


def test_pagina_de_detalhe_com_erro_transitorio_vira_none():
    sem = asyncio.Semaphore(1)
    result = _with_client(lambda r: httpx.Response(503),
                          lambda c: mc._fetch_detail(c, f"{BASE}/jobs/1", sem))
    assert result is None


def test_detalhe_que_falhou_mantem_o_resumo_do_rss(monkeypatch):
    monkeypatch.setattr(mc, "_fetch_known_source_urls", lambda urls: set())
    records = [{"source_url": f"{BASE}/jobs/1", "institution": None, "deadline": None,
                "description": "Resumo", "raw_text": "Resumo"}]

    dead = _with_client(lambda r: httpx.Response(503),
                        lambda c: mc._enrich_with_details(c, records))

    assert dead == set()
    assert records[0]["description"] == "Resumo"


def test_sem_registros_novos_nao_visita_nenhuma_pagina(monkeypatch):
    monkeypatch.setattr(mc, "_fetch_known_source_urls", lambda urls: set(urls))
    visited = []

    def handler(request):
        visited.append(request.url.path)
        return httpx.Response(200)

    dead = _with_client(handler, lambda c: mc._enrich_with_details(
        c, [{"source_url": f"{BASE}/jobs/1"}]))

    assert dead == set() and visited == []


def test_consulta_os_links_ja_gravados_no_banco(monkeypatch, db_session):
    from tests.helpers import make_opportunity
    import app.database as database

    make_opportunity(db_session, title="Já gravada", source_url=f"{BASE}/jobs/1")
    monkeypatch.setattr(database, "SessionLocal", lambda: db_session)

    known = mc._fetch_known_source_urls([f"{BASE}/jobs/1", f"{BASE}/jobs/2"])

    assert known == {f"{BASE}/jobs/1"}
    assert mc._fetch_known_source_urls([]) == set()
