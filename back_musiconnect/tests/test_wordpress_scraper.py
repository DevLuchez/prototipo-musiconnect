"""
Scraper de SCAR e FEMUSC (services/scrapers/wordpress_scraper.py): posts
recentes pela API do WordPress → só os que parecem chamada → oportunidade
bruta para o Gemini. Sai do app quando o post some ou fica velho sem prazo.

Os sites são simulados (httpx.MockTransport) — nenhum teste acessa a rede.
"""

import asyncio
from datetime import date, datetime, timedelta

import httpx
import pytest

import app.services.scrapers.wordpress_scraper as wp
from app.models import Opportunity
from tests.helpers import make_institution, make_opportunity

SCAR = wp.SOURCES[0]
FEMUSC = wp.SOURCES[1]


def _post(title, content="", link="https://scar.art.br/x/", lang=None,
          date_gmt="2026-10-20T13:00:00"):
    post = {
        "date": date_gmt, "date_gmt": date_gmt, "link": link,
        "title": {"rendered": title},
        "content": {"rendered": f"<p>{content}</p>"},
    }
    if lang:
        post["lang"] = lang
    return post


@pytest.mark.parametrize(
    "title,content,expected",
    [
        ("Orquestra Jovem SCAR abre audições para diferentes instrumentos", "", True),
        ("Projeto Música Para Todos está com inscrições abertas", "", True),
        ("SCAR recebe masterclasses gratuitas com o fagotista", "", True),
        ("Coral SCAR apresenta repertório", "Interessados devem fazer a inscrição", True),
        ("[FOTOS] Mostra Geral dos alunos", "inscrições", False),
        ("Edital de convocação de Assembleia Geral", "", False),
        ("FEMUSC registra recordes de inscrições", "", False),
        ("Escola de Dança conquista medalhas", "", False),
    ],
)
def test_so_o_que_parece_chamada(title, content, expected):
    assert wp.looks_like_call(title, content) is expected


def test_post_vira_oportunidade_bruta():
    posts = [
        _post("Orquestra Jovem SCAR abre &#8220;audições&#8221;", "Para <b>violino</b> e viola",
              link="https://scar.art.br/audicoes/"),
        _post("Mostra de dança encanta o público"),
    ]

    [rec] = wp._parse_posts(posts, SCAR)

    assert rec["title"] == "Orquestra Jovem SCAR abre “audições”"
    assert rec["source_url"] == "https://scar.art.br/audicoes/"
    assert rec["source_name"] == "SCAR"
    assert rec["institution_id"] == "way_256649111"
    assert (rec["city"], rec["state"], rec["country"]) == ("Jaraguá do Sul", "SC", "Brasil")
    assert rec["type"] is None and rec["llm_confidence"] == 0.0
    assert "Publicado em: 2026-10-20" in rec["raw_text"]
    assert "Para violino e viola" in rec["raw_text"]
    assert rec["created_at"] == datetime(2026, 10, 20, 13, 0)


def test_so_a_versao_em_portugues_do_femusc():
    posts = [
        _post("Inscrições para a 22ª edição do FEMUSC estão abertas", lang="pt"),
        _post("Las inscripciones para la 22.ª edición de FEMUSC están abiertas", lang="es"),
        _post("Registration for the 22nd edition of FEMUSC is open", lang="en"),
    ]

    records = wp._parse_posts(posts, FEMUSC)

    assert [r["title"] for r in records] == ["Inscrições para a 22ª edição do FEMUSC estão abertas"]
    assert records[0]["institution_id"] is None


def test_data_invalida_nao_impede_a_coleta():
    [rec] = wp._parse_posts([_post("Inscrições abertas", date_gmt="")], SCAR)
    assert "created_at" not in rec


_REAL_CLIENT = httpx.AsyncClient


