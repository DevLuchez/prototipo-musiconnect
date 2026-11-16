"""
Aba Início (GET /api/dashboard), numa chamada só: favoritos com prazo
próximo, melhores matches, novidades compatíveis (pelo `created_at`) e
contagem por tipo. Sem login, vem só a contagem por tipo.
"""

from collections import Counter
from datetime import date, datetime, timedelta, timezone
from typing import Dict, List, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import FavoriteOpportunity, Opportunity, User
from app.routers.auth import get_current_user_optional
from app.routers.opportunities import _apply_filters, _only_open
from app.schemas import OpportunityOut
from app.services.matching import (
    HIGH_MATCH_THRESHOLD,
    URGENT_DEADLINE_DAYS,
    compute_match_breakdown,
)

router = APIRouter(prefix="/api/dashboard", tags=["Início"])

# Quantos cards em cada carrossel do Início.
_CAROUSEL_LIMIT = 10
# Janela de "Novas para você".
_NEW_WINDOW = timedelta(days=7)


class DashboardOut(BaseModel):
    """Resumo da tela inicial."""

    match_count: int
    """Oportunidades abertas com match a partir de 85%."""
    urgent_saved: List[OpportunityOut]
    """Oportunidades favoritas com menos de 7 dias até o encerramento do prazo."""
    top_matches: List[OpportunityOut]
    """Oportunidades de maior match (a primeira é o "Seu melhor match")."""
    new_matches: List[OpportunityOut]
    """Oportunidades compatíveis que entraram no aplicativo nos últimos 7 dias."""
    # {"audicao": 52, "competicao": 44, ...} — todas as abertas, não só matches.
    type_counts: Dict[str, int]
    """Quantidade de oportunidades abertas por tipo (bloco "Explorar")."""

    model_config = {"use_attribute_docstrings": True}


@router.get(
    "",
    response_model=DashboardOut,
    summary="Consultar o resumo da tela inicial",
    response_description="Resumo da tela inicial.",
    description="Retorna, em uma chamada, os dados da tela inicial: melhores matches, favoritas com prazo nos próximos 7 dias, novas oportunidades compatíveis e a quantidade de oportunidades abertas por tipo. Sem autenticação (modo visitante), apenas a contagem por tipo é preenchida.",
)
def get_dashboard(
    user: Optional[User] = Depends(get_current_user_optional),
    db: Session = Depends(get_db),
):
    visible = _only_open(_apply_filters(db.query(Opportunity))).all()
    type_counts = dict(Counter(o.type for o in visible if o.type))
    if user is None:
        return DashboardOut(
            match_count=0, urgent_saved=[], top_matches=[], new_matches=[],
            type_counts=type_counts,
        )

    for opp in visible:
        breakdown = compute_match_breakdown(user, opp)
        opp.match_percentage = breakdown.total
        opp.match_breakdown = breakdown

    matches = [o for o in visible if o.match_percentage >= HIGH_MATCH_THRESHOLD]
    # Maior match primeiro; empate → prazo mais próximo (sem prazo por último).
    matches.sort(key=lambda o: (-o.match_percentage, o.deadline or date.max))

    new_since = datetime.now(timezone.utc).replace(tzinfo=None) - _NEW_WINDOW
    new_matches = sorted(
        (o for o in matches if o.created_at and o.created_at >= new_since),
        key=lambda o: o.created_at,
        reverse=True,
    )

    today = date.today()
    urgent_until = today + timedelta(days=URGENT_DEADLINE_DAYS)
    saved_ids = {
        opp_id for (opp_id,) in db.query(FavoriteOpportunity.opportunity_id)
        .filter(FavoriteOpportunity.user_id == user.id)
        .all()
    }
    urgent_saved = sorted(
        (
            o for o in visible
            if o.id in saved_ids and o.deadline and today <= o.deadline < urgent_until
        ),
        key=lambda o: o.deadline,
    )

    return DashboardOut(
        match_count=len(matches),
        urgent_saved=urgent_saved,
        top_matches=matches[:_CAROUSEL_LIMIT],
        new_matches=new_matches[:_CAROUSEL_LIMIT],
        type_counts=type_counts,
    )
