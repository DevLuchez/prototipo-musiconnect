import 'dart:convert';
import 'package:http/http.dart' as http;
import '../place_model.dart';

/// Serviço que usa a Google Places API (Nearby Search) para buscar
/// instituições musicais próximas a um ponto geográfico.
/// Assim como o Google Maps, os resultados são visíveis em qualquer zoom.
class GooglePlacesService {
  static const String _apiKey = 'AIzaSyCUyLZsk0YK9N15ZvRmPDMs5SjpIkJ-9gQ';
  static const String _baseUrl =
      'https://maps.googleapis.com/maps/api/place/nearbysearch/json';

  /// Busca locais musicais num raio ao redor de [lat]/[lng].
  /// [radiusMeters] máximo permitido pela API: 50.000m (50km).
  Future<List<PlaceModel>> searchNearby({
    required double lat,
    required double lng,
    int radiusMeters = 30000,
  }) async {
    // Faz buscas para cada tipo de local musical em paralelo
    final futures = _searchTerms.map(
      (term) => _fetchByKeyword(lat, lng, radiusMeters, term),
    );
    final results = await Future.wait(futures);

    // Mescla e desduplicar pelo place_id
    final seen = <String>{};
    final places = <PlaceModel>[];
    for (final list in results) {
      for (final place in list) {
        if (seen.add(place.id)) places.add(place);
      }
    }
    return places;
  }

  static const List<String> _searchTerms = [
    'escola de música',
    'conservatório',
    'academia de música',
    'casa de shows',
    'teatro musical',
  ];

  Future<List<PlaceModel>> _fetchByKeyword(
    double lat,
    double lng,
    int radius,
    String keyword,
  ) async {
    try {
      final uri = Uri.parse(_baseUrl).replace(queryParameters: {
        'location': '$lat,$lng',
        'radius': radius.toString(),
        'keyword': keyword,
        'language': 'pt-BR',
        'key': _apiKey,
      });

      final response =
          await http.get(uri).timeout(const Duration(seconds: 15));

      print('[PlacesService] "$keyword" → ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final status = data['status'] as String?;
        print('[PlacesService] status=$status');

        if (status == 'OK' || status == 'ZERO_RESULTS') {
          final results = (data['results'] as List<dynamic>?) ?? [];
          return results
              .map((r) =>
                  PlaceModel.tryFromGooglePlaces(r as Map<String, dynamic>))
              .whereType<PlaceModel>()
              .toList();
        } else {
          // REQUEST_DENIED → Places API não habilitada no Cloud Console
          print('[PlacesService] ERRO: $status — ${data['error_message']}');
        }
      }
    } catch (e) {
      print('[PlacesService] Exceção "$keyword": $e');
    }
    return [];
  }
}
