"""
Fluxos de conta da API (/api/auth): cadastro, confirmação, login, perfil,
troca de senha, logout, esqueci a senha e exclusão de conta.
O envio de e-mail é sempre simulado — nenhum teste manda e-mail de verdade.
"""

import pytest

import app.routers.auth as auth_router
from app.models import User
from tests.helpers import SENHA, auth_headers, make_user

SIGNUP = {
    "email": "nova@example.com",
    "password": SENHA,
    "name": "Nova",
    "instruments": ["Piano"],
    "is_student": True,
    "country": "Brasil",
    "privacy_accepted": True,
}


@pytest.fixture
def sent_emails(monkeypatch):
    """Captura os e-mails que seriam enviados."""
    sent = []

    async def fake_confirmation(*, to_email, token):
        sent.append(("confirm", to_email, token))
        return True

    async def fake_reset(*, to_email, token):
        sent.append(("reset", to_email, token))
        return True

    monkeypatch.setattr(auth_router, "send_confirmation_email", fake_confirmation)
    monkeypatch.setattr(auth_router, "send_password_reset_email", fake_reset)
    return sent


def _user_by_email(db, email):
    return db.query(User).filter(User.email == email).first()


# ── Cadastro e confirmação ───────────────────────────────────────────────

def test_cadastro_cria_usuario_pendente_e_envia_confirmacao(api, db_session, sent_emails):
    response = api.post("/api/auth/signup", json=SIGNUP)

    assert response.status_code == 201
    user = _user_by_email(db_session, "nova@example.com")
    assert user.email_confirmed is False
    assert user.password_hash != SENHA  # nunca em texto puro
    assert sent_emails == [("confirm", "nova@example.com", user.confirmation_token)]


def test_cadastro_com_email_ja_confirmado_e_recusado(api, db_session, sent_emails):
    make_user(db_session, email="nova@example.com")

    assert api.post("/api/auth/signup", json=SIGNUP).status_code == 409


def test_refazer_cadastro_pendente_atualiza_os_dados(api, db_session, sent_emails):
    api.post("/api/auth/signup", json=SIGNUP)
    api.post("/api/auth/signup", json={**SIGNUP, "name": "Nome Corrigido"})

    assert db_session.query(User).filter(User.email == "nova@example.com").count() == 1
    assert _user_by_email(db_session, "nova@example.com").name == "Nome Corrigido"


def test_confirmar_pela_api_e_consultar_status(api, db_session, sent_emails):
    api.post("/api/auth/signup", json=SIGNUP)
    token = sent_emails[0][2]

    assert api.get("/api/auth/status", params={"email": "nova@example.com"}).json() == {"confirmed": False}
    assert api.post("/api/auth/confirm", json={"token": token}).json()["status"] == "confirmed"
    assert api.get("/api/auth/status", params={"email": "nova@example.com"}).json() == {"confirmed": True}
    # O link só funciona uma vez.
    assert api.post("/api/auth/confirm", json={"token": token}).status_code == 400


def test_reenviar_confirmacao(api, db_session, sent_emails):
    api.post("/api/auth/signup", json=SIGNUP)

    response = api.post("/api/auth/resend", json={"email": "nova@example.com"})

    assert response.status_code == 200
    assert len(sent_emails) == 2
    assert sent_emails[0][2] != sent_emails[1][2]  # token novo
    assert api.post("/api/auth/resend", json={"email": "ninguem@example.com"}).status_code == 404


def test_reenviar_ou_confirmar_conta_ja_confirmada(api, db_session, sent_emails):
    api.post("/api/auth/signup", json=SIGNUP)
    token = sent_emails[0][2]
    api.post("/api/auth/confirm", json={"token": token})

    assert api.post("/api/auth/resend", json={"email": "nova@example.com"}).status_code == 409
    user = _user_by_email(db_session, "nova@example.com")
    # Mesmo token de novo (ainda guardado): responde "já confirmado", sem erro
    user.confirmation_token = token
    db_session.commit()
    assert api.post("/api/auth/confirm", json={"token": token}).json()["status"] == "already_confirmed"


def test_status_de_email_sem_cadastro(api):
    assert api.get("/api/auth/status", params={"email": "ninguem@example.com"}).status_code == 404


# ── Login, sessão e perfil ───────────────────────────────────────────────

