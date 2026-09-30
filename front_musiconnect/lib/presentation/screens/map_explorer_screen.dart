import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/opportunity_model.dart';
import '../../data/models/place_model.dart';
import '../../data/models/providers/auth_service.dart';
import '../../data/models/providers/musicconnect_api_service.dart';
import '../../data/models/providers/opportunities_service.dart';
import '../widgets/app_loading_indicator.dart';
import '../widgets/opportunity_card.dart';
import 'opportunity_detail_screen.dart';

const String _mapStyle = '''
[
  {"featureType":"poi","elementType":"all","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"visibility":"on"}]},
  {"featureType":"transit","elementType":"labels.icon","stylers":[{"visibility":"off"}]}
]
''';

// Paleta e tipografia padronizadas com o botão/modal de filtro da aba
// Matcher (ver filter_modal.dart) — mesmo rosa, mesmo tom de fundo,
// mesmo estilo de cabeçalho e de botões de ação.
const _pink = Color(0xFFEC4899);
const _pinkTint = Color(0xFFFFFFFF);
const _pinkIcon = Color(0xFFDF2881);
// Estrela de "tem oportunidade aberta" — pinos, bolinhas de cidade e legenda.
const _starColor = Color.fromARGB(255, 255, 183, 0);
const _sheetHeaderStyle = TextStyle(
  fontSize: 18,
  fontWeight: FontWeight.w800,
  color: Color(0xFF111827),
);

/// Grupo de filtro por tipo de instituição — espelha as cores/rótulos da
/// legenda e agrupa categorias OSM equivalentes (ex: concert_hall + arts_centre).
class _CategoryFilter {
  final String key;
  final String label;
  final Color color;
  final Set<String> categories;

  const _CategoryFilter({
    required this.key,
    required this.label,
    required this.color,
    required this.categories,
  });
}

const List<_CategoryFilter> _categoryFilters = [
  _CategoryFilter(
    key: 'music_school',
    label: 'Escola de música / Conservatório',
    color: Color.fromARGB(255, 39, 123, 176),
    categories: {'music_school'},
  ),
  _CategoryFilter(
    key: 'concert_hall',
    label: 'Centro cultural',
    color: Colors.pink,
    categories: {'concert_hall', 'arts_centre'},
  ),
  _CategoryFilter(
    key: 'theatre',
    label: 'Teatro / Ópera',
    color: Colors.deepPurple,
    categories: {'theatre'},
  ),
  _CategoryFilter(
    key: 'music_venue',
    label: 'Local de música ao vivo',
    color: Colors.orange,
    categories: {'music_venue'},
  ),
  _CategoryFilter(
    key: 'music_org',
    label: 'Orquestra / Festival',
    color: Colors.green,
    categories: {'music_org'},
  ),
];

class MapExplorerScreen extends StatefulWidget {
  /// Usuário logado — repassado à tela de detalhes das oportunidades
  /// abertas a partir do detalhe de uma instituição.
  final AuthUser user;

  /// Pedido para focar numa oportunidade (pino da instituição ou marcador
  /// da cidade), vindo do botão "Ver no mapa". O mapa zera o valor depois
  /// de atender.
  final ValueNotifier<OpportunityModel?>? focusRequest;

  const MapExplorerScreen({super.key, required this.user, this.focusRequest});
  @override
  State<MapExplorerScreen> createState() => _MapExplorerScreenState();
}

class _MapExplorerScreenState extends State<MapExplorerScreen> {
  GoogleMapController? _mapController;
  final MusicConnectApiService _apiService = MusicConnectApiService();
  Timer? _cameraDebounce;
  Timer? _searchDebounce;

  // Marcadores e lugares
  final Map<MarkerId, Marker> _markers = {};
  final List<PlaceModel> _places = [];
  final Set<String> _loadedIds = {};

  LatLng _mapCenter = const LatLng(-26.4855, -49.0669); // Jaraguá do Sul/SC

  // Abaixo desse zoom os marcadores ficam ilegíveis (muito sobrepostos),
  // então simplesmente ficam ocultos até o usuário aproximar o suficiente.
  static const double _markersMinZoom = 7.0;
  bool _showMarkers = true; // zoom inicial (12.0) já está acima do limite

  bool _isLoading = true;
  bool _initialLoadDone = false;
  bool _backendOffline = false;
  int? _dbTotalCount;
  int? _dbWithOpportunitiesCount;

  // Oportunidade aguardando foco — o pedido pode chegar antes da carga
  // inicial terminar ou do mapa nativo estar pronto.
  OpportunityModel? _pendingFocus;

