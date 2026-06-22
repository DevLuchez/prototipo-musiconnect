import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  Timer? _cameraDebounce; // evita busca a cada micro-movimento

  final Map<MarkerId, Marker> _markers = {};
  LatLng _mapCenter = const LatLng(-26.3044, -48.8493); // Joinville/SC

  bool _isLoading = true;
  bool _backendOffline = false;
  String _status = 'Conectando ao servidor...';
  int _backendCount = 0;

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
    super.dispose();
  }

  // ── Carga inicial: verifica backend e carrega área inicial ────

  Future<void> _initialLoad() async {
    final online = await _apiService.isReachable();
    if (!mounted) return;

    if (!online) {
      setState(() {
        _backendOffline = true;
        _isLoading = false;
        _status = 'Backend offline — dados não disponíveis';
      });
      return;
    }

    // Raio de 200km na abertura → mostra todas as instituições da região imediatamente
    await _fetchFromBackend(_mapCenter, radiusM: 200000);
  }

  // ── Busca no backend (fonte primária) ─────────────────────────

  Future<void> _fetchFromBackend(LatLng center, {int radiusM = 50000}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _status = 'Buscando instituições musicais...';
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
      final mid = MarkerId(p.id);
      if (!_markers.containsKey(mid)) {
        _markers[mid] = _buildMarker(p, fromBackend: true);
        newCount++;
      }
    }
    _backendCount += newCount;

    setState(() {
      _isLoading = false;
      final total = _markers.length;
      _status = '$total instituições no mapa';
    });
  }

  // ── Eventos do mapa ───────────────────────────────────────────

  void _onMapCreated(GoogleMapController c) {
    _mapController = c;
    c.setMapStyle(_mapStyle);
  }

  void _onCameraMove(CameraPosition pos) {
    _mapCenter = pos.target;
  }

  void _onCameraIdle() {
    // Debounce de 800ms: só busca após o mapa ficar parado
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
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Explorar Instituições'),
          Text(_status,
              style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ]),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
            ),
          IconButton(
            icon: const Icon(Icons.legend_toggle),
            tooltip: 'Legenda',
            onPressed: _showLegend,
          ),
        ],
      ),
      body: Stack(children: [
        GoogleMap(
          onMapCreated: _onMapCreated,
          initialCameraPosition: CameraPosition(target: _mapCenter, zoom: 12.0),
          markers: Set.of(_markers.values),
          myLocationEnabled: false,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: true,
          onCameraMove: _onCameraMove,
          onCameraIdle: _onCameraIdle,
        ),

        // Banner de aviso: backend offline
        if (_backendOffline)
          Positioned(
            top: 0, left: 0, right: 0,
            child: Material(
              color: Colors.amber[700],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'Backend offline. Inicie o servidor FastAPI e reinicie o app.',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  )),
                ]),
              ),
            ),
          ),



        // Indicador de carregamento inicial
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
      ]),


    );
  }

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
            Center(child: Container(width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)))),
            Text('Legenda', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _legendItem(Colors.purple,     'Escola de Música / Conservatório'),
            _legendItem(Colors.pink,       'Casa de Shows / Centro Cultural'),
            _legendItem(Colors.deepPurple, 'Teatro / Ópera'),
            _legendItem(Colors.blue,       'Nightclub'),
            _legendItem(Colors.orange,     'Local de Música ao Vivo'),
            _legendItem(Colors.cyan,       'Loja de Instrumentos / Música'),
            const Divider(),
            Row(children: [
              const Icon(Icons.storage, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(child: Text(
                '$_backendCount instituições carregadas do banco de dados',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              )),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(Color color, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Container(width: 14, height: 14,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 13)),
        ]),
      );
}

// ── Widgets auxiliares ────────────────────────────────────────────

class _DetailSheet extends StatelessWidget {
  final PlaceModel place;
  const _DetailSheet({required this.place});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2)))),
            Row(children: [
              const Icon(Icons.music_note, color: Colors.purple),
              const SizedBox(width: 8),
              Expanded(child: Text(place.name,
                  style: Theme.of(context).textTheme.titleLarge)),
            ]),
            const SizedBox(height: 8),
            Chip(label: Text(place.categoryLabel),
                backgroundColor: Colors.purple[50],
                labelStyle: const TextStyle(color: Colors.purple)),
            if (place.address != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.location_on, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(child: Text(place.address!,
                    style: const TextStyle(color: Colors.grey))),
              ]),
            ],
          ],
        ),
      );
}