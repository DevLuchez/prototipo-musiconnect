"""
Router da aba Início do app — resumo do que importa hoje para o usuário
logado, numa chamada só.

Endpoint:
  GET /api/dashboard

Seções (todas com o mesmo critério de visibilidade do Matcher: ativa,
confiança >= 0.80, prazo vigente):
  - urgent_saved: oportunidades SALVAS com prazo nos próximos
    URGENT_DEADLINE_DAYS dias (mesma regra da data vermelha no card).
  - top_matches: as de maior match, só as >= HIGH_MATCH_THRESHOLD (as
    mesmas de "Minhas oportunidades").
  - new_matches: compatíveis que entraram no app nos últimos 7 dias — pelo
    `created_at` (gravado uma vez), não pelo `scraped_at`, que é
    atualizado toda vez que o RSS relista uma oportunidade antiga.
"""

from datetime import date, datetime, timedelta
from typing import List

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import FavoriteOpportunity, Opportunity, User
from app.routers.auth import get_current_user
from app.routers.opportunities import _apply_filters, _only_open
from app.schemas import OpportunityOut
from app.services.matching import (
    HIGH_MATCH_THRESHOLD,
    URGENT_DEADLINE_DAYS,
    compute_match_breakdown,
)

router = APIRouter(prefix="/api/dashboard", tags=["dashboard"])

# Quantos cards em cada carrossel do Início.
_CAROUSEL_LIMIT = 10
# Janela de "Novas para você".
_NEW_WINDOW = timedelta(days=7)


class DashboardOut(BaseModel):
    match_count: int
    urgent_saved: List[OpportunityOut]
    top_matches: List[OpportunityOut]
    new_matches: List[OpportunityOut]


@router.get("", response_model=DashboardOut)
def get_dashboard(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    visible = _only_open(_apply_filters(db.query(Opportunity))).all()
    for opp in visible:
        breakdown = compute_match_breakdown(user, opp)
        opp.match_percentage = breakdown.total
        opp.match_breakdown = breakdown

    matches = [o for o in visible if o.match_percentage >= HIGH_MATCH_THRESHOLD]
    # Maior match primeiro; empate → prazo mais próximo (sem prazo por último).
    matches.sort(key=lambda o: (-o.match_percentage, o.deadline or date.max))

    new_since = datetime.utcnow() - _NEW_WINDOW
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
    )