  // Marcadores "oportunidades por cidade": oportunidades cuja organizadora
  // não tem localização exata ficam numa bolinha com estrela, no centro da
  // cidade — separada dos pinos de instituição.
  final OpportunitiesService _opportunitiesService = OpportunitiesService();
  List<CityOpportunities> _cities = [];
  Map<MarkerId, Marker> _cityMarkers = {};
  bool _showCityMarkers = true;

  // Ícones dos marcadores, desenhados uma vez na carga inicial e
  // reaproveitados por todos os pinos (chave = hue da categoria). Todos os
  // pinos são desenhados — não só os com estrela — para que a única
  // diferença visual seja a estrela: o google_maps_flutter não permite
  // sobrepor nada ao pino padrão do Google.
  final Map<double, BitmapDescriptor> _pinIcons = {};
  final Map<double, BitmapDescriptor> _starPinIcons = {};
  BitmapDescriptor? _starCityIcon;

  // Busca
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<PlaceModel> _searchResults = [];
  bool _showSearchResults = false;

  // Filtro por tipo de instituição — por padrão, todos os tipos ativos
  // (nenhum filtro aplicado, todos os marcadores aparecem).
  Set<String> _activeFilterKeys =
      _categoryFilters.map((f) => f.key).toSet();
  bool _onlyWithOpportunities = false;

  int get _activeFilterCount =>
      (_categoryFilters.length - _activeFilterKeys.length) +
      (_onlyWithOpportunities ? 1 : 0) +
      (_showCityMarkers ? 0 : 1);

  static final Map<String, double> _hues = {
    'music_school': BitmapDescriptor.hueAzure,
    'concert_hall': BitmapDescriptor.hueRose,
    'arts_centre':  BitmapDescriptor.hueRose,
    'theatre':      BitmapDescriptor.hueViolet,
    'music_venue':  BitmapDescriptor.hueOrange,
    'music_org':    BitmapDescriptor.hueGreen,
  };

  @override
  void initState() {
    super.initState();
    widget.focusRequest?.addListener(_onFocusRequest);
    _initialLoad();
  }

