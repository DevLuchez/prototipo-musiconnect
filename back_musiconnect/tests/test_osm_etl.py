"""
ETL do OpenStreetMap via QLever (services/osm_etl.py): consultas por tipo,
paginação com retry, junção de pinos + tags, as regras do _parse_element
(correções manuais, nome, categoria, endereço) e a remoção das que saíram
do OSM.

O QLever e a API do OSM são simulados (httpx.MockTransport) — nenhum teste
acessa a rede.
"""

import asyncio
import json

import httpx
import pytest

import app.services.osm_etl as etl

NODE = f"{etl.OSM_IRI}node/1"
WAY = f"{etl.OSM_IRI}way/2"
REL = f"{etl.OSM_IRI}relation/3"


def _geo(iri, lat, lng):
    return {"o": {"value": iri}, "lat": {"value": str(lat)}, "lng": {"value": str(lng)}}


def _tag(iri, tag, value):
    return {"o": {"value": iri}, "p": {"value": etl.OSM_KEY_IRI + tag}, "v": {"value": value}}


def _bindings(rows):
    return httpx.Response(200, json={"results": {"bindings": rows}})


@pytest.fixture(autouse=True)
def sem_espera(monkeypatch):
    """Retry sem dormir de verdade."""
    async def no_sleep(_):
        return None
    monkeypatch.setattr(etl.asyncio, "sleep", no_sleep)


def _fetch(handler, query="SELECT ?o WHERE {}"):
    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await etl._fetch_all_pages(client, query, "teste")
    return asyncio.run(run())


# ── Consultas ────────────────────────────────────────────────────────────

def test_consulta_de_pinos_calcula_centroide_e_ordena_para_paginar():
    q = etl._build_geo_query("amenity", "theatre")
    assert 'osmkey:amenity "theatre"' in q
    assert "geof:centroid" in q
    assert q.rstrip().endswith("ORDER BY ?o")


def test_consulta_de_tags_traz_so_as_tags_lidas_pelo_parser():
    q = etl._build_tags_query("leisure", "music_venue")
    assert 'osmkey:leisure "music_venue"' in q
    for tag in ("name", "addr:city", "contact:website", "email"):
        assert f"osmkey:{tag}" in q
    assert "OPTIONAL" not in q  # OPTIONAL com muitas tags trava o servidor


# ── Paginação ────────────────────────────────────────────────────────────

def test_paginacao_segue_ate_a_pagina_incompleta(monkeypatch):
    monkeypatch.setattr(etl, "PAGE_SIZE", 2)
    pages = {0: [_geo(NODE, 1, 1), _geo(WAY, 2, 2)], 2: [_geo(REL, 3, 3)]}
    offsets = []

    def handler(request):
        query = request.url.params["query"]
        offset = int(query.rsplit("OFFSET ", 1)[1])
        assert f"LIMIT 2 OFFSET {offset}" in query
        offsets.append(offset)
        return _bindings(pages[offset])

    rows = _fetch(handler)
    assert offsets == [0, 2]
    assert [r["o"]["value"] for r in rows] == [NODE, WAY, REL]


def test_pagina_com_falha_e_repetida():
    calls = []

    def handler(request):
        calls.append(1)
        if len(calls) == 1:
            # Erro de consulta do QLever: JSON com status ERROR
            return httpx.Response(500, json={"status": "ERROR", "exception": "x"})
        if len(calls) == 2:
            # Resposta cortada no meio (conexão fechada pelo servidor)
            return httpx.Response(200, content=b'{"results": {"bindi')
        return _bindings([_geo(NODE, 1, 1)])

    rows = _fetch(handler)
    assert len(calls) == 3
    assert len(rows) == 1


def test_falha_persistente_interrompe_o_etl_em_vez_de_seguir_vazio():
    # Antes (Overpass) uma célula que falhava virava lista vazia e o ETL
    # seguia como se não houvesse instituições ali.
    def handler(request):
        return httpx.Response(502)

    with pytest.raises(RuntimeError, match="QLever falhou"):
        _fetch(handler)


# ── Junção de pinos + tags ───────────────────────────────────────────────

