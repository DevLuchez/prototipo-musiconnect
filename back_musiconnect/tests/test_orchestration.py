"""
Orquestração: pipelines agendados (scrapers + Gemini + vínculo ao mapa +
limpeza; ETL + validações), agendador, inicialização da API, migrações e a
sessão de banco das rotas.

As etapas de cada pipeline são simuladas — aqui se testa a ordem, o que
acontece quando uma etapa falha e o que cada pipeline devolve.
"""

import asyncio
from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import text

import app.database as database
import app.main as main
import app.routers.scheduler as scheduler_router
import app.scheduler as scheduler_module
import app.security as security
import app.services.etl_task as etl_task
import app.services.scraper_task as scraper_task
from app.migrations import run_migrations

ADMIN_KEY = "chave-admin-teste"


# ── Pipeline de oportunidades (scraper_task) ─────────────────────────────

def _fake_step(steps, name, result, is_async=True):
    """Etapa simulada: registra a chamada e falha se `name` estiver em steps["fail"]."""
    def run():
        steps["calls"].append(name)
        if name in steps["fail"]:
            raise RuntimeError(f"falha em {name}")
        return result

    async def async_step(*args, **kwargs):
        return run()

    def sync_step(*args, **kwargs):
        return run()

    return async_step if is_async else sync_step


@pytest.fixture
def scraper_steps(monkeypatch):
    """Simula as etapas do pipeline de oportunidades."""
    steps = {"calls": [], "fail": set()}
    fakes = {
        "scrape_musical_chairs": _fake_step(steps, "scrape", [{"a": 1}, {"b": 2}]),
        "_upsert_raw": _fake_step(steps, "upsert", 2),
        "enrich_opportunities": _fake_step(steps, "enrich", {"success": 2, "processed": 2}),
        "resolve_opportunity_institutions": _fake_step(
            steps, "resolve", {"linked": 1, "unresolved": 1, "linked_to_city": 1}),
        "cleanup_favorite_opportunities": _fake_step(steps, "cleanup", 0, is_async=False),
    }
    for attr, fake in fakes.items():
        monkeypatch.setattr(scraper_task, attr, fake)
    return steps


def test_pipeline_de_oportunidades_roda_as_etapas_em_ordem(scraper_steps):
    asyncio.run(scraper_task.run_all_scrapers())
    assert scraper_steps["calls"] == ["scrape", "upsert", "enrich", "resolve", "cleanup"]


@pytest.mark.parametrize("failing", ["scrape", "enrich", "resolve", "cleanup"])
def test_falha_numa_etapa_nao_impede_as_seguintes(scraper_steps, failing):
    scraper_steps["fail"].add(failing)

    asyncio.run(scraper_task.run_all_scrapers())  # não levanta

    assert scraper_steps["calls"][-1] == "cleanup"


def test_upsert_bruto_sem_registros_nao_grava(monkeypatch):
    assert asyncio.run(scraper_task._upsert_raw([])) == 0

    import app.routers.opportunities as opportunities_router
    monkeypatch.setattr(opportunities_router, "_upsert_opportunities", lambda recs: len(recs))
    assert asyncio.run(scraper_task._upsert_raw([{"x": 1}])) == 1


# ── Pipeline do ETL (etl_task) ───────────────────────────────────────────

@pytest.fixture
def etl_steps(monkeypatch):
    """Simula as etapas do ETL agendado."""
    steps = {"calls": [], "fail": set()}
    monkeypatch.setattr(etl_task, "run_etl", _fake_step(
        steps, "osm", {"records_upserted": 10, "types_processed": 5}))
    monkeypatch.setattr(etl_task, "run_musicbrainz_validation", _fake_step(
        steps, "musicbrainz", {"verified": 1, "total": 2}))
    monkeypatch.setattr(etl_task, "run_wikidata_validation", _fake_step(
        steps, "wikidata", {"verified": 3}))
    return steps


def test_etl_completo_roda_osm_e_as_duas_validacoes(etl_steps):
    asyncio.run(etl_task.run_full_etl())
    assert etl_steps["calls"] == ["osm", "musicbrainz", "wikidata"]


def test_falha_no_osm_aborta_as_validacoes(etl_steps):
    etl_steps["fail"].add("osm")
    asyncio.run(etl_task.run_full_etl())
    assert etl_steps["calls"] == ["osm"]


