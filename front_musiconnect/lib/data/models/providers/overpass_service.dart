import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../place_model.dart';

class OverpassService {
  // kumi.systems pede User-Agent explícito — com ele, funciona corretamente.
  static const String _endpoint =
      'https://overpass.kumi.systems/api/interpreter';

  static const _headers = {
    'User-Agent': 'MusicConnect/1.0 (TCC academico Flutter)',
    'Referer': 'https://musiconnect.app',
  };

  Future<List<PlaceModel>> fetchMusicPlacesInBounds(
      LatLngBounds bounds) async {
    final s = bounds.southwest.latitude.toStringAsFixed(5);
    final w = bounds.southwest.longitude.toStringAsFixed(5);
    final n = bounds.northeast.latitude.toStringAsFixed(5);
    final e = bounds.northeast.longitude.toStringAsFixed(5);
    final bbox = '$s,$w,$n,$e';

    // Query compacta em linha única — evita problemas de encoding com quebras de linha
    final query =
        '[out:json][timeout:25];'
        '('
        'node["amenity"="music_school"]($bbox);'
        'node["amenity"="concert_hall"]($bbox);'
        'node["amenity"="theatre"]($bbox);'
        'node["amenity"="nightclub"]($bbox);'
        'node["amenity"="arts_centre"]($bbox);'
        'node["leisure"="music_venue"]($bbox);'
        'node["shop"="music"]($bbox);'
        'node["shop"="musical_instrument"]($bbox);'
        'node["live_music"="yes"]($bbox);'
        'way["amenity"="music_school"]($bbox);'
        'way["amenity"="concert_hall"]($bbox);'
        'way["amenity"="theatre"]($bbox);'
        'way["leisure"="music_venue"]($bbox);'
        'way["shop"="music"]($bbox);'
        ');'
        'out center 300;';

    try {
      // GET com User-Agent — formato que kumi.systems aceita
      final uri = Uri.parse(_endpoint).replace(
        queryParameters: {'data': query},
      );

      print('[Overpass] GET $uri');
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 30));

      print('[Overpass] Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final body = json.decode(response.body) as Map<String, dynamic>;
        final elements = (body['elements'] as List<dynamic>?) ?? [];
        print('[Overpass] Elementos: ${elements.length}');
        if (elements.isNotEmpty) print('[Overpass] Ex: ${elements.first}');

        return elements
            .map((e) => PlaceModel.tryFromOverpass(e as Map<String, dynamic>))
            .whereType<PlaceModel>()
            .toList();
      }

      print('[Overpass] Corpo: ${response.body.substring(0, response.body.length.clamp(0, 300))}');
    } catch (e) {
      print('[Overpass] Erro: $e');
    }
    return [];
  }
}
