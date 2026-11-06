"""
GET /api/app/version — versão mais recente (do GitHub, simulado aqui) e
versão mínima do app.
"""

import pytest

import app.routers.app_version as app_version
from app.config import settings


@pytest.fixture
def github(monkeypatch):
    """GitHub simulado: devolve `releases[0]` (ou falha) e conta as consultas."""
    state = {"releases": ["1.2.2"], "calls": 0, "fail": False}

    def fake_fetch():
        state["calls"] += 1
        if state["fail"]:
            raise RuntimeError("GitHub fora do ar")
        return state["releases"][0]

    monkeypatch.setattr(app_version, "fetch_latest_release", fake_fetch)
    monkeypatch.setattr(app_version, "_cache", {"version": None, "fetched_at": 0.0})
    return state


def test_devolve_a_versao_mais_recente_sem_minima(api, github):
    body = api.get("/api/app/version").json()

    assert body["latest"] == "1.2.2"
    assert body["minimum"] is None
    assert body["download_url"].endswith("/musiconnect.apk")


def test_versao_minima_vem_da_configuracao(api, github, monkeypatch):
    monkeypatch.setattr(settings, "app_minimum_version", "1.2.0")

    assert api.get("/api/app/version").json()["minimum"] == "1.2.0"


def test_consulta_o_github_no_maximo_uma_vez_a_cada_10_minutos(api, github, monkeypatch):
    api.get("/api/app/version")
    github["releases"] = ["1.3.0"]
    assert api.get("/api/app/version").json()["latest"] == "1.2.2"
    assert github["calls"] == 1

    # Passados os 10 minutos, busca de novo.
    app_version._cache["fetched_at"] -= app_version.CACHE_TTL + 1
    assert api.get("/api/app/version").json()["latest"] == "1.3.0"


def test_github_fora_do_ar_mantem_a_ultima_versao_conhecida(api, github):
    api.get("/api/app/version")
    github["fail"] = True
    app_version._cache["fetched_at"] -= app_version.CACHE_TTL + 1

    assert api.get("/api/app/version").json()["latest"] == "1.2.2"


def test_github_fora_do_ar_desde_o_inicio_nao_avisa_nada(api, github):
    github["fail"] = True

    assert api.get("/api/app/version").json()["latest"] is None