def _mock_sites(monkeypatch, handler):
    """Troca a rede pelo `handler` (pode ser chamado de novo no mesmo teste)."""
    monkeypatch.setattr(
        wp.httpx, "AsyncClient",
        lambda **kw: _REAL_CLIENT(transport=httpx.MockTransport(handler), **kw),
    )


def test_sem_o_pino_no_mapa_fica_sem_vinculo(monkeypatch, same_session):
    """Banco sem o pino da SCAR: grava sem vínculo (a resolução procura depois)."""
    _mock_sites(monkeypatch, lambda request: httpx.Response(200, json=[_post("Inscrições abertas")]))
    records = asyncio.run(wp.scrape_wordpress_sources())
    assert {r["institution_id"] for r in records} == {None}

    make_institution(same_session, osm_id="way_256649111", name="SCAR")
    records = asyncio.run(wp.scrape_wordpress_sources())
    assert [r["institution_id"] for r in records if r["source_name"] == "SCAR"] == ["way_256649111"]


def test_coleta_pagina_as_duas_fontes(monkeypatch, same_session):
    seen = []

    def handler(request):
        seen.append((request.url.host, request.url.params.get("page")))
        if request.url.host == "scar.art.br":
            page = int(request.url.params["page"])
            title = "Inscrições abertas" if page == 1 else "Audições abertas"
            return httpx.Response(200, json=[_post(title, link=f"https://scar.art.br/{page}/")],
                                  headers={"X-WP-TotalPages": "2"})
        return httpx.Response(200, json=[_post("Concerto de gala")])

    _mock_sites(monkeypatch, handler)
    records = asyncio.run(wp.scrape_wordpress_sources(now=datetime(2026, 11, 1)))

    assert [r["source_url"] for r in records] == ["https://scar.art.br/1/", "https://scar.art.br/2/"]
    assert ("scar.art.br", "2") in seen
    assert ("femusc.com.br", "1") in seen


def test_site_fora_do_ar_nao_derruba_a_coleta(monkeypatch, same_session):
    def handler(request):
        if request.url.host == "femusc.com.br":
            return httpx.Response(500)
        return httpx.Response(200, json=[_post("Inscrições abertas")])

    _mock_sites(monkeypatch, handler)
    records = asyncio.run(wp.scrape_wordpress_sources())

    assert [r["source_name"] for r in records] == ["SCAR"]


# ── Saída do app ─────────────────────────────────────────────────────────

@pytest.fixture
def same_session(monkeypatch, db_session):
    import app.database
    monkeypatch.setattr(app.database, "SessionLocal", lambda: db_session)
    monkeypatch.setattr(db_session, "close", lambda: None)
    return db_session


def test_post_apagado_ou_velho_sem_prazo_sai_do_app(monkeypatch, same_session):
    db = same_session
    now = datetime(2026, 11, 1, 12, 0)
    apagado = make_opportunity(db, source_name="SCAR", source_url="https://scar.art.br/apagado/",
                               deadline=None, created_at=now - timedelta(days=5))
    velho = make_opportunity(db, source_name="FEMUSC", source_url="https://femusc.com.br/velho/",
                             deadline=None, created_at=now - timedelta(days=60))
    no_ar = make_opportunity(db, source_name="SCAR", source_url="https://scar.art.br/no-ar/",
                             deadline=date(2026, 12, 1), created_at=now - timedelta(days=60))
    instavel = make_opportunity(db, source_name="SCAR", source_url="https://scar.art.br/instavel/",
                                deadline=None, created_at=now - timedelta(days=1))
    outra_fonte = make_opportunity(db, source_name="Musical Chairs",
                                   source_url="https://www.musicalchairs.info/jobs/1",
                                   deadline=None, created_at=now - timedelta(days=90))
    ids = {o: o.id for o in (apagado, velho, no_ar, instavel, outra_fonte)}
    checked = []

    def handler(request):
        checked.append(str(request.url))
        if request.url.path == "/apagado/":
            return httpx.Response(404)
        if request.url.path == "/instavel/":
            raise httpx.ConnectError("sem rede")
        return httpx.Response(200)

    _mock_sites(monkeypatch, handler)
    removed = asyncio.run(wp.deactivate_stale_posts(now=now))

    assert removed == 2
    active = {o: db.get(Opportunity, i).is_active for o, i in ids.items()}
    assert active == {apagado: False, velho: False, no_ar: True, instavel: True, outra_fonte: True}
    assert "https://femusc.com.br/velho/" not in checked  # nem precisa conferir


