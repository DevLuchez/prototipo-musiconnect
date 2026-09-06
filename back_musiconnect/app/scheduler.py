"""
Scheduler central do MusiConnect.

Gerencia todos os jobs agendados usando APScheduler (AsyncIOScheduler).
Roda dentro do processo FastAPI — não requer infraestrutura extra.

Jobs ativos:
  - ETL diário     (hora configurável): atualiza mapa de instituições (OSM/MusicBrainz/Wikidata)
  - Scrapers diário (hora configurável): coleta oportunidades do Musical Chairs e enriquece com LLM
"""

import logging
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

from app.config import settings
from app.services.etl_task import run_full_etl
from app.services.scraper_task import run_all_scrapers

logger = logging.getLogger("scheduler")

# Instância global — iniciada no lifespan do FastAPI
scheduler = AsyncIOScheduler(timezone="America/Sao_Paulo")


def setup_scheduler() -> AsyncIOScheduler:
    """
    Configura os jobs e retorna o scheduler pronto para iniciar.
    Chamado uma vez no startup do FastAPI.
    """
    if not settings.scheduler_enabled:
        logger.info(
            "[Scheduler] SCHEDULER_ENABLED=false — scheduler desativado. "
            "Para ativar, defina SCHEDULER_ENABLED=true no .env"
        )
        return scheduler

    # ── Job 1: ETL completo diário ────────────────────────────────
    scheduler.add_job(
        run_full_etl,
        trigger=CronTrigger(
            hour=settings.scheduler_etl_hour,
            minute=0,
            timezone="America/Sao_Paulo",
        ),
        id="etl_full_daily",
        name=f"ETL Completo (OSM + MusicBrainz + Wikidata) — {settings.scheduler_etl_hour:02d}:00",
        replace_existing=True,
        misfire_grace_time=3600,  # tolera até 1h de atraso (ex: container reiniciado)
    )

    # ── Job 2: Scrapers diários (Musical Chairs + LLM Enrichment) ────
    scheduler.add_job(
        run_all_scrapers,
        trigger=CronTrigger(
            hour=settings.scheduler_scrapers_hour,
            minute=0,
            timezone="America/Sao_Paulo",
        ),
        id="scrapers_daily",
        name=f"Scrapers + LLM Enrichment (Musical Chairs...) — {settings.scheduler_scrapers_hour:02d}:00",
        replace_existing=True,
        misfire_grace_time=3600,
    )

    jobs = scheduler.get_jobs()
    logger.info(
        f"[Scheduler] Configurado — {len(jobs)} job(s) ativo(s): "
        + ", ".join(j.name for j in jobs)
    )

    return scheduler