  @override
  void dispose() {
    widget.focusRequest?.removeListener(_onFocusRequest);
    _cameraDebounce?.cancel();
    _searchDebounce?.cancel();
    _mapController?.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Carga inicial ─────────────────────────────────────────────

  Future<void> _initialLoad() async {
    final online = await _apiService.isReachable();
    if (!mounted) return;

    if (!online) {
      setState(() {
        _backendOffline = true;
        _isLoading = false;
        _initialLoadDone = true;
      });
      return;
    }

    setState(() => _isLoading = true);

    // Antes de criar qualquer marcador, que já usa esses ícones
    await _prepareMarkerIcons();
    final places = await _apiService.fetchAll(limit: 5000);
    final stats = await _apiService.fetchStats();
    if (!mounted) return;

    for (final p in places) {
      _addPlace(p);
    }
    _dbTotalCount = stats?.total;
    _dbWithOpportunitiesCount = stats?.withOpportunities;
    await _loadCities();
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _initialLoadDone = true;
    });
    _nudgeMapRedraw();
    _focusPending();
  }

  // ── Foco vindo de uma oportunidade ("Ver no mapa") ─────────────

  void _onFocusRequest() {
    final opp = widget.focusRequest?.value;
    if (opp == null) return;
    widget.focusRequest!.value = null;
    _pendingFocus = opp;
    _focusPending();
  }

  /// Leva o mapa até a oportunidade pendente: pino da instituição, ou o
  /// marcador da cidade quando a organizadora não tem localização exata.
  Future<void> _focusPending() async {
    final opp = _pendingFocus;
    if (opp == null || !_initialLoadDone || _mapController == null) return;
    _pendingFocus = null;

    final osmId = opp.institutionId;
    final cityId = opp.cityLocationId;
    if (osmId != null) {
      await _focusInstitution(osmId);
    } else if (cityId != null) {
      await _focusCity(cityId);
    }
  }

  void _showNotFoundOnMap() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Não foi possível localizar esta oportunidade no mapa.'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Centraliza no pino da instituição e abre o detalhe dela. Se o pino
  /// ainda não foi carregado (fora da carga inicial), busca no backend; se
  /// algum filtro ativo o esconderia, limpa os filtros.
  Future<void> _focusInstitution(String osmId) async {
    final place = _places.where((p) => p.osmId == osmId).firstOrNull ??
        await _apiService.fetchById(osmId);
    if (!mounted) return;
    if (place == null) {
      _showNotFoundOnMap();
      return;
    }
    await _focusPlace(place);
  }

  /// Adiciona o pino (se ainda não estava carregado), garante que nenhum
  /// filtro o esconda, centraliza e abre o detalhe da instituição — usado
  /// pelo "Ver no mapa" das oportunidades e pela barra de busca.
  Future<void> _focusPlace(PlaceModel place) async {
    // Se já estava carregado, usa a instância do mapa (mesmo marcador)
    final target =
        _places.where((p) => p.id == place.id).firstOrNull ?? place;
    setState(() {
      _addPlace(target);
      if (!_isVisible(target)) {
        _activeFilterKeys = _categoryFilters.map((f) => f.key).toSet();
        _onlyWithOpportunities = false;
      }
    });
    await _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(target.lat, target.lng), zoom: 16),
      ),
    );
    if (mounted) _showDetail(target);
  }

  /// Centraliza no marcador da cidade e abre a lista das oportunidades dela.
  Future<void> _focusCity(int cityId) async {
    var city = _cities.where((c) => c.id == cityId).firstOrNull;
    if (city == null) {
      // Vínculo criado depois da carga inicial — recarrega os marcadores.
      await _loadCities();
      city = _cities.where((c) => c.id == cityId).firstOrNull;
    }
    if (!mounted) return;
    if (city == null) {
      _showNotFoundOnMap();
      return;
    }

    final target = city;
    if (!_showCityMarkers) setState(() => _showCityMarkers = true);
    await _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(target.lat, target.lng), 11),
    );
    if (mounted) _showCityDetail(target);
  }

  // ── Oportunidades por cidade ──────────────────────────────────

  Future<void> _loadCities() async {
    final cities = await _opportunitiesService.fetchCities();
    final markers = <MarkerId, Marker>{};
    for (final c in cities) {
      final id = MarkerId('city_${c.id}');
      markers[id] = Marker(
        markerId: id,
        position: LatLng(c.lat, c.lng),
        icon: _starCityIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose),
        anchor: const Offset(0.5, 0.5),
        zIndex: 3.0,
        onTap: () => _showCityDetail(c),
      );
    }
    if (!mounted) return;
    setState(() {
      _cities = cities;
      _cityMarkers = markers;
    });
  }

  // ── Ícones dos marcadores ─────────────────────────────────────

  Future<void> _prepareMarkerIcons() async {
    final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    for (final hue in {..._hues.values, BitmapDescriptor.hueViolet}) {
      _pinIcons[hue] = await _drawPin(hue, dpr, withStar: false);
      _starPinIcons[hue] = await _drawPin(hue, dpr, withStar: true);
    }
    _starCityIcon = await _drawStarCity(dpr);
  }

  /// Estrela de 5 pontas centrada em [center].
  static Path _starPath(Offset center, double outerRadius) {
    final innerRadius = outerRadius * 0.45;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outerRadius : innerRadius;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point = center + Offset(r * math.cos(angle), r * math.sin(angle));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  static Future<BitmapDescriptor> _toBitmap(
      ui.PictureRecorder recorder, double width, double height, double dpr) async {
    final image = await recorder
        .endRecording()
        .toImage(width.round(), height.round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BytesMapBitmap(bytes!.buffer.asUint8List(), imagePixelRatio: dpr);
  }

  /// Pino em gota na cor da categoria — com estrela amarela na cabeça quando
  /// a instituição tem oportunidade aberta, ou com o miolo escuro do pino
  /// padrão do Google quando não tem.
  static Future<BitmapDescriptor> _drawPin(double hue, double dpr,
      {required bool withStar}) async {
    final width = 28 * dpr;
    final height = 42 * dpr;
    final r = width / 2;
    final head = Offset(width / 2, r);
    final fill = HSVColor.fromAHSV(1, hue, 0.8, 0.95).toColor();
    final dark = HSVColor.fromAHSV(1, hue, 0.8, 0.6).toColor();

    // Cabeça redonda + ponta triangular (os cantos do triângulo ficam sobre
    // a circunferência, então a união não tem "degrau").
    final body = Path.combine(
      PathOperation.union,
      Path()..addOval(Rect.fromCircle(center: head, radius: r - dpr)),
      Path()
        ..moveTo(width / 2 - r * 0.78, r + r * 0.62)
        ..lineTo(width / 2, height - dpr)
        ..lineTo(width / 2 + r * 0.78, r + r * 0.62)
        ..close(),
    );

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawPath(body, Paint()..color = fill);
    canvas.drawPath(
      body,
      Paint()
        ..color = dark
        ..style = PaintingStyle.stroke
        ..strokeWidth = dpr,
    );
    if (withStar) {
      canvas.drawPath(_starPath(head, r * 0.62), Paint()..color = _starColor);
    } else {
      canvas.drawCircle(head, r * 0.3, Paint()..color = dark);
    }
    return _toBitmap(recorder, width, height, dpr);
  }

  /// Bolinha rosa com estrela amarela — marcador de cidade.
  static Future<BitmapDescriptor> _drawStarCity(double dpr) async {
    final size = 30 * dpr;
    final center = Offset(size / 2, size / 2);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(center, size / 2, Paint()..color = Colors.white);
    canvas.drawCircle(center, size / 2 - 3 * dpr, Paint()..color = _pink);
    canvas.drawPath(_starPath(center, size * 0.28), Paint()..color = _starColor);
    return _toBitmap(recorder, size, size, dpr);
  }

  void _showCityDetail(CityOpportunities city) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CitySheet(city: city, user: widget.user),
    );
  }

  // ── Busca no backend (ao mover câmera) ────────────────────────

  Future<void> _fetchFromBackend(LatLng center, {int radiusM = 50000}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    final places = await _apiService.fetchNearby(
      lat: center.latitude,
      lng: center.longitude,
      radiusM: radiusM,
      limit: 500,
    );

    if (!mounted) return;

    for (final p in places) {
      _addPlace(p);
    }

    setState(() => _isLoading = false);
    // Sem nudge aqui: essa busca já é disparada por um movimento real de
    // câmera do usuário, então o mapa já está ativo/repintando — nudgear de
    // novo só reacionaria onCameraIdle e viraria um loop infinito de fetch.
  }

  /// Empurra a câmera 1px e volta, forçando o Android a repintar a
  /// superfície nativa do GoogleMap — sem esse empurrão, marcadores
  /// recém-adicionados via setState só aparecem depois que o usuário
  /// toca/arrasta o mapa (bug conhecido do google_maps_flutter no Android).
  void _nudgeMapRedraw() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController?.moveCamera(CameraUpdate.scrollBy(1, 0));
      _mapController?.moveCamera(CameraUpdate.scrollBy(-1, 0));
    });
  }

  /// Adiciona uma instituição à lista e mapa de marcadores.
  /// Retorna true se era nova (não duplicada).
  bool _addPlace(PlaceModel p) {
    if (_loadedIds.contains(p.id)) return false;
    _loadedIds.add(p.id);
    _places.add(p);
    final mid = MarkerId(p.id);
    _markers[mid] = _buildMarker(p);
    return true;
  }

  // ── Busca por texto ───────────────────────────────────────────

  /// Busca no backend, em todas as instituições — o mapa só tem parte delas
  /// em memória. Espera uma pausa na digitação antes de consultar; se o
  /// backend falhar, cai na busca local (só no que já está carregado).
  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    final term = query.trim();
    if (term.length < 2) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await _apiService.search(term) ?? _searchLocal(term);
      // Descarta respostas atrasadas de um termo que já foi alterado
      if (!mounted || _searchController.text.trim() != term) return;
      setState(() {
        _searchResults = results;
        _showSearchResults = true;
      });
    });
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

  void _navigateToPlace(PlaceModel p) {
    _searchDebounce?.cancel();
    _searchController.clear();
    _searchFocus.unfocus();
    setState(() {
      _searchResults = [];
      _showSearchResults = false;
    });
    _focusPlace(p);
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _searchFocus.unfocus();
    setState(() {
      _searchResults = [];
      _showSearchResults = false;
    });
  }

  // ── Eventos do mapa ───────────────────────────────────────────

  void _onMapCreated(GoogleMapController c) {
    _mapController = c;
    _focusPending();
    // Confirma o zoom real assim que o mapa nativo está pronto: o primeiro
    // onCameraMove pode reportar um zoom incorreto (view ainda sem
    // dimensões finais), o que deixaria _showMarkers travado em false até
    // o usuário mexer no mapa.
    c.getZoomLevel().then((zoom) {
      if (!mounted) return;
      final showMarkers = zoom >= _markersMinZoom;
      if (showMarkers != _showMarkers) {
        setState(() => _showMarkers = showMarkers);
      }
    });
  }

  void _onCameraMove(CameraPosition pos) {
    _mapCenter = pos.target;
    final showMarkers = pos.zoom >= _markersMinZoom;
    if (showMarkers != _showMarkers) {
      setState(() => _showMarkers = showMarkers);
    }
  }

  void _onCameraIdle() {
    _cameraDebounce?.cancel();
    _cameraDebounce = Timer(const Duration(milliseconds: 800), () {
      if (!_backendOffline && !_isLoading) {
        _fetchFromBackend(_mapCenter);
      }
    });
  }

  // ── Filtro por tipo ──────────────────────────────────────────────

  /// Se a instituição passa pelos filtros ativos (tipo + "só com
  /// oportunidades abertas"). Com todos os tipos selecionados (padrão),
  /// qualquer categoria passa — inclusive as fora dos grupos conhecidos
  /// (ex.: ruído de tags do OSM).
  bool _isVisible(PlaceModel p) {
    if (_onlyWithOpportunities && !p.hasActiveOpportunities) return false;
    if (_activeFilterKeys.length == _categoryFilters.length) return true;
    return _categoryFilters.any((f) =>
        _activeFilterKeys.contains(f.key) && f.categories.contains(p.category));
  }

  /// Marcadores exibidos no mapa, considerando os filtros ativos.
  Set<Marker> get _visibleMarkers {
    if (_activeFilterCount == 0) return Set.of(_markers.values);
    return _places
        .where(_isVisible)
        .map((p) => _markers[MarkerId(p.id)])
        .whereType<Marker>()
        .toSet();
  }

  void _openCategoryFilter() {
    // Seleção provisória — só é aplicada de fato (setState no estado da
    // tela, que filtra os marcadores) quando o usuário toca em "Aplicar".
    final draftKeys = Set<String>.of(_activeFilterKeys);
    var draftOnlyWithOpportunities = _onlyWithOpportunities;
    var draftShowCityMarkers = _showCityMarkers;

    showModalBottomSheet(
      context: context,
      // Sem isso o sheet fica limitado a ~56% da tela e o conteúdo estoura
      // em telas menores — a parte do meio rola, cabeçalho e rodapé ficam.
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) {
          void toggle(String key, bool value) {
            setModalState(() {
              if (value) {
                draftKeys.add(key);
              } else {
                draftKeys.remove(key);
              }
            });
          }

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Cabeçalho ────────────────────────────────────
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text('Filtrar por tipo de instituição', style: _sheetHeaderStyle),
                ),
                const Divider(height: 1),

                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Só com oportunidades abertas ─────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: SwitchListTile(
                            value: draftOnlyWithOpportunities,
                            onChanged: (v) =>
                                setModalState(() => draftOnlyWithOpportunities = v),
                            contentPadding: EdgeInsets.zero,
                            activeColor: _pink,
                            title: const Text('Só com oportunidades abertas',
                                style: TextStyle(fontSize: 14)),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: SwitchListTile(
                            value: draftShowCityMarkers,
                            onChanged: (v) =>
                                setModalState(() => draftShowCityMarkers = v),
                            contentPadding: EdgeInsets.zero,
                            activeColor: _pink,
                            title: const Text('Oportunidades por cidade',
                                style: TextStyle(fontSize: 14)),
                          ),
                        ),
                        const Divider(height: 1),

                        // ── Lista de tipos ───────────────────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            children: [
                              for (final f in _categoryFilters)
                                CheckboxListTile(
                                  value: draftKeys.contains(f.key),
                                  onChanged: (v) => toggle(f.key, v ?? false),
                                  controlAffinity: ListTileControlAffinity.leading,
                                  contentPadding: EdgeInsets.zero,
                                  activeColor: _pink,
                                  title: Row(children: [
                                    Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                          color: f.color, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: Text(f.label,
                                            style: const TextStyle(fontSize: 14))),
                                  ]),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Rodapé fixo ──────────────────────────────────
                const Divider(height: 1),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    MediaQuery.of(context).viewInsets.bottom + 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setModalState(() {
                              draftKeys
                                ..clear()
                                ..addAll(_categoryFilters.map((f) => f.key));
                              draftOnlyWithOpportunities = false;
                              draftShowCityMarkers = true;
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF6B7280),
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Limpar tudo'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _activeFilterKeys = draftKeys;
                              _onlyWithOpportunities =
                                  draftOnlyWithOpportunities;
                              _showCityMarkers = draftShowCityMarkers;
                            });
                            Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _pink,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'Aplicar',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Marcadores ────────────────────────────────────────────────

  Marker _buildMarker(PlaceModel p) {
    final highlighted = p.hasActiveOpportunities;
    final snippet = [
      p.categoryLabel,
      if (highlighted) _openOpportunitiesLabel(p.activeOpportunitiesCount),
      if (p.address != null) p.address!,
    ].join(' · ');
    final hue = _hues[p.category] ?? BitmapDescriptor.hueViolet;
    return Marker(
      markerId: MarkerId(p.id),
      position: LatLng(p.lat, p.lng),
      // Com oportunidade aberta → mesmo pino, com estrela
      icon: (highlighted ? _starPinIcons[hue] : _pinIcons[hue]) ??
          BitmapDescriptor.defaultMarkerWithHue(hue),
      infoWindow: InfoWindow(title: p.name, snippet: snippet),
      onTap: () => _showDetail(p),
      zIndex: highlighted ? 2.0 : 1.0,
    );
  }

  void _showDetail(PlaceModel p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetailSheet(place: p, user: widget.user),
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Fecha a busca ao tocar fora
      onTap: () {
        if (_showSearchResults) _clearSearch();
      },
      child: Stack(
        children: [
          // ── Mapa ──────────────────────────────────────────────
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition:
                CameraPosition(target: _mapCenter, zoom: 12.0),
            // Instituições e cidades somem juntas abaixo de _markersMinZoom.
            markers: _showMarkers
                ? {
                    ..._visibleMarkers,
                    if (_showCityMarkers) ..._cityMarkers.values,
                  }
                : const {},
            style: _mapStyle,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
          ),

          // ── Banner: backend offline ───────────────────────────
          if (_backendOffline)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                color: Colors.amber[700],
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Houve um problema ao carregar os dados, favor contatar o suporte!',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ]),
                ),
              ),
            ),

          // ── Barra de busca flutuante ──────────────────────────
          Positioned(
            top: _backendOffline ? 48 : 12,
            left: 12,
            right: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Barra principal + botão de filtro
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(1, 1),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          onChanged: _onSearchChanged,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            hintText:
                                'Busque por localização ou instituição...',
                            hintStyle: TextStyle(
                              fontSize: 13.5,
                              color: Colors.grey[400],
                            ),
                            prefixIcon: Icon(Icons.search_rounded,
                                size: 18, color: Colors.grey[400]),
                            prefixIconConstraints:
                                const BoxConstraints(minWidth: 40, minHeight: 0),
                            suffixIcon: _showSearchResults
                                ? GestureDetector(
                                    onTap: _clearSearch,
                                    child: Icon(Icons.close_rounded,
                                        size: 16, color: Colors.grey[400]),
                                  )
                                : null,
                            suffixIconConstraints:
                                const BoxConstraints(minWidth: 40, minHeight: 0),
                            border: InputBorder.none,
                            isCollapsed: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 11),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Botão de filtro por tipo
                    GestureDetector(
                      onTap: _openCategoryFilter,
                      child: Container(
                        height: 42,
                        width: 42,
                        decoration: BoxDecoration(
                          color: _pinkTint,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(1, 1),
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Icon(Icons.tune_rounded,
                                size: 20, color: _pinkIcon),
                            if (_activeFilterCount > 0)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: const BoxDecoration(
                                    color: _pink,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$_activeFilterCount',
                                      style: const TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // Lista de resultados
                if (_showSearchResults)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.10),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _searchResults.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Nenhum resultado encontrado.',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 13),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: _searchResults.length,
                            separatorBuilder: (_, __) => Divider(
                                height: 1, color: Colors.grey[100]),
                            itemBuilder: (_, i) {
                              final p = _searchResults[i];
                              return InkWell(
                                onTap: () => _navigateToPlace(p),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDF2881)
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Icon(
                                          Icons.business_rounded,
                                          color: Color(0xFFDF2881),
                                          size: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              p.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (p.address != null)
                                              Text(
                                                p.address!,
                                                style: TextStyle(
                                                  color: Colors.grey[500],
                                                  fontSize: 11,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.chevron_right,
                                          color: Colors.grey[300], size: 18),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
              ],
            ),
          ),

          // ── Carregamento inicial ───────────────────────────────
          if (_isLoading && _markers.isEmpty)
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Column(mainAxisSize: MainAxisSize.min, children: [
                  AppLoadingIndicator(size: 34),
                  SizedBox(height: 14),
                  Text(
                    'Carregando instituições globais...',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111827),
                    ),
                  ),
                ]),
              ),
            ),

          // ── Botão de legenda (esquerda) ─────────────────────────
          Positioned(
            bottom: 16,
            left: 16,
            child: Tooltip(
              message: 'Legenda',
              child: GestureDetector(
                onTap: _showLegend,
                child: Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: _pinkTint,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(1, 1),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.legend_toggle_rounded,
                      size: 20, color: _pinkIcon),
                ),
              ),
            ),
          ),

          // ── Indicador de loading (direita, pós-carga inicial) ───
          if (_isLoading && _markers.isNotEmpty)
            Positioned(
              bottom: 16,
              right: 16,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.12), blurRadius: 8)
                  ],
                ),
                child: const Padding(
                  padding: EdgeInsets.all(9),
                  child: AppLoadingIndicator(size: 20),
                ),
              ),
            ),

        ],
      ),
    );
  }

  // ── Legenda ───────────────────────────────────────────────────

  void _showLegend() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho ──────────────────────────────────────────
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text('Legenda', style: _sheetHeaderStyle),
            ),
            const Divider(height: 1),

            // ── Itens ────────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final f in _categoryFilters)
                      _legendItem(f.color, f.label),
                    const Divider(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        SizedBox(
                          width: 18,
                          height: 22,
                          child: Stack(
                            alignment: Alignment.topCenter,
                            children: [
                              Icon(Icons.location_on,
                                  size: 22, color: Colors.grey[600]),
                              const Padding(
                                padding: EdgeInsets.only(top: 3.5),
                                child: Icon(Icons.star_rounded,
                                    size: 10, color: _starColor),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Pino com estrela: instituição com oportunidades abertas',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: const BoxDecoration(
                              color: _pink, shape: BoxShape.circle),
                          child: const Icon(Icons.star_rounded,
                              size: 12, color: _starColor),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Bolinha com estrela: oportunidades na cidade, de instituições sem endereço exato',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ]),
                    ),
                    const Divider(height: 24),
                    Row(children: [
                      const Icon(Icons.storage, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _dbTotalCount != null
                              ? '$_dbTotalCount instituições catalogadas na base de dados'
                                  '${_dbWithOpportunitiesCount != null ? ', $_dbWithOpportunitiesCount com oportunidades abertas' : ''}.'
                              : 'Carregando total de instituições catalogadas...',
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _openOpportunitiesLabel(int n) =>
      n == 1 ? '1 oportunidade aberta' : '$n oportunidades abertas';

  Widget _legendItem(Color color, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        ]),
      );
}

// ── Widget: sheet de oportunidades de uma cidade ──────────────────

class _CitySheet extends StatefulWidget {
  final CityOpportunities city;
  final AuthUser user;
  const _CitySheet({required this.city, required this.user});

  @override
  State<_CitySheet> createState() => _CitySheetState();
}

class _CitySheetState extends State<_CitySheet> {
  // null = carregando
  List<OpportunityModel>? _opportunities;

  @override
  void initState() {
    super.initState();
    OpportunitiesService()
        .fetchOpportunities(cityLocationId: widget.city.id)
        .then((result) {
      if (mounted) setState(() => _opportunities = result.items);
    });
  }

  void _openOpportunity(OpportunityModel opp) {
    // Sem onOpenMap: quem chegou aqui já está no mapa, com esta cidade aberta.
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OpportunityDetailScreen(opportunity: opp, user: widget.user),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final items = _opportunities;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabeçalho ──────────────────────────────────────────
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(children: [
              const Icon(Icons.location_city_rounded, color: _pinkIcon),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(widget.city.label, style: _sheetHeaderStyle)),
            ]),
          ),
          const Divider(height: 1),

          // ── Oportunidades ──────────────────────────────────────
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'As instituições destas oportunidades não têm endereço '
                    'exato cadastrado, por isso elas aparecem no centro da cidade.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  if (items == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: AppLoadingIndicator(size: 24)),
                    )
                  else if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Não foi possível carregar as oportunidades.',
                        style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      ),
                    )
                  else
                    for (final opp in items)
                      OpportunityCard(
                        opportunity: opp,
                        matchPercentage: opp.matchPercentage,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        onTap: () => _openOpportunity(opp),
                      ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Widget: sheet de detalhes ─────────────────────────────────────

class _DetailSheet extends StatefulWidget {
  final PlaceModel place;
  final AuthUser user;
  const _DetailSheet({required this.place, required this.user});

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  // null = carregando; só é buscado quando o pino tem oportunidades abertas.
  List<OpportunityModel>? _opportunities;

  PlaceModel get place => widget.place;

  @override
  void initState() {
    super.initState();
    final osmId = place.osmId;
    if (place.hasActiveOpportunities && osmId != null) {
      OpportunitiesService().fetchByInstitution(osmId).then((items) {
        if (mounted) setState(() => _opportunities = items);
      });
    }
  }

  void _openOpportunity(OpportunityModel opp) {
    // Sem onOpenMap: quem chegou aqui já está no mapa, com este pino aberto.
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OpportunityDetailScreen(opportunity: opp, user: widget.user),
    ));
  }

  Widget _buildOpportunities() {
    final items = _opportunities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 12),
        Text(
          'Oportunidades abertas (${place.activeOpportunitiesCount})',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 4),
        if (items == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: AppLoadingIndicator(size: 24)),
          )
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Não foi possível carregar as oportunidades.',
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
          )
        else
          for (final opp in items)
            OpportunityCard(
              opportunity: opp,
              matchPercentage: opp.matchPercentage,
              margin: const EdgeInsets.symmetric(vertical: 6),
              onTap: () => _openOpportunity(opp),
            ),
      ],
    );
  }

  static final ButtonStyle _linkButtonStyle = OutlinedButton.styleFrom(
    foregroundColor: const Color(0xFFDF2881),
    side: const BorderSide(color: Color(0xFFDF2881)),
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
  );

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Abre a instituição no app de mapas sem nunca mostrar coordenadas cruas:
  ///  - com endereço → busca "nome, endereço" no Google Maps (abre a página
  ///    do lugar, com endereço/fotos/horário);
  ///  - sem endereço → pino no ponto exato, rotulado com o nome: `geo:` no
  ///    Android (Google Maps) e Apple Maps no iOS (o link do Google Maps
  ///    não aceita "ponto + rótulo", só busca por texto, que poderia cair
  ///    num lugar homônimo de outra cidade).
  void _openInMaps() {
    final address = place.address;
    if (address != null && address.isNotEmpty) {
      _openUrl(Uri.https('www.google.com', '/maps/search/', {
        'api': '1',
        'query': '${place.name}, $address',
      }).toString());
      return;
    }

    final coords = '${place.lat},${place.lng}';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        // Parênteses delimitam o rótulo — remove os do próprio nome.
        final label = Uri.encodeComponent(
            place.name.replaceAll(RegExp(r'[()]'), ''));
        _openUrl('geo:0,0?q=$coords($label)');
      case TargetPlatform.iOS:
        _openUrl(Uri.https('maps.apple.com', '/', {
          'll': coords,
          'q': place.name,
        }).toString());
      default:
        _openUrl(Uri.https('www.google.com', '/maps/search/', {
          'api': '1',
          'query': coords,
        }).toString());
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cabeçalho ──────────────────────────────────────────
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(children: [
                // Instituição confirmada no Wikidata/MusicBrainz → só um
                // check discreto no ícone (um selo "Verificado" dava má
                // impressão às que não têm).
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.business_rounded, color: Color(0xFFDF2881)),
                      if (place.verified)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.verified,
                                size: 14, color: Colors.green[600]),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(child: Text(place.name, style: _sheetHeaderStyle)),
              ]),
            ),
            const Divider(height: 1),

            // ── Detalhes ─────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Categoria
                    Chip(
                      label: Text(place.categoryLabel,
                          style: const TextStyle(fontSize: 13)),
                      backgroundColor:
                          const Color(0xFFDF2881).withOpacity(0.08),
                      labelStyle: const TextStyle(color: Color(0xFFDF2881)),
                      side: BorderSide.none,
                    ),

                    // E-mail de contato (OSM) — link que abre o app de e-mail
                    const SizedBox(height: 12),
                    if (place.email != null) ...[
                      Row(children: [
                        const Icon(Icons.email_outlined,
                            size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Flexible(
                          child: GestureDetector(
                            onTap: () => _openUrl(Uri(
                              scheme: 'mailto',
                              path: place.email,
                            ).toString()),
                            child: Text(
                              place.email!,
                              style: const TextStyle(
                                color: Color(0xFFDF2881),
                                fontSize: 13,
                                decoration: TextDecoration.underline,
                                decorationColor: Color(0xFFDF2881),
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ],
                    // Endereço (abaixo do e-mail) + botões "Abrir com Maps" / "Saiba mais"
                    Padding(
                      padding: EdgeInsets.only(top: place.email != null ? 6 : 0),
                      child: Row(children: [
                        const Icon(Icons.location_on, size: 16, color: Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            place.address ?? 'Endereço não informado',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 13),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      OutlinedButton.icon(
                        onPressed: _openInMaps,
                        icon: const Icon(Icons.map_rounded, size: 16),
                        label: const Text('Abrir com Maps'),
                        style: _linkButtonStyle,
                      ),
                      // Site oficial (OSM, Wikidata ou MusicBrainz), quando houver
                      if (place.website != null)
                        OutlinedButton.icon(
                          onPressed: () => _openUrl(place.website!),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Saiba mais'),
                          style: _linkButtonStyle,
                        ),
                    ]),

                    // Oportunidades abertas vinculadas a este pino
                    if (place.hasActiveOpportunities) _buildOpportunities(),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}