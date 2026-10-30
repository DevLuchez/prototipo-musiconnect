import 'dart:async';
import '../../data/models/opportunity_model.dart';
import '../../data/models/place_model.dart';
import '../../data/services/musicconnect_api_service.dart';
import '../../data/services/opportunities_service.dart';
import 'view_model.dart';

/// Estado e regras da aba Mapa ([MapExplorerScreen]): instituições
/// carregadas, filtros por tipo, busca, zoom mínimo para mostrar os pinos,
/// marcadores por cidade e as oportunidades de um pino/cidade.
///
/// O que é próprio do Google Maps (ícones desenhados, `Marker`, câmera)
/// fica na tela — ela monta os marcadores a partir de [visiblePlaces] e
/// [cities].
class MapExplorerViewModel extends ViewModel {
  MapExplorerViewModel({
    required Map<String, Set<String>> filterGroups,
    MusicConnectApiService? apiService,
    OpportunitiesService? opportunitiesService,
    this.searchDebounce = const Duration(milliseconds: 300),
  })  : _filterGroups = filterGroups,
        _activeFilterKeys = filterGroups.keys.toSet(),
        _api = apiService ?? MusicConnectApiService(),
        _opportunities = opportunitiesService ?? OpportunitiesService();

  final MusicConnectApiService _api;
  final OpportunitiesService _opportunities;

  /// Grupo do filtro → categorias do OSM que ele cobre (ex: "concert_hall"
  /// → {concert_hall, arts_centre}).
  final Map<String, Set<String>> _filterGroups;

  /// Pausa na digitação antes de consultar a busca.
  final Duration searchDebounce;

  /// Abaixo desse zoom os pinos ficam ilegíveis (sobrepostos) e somem.
  static const double markersMinZoom = 7.0;

  // ── Instituições carregadas ────────────────────────────────────────────
  final List<PlaceModel> _places = [];
  final Set<String> _loadedIds = {};

  List<PlaceModel> get places => List.unmodifiable(_places);

  /// Adiciona uma instituição (sem repetir). Devolve true se era nova.
  bool _addPlace(PlaceModel p) {
    if (!_loadedIds.add(p.id)) return false;
    _places.add(p);
    return true;
  }

  // ── Carga ──────────────────────────────────────────────────────────────
  bool _isLoading = true;
  bool _initialLoadDone = false;
  bool _backendOffline = false;
  int? _totalCount;
  int? _withOpportunitiesCount;

  bool get isLoading => _isLoading;
  bool get initialLoadDone => _initialLoadDone;
  bool get backendOffline => _backendOffline;

  /// Texto do rodapé da legenda.
  String get catalogSummary {
    if (_totalCount == null) return 'Carregando total de instituições catalogadas...';
    final withOpps = _withOpportunitiesCount != null
        ? ', $_withOpportunitiesCount com oportunidades abertas'
        : '';
    return '$_totalCount instituições catalogadas na base de dados$withOpps.';
  }

