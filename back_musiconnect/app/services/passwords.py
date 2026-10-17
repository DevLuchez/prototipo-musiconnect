"""
Regra de senha forte — espelho de AuthPasswordRequirements.isValid
(front_musiconnect/lib/presentation/widgets/auth/auth_common.dart).
Atualizar os dois juntos se a regra mudar.

Válida: 8+ caracteres e pelo menos 2 destes 3 critérios — maiúscula e
minúscula, número, caractere especial.
"""

import re

_SPECIAL = re.compile(r"""[!@#$%^&*(),.?":{}|<>_\-+=/\\\[\];~`]""")


def is_strong_password(password: str) -> bool:
    if len(password) < 8:
        return False
    criteria = [
        bool(re.search(r"[a-z]", password)) and bool(re.search(r"[A-Z]", password)),
        bool(re.search(r"[0-9]", password)),
        bool(_SPECIAL.search(password)),
    ]
    return sum(criteria) >= 2