def test_login_devolve_token_que_abre_o_perfil(api, db_session):
    make_user(db_session)

    response = api.post("/api/auth/login", json={"email": "aluna@example.com", "password": SENHA})

    assert response.status_code == 200
    token = response.json()["token"]
    me = api.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 200
    assert me.json()["email"] == "aluna@example.com"


def test_login_com_senha_errada_ou_email_inexistente_da_a_mesma_resposta(api, db_session):
    make_user(db_session)

    errada = api.post("/api/auth/login", json={"email": "aluna@example.com", "password": "Errada#1"})
    inexistente = api.post("/api/auth/login", json={"email": "x@example.com", "password": SENHA})

    assert errada.status_code == inexistente.status_code == 401
    assert errada.json() == inexistente.json()  # não revela quais e-mails existem


def test_login_sem_confirmar_o_email_e_recusado(api, db_session):
    make_user(db_session, email_confirmed=False)

    response = api.post("/api/auth/login", json={"email": "aluna@example.com", "password": SENHA})

    assert response.status_code == 403


def test_rotas_logadas_exigem_token_valido(api):
    assert api.get("/api/auth/me").status_code == 401
    assert api.get("/api/auth/me", headers={"Authorization": "Bearer invalido"}).status_code == 401


def test_editar_perfil(api, db_session):
    user = make_user(db_session)
    headers = auth_headers(db_session, user)

    response = api.patch(
        "/api/auth/me",
        headers=headers,
        json={"name": "Novo Nome", "instruments": ["Flauta"], "is_professional": True, "country": "Brasil"},
    )

    assert response.status_code == 200
    assert response.json()["name"] == "Novo Nome"
    assert response.json()["instruments"] == ["Flauta"]


def test_logout_invalida_o_token(api, db_session):
    user = make_user(db_session)
    headers = auth_headers(db_session, user)

    assert api.post("/api/auth/logout", headers=headers).status_code == 200
    assert api.get("/api/auth/me", headers=headers).status_code == 401


# ── Senha ────────────────────────────────────────────────────────────────

def test_trocar_senha_logada_gera_novo_token(api, db_session):
    user = make_user(db_session)
    headers = auth_headers(db_session, user)

    errada = api.post(
        "/api/auth/change-password", headers=headers,
        json={"current_password": "Errada#1", "new_password": "NovaSenha#1"},
    )
    certa = api.post(
        "/api/auth/change-password", headers=headers,
        json={"current_password": SENHA, "new_password": "NovaSenha#1"},
    )

    assert errada.status_code == 401
    assert certa.status_code == 200
    assert api.get("/api/auth/me", headers=headers).status_code == 401  # token antigo morreu
    novo = {"Authorization": f"Bearer {certa.json()['token']}"}
    assert api.get("/api/auth/me", headers=novo).status_code == 200


def test_esqueci_a_senha_responde_igual_exista_ou_nao_o_email(api, db_session, sent_emails):
    make_user(db_session)

    existe = api.post("/api/auth/forgot-password", json={"email": "aluna@example.com"})
    nao_existe = api.post("/api/auth/forgot-password", json={"email": "x@example.com"})

    assert existe.json() == nao_existe.json()
    assert [kind for kind, *_ in sent_emails] == ["reset"]  # só para quem existe


def test_redefinir_senha_pela_api(api, db_session, sent_emails):
    make_user(db_session)
    api.post("/api/auth/forgot-password", json={"email": "aluna@example.com"})
    token = sent_emails[0][2]

    assert api.post("/api/auth/reset-password", json={"token": token, "password": "NovaSenha#1"}).status_code == 200
    login = api.post("/api/auth/login", json={"email": "aluna@example.com", "password": "NovaSenha#1"})
    assert login.status_code == 200
    assert api.post("/api/auth/reset-password", json={"token": token, "password": "Outra#123"}).status_code == 400


# ── Exclusão de conta ────────────────────────────────────────────────────

def test_excluir_conta_exige_a_senha(api, db_session):
    user = make_user(db_session)
    headers = auth_headers(db_session, user)

    errada = api.request("DELETE", "/api/auth/me", headers=headers, json={"password": "Errada#1"})
    assert errada.status_code == 401
    assert _user_by_email(db_session, "aluna@example.com") is not None

    certa = api.request("DELETE", "/api/auth/me", headers=headers, json={"password": SENHA})
    assert certa.status_code == 200
    assert _user_by_email(db_session, "aluna@example.com") is None
