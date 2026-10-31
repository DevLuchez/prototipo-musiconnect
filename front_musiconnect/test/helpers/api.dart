import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Servidor simulado: cada requisição é registrada em [requests] e
/// respondida pelo [handler] do teste. Os serviços usam as funções
/// globais do pacote http (http.get etc.), que dentro de [run] passam a
/// usar este servidor.
class FakeApi {
  FakeApi(this.handler);

  http.Response Function(http.Request request) handler;
  final requests = <http.Request>[];

  http.Request get last => requests.last;

  /// Roda [body] com as chamadas HTTP indo para este servidor simulado.
  Future<T> run<T>(Future<T> Function() body) => http.runWithClient(
        body,
        () => MockClient((request) async {
          requests.add(request);
          return handler(request);
        }),
      );
}

/// Resposta JSON (com acentos em UTF-8, como o backend manda).
http.Response jsonResponse(Object body, {int status = 200, Map<String, String>? headers}) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json; charset=utf-8', ...?headers});

/// Erro do FastAPI: {"detail": "..."}.
http.Response detailError(String detail, {int status = 400}) =>
    jsonResponse({'detail': detail}, status: status);

/// Falha de rede (sem conexão).
http.Response offline(http.Request _) => throw http.ClientException('sem rede');

/// GeoNames simulado: um país, um estado e uma cidade.
http.Response geoNames(http.Request r) {
  if (r.url.path.endsWith('/countryInfoJSON')) {
    return jsonResponse({'geonames': [{'countryName': 'Brasil', 'countryCode': 'BR'}]});
  }
  if (r.url.queryParameters['featureCode'] == 'ADM1') {
    return jsonResponse({'geonames': [{'name': 'Santa Catarina', 'adminCode1': '26'}]});
  }
  return jsonResponse({'geonames': [{'name': 'Jaraguá do Sul'}]});
}

Map<String, dynamic> placeJson(String osmId, {int opportunities = 0}) => {
      'osm_id': osmId,
      'name': 'Instituição $osmId',
      'lat': -26.48,
      'lng': -49.07,
      'category': 'music_school',
      'active_opportunities_count': opportunities,
    };

Map<String, dynamic> opportunityJson(int id, {String title = 'Oportunidade'}) =>
    {'id': id, 'title': title, 'type': 'audicao'};

Map<String, dynamic> userJson({String? token, String? privacyVersion}) => {
      'id': 1,
      'email': 'aluna@example.com',
      'name': 'Aluna',
      'instruments': ['Violino'],
      'is_professional': false,
      'is_student': true,
      'country': 'Brasil',
      'state': 'SC',
      'city': 'Jaraguá do Sul',
      'privacy_policy_version': privacyVersion,
      if (token != null) 'token': token,
    };
