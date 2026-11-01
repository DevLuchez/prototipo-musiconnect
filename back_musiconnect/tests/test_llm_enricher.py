"""
Enriquecimento de oportunidades com o Gemini (services/llm_enricher.py):
leitura da resposta, normalização dos campos e o laço que processa as
oportunidades pendentes (com retry em 503 e desistência em 429).

O Gemini é sempre simulado — nenhum teste acessa a API nem gasta cota.
"""

import asyncio
import json
from datetime import date

import pytest

import app.services.llm_enricher as enricher
from app.models import Opportunity
from tests.helpers import make_opportunity


# ── Partes isoladas ──────────────────────────────────────────────────────

def test_prompt_traz_a_data_de_hoje_e_corta_o_texto_longo():
    prompt = enricher._build_prompt("x" * 5000)
    assert date.today().strftime("%d/%m/%Y") in prompt
    assert "x" * 3000 in prompt and "x" * 3001 not in prompt


def test_resposta_json_simples_e_com_markdown():
    assert enricher._parse_llm_response('{"title": "A"}') == {"title": "A"}
    assert enricher._parse_llm_response('```json\n{"title": "B"}\n```') == {"title": "B"}


def test_resposta_que_nao_e_json_vira_none():
    assert enricher._parse_llm_response("desculpe, não consegui") is None


@pytest.mark.parametrize(
    "raw,expected",
    [("15/01/2027", date(2027, 1, 15)), (" 01/02/2027 ", date(2027, 2, 1)),
     ("2027-01-15", None), ("", None), (None, None)],
)
def test_prazo_dd_mm_aaaa(raw, expected):
    assert enricher._parse_deadline(raw) == expected


@pytest.mark.parametrize(
    "raw,expected",
    [("violin", "Violino"), ("  Double Bass ", "Contrabaixo"), ("singer", "Vocal"),
     ("theremin", "Theremin"), ("Clarineta", "Clarinete"), ("Fagot", "Fagote"),
     ("Tpa", "Trompa"), ("Tímpani", "Tímpanos"), ("CLARINETE", "Clarinete"),
     ("Gaita De Fole", "Gaita de Fole"), ("viola da gamba", "Viola da Gamba"),
     ("Jazz", None), ("Câmara", None), ("", None)],
)
def test_instrumentos_em_portugues(raw, expected):
    assert enricher._normalize_instrument(raw) == expected


def test_instrumento_fora_da_lista_vai_para_o_log(caplog):
    enricher._normalize_instrument("theremin")
    assert "Instrumento fora da lista: 'theremin'" in caplog.text


def test_lista_normalizada_sem_repetidos_nem_generos():
    assert enricher.normalize_instruments(
        ["Clarinete", "Clarineta", "clarinet", "Jazz", None, "Oboe"]
    ) == ["Clarinete", "Oboé"]


def test_prompt_pede_os_nomes_oficiais_e_o_titulo_em_portugues():
    prompt = enricher._build_prompt("Audition: Tutti Cello")
    assert "Clarinete, Clarone" in prompt
    assert "Só o NOME da organização" in prompt
    assert "Audition, Fellowship" in prompt


def _opp(**fields):
    base = dict(title="Original", type=None, instruments=None, level=None, deadline=None,
                institution=None, country=None, state=None, city=None,
                is_remote=False, is_active=True)
    base.update(fields)
    return Opportunity(**base)


def test_aplica_os_campos_extraidos():
    opp = _opp()
    enricher._apply_enrichment(opp, {
        "title": "Audição de violino", "description": "Vaga na orquestra.",
        "type": "audicao", "instruments": ["violin", "Piano"], "level": "profissional",
        "deadline": "15/01/2027", "institution": "Orquestra X",
        "institution_category": "music_org", "country": "Alemanha", "city": "Berlim",
        "is_remote": False, "is_active": True, "is_music_related": True,
        "llm_confidence": 0.9,
    })
    assert opp.title == "Audição de violino"
    assert opp.instruments == ["Violino", "Piano"]
    assert opp.deadline == date(2027, 1, 15)
    assert opp.institution_category == "music_org"
    assert opp.llm_confidence == 0.9
    assert opp.enriched_at is not None


