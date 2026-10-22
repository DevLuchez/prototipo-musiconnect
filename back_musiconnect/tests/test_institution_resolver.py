"""
Resolvedor oportunidade → mapa (services/institution_resolver.py).

Passada 1: liga a oportunidade ao pino da instituição organizadora (nome
igual + mesma cidade; senão geocodifica e reaproveita/cria o pino).
Passada 2: sem pino, liga ao centro da cidade (marcador "por cidade").

O Nominatim (geocodificação) é sempre simulado — nenhum teste acessa a rede.
"""

import asyncio

import pytest

import app.services.institution_factory as institution_factory
import app.services.institution_resolver as institution_resolver
from app.models import CityLocation, Institution, Opportunity
from tests.helpers import make_institution, make_opportunity

JARAGUA = {"category": "place", "lat": "-26.4851", "lon": "-49.0713"}


@pytest.fixture
def nominatim(monkeypatch, db_session):
    """Simula o Nominatim: `cities` responde centros de cidade e `places`
    responde organizadoras, por texto de busca. Registra as buscas feitas."""
    fake = {"cities": {}, "places": {}, "calls": []}

    async def fake_city(client, query):
        fake["calls"].append(("city", query))
        return fake["cities"].get(query)

    async def fake_place(client, query):
        fake["calls"].append(("place", query))
        return fake["places"].get(query)

    monkeypatch.setattr(institution_resolver, "geocode", fake_city)
    monkeypatch.setattr(institution_factory, "geocode_place", fake_place)
    monkeypatch.setattr(institution_resolver, "SessionLocal", lambda: db_session)
    return fake


def _run():
    return asyncio.run(institution_resolver.resolve_opportunity_institutions())




def test_liga_a_instituicao_existente_com_mesmo_nome_na_mesma_cidade(db_session, nominatim):
    make_institution(db_session, osm_id="node_1", name="Sociedade Cultura Artística",
                     lat=-26.4860, lng=-49.0700)
    opp = make_opportunity(db_session, institution="SOCIEDADE CULTURA ARTISTICA")
    opp_id = opp.id
    nominatim["cities"]["Jaraguá do Sul, SC, Brasil"] = JARAGUA

    stats = _run()

    opp = db_session.get(Opportunity, opp_id)
    assert opp.institution_id == "node_1"
    assert stats["linked"] == 1
    # Já existia no mapa: não precisou geocodificar a organizadora.
    assert not [c for c in nominatim["calls"] if c[0] == "place"]


def test_mesmo_nome_em_outra_cidade_nao_e_a_mesma_instituicao(db_session, nominatim):
    make_institution(db_session, osm_id="node_sp", name="Orquestra Municipal",
                     lat=-23.55, lng=-46.63)  # São Paulo, ~400 km
    opp = make_opportunity(db_session, institution="Orquestra Municipal")
    opp_id = opp.id
    nominatim["cities"]["Jaraguá do Sul, SC, Brasil"] = JARAGUA
    nominatim["places"]["Orquestra Municipal, Jaraguá do Sul, Brasil"] = {
        "osm_type": "node", "osm_id": 999, "lat": "-26.48", "lon": "-49.07",
        "type": "university", "category": "amenity", "display_name": "Rua X, Jaraguá do Sul",
    }

    _run()

    opp = db_session.get(Opportunity, opp_id)
    assert opp.institution_id == "node_999"
    criada = db_session.get(Institution, "node_999")
    assert criada.source == "pipeline"
    assert criada.category == "music_school"  # tipo do OSM prevalece (university)


def test_reaproveita_pino_do_mapa_achado_pela_geocodificacao(db_session, nominatim):
    make_institution(db_session, osm_id="node_7", name="Theatro Carlos Gomes")
    opp = make_opportunity(db_session, institution="Festival de Inverno", city="Blumenau")
    opp_id = opp.id
    nominatim["places"]["Festival de Inverno, Blumenau, Brasil"] = {
        "osm_type": "node", "osm_id": 7, "lat": "-26.92", "lon": "-49.06", "category": "amenity",
    }

    _run()

    opp = db_session.get(Opportunity, opp_id)
    assert opp.institution_id == "node_7"
    assert db_session.query(Institution).count() == 1  # não duplicou


