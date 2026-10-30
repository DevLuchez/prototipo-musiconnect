import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/data/models/opportunity_model.dart';
import 'package:prototipo_musiconnect/data/models/place_model.dart';
import 'package:prototipo_musiconnect/data/services/musicconnect_api_service.dart';
import 'package:prototipo_musiconnect/data/services/opportunities_service.dart';
import 'package:prototipo_musiconnect/presentation/view_models/map_explorer_view_model.dart';

import '../helpers/fakes.dart';

PlaceModel _place(String osmId, {
  String name = 'Escola',
  String category = 'music_school',
  int opportunities = 0,
  String? address,
}) =>
    PlaceModel(
      id: 'backend_$osmId',
      osmId: osmId,
      name: name,
      address: address,
      lat: -26.48,
      lng: -49.07,
      category: category,
      activeOpportunitiesCount: opportunities,
    );

CityOpportunities _city(int id) =>
    CityOpportunities(id: id, city: 'Cidade $id', lat: 1, lng: 1, count: 2);

/// Servidor simulado: [online], [all] na carga inicial, [nearby] ao mover o
/// mapa, [searchResult] na busca (null = falhou) e [byId] no "Ver no mapa".
class _FakeApi implements MusicConnectApiService {
  bool online = true;
  List<PlaceModel> all = [];
  List<PlaceModel> nearby = [];
  List<PlaceModel>? searchResult = [];
  Map<String, PlaceModel> byId = {};
  final searched = <String>[];
  int nearbyCalls = 0;

  /// Faz a próxima busca esperar até [releaseSearch] (resposta atrasada).
  Completer<void>? searchGate;

  @override
  Future<bool> isReachable() async => online;

  @override
  Future<List<PlaceModel>> fetchAll({int limit = 5000}) async => all;

  @override
  Future<({int total, int withOpportunities})?> fetchStats() async =>
      (total: 82652, withOpportunities: 80);

  @override
  Future<List<PlaceModel>> fetchNearby({
    required double lat,
    required double lng,
    int radiusM = 50000,
    int limit = 500,
  }) async {
    nearbyCalls++;
    return nearby;
  }

  @override
  Future<List<PlaceModel>?> search(String query, {int limit = 8}) async {
    searched.add(query);
    await searchGate?.future;
    return searchResult;
  }

