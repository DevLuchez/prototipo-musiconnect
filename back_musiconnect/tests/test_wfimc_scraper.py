"""
Scraper da WFIMC (services/scrapers/wfimc_scraper.py): cartões da página de
prazos → oportunidade bruta (concurso) para o Gemini, com o texto da página
do concurso. Concurso repetido de outra fonte não entra; o que sai da
página sai do app.

O site é simulado (httpx.MockTransport) — nenhum teste acessa a rede.
"""

import asyncio
from datetime import date, datetime

import httpx
import pytest

import app.services.scrapers.wfimc_scraper as w
from app.models import Opportunity
from tests.helpers import make_opportunity

BASE = "https://www.wfimc.org/member-competition"


def _card(name, deadlines, disciplines=("Piano",), country="Canada", slug="x"):
    times = "".join(f'<time datetime="{d}T00:00:00+01:00">x</time>' for d in deadlines)
    disc = "".join(f'<p class="cmp-discipline">{d}</p>' for d in disciplines)
    return (f'<div class="views-row-inner"><h3>{times}</h3><div class="node">{disc}'
            f'<h3 class="cmp-title"><a href="{BASE}/{slug}">{name}</a></h3>'
            f'<p class="larger light">{country}</p></div></div>')


PAGE = "<main>" + "".join([
    _card("Leeds - Leeds International Piano Competition", ["2026-12-31"],
          country="United Kingdom", slug="leeds"),
    _card("Helsinki - Mirjam Helin International Singing Competition",
          ["2026-11-02", "2026-11-30"], ("Voice",), "Finland", "helsinki"),
    _card('Porcia - International Competition "Città di Porcia"', ["2026-11-29"],
          ("Brass", "Tuba"), "Italy", "porcia"),
    _card('Porcia - International Competition "Città di Porcia"', ["2027-09-25"],
          ("Brass", "Horn"), "Italy", "porcia"),
    _card("Concurso sem cidade", ["2027-01-10"], slug="sem-cidade"),
    _card("Já encerrado - Old Competition", ["2026-10-01"], slug="old"),
    '<div class="views-row-inner"><h3>sem prazo</h3></div>',
    _card("Data ruim - Broken", ["2026-13-45"], slug="broken"),
]) + "</main>"


def test_leitura_dos_cartoes():
    records = {r["source_url"]: r for r in w.parse_page(PAGE)}

    assert len(records) == 6  # sem o cartão sem prazo e o de data inválida
    leeds = records[f"{BASE}/leeds#2026-12-31"]
    assert leeds["title"] == "Leeds International Piano Competition"
    assert (leeds["city"], leeds["country"]) == ("Leeds", "United Kingdom")
    assert leeds["type"] == "competicao" and leeds["deadline"] == date(2026, 12, 31)
    assert leeds["source_name"] == "WFIMC" and leeds["institution"] == leeds["title"]
    assert "Disciplinas: Piano" in leeds["raw_text"]
    # Intervalo de prazo: vale a data final.
    assert f"{BASE}/helsinki#2026-11-30" in records
    # O mesmo concurso em duas edições: dois registros.
    assert {f"{BASE}/porcia#2026-11-29", f"{BASE}/porcia#2027-09-25"} <= set(records)
    sem_cidade = records[f"{BASE}/sem-cidade#2027-01-10"]
    assert sem_cidade["city"] is None and sem_cidade["title"] == "Concurso sem cidade"


def test_texto_da_pagina_do_concurso():
    html = "<header>Menu</header><main><h1>Leeds</h1><p>Upper   age limit 35.</p></main>"
    assert w._page_text(html) == "Leeds Upper age limit 35."


@pytest.fixture
def same_session(monkeypatch, db_session):
    import app.database
    monkeypatch.setattr(app.database, "SessionLocal", lambda: db_session)
    monkeypatch.setattr(db_session, "close", lambda: None)
    return db_session


_REAL_CLIENT = httpx.AsyncClient


def _mock_site(monkeypatch, handler):
    monkeypatch.setattr(
        w.httpx, "AsyncClient",
        lambda **kw: _REAL_CLIENT(transport=httpx.MockTransport(handler), **kw),
    )


def test_sincronizacao(monkeypatch, same_session):
    db = same_session
    # Já no Musical Chairs: mesmo prazo, mesmo nome.
    make_opportunity(db, source_name="Musical Chairs", type="competicao",
                     title="Concurso Internacional de Piano de Leeds",
                     institution="Leeds International Piano Competition",
                     deadline=date(2026, 12, 31), source_url="https://mc/leeds")
    pages_fetched = []

    def handler(request):
        if str(request.url) == w.PAGE_URL:
            return httpx.Response(200, text=PAGE)
        pages_fetched.append(request.url.path)
        if request.url.path.endswith("/porcia"):
            return httpx.Response(500)  # entra só com os dados do cartão
        return httpx.Response(200, text="<main>Regulamento completo.</main>")

    _mock_site(monkeypatch, handler)
    now = datetime(2026, 11, 2, 6, 0)

    stats = asyncio.run(w.sync_wfimc(now=now))

    # 6 cartões válidos − 1 encerrado − 1 repetido do Musical Chairs = 4.
    assert stats == {"new": 4, "duplicates": 1, "removed": 0}
    by_url = {o.source_url: o for o in db.query(Opportunity).filter_by(source_name="WFIMC")}
    assert "Página do concurso:\nRegulamento completo." in by_url[f"{BASE}/helsinki#2026-11-30"].raw_text
    assert "Página do concurso" not in by_url[f"{BASE}/porcia#2026-11-29"].raw_text
    assert pages_fetched.count(f"/member-competition/porcia") == 1  # uma vez por concurso

    # Dia seguinte: o Helsinki saiu da página; os outros continuam (sem reler).
    pages_fetched.clear()
    page2 = PAGE.replace("Helsinki - Mirjam", "X").replace("/helsinki", "/sumiu").replace(
        "2026-11-30", "2026-10-02")
    _mock_site(monkeypatch, lambda request: httpx.Response(200, text=page2)
               if str(request.url) == w.PAGE_URL else httpx.Response(200, text="<main>x</main>"))
    stats = asyncio.run(w.sync_wfimc(now=datetime(2026, 11, 3, 6, 0)))

    assert stats["removed"] == 1 and stats["new"] == 0
    assert db.query(Opportunity).filter_by(
        source_url=f"{BASE}/helsinki#2026-11-30").one().is_active is False


def test_pagina_fora_do_ar_ou_vazia_nao_mexe_em_nada(monkeypatch, same_session):
    db = same_session
    make_opportunity(db, source_name="WFIMC", type="competicao",
                     source_url=f"{BASE}/leeds#2026-12-31", deadline=date(2026, 12, 31))

    _mock_site(monkeypatch, lambda request: httpx.Response(503))
    assert asyncio.run(w.sync_wfimc()) is None
    _mock_site(monkeypatch, lambda request: httpx.Response(200, text="<main>manutenção</main>"))
    assert asyncio.run(w.sync_wfimc()) is None

    assert db.query(Opportunity).one().is_active is True
