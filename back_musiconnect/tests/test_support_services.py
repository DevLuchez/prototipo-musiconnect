"""
Serviços de apoio: envio de e-mail (Resend), geocodificação (Nominatim),
teste e gravação de site/e-mail das instituições e a gravação do ETL do OSM
no banco.

Resend, Nominatim e os sites das instituições são sempre simulados
(httpx.MockTransport) — nenhum teste acessa a rede.
"""

import asyncio

import httpx
import pytest

import app.services.email_service as email_service
import app.services.institution_factory as factory
import app.services.osm_contacts as contacts
import app.services.osm_etl as etl
from app.models import Institution
from tests.helpers import make_institution


# Guardado antes de qualquer teste trocar o httpx.AsyncClient — assim
# _mock_client pode ser chamado mais de uma vez no mesmo teste.
_REAL_CLIENT = httpx.AsyncClient


def _mock_client(monkeypatch, handler):
    """Faz o `httpx.AsyncClient(...)` criado dentro do serviço usar o servidor simulado."""
    monkeypatch.setattr(
        httpx, "AsyncClient",
        lambda *a, **kw: _REAL_CLIENT(transport=httpx.MockTransport(handler),
                                      follow_redirects=kw.get("follow_redirects", False)),
    )


# ── E-mail (Resend) ──────────────────────────────────────────────────────

def test_links_dos_emails_usam_o_dominio_publico(monkeypatch):
    monkeypatch.setattr(email_service.settings, "public_base_url", "https://app.exemplo")
    assert email_service.build_confirmation_link("abc") == "https://app.exemplo/confirmar?token=abc"
    assert (email_service.build_reset_password_link("xyz")
            == "https://app.exemplo/redefinir-senha?token=xyz")


def test_sem_chave_do_resend_nao_envia(monkeypatch):
    monkeypatch.setattr(email_service.settings, "resend_api_key", None)
    sent = asyncio.run(email_service.send_confirmation_email(to_email="a@b.com", token="t"))
    assert sent is False


def test_envio_de_confirmacao_aceito(monkeypatch):
    monkeypatch.setattr(email_service.settings, "resend_api_key", "chave")
    seen = {}

    def handler(request):
        seen["auth"] = request.headers["Authorization"]
        seen["body"] = request.read().decode()
        return httpx.Response(200, json={"id": "1"})

    _mock_client(monkeypatch, handler)
    sent = asyncio.run(email_service.send_confirmation_email(to_email="aluna@x.com", token="tok"))

    assert sent is True
    assert seen["auth"] == "Bearer chave"
    assert "aluna@x.com" in seen["body"] and "confirmar?token=tok" in seen["body"]


def test_envio_de_redefinicao_recusado_ou_sem_rede(monkeypatch):
    monkeypatch.setattr(email_service.settings, "resend_api_key", "chave")

    _mock_client(monkeypatch, lambda r: httpx.Response(422, json={"message": "inválido"}))
    assert asyncio.run(email_service.send_password_reset_email(to_email="a@b.com", token="t")) is False

    def broken(request):
        raise httpx.ConnectError("sem rede")
    _mock_client(monkeypatch, broken)
    assert asyncio.run(email_service.send_password_reset_email(to_email="a@b.com", token="t")) is False


# ── Geocodificação (Nominatim) ───────────────────────────────────────────

def test_nome_normalizado_e_id_de_reserva():
    assert factory.normalize_name("ORQUESTRA SINFÔNICA  de S.C.") == "orquestra sinfonica de s c"
    assert factory.normalize_name(None) == ""
    a = factory._fallback_id("Orquestra Municipal", "Jaraguá do Sul", "Brasil")
    b = factory._fallback_id("Orquestra Municipal", "Joinville", "Brasil")
    assert a.startswith("pl_") and a != b  # mesma orquestra em cidades diferentes