def test_dados_do_scraper_prevalecem_sobre_o_palpite_do_llm():
    opp = _opp(type="curso", deadline=date(2026, 12, 1), institution="Conservatório Y")
    enricher._apply_enrichment(opp, {
        "type": "audicao", "deadline": "15/01/2027", "institution": "Outra",
    })
    assert opp.type == "curso"
    assert opp.deadline == date(2026, 12, 1)
    assert opp.institution == "Conservatório Y"


def test_categoria_invalida_e_descartada_e_nao_musical_e_desativada():
    opp = _opp()
    enricher._apply_enrichment(opp, {"institution_category": "restaurante",
                                     "is_music_related": False})
    assert opp.institution_category is None
    assert opp.is_active is False
    assert opp.llm_confidence == 0.5  # padrão quando o LLM não informa


# ── Laço de enriquecimento (Gemini simulado) ─────────────────────────────

class _FakeResponse:
    def __init__(self, text):
        self.text = text


class _FakeGemini:
    """Responde em ordem a fila `replies`: texto vira resposta, exceção é levantada."""

    def __init__(self, replies):
        self.replies = list(replies)
        self.calls = 0
        self.used_models = []
        self.models = self

    def generate_content(self, model, contents):
        self.calls += 1
        self.used_models.append(model)
        reply = self.replies.pop(0)
        if isinstance(reply, Exception):
            raise reply
        return _FakeResponse(reply)


@pytest.fixture
def gemini(monkeypatch, db_session):
    """Instala um Gemini simulado; `gemini(replies)` define as respostas."""
    holder = {}
    sleeps = []

    async def no_sleep(seconds):
        sleeps.append(seconds)

    def install(replies):
        holder["client"] = _FakeGemini(replies)
        return holder["client"]

    monkeypatch.setattr(enricher.settings, "gemini_api_key", "chave-teste")
    monkeypatch.setattr(enricher.genai, "Client", lambda api_key: holder["client"])
    monkeypatch.setattr(enricher, "SessionLocal", lambda: db_session)
    monkeypatch.setattr(enricher.asyncio, "sleep", no_sleep)
    install.sleeps = sleeps
    return install


def _ok(**fields):
    data = {"title": "Título traduzido", "is_music_related": True, "llm_confidence": 0.92}
    data.update(fields)
    return json.dumps(data)


def _run():
    return asyncio.run(enricher.enrich_opportunities())


def test_sem_chave_do_gemini_nao_processa(monkeypatch):
    monkeypatch.setattr(enricher.settings, "gemini_api_key", None)
    assert _run() == {"error": "GEMINI_API_KEY não configurada", "processed": 0}


def test_processa_so_as_pendentes_com_texto(db_session, gemini):
    pendente = make_opportunity(db_session, title="Pendente", raw_text="texto do edital")
    make_opportunity(db_session, title="Sem texto", raw_text=None)
    make_opportunity(db_session, title="Já feita", raw_text="x",
                     enriched_at=enricher._utc_now())
    pendente_id = pendente.id
    client = gemini([_ok(title="Audição traduzida")])

    stats = _run()

    assert client.calls == 1
    assert stats == {"total_pending": 1, "processed": 1, "success": 1, "failed": 0}
    opp = db_session.get(Opportunity, pendente_id)
    assert opp.title == "Audição traduzida"
    assert opp.enriched_at is not None


@pytest.mark.parametrize(
    "text,expected",
    [("Audition for a Tutti Cello position in the Netherlands.", True),
     ("Audição para Tutti Violoncelo na Phion, em Arnhem.", False),
     ("Verbier Festival Junior Orchestra 2027 - Clarinete", False),
     ("Global Young Musicians Competition", False), (None, False)],
)
def test_detecta_texto_em_ingles(text, expected):
    assert enricher._looks_english(text) is expected


def test_resposta_em_ingles_pede_de_novo_em_portugues(db_session, gemini):
    opp_id = make_opportunity(db_session, raw_text="Audition: Tutti Cello").id
    client = gemini([
        _ok(title="Audição para Tutti Violoncelo",
            description="Audition for a Tutti Cello position in the Netherlands."),
        _ok(title="Audição para Tutti Violoncelo",
            description="Audição para Tutti Violoncelo nos Países Baixos."),
    ])

    _run()

    assert client.calls == 2
    assert db_session.get(Opportunity, opp_id).description == (
        "Audição para Tutti Violoncelo nos Países Baixos.")


