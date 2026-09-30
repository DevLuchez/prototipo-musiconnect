"""
Router de monitoramento do scheduler.

Endpoints:
  GET /scheduler/status      — jobs ativos e próximas execuções
  POST /scheduler/run-etl    — dispara ETL imediatamente (dev/testes)
  POST /scheduler/resolve-institutions — vincula oportunidades ao mapa (backfill)
"""

import logging
from fastapi import APIRouter
from app.scheduler import scheduler

logger = logging.getLogger("routers.scheduler")

router = APIRouter(prefix="/scheduler", tags=["scheduler"])


@router.get("/status")
def scheduler_status():
    """
    Retorna o status do scheduler e os jobs agendados com suas próximas execuções.
    Útil para monitorar no Oracle Cloud sem precisar de acesso SSH.
    """
    if not scheduler.running:
        return {"status": "stopped", "jobs": []}

    jobs = []
    for job in scheduler.get_jobs():
        next_run = job.next_run_time
        jobs.append({
            "id": job.id,
            "name": job.name,
            "next_run": next_run.isoformat() if next_run else None,
            "status": "active" if next_run else "paused",
        })

    return {
        "status": "running",
        "timezone": "America/Sao_Paulo",
        "total_jobs": len(jobs),
        "jobs": jobs,
    }


@router.post("/run-etl")
async def run_etl_now():
    """
    Dispara o ETL imediatamente em background, sem esperar o horário agendado.
    Útil para testes locais e validação no Oracle Cloud.
    """
    from app.services.etl_task import run_full_etl
    import asyncio

    asyncio.create_task(run_full_etl())

    return {
        "status": "started",
        "message": "ETL iniciado em background. Acompanhe via logs do container.",
    }


@router.post("/resolve-institutions")
async def resolve_institutions_now():
    """
    Vincula ao mapa as oportunidades ainda sem institution_id, sem esperar o
    pipeline diário. Serve também de backfill para as já existentes.
    """
    from app.services.institution_resolver import resolve_opportunity_institutions
    import asyncio

    asyncio.create_task(resolve_opportunity_institutions())

    return {
        "status": "started",
        "message": "Resolução iniciada em background (~1s por geocodificação). Acompanhe via logs do container.",
    }
