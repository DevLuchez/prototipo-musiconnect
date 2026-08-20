import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/place_model.dart';
import '../../data/models/providers/musicconnect_api_service.dart';

const String _mapStyle = '''
[
  {"featureType":"poi","elementType":"all","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"visibility":"on"}]},
  {"featureType":"transit","elementType":"labels.icon","stylers":[{"visibility":"off"}]}
]
''';

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

  LatLng _mapCenter = const LatLng(-26.3044, -48.8493); // Joinville/SC

  bool _isLoading = true;
  bool _backendOffline = false;
  int _backendCount = 0;

  // Busca
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<PlaceModel> _searchResults = [];
  bool _showSearchResults = false;

  static final Map<String, double> _hues = {
    'music_school':       BitmapDescriptor.hueViolet,
    'concert_hall':       BitmapDescriptor.hueRose,
    'theatre':            BitmapDescriptor.hueMagenta,
    'nightclub':          BitmapDescriptor.hueBlue,
    'music_venue':        BitmapDescriptor.hueOrange,
    'studio':             BitmapDescriptor.hueYellow,
    'arts_centre':        BitmapDescriptor.hueRose,
    'music':              BitmapDescriptor.hueCyan,
    'musical_instrument': BitmapDescriptor.hueCyan,
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
    if (!mounted) return;

    for (final p in places) {
      _addPlace(p, fromBackend: true);
    }
    _backendCount = _markers.length;

    setState(() => _isLoading = false);
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

    int newCount = 0;
    for (final p in places) {
      if (_addPlace(p, fromBackend: true)) newCount++;
    }
    _backendCount += newCount;

    setState(() => _isLoading = false);
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

  // ── Ações do menu ⋮ ──────────────────────────────────────────

  Future<void> _openGoogleMaps() async {
    final url = Uri.parse(
      'https://www.google.com/maps/@${_mapCenter.latitude},${_mapCenter.longitude},14z',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível abrir o Google Maps')),
        );
      }
    }
  }

  void _openFavorites() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pins favoritos em breve!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ── Eventos do mapa ───────────────────────────────────────────

  void _onMapCreated(GoogleMapController c) {
    _mapController = c;
  }

  void _onCameraMove(CameraPosition pos) {
    _mapCenter = pos.target;
  }

  void _onCameraIdle() {
    _cameraDebounce?.cancel();
    _cameraDebounce = Timer(const Duration(milliseconds: 800), () {
      if (!_backendOffline && !_isLoading) {
        _fetchFromBackend(_mapCenter);
      }
    });
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
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
            markers: Set.of(_markers.values),
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
                        'Backend offline. Inicie o servidor FastAPI e reinicie o app.',
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
                // Barra principal
                Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Menu ⋮
                      _SearchMenuButton(
                        onGoogleMaps: _openGoogleMaps,
                        onFavorites: _openFavorites,
                      ),
                      // Divisor vertical
                      Container(
                        width: 1,
                        height: 24,
                        color: Colors.grey[200],
                      ),
                      // Campo de busca
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            hintText:
                                'Busque por localização ou instituição...',
                            hintStyle: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 13,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      // Ícone de busca ou limpar
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _showSearchResults
                            ? GestureDetector(
                                onTap: _clearSearch,
                                child: Icon(Icons.close,
                                    color: Colors.grey[500], size: 20),
                              )
                            : Icon(Icons.search,
                                color: Colors.grey[400], size: 20),
                      ),
                    ],
                  ),
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
                                          color: const Color(0xFF7C3AED)
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: const Icon(
                                          Icons.music_note_rounded,
                                          color: Color(0xFF7C3AED),
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
            const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Carregando mapa musical global...'),
                  ]),
                ),
              ),
            ),

          // ── Botões flutuantes (direita) ────────────────────────
          Positioned(
            bottom: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Indicador de loading (pós-carga inicial)
                if (_isLoading && _markers.isNotEmpty)
                  Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 8)
                      ],
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF7C3AED)),
                    ),
                  ),
                // Botão de legenda
                FloatingActionButton.small(
                  heroTag: 'legend_fab',
                  onPressed: _showLegend,
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF7C3AED),
                  elevation: 4,
                  tooltip: 'Legenda',
                  child: const Icon(Icons.legend_toggle_rounded, size: 20),
                ),
              ],
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
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2))),
            ),
            Text('Legenda', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _legendItem(Colors.purple, 'Escola de Música / Conservatório'),
            _legendItem(Colors.pink, 'Casa de Shows / Centro Cultural'),
            _legendItem(Colors.deepPurple, 'Teatro / Ópera'),
            _legendItem(Colors.blue, 'Nightclub'),
            _legendItem(Colors.orange, 'Local de Música ao Vivo'),
            _legendItem(Colors.cyan, 'Loja de Instrumentos / Música'),
            const Divider(),
            Row(children: [
              const Icon(Icons.storage, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$_backendCount instituições carregadas do banco de dados',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ),
            ]),
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

// ── Widget: botão de menu ⋮ ───────────────────────────────────────

class _SearchMenuButton extends StatelessWidget {
  final VoidCallback onGoogleMaps;
  final VoidCallback onFavorites;

  const _SearchMenuButton({
    required this.onGoogleMaps,
    required this.onFavorites,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: Colors.grey[600], size: 22),
      tooltip: 'Opções do mapa',
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 8,
      onSelected: (value) {
        if (value == 'google_maps') {
          onGoogleMaps();
        } else if (value == 'favorites') {
          onFavorites();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'google_maps',
          child: Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.map_rounded,
                  color: Colors.blue, size: 16),
            ),
            const SizedBox(width: 10),
            const Text('Google Maps',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ]),
        ),
        PopupMenuItem<String>(
          value: 'favorites',
          child: Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.pink.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.favorite_rounded,
                  color: Colors.pink, size: 16),
            ),
            const SizedBox(width: 10),
            const Text('Pins favoritos',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ]),
        ),
      ],
    );
  }
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

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2))),
            ),

            // Nome
            Row(children: [
              const Icon(Icons.music_note, color: Color(0xFF7C3AED)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(place.name,
                      style: Theme.of(context).textTheme.titleLarge)),
            ]),
            const SizedBox(height: 10),

            // Categoria + badge verificado
            Wrap(spacing: 8, children: [
              Chip(
                label: Text(place.categoryLabel),
                backgroundColor: const Color(0xFF7C3AED).withOpacity(0.08),
                labelStyle: const TextStyle(color: Color(0xFF7C3AED)),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4),
                  side: BorderSide.none,
                ),
            ]),

            // Endereço
            if (place.address != null) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.location_on,
                    size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                    child: Text(place.address!,
                        style:
                            const TextStyle(color: Colors.grey))),
              ]),
            ],

            // Descrição
            if (place.description != null) ...[
              const SizedBox(height: 10),
              Text(place.description!,
                  style: TextStyle(
                      color: Colors.grey[700], fontSize: 13)),
            ],

            // Links externos
            if (place.website != null ||
                place.wikidataId != null ||
                place.mbId != null) ...[
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (place.website != null)
                  ActionChip(
                    avatar:
                        const Icon(Icons.language, size: 16),
                    label: const Text('Site oficial'),
                    onPressed: () => _openUrl(place.website!),
                  ),
                if (place.wikidataId != null)
                  ActionChip(
                    avatar:
                        const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Wikidata'),
                    onPressed: () => _openUrl(
                        'https://www.wikidata.org/wiki/${place.wikidataId}'),
                  ),
                if (place.mbId != null)
                  ActionChip(
                    avatar: const Icon(Icons.album, size: 16),
                    label: const Text('MusicBrainz'),
                    onPressed: () => _openUrl(
                        'https://musicbrainz.org/place/${place.mbId}'),
                  ),
              ]),
            ],
          ],
        ),
      );
}