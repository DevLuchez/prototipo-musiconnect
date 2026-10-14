"""
Consentimento com a Política de privacidade no cadastro (LGPD).

O cadastro só é aceito com o consentimento explícito, e o backend guarda
quando e qual versão da política foi aceita — é a prova do consentimento.
"""

from datetime import datetime, timezone

import pytest
from pydantic import ValidationError

from app.models import User
from app.routers.auth import PRIVACY_POLICY_VERSION, _record_privacy_consent
from app.schemas import SignupIn

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


def test_consentimento_registra_data_e_versao_da_politica():
    user = User(email="aluna@example.com")
    now = datetime(2026, 10, 13, 12, 0, tzinfo=timezone.utc)

    _record_privacy_consent(user, now)

    assert user.privacy_accepted_at == now
    assert user.privacy_policy_version == PRIVACY_POLICY_VERSION
