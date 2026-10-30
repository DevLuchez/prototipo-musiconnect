"""
Rotas do mapa (/api/institutions): busca por raio, carga inicial, busca por
texto, estatísticas, detalhe de um pino e as oportunidades de um pino.
"""

from datetime import date, timedelta

from tests.helpers import auth_headers, make_institution, make_opportunity, make_user

JARAGUA = (-26.4851, -49.0713)
SAO_PAULO = (-23.5505, -46.6333)


def _jaragua_e_sp(db):
    make_institution(db, osm_id="node_scar", name="SCAR – Sociedade Cultura Artística",
                     lat=JARAGUA[0], lng=JARAGUA[1])
    make_institution(db, osm_id="node_sp", name="Sala São Paulo",
                     lat=SAO_PAULO[0], lng=SAO_PAULO[1])


# ── /nearby ──────────────────────────────────────────────────────────────

def test_nearby_traz_so_o_que_esta_no_raio(api, db_session):
    _jaragua_e_sp(db_session)

    response = api.get("/api/institutions/nearby",
                       params={"lat": JARAGUA[0], "lng": JARAGUA[1], "radius_m": 50_000})

    assert response.status_code == 200
    assert [i["osm_id"] for i in response.json()] == ["node_scar"]


def test_nearby_ordena_pelo_mais_proximo_e_respeita_o_limite(api, db_session):
    _jaragua_e_sp(db_session)

    response = api.get("/api/institutions/nearby",
                       params={"lat": JARAGUA[0], "lng": JARAGUA[1],
                               "radius_m": 500_000, "limit": 1})

    assert [i["osm_id"] for i in response.json()] == ["node_scar"]


def test_nearby_recusa_coordenadas_invalidas(api):
    response = api.get("/api/institutions/nearby", params={"lat": 95, "lng": 0})
    assert response.status_code == 422


def test_nearby_conta_oportunidades_abertas_do_pino(api, db_session):
    _jaragua_e_sp(db_session)
    make_opportunity(db_session, title="Aberta", institution_id="node_scar")
    make_opportunity(db_session, title="Vencida", institution_id="node_scar",
                     deadline=date.today() - timedelta(days=1))
    make_opportunity(db_session, title="Baixa confiança", institution_id="node_scar",
                     llm_confidence=0.5)

    [scar] = api.get("/api/institutions/nearby",
                     params={"lat": JARAGUA[0], "lng": JARAGUA[1]}).json()

    assert scar["active_opportunities_count"] == 1


# ── /all ─────────────────────────────────────────────────────────────────

def test_all_poe_primeiro_as_que_tem_oportunidades(api, db_session):
    make_institution(db_session, osm_id="node_a", name="A Escola")
    make_institution(db_session, osm_id="node_z", name="Z Escola")
    make_opportunity(db_session, institution_id="node_z")

    response = api.get("/api/institutions/all", params={"limit": 1})

    assert [i["osm_id"] for i in response.json()] == ["node_z"]


# ── /stats ───────────────────────────────────────────────────────────────

def test_stats(api, db_session):
    _jaragua_e_sp(db_session)
    make_opportunity(db_session, institution_id="node_sp")

    stats = api.get("/api/institutions/stats").json()

    assert stats["total"] == 2
    assert stats["by_category"] == {"music_school": 2}
    assert stats["with_active_opportunities"] == 1
    assert stats["last_etl_run"] is not None


# ── /search ──────────────────────────────────────────────────────────────

def test_busca_ignora_maiusculas_e_acentos(api, db_session):
    _jaragua_e_sp(db_session)

    response = api.get("/api/institutions/search", params={"q": "sociedade cultura artistica"})

    assert [i["osm_id"] for i in response.json()] == ["node_scar"]


def test_busca_poe_primeiro_quem_comeca_com_o_termo(api, db_session):
    make_institution(db_session, osm_id="node_1", name="Escola Municipal de Teatro")
    make_institution(db_session, osm_id="node_2", name="Teatro Municipal")

    response = api.get("/api/institutions/search", params={"q": "teatro"})

    assert [i["osm_id"] for i in response.json()] == ["node_2", "node_1"]


def test_busca_trata_curingas_digitados_como_texto(api, db_session):
    make_institution(db_session, osm_id="node_1", name="Escola 100% Música")
    make_institution(db_session, osm_id="node_2", name="Escola 100 Música")

    response = api.get("/api/institutions/search", params={"q": "100%"})

    assert [i["osm_id"] for i in response.json()] == ["node_1"]


def test_busca_exige_dois_caracteres(api):
    assert api.get("/api/institutions/search", params={"q": "a"}).status_code == 422


# ── /{osm_id} e /{osm_id}/opportunities ──────────────────────────────────

def test_detalhe_de_um_pino(api, db_session):
    _jaragua_e_sp(db_session)

    response = api.get("/api/institutions/node_scar")

    assert response.status_code == 200
    assert response.json()["name"] == "SCAR – Sociedade Cultura Artística"


def test_detalhe_de_pino_inexistente(api):
    assert api.get("/api/institutions/node_nao_existe").status_code == 404


def test_oportunidades_do_pino_por_prazo(api, db_session):
    _jaragua_e_sp(db_session)
    make_opportunity(db_session, title="Depois", institution_id="node_scar",
                     deadline=date.today() + timedelta(days=60))
    make_opportunity(db_session, title="Antes", institution_id="node_scar",
                     deadline=date.today() + timedelta(days=5))
    make_opportunity(db_session, title="De outro pino", institution_id="node_sp")

    items = api.get("/api/institutions/node_scar/opportunities").json()

    assert [o["title"] for o in items] == ["Antes", "Depois"]
    assert items[0]["match_percentage"] is None  # sem login, sem match


def test_oportunidades_do_pino_com_match_para_quem_esta_logado(api, db_session):
    _jaragua_e_sp(db_session)
    make_opportunity(db_session, institution_id="node_scar", instruments=["Violino"])
    user = make_user(db_session)

    [opp] = api.get("/api/institutions/node_scar/opportunities",
                    headers=auth_headers(db_session, user)).json()

    assert opp["match_percentage"] > 0
    assert opp["match_breakdown"] is not None
