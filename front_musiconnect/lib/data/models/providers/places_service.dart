import 'dart:convert';
import 'package:http/http.dart' as http;
import '../place_model.dart';

class PlacesService {
  // ⚠️ Certifique-se de habilitar a "Places API" no Google Cloud Console
  // para a mesma API Key usada no AndroidManifest.xml
  static const String _apiKey = 'AIzaSyCUyLZsk0YK9N15ZvRmPDMs5SjpIkJ-9gQ';
  static const String _baseUrl =
      'https://maps.googleapis.com/maps/api/place/nearbysearch/json';

  /// Tipos de locais musicais pesquisados na API.
  /// A busca é feita em rodadas para maximizar a cobertura.
  static const List<String> _musicTypes = [
    'music_store',
    'night_club',
    'concert_hall',
    'stadium',
  ];

  /// Palavras-chave adicionais para capturar locais que a API não classifica
  /// com tipos específicos, como escolas de música e teatros.
  static const List<String> _musicKeywords = [
    'music school',
    'escola de música',
    'conservatório',
    'teatro',
    'music venue',
    'bar ao vivo',
  ];

  /// Busca locais musicais próximos a uma coordenada [lat]/[lng],
  /// em um raio de [radiusMeters] metros.
  Future<List<PlaceModel>> fetchNearbyMusicPlaces({
    required double lat,
    required double lng,
    int radiusMeters = 5000,
  }) async {
    final Set<String> seenIds = {};
    final List<PlaceModel> allPlaces = [];

    // Busca por tipo (ex: music_store, night_club)
    for (final type in _musicTypes) {
      final places = await _fetchByType(lat, lng, radiusMeters, type);
      for (final place in places) {
        if (seenIds.add(place.placeId)) {
          allPlaces.add(place);
        }
      }
    }

    // Busca por palavra-chave (ex: "escola de música")
    for (final keyword in _musicKeywords) {
      final places = await _fetchByKeyword(lat, lng, radiusMeters, keyword);
      for (final place in places) {
        if (seenIds.add(place.placeId)) {
          allPlaces.add(place);
        }
      }
    }

    return allPlaces;
  }

  Future<List<PlaceModel>> _fetchByType(
      double lat, double lng, int radius, String type) async {
    final url = Uri.parse(
      '$_baseUrl?location=$lat,$lng&radius=$radius&type=$type&key=$_apiKey',
    );
    return _fetchAndParse(url);
  }

  Future<List<PlaceModel>> _fetchByKeyword(
      double lat, double lng, int radius, String keyword) async {
    final encodedKeyword = Uri.encodeComponent(keyword);
    final url = Uri.parse(
      '$_baseUrl?location=$lat,$lng&radius=$radius&keyword=$encodedKeyword&key=$_apiKey',
    );
    return _fetchAndParse(url);
  }

  Future<List<PlaceModel>> _fetchAndParse(Uri url) async {
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List<dynamic>? ?? [];
        return results
            .map((json) => PlaceModel.fromJson(json as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      // ignore: avoid_print
      print('[PlacesService] Erro ao buscar locais: $e');
    }
    return [];
  }
}
