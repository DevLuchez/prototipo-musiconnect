import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/place_model.dart';
import '../../data/models/providers/musicconnect_api_service.dart';
import '../widgets/app_loading_indicator.dart';

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
];

class MapExplorerScreen extends StatefulWidget {
  const MapExplorerScreen({super.key});
  @override
  State<MapExplorerScreen> createState() => _MapExplorerScreenState();
}

class _MapExplorerScreenState extends State<MapExplorerScreen> {
  GoogleMapController? _mapController;
  final MusicConnectApiService _apiService = MusicConnectApiService();
  Timer? _cameraDebounce;

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
  bool _backendOffline = false;
  int? _dbTotalCount;

  // Busca
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<PlaceModel> _searchResults = [];
  bool _showSearchResults = false;

  // Filtro por tipo de instituição — por padrão, todos os tipos ativos
  // (nenhum filtro aplicado, todos os marcadores aparecem).
  Set<String> _activeFilterKeys =
      _categoryFilters.map((f) => f.key).toSet();

  static final Map<String, double> _hues = {
    'music_school': BitmapDescriptor.hueAzure,
    'concert_hall': BitmapDescriptor.hueRose,
    'arts_centre':  BitmapDescriptor.hueRose,
    'theatre':      BitmapDescriptor.hueViolet,
    'music_venue':  BitmapDescriptor.hueOrange,
  };

  @override
  void initState() {
    super.initState();
    _initialLoad();
  }

  @override
  void dispose() {
    _cameraDebounce?.cancel();
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
      });
      return;
    }

    setState(() => _isLoading = true);

    final places = await _apiService.fetchAll(limit: 5000);
    final total = await _apiService.fetchTotalCount();
    if (!mounted) return;

    for (final p in places) {
      _addPlace(p, fromBackend: true);
    }
    _dbTotalCount = total;

    setState(() => _isLoading = false);
    _nudgeMapRedraw();
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
      _addPlace(p, fromBackend: true);
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
  bool _addPlace(PlaceModel p, {required bool fromBackend}) {
    if (_loadedIds.contains(p.id)) return false;
    _loadedIds.add(p.id);
    _places.add(p);
    final mid = MarkerId(p.id);
    _markers[mid] = _buildMarker(p, fromBackend: fromBackend);
    return true;
  }

  // ── Busca por texto ───────────────────────────────────────────

  void _onSearchChanged(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
      });
      return;
    }
    final lower = query.toLowerCase();
    setState(() {
      _searchResults = _places
          .where((p) =>
              p.name.toLowerCase().contains(lower) ||
              (p.address?.toLowerCase().contains(lower) ?? false) ||
              p.categoryLabel.toLowerCase().contains(lower))
          .take(8)
          .toList();
      _showSearchResults = true;
    });
  }

  void _navigateToPlace(PlaceModel p) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(p.lat, p.lng), zoom: 16),
      ),
    );
    _searchController.clear();
    _searchFocus.unfocus();
    setState(() {
      _searchResults = [];
      _showSearchResults = false;
    });
    // Abre o infoWindow após a animação
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        _mapController?.showMarkerInfoWindow(MarkerId(p.id));
      }
    });
  }

  void _clearSearch() {
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

  /// Marcadores exibidos no mapa, considerando o filtro de tipo ativo.
  /// Com todos os tipos selecionados (padrão), mostra tudo — inclusive
  /// categorias fora dos grupos conhecidos (ex.: ruído de tags do OSM).
  Set<Marker> get _visibleMarkers {
    if (_activeFilterKeys.length == _categoryFilters.length) {
      return Set.of(_markers.values);
    }
    final allowedCategories = <String>{
      for (final f in _categoryFilters)
        if (_activeFilterKeys.contains(f.key)) ...f.categories,
    };
    return _places
        .where((p) => allowedCategories.contains(p.category))
        .map((p) => _markers[MarkerId(p.id)])
        .whereType<Marker>()
        .toSet();
  }

  void _openCategoryFilter() {
    // Seleção provisória — só é aplicada de fato (setState no estado da
    // tela, que filtra os marcadores) quando o usuário toca em "Aplicar".
    final draftKeys = Set<String>.of(_activeFilterKeys);

    showModalBottomSheet(
      context: context,
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
                            setState(() => _activeFilterKeys = draftKeys);
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

  Marker _buildMarker(PlaceModel p, {required bool fromBackend}) => Marker(
        markerId: MarkerId(p.id),
        position: LatLng(p.lat, p.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          _hues[p.category] ?? BitmapDescriptor.hueViolet,
        ),
        infoWindow: InfoWindow(
          title: p.name,
          snippet: '${p.categoryLabel}${p.address != null ? ' · ${p.address}' : ''}',
        ),
        onTap: () => _showDetail(p),
        zIndex: fromBackend ? 2.0 : 1.0,
      );

  void _showDetail(PlaceModel p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetailSheet(place: p),
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
            markers: _showMarkers ? _visibleMarkers : const {},
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
                            if (_activeFilterKeys.length <
                                _categoryFilters.length)
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
                                      '${_categoryFilters.length - _activeFilterKeys.length}',
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
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final f in _categoryFilters)
                    _legendItem(f.color, f.label),
                  const Divider(height: 24),
                  Row(children: [
                    const Icon(Icons.storage, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _dbTotalCount != null
                            ? '$_dbTotalCount instituições catalogadas na base de dados.'
                            : 'Carregando total de instituições catalogadas...',
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 13)),
        ]),
      );
}

