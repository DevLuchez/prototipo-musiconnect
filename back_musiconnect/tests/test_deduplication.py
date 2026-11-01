"""
Observação de repetidas entre fontes (services/deduplication.py): só
registra no log os pares suspeitos — nada muda no app até a decisão de 07/11.
"""

from datetime import date, timedelta

from app.models import Opportunity
from app.services import deduplication as dd
from tests.helpers import make_opportunity

PRAZO = date.today() + timedelta(days=20)


def _opp(db, source, title, institution=None, **fields):
    data = dict(source_name=source, title=title, institution=institution, deadline=PRAZO,
                enriched_at=date.today(), source_url=f"https://x/{source}/{title}")
    data.update(fields)
    return make_opportunity(db, **data)


def test_palavras_distintivas():
    assert dd.name_words("Concurso Internacional de Piano Karol Szymanowski") == {"karol", "szymanowski"}
    assert dd.name_words(None) == set()


def test_registra_so_os_pares_de_fontes_diferentes(db_session, caplog):
    mc = _opp(db_session, "Musical Chairs", "Concurso Internacional de Música Karol Szymanowski")
    wf = _opp(db_session, "Revista CONCERTO", "Karol Szymanowski Music Competition")
    # Duas audições de violino diferentes com o mesmo prazo: não confunde.
    _opp(db_session, "Musical Chairs", "Audição para Violino Tutti", "Orquestra Sinfônica de Lahti")
    _opp(db_session, "Revista CONCERTO", "Audição para Violino Tutti", "Orquestra Sinfônica Municipal de São Paulo")
    # Prazo diferente: não é a mesma.
    _opp(db_session, "WFIMC", "Karol Szymanowski Competition", deadline=PRAZO + timedelta(days=1))
    # Escondidas não entram.
    _opp(db_session, "WFIMC", "Karol Szymanowski Competition hidden", is_active=False)
    _opp(db_session, "SCAR", "Karol Szymanowski low", llm_confidence=0.5)
    _opp(db_session, "FEMUSC", "Karol Szymanowski raw", enriched_at=None)

    pairs = dd.report_cross_source_duplicates(db_session)

    assert [(a.id, b.id) for a, b in pairs] == [(mc.id, wf.id)]
    assert "1 pares suspeitos" in caplog.text
    assert all(o.is_active for o in (mc, wf))  # só observa
    assert db_session.query(Opportunity).filter_by(is_active=False).count() == 1


def test_mesma_fonte_nao_conta(db_session):
    _opp(db_session, "Musical Chairs", "Karol Szymanowski Competition")
    _opp(db_session, "Musical Chairs", "Karol Szymanowski Competition (outra edição)")

    assert dd.report_cross_source_duplicates(db_session) == []


def test_prazos_diferentes_nunca_sao_a_mesma():
    a = Opportunity(title="Karol Szymanowski Competition", deadline=PRAZO)
    b = Opportunity(title="Karol Szymanowski Competition", deadline=PRAZO + timedelta(days=1))
    sem_prazo = Opportunity(title="Karol Szymanowski Competition", deadline=None)
    assert dd.looks_same(a, b) is False
    assert dd.looks_same(sem_prazo, sem_prazo) is False
