"""
Validação cruzada das instituições do OSM com o MusicBrainz e o Wikidata
(services/musicbrainz_validator.py e services/wikidata_validator.py):
casamento por nome + distância e gravação de verified/IDs/site.

Os dois serviços são simulados (httpx.MockTransport) — nenhum teste acessa
a rede.
"""

import asyncio

import httpx
import pytest

import app.services.musicbrainz_validator as mb
import app.services.wikidata_validator as wd
from app.models import Institution


def _inst(db, osm_id, name, lat=-26.48, lng=-49.07, category="concert_hall", **fields):
    inst = Institution(
        osm_id=osm_id, name=name, lat=lat, lng=lng, category=category, source="osm",
        location=f"SRID=4326;POINT({lng} {lat})", verified=False, **fields,
    )
    db.add(inst)
    db.commit()
    return inst


@pytest.fixture
def fake_http(monkeypatch, db_session):
    """Liga os validadores a um servidor simulado e à sessão de teste.
    `fake_http(handler)` define quem responde as requisições."""
    real_client = httpx.AsyncClient
    holder = {}

    def factory(*args, **kwargs):
        return real_client(transport=httpx.MockTransport(holder["handler"]))

    async def no_sleep(_):
        return None

    for module in (mb, wd):
        monkeypatch.setattr(module, "SessionLocal", lambda: db_session)
        monkeypatch.setattr(module.asyncio, "sleep", no_sleep)
    monkeypatch.setattr(httpx, "AsyncClient", factory)

    def install(handler):
        holder["handler"] = handler
    return install


# ── MusicBrainz: partes isoladas ─────────────────────────────────────────

def test_distancia_haversine():
    assert mb._haversine_m(0, 0, 0, 0) == 0
    # 0,001° de latitude ≈ 111 m
    assert 100 < mb._haversine_m(-26.480, -49.07, -26.481, -49.07) < 120


def test_melhor_casamento_exige_nome_parecido_e_lugar_proximo():
    places = [
        {"id": "longe", "name": "Teatro Municipal",
         "coordinates": {"latitude": "-23.55", "longitude": "-46.63"}},
        {"id": "outro-nome", "name": "Bar do Zé",
         "coordinates": {"latitude": "-26.48", "longitude": "-49.07"}},
        {"id": "certo", "name": "Teatro Municipal",
         "coordinates": {"latitude": "-26.4801", "longitude": "-49.0701"}},
    ]
    assert mb._best_match(places, "Teatro Municipal", -26.48, -49.07)["id"] == "certo"


def test_sem_coordenadas_confia_no_nome():
    places = [{"id": "x", "name": "Teatro Municipal"}]
    assert mb._best_match(places, "Teatro Municipal", 0, 0)["id"] == "x"
    assert mb._best_match([{"id": "y", "name": "Outro Lugar"}], "Teatro Municipal", 0, 0) is None


def test_site_oficial_das_relacoes():
    place = {"relations": [
        {"type": "wikipedia", "url": {"resource": "https://wiki"}},
        {"type": "official homepage", "url": {"resource": "https://teatro.org"}},
    ]}
    assert mb._extract_website(place) == "https://teatro.org"
    assert mb._extract_website({}) is None


# ── MusicBrainz: busca ───────────────────────────────────────────────────

def _mb_search(handler, name="Sala X", mb_type="Concert hall"):
    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await mb._search_mb_places(client, name, mb_type)
    return asyncio.run(run())


def test_busca_monta_a_consulta_com_nome_e_tipo():
    seen = {}

    def handler(request):
        seen["query"] = request.url.params["query"]
        return httpx.Response(200, json={"places": [{"id": "1"}]})

    assert _mb_search(handler) == [{"id": "1"}]
    assert seen["query"] == 'name:"Sala X" AND type:"Concert hall"'


def test_busca_sem_tipo_e_com_falhas(monkeypatch):
    async def no_sleep(_):
        return None
    monkeypatch.setattr(mb.asyncio, "sleep", no_sleep)

    def only_name(request):
        assert "type:" not in request.url.params["query"]
        return httpx.Response(200, json={})
    assert _mb_search(only_name, mb_type=None) == []

    assert _mb_search(lambda r: httpx.Response(503)) == []  # sobrecarga: espera e desiste
    assert _mb_search(lambda r: httpx.Response(404)) == []

    def broken(request):
        raise httpx.ConnectError("sem rede")
    assert _mb_search(broken) == []


# ── MusicBrainz: validação completa ──────────────────────────────────────

def test_validacao_marca_verificada_com_id_e_site(db_session, fake_http):
    _inst(db_session, "node_1", "Sala São Paulo", category="concert_hall")
    _inst(db_session, "node_2", "Escola Y", category="music_school")  # fora do escopo
    _inst(db_session, "node_3", "Casa Z", category="music_venue")

    def handler(request):
        if "Sala São Paulo" in request.url.params["query"]:
            return httpx.Response(200, json={"places": [{
                "id": "mb-1", "name": "Sala São Paulo",
                "coordinates": {"latitude": "-26.48", "longitude": "-49.07"},
                "relations": [{"type": "official homepage",
                               "url": {"resource": "https://salasaopaulo.art.br"}}],
            }]})
        return httpx.Response(200, json={"places": []})

    fake_http(handler)
    stats = asyncio.run(mb.run_musicbrainz_validation())

    assert stats == {"total": 2, "verified": 1}
    sala = db_session.get(Institution, "node_1")
    assert sala.verified and sala.mb_id == "mb-1"
    assert sala.website == "https://salasaopaulo.art.br"
    assert not db_session.get(Institution, "node_3").verified