def test_nada_para_conferir(monkeypatch, same_session):
    _mock_sites(monkeypatch, lambda request: pytest.fail("não devia acessar a rede"))
    assert asyncio.run(wp.deactivate_stale_posts()) == 0


# ── Cursos de música da SCAR ─────────────────────────────────────────────

LISTING = """<header><a href="https://scar.art.br/cursos/fora-do-main/">menu</a></header>
<main>
  <a href="https://scar.art.br/cursos/cordas/">Cordas</a>
  <a href="https://scar.art.br/cursos/cordas/#mais">Mais informações</a>
  <a href="https://scar.art.br/cursos/piano-2/">Piano</a>
  <a href="https://scar.art.br/contato/">Contato</a>
</main>"""


def _course_page(name, price="12 x de R$ 398"):
    return (f"<header>Menu do site</header><main><h1>{name}</h1><p>Aulas de {name}.</p>"
            f"<p>Anual {price}</p><p>CURSOS POR CATEGORIA Clique para ver</p></main>")


def test_leitura_da_pagina_de_cursos():
    assert wp._course_links(LISTING) == [
        "https://scar.art.br/cursos/cordas/", "https://scar.art.br/cursos/piano-2/"]
    page = _course_page("Cordas")
    assert wp._course_name(page) == "Cordas"
    assert wp._course_text(page) == "Cordas Aulas de Cordas. Anual 12 x de R$ 398"
    assert wp._course_name("<main><p>sem título</p></main>") == ""
    raw = wp._course_raw_text("Cordas", "texto")
    assert 'Use como título: "Curso de Cordas na SCAR"' in raw
    assert "sem data de encerramento" in raw
    assert "Use como título" not in wp._course_raw_text("", "texto")


def _mock_courses(monkeypatch, pages, fail=False):
    def handler(request):
        if fail:
            return httpx.Response(503)
        if str(request.url) == wp.SCAR_MUSIC_COURSES_PAGE:
            return httpx.Response(200, text=pages["listing"])
        return httpx.Response(200, text=pages[request.url.path])

    _mock_sites(monkeypatch, handler)


def test_cursos_entram_sem_prazo_e_sao_conferidos_uma_vez_por_mes(monkeypatch, same_session):
    db = same_session
    make_institution(db, osm_id="way_256649111", name="SCAR – Sociedade Cultura Artística")
    pages = {"listing": LISTING, "/cursos/cordas/": _course_page("Cordas"),
             "/cursos/piano-2/": _course_page("Piano")}
    _mock_courses(monkeypatch, pages)
    dia1 = datetime(2026, 11, 1, 6, 0)

    assert asyncio.run(wp.sync_scar_courses(now=dia1)) == {"new": 2, "changed": 0, "removed": 0}
    cordas = db.query(Opportunity).filter_by(source_url="https://scar.art.br/cursos/cordas/").one()
    assert (cordas.type, cordas.deadline, cordas.source_name) == ("curso", None, "SCAR")
    assert cordas.title == "Curso de Cordas na SCAR"
    assert cordas.institution_id == "way_256649111"
    assert cordas.enriched_at is None  # vai para o Gemini

    # No mesmo mês, nem acessa o site.
    _mock_sites(monkeypatch, lambda request: pytest.fail("não devia acessar o site"))
    assert asyncio.run(wp.sync_scar_courses(now=dia1 + timedelta(days=10))) is None

    # Um mês depois: piano mudou de preço, cordas igual, um curso novo.
    for opp in db.query(Opportunity):
        opp.enriched_at = dia1
    db.commit()
    pages["/cursos/piano-2/"] = _course_page("Piano", price="12 x de R$ 420")
    pages["listing"] = LISTING.replace(
        "</main>", '<a href="https://scar.art.br/cursos/metais/">Metais</a></main>')
    pages["/cursos/metais/"] = _course_page("Metais")
    _mock_courses(monkeypatch, pages)

    stats = asyncio.run(wp.sync_scar_courses(now=dia1 + timedelta(days=31)))

    assert stats == {"new": 1, "changed": 1, "removed": 0}
    by_url = {o.source_url: o for o in db.query(Opportunity)}
    assert by_url["https://scar.art.br/cursos/piano-2/"].enriched_at is None
    assert by_url["https://scar.art.br/cursos/cordas/"].enriched_at == dia1


