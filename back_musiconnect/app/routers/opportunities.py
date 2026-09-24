"""
Router de oportunidades musicais — aba Matcher do app Flutter.

Endpoints:
  GET  /api/opportunities          — lista oportunidades ativas
  GET  /api/opportunities/{id}     — detalhes de uma oportunidade
  POST /api/opportunities/scrape   — dispara full scraping manual (dev/admin)
  POST /api/opportunities/enrich   — enriquece oportunidades brutas via LLM (Gemini)
"""

import logging
from typing import Optional, List
from datetime import date

import pycountry
from babel import Locale
from fastapi import APIRouter, Depends, HTTPException, Query, BackgroundTasks, Response
from sqlalchemy.orm import Session
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.database import get_db, SessionLocal
from app.models import Opportunity, User
from app.schemas import OpportunityOut
from app.routers.auth import get_current_user_optional
from app.services.matching import compute_match_breakdown
from app.services.scrapers.musical_chairs_scraper import scrape_musical_chairs
from app.services.llm_enricher import enrich_opportunities

logger = logging.getLogger("routers.opportunities")

router = APIRouter(prefix="/api/opportunities", tags=["opportunities"])


# ── Nome de estado/província por extenso ──────────────────────────────────────
# Siglas de estado colidem entre países (ex: "MT" = Mato Grosso no Brasil ou
# Montana nos EUA) — por isso o nome é resolvido usando o país real do
# registro, com dados oficiais reais (não um mapa inventado):
#   - Babel/CLDR: nome do país em português → código ISO 3166-1 alpha-2
#     (os países já são gravados em português pelo LLM, ex: "Estados Unidos")
#   - pycountry: código do país + sigla do estado → nome oficial da
#     subdivisão (ISO 3166-2), ex: "US-MT" → "Montana", "BR-MT" → "Mato Grosso"
_PT_COUNTRY_TO_ALPHA2 = {
    name.lower(): code
    for code, name in Locale("pt").territories.items()
    if len(code) == 2
}


def _state_label(code: str, country: Optional[str]) -> str:
    """Formata 'SIGLA | Nome por extenso' resolvendo pelo país real do registro."""
    alpha2 = _PT_COUNTRY_TO_ALPHA2.get((country or "").lower())
    name = None
    if alpha2:
        subdivision = pycountry.subdivisions.get(code=f"{alpha2}-{code}")
        name = subdivision.name if subdivision else None
    return f"{code} | {name}" if name else code


# ── Helpers ──────────────────────────────────────────────────────────────────

def _upsert_opportunities(records: list[dict]) -> int:
    """
    Faz upsert em lote na tabela opportunities.
    Deduplicação por source_url — nunca duplica a mesma oportunidade.

    Numa oportunidade NOVA, todos os campos são gravados (incluindo os
    coletados na página de detalhe: instituição, prazo, descrição completa).

    Numa oportunidade JÁ CONHECIDA (conflito por source_url), o RSS a
    relista por vários dias seguidos com apenas o resumo curto — sem
    revisitar a página de detalhe (ver `_enrich_with_details` no scraper).
    Por isso, no conflito, só `scraped_at` é atualizado: sobrescrever
    title/description/raw_text/institution/deadline com o resumo raso
    apagaria dados melhores já coletados, e sobrescrever llm_confidence
    resetaria oportunidades já enriquecidas para 0.0 (como `enriched_at`
    não seria reposto para NULL, elas nunca mais seriam reenriquecidas e
    sumiriam da listagem — bug encontrado durante esta revisão).
    """
    if not records:
        return 0

    # Remove registros sem source_url (não podem ser deduplicados com segurança)
    valid = [r for r in records if r.get("source_url")]
    if not valid:
        return 0

    db = SessionLocal()
    try:
        stmt = (
            pg_insert(Opportunity)
            .values(valid)
            .on_conflict_do_update(
                index_elements=["source_url"],
                set_={
                    "scraped_at": pg_insert(Opportunity).excluded.scraped_at,
                },
            )
        )
        db.execute(stmt)
        db.commit()
        return len(valid)
    finally:
        db.close()


async def _run_full_scrape() -> dict:
    """Executa todos os scrapers e persiste as oportunidades.
    
    Novos scrapers devem ser chamados aqui e seus resultados concatenados
    em `all_results` antes do upsert.
    """
    logger.info("[Scraper] Iniciando scraping...")

    musical_chairs_results = await scrape_musical_chairs()

    all_results: list[dict] = [
        *musical_chairs_results,
        # Adicionar resultados de outros scrapers aqui
    ]

    saved = _upsert_opportunities(all_results)

    logger.info(
        f"[Scraper] Concluído: Musical Chairs={len(musical_chairs_results)}, "
        f"total_encontrado={len(all_results)}, salvos={saved}"
    )
    return {
        "musical_chairs": len(musical_chairs_results),
        "total_found":    len(all_results),
        "total_saved":    saved,
    }


# ── Endpoints ────────────────────────────────────────────────────────────────

@router.get("/", response_model=List[OpportunityOut])
def list_opportunities(
    response: Response,
    type: Optional[List[str]] = Query(None, description="Tipo(s): audicao, emprego, curso, competicao"),
    source_name: Optional[str] = Query(None, description="Fonte: Funarte, Musical Chairs..."),
    instrument: Optional[List[str]] = Query(None, description="Instrumento(s) exigido(s) (ex: Violino)"),
    country: Optional[List[str]] = Query(None, description="País(es) (ex: Brasil)"),
    state: Optional[List[str]] = Query(None, description="Estado(s)/província(s) (ex: SP)"),
    city: Optional[List[str]] = Query(None, description="Cidade(s) (ex: São Paulo)"),
    is_remote: Optional[bool] = Query(None, description="Apenas oportunidades remotas"),
    only_active: bool = Query(True, description="Exibe apenas oportunidades com prazo vigente"),
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user_optional),
):
    """
    Lista oportunidades musicais para a aba Matcher.
    Retorna apenas oportunidades com llm_confidence >= 0.80.

    Cada filtro aceita múltiplos valores (ex: ?instrument=Violino&instrument=Piano)
    — dentro do mesmo campo é OR (qualquer um dos valores serve), entre campos
    diferentes é AND (todos os campos informados precisam bater).

    O total real (antes do corte por `limit`) vai no header `X-Total-Count`,
    já que o corpo da resposta é só a página pedida — o cliente não deve
    usar o tamanho da lista retornada como se fosse o total.
    """
    query = _apply_filters(
        db.query(Opportunity),
        type=type,
        source_name=source_name,
        instrument=instrument,
        country=country,
        state=state,
        city=city,
        is_remote=is_remote,
    )

    if only_active:
        # Exclui oportunidades com prazo já expirado
        query = query.filter(
            (Opportunity.deadline == None) | (Opportunity.deadline >= date.today())
        )

    # Total que atende aos filtros, independente do limit — calculado antes
    # do order_by/limit para não ser afetado por eles.
    response.headers["X-Total-Count"] = str(query.count())

    items = (
        query
        .order_by(Opportunity.scraped_at.desc())
        .limit(limit)
        .all()
    )
    if current_user:
        for opp in items:
            breakdown = compute_match_breakdown(current_user, opp)
            opp.match_percentage = breakdown.total
            opp.match_breakdown = breakdown
    return items


def _apply_filters(
    query,
    *,
    type: Optional[List[str]] = None,
    source_name: Optional[str] = None,
    instrument: Optional[List[str]] = None,
    country: Optional[List[str]] = None,
    state: Optional[List[str]] = None,
    city: Optional[List[str]] = None,
    is_remote: Optional[bool] = None,
):
    """Aplica os filtros comuns entre `list_opportunities` e `get_filter_options`."""
    query = query.filter(Opportunity.is_active == True).filter(
        Opportunity.llm_confidence >= 0.80
    )
    if type:
        query = query.filter(Opportunity.type.in_(type))
    if source_name:
        query = query.filter(Opportunity.source_name == source_name)
    if instrument:
        # ARRAY && ARRAY — verdadeiro se instruments tiver ao menos um dos pedidos
        query = query.filter(Opportunity.instruments.overlap(instrument))
    if country:
        query = query.filter(Opportunity.country.in_(country))
    if state:
        query = query.filter(Opportunity.state.in_(state))
    if city:
        query = query.filter(Opportunity.city.in_(city))
    if is_remote is not None:
        query = query.filter(Opportunity.is_remote == is_remote)
    return query