def test_junta_pinos_e_tags_no_formato_do_osm():
    geo = [_geo(NODE, -26.5, -49.1), _geo(WAY, 10, 20)]
    tags = [
        _tag(NODE, "name", "Escola A"),
        _tag(NODE, "amenity", "music_school"),
        _tag(WAY, "name", "Teatro B"),
    ]
    node, way = etl._build_elements(geo, tags)

    assert node == {"type": "node", "id": 1, "lat": -26.5, "lon": -49.1,
                    "tags": {"name": "Escola A", "amenity": "music_school"}}
    assert way == {"type": "way", "id": 2, "center": {"lat": 10.0, "lon": 20.0},
                   "tags": {"name": "Teatro B"}}


def test_relacoes_e_pinos_sem_centroide_ficam_de_fora():
    geo = [_geo(REL, 1, 1), {"o": {"value": NODE}}]
    assert etl._build_elements(geo, []) == []


def test_tag_com_varios_valores_fica_com_o_primeiro():
    tags = [_tag(NODE, "name", "Primeiro"), _tag(NODE, "name", "Segundo")]
    [elem] = etl._build_elements([_geo(NODE, 1, 1)], tags)
    assert elem["tags"]["name"] == "Primeiro"


# ── Regras do _parse_element ─────────────────────────────────────────────

def test_scar_aparece_com_o_nome_corrigido():
    elem = {"type": "way", "id": 256649111, "center": {"lat": -26.48, "lon": -49.07},
            "tags": {"name": "Teatro Scar", "amenity": "arts_centre"}}
    record = etl._parse_element(elem)
    assert record["osm_id"] == "way_256649111"
    assert record["name"] == "SCAR – Sociedade Cultura Artística"
    assert record["category"] == "arts_centre"


def test_sem_nome_e_descartado_mas_aceita_name_en():
    base = {"type": "node", "id": 9, "lat": 1.0, "lon": 1.0}
    assert etl._parse_element({**base, "tags": {"amenity": "theatre"}}) is None
    record = etl._parse_element({**base, "tags": {"name:en": "Hall", "amenity": "theatre"}})
    assert record["name"] == "Hall"


def test_registro_completo_pronto_para_o_upsert():
    elem = {"type": "node", "id": 5, "lat": -23.5, "lon": -46.6, "tags": {
        "name": "Sala X", "leisure": "music_venue",
        "addr:street": "Rua A", "addr:city": "São Paulo",
        "website": "salax.com.br", "email": "mailto:contato@salax.com.br",
    }}
    record = etl._parse_element(elem)
    assert record == {
        "osm_id": "node_5", "name": "Sala X", "address": "Rua A, São Paulo",
        "lat": -23.5, "lng": -46.6, "category": "music_venue",
        "website": "https://salax.com.br", "email": "contato@salax.com.br",
        "source": "osm", "location": "SRID=4326;POINT(-46.6 -23.5)",
    }


def test_ignorados_saem_da_coleta(monkeypatch):
    monkeypatch.setattr(etl, "OSM_IGNORED_IDS", {"node_7"})
    elem = {"type": "node", "id": 7, "lat": 1.0, "lon": 1.0, "tags": {"name": "Duplicado"}}
    assert etl._parse_element(elem) is None


# ── Coleta completa (todos os tipos) ─────────────────────────────────────

def test_coleta_todos_os_tipos_sem_repetir_objeto(monkeypatch):
    monkeypatch.setattr(etl, "OSM_TAGS", [("amenity", "theatre"), ("amenity", "arts_centre")])

    def handler(request):
        query = request.url.params["query"]
        is_geo = "geof:centroid" in query
        if '"theatre"' in query:
            rows = [_geo(NODE, 1, 1)] if is_geo else [_tag(NODE, "name", "T"), _tag(NODE, "amenity", "theatre")]
        else:
            # O mesmo objeto também marcado como arts_centre, e um novo
            rows = ([_geo(NODE, 1, 1), _geo(WAY, 2, 2)] if is_geo
                    else [_tag(NODE, "name", "T"), _tag(WAY, "name", "C"), _tag(WAY, "amenity", "arts_centre")])
        return _bindings(rows)

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await etl._collect_records(client)

    records = asyncio.run(run())
    assert set(records) == {"node_1", "way_2"}
    assert records["node_1"]["category"] == "theatre"  # fica o primeiro tipo
    assert records["way_2"]["category"] == "arts_centre"
    json.dumps(list(records.values()))  # registros serializáveis, sem objetos


# ── Instituições que saíram do OSM ───────────────────────────────────────