@pytest.fixture
def nominatim(monkeypatch):
    """Sem espera real entre consultas; `nominatim(handler)` roda o geocode."""
    async def no_sleep(_):
        return None
    monkeypatch.setattr(factory.asyncio, "sleep", no_sleep)
    monkeypatch.setattr(factory, "_last_request_at", 0.0)

    def run(handler, fn=factory.geocode, query="SCAR, Jaraguá do Sul"):
        async def go():
            async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
                return await fn(client, query)
        return asyncio.run(go())
    return run


def test_geocode_devolve_o_primeiro_resultado(nominatim):
    def handler(request):
        assert request.url.params["extratags"] == "1"
        return httpx.Response(200, json=[{"osm_type": "way", "osm_id": 1}, {"osm_id": 2}])
    assert nominatim(handler) == {"osm_type": "way", "osm_id": 1}


def test_geocode_sem_resultado_ou_com_erro(nominatim):
    assert nominatim(lambda r: httpx.Response(200, json=[])) is None
    assert nominatim(lambda r: httpx.Response(500)) is None


def test_geocode_place_recusa_cidades_e_regioes(nominatim):
    cidade = lambda r: httpx.Response(200, json=[{"category": "place", "osm_id": 1}])
    teatro = lambda r: httpx.Response(200, json=[{"category": "amenity", "osm_id": 2}])
    assert nominatim(cidade, fn=factory.geocode_place) is None
    assert nominatim(teatro, fn=factory.geocode_place)["osm_id"] == 2


# ── Site e e-mail das instituições ───────────────────────────────────────

def test_site_no_ar_bloqueado_para_robo_ou_fora_do_ar(monkeypatch):
    def handler(request):
        host = request.url.host
        if host == "ok.org":
            return httpx.Response(200)
        if host == "cloudflare.org":
            return httpx.Response(403)  # existe, só recusa robôs
        if host == "sumiu.org":
            return httpx.Response(404)
        raise httpx.ConnectError("domínio não existe")

    _mock_client(monkeypatch, handler)
    alive = asyncio.run(contacts._alive_sites(
        {"https://ok.org", "https://cloudflare.org", "https://sumiu.org", "https://expirou.org"}))

    assert alive == {"https://ok.org", "https://cloudflare.org"}


def test_grava_site_no_ar_e_email_sem_sobrescrever_o_que_ja_existe(monkeypatch, db_session):
    make_institution(db_session, osm_id="node_1", name="Sem nada")
    make_institution(db_session, osm_id="node_2", name="Já tem site")
    db_session.get(Institution, "node_2").website = "https://wikidata-site.org"
    make_institution(db_session, osm_id="node_3", name="Site morto")
    db_session.commit()

    async def fake_alive(urls):
        return {u for u in urls if "morto" not in u}
    monkeypatch.setattr(contacts, "_alive_sites", fake_alive)

    sites, emails, dead = asyncio.run(contacts.save_contacts(db_session, {
        "node_1": ("https://escola.org", "contato@escola.org"),
        "node_2": ("https://osm-site.org", None),
        "node_3": ("https://morto.org", None),
        "node_9": ("https://nao-existe-no-banco.org", None),
        "node_vazio": (None, None),
    }))

    assert (sites, emails, dead) == (1, 1, 1)
    db_session.expire_all()
    assert db_session.get(Institution, "node_1").website == "https://escola.org"
    assert db_session.get(Institution, "node_1").email == "contato@escola.org"
    assert db_session.get(Institution, "node_2").website == "https://wikidata-site.org"
    assert db_session.get(Institution, "node_3").website is None


def test_simulacao_nao_grava_nada(monkeypatch, db_session):
    make_institution(db_session, osm_id="node_1")

    async def fake_alive(urls):
        return set(urls)
    monkeypatch.setattr(contacts, "_alive_sites", fake_alive)

    result = asyncio.run(contacts.save_contacts(
        db_session, {"node_1": ("https://a.org", "a@a.org")}, dry_run=True))

    assert result == (1, 1, 0)
    db_session.expire_all()
    assert db_session.get(Institution, "node_1").website is None


