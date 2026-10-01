"""
Wrapper assíncrono do pipeline de Scrapers + LLM Enrichment.

Este módulo é a ponte entre o scheduler e os scrapers/enricher,
seguindo o mesmo padrão do etl_task.py.

Pipeline:
  Etapa 1 — Scrapers: coleta oportunidades brutas das fontes externas
  Etapa 2 — Enrichment: LLM (Gemini) transforma os dados brutos em campos estruturados
  Etapa 3 — Resolução: vincula cada oportunidade ao pino da sua instituição no mapa
  Etapa 4 — Limpeza: apaga oportunidades salvas que venceram/foram desativadas

Fluxo diário:
  scheduler → run_all_scrapers() → salva no DB → enriquece com LLM → disponível na API
"""

import logging
from datetime import datetime, timezone

from app.services.scrapers.musical_chairs_scraper import scrape_musical_chairs
from app.services.llm_enricher import enrich_opportunities
from app.services.institution_resolver import resolve_opportunity_institutions
from app.services.favorites_cleanup import cleanup_favorite_opportunities

logger = logging.getLogger("scheduler.scrapers")


async def _upsert_raw(records: list[dict]) -> int:
    """Persiste as oportunidades brutas no banco. Reutiliza a lógica do router."""
    if not records:
        return 0
    # Importação local para evitar circular import com o router
    from app.routers.opportunities import _upsert_opportunities
    return _upsert_opportunities(records)


async def run_all_scrapers() -> None:
    """
    Executa o pipeline completo de coleta e enriquecimento de oportunidades.

    Etapa 1: Scrapers — coleta das fontes configuradas
    Etapa 2: LLM Enrichment — processa registros pendentes (enriched_at IS NULL)
    Etapa 3: Resolução — preenche institution_id (pino do mapa) das pendentes
    Etapa 4: Limpeza — apaga oportunidades salvas que não estão mais visíveis

    Captura todas as exceções para que uma falha não derrube a API.
    """
    start = datetime.now(timezone.utc)
    logger.info("=" * 60)
    logger.info("[Scrapers] Iniciando pipeline de oportunidades")
    logger.info("=" * 60)

    # ── Etapa 1: Coleta ───────────────────────────────────────────────────────
    total_found = 0
    total_saved = 0

    # Musical Chairs
    try:
        logger.info("[Scrapers] Etapa 1/4 — Musical Chairs RSS...")
        mc_records = await scrape_musical_chairs()
        saved = await _upsert_raw(mc_records)
        total_found += len(mc_records)
        total_saved += saved
        logger.info(
            f"[Scrapers] Musical Chairs: {len(mc_records)} encontradas, "
            f"{saved} salvas/atualizadas"
        )
    except Exception as exc:
        logger.error(f"[Scrapers] Erro no Musical Chairs: {exc}", exc_info=True)

    # Próximos scrapers — adicionar aqui seguindo o mesmo padrão:
    # try:
    #     logger.info("[Scrapers] Etapa 1/4 — Resartis...")
    #     resartis_records = await scrape_resartis()
    #     saved = await _upsert_raw(resartis_records)
    #     total_found += len(resartis_records)
    #     total_saved += saved
    # except Exception as exc:
    #     logger.error(f"[Scrapers] Erro no Resartis: {exc}", exc_info=True)

    logger.info(
        f"[Scrapers] Coleta concluída: {total_found} encontradas, "
        f"{total_saved} salvas"
    )

    # ── Etapa 2: Enrichment ───────────────────────────────────────────────────
    try:
        logger.info(
            "[Scrapers] Etapa 2/4 — LLM Enrichment "
            "(processa registros com enriched_at IS NULL)..."
        )
        stats = await enrich_opportunities()
        logger.info(
            f"[Scrapers] Enrichment concluído: "
            f"{stats.get('success', 0)}/{stats.get('processed', 0)} com sucesso"
        )
    except Exception as exc:
        logger.error(f"[Scrapers] Erro no LLM Enrichment: {exc}", exc_info=True)

    # ── Etapa 3: Vínculo com o mapa ───────────────────────────────────────────
    try:
        logger.info("[Scrapers] Etapa 3/4 — Vinculando oportunidades às instituições do mapa...")
        stats = await resolve_opportunity_institutions()
        logger.info(
            f"[Scrapers] Resolução concluída: {stats.get('linked', 0)} vinculadas a uma "
            f"instituição, {stats.get('unresolved', 0)} sem instituição localizada, "
            f"{stats.get('linked_to_city', 0)} vinculadas à cidade"
        )
    except Exception as exc:
        logger.error(f"[Scrapers] Erro na resolução de instituições: {exc}", exc_info=True)

    # ── Etapa 4: Limpeza dos salvos ───────────────────────────────────────────
    try:
        logger.info("[Scrapers] Etapa 4/4 — Limpando oportunidades salvas vencidas...")
        removed = cleanup_favorite_opportunities()
        logger.info(f"[Scrapers] Limpeza concluída: {removed} salvos removidos")
    except Exception as exc:
        logger.error(f"[Scrapers] Erro na limpeza dos salvos: {exc}", exc_info=True)

    elapsed = (datetime.now(timezone.utc) - start).seconds
    logger.info(f"[Scrapers] Pipeline finalizado em {elapsed}s.")