def _osm_api(responses: dict):
    """API do OSM simulada: caminho → (status, tags). Registra os pedidos."""
    requested = []

    def handler(request):
        path = request.url.path.removeprefix("/api/0.6/").removesuffix(".json")
        requested.append(path)
        status, tags = responses[path]
        if status != 200:
            return httpx.Response(status)
        return httpx.Response(200, json={"elements": [{"tags": tags}]})

    return handler, requested


@pytest.fixture
def osm_api(monkeypatch):
    def install(responses):
        handler, requested = _osm_api(responses)
        real_client = httpx.AsyncClient
        monkeypatch.setattr(
            etl.httpx, "AsyncClient",
            lambda **kw: real_client(transport=httpx.MockTransport(handler), **kw),
        )
        return requested
    return install


def test_remove_so_as_que_sairam_ou_deixaram_de_ser_musicais(osm_api, db_session, monkeypatch):
    from app.models import FavoriteInstitution, Institution, Opportunity
    from tests.helpers import make_institution, make_opportunity, make_user

    for osm_id in ("node_1", "node_2", "node_3", "node_4", "node_5", "way_6", "node_7"):
        make_institution(db_session, osm_id=osm_id, name=osm_id)
    # Organizadoras achadas pelo sistema: só se confere se ainda existem.
    for osm_id in ("way_20", "relation_21", "pl_abc"):
        make_institution(db_session, osm_id=osm_id, name=osm_id).source = "pipeline"
    user = make_user(db_session)
    db_session.add(FavoriteInstitution(user_id=user.id, institution_id="node_2"))
    opp = make_opportunity(db_session, institution_id="node_2")
    db_session.commit()
    monkeypatch.setattr(etl, "OSM_IGNORED_IDS", {"node_7"})

    requested = osm_api({
        "node/2": (410, None),                                # apagada do OSM
        "node/3": (200, {"amenity": "cinema"}),               # virou cinema
        "node/4": (200, {"amenity": "theatre"}),              # QLever atrasado: fica
        "node/5": (503, None),                                # API fora: fica
        "way/6": (200, {"disused:amenity": "theatre"}),       # desativada
        "way/20": (200, {"building": "yes"}),                 # organizadora existe: fica
        "relation/21": (410, None),                           # organizadora apagada
    })

    removed = asyncio.run(etl.remove_closed_institutions(db_session, {"node_1"}))

    assert removed == 5
    db_session.expire_all()
    remaining = {i.osm_id for i in db_session.query(Institution)}
    assert remaining == {"node_1", "node_4", "node_5", "way_20", "pl_abc"}
    # Sai dos favoritos e a oportunidade perde só o pino.
    assert db_session.query(FavoriteInstitution).count() == 0
    assert db_session.get(Opportunity, opp.id).institution_id is None
    # Confere quem ficou fora da coleta e as organizadoras com objeto do OSM
    # (o ignorado sai direto; "pl_" não tem objeto no OSM).
    assert sorted(requested) == ["node/2", "node/3", "node/4", "node/5",
                                 "relation/21", "way/20", "way/6"]


def test_nada_fora_da_coleta_nao_consulta_a_api(osm_api, db_session):
    from tests.helpers import make_institution

    make_institution(db_session, osm_id="node_1")
    requested = osm_api({})

    assert asyncio.run(etl.remove_closed_institutions(db_session, {"node_1"})) == 0
    assert requested == []


def test_muitas_de_uma_vez_indica_problema_e_nao_remove(osm_api, db_session, monkeypatch):
    from app.models import Institution
    from tests.helpers import make_institution

    monkeypatch.setattr(etl, "MAX_REMOVAL_CHECKS", 2)
    for osm_id in ("node_1", "node_2", "node_3"):
        make_institution(db_session, osm_id=osm_id)
    make_institution(db_session, osm_id="node_9").source = "pipeline"
    db_session.commit()
    requested = osm_api({"node/9": (410, None)})

    # As do ETL ficam (sinal de problema na fonte); as organizadoras seguem
    # sendo conferidas.
    assert asyncio.run(etl.remove_closed_institutions(db_session, set())) == 1
    assert requested == ["node/9"]
    assert db_session.query(Institution).count() == 3


def test_resposta_estranha_da_api_mantem_a_instituicao():
    def handler(request):
        return httpx.Response(200, text="não é json")

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            return await etl._osm_tags(client, "node_1")

    assert asyncio.run(run()) is None
