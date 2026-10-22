"""
Leitura da página de detalhe de um anúncio do Musical Chairs
(_parse_detail_page). HTML reduzido ao essencial da estrutura real do site;
nenhum teste acessa a rede.
"""

from datetime import date

from app.services.scrapers.musical_chairs_scraper import _parse_detail_page

# Vaga de emprego: post_item_name embrulha um <h2> com a instituição.
JOB_PAGE = """
<div class="post_item_name"><h2>Tampere Philharmonic Orchestra</h2></div>
<h1 class="post_item_info">Principal Cello</h1>
<div class="post_item_location">Tampere, Finland</div>
<div class="post_item_closingdate">Closing date: 01 Dec 2026</div>
<div class="post_item_desc">The orchestra seeks a principal cellist.</div>
"""

# Competição: post_item_name é o <h1> (título), sem instituição na página.
COMPETITION_PAGE = """
<div class="post_item_name"><h1>International Piano Competition</h1></div>
<div class="post_item_location">Leeds, United Kingdom</div>
"""


def test_pagina_de_vaga_extrai_todos_os_campos():
    result = _parse_detail_page(JOB_PAGE)

    assert result["institution"] == "Tampere Philharmonic Orchestra"
    assert result["location_raw"] == "Tampere, Finland"
    assert result["deadline"] == date(2026, 12, 1)
    assert result["description"] == "The orchestra seeks a principal cellist."


def test_pagina_de_competicao_nao_inventa_instituicao():
    result = _parse_detail_page(COMPETITION_PAGE)

    assert result["institution"] is None
    assert result["location_raw"] == "Leeds, United Kingdom"
    assert result["deadline"] is None


def test_pagina_sem_os_campos_esperados_nao_quebra():
    # Se o site mudar o HTML, o scraper segue em frente com campos vazios.
    result = _parse_detail_page("<html><body><p>Página nova</p></body></html>")

    assert result == {
        "institution": None,
        "location_raw": None,
        "deadline": None,
        "description": None,
    }


def test_prazo_em_formato_desconhecido_vira_none():
    result = _parse_detail_page(
        '<div class="post_item_closingdate">Closing date: em breve</div>'
    )

    assert result["deadline"] is None
