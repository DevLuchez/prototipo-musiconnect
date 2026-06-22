class PlaceModel {
  final String id;
  final String name;
  final String? address;
  final double lat;
  final double lng;
  final String category; // ex: "music_school", "concert_hall", etc.

  PlaceModel({
    required this.id,
    required this.name,
    this.address,
    required this.lat,
    required this.lng,
    required this.category,
  });

  // ── MusiConnect Backend API ───────────────────────────────────

  /// Cria um PlaceModel a partir da resposta do backend FastAPI.
  /// Campos esperados: osm_id, name, address, lat, lng, category, source.
  static PlaceModel? tryFromBackend(Map<String, dynamic> json) {
    try {
      return PlaceModel.fromBackend(json);
    } catch (e) {
      return null;
    }
  }

  factory PlaceModel.fromBackend(Map<String, dynamic> json) {
    final lat = (json['lat'] as num?)?.toDouble() ?? 0;
    final lng = (json['lng'] as num?)?.toDouble() ?? 0;
    if (lat == 0 && lng == 0) throw Exception('Coordenadas inválidas');

    return PlaceModel(
      id: 'backend_${json['osm_id'] ?? json['name']}',
      name: json['name'] as String? ?? 'Local Musical',
      address: json['address'] as String?,
      lat: lat,
      lng: lng,
      category: json['category'] as String? ?? 'music',
    );
  }

  // ────────────────────────────────────────────────────────────

  /// Cria um PlaceModel a partir de um elemento retornado pela Overpass API.
  /// Suporta tanto `node` (lat/lon direto) quanto `way`/`relation` (usa center).
  /// Retorna null se o elemento não tiver coordenadas válidas.
  static PlaceModel? tryFromOverpass(Map<String, dynamic> json) {
    try {
      return PlaceModel.fromOverpass(json);
    } catch (e) {
      return null;
    }
  }

  factory PlaceModel.fromOverpass(Map<String, dynamic> json) {
    final tags = (json['tags'] as Map<String, dynamic>?) ?? {};

    double lat;
    double lng;

    final type = json['type'] as String? ?? '';
    if (type == 'node') {
      lat = (json['lat'] as num?)?.toDouble() ?? 0;
      lng = (json['lon'] as num?)?.toDouble() ?? 0;
    } else {
      // way ou relation — usa o campo "center" (requer 'out center' na query)
      final center = json['center'] as Map<String, dynamic>?;
      lat = (center?['lat'] as num?)?.toDouble() ?? 0;
      lng = (center?['lon'] as num?)?.toDouble() ?? 0;
    }

    if (lat == 0 && lng == 0) throw Exception('Coordenadas inválidas');

    // Resolve a categoria mais descritiva disponível nas tags
    final category = tags['amenity'] ??
        tags['leisure'] ??
        tags['shop'] ??
        tags['tourism'] ??
        'music';

    // Monta um endereço a partir das sub-tags de endereço do OSM, se disponíveis
    final addressParts = <String>[
      if (tags['addr:street'] != null) tags['addr:street']!,
      if (tags['addr:city'] != null) tags['addr:city']!,
      if (tags['addr:country'] != null) tags['addr:country']!,
    ];

    return PlaceModel(
      id: '${json['type']}_${json['id']}',
      name: tags['name'] ?? tags['name:en'] ?? _labelFromCategory(category),
      address: addressParts.isNotEmpty ? addressParts.join(', ') : null,
      lat: lat,
      lng: lng,
      category: category,
    );
  }

  static String _labelFromCategory(String category) {
    const labels = {
      'music_school': 'Escola de Música',
      'concert_hall': 'Casa de Shows',
      'theatre': 'Teatro',
      'nightclub': 'Nightclub',
      'music_venue': 'Local de Música',
      'studio': 'Estúdio',
      'music': 'Local Musical',
      'musical_instrument': 'Loja de Instrumentos',
      'arts_centre': 'Centro Cultural',
    };
    return labels[category] ?? 'Local Musical';
  }

  // ── Google Places API ─────────────────────────────────────────

  static PlaceModel? tryFromGooglePlaces(Map<String, dynamic> json) {
    try {
      return PlaceModel.fromGooglePlaces(json);
    } catch (e) {
      return null;
    }
  }

  factory PlaceModel.fromGooglePlaces(Map<String, dynamic> json) {
    final geometry = json['geometry'] as Map<String, dynamic>;
    final location = geometry['location'] as Map<String, dynamic>;
    final lat = (location['lat'] as num).toDouble();
    final lng = (location['lng'] as num).toDouble();

    final name = json['name'] as String? ?? 'Local desconhecido';
    final address = json['vicinity'] as String?;
    final placeId = json['place_id'] as String? ?? name;

    // Mapeia os tipos do Google Places para categorias internas
    final types = (json['types'] as List<dynamic>?)?.cast<String>() ?? [];
    String category = 'music';
    if (types.contains('school') || types.contains('university')) {
      category = 'music_school';
    } else if (types.contains('night_club')) {
      category = 'nightclub';
    } else if (types.contains('movie_theater') ||
        types.contains('performing_arts_theater')) {
      category = 'theatre';
    } else if (types.contains('bar') || types.contains('restaurant')) {
      category = 'music_venue';
    } else if (types.contains('store') || types.contains('shopping_mall')) {
      category = 'musical_instrument';
    }

    return PlaceModel(
      id: 'gp_$placeId',
      name: name,
      address: address,
      lat: lat,
      lng: lng,
      category: category,
    );
  }

  /// Rótulo amigável para exibição na UI.
  String get categoryLabel => PlaceModel._labelFromCategory(category);
}