def test_falha_no_musicbrainz_ainda_roda_o_wikidata(etl_steps):
    etl_steps["fail"].update({"musicbrainz", "wikidata"})
    asyncio.run(etl_task.run_full_etl())  # não levanta
    assert etl_steps["calls"] == ["osm", "musicbrainz", "wikidata"]


# ── Agendador ────────────────────────────────────────────────────────────

@pytest.fixture
def clean_scheduler():
    scheduler_module.scheduler.remove_all_jobs()
    yield scheduler_module.scheduler
    scheduler_module.scheduler.remove_all_jobs()


def test_agendador_desligado_nao_cria_jobs(monkeypatch, clean_scheduler):
    monkeypatch.setattr(scheduler_module.settings, "scheduler_enabled", False)
    assert scheduler_module.setup_scheduler().get_jobs() == []


def test_agendador_cria_etl_e_scrapers_nos_horarios_configurados(monkeypatch, clean_scheduler):
    monkeypatch.setattr(scheduler_module.settings, "scheduler_enabled", True)
    monkeypatch.setattr(scheduler_module.settings, "scheduler_etl_hour", 0)
    monkeypatch.setattr(scheduler_module.settings, "scheduler_scrapers_hour", 6)

    jobs = {job.id: job for job in scheduler_module.setup_scheduler().get_jobs()}

    assert set(jobs) == {"etl_full_daily", "scrapers_daily"}
    assert "00:00" in jobs["etl_full_daily"].name
    assert "06:00" in jobs["scrapers_daily"].name


class _FakeJob:
    def __init__(self, job_id, next_run):
        self.id, self.name, self.next_run_time = job_id, f"Job {job_id}", next_run


class _FakeScheduler:
    def __init__(self, running, jobs=()):
        self.running = running
        self._jobs = list(jobs)
        self.started = self.stopped = False

    def get_jobs(self):
        return self._jobs

    def start(self):
        self.started = True

    def shutdown(self, wait=True):
        self.stopped = True


@pytest.fixture
def admin_client(monkeypatch):
    monkeypatch.setattr(security.settings, "admin_api_key", ADMIN_KEY)
    return TestClient(main.app), {"X-Admin-Key": ADMIN_KEY}


def test_status_do_agendador_parado(monkeypatch, admin_client):
    client, headers = admin_client
    monkeypatch.setattr(scheduler_router, "scheduler", _FakeScheduler(running=False))

    assert client.get("/scheduler/status", headers=headers).json() == {"status": "stopped", "jobs": []}


def test_status_do_agendador_com_jobs_ativos_e_pausados(monkeypatch, admin_client):
    client, headers = admin_client
    proxima = datetime(2026, 11, 1, 0, 0, tzinfo=timezone.utc)
    monkeypatch.setattr(scheduler_router, "scheduler", _FakeScheduler(
        running=True, jobs=[_FakeJob("etl", proxima), _FakeJob("parado", None)]))

    body = client.get("/scheduler/status", headers=headers).json()

    assert body["status"] == "running" and body["total_jobs"] == 2
    assert body["jobs"][0] == {"id": "etl", "name": "Job etl",
                               "next_run": proxima.isoformat(), "status": "active"}
    assert body["jobs"][1]["status"] == "paused"


# ── Inicialização da API, migrações e sessão do banco ────────────────────

def test_inicializacao_cria_tabelas_migra_e_liga_o_agendador(monkeypatch, db_engine):
    fake = _FakeScheduler(running=False)
    monkeypatch.setattr(main, "engine", db_engine)
    monkeypatch.setattr(main, "setup_scheduler", lambda: fake)

    with TestClient(main.app) as client:  # `with` roda o lifespan
        assert fake.started
        assert client.get("/").json()["status"] == "ok"
    assert fake.stopped


def test_migracoes_podem_rodar_mais_de_uma_vez(db_engine):
    run_migrations(db_engine)
    run_migrations(db_engine)
    with db_engine.connect() as conn:
        cols = {row[0] for row in conn.execute(text(
            "SELECT column_name FROM information_schema.columns WHERE table_name = 'users'"))}
    assert {"privacy_accepted_at", "privacy_policy_version"} <= cols


def test_sessao_das_rotas_e_fechada_no_fim(monkeypatch):
    closed = []

    class FakeSession:
        def close(self):
            closed.append(True)

    monkeypatch.setattr(database, "SessionLocal", FakeSession)
    gen = database.get_db()
    assert isinstance(next(gen), FakeSession)
    with pytest.raises(StopIteration):
        next(gen)
    assert closed == [True]
