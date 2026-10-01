"""
Cálculo do percentual de compatibilidade (match) entre um usuário e uma
oportunidade, exibido na aba Matcher do Flutter.

Heurística de filtragem baseada em conteúdo (não é ML de verdade — é o
placeholder pragmático pro "Score de Compatibilidade" idealizado no TCC,
usando só os campos que já existem hoje nos dois lados):

  - Instrumento (peso 45%): sobreposição entre os instrumentos do usuário
    e os exigidos pela oportunidade.
  - Ramo de atuação x tipo (peso 20%): afinidade entre profissional/
    estudante e o tipo do evento (emprego, curso, audição, competição).
  - Localização (peso 20%): cidade/estado/país em comum, ou remoto.
  - Confiança da extração (peso 15%): `llm_confidence` da oportunidade —
    os três fatores acima dependem de instrumento/tipo/local terem sido
    extraídos corretamente pela LLM; quando essa extração é pouco
    confiável, o match pesa menos, mesmo que os campos "batam" no papel.

Fica de fora, deliberadamente, o campo `level` da oportunidade (extraído
por LLM, não confiável) — não há dado equivalente no perfil do usuário.

Cada fator é arredondado pra pontos inteiros ANTES de somar (não a soma
bruta arredondada no final) — assim o detalhamento mostrado na UI (ex:
"45% instrumento + 20% localização") sempre soma exatamente o total
exibido, sem sobra por arredondamento.
"""

from dataclasses import dataclass

from app.models import Opportunity, User

_INSTRUMENT_WEIGHT = 45
_AFFINITY_WEIGHT = 20
_LOCATION_WEIGHT = 20
_CONFIDENCE_WEIGHT = 15

# A partir de quanto uma oportunidade é "compatível com o perfil" — é o
# corte da aba "Minhas oportunidades" e o número de Matches do Perfil.
# O app tem o mesmo valor em kHighMatchThreshold (core/constants.dart).
HIGH_MATCH_THRESHOLD = 85

# Prazo "urgente": vence em menos de N dias (hoje incluso). É quando a data
# fica vermelha no card e entra em "Prazos se aproximando" no Início.
# O app tem o mesmo valor em kUrgentDeadlineDays (core/constants.dart).
URGENT_DEADLINE_DAYS = 7


@dataclass
class MatchBreakdown:
    """Pontos contribuídos por cada fator (0 até o seu próprio peso) — somam
    exatamente `total`. Os campos `*_max` (sempre os pesos acima) vão junto
    pra UI poder mostrar "14/15", não um "14%" solto que parece confiança
    bruta — cada fator tem um máximo diferente, não é uma fração de 100."""

    instrument: int
    affinity: int
    location: int
    confidence: int

    instrument_max: int = _INSTRUMENT_WEIGHT
    affinity_max: int = _AFFINITY_WEIGHT
    location_max: int = _LOCATION_WEIGHT
    confidence_max: int = _CONFIDENCE_WEIGHT

    @property
    def total(self) -> int:
        return self.instrument + self.affinity + self.location + self.confidence


def _normalize(values: list[str] | None) -> set[str]:
    return {v.strip().lower() for v in (values or []) if v and v.strip()}


def _instrument_score(user: User, opportunity: Opportunity) -> float:
    opp_instruments = _normalize(opportunity.instruments)
    if not opp_instruments:
        # Oportunidade não exige instrumento específico — aberta a todos.
        return 1.0
    user_instruments = _normalize(user.instruments)
    overlap = user_instruments & opp_instruments
    return min(len(overlap) / len(opp_instruments), 1.0)


# Afinidade entre o tipo da oportunidade e cada ramo de atuação — chave
# normalizada (lowercase, sem acento) porque o tipo às vezes vem acentuado.
_TYPE_AFFINITY = {
    "curso": {"student": 1.0, "professional": 0.6},
    "emprego": {"student": 0.4, "professional": 1.0},
    "audicao": {"student": 1.0, "professional": 1.0},
    "competicao": {"student": 1.0, "professional": 1.0},
}


def _normalize_type(type_: str | None) -> str | None:
    if not type_:
        return None
    return (
        type_.strip()
        .lower()
        .replace("competição", "competicao")
        .replace("audição", "audicao")
    )


def _affinity_score(user: User, opportunity: Opportunity) -> float:
    affinity = _TYPE_AFFINITY.get(_normalize_type(opportunity.type))
    if affinity is None:
        # Tipo desconhecido/não mapeado — neutro, não penaliza.
        return 0.5

    candidates = []
    if user.is_student:
        candidates.append(affinity["student"])
    if user.is_professional:
        candidates.append(affinity["professional"])
    if not candidates:
        # Usuário não marcou nenhum ramo de atuação — neutro.
        return 0.5
    return max(candidates)


def _location_score(user: User, opportunity: Opportunity) -> float:
    if opportunity.is_remote:
        return 1.0

    opp_city = (opportunity.city or "").strip().lower()
    opp_state = (opportunity.state or "").strip().lower()
    opp_country = (opportunity.country or "").strip().lower()

    if not opp_city and not opp_state and not opp_country:
        # Oportunidade sem local informado — neutro.
        return 0.5

    user_city = (user.city or "").strip().lower()
    user_state = (user.state or "").strip().lower()
    user_country = (user.country or "").strip().lower()

    if opp_city and opp_city == user_city:
        return 1.0
    if opp_state and opp_state == user_state:
        return 0.6
    if opp_country and opp_country == user_country:
        return 0.3
    return 0.0


def _confidence_score(opportunity: Opportunity) -> float:
    return max(0.0, min(1.0, opportunity.llm_confidence or 0.0))


def _points(fraction: float, weight: int) -> int:
    return round(max(0.0, min(1.0, fraction)) * weight)


def compute_match_breakdown(user: User, opportunity: Opportunity) -> MatchBreakdown:
    """Detalhamento (0-100, soma = total) do match entre `user` e `opportunity`."""
    return MatchBreakdown(
        instrument=_points(_instrument_score(user, opportunity), _INSTRUMENT_WEIGHT),
        affinity=_points(_affinity_score(user, opportunity), _AFFINITY_WEIGHT),
        location=_points(_location_score(user, opportunity), _LOCATION_WEIGHT),
        confidence=_points(_confidence_score(opportunity), _CONFIDENCE_WEIGHT),
    )


def compute_match_percentage(user: User, opportunity: Opportunity) -> int:
    """Percentual de compatibilidade (0-100) entre `user` e `opportunity`."""
    return compute_match_breakdown(user, opportunity).total
