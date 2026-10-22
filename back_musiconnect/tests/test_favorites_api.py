"""
Favoritos (/api/favorites): oportunidades salvas e instituições favoritas.
Salvar e remover são idempotentes; salvas vencidas somem da lista.
"""

from datetime import date, timedelta

from tests.helpers import auth_headers, make_institution, make_opportunity, make_user


def test_salvar_listar_e_remover_oportunidade(api, db_session):
    opp = make_opportunity(db_session, title="Salva", llm_confidence=1.0)
    headers = auth_headers(db_session, make_user(db_session))
    url = f"/api/favorites/opportunities/{opp.id}"

    assert api.put(url, headers=headers).status_code == 204
    assert api.put(url, headers=headers).status_code == 204  # salvar de novo não duplica

    salvas = api.get("/api/favorites/opportunities", headers=headers).json()
    assert [o["title"] for o in salvas] == ["Salva"]
    assert salvas[0]["saved_at"] is not None
    assert salvas[0]["match_percentage"] == 100
    assert api.get("/api/favorites/ids", headers=headers).json()["opportunities"] == [opp.id]

    assert api.delete(url, headers=headers).status_code == 204
    assert api.delete(url, headers=headers).status_code == 204  # remover de novo não dá erro
    assert api.get("/api/favorites/opportunities", headers=headers).json() == []


def test_salvar_oportunidade_inexistente_da_404(api, db_session):
    headers = auth_headers(db_session, make_user(db_session))

    assert api.put("/api/favorites/opportunities/999999", headers=headers).status_code == 404


def test_salva_vencida_some_da_lista(api, db_session):
    opp = make_opportunity(db_session, title="Vai vencer", deadline=date.today() + timedelta(days=1))
    headers = auth_headers(db_session, make_user(db_session))
    api.put(f"/api/favorites/opportunities/{opp.id}", headers=headers)

    opp.deadline = date.today() - timedelta(days=1)
    db_session.commit()

    assert api.get("/api/favorites/opportunities", headers=headers).json() == []
    assert api.get("/api/favorites/ids", headers=headers).json()["opportunities"] == []


def test_favoritos_sao_de_cada_usuario(api, db_session):
    opp = make_opportunity(db_session)
    ana = auth_headers(db_session, make_user(db_session, email="ana@example.com"), token="t-ana")
    bia = auth_headers(db_session, make_user(db_session, email="bia@example.com"), token="t-bia")

    api.put(f"/api/favorites/opportunities/{opp.id}", headers=ana)

    assert api.get("/api/favorites/ids", headers=bia).json()["opportunities"] == []


def test_favoritar_instituicao_com_contagem_de_oportunidades(api, db_session):
    make_institution(db_session, osm_id="node_42", name="Conservatório")
    make_opportunity(db_session, institution_id="node_42")
    headers = auth_headers(db_session, make_user(db_session))

    assert api.put("/api/favorites/institutions/node_42", headers=headers).status_code == 204
    favoritas = api.get("/api/favorites/institutions", headers=headers).json()

    assert [i["name"] for i in favoritas] == ["Conservatório"]
    assert favoritas[0]["active_opportunities_count"] == 1
    assert api.get("/api/favorites/ids", headers=headers).json()["institutions"] == ["node_42"]

    assert api.delete("/api/favorites/institutions/node_42", headers=headers).status_code == 204
    assert api.get("/api/favorites/institutions", headers=headers).json() == []


def test_favoritar_instituicao_inexistente_da_404(api, db_session):
    headers = auth_headers(db_session, make_user(db_session))

    assert api.put("/api/favorites/institutions/nao_existe", headers=headers).status_code == 404


def test_favoritos_exigem_login(api):
    assert api.get("/api/favorites/ids").status_code == 401
