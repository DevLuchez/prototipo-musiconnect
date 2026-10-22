"""Construtores de dados para os testes que usam o banco de teste."""

from datetime import date, timedelta

from app.models import Institution, Opportunity, User
from app.routers.auth import _hash_password

SENHA = "Senha#123"


def make_user(db, **fields) -> User:
    data = {
        "email": "aluna@example.com",
        "password_hash": _hash_password(SENHA),
        "name": "Aluna",
        "email_confirmed": True,
        "instruments": ["Violino"],
        "is_student": True,
        "country": "Brasil",
        "state": "SC",
        "city": "Jaraguá do Sul",
    }
    data.update(fields)
    user = User(**data)
    db.add(user)
    db.commit()
    return user


def auth_headers(db, user: User, token: str = "sessao-teste") -> dict:
    """Simula um usuário logado (mesmo efeito do login)."""
    user.session_token = token
    db.commit()
    return {"Authorization": f"Bearer {token}"}


def make_opportunity(db, **fields) -> Opportunity:
    data = {
        "title": "Audição de violino",
        "type": "audicao",
        "source_url": f"https://example.com/opp/{fields.get('title', 'x')}-{id(fields)}",
        "source_name": "Musical Chairs",
        "instruments": ["Violino"],
        "country": "Brasil",
        "state": "SC",
        "city": "Jaraguá do Sul",
        "deadline": date.today() + timedelta(days=30),
        "is_active": True,
        "llm_confidence": 0.95,
    }
    data.update(fields)
    opp = Opportunity(**data)
    db.add(opp)
    db.commit()
    return opp


def make_institution(db, osm_id="node_1", name="Escola de Música", lat=-26.48, lng=-49.07) -> Institution:
    inst = Institution(
        osm_id=osm_id,
        name=name,
        lat=lat,
        lng=lng,
        category="music_school",
        source="osm",
        location=f"SRID=4326;POINT({lng} {lat})",
        verified=False,
    )
    db.add(inst)
    db.commit()
    return inst
