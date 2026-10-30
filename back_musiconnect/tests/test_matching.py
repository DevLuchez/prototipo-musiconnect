"""
Percentual de compatibilidade (match) — services/matching.py.
Pesos: instrumento 45 · ramo x tipo 20 · localização 20 · confiança 15.
Testes de unidade puros (objetos em memória, sem banco).
"""

from app.models import Opportunity, User
from app.services.matching import compute_match_breakdown, compute_match_percentage


def _user(**fields):
    data = dict(
        instruments=["Violino"], is_student=True, is_professional=False,
        country="Brasil", state="SC", city="Jaraguá do Sul",
    )
    data.update(fields)
    return User(**data)


def _opp(**fields):
    data = dict(
        instruments=["Violino"], type="audicao", is_remote=False,
        country="Brasil", state="SC", city="Jaraguá do Sul", llm_confidence=1.0,
    )
    data.update(fields)
    return Opportunity(**data)


def test_combinacao_perfeita_da_100():
    assert compute_match_percentage(_user(), _opp()) == 100


def test_detalhamento_sempre_soma_o_total():
    b = compute_match_breakdown(
        _user(instruments=["Violino"]),
        _opp(instruments=["Violino", "Piano", "Flauta"], llm_confidence=0.83, state="SP", city="Campinas"),
    )
    assert b.instrument + b.affinity + b.location + b.confidence == b.total


# ── Instrumento (45) ─────────────────────────────────────────────────────

def test_instrumento_nao_comparar_maiusculas_nem_espacos():
    b = compute_match_breakdown(_user(instruments=[" violino "]), _opp(instruments=["VIOLINO"]))
    assert b.instrument == 45


def test_instrumento_parcial_proporcional():
    b = compute_match_breakdown(_user(instruments=["Violino"]), _opp(instruments=["Violino", "Viola"]))
    assert b.instrument == 22  # metade de 45, arredondado


def test_sem_instrumento_em_comum_zera_o_fator():
    b = compute_match_breakdown(_user(instruments=["Piano"]), _opp(instruments=["Violino"]))
    assert b.instrument == 0


def test_oportunidade_sem_instrumento_exigido_vale_para_todos():
    b = compute_match_breakdown(_user(instruments=["Piano"]), _opp(instruments=[]))
    assert b.instrument == 45


# ── Ramo de atuação x tipo (20) ──────────────────────────────────────────

def test_emprego_pesa_menos_para_estudante():
    b = compute_match_breakdown(_user(is_student=True, is_professional=False), _opp(type="emprego"))
    assert b.affinity == 8  # 0.4 x 20


def test_vale_a_melhor_afinidade_entre_os_ramos():
    b = compute_match_breakdown(_user(is_student=True, is_professional=True), _opp(type="emprego"))
    assert b.affinity == 20


def test_tipo_acentuado_e_reconhecido():
    b = compute_match_breakdown(_user(), _opp(type="Competição"))
    assert b.affinity == 20


def test_tipo_desconhecido_ou_sem_ramo_fica_neutro():
    assert compute_match_breakdown(_user(), _opp(type="outro")).affinity == 10
    assert compute_match_breakdown(_user(is_student=False), _opp()).affinity == 10


# ── Localização (20) ─────────────────────────────────────────────────────

def test_localizacao_por_cidade_estado_pais():
    user = _user()
    assert compute_match_breakdown(user, _opp()).location == 20
    assert compute_match_breakdown(user, _opp(city="Joinville")).location == 12
    assert compute_match_breakdown(user, _opp(state="SP", city="Campinas")).location == 6
    assert compute_match_breakdown(
        user, _opp(country="Alemanha", state=None, city="Berlim")
    ).location == 0


def test_remota_vale_o_maximo_de_localizacao():
    b = compute_match_breakdown(_user(), _opp(is_remote=True, country="Alemanha", city="Berlim"))
    assert b.location == 20


def test_oportunidade_sem_local_fica_neutra():
    b = compute_match_breakdown(_user(), _opp(country=None, state=None, city=None))
    assert b.location == 10


# ── Confiança da extração (15) ───────────────────────────────────────────

def test_confianca_proporcional_e_limitada():
    assert compute_match_breakdown(_user(), _opp(llm_confidence=0.8)).confidence == 12
    assert compute_match_breakdown(_user(), _opp(llm_confidence=None)).confidence == 0
    assert compute_match_breakdown(_user(), _opp(llm_confidence=1.7)).confidence == 15


def test_oportunidade_sem_tipo_tem_afinidade_neutra():
    sem_tipo = compute_match_breakdown(_user(is_student=True), _opp(type=None))
    tipo_desconhecido = compute_match_breakdown(_user(is_student=True), _opp(type="outro"))

    assert sem_tipo.affinity == tipo_desconhecido.affinity  # neutro: metade do peso
