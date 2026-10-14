"""
Rotas de administração (disparo manual de scraper, LLM, ETL e resolvedor,
e status do agendador) só respondem com a chave `X-Admin-Key` correta.

Sem chave configurada no servidor (ADMIN_API_KEY vazia), ficam sempre
bloqueadas — esquecer de configurar nunca deixa as rotas abertas.

Os jobs são substituídos por versões falsas: os testes nunca disparam
scraping, Gemini ou ETL de verdade.
"""

import pytest
from fastapi.testclient import TestClient

import app.routers.opportunities as opportunities_router
import app.services.etl_task as etl_task
import app.services.institution_resolver as institution_resolver
from app.config import settings
from app.main import app

ADMIN_KEY = "chave-de-teste"

ADMIN_ROUTES = [
    ("POST", "/api/opportunities/scrape"),
    ("POST", "/api/opportunities/enrich"),
    ("POST", "/scheduler/run-etl"),
    ("POST", "/scheduler/resolve-institutions"),
    ("GET", "/scheduler/status"),
]


async def _fake_job(*args, **kwargs):
    return {}


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(settings, "admin_api_key", ADMIN_KEY)
    monkeypatch.setattr(opportunities_router, "_run_full_scrape", _fake_job)
    monkeypatch.setattr(opportunities_router, "enrich_opportunities", _fake_job)
    monkeypatch.setattr(etl_task, "run_full_etl", _fake_job)
    monkeypatch.setattr(
        institution_resolver, "resolve_opportunity_institutions", _fake_job
    )
    # Sem `with`: não roda o lifespan (banco/agendador) da API.
    return TestClient(app)


@pytest.mark.parametrize("method,path", ADMIN_ROUTES)
def test_sem_chave_e_bloqueado(client, method, path):
    assert client.request(method, path).status_code == 403


@pytest.mark.parametrize("method,path", ADMIN_ROUTES)
def test_chave_errada_e_bloqueada(client, method, path):
    response = client.request(method, path, headers={"X-Admin-Key": "errada"})
    assert response.status_code == 403


@pytest.mark.parametrize("method,path", ADMIN_ROUTES)
def test_chave_certa_e_aceita(client, method, path):
    response = client.request(method, path, headers={"X-Admin-Key": ADMIN_KEY})
    assert response.status_code == 200


@pytest.mark.parametrize("method,path", ADMIN_ROUTES)
def test_servidor_sem_chave_configurada_bloqueia_tudo(
    client, monkeypatch, method, path
):
    monkeypatch.setattr(settings, "admin_api_key", None)
    response = client.request(method, path, headers={"X-Admin-Key": ""})
    assert response.status_code == 403
