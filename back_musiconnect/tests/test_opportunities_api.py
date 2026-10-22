"""
Listagem e filtros do Matcher (/api/opportunities): o que aparece para o
aluno, filtros combinados, busca livre, total, match e contagem de Matches.
"""

from datetime import date, timedelta

from tests.helpers import auth_headers, make_opportunity, make_user


def _titles(response):
    return sorted(o["title"] for o in response.json())


def test_so_mostra_ativas_confiaveis_e_com_prazo_aberto(api, db_session):
    make_opportunity(db_session, title="Visível")
    make_opportunity(db_session, title="Sem prazo", deadline=None)
    make_opportunity(db_session, title="Inativa", is_active=False)
    make_opportunity(db_session, title="Pouco confiável", llm_confidence=0.5)
    make_opportunity(db_session, title="Vencida", deadline=date.today() - timedelta(days=1))

    response = api.get("/api/opportunities/")

    assert _titles(response) == ["Sem prazo", "Visível"]
    assert response.headers["X-Total-Count"] == "2"


def test_total_ignora_o_limite_da_pagina(api, db_session):
    for i in range(3):
        make_opportunity(db_session, title=f"Opp {i}")

    response = api.get("/api/opportunities/", params={"limit": 1})

    assert len(response.json()) == 1
    assert response.headers["X-Total-Count"] == "3"


def test_filtros_or_dentro_do_campo_e_and_entre_campos(api, db_session):
    make_opportunity(db_session, title="Violino SC", instruments=["Violino"], state="SC")
    make_opportunity(db_session, title="Piano SC", instruments=["Piano"], state="SC")
    make_opportunity(db_session, title="Violino SP", instruments=["Violino"], state="SP")
    make_opportunity(db_session, title="Flauta SC", instruments=["Flauta"], state="SC")

    response = api.get(
        "/api/opportunities/",
        params={"instrument": ["Violino", "Piano"], "state": "SC"},
    )

    assert _titles(response) == ["Piano SC", "Violino SC"]


def test_filtro_por_tipo_e_remotas(api, db_session):
    make_opportunity(db_session, title="Curso online", type="curso", is_remote=True)
    make_opportunity(db_session, title="Curso presencial", type="curso")
    make_opportunity(db_session, title="Emprego", type="emprego")

    assert _titles(api.get("/api/opportunities/", params={"type": "curso"})) == [
        "Curso online", "Curso presencial",
    ]
    assert _titles(api.get("/api/opportunities/", params={"is_remote": True})) == ["Curso online"]


def test_busca_livre_ignora_acentos_e_maiusculas(api, db_session):
    make_opportunity(db_session, title="Audição", institution="Orquestra de Joaçaba")
    make_opportunity(db_session, title="Outra", institution="Filarmônica")

    response = api.get("/api/opportunities/", params={"q": "JOACABA"})

    assert _titles(response) == ["Audição"]


def test_match_so_aparece_para_quem_esta_logado(api, db_session):
    make_opportunity(db_session, llm_confidence=1.0)
    user = make_user(db_session)

    anonimo = api.get("/api/opportunities/").json()[0]
    logado = api.get("/api/opportunities/", headers=auth_headers(db_session, user)).json()[0]

    assert anonimo["match_percentage"] is None
    assert logado["match_percentage"] == 100
    assert logado["match_breakdown"]["instrument"] == 45


def test_detalhe_da_oportunidade(api, db_session):
    opp = make_opportunity(db_session, title="Detalhe")

    assert api.get(f"/api/opportunities/{opp.id}").json()["title"] == "Detalhe"
    assert api.get("/api/opportunities/999999").status_code == 404


def test_contagem_de_matches_do_perfil(api, db_session):
    make_opportunity(db_session, title="Compatível")
    make_opportunity(db_session, title="Outro instrumento", instruments=["Tuba"])
    user = make_user(db_session)

    response = api.get("/api/opportunities/matches/count", headers=auth_headers(db_session, user))

    assert response.json() == {"count": 1, "threshold": 85}
    assert api.get("/api/opportunities/matches/count").status_code == 401


def test_opcoes_de_filtro_se_restringem_umas_as_outras(api, db_session):
    make_opportunity(db_session, title="A", instruments=["Violino"], country="Brasil", state="SC", city="Joinville")
    make_opportunity(db_session, title="B", instruments=["Piano"], country="Alemanha", state=None, city="Berlim")

    tudo = api.get("/api/opportunities/filter-options").json()
    so_piano = api.get("/api/opportunities/filter-options", params={"instrument": "Piano"}).json()

    assert tudo["instruments"] == ["Piano", "Violino"]
    assert tudo["countries"] == ["Alemanha", "Brasil"]
    assert so_piano["countries"] == ["Alemanha"]
    assert so_piano["cities"] == ["Berlim"]
    # O próprio campo não se filtra: continua oferecendo os dois instrumentos.
    assert so_piano["instruments"] == ["Piano", "Violino"]