def test_categoria_sugerida_pelo_llm_quando_o_osm_nao_diz(db_session, nominatim):
    opp = make_opportunity(db_session, institution="Coro Jovem", institution_category="music_org")
    opp_id = opp.id
    nominatim["places"]["Coro Jovem, Jaraguá do Sul, Brasil"] = {
        "osm_type": "way", "osm_id": 5, "lat": "-26.48", "lon": "-49.07",
        "type": "yes", "category": "building",
    }

    _run()

    opp = db_session.get(Opportunity, opp_id)
    assert db_session.get(Institution, opp.institution_id).category == "music_org"


def test_sem_pino_cai_no_centro_da_cidade(db_session, nominatim):
    opp = make_opportunity(db_session, institution="Concurso Internacional")
    opp_id = opp.id
    nominatim["cities"]["Jaraguá do Sul, SC, Brasil"] = JARAGUA  # organizadora não achada

    stats = _run()

    opp = db_session.get(Opportunity, opp_id)
    assert opp.institution_id is None
    city = db_session.get(CityLocation, opp.city_location_id)
    assert city.city == "Jaraguá do Sul"
    assert (city.lat, city.lng) == (-26.4851, -49.0713)
    assert stats == {"pending": 1, "linked": 0, "unresolved": 1, "linked_to_city": 1}


def test_resultado_que_nao_e_cidade_nao_vira_centro_da_cidade(db_session, nominatim):
    opp = make_opportunity(db_session, institution=None, city="Split", state=None, country="Croácia")
    opp_id = opp.id
    nominatim["cities"]["Split, Croácia"] = {"category": "shop", "lat": "1", "lon": "1"}

    _run()

    opp = db_session.get(Opportunity, opp_id)
    assert opp.city_location_id is None


def test_ignora_remotas_inativas_e_pouco_confiaveis(db_session, nominatim):
    for fields in ({"is_remote": True}, {"is_active": False}, {"llm_confidence": 0.5}):
        make_opportunity(db_session, institution="Orquestra X", title=str(fields), **fields)

    stats = _run()

    assert stats["pending"] == 0
    assert nominatim["calls"] == []


def test_mesma_organizadora_e_geocodificada_uma_vez_so(db_session, nominatim):
    make_opportunity(db_session, institution="Orquestra Y", title="Vaga 1")
    make_opportunity(db_session, institution="Orquestra Y", title="Vaga 2")
    nominatim["places"]["Orquestra Y, Jaraguá do Sul, Brasil"] = {
        "osm_type": "node", "osm_id": 42, "lat": "-26.48", "lon": "-49.07", "category": "amenity",
    }

    stats = _run()

    assert stats["linked"] == 2
    assert [c for c in nominatim["calls"] if c[0] == "place"] == [
        ("place", "Orquestra Y, Jaraguá do Sul, Brasil")
    ]


# ── Funções de apoio ─────────────────────────────────────────────────────

def test_normalizacao_de_nomes():
    assert (
        institution_factory.normalize_name("ORQUESTRA SINFÔNICA  de S.C.")
        == "orquestra sinfonica de s c"
    )
    assert institution_factory.normalize_name(None) == ""


def test_geocodificacao_descarta_cidades_ruas_e_lojas(monkeypatch):
    async def fake_geocode(client, query):
        return {"category": query}

    monkeypatch.setattr(institution_factory, "geocode", fake_geocode)

    for rejeitada in ("boundary", "place", "highway", "shop"):
        assert asyncio.run(institution_factory.geocode_place(None, rejeitada)) is None
    assert asyncio.run(institution_factory.geocode_place(None, "amenity")) == {"category": "amenity"}