  @override
  Future<PlaceModel?> fetchById(String osmId) async => byId[osmId];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOpportunities implements OpportunitiesService {
  List<CityOpportunities> cities = [];
  int cityCalls = 0;
  int? askedCityLocation;
  String? askedInstitution;

  @override
  Future<List<CityOpportunities>> fetchCities() async {
    cityCalls++;
    return cities;
  }

  @override
  Future<List<OpportunityModel>> fetchByInstitution(String osmId) async {
    askedInstitution = osmId;
    return [fakeOpportunity(1)];
  }

  @override
  Future<OpportunitiesResult> fetchOpportunities({
    String? q,
    List<String>? types,
    List<String>? instruments,
    List<String>? countries,
    List<String>? states,
    List<String>? cities,
    int? cityLocationId,
    bool onlyActive = true,
    int limit = 100,
    int offset = 0,
  }) async {
    askedCityLocation = cityLocationId;
    return OpportunitiesResult(items: [fakeOpportunity(2)], total: 1);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _groups = {
  'music_school': {'music_school'},
  'concert_hall': {'concert_hall', 'arts_centre'},
  'theatre': {'theatre'},
};

void main() {
  late _FakeApi api;
  late _FakeOpportunities opportunities;

  MapExplorerViewModel build() => MapExplorerViewModel(
        filterGroups: _groups,
        apiService: api,
        opportunitiesService: opportunities,
        searchDebounce: Duration.zero,
      );

  setUp(() {
    api = _FakeApi();
    opportunities = _FakeOpportunities();
  });

  group('carga', () {
    test('carga inicial traz instituições, estatísticas e cidades', () async {
      api.all = [_place('n1'), _place('n2')];
      opportunities.cities = [_city(1)];
      final vm = build();
      expect(vm.isLoading, isTrue);

      await vm.initialLoad();

      expect(vm.isLoading, isFalse);
      expect(vm.initialLoadDone, isTrue);
      expect(vm.places.length, 2);
      expect(vm.cities.single.id, 1);
      expect(vm.catalogSummary,
          '82652 instituições catalogadas na base de dados, 80 com oportunidades abertas.');
    });

    test('antes das estatísticas, a legenda avisa que está carregando', () {
      expect(build().catalogSummary, 'Carregando total de instituições catalogadas...');
    });

    test('servidor fora do ar: aviso e nada é carregado', () async {
      api.online = false;
      final vm = build();

      await vm.initialLoad();

      expect(vm.backendOffline, isTrue);
      expect(vm.initialLoadDone, isTrue);
      expect(vm.places, isEmpty);

      await vm.loadNearby(0, 0);
      expect(api.nearbyCalls, 0); // não tenta de novo ao mover o mapa
    });

    test('mover o mapa soma instituições, sem repetir as já carregadas', () async {
      api.all = [_place('n1')];
      api.nearby = [_place('n1'), _place('n3')];
      final vm = build();
      await vm.initialLoad();

      await vm.loadNearby(-26.4, -49.0);

      expect(vm.places.map((p) => p.osmId), ['n1', 'n3']);
    });

    test('não começa outra carga enquanto uma está em andamento', () async {
      final vm = build(); // isLoading começa true (carga inicial)
      await vm.loadNearby(0, 0);
      expect(api.nearbyCalls, 0);
    });
  });

  group('zoom', () {
    test('pinos somem abaixo do zoom mínimo e voltam acima', () {
      final vm = build();
      var notified = 0;
      vm.addListener(() => notified++);

      vm.onZoomChanged(12);
      expect(notified, 0); // já estava visível: não redesenha à toa

      vm.onZoomChanged(5);
      expect(vm.showMarkers, isFalse);

      vm.onZoomChanged(MapExplorerViewModel.markersMinZoom);
      expect(vm.showMarkers, isTrue);
      expect(notified, 2);
    });
  });

  group('filtros', () {
    late MapExplorerViewModel vm;

    setUp(() async {
      api.all = [
        _place('escola', category: 'music_school'),
        _place('centro', category: 'arts_centre', opportunities: 2),
        _place('teatro', category: 'theatre'),
        _place('ruido', category: 'tag_desconhecida'),
      ];
      vm = build();
      await vm.initialLoad();
    });

    test('sem filtro, todos aparecem — inclusive categorias desconhecidas', () {
      expect(vm.activeFilterCount, 0);
      expect(vm.visiblePlaces.length, 4);
    });

    test('um grupo cobre categorias equivalentes do OSM', () {
      vm.applyFilters(keys: {'concert_hall'}, onlyWithOpportunities: false, showCityMarkers: true);

      expect(vm.visiblePlaces.map((p) => p.osmId), ['centro']); // arts_centre
      expect(vm.activeFilterCount, 2); // dois tipos desmarcados
    });

    test('só com oportunidades abertas e esconder cidades contam como filtro', () {
      vm.applyFilters(keys: _groups.keys.toSet(), onlyWithOpportunities: true,
          showCityMarkers: false);

      expect(vm.visiblePlaces.map((p) => p.osmId), ['centro']);
      expect(vm.activeFilterCount, 2);
      expect(vm.showCityMarkers, isFalse);
    });
  });

  group('busca', () {
    test('menos de 2 letras não busca', () async {
      final vm = build();

      vm.onSearchChanged('a');
      await Future<void>.delayed(Duration.zero);

      expect(api.searched, isEmpty);
      expect(vm.showSearchResults, isFalse);
    });

    test('mostra os resultados do servidor', () async {
      api.searchResult = [_place('n1', name: 'SCAR')];
      final vm = build();

      vm.onSearchChanged('  scar ');
      await Future<void>.delayed(Duration.zero);

      expect(api.searched, ['scar']);
      expect(vm.showSearchResults, isTrue);
      expect(vm.searchResults.single.name, 'SCAR');
    });

    test('servidor falhou: busca no que já está carregado (nome ou endereço)', () async {
      api.all = [
        _place('n1', name: 'Teatro Municipal'),
        _place('n2', name: 'Escola', address: 'Rua do Teatro, 10'),
        _place('n3', name: 'Outra'),
      ];
      api.searchResult = null;
      final vm = build();
      await vm.initialLoad();

      vm.onSearchChanged('teatro');
      await Future<void>.delayed(Duration.zero);

      expect(vm.searchResults.map((p) => p.osmId), ['n1', 'n2']);
    });

    test('resposta atrasada de um termo já alterado é descartada', () async {
      api.searchResult = [_place('velho')];
      api.searchGate = Completer();
      final vm = build();

      vm.onSearchChanged('vel');
      await Future<void>.delayed(Duration.zero); // busca de "vel" em andamento
      vm.clearSearch();
      api.searchGate!.complete();
      await Future<void>.delayed(Duration.zero);

      expect(vm.showSearchResults, isFalse);
      expect(vm.searchResults, isEmpty);
    });
  });

  group('"Ver no mapa"', () {
    test('acha a instituição carregada ou busca no servidor', () async {
      api.all = [_place('n1')];
      api.byId = {'n9': _place('n9')};
      final vm = build();
      await vm.initialLoad();

      expect((await vm.findInstitution('n1'))?.osmId, 'n1');
      expect((await vm.findInstitution('n9'))?.osmId, 'n9');
      expect(await vm.findInstitution('nao_existe'), isNull);
    });

    test('revelar um pino escondido pelos filtros limpa os filtros', () async {
      api.all = [_place('teatro', category: 'theatre')];
      final vm = build();
      await vm.initialLoad();
      vm.applyFilters(keys: {'music_school'}, onlyWithOpportunities: true, showCityMarkers: true);

      final shown = vm.reveal(_place('teatro', category: 'theatre'));

      expect(shown, same(vm.places.single)); // usa a instância já no mapa
      expect(vm.activeFilterCount, 0);
    });

    test('revelar um pino ainda não carregado adiciona ele', () async {
      final vm = build();

      vm.reveal(_place('novo'));

      expect(vm.places.single.osmId, 'novo');
    });

    test('cidade criada depois da carga: recarrega e mostra as cidades', () async {
      final vm = build();
      await vm.initialLoad();
      vm.applyFilters(keys: _groups.keys.toSet(), onlyWithOpportunities: false,
          showCityMarkers: false);
      opportunities.cities = [_city(5)];

      final city = await vm.revealCity(5);

      expect(city?.id, 5);
      expect(opportunities.cityCalls, 2);
      expect(vm.showCityMarkers, isTrue);
      expect(await vm.revealCity(99), isNull);
    });
  });

  test('oportunidades de um pino e de uma cidade', () async {
    final vm = build();

    expect((await vm.opportunitiesOfInstitution('n1')).single.id, 1);
    expect(opportunities.askedInstitution, 'n1');
    expect((await vm.opportunitiesOfCity(7)).single.id, 2);
    expect(opportunities.askedCityLocation, 7);
  });

  test('descartado no meio de uma busca, não quebra', () async {
    api.searchGate = Completer();
    final vm = build();
    vm.onSearchChanged('scar');
    await Future<void>.delayed(Duration.zero);

    vm.dispose();
    api.searchGate!.complete();
    await Future<void>.delayed(Duration.zero);
  });
}
