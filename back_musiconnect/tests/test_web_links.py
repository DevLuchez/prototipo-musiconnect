"""
Páginas abertas pelos links dos e-mails quando o app NÃO está instalado
(ex: e-mail lido no computador). Confirmam o cadastro ou trocam a senha
direto no navegador.
"""

from datetime import datetime, timedelta, timezone

from app.models import User
from app.routers.auth import _verify_password

NOVA_SENHA = "NovaSenha#1"


def _user(db, **fields):
    user = User(
        email=fields.pop("email", "aluna@example.com"),
        password_hash="hash-antigo",
        name="Aluna",
        **fields,
    )
    db.add(user)
    db.commit()
    return user


# ── Confirmação de cadastro ──────────────────────────────────────────────

def test_pagina_de_confirmacao_mostra_botao_sem_confirmar_ainda(api, db_session):
    user = _user(db_session, confirmation_token="tok-conf")

    response = api.get("/confirmar", params={"token": "tok-conf"})

    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]
    assert "Confirmar" in response.text
    db_session.refresh(user)
    # Só abrir o link não confirma (leitores de e-mail às vezes "visitam" links).
    assert user.email_confirmed is False


def test_confirmar_pela_pagina_confirma_o_cadastro(api, db_session):
    user = _user(db_session, confirmation_token="tok-conf")

    response = api.post("/confirmar", data={"token": "tok-conf"})

    assert response.status_code == 200
    assert "confirmado" in response.text.lower()
    db_session.refresh(user)
    assert user.email_confirmed is True
    assert user.confirmation_token is None


def test_confirmar_com_token_invalido_mostra_erro(api, db_session):
    response = api.post("/confirmar", data={"token": "nao-existe"})

    assert response.status_code == 400
    assert "inválido" in response.text.lower()


# ── Redefinição de senha ─────────────────────────────────────────────────

def _user_com_reset(db, sent_minutes_ago=5):
    return _user(
        db,
        email_confirmed=True,
        session_token="sessao-ativa",
        password_reset_token="tok-reset",
        password_reset_sent_at=datetime.now(timezone.utc)
        - timedelta(minutes=sent_minutes_ago),
    )


def test_pagina_de_redefinicao_mostra_formulario(api, db_session):
    _user_com_reset(db_session)

    response = api.get("/redefinir-senha", params={"token": "tok-reset"})

    assert response.status_code == 200
    assert 'type="password"' in response.text


def test_redefinir_pela_pagina_troca_a_senha(api, db_session):
    user = _user_com_reset(db_session)

    response = api.post(
        "/redefinir-senha",
        data={"token": "tok-reset", "password": NOVA_SENHA, "password_confirm": NOVA_SENHA},
    )

    assert response.status_code == 200
    assert "alterada" in response.text.lower()
    db_session.refresh(user)
    assert _verify_password(NOVA_SENHA, user.password_hash)
    assert user.password_reset_token is None
    # Trocar a senha encerra as sessões abertas.
    assert user.session_token is None


def test_redefinir_com_senhas_diferentes_nao_troca(api, db_session):
    user = _user_com_reset(db_session)

    response = api.post(
        "/redefinir-senha",
        data={"token": "tok-reset", "password": NOVA_SENHA, "password_confirm": "Outra#123"},
    )

    assert response.status_code == 400
    db_session.refresh(user)
    assert user.password_hash == "hash-antigo"


def test_redefinir_com_senha_fraca_nao_troca(api, db_session):
    user = _user_com_reset(db_session)

    response = api.post(
        "/redefinir-senha",
        data={"token": "tok-reset", "password": "fraca", "password_confirm": "fraca"},
    )

    assert response.status_code == 400
    db_session.refresh(user)
    assert user.password_hash == "hash-antigo"


def test_redefinir_com_link_expirado_nao_troca(api, db_session):
    user = _user_com_reset(db_session, sent_minutes_ago=31)

    response = api.post(
        "/redefinir-senha",
        data={"token": "tok-reset", "password": NOVA_SENHA, "password_confirm": NOVA_SENHA},
    )

    assert response.status_code == 400
    assert "expirou" in response.text.lower()
    db_session.refresh(user)
    assert user.password_hash == "hash-antigo"
