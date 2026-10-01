"""
Ponto de entrada da API MusiConnect.

Integra o scheduler APScheduler via lifespan do FastAPI —
o scheduler inicia junto com a API e para junto com ela.
"""

from contextlib import asynccontextmanager
import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.database import engine
from app.migrations import run_migrations
from app.models import Base
from app.routers import auth
from app.routers import favorites
from app.routers import institutions
from app.routers import opportunities
from app.routers import scheduler as scheduler_router
from app.scheduler import setup_scheduler

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)

logger = logging.getLogger("main")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Gerencia o ciclo de vida da aplicação:
      - Startup: cria tabelas e inicia o scheduler
      - Shutdown: para o scheduler graciosamente
    """
    # ── Startup ──────────────────────────────────────────────────
    logger.info("MusiConnect API iniciando...")

    # Cria as tabelas no banco (incluindo a nova tabela 'opportunities')
    Base.metadata.create_all(bind=engine)
    logger.info("Tabelas verificadas/criadas no banco.")

    # Colunas novas em tabelas que já existiam (create_all não faz isso)
    run_migrations(engine)

    # Configura e inicia o scheduler
    scheduler = setup_scheduler()
    scheduler.start()
    logger.info("Scheduler iniciado.")

    yield  # A API fica disponível aqui

    # ── Shutdown ─────────────────────────────────────────────────
    logger.info("MusiConnect API encerrando...")
    scheduler.shutdown(wait=False)
    logger.info("Scheduler encerrado.")


app = FastAPI(
    title="MusiConnect API",
    description="Backend para descoberta global de instituições musicais e oportunidades.",
    version="0.2.0",
    lifespan=lifespan,
)

# CORS liberado para desenvolvimento — ajuste em produção
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
    # Sem isso, o navegador (build Web) não deixa o JS ler X-Total-Count
    # via fetch/XHR — apps nativos (Android/iOS) não são afetados por CORS.
    expose_headers=["X-Total-Count"],
)

app.include_router(auth.router)
app.include_router(favorites.router)
app.include_router(institutions.router)
app.include_router(opportunities.router)
app.include_router(scheduler_router.router)


@app.get("/")
def health_check():
    return {"status": "ok", "service": "MusiConnect API", "version": "0.2.0"}
