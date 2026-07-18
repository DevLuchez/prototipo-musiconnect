import 'dart:convert';
import 'package:http/http.dart' as http;
import '../place_model.dart';
import '../../../core/config/api_config.dart';

/// Consome o backend FastAPI MusiConnect.
/// Endpoint principal: GET /api/institutions/nearby
///
/// Substitui o CuratedInstitutionsService (JSON estático) e o
/// OverpassService (chamada direta ao OSM) como fonte primária de dados.
class MusicConnectApiService {
  static const Duration _timeout = Duration(seconds: 15);

  /// Busca instituições musicais próximas a [lat]/[lng] dentro de [radiusM] metros.
  /// Retorna lista vazia em caso de erro (app não quebra).
  Future<List<PlaceModel>> fetchNearby({
    required double lat,
    required double lng,
    int radiusM = 50000,
    int limit = 500,
  }) async {
    final uri = Uri.parse(ApiConfig.nearby).replace(queryParameters: {
      'lat': lat.toString(),
      'lng': lng.toString(),
      'radius_m': radiusM.toString(),
      'limit': limit.toString(),
    });

    try {
      print('[MusicConnectAPI] GET $uri');
      final response = await http.get(uri).timeout(_timeout);
      print('[MusicConnectAPI] Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> body = json.decode(response.body) as List<dynamic>;
        print('[MusicConnectAPI] Retornados: ${body.length} locais');
        return body
            .map((e) => PlaceModel.tryFromBackend(e as Map<String, dynamic>))
            .whereType<PlaceModel>()
            .toList();
      }

      print('[MusicConnectAPI] Erro HTTP ${response.statusCode}: ${response.body.substring(0, response.body.length.clamp(0, 300))}');
    } catch (e) {
      print('[MusicConnectAPI] Exceção: $e');
    }
    return [];
  }

  /// Busca TODAS as instituições do banco sem filtro geoespacial.
  /// Usado na carga inicial do mapa para exibir todos os marcadores
  /// imediatamente, independentemente de zoom ou localização.
  Future<List<PlaceModel>> fetchAll({int limit = 5000}) async {
    final uri = Uri.parse(ApiConfig.all).replace(queryParameters: {
      'limit': limit.toString(),
    });

    try {
      print('[MusicConnectAPI] GET $uri (todas as instituições)');
      final response = await http.get(uri).timeout(_timeout);
      print('[MusicConnectAPI] Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> body = json.decode(response.body) as List<dynamic>;
        print('[MusicConnectAPI] Total retornado: ${body.length} instituições');
        return body
            .map((e) => PlaceModel.tryFromBackend(e as Map<String, dynamic>))
            .whereType<PlaceModel>()
            .toList();
      }

      print('[MusicConnectAPI] Erro HTTP ${response.statusCode}');
    } catch (e) {
      print('[MusicConnectAPI] Exceção em fetchAll: $e');
    }
    return [];
  }

  /// Verifica se o backend está acessível.
  Future<bool> isReachable() async {
    try {
      final response = await http
          .get(Uri.parse(ApiConfig.health))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