def test_curso_que_sai_do_site_sai_do_app(monkeypatch, same_session):
    db = same_session
    make_opportunity(db, source_name="SCAR", source_url="https://scar.art.br/cursos/flauta/",
                     deadline=None, scraped_at=datetime(2026, 9, 1))
    _mock_courses(monkeypatch, {"listing": LISTING, "/cursos/cordas/": _course_page("Cordas"),
                                "/cursos/piano-2/": _course_page("Piano")})

    stats = asyncio.run(wp.sync_scar_courses(now=datetime(2026, 11, 1)))

    assert stats["removed"] == 1
    flauta = db.query(Opportunity).filter_by(source_url="https://scar.art.br/cursos/flauta/").one()
    assert flauta.is_active is False


def test_site_fora_do_ar_nao_mexe_nos_cursos(monkeypatch, same_session):
    db = same_session
    make_opportunity(db, source_name="SCAR", source_url="https://scar.art.br/cursos/flauta/",
                     deadline=None, scraped_at=datetime(2026, 9, 1))
    _mock_courses(monkeypatch, {}, fail=True)

    assert asyncio.run(wp.sync_scar_courses(now=datetime(2026, 11, 1))) is None
    assert db.query(Opportunity).one().is_active is True


def test_pagina_de_cursos_vazia_nao_desativa_nada(monkeypatch, same_session):
    db = same_session
    make_opportunity(db, source_name="SCAR", source_url="https://scar.art.br/cursos/flauta/",
                     deadline=None, scraped_at=datetime(2026, 9, 1))
    _mock_courses(monkeypatch, {"listing": "<main>em manutenção</main>"})

    assert asyncio.run(wp.sync_scar_courses(now=datetime(2026, 11, 1))) is None
    assert db.query(Opportunity).one().is_active is True


def test_curso_sem_prazo_nao_vence_por_idade(monkeypatch, same_session):
    db = same_session
    now = datetime(2026, 11, 1)
    curso = make_opportunity(db, source_name="SCAR", source_url="https://scar.art.br/cursos/cordas/",
                             deadline=None, created_at=now - timedelta(days=200))
    _mock_sites(monkeypatch, lambda request: httpx.Response(200))

    assert asyncio.run(wp.deactivate_stale_posts(now=now)) == 0
    assert db.get(Opportunity, curso.id).is_active is True


# ── Páginas fixas (FEMUSC) ───────────────────────────────────────────────

def _page(slug, title, content, modified="2026-10-20T10:00:00", lang=None,
          link=None):
    page = {"slug": slug, "link": link or f"https://femusc.com.br/{slug}/",
            "modified": modified, "modified_gmt": modified,
            "title": {"rendered": title},
            "content": {"rendered": f"<style>#uc_x {{ color: red; }}</style><p>{content}</p>"}}
    if lang:
        page["lang"] = lang
    return page