@router.get("/filter-options")
def get_filter_options(
    instrument: Optional[List[str]] = Query(None),
    country: Optional[List[str]] = Query(None),
    state: Optional[List[str]] = Query(None),
    city: Optional[List[str]] = Query(None),
    db: Session = Depends(get_db),
):
    """
    Valores distintos disponíveis pra popular os seletores do modal de
    filtros (Instrumento, País, Estado, Cidade) — busca facetada/cruzada:
    cada campo é calculado aplicando os filtros JÁ escolhidos nos OUTROS
    campos (nunca nele mesmo), pra que escolher um instrumento estreite as
    opções de localização mostradas, e vice-versa.

    Precisa vir ANTES de /{opportunity_id} no router — senão o FastAPI
    tentaria casar "filter-options" como opportunity_id (int) e falharia.
    """

    def rows(*, exclude: str):
        query = _apply_filters(
            db.query(
                Opportunity.instruments,
                Opportunity.country,
                Opportunity.state,
                Opportunity.city,
            ),
            instrument=instrument if exclude != "instrument" else None,
            country=country if exclude != "country" else None,
            state=state if exclude != "state" else None,
            city=city if exclude != "city" else None,
        )
        return query.all()

    instruments = sorted({
        i for row in rows(exclude="instrument") for i in (row.instruments or []) if i
    })
    countries = sorted({row.country for row in rows(exclude="country") if row.country})
    cities = sorted({row.city for row in rows(exclude="city") if row.city})

    # Um país por sigla de estado (o primeiro encontrado) — só pra resolver
    # o nome por extenso; o filtro em si continua usando a sigla crua.
    state_country: dict[str, Optional[str]] = {}
    for row in rows(exclude="state"):
        if row.state and row.state not in state_country:
            state_country[row.state] = row.country
    states = [
        {"value": code, "label": _state_label(code, state_country[code])}
        for code in sorted(state_country)
    ]

    return {
        "instruments": instruments,
        "countries": countries,
        "states": states,
        "cities": cities,
    }


@router.get("/{opportunity_id}", response_model=OpportunityOut)
def get_opportunity(
    opportunity_id: int,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user_optional),
):
    """Retorna os detalhes de uma oportunidade específica."""
    opp = db.query(Opportunity).filter(Opportunity.id == opportunity_id).first()
    if not opp:
        raise HTTPException(status_code=404, detail="Oportunidade não encontrada")
    if current_user:
        breakdown = compute_match_breakdown(current_user, opp)
        opp.match_percentage = breakdown.total
        opp.match_breakdown = breakdown
    return opp


@router.post("/scrape")
async def trigger_scrape(background_tasks: BackgroundTasks):
    """
    Dispara o scraping manual de todas as fontes em background.
    Útil para testes e validação antes de ativar o scheduler.
    Retorna imediatamente com status 202 (processamento assíncrono).
    """
    background_tasks.add_task(_run_full_scrape)
    return {
        "status": "started",
        "message": "Scraping iniciado em background. Verifique GET /api/opportunities em alguns minutos.",
    }


@router.post("/enrich")
async def trigger_enrich(background_tasks: BackgroundTasks):
    """
    Enriquece via Gemini todas as oportunidades brutas ainda não processadas.
    Extrai: título limpo, descrição, tipo, instrumentos, nível, prazo,
    instituição, cidade, estado e pontuação de confiança.
    Apenas oportunidades com llm_confidence >= 0.80 são exibidas ao usuário.
    """
    background_tasks.add_task(enrich_opportunities)
    return {
        "status": "started",
        "message": (
            "Enriquecimento LLM iniciado em background. "
            "Verifique GET /api/opportunities após alguns minutos — "
            f"~{4.5:.0f}s por oportunidade (rate limit Gemini free tier)."
        ),
    }
