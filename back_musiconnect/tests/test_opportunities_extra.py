"""
Complementa test_opportunities_api.py: gravação das oportunidades vindas
dos scrapers, filtros por fonte/estado/cidade, marcadores por cidade do mapa,
aba Início (/api/dashboard) e limpeza diária dos salvos vencidos.
"""

import asyncio
from datetime import date, datetime, timedelta

import pytest

import app.routers.opportunities as opportunities_router
import app.services.favorites_cleanup as favorites_cleanup
from app.models import CityLocation, FavoriteOpportunity, Opportunity
from tests.helpers import auth_headers, make_institution, make_opportunity, make_user


@pytest.fixture
def same_session(monkeypatch, db_session):
    """Funções que abrem a própria sessão passam a usar a do teste."""
    monkeypatch.setattr(opportunities_router, "SessionLocal", lambda: db_session)
    monkeypatch.setattr(favorites_cleanup, "SessionLocal", lambda: db_session)


def _city(db, city="Jaraguá do Sul", lat=-26.48, lng=-49.07):
    loc = CityLocation(key=f"{city}|SC|Brasil", city=city, state="SC", country="Brasil",
                       lat=lat, lng=lng)
    db.add(loc)
    db.commit()
    return loc


# ── Gravação das oportunidades dos scrapers ──────────────────────────────

def _record(url, **fields):
    data = {"title": "Nova", "source_url": url, "source_name": "Musical Chairs",
            "raw_text": "texto", "type": "audicao", "is_active": True,
            "llm_confidence": 0.0, "scraped_at": datetime(2026, 10, 1)}
    data.update(fields)
    return data


def test_upsert_ignora_lista_vazia_e_registros_sem_link(same_session):
    assert opportunities_router._upsert_opportunities([]) == 0
    assert opportunities_router._upsert_opportunities([_record(None)]) == 0


def test_upsert_insere_novas_e_so_atualiza_a_data_das_existentes(db_session, same_session):
    url = "https://www.musicalchairs.info/jobs/1"
    existente = make_opportunity(db_session, title="Título bom", source_url=url,
                                 llm_confidence=0.95)
    existente_id = existente.id

    saved = opportunities_router._upsert_opportunities([
        _record(url, title="Resumo raso", scraped_at=datetime(2026, 10, 30)),
        _record("https://www.musicalchairs.info/jobs/2"),
    ])

    assert saved == 2
    db_session.expire_all()
    opp = db_session.get(Opportunity, existente_id)
    assert opp.title == "Título bom"          # não sobrescreve dados melhores
    assert opp.llm_confidence == 0.95         # nem a confiança já calculada
    assert opp.scraped_at == datetime(2026, 10, 30)
    assert db_session.query(Opportunity).count() == 2


def test_scrape_completo_grava_o_que_o_scraper_trouxe(monkeypatch, db_session, same_session):
    async def fake_scrape():
        return [_record("https://www.musicalchairs.info/jobs/9")]
    monkeypatch.setattr(opportunities_router, "scrape_musical_chairs", fake_scrape)

    stats = asyncio.run(opportunities_router._run_full_scrape())

    assert stats == {"musical_chairs": 1, "total_found": 1, "total_saved": 1}


# ── Filtros e detalhe ────────────────────────────────────────────────────

def test_filtros_por_fonte_estado_e_cidade(api, db_session):
    make_opportunity(db_session, title="SC MC", source_name="Musical Chairs",
                     state="SC", city="Jaraguá do Sul")
    make_opportunity(db_session, title="SP MC", source_name="Musical Chairs",
                     state="SP", city="São Paulo")
    make_opportunity(db_session, title="SC Funarte", source_name="Funarte",
                     state="SC", city="Jaraguá do Sul")

    titles = lambda params: {o["title"] for o in api.get("/api/opportunities/", params=params).json()}

    assert titles({"source_name": "Musical Chairs", "state": "SC"}) == {"SC MC"}
    assert titles({"city": "São Paulo"}) == {"SP MC"}


def test_lista_de_uma_cidade_exclui_as_que_tem_pino_proprio(api, db_session):
    loc = _city(db_session)
    make_institution(db_session, osm_id="node_1")
    make_opportunity(db_session, title="Só cidade", city_location_id=loc.id)
    make_opportunity(db_session, title="Com pino", city_location_id=loc.id,
                     institution_id="node_1")

    items = api.get("/api/opportunities/", params={"city_location_id": loc.id}).json()

    assert [o["title"] for o in items] == ["Só cidade"]


