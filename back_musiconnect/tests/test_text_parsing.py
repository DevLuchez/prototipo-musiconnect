"""
Validações de texto que o SonarCloud pediu para simplificar (expressões
regulares com risco de lentidão). Os testes garantem que a simplificação
não muda o que é aceito ou recusado.
"""

import pytest

from app.services.osm_contacts import extract_contacts
from app.services.wikidata_validator import _parse_wkt_point


# ── E-mail das tags do OpenStreetMap ─────────────────────────────────────

@pytest.mark.parametrize(
    "email",
    ["contato@escola.com.br", "mailto:info@orquestra.org", "a.b-c@sub.dominio.de"],
)
def test_emails_validos_sao_aceitos(email):
    _, result = extract_contacts({"email": email})
    assert result == email.removeprefix("mailto:")


@pytest.mark.parametrize(
    "email",
    ["sem-arroba.com", "dois@@arrobas.com", "sem@ponto", "com espaco@x.com", "a@.com", "a@b."],
)
def test_emails_invalidos_sao_descartados(email):
    _, result = extract_contacts({"email": email})
    assert result is None


def test_usa_o_primeiro_de_varios_emails():
    _, result = extract_contacts({"contact:email": "um@x.com; dois@y.com"})
    assert result == "um@x.com"


def test_site_sem_esquema_ganha_https():
    site, _ = extract_contacts({"website": "www.escola.com.br"})
    assert site == "https://www.escola.com.br"


# ── Coordenadas do Wikidata ("Point(lon lat)") ───────────────────────────

def test_ponto_do_wikidata_vira_lat_lon():
    assert _parse_wkt_point("Point(-46.63 -23.55)") == (-23.55, -46.63)
    assert _parse_wkt_point("point( 10 +20.5 )") == (20.5, 10.0)


def test_ponto_invalido_vira_none():
    assert _parse_wkt_point("Polygon((1 2, 3 4))") is None
    assert _parse_wkt_point("Point(abc def)") is None
