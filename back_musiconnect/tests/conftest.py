"""
Fixtures compartilhadas dos testes.

Testes que precisam de banco usam um banco SEPARADO (TEST_DATABASE_URL,
ex: musiconnect_test no PostGIS do Docker) — nunca o banco real. O nome
precisa terminar em "_test", senão os testes recusam rodar: as tabelas são
apagadas e recriadas a cada execução.

Cada teste roda dentro de uma transação desfeita no final, então um teste
não enxerga os dados de outro.
"""

import os

import pytest
from dotenv import load_dotenv
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session

from app.database import get_db
from app.main import app
from app.models import Base

load_dotenv()

TEST_DATABASE_URL = os.getenv("TEST_DATABASE_URL")


def _create_database_if_missing(url: str) -> None:
    target = make_url(url)
    admin = create_engine(
        target.set(database="postgres"), isolation_level="AUTOCOMMIT"
    )
    with admin.connect() as conn:
        exists = conn.execute(
            text("SELECT 1 FROM pg_database WHERE datname = :name"),
            {"name": target.database},
        ).scalar()
        if not exists:
            conn.execute(text(f'CREATE DATABASE "{target.database}"'))
    admin.dispose()


@pytest.fixture(scope="session")
def db_engine():
    if not TEST_DATABASE_URL:
        pytest.skip("TEST_DATABASE_URL não configurada — testes com banco ignorados.")
    if not make_url(TEST_DATABASE_URL).database.endswith("_test"):
        pytest.exit("TEST_DATABASE_URL precisa apontar para um banco terminado em '_test'.")

    _create_database_if_missing(TEST_DATABASE_URL)
    engine = create_engine(TEST_DATABASE_URL)
    with engine.begin() as conn:
        conn.execute(text("CREATE EXTENSION IF NOT EXISTS postgis"))
        conn.execute(text("CREATE EXTENSION IF NOT EXISTS unaccent"))
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    yield engine
    engine.dispose()


@pytest.fixture
def db_session(db_engine):
    connection = db_engine.connect()
    transaction = connection.begin()
    # Os commits das rotas viram savepoints dentro da transação do teste.
    session = Session(bind=connection, join_transaction_mode="create_savepoint")
    yield session
    session.close()
    transaction.rollback()
    connection.close()


@pytest.fixture
def api(db_session):
    """Cliente da API usando a sessão do banco de teste."""
    app.dependency_overrides[get_db] = lambda: db_session
    # Sem `with`: não roda o lifespan (migrações/agendador) da API.
    yield TestClient(app)
    app.dependency_overrides.clear()
