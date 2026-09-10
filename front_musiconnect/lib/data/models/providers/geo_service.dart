import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/config/api_config.dart';

/// Um país, estado ou cidade retornado pelo GeoNames — carrega o(s)
/// código(s) necessários pra buscar o nível seguinte da cascata (ex: o
/// [countryCode] de um país é usado pra buscar seus estados).
class GeoOption {
  final String name;
  final String? countryCode;
  final String? adminCode1;

  const GeoOption({required this.name, this.countryCode, this.adminCode1});
}

/// Busca países/estados/cidades reais (dados do GeoNames, não mockados)
/// pros campos de seleção em cascata do cadastro: escolher um país
/// restringe as opções de estado às daquele país, e escolher um estado
/// restringe as opções de cidade às daquele estado.
class GeoService {
  static const Duration _timeout = Duration(seconds: 15);

  Uri _uri(String path, Map<String, String> params) {
    return Uri.parse('${ApiConfig.geoNamesBaseUrl}$path').replace(
      queryParameters: {
        ...params,
        'username': ApiConfig.geoNamesUsername,
      },
    );
  }

  /// Todos os países do mundo, ordenados por nome.
  Future<List<GeoOption>> fetchCountries() async {
    final uri = _uri('/countryInfoJSON', {'lang': 'pt'});
    try {
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return const [];
      final body = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final list = (body['geonames'] as List<dynamic>? ?? [])
          .map((e) => GeoOption(
                name: (e as Map<String, dynamic>)['countryName'] as String,
                countryCode: e['countryCode'] as String,
              ))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return list;
    } catch (e) {
      print('[GeoService] Exceção (countries): $e');
      return const [];
    }
  }

  /// Estados/províncias (divisão administrativa de 1º nível) do país
  /// [countryCode] (ISO 3166-1 alpha-2, ex: "BR"), ordenados por nome.
  Future<List<GeoOption>> fetchStates(String countryCode) async {
    final uri = _uri('/searchJSON', {
      'country': countryCode,
      'featureCode': 'ADM1',
      'maxRows': '1000',
      'lang': 'pt',
    });
    try {
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return const [];
      final body = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final list = (body['geonames'] as List<dynamic>? ?? [])
          .map((e) => GeoOption(
                name: (e as Map<String, dynamic>)['name'] as String,
                countryCode: countryCode,
                adminCode1: e['adminCode1'] as String?,
              ))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return list;
    } catch (e) {
      print('[GeoService] Exceção (states): $e');
      return const [];
    }
  }

  /// Cidades do estado [adminCode1] dentro do país [countryCode],
  /// ordenadas por população (maiores primeiro — mais úteis no topo).
  Future<List<GeoOption>> fetchCities(String countryCode, String adminCode1) async {
    final uri = _uri('/searchJSON', {
      'country': countryCode,
      'adminCode1': adminCode1,
      'featureClass': 'P',
      'maxRows': '1000',
      'orderby': 'population',
      'lang': 'pt',
    });
    try {
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return const [];
      final body = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final list = (body['geonames'] as List<dynamic>? ?? [])
          .map((e) => GeoOption(name: (e as Map<String, dynamic>)['name'] as String))
          .toList();
      return list;
    } catch (e) {
      print('[GeoService] Exceção (cities): $e');
      return const [];
    }
  }
}
