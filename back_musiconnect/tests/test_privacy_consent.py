"""
Consentimento com a Política de privacidade (LGPD): no cadastro e no novo
aceite de quem já tem conta quando a política muda.

O cadastro só é aceito com o consentimento explícito, e o backend guarda
quando e qual versão da política foi aceita — é a prova do consentimento.
"""

from datetime import datetime, timezone

import pytest
from pydantic import ValidationError

from app.models import User
from app.routers.auth import LEGACY_PRIVACY_POLICY_VERSION, _record_privacy_consent
from app.schemas import SignupIn
from tests.helpers import auth_headers, make_user

_SIGNUP = {
    "email": "aluna@example.com",
    "password": "Senha#123",
    "name": "Aluna",
}


def test_signup_sem_consentimento_e_recusado():
    with pytest.raises(ValidationError):
        SignupIn(**_SIGNUP)


def test_signup_com_consentimento_negado_e_recusado():
    with pytest.raises(ValidationError):
        SignupIn(**_SIGNUP, privacy_accepted=False)


def test_signup_com_consentimento_e_aceito():
    data = SignupIn(**_SIGNUP, privacy_accepted=True)
    assert data.privacy_accepted is True


def test_consentimento_registra_data_e_a_versao_que_o_app_mostrou():
    user = User(email="aluna@example.com")
    now = datetime(2026, 10, 13, 12, 0, tzinfo=timezone.utc)

    _record_privacy_consent(user, now, "2026-11-05")

    assert user.privacy_accepted_at == now
    assert user.privacy_policy_version == "2026-11-05"


def test_app_antigo_sem_versao_registra_a_que_ele_mostra():
    user = User(email="aluna@example.com")

    _record_privacy_consent(user, datetime.now(timezone.utc))

    assert user.privacy_policy_version == LEGACY_PRIVACY_POLICY_VERSION == "2026-10-30"


def test_versao_em_formato_invalido_e_recusada():
    with pytest.raises(ValidationError):
        SignupIn(**_SIGNUP, privacy_accepted=True, privacy_policy_version="ontem")


# ── Novo aceite quando a política muda ───────────────────────────────────

def test_perfil_informa_a_versao_aceita(api, db_session):
    user = make_user(db_session, privacy_policy_version="2026-10-13")

    me = api.get("/api/auth/me", headers=auth_headers(db_session, user))

    assert me.json()["privacy_policy_version"] == "2026-10-13"


def test_novo_aceite_registra_a_versao_que_o_app_mostrou(api, db_session):
    user = make_user(db_session, privacy_policy_version="2026-10-13")

    response = api.post("/api/auth/accept-privacy", headers=auth_headers(db_session, user),
                        json={"privacy_policy_version": "2026-10-31"})

    assert response.status_code == 200
    assert response.json()["privacy_policy_version"] == "2026-10-31"
    db_session.refresh(user)
    assert user.privacy_policy_version == "2026-10-31"
    assert user.privacy_accepted_at is not None


def test_novo_aceite_pelo_app_antigo_sem_versao(api, db_session):
    user = make_user(db_session, privacy_policy_version="2026-10-13")

    response = api.post("/api/auth/accept-privacy", headers=auth_headers(db_session, user))

    assert response.json()["privacy_policy_version"] == LEGACY_PRIVACY_POLICY_VERSION


def test_novo_aceite_exige_login(api):
    assert api.post("/api/auth/accept-privacy").status_code == 401
