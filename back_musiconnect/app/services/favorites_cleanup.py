"""
Limpeza diária das oportunidades salvas que deixaram de estar visíveis no
app (prazo vencido, desativada pelo LLM ou confiança abaixo do corte).

A lista de salvos já esconde essas oportunidades na consulta (mesmo
critério da aba Matcher) — esta etapa só apaga os registros de fato.
Instituições favoritas não precisam disso: somem por ON DELETE CASCADE
quando a instituição é apagada.
"""

import logging

from sqlalchemy import text

from app.database import SessionLocal

logger = logging.getLogger("scheduler.favorites")


def cleanup_favorite_opportunities() -> int:
    """Apaga os salvos de oportunidades não visíveis. Retorna quantos apagou."""
    db = SessionLocal()
    try:
        result = db.execute(text("""
            DELETE FROM user_favorite_opportunities f
            USING opportunities o
            WHERE o.id = f.opportunity_id
              AND NOT (
                  o.is_active
                  AND o.llm_confidence >= 0.80
                  AND (o.deadline IS NULL OR o.deadline >= CURRENT_DATE)
              )
        """))
        db.commit()
        return result.rowcount
    finally:
        db.close()
