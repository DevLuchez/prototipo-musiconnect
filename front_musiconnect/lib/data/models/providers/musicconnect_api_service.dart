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

  /// Totais reais do banco (independente de quantas instituições já foram
  /// carregadas/renderizadas no mapa): todas as catalogadas e as que têm
  /// oportunidades abertas. Retorna null em caso de erro.
  Future<({int total, int withOpportunities})?> fetchStats() async {
    try {
      final response =
          await http.get(Uri.parse(ApiConfig.stats)).timeout(_timeout);
      if (response.statusCode == 200) {
        final body = json.decode(response.body) as Map<String, dynamic>;
        return (
          total: body['total'] as int? ?? 0,
          withOpportunities: body['with_active_opportunities'] as int? ?? 0,
        );
      }
    } catch (e) {
      print('[MusicConnectAPI] Exceção em fetchStats: $e');
    }
    return null;
  }

  /// Busca da barra do mapa em todas as instituições do banco (nome ou
  /// endereço, sem diferenciar acentos). Retorna null em caso de erro, para
  /// o mapa cair na busca local.
  Future<List<PlaceModel>?> search(String query, {int limit = 8}) async {
    final uri = Uri.parse('${ApiConfig.institutions}/search').replace(
      queryParameters: {'q': query, 'limit': limit.toString()},
    );
    try {
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode == 200) {
        final List<dynamic> body =
            json.decode(utf8.decode(response.bodyBytes)) as List<dynamic>;
        return body
            .map((e) => PlaceModel.tryFromBackend(e as Map<String, dynamic>))
            .whereType<PlaceModel>()
            .toList();
      }
      print('[MusicConnectAPI] Erro HTTP ${response.statusCode} em search');
    } catch (e) {
      print('[MusicConnectAPI] Exceção em search: $e');
    }
    return null;
  }

  /// Uma instituição pelo osm_id — usada quando o mapa precisa focar num
  /// pino que ainda não foi carregado. Retorna null em caso de erro.
  Future<PlaceModel?> fetchById(String osmId) async {
    final uri = Uri.parse('${ApiConfig.institutions}/${Uri.encodeComponent(osmId)}');
    try {
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode == 200) {
        return PlaceModel.tryFromBackend(
          json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
        );
      }
      print('[MusicConnectAPI] Erro HTTP ${response.statusCode} em fetchById');
    } catch (e) {
      print('[MusicConnectAPI] Exceção em fetchById: $e');
    }
    return null;
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