// ── Widget: sheet de detalhes ─────────────────────────────────────

class _DetailSheet extends StatelessWidget {
  final PlaceModel place;
  const _DetailSheet({required this.place});

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _openInGoogleMaps() => _openUrl(
      'https://www.google.com/maps/search/?api=1&query=${place.lat},${place.lng}');

  @override
  Widget build(BuildContext context) => Container(
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
                const Icon(Icons.business_rounded, color: Color(0xFFDF2881)),
                const SizedBox(width: 8),
                Expanded(child: Text(place.name, style: _sheetHeaderStyle)),
              ]),
            ),
            const Divider(height: 1),

            // ── Detalhes ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Categoria + badge verificado
                  Wrap(spacing: 8, children: [
                    Chip(
                      label: Text(place.categoryLabel,
                          style: const TextStyle(fontSize: 13)),
                      backgroundColor:
                          const Color(0xFFDF2881).withOpacity(0.08),
                      labelStyle: const TextStyle(color: Color(0xFFDF2881)),
                      side: BorderSide.none,
                    ),
                    if (place.verified)
                      Chip(
                        avatar: const Icon(Icons.verified,
                            size: 16, color: Colors.white),
                        label: const Text('Verificado',
                            style:
                                TextStyle(color: Colors.white, fontSize: 12)),
                        backgroundColor: Colors.green[600],
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        side: BorderSide.none,
                      ),
                  ]),

                  // Endereço + botão "Ver no Google Maps"
                  const SizedBox(height: 12),
                  Row(children: [
                    const Icon(Icons.location_on, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        place.address ?? 'Endereço não disponível',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 13),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _openInGoogleMaps,
                    icon: const Icon(Icons.map_rounded, size: 16),
                    label: const Text('Ver no Google Maps'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFDF2881),
                      side: const BorderSide(color: Color(0xFFDF2881)),
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                    ),
                  ),

                  // Descrição
                  if (place.description != null) ...[
                    const SizedBox(height: 14),
                    Text(place.description!,
                        style:
                            TextStyle(color: Colors.grey[700], fontSize: 13)),
                  ],

                  // Links externos
                  if (place.website != null || place.wikidataId != null) ...[
                    const SizedBox(height: 14),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (place.website != null)
                        ActionChip(
                          avatar: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Saiba mais',
                              style: TextStyle(fontSize: 13)),
                          onPressed: () => _openUrl(place.website!),
                        ),
                      if (place.wikidataId != null)
                        ActionChip(
                          avatar: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Wikidata',
                              style: TextStyle(fontSize: 13)),
                          onPressed: () => _openUrl(
                              'https://www.wikidata.org/wiki/${place.wikidataId}'),
                        ),
                    ]),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}