def test_se_continuar_em_ingles_fica_com_a_primeira_resposta(db_session, gemini):
    opp_id = make_opportunity(db_session, raw_text="Audition: Tutti Cello").id
    english = "Audition for a Tutti Cello position in the Netherlands."
    client = gemini([_ok(description=english), _ok(description=english)])

    _run()

    assert client.calls == 2
    assert db_session.get(Opportunity, opp_id).description == english


def test_padroniza_os_instrumentos_das_ja_enriquecidas(db_session, gemini):
    antiga = make_opportunity(db_session, raw_text="x", enriched_at=enricher._utc_now(),
                              instruments=["Clarineta", "Jazz", "Fagot"])
    certa = make_opportunity(db_session, raw_text="x", enriched_at=enricher._utc_now(),
                             instruments=["Violino"])
    antiga_id, certa_id = antiga.id, certa.id
    client = gemini([])

    _run()

    assert client.calls == 0
    assert db_session.get(Opportunity, antiga_id).instruments == ["Clarinete", "Fagote"]
    assert db_session.get(Opportunity, certa_id).instruments == ["Violino"]


def test_resposta_ilegivel_marca_como_processada_com_confianca_zero(db_session, gemini):
    opp_id = make_opportunity(db_session, raw_text="texto").id
    gemini(["não é JSON"])

    stats = _run()

    assert stats["failed"] == 1
    opp = db_session.get(Opportunity, opp_id)
    assert opp.llm_confidence == 0.0
    assert opp.enriched_at is not None  # não tenta de novo a cada execução


def test_503_tenta_de_novo_uma_vez(db_session, gemini):
    make_opportunity(db_session, raw_text="texto")
    client = gemini([RuntimeError("503 UNAVAILABLE"), _ok()])

    stats = _run()

    assert client.calls == 2
    assert stats["success"] == 1
    assert 10 in gemini.sleeps


def test_503_persistente_conta_como_falha_e_continua(db_session, gemini):
    make_opportunity(db_session, title="A", raw_text="texto")
    make_opportunity(db_session, title="B", raw_text="texto")
    gemini([RuntimeError("503"), RuntimeError("503"), _ok()])

    stats = _run()

    assert stats["failed"] == 1 and stats["success"] == 1


def test_429_espera_o_tempo_pedido_e_deixa_a_oportunidade_para_depois(db_session, gemini):
    opp_id = make_opportunity(db_session, raw_text="texto").id
    gemini([RuntimeError('429 RESOURCE_EXHAUSTED retryDelay: "30s"')])

    stats = _run()

    assert stats["failed"] == 1
    assert 35 in gemini.sleeps  # retryDelay + 5s de margem
    # Continua pendente: será tentada na próxima execução
    assert db_session.get(Opportunity, opp_id).enriched_at is None


def test_429_sem_tempo_informado_espera_um_minuto(db_session, gemini):
    make_opportunity(db_session, raw_text="texto")
    gemini([RuntimeError("429 quota")])

    _run()

    assert 60 in gemini.sleeps


_DAILY_429 = RuntimeError(
    "429 RESOURCE_EXHAUSTED quotaId: GenerateRequestsPerDayPerProjectPerModel-FreeTier")


def test_cota_diaria_do_flash_segue_com_o_lite_sem_esperar(db_session, gemini):
    make_opportunity(db_session, title="A", raw_text="texto")
    make_opportunity(db_session, title="B", raw_text="texto")
    client = gemini([_ok(), _DAILY_429, _ok()])

    stats = _run()

    assert stats["success"] == 2
    assert client.used_models == [
        "gemini-3.5-flash", "gemini-3.5-flash", "gemini-3.5-flash-lite"]
    assert 60 not in gemini.sleeps


def test_cota_diaria_de_todos_esgotada_deixa_o_resto_para_depois(db_session, gemini):
    ids = [make_opportunity(db_session, title=t, raw_text="texto").id for t in "ABC"]
    client = gemini([_DAILY_429, _DAILY_429])

    stats = _run()

    assert client.calls == 2  # não tenta as outras: a cota só volta amanhã
    assert stats["success"] == 0
    assert all(db_session.get(Opportunity, i).enriched_at is None for i in ids)


def test_outro_erro_conta_como_falha(db_session, gemini):
    make_opportunity(db_session, raw_text="texto")
    gemini([ValueError("erro inesperado")])

    assert _run()["failed"] == 1