FEMUSC_PAGES = [
    _page("femusc-jovem", "Femusc Jovem", "EDITAL DE SELEÇÃO. Inscrições de 5 a 15 de novembro."),
    _page("concurso-sheherazade", "Concurso", "Regulamento do concurso para solistas."),
    _page("femusckinho", "Femusckinho", "Colônia de férias musical."),  # não parece chamada
    _page("contato", "Contato", "Inscrições por e-mail"),             # institucional
    _page("", "Início", "Inscrições abertas", link="https://femusc.com.br/"),  # página inicial
    _page("femusc-youth", "Femusc Youth", "Registration", lang="en"),
    _page("galeria", "[FOTOS] Galeria", "inscrições"),
]


def test_paginas_que_parecem_chamada():
    records = wp._parse_pages(FEMUSC_PAGES, FEMUSC)

    assert set(records) == {
        "https://femusc.com.br/femusc-jovem/#pagina",
        "https://femusc.com.br/concurso-sheherazade/#pagina",
    }
    jovem = records["https://femusc.com.br/femusc-jovem/#pagina"]
    assert jovem["source_name"] == "FEMUSC" and jovem["type"] is None
    assert "color: red" not in jovem["raw_text"]  # CSS do construtor de páginas fora
    assert "Inscrições de 5 a 15 de novembro" in jovem["raw_text"]
    assert "atualizada em 2026-10-20" in jovem["raw_text"]
    assert jovem["created_at"] == datetime(2026, 10, 20, 10, 0)


def test_pagina_com_data_invalida_entra_sem_data():
    [rec] = wp._parse_pages([_page("x", "Edital", "inscrições", modified="")], FEMUSC).values()
    assert "created_at" not in rec


def test_sincronizacao_das_paginas(monkeypatch, same_session):
    db = same_session
    pages = {"list": list(FEMUSC_PAGES)}

    def handler(request):
        if request.url.host == "femusc.com.br" and request.url.path == "/wp-json/wp/v2/pages":
            return httpx.Response(200, json=pages["list"])
        return httpx.Response(404)

    _mock_sites(monkeypatch, handler)
    assert asyncio.run(wp.sync_wordpress_pages()) == {
        "FEMUSC": {"new": 2, "changed": 0, "removed": 0}}
    for opp in db.query(Opportunity):
        opp.enriched_at = datetime(2026, 11, 2)
    db.commit()

    # Página velha sem prazo foi desativada pela idade; depois o FEMUSC
    # atualiza o FEMUSC Jovem (edição nova) e tira o concurso do ar.
    jovem = db.query(Opportunity).filter(Opportunity.source_url.like("%femusc-jovem%")).one()
    jovem.is_active = False
    db.commit()
    pages["list"] = [_page("femusc-jovem", "Femusc Jovem", "EDITAL 2028. Inscrições em novembro.",
                           modified="2027-10-01T09:00:00")]

    stats = asyncio.run(wp.sync_wordpress_pages())

    assert stats == {"FEMUSC": {"new": 0, "changed": 1, "removed": 1}}
    db.refresh(jovem)
    assert jovem.is_active is True and jovem.enriched_at is None
    assert jovem.created_at == datetime(2027, 10, 1, 9, 0)
    concurso = db.query(Opportunity).filter(Opportunity.source_url.like("%sheherazade%")).one()
    assert concurso.is_active is False


def test_site_fora_do_ar_nao_mexe_nas_paginas(monkeypatch, same_session):
    _mock_sites(monkeypatch, lambda request: httpx.Response(503))
    assert asyncio.run(wp.sync_wordpress_pages()) == {}


def test_pagina_sem_prazo_vence_pela_data_da_atualizacao(monkeypatch, same_session):
    db = same_session
    now = datetime(2026, 11, 2)
    velha = make_opportunity(db, source_name="FEMUSC", deadline=None,
                             source_url="https://femusc.com.br/harpa/#pagina",
                             created_at=now - timedelta(days=150))
    _mock_sites(monkeypatch, lambda request: httpx.Response(200))

    assert asyncio.run(wp.deactivate_stale_posts(now=now)) == 1
    assert db.get(Opportunity, velha.id).is_active is False