def test_sem_contatos_nao_consulta_o_banco(db_session):
    assert asyncio.run(contacts.save_contacts(db_session, {"node_1": (None, None)})) == (0, 0, 0)


# ── ETL do OSM: gravação no banco ────────────────────────────────────────

def _record(osm_id, name, lat=-26.48, lng=-49.07):
    return {"osm_id": osm_id, "name": name, "address": None, "lat": lat, "lng": lng,
            "category": "theatre", "source": "osm",
            "location": f"SRID=4326;POINT({lng} {lat})"}


def test_upsert_insere_e_atualiza_sem_apagar_validacoes(db_session):
    make_institution(db_session, osm_id="way_1", name="Nome antigo")
    inst = db_session.get(Institution, "way_1")
    inst.verified, inst.website = True, "https://validado.org"
    db_session.commit()

    n = etl._upsert_batch(db_session, [_record("way_1", "Nome novo"), _record("node_2", "Nova")])

    assert n == 2
    db_session.expire_all()
    atualizada = db_session.get(Institution, "way_1")
    assert atualizada.name == "Nome novo"
    assert atualizada.verified is True and atualizada.website == "https://validado.org"
    assert db_session.get(Institution, "node_2").verified is False
    assert etl._upsert_batch(db_session, []) == 0


def test_elemento_invalido_e_ignorado():
    assert etl._parse_element({"type": "node", "id": 1, "lat": "x", "lon": 0,
                               "tags": {"name": "A"}}) is None
    assert etl._parse_element({"type": "node", "id": 1, "lat": 0, "lon": 0,
                               "tags": {"name": "Sem coordenada"}}) is None


def test_run_etl_grava_pinos_e_contatos(monkeypatch, db_session):
    async def fake_collect(client):
        rec = _record("way_7", "Teatro Novo")
        rec.update(website="https://teatro.org", email=None)
        sem_contato = _record("node_8", "Sala")
        sem_contato.update(website=None, email=None)
        return {"way_7": rec, "node_8": sem_contato}

    saved = {}

    async def fake_save(db, chunk):
        saved.update(chunk)
        return (1, 0, 0)

    monkeypatch.setattr(etl, "_collect_records", fake_collect)
    monkeypatch.setattr(etl, "save_contacts", fake_save)
    monkeypatch.setattr(etl, "SessionLocal", lambda: db_session)

    stats = asyncio.run(etl.run_etl())

    assert stats == {"types_processed": len(etl.OSM_TAGS), "records_upserted": 2,
                     "records_removed": 0}
    assert db_session.get(Institution, "way_7").name == "Teatro Novo"
    assert saved == {"way_7": ("https://teatro.org", None)}  # só quem tem contato


def test_site_sem_dominio_e_descartado():
    assert contacts.extract_contacts({"website": "localhost"}) == (None, None)


def test_organizadora_sem_objeto_do_osm_ganha_id_de_reserva(monkeypatch, db_session):
    async def fake_place(client, query):
        return {"lat": "-26.48", "lon": "-49.07", "display_name": "Jaraguá do Sul"}

    async def no_contacts(db, data):
        return (0, 0, 0)

    monkeypatch.setattr(factory, "geocode_place", fake_place)
    monkeypatch.setattr(factory, "save_contacts", no_contacts)

    async def run():
        async with httpx.AsyncClient() as client:
            return await factory.get_or_create_institution(
                db_session, client, name="Festival X", city="Jaraguá do Sul",
                country="Brasil", category="categoria-inventada")

    osm_id = asyncio.run(run())

    assert osm_id == factory._fallback_id("Festival X", "Jaraguá do Sul", "Brasil")
    inst = db_session.get(Institution, osm_id)
    assert inst.source == "pipeline"
    assert inst.category == factory.DEFAULT_CATEGORY  # categoria inválida não é usada