  /// Carga inicial: confere se o servidor responde, traz as instituições
  /// (as com oportunidades primeiro), as estatísticas e as cidades.
  Future<void> initialLoad() async {
    if (!await _api.isReachable()) {
      _backendOffline = true;
      _isLoading = false;
      _initialLoadDone = true;
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    final places = await _api.fetchAll(limit: 5000);
    final stats = await _api.fetchStats();
    places.forEach(_addPlace);
    _totalCount = stats?.total;
    _withOpportunitiesCount = stats?.withOpportunities;
    await loadCities();

    _isLoading = false;
    _initialLoadDone = true;
    notifyListeners();
  }

  /// Instituições ao redor do centro do mapa — chamada quando a câmera
  /// para. Ignorada com o servidor fora ou outra carga em andamento.
  Future<void> loadNearby(double lat, double lng, {int radiusM = 50000}) async {
    if (_backendOffline || _isLoading) return;
    _isLoading = true;
    notifyListeners();

    final places = await _api.fetchNearby(lat: lat, lng: lng, radiusM: radiusM, limit: 500);
    places.forEach(_addPlace);

    _isLoading = false;
    notifyListeners();
  }

  // ── Zoom ───────────────────────────────────────────────────────────────
  bool _showMarkers = true; // o zoom inicial (12) já está acima do limite

  bool get showMarkers => _showMarkers;

  void onZoomChanged(double zoom) {
    final show = zoom >= markersMinZoom;
    if (show == _showMarkers) return;
    _showMarkers = show;
    notifyListeners();
  }

  // ── Filtros ────────────────────────────────────────────────────────────
  Set<String> _activeFilterKeys;
  bool _onlyWithOpportunities = false;
  bool _showCityMarkers = true;

  Set<String> get activeFilterKeys => Set.unmodifiable(_activeFilterKeys);
  bool get onlyWithOpportunities => _onlyWithOpportunities;
  bool get showCityMarkers => _showCityMarkers;

  /// Tipos desmarcados + "só com oportunidades" + cidades escondidas.
  int get activeFilterCount =>
      (_filterGroups.length - _activeFilterKeys.length) +
      (_onlyWithOpportunities ? 1 : 0) +
      (_showCityMarkers ? 0 : 1);

  void applyFilters({
    required Set<String> keys,
    required bool onlyWithOpportunities,
    required bool showCityMarkers,
  }) {
    _activeFilterKeys = Set.of(keys);
    _onlyWithOpportunities = onlyWithOpportunities;
    _showCityMarkers = showCityMarkers;
    notifyListeners();
  }

  /// Se a instituição passa pelos filtros. Com todos os tipos marcados
  /// (padrão), qualquer categoria passa — inclusive as fora dos grupos
  /// conhecidos (ruído de tags do OSM).
  bool isVisible(PlaceModel p) {
    if (_onlyWithOpportunities && !p.hasActiveOpportunities) return false;
    if (_activeFilterKeys.length == _filterGroups.length) return true;
    return _activeFilterKeys.any((key) => _filterGroups[key]!.contains(p.category));
  }

  /// Pinos que aparecem no mapa (com zoom suficiente).
  Iterable<PlaceModel> get visiblePlaces =>
      activeFilterCount == 0 ? _places : _places.where(isVisible);

  // ── Oportunidades por cidade ───────────────────────────────────────────
  List<CityOpportunities> _cities = [];

  List<CityOpportunities> get cities => _cities;

  Future<void> loadCities() async {
    _cities = await _opportunities.fetchCities();
    notifyListeners();
  }

  // ── Busca por texto ────────────────────────────────────────────────────
  Timer? _searchTimer;
  String _searchTerm = '';
  List<PlaceModel> _searchResults = [];
  bool _showSearchResults = false;

  List<PlaceModel> get searchResults => _searchResults;
  bool get showSearchResults => _showSearchResults;

  /// Busca em todas as instituições do banco (o mapa só tem parte delas em
  /// memória) depois de uma pausa na digitação. Se o servidor falhar, busca
  /// no que já está carregado. Respostas de um termo já alterado são
  /// descartadas.
  void onSearchChanged(String text) {
    _searchTimer?.cancel();
    final term = text.trim();
    _searchTerm = term;
    if (term.length < 2) {
      _setSearch(const [], visible: false);
      return;
    }
    _searchTimer = Timer(searchDebounce, () async {
      final results = await _api.search(term) ?? _searchLocal(term);
      if (term != _searchTerm) return;
      _setSearch(results, visible: true);
    });
  }

  void clearSearch() {
    _searchTimer?.cancel();
    _searchTerm = '';
    _setSearch(const [], visible: false);
  }

  void _setSearch(List<PlaceModel> results, {required bool visible}) {
    _searchResults = results;
    _showSearchResults = visible;
    notifyListeners();
  }

  List<PlaceModel> _searchLocal(String term) {
    final lower = term.toLowerCase();
    return _places
        .where((p) =>
            p.name.toLowerCase().contains(lower) ||
            (p.address?.toLowerCase().contains(lower) ?? false))
        .take(8)
        .toList();
  }

  // ── Focar um pino ou cidade ("Ver no mapa", busca, favoritas) ──────────

  /// A instituição pelo osm_id — a já carregada, ou buscada no servidor.
  Future<PlaceModel?> findInstitution(String osmId) async =>
      _places.where((p) => p.osmId == osmId).firstOrNull ?? await _api.fetchById(osmId);

  /// Garante que o pino apareça: adiciona se ainda não estava carregado e
  /// limpa os filtros que o esconderiam. Devolve a instância usada no mapa.
  PlaceModel reveal(PlaceModel place) {
    final target = _places.where((p) => p.id == place.id).firstOrNull ?? place;
    _addPlace(target);
    if (!isVisible(target)) {
      _activeFilterKeys = _filterGroups.keys.toSet();
      _onlyWithOpportunities = false;
    }
    notifyListeners();
    return target;
  }

  /// A cidade pelo id; se não estiver entre as carregadas (vínculo criado
  /// depois da carga inicial), recarrega as cidades. Mostra os marcadores
  /// de cidade se estavam escondidos.
  Future<CityOpportunities?> revealCity(int cityId) async {
    var city = _cities.where((c) => c.id == cityId).firstOrNull;
    if (city == null) {
      await loadCities();
      city = _cities.where((c) => c.id == cityId).firstOrNull;
    }
    if (city != null && !_showCityMarkers) {
      _showCityMarkers = true;
      notifyListeners();
    }
    return city;
  }

  // ── Oportunidades de um pino/cidade (painéis de detalhe) ───────────────

  Future<List<OpportunityModel>> opportunitiesOfInstitution(String osmId) =>
      _opportunities.fetchByInstitution(osmId);

  Future<List<OpportunityModel>> opportunitiesOfCity(int cityId) async =>
      (await _opportunities.fetchOpportunities(cityLocationId: cityId)).items;

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }
}
