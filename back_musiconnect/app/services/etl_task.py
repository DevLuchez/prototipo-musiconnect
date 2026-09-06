"""
Wrapper assíncrono do ETL para uso pelo APScheduler.

Este módulo serve de ponte entre o scheduler e as funções ETL existentes,
sem modificar o comportamento do script manual `python -m scripts.run_etl`.
"""

import logging
from app.services.overpass_etl import run_etl
from app.services.musicbrainz_validator import run_musicbrainz_validation
from app.services.wikidata_validator import run_wikidata_validation

logger = logging.getLogger("scheduler.etl")


async def run_full_etl() -> None:
    """
    Executa o pipeline ETL completo:
      Etapa 1 — OpenStreetMap via Overpass API
      Etapa 2 — Validação MusicBrainz
      Etapa 3 — Validação Wikidata

    Captura todas as exceções para que uma falha no ETL
    não derrube o processo da API FastAPI.
    """
    logger.info("=" * 60)
    logger.info("[ETL] Iniciando pipeline completo")
    logger.info("=" * 60)

    # ── Etapa 1: OpenStreetMap ────────────────────────────────────
    try:
        logger.info("[ETL] Etapa 1/3 — OpenStreetMap (Overpass API)...")
        stats = await run_etl(concurrency=4)
        logger.info(
            f"[ETL] OSM concluído: {stats['records_upserted']} registros "
            f"em {stats['cells_processed']} células"
        )
    except Exception as exc:
        logger.error(f"[ETL] Erro na Etapa 1 (OSM): {exc}", exc_info=True)
        return  # Aborta as próximas etapas se o OSM falhar

    # ── Etapa 2: MusicBrainz ─────────────────────────────────────
    try:
        logger.info("[ETL] Etapa 2/3 — Validação MusicBrainz...")
        mb_stats = await run_musicbrainz_validation()
        logger.info(
            f"[ETL] MusicBrainz concluído: "
            f"{mb_stats.get('verified', 0)}/{mb_stats.get('total', 0)} verificados"
        )
    except Exception as exc:
        logger.error(f"[ETL] Erro na Etapa 2 (MusicBrainz): {exc}", exc_info=True)
        # Continua para a Etapa 3 mesmo com falha no MusicBrainz

    # ── Etapa 3: Wikidata ─────────────────────────────────────────
    try:
        logger.info("[ETL] Etapa 3/3 — Validação Wikidata SPARQL...")
        wd_stats = await run_wikidata_validation()
        logger.info(
            f"[ETL] Wikidata concluído: {wd_stats.get('verified', 0)} verificados"
        )
    except Exception as exc:
        logger.error(f"[ETL] Erro na Etapa 3 (Wikidata): {exc}", exc_info=True)

    logger.info("[ETL] Pipeline finalizado.")
