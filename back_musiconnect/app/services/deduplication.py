"""
Observação de oportunidades repetidas entre fontes (ex: o mesmo concurso no
Musical Chairs e na Revista CONCERTO) — só registra no log, não muda nada no
app.

Decisão (Laura, 01/11/2026): observar até 06/11 e, em 07/11, decidir com os
pares registrados se as repetidas devem ser escondidas, agrupadas no app
("também divulgado por...") ou se são raras demais para valer a pena. Antes
de qualquer mudança no app, a detecção precisa provar que acerta — esconder
uma oportunidade diferente por engano é pior do que mostrar uma repetida.

(A WFIMC já evita, na coleta, o caso medido: concurso que veio de outra
fonte com o mesmo prazo — ver scrapers/wfimc_scraper.py.)

Duas oportunidades parecem a mesma quando têm o mesmo prazo e pelo menos
duas palavras distintivas em comum no nome/instituição. Palavras genéricas
("concurso", "audição", "orquestra", nomes de instrumentos...) não contam —
senão duas audições de violino diferentes com o mesmo prazo pareceriam
iguais.
"""

import logging
import re
from datetime import date
from typing import Optional

from sqlalchemy.orm import Session

from app.models import Opportunity
from app.services.llm_enricher import CANONICAL_INSTRUMENTS

logger = logging.getLogger("services.deduplication")

_GENERIC = {
    # inglês
    "international", "competition", "competitions", "music", "musical", "prize",
    "festival", "young", "award", "orchestra", "symphony", "philharmonic",
    "audition", "auditions", "position", "academy", "school", "course",
    # francês/italiano/espanhol
    "concours", "concorso", "musique", "premio", "orchestre", "orquesta",
    # português (títulos reescritos pelo Gemini)
    "concurso", "internacional", "nacional", "audição", "audições", "orquestra",
    "sinfônica", "filarmônica", "academia", "escola", "curso", "cursos",
    "oficina", "masterclass", "bolsa", "bolsas", "vagas", "seleção", "edital",
    "músicos", "música", "programa", "inscrições", "principal", "tutti",
}
_GENERIC |= {w for name in CANONICAL_INSTRUMENTS for w in name.lower().split()}


def name_words(text: Optional[str]) -> set[str]:
    """Palavras distintivas (5+ letras, fora as genéricas)."""
    return set(re.findall(r"[a-zà-ÿ]{5,}", (text or "").lower())) - _GENERIC


def looks_same(a: Opportunity, b: Opportunity) -> bool:
    if not a.deadline or a.deadline != b.deadline:
        return False
    words_a = name_words(f"{a.title} {a.institution or ''}")
    words_b = name_words(f"{b.title} {b.institution or ''}")
    return len(words_a & words_b) >= 2


def report_cross_source_duplicates(db: Session, today: Optional[date] = None) -> list[tuple]:
    """Pares (mais antiga, repetida) de fontes diferentes entre as
    oportunidades visíveis. Só registra no log."""
    today = today or date.today()
    visible = (
        db.query(Opportunity)
        .filter(
            Opportunity.is_active.is_(True),
            Opportunity.llm_confidence >= 0.80,
            Opportunity.enriched_at.isnot(None),
            Opportunity.deadline >= today,
        )
        .order_by(Opportunity.id)
        .all()
    )
    by_deadline: dict[date, list[Opportunity]] = {}
    pairs = []
    for opp in visible:
        same_day = by_deadline.setdefault(opp.deadline, [])
        for earlier in same_day:
            if earlier.source_name != opp.source_name and looks_same(earlier, opp):
                pairs.append((earlier, opp))
                logger.info(
                    f"[Duplicadas?] {opp.deadline} | '{earlier.title[:60]}' "
                    f"({earlier.source_name}, id {earlier.id}) × '{opp.title[:60]}' "
                    f"({opp.source_name}, id {opp.id})"
                )
                break
        same_day.append(opp)
    logger.info(f"[Duplicadas?] {len(pairs)} pares suspeitos entre fontes diferentes")
    return pairs
