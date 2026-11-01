"""
Scraper da Revista CONCERTO (services/scrapers/concerto_scraper.py): uma
página com um parágrafo por item, em seções → oportunidade bruta para o
Gemini. Item que sai da página sai do app; texto mudado volta ao Gemini.

A página é simulada (httpx.MockTransport) — nenhum teste acessa a rede.
"""

import asyncio
from datetime import datetime

import httpx
import pytest

import app.services.scrapers.concerto_scraper as c
from app.models import Opportunity

PAGE = """
<html><body><header><p>SÃO PAULO</p><p>Menu: Temporada 2027</p></header>
<article><div class="field--type-text-with-summary"><div>
  <p>Última atualização: 30/10/2026</p>
  <p>Texto de abertura, antes das seções.</p>
  <p>SÃO PAULO</p>
  <p>[NOVO] 25º CONCURSO BRASILEIRO MARIA CALLAS . De 7 a 15 de março de 2027 .</p>
  <p>[NOVO] II SIMPÓSIO INTERNACIONAL FORMA MUSICAL: Franz Liszt, 140 anos . Resumo.</p>
  <p>BRASIL</p>
  <p>[NOVO] Belo Horizonte, MG / ACADEMIA FILARMÔNICA . Edital resumido.</p>
  <p>SÃO PAULO</p>
  <p>25º CONCURSO BRASILEIRO MARIA CALLAS . De 7 a 15 de março de 2027 . Inscrições até 16 de
     novembro <a href="https://mariacallas.example/">site</a>.</p>
  <p>II SIMPÓSIO INTERNACIONAL FORMA MUSICAL: FRANZ LISZT (1811-1886), 140 anos . Completo.</p>
  <p>Santo André, SP / PESQUISA SOBRE PERFORMANCE MUSICAL . Voluntários pianistas.</p>
  <p>OSESP . Temporada 2027 . Séries de assinaturas.</p>
  <p>EXPOSIÇÃO: Ecomusica . Até abril.</p>
  <p>[ON-LINE] ONDANCE - O marketplace da dança . Plataforma.</p>
  <p>BRASIL</p>
  <p>Belo Horizonte, MG / ACADEMIA FILARMÔNICA . Edital para harpa e viola até 31 de janeiro.</p>
  <p>INTERNACIONAL</p>
  <p>Portugal / 8º PRÊMIO MUSA . Composição, até 31 de janeiro de 2027.</p>
</div></div></article></body></html>
"""


def test_le_cada_item_uma_vez_com_o_local():
    records = {r["source_url"].split("#")[1]: r for r in c.parse_page(PAGE)}

    assert set(records) == {
        "25o-concurso-brasileiro-maria-callas",
        "ii-simposio-internacional-forma-musical-franz",
        "pesquisa-sobre-performance-musical",
        "academia-filarmonica",
        "8o-premio-musa",
    }
    callas = records["25o-concurso-brasileiro-maria-callas"]
    assert callas["source_name"] == "Revista CONCERTO"
    assert callas["source_url"].startswith(c.PAGE_URL + "#")
    assert "Local (segundo a revista): São Paulo, SP" in callas["raw_text"]
    assert "Inscrições até 16 de novembro" in callas["raw_text"]  # a lista completa prevalece
    assert "Links: https://mariacallas.example/" in callas["raw_text"]
    assert callas["country"] == "Brasil" and callas["llm_confidence"] == 0.0
    assert "Completo" in records["ii-simposio-internacional-forma-musical-franz"]["raw_text"]
    assert "Santo André, SP" in records["pesquisa-sobre-performance-musical"]["raw_text"]
    filarmonica = records["academia-filarmonica"]
    assert filarmonica["title"] == "ACADEMIA FILARMÔNICA"
    assert "Belo Horizonte, MG" in filarmonica["raw_text"]
    assert "harpa e viola" in filarmonica["raw_text"]
    musa = records["8o-premio-musa"]
    assert musa["country"] is None and "Portugal" in musa["raw_text"]


def test_pagina_sem_a_lista_nao_tem_itens():
    assert c.parse_page("<html><body><p>Fora do ar</p></body></html>") == []


@pytest.fixture
def same_session(monkeypatch, db_session):
    import app.database
    monkeypatch.setattr(app.database, "SessionLocal", lambda: db_session)
    monkeypatch.setattr(db_session, "close", lambda: None)
    return db_session


_REAL_CLIENT = httpx.AsyncClient


def _mock_page(monkeypatch, handler):
    """Troca a rede pelo `handler` (pode ser chamado de novo no mesmo teste)."""
    monkeypatch.setattr(
        c.httpx, "AsyncClient",
        lambda **kw: _REAL_CLIENT(transport=httpx.MockTransport(handler), **kw),
    )


def test_novos_mudados_e_que_sairam(monkeypatch, same_session):
    db = same_session
    pages = {"html": PAGE}
    _mock_page(monkeypatch, lambda request: httpx.Response(200, text=pages["html"]))
    dia1 = datetime(2026, 11, 2, 6, 0)

    assert asyncio.run(c.sync_concerto(now=dia1)) == {"new": 5, "changed": 0, "removed": 0}
    for opp in db.query(Opportunity):
        opp.enriched_at = dia1
    db.commit()

    # Dia seguinte: a revista mudou o texto da Academia e tirou o Prêmio MUSA.
    pages["html"] = PAGE.replace("harpa e viola", "harpa, viola e trompa").replace(
        "<p>Portugal / 8º PRÊMIO MUSA . Composição, até 31 de janeiro de 2027.</p>", "")
    stats = asyncio.run(c.sync_concerto(now=datetime(2026, 11, 3, 6, 0)))

    assert stats == {"new": 0, "changed": 1, "removed": 1}
    by_key = {o.source_url.split("#")[1]: o for o in db.query(Opportunity)}
    assert by_key["academia-filarmonica"].enriched_at is None  # volta ao Gemini
    assert by_key["25o-concurso-brasileiro-maria-callas"].enriched_at == dia1
    assert by_key["8o-premio-musa"].is_active is False


def test_pagina_fora_do_ar_ou_vazia_nao_mexe_em_nada(monkeypatch, same_session):
    db = same_session
    _mock_page(monkeypatch, lambda request: httpx.Response(200, text=PAGE))
    asyncio.run(c.sync_concerto())

    _mock_page(monkeypatch, lambda request: httpx.Response(503))
    assert asyncio.run(c.sync_concerto()) is None
    _mock_page(monkeypatch, lambda request: httpx.Response(200, text="<p>em manutenção</p>"))
    assert asyncio.run(c.sync_concerto()) is None

    assert all(o.is_active for o in db.query(Opportunity))
