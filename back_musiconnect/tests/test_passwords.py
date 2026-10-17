"""
Regra de senha forte — a mesma do app (AuthPasswordRequirements, em
auth_common.dart): 8+ caracteres e pelo menos 2 destes 3 critérios:
maiúscula e minúscula, número, caractere especial.
"""

import pytest

from app.services.passwords import is_strong_password


@pytest.mark.parametrize(
    "password",
    [
        "Senha123",    # maiúscula/minúscula + número
        "senha#123",   # número + especial
        "SenhaForte!", # maiúscula/minúscula + especial
    ],
)
def test_senhas_fortes_sao_aceitas(password):
    assert is_strong_password(password)


@pytest.mark.parametrize(
    "password",
    [
        "Ab1#",        # curta demais
        "senhasenha",  # só minúsculas
        "senha1234",   # só número a mais
        "SenhaSenha",  # só maiúscula/minúscula
    ],
)
def test_senhas_fracas_sao_recusadas(password):
    assert not is_strong_password(password)