# ── Wikidata ─────────────────────────────────────────────────────────────

@pytest.mark.parametrize(
    "wkt,expected",
    [("Point(-46.63 -23.55)", (-23.55, -46.63)), ("point( 10 20 )", (20.0, 10.0)),
     ("Polygon((0 0))", None), ("", None)],
)
def test_ponto_wkt(wkt, expected):
    assert wd._parse_wkt_point(wkt) == expected


def test_consulta_sparql_tem_os_tipos():
    q = wd._build_sparql(["Q24354", "Q153562"])
    assert "wd:Q24354 wd:Q153562" in q
    assert "wdt:P856" in q  # site oficial


def _binding(qid, name, lng, lat, website=None):
    b = {"item": {"value": f"http://www.wikidata.org/entity/{qid}"},
         "name": {"value": name}, "coords": {"value": f"Point({lng} {lat})"}}
    if website:
        b["website"] = {"value": website}
    return b


def test_busca_wikidata_converte_e_descarta_sem_coordenada():
    def handler(request):
        return httpx.Response(200, json={"results": {"bindings": [
            _binding("Q1", "Teatro A", -49.07, -26.48, "https://a.org"),
            {"item": {"value": "x/Q2"}, "name": {"value": "Sem ponto"},
             "coords": {"value": "inválido"}},
        ]}})

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await wd._fetch_wikidata(client, ["Q24354"])

    assert asyncio.run(run()) == [{"wikidata_id": "Q1", "name": "Teatro A",
                                   "lat": -26.48, "lng": -49.07, "website": "https://a.org"}]


def test_busca_wikidata_com_erro_devolve_vazio():
    async def run():
        transport = httpx.MockTransport(lambda r: httpx.Response(500))
        async with httpx.AsyncClient(transport=transport) as client:
            return await wd._fetch_wikidata(client, ["Q1"])
    assert asyncio.run(run()) == []


def test_validacao_wikidata_casa_por_nome_e_distancia(db_session, fake_http):
    _inst(db_session, "way_1", "Teatro Carlos Gomes", category="theatre")
    _inst(db_session, "way_2", "Teatro Longe", category="theatre", lat=-23.55, lng=-46.63)
    _inst(db_session, "way_3", "Nome Diferente", category="theatre")

    def handler(request):
        body = request.content.decode()
        if "Q24354" in body:  # só a categoria teatro tem itens
            return httpx.Response(200, json={"results": {"bindings": [
                _binding("Q10", "Teatro Carlos Gomes", -49.0701, -26.4801, "https://tcg.br"),
                _binding("Q11", "Teatro Longe", -49.07, -26.48),
                _binding("Q12", "Outra Coisa Qualquer", -49.07, -26.48),
            ]}})
        return httpx.Response(200, json={"results": {"bindings": []}})

    fake_http(handler)
    stats = asyncio.run(wd.run_wikidata_validation())

    assert stats == {"verified": 1}
    teatro = db_session.get(Institution, "way_1")
    assert teatro.verified and teatro.wikidata_id == "Q10"
    assert teatro.website == "https://tcg.br"
    assert not db_session.get(Institution, "way_2").verified
    assert not db_session.get(Institution, "way_3").verified


def test_validacao_wikidata_nao_troca_site_existente(db_session, fake_http):
    _inst(db_session, "way_1", "Teatro A", category="theatre", website="https://ja-tinha.br")

    fake_http(lambda r: httpx.Response(200, json={"results": {"bindings": [
        _binding("Q10", "Teatro A", -49.07, -26.48, "https://novo.br")]}}))
    asyncio.run(wd.run_wikidata_validation())

    assert db_session.get(Institution, "way_1").website == "https://ja-tinha.br"


def test_dois_pinos_do_mesmo_lugar_ficam_verificados_sem_repetir_o_id(db_session, fake_http):
    # Ex: o mesmo teatro mapeado como ponto e como polígono no OSM. O ID do
    # Wikidata é único no banco: só um fica com ele, os dois ficam verificados.
    _inst(db_session, "node_1", "Teatro A", category="theatre")
    _inst(db_session, "way_1", "Teatro A", category="theatre")

    fake_http(lambda r: httpx.Response(200, json={"results": {"bindings": [
        _binding("Q10", "Teatro A", -49.07, -26.48)]}}))
    stats = asyncio.run(wd.run_wikidata_validation())

    assert stats == {"verified": 2}
    db_session.expire_all()
    pinos = [db_session.get(Institution, i) for i in ("node_1", "way_1")]
    assert all(p.verified for p in pinos)
    assert sorted(p.wikidata_id or "" for p in pinos) == ["", "Q10"]


def test_musicbrainz_dois_pinos_do_mesmo_lugar(db_session, fake_http):
    _inst(db_session, "node_1", "Sala X", category="concert_hall")
    _inst(db_session, "way_1", "Sala X", category="concert_hall")

    fake_http(lambda r: httpx.Response(200, json={"places": [{
        "id": "mb-1", "name": "Sala X",
        "coordinates": {"latitude": "-26.48", "longitude": "-49.07"}}]}))
    stats = asyncio.run(mb.run_musicbrainz_validation())

    assert stats == {"total": 2, "verified": 2}
    db_session.expire_all()
    pinos = [db_session.get(Institution, i) for i in ("node_1", "way_1")]
    assert all(p.verified for p in pinos)
    assert sorted(p.mb_id or "" for p in pinos) == ["", "mb-1"]
