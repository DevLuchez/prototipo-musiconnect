"""
Router de favoritos — oportunidades salvas (Matcher) e instituições
favoritas (mapa) do usuário logado.

Endpoints:
  GET    /api/favorites/ids                        — IDs salvos (estado dos corações no app)
  GET    /api/favorites/opportunities              — oportunidades salvas
  PUT    /api/favorites/opportunities/{id}         — salva uma oportunidade
  DELETE /api/favorites/opportunities/{id}         — remove dos salvos
  GET    /api/favorites/institutions               — instituições favoritas
  PUT    /api/favorites/institutions/{osm_id}      — favorita uma instituição
  DELETE /api/favorites/institutions/{osm_id}      — remove dos favoritos

PUT/DELETE são idempotentes (salvar duas vezes ou remover o que não está
salvo não dá erro) — o app pode repetir a chamada sem se preocupar.

Oportunidades salvas seguem o mesmo critério de visibilidade da aba
Matcher (ativa, confiança >= 0.80, prazo vigente): a que vence some da
lista no mesmo dia, e a limpeza diária apaga o registro depois.
"""

from typing import List

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy import text
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import FavoriteInstitution, FavoriteOpportunity, Institution, Opportunity, User
from app.routers.auth import get_current_user
from app.routers.institutions import _ACTIVE_OPPORTUNITIES_JOIN, _INSTITUTION_COLUMNS
from app.routers.opportunities import _apply_filters, _only_open
from app.schemas import FavoriteIdsOut, InstitutionOut, OpportunityOut
from app.services.matching import compute_match_breakdown

router = APIRouter(prefix="/api/favorites", tags=["favorites"])


def _saved_opportunities_query(db: Session, user: User):
    """Oportunidades salvas pelo usuário que ainda estão visíveis no app."""
    return _only_open(_apply_filters(
        db.query(Opportunity).join(
            FavoriteOpportunity,
            (FavoriteOpportunity.opportunity_id == Opportunity.id)
            & (FavoriteOpportunity.user_id == user.id),
        )
    ))


@router.get("/ids", response_model=FavoriteIdsOut)
def get_favorite_ids(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """IDs salvos — o app carrega uma vez ao abrir e usa pra desenhar os
    corações (cheio/vazio) sem precisar consultar item a item."""
    opportunity_ids = [
        opp_id for (opp_id,) in _saved_opportunities_query(db, user)
        .with_entities(Opportunity.id)
        .all()
    ]
    institution_ids = [
        inst_id for (inst_id,) in db.query(FavoriteInstitution.institution_id)
        .filter(FavoriteInstitution.user_id == user.id)
        .all()
    ]
    return FavoriteIdsOut(opportunities=opportunity_ids, institutions=institution_ids)


# ── Oportunidades ────────────────────────────────────────────────────────────

@router.get("/opportunities", response_model=List[OpportunityOut])
def list_favorite_opportunities(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Oportunidades salvas, prazo mais próximo primeiro (o app reordena
    conforme a escolha do usuário — por isso vai junto `saved_at`)."""
    rows = (
        _saved_opportunities_query(db, user)
        .add_columns(FavoriteOpportunity.created_at)
        .order_by(Opportunity.deadline.asc().nulls_last())
        .all()
    )
    items = []
    for opp, saved_at in rows:
        opp.saved_at = saved_at
        items.append(opp)
        breakdown = compute_match_breakdown(user, opp)
        opp.match_percentage = breakdown.total
        opp.match_breakdown = breakdown
    return items


@router.put("/opportunities/{opportunity_id}", status_code=204)
def add_favorite_opportunity(
    opportunity_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if db.get(Opportunity, opportunity_id) is None:
        raise HTTPException(status_code=404, detail="Oportunidade não encontrada")
    db.execute(
        pg_insert(FavoriteOpportunity)
        .values(user_id=user.id, opportunity_id=opportunity_id)
        .on_conflict_do_nothing()
    )
    db.commit()
    return Response(status_code=204)


@router.delete("/opportunities/{opportunity_id}", status_code=204)
def remove_favorite_opportunity(
    opportunity_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    db.query(FavoriteOpportunity).filter(
        FavoriteOpportunity.user_id == user.id,
        FavoriteOpportunity.opportunity_id == opportunity_id,
    ).delete()
    db.commit()
    return Response(status_code=204)


# ── Instituições ─────────────────────────────────────────────────────────────

@router.get("/institutions", response_model=List[InstitutionOut])
def list_favorite_institutions(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Instituições favoritas em ordem alfabética, com a contagem de
    oportunidades abertas (mesmo formato dos pinos do mapa)."""
    rows = db.execute(
        text(f"""
            SELECT {_INSTITUTION_COLUMNS}, f.created_at AS saved_at
            FROM institutions i
            JOIN user_favorite_institutions f
              ON f.institution_id = i.osm_id AND f.user_id = :user_id
            {_ACTIVE_OPPORTUNITIES_JOIN}
            ORDER BY i.name
        """),
        {"user_id": user.id},
    )
    return [InstitutionOut(**row) for row in rows.mappings()]


@router.put("/institutions/{osm_id}", status_code=204)
def add_favorite_institution(
    osm_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if db.get(Institution, osm_id) is None:
        raise HTTPException(status_code=404, detail="Instituição não encontrada")
    db.execute(
        pg_insert(FavoriteInstitution)
        .values(user_id=user.id, institution_id=osm_id)
        .on_conflict_do_nothing()
    )
    db.commit()
    return Response(status_code=204)


@router.delete("/institutions/{osm_id}", status_code=204)
def remove_favorite_institution(
    osm_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    db.query(FavoriteInstitution).filter(
        FavoriteInstitution.user_id == user.id,
        FavoriteInstitution.institution_id == osm_id,
    ).delete()
    db.commit()
    return Response(status_code=204)
