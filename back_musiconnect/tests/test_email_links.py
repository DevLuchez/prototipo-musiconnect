"""
Links dos e-mails de confirmação e de redefinição de senha.

São links https no domínio do app (o Gmail remove links musiconnect://).
Com o app instalado, o Android abre o app direto (App Links); sem o app,
abrem as páginas do próprio backend.
"""

import json

from app.config import settings
from app.services.email_service import (
    build_confirmation_link,
    build_reset_password_link,
)


def test_link_de_confirmacao_e_https_no_dominio_do_app():
    assert build_confirmation_link("abc") == "https://musiconnect.app.br/confirmar?token=abc"


def test_link_de_redefinicao_e_https_no_dominio_do_app():
    assert (
        build_reset_password_link("abc")
        == "https://musiconnect.app.br/redefinir-senha?token=abc"
    )


def test_assetlinks_autoriza_o_app_android(api):
    response = api.get("/.well-known/assetlinks.json")

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("application/json")
    statement = json.loads(response.text)[0]
    assert statement["relation"] == ["delegate_permission/common.handle_all_urls"]
    target = statement["target"]
    assert target["namespace"] == "android_app"
    assert target["package_name"] == settings.android_package_name
    assert target["sha256_cert_fingerprints"]
    for fingerprint in target["sha256_cert_fingerprints"]:
        # Formato exigido pelo Android: 32 pares hexadecimais separados por ":".
        assert len(fingerprint.split(":")) == 32