def test_detalhe_com_match_para_quem_esta_logado(api, db_session):
    opp = make_opportunity(db_session)
    user = make_user(db_session)

    body = api.get(f"/api/opportunities/{opp.id}", headers=auth_headers(db_session, user)).json()

    assert body["match_percentage"] > 0


def test_opcoes_de_filtro_respeitam_a_busca(api, db_session):
    make_opportunity(db_session, title="Audição de violino", instruments=["Violino"])
    make_opportunity(db_session, title="Curso de piano", instruments=["Piano"])

    options = api.get("/api/opportunities/filter-options", params={"q": "piano"}).json()

    assert options["instruments"] == ["Piano"]


# ── Marcadores por cidade (/cities) ──────────────────────────────────────

def test_marcadores_por_cidade_contam_so_as_sem_pino_presenciais_e_abertas(api, db_session):
    jaragua = _city(db_session)
    make_institution(db_session, osm_id="node_1")
    make_institution(db_session, osm_id="node_2", name="Outra")
    make_opportunity(db_session, title="Conta 1", city_location_id=jaragua.id)
    make_opportunity(db_session, title="Conta 2", city_location_id=jaragua.id)
    make_opportunity(db_session, title="Tem pino", city_location_id=jaragua.id,
                     institution_id="node_1")
    make_opportunity(db_session, title="Remota", city_location_id=jaragua.id, is_remote=True)
    make_opportunity(db_session, title="Vencida", city_location_id=jaragua.id,
                     deadline=date.today() - timedelta(days=1))
    vazia = _city(db_session, city="Blumenau")
    make_opportunity(db_session, title="Pino em Blumenau", city_location_id=vazia.id,
                     institution_id="node_2")

    cities = api.get("/api/opportunities/cities").json()

    assert len(cities) == 1
    assert cities[0]["city"] == "Jaraguá do Sul"
    assert cities[0]["opportunities_count"] == 2


# ── Aba Início (/api/dashboard) ──────────────────────────────────────────

def test_inicio_exige_login(api):
    assert api.get("/api/dashboard").status_code == 401


def test_inicio_monta_as_secoes(api, db_session):
    user = make_user(db_session, instruments=["Violino"])
    hoje = date.today()
    compat_urgente = make_opportunity(db_session, title="Compatível urgente",
                                      instruments=["Violino"], deadline=hoje + timedelta(days=2))
    make_opportunity(db_session, title="Compatível depois", instruments=["Violino"],
                     deadline=hoje + timedelta(days=40))
    salva_longe = make_opportunity(db_session, title="Salva longe", instruments=["Tuba"],
                                   deadline=hoje + timedelta(days=40), type="curso")
    for opp in (compat_urgente, salva_longe):
        db_session.add(FavoriteOpportunity(user_id=user.id, opportunity_id=opp.id))
    db_session.commit()

    body = api.get("/api/dashboard", headers=auth_headers(db_session, user)).json()

    assert body["match_count"] == 2
    assert [o["title"] for o in body["top_matches"]] == ["Compatível urgente", "Compatível depois"]
    assert {o["title"] for o in body["new_matches"]} == {"Compatível urgente", "Compatível depois"}
    assert [o["title"] for o in body["urgent_saved"]] == ["Compatível urgente"]
    assert body["type_counts"] == {"audicao": 2, "curso": 1}


# ── Limpeza diária dos salvos ────────────────────────────────────────────

def test_limpeza_apaga_so_os_salvos_que_sairam_do_app(db_session, same_session):
    user = make_user(db_session)
    visivel = make_opportunity(db_session, title="Visível")
    vencida = make_opportunity(db_session, title="Vencida", deadline=date.today() - timedelta(days=1))
    desativada = make_opportunity(db_session, title="Desativada", is_active=False)
    duvidosa = make_opportunity(db_session, title="Baixa confiança", llm_confidence=0.5)
    for opp in (visivel, vencida, desativada, duvidosa):
        db_session.add(FavoriteOpportunity(user_id=user.id, opportunity_id=opp.id))
    db_session.commit()
    visivel_id = visivel.id

    removed = favorites_cleanup.cleanup_favorite_opportunities()

    assert removed == 3
    restantes = db_session.query(FavoriteOpportunity.opportunity_id).all()
    assert restantes == [(visivel_id,)]


def test_filtro_por_pais(api, db_session):
    make_opportunity(db_session, title="No Brasil", country="Brasil")
    make_opportunity(db_session, title="Na Alemanha", country="Alemanha", state=None, city="Berlim")

    items = api.get("/api/opportunities/", params={"country": "Alemanha"}).json()

    assert [o["title"] for o in items] == ["Na Alemanha"]
