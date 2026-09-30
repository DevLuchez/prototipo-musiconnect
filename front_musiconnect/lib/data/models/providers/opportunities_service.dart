import 'dart:convert';
import 'package:http/http.dart' as http;
import '../opportunity_model.dart';
import '../../../core/config/api_config.dart';
import 'auth_service.dart';

/// Resultado de [OpportunitiesService.fetchOpportunities]: a página de
/// resultados junto com o total real que atende aos filtros (antes do
/// corte por `limit`) — o backend manda isso no header `X-Total-Count`,
/// já que `items.length` só reflete o tamanho da página, não o total.
class OpportunitiesResult {
  final List<OpportunityModel> items;
  final int total;

  const OpportunitiesResult({required this.items, required this.total});
}

/// Um valor de filtro com rótulo de exibição — usado quando o valor cru
/// (o que vai pro backend) é diferente do que se mostra pro usuário, como
/// em Estado ("MT" vira "MT | Montana").
class FilterOption {
  final String value;
  final String label;

  const FilterOption({required this.value, required this.label});
}

/// Opções disponíveis pra popular os seletores do modal de filtros —
/// só valores que realmente aparecem em pelo menos uma oportunidade
/// visível (ver GET /api/opportunities/filter-options no backend), já
/// cruzadas com os filtros atualmente escolhidos nos outros campos.
class FilterOptions {
  final List<String> instruments;
  final List<String> countries;
  final List<FilterOption> states;
  final List<String> cities;

  const FilterOptions({
    this.instruments = const [],
    this.countries = const [],
    this.states = const [],
    this.cities = const [],
  });
}

/// Marcador "oportunidades por cidade" do mapa: oportunidades abertas de
/// uma cidade cuja organizadora não tem localização exata (sem pino de
/// instituição) — ver GET /api/opportunities/cities no backend.
class CityOpportunities {
  final int id;
  final String city;
  final String? state;
  final String? country;
  final double lat;
  final double lng;
  final int count;

  const CityOpportunities({
    required this.id,
    required this.city,
    this.state,
    this.country,
    required this.lat,
    required this.lng,
    required this.count,
  });

  factory CityOpportunities.fromJson(Map<String, dynamic> json) =>
      CityOpportunities(
        id: json['id'] as int,
        city: json['city'] as String,
        state: json['state'] as String?,
        country: json['country'] as String?,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        count: json['opportunities_count'] as int? ?? 0,
      );

  /// "Norfolk, VA, Estados Unidos"
  String get label => [city, state, country]
      .where((p) => p != null && p.isNotEmpty)
      .join(', ');
}

/// Serviço para buscar oportunidades musicais da API MusiConnect.
class OpportunitiesService {
  static const Duration _timeout = Duration(seconds: 20);

  final _authService = AuthService();

  /// Header de autenticação, quando há sessão salva — permite ao backend
  /// calcular `match_percentage` por oportunidade. Sem sessão, a listagem
  /// continua funcionando normalmente, só sem o percentual de match.
  Future<Map<String, String>> _authHeaders() async {
    final token = await _authService.getStoredToken();
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }

  /// Busca oportunidades com filtros opcionais.
  ///
  /// [q]         : filtro por título (busca parcial)
  /// [types]/[instruments]/[countries]/[states]/[cities]: cada um aceita
  ///   vários valores (multi-seleção) — dentro do mesmo campo é OR, entre
  ///   campos diferentes é AND. [types] serve tanto pro tipo travado por
  ///   categoria (carrossel/subpágina — um valor só) quanto pro filtro de
  ///   "Tipo de oportunidade" escolhido no modal (múltiplos valores).
  /// [onlyActive]: se true, exclui oportunidades com prazo vencido
  /// [limit]     : máximo de resultados
  /// [offset]    : paginação
  Future<OpportunitiesResult> fetchOpportunities({
    String? q,
    List<String>? types,
    List<String>? instruments,
    List<String>? countries,
    List<String>? states,
    List<String>? cities,
    int? cityLocationId,
    bool onlyActive = true,
    int limit = 100,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{
      'only_active': onlyActive.toString(),
      'limit': limit.toString(),
      'offset': offset.toString(),
      if (q != null && q.isNotEmpty) 'q': q,
      if (types != null && types.isNotEmpty) 'type': types,
      if (instruments != null && instruments.isNotEmpty) 'instrument': instruments,
      if (countries != null && countries.isNotEmpty) 'country': countries,
      if (states != null && states.isNotEmpty) 'state': states,
      if (cities != null && cities.isNotEmpty) 'city': cities,
      if (cityLocationId != null) 'city_location_id': cityLocationId.toString(),
    };

    final uri = Uri.parse(ApiConfig.opportunities)
        .replace(queryParameters: params);

    try {
      print('[OpportunitiesService] GET $uri');
      final response = await http
          .get(uri, headers: await _authHeaders())
          .timeout(_timeout);
      print('[OpportunitiesService] Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> body =
            json.decode(utf8.decode(response.bodyBytes)) as List<dynamic>;
        final items = body
            .map((e) => OpportunityModel.fromJson(e as Map<String, dynamic>))
            .toList();
        // Total real, antes do corte por `limit` — cai pro tamanho da
        // página se o header não vier (ex: resposta de erro/proxy antigo).
        final total = int.tryParse(
              response.headers['x-total-count'] ?? '',
            ) ??
            items.length;
        print(
          '[OpportunitiesService] ${items.length} recebidas (total real: $total)',
        );
        return OpportunitiesResult(items: items, total: total);
      }

      print('[OpportunitiesService] Erro HTTP ${response.statusCode}');
    } catch (e) {
      print('[OpportunitiesService] Exceção: $e');
    }
    return const OpportunitiesResult(items: [], total: 0);
  }

  /// Busca os valores disponíveis pra popular os seletores do modal de
  /// filtros (Instrumento, País, Estado, Cidade) — cruzados com o que já
  /// está selecionado nos OUTROS campos (busca facetada): passe os filtros
  /// atualmente escolhidos pra que a lista de cada campo reflita só o que
  /// tem oportunidade de verdade dado o resto da seleção.
  Future<FilterOptions> fetchFilterOptions({
    List<String>? instruments,
    List<String>? countries,
    List<String>? states,
    List<String>? cities,
  }) async {
    try {
      final params = <String, dynamic>{
        if (instruments != null && instruments.isNotEmpty) 'instrument': instruments,
        if (countries != null && countries.isNotEmpty) 'country': countries,
        if (states != null && states.isNotEmpty) 'state': states,
        if (cities != null && cities.isNotEmpty) 'city': cities,
      };
      final uri = Uri.parse(ApiConfig.opportunityFilterOptions)
          .replace(queryParameters: params);
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode == 200) {
        final Map<String, dynamic> body =
            json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        // Ordena em ordem alfabética explicitamente — não depende da ordem
        // que o backend devolve.
        List<String> asStringList(String key) =>
            (body[key] as List<dynamic>? ?? [])
                .map((e) => e.toString())
                .toList()
              ..sort();
        final states = (body['states'] as List<dynamic>? ?? [])
            .map((e) => FilterOption(
                  value: (e as Map<String, dynamic>)['value'] as String,
                  label: e['label'] as String,
                ))
            .toList()
          ..sort((a, b) => a.label.compareTo(b.label));
        return FilterOptions(
          instruments: asStringList('instruments'),
          countries: asStringList('countries'),
          states: states,
          cities: asStringList('cities'),
        );
      }
      print('[OpportunitiesService] Erro HTTP ${response.statusCode} (filter-options)');
    } catch (e) {
      print('[OpportunitiesService] Exceção (filter-options): $e');
    }
    return const FilterOptions();
  }

  /// Marcadores "oportunidades por cidade" do mapa. Retorna lista vazia em
  /// caso de erro.
  Future<List<CityOpportunities>> fetchCities() async {
    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.opportunities}cities'))
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final List<dynamic> body =
            json.decode(utf8.decode(response.bodyBytes)) as List<dynamic>;
        return body
            .map((e) => CityOpportunities.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      print('[OpportunitiesService] Erro HTTP ${response.statusCode} (cidades)');
    } catch (e) {
      print('[OpportunitiesService] Exceção (cidades): $e');
    }
    return [];
  }

  /// Oportunidades abertas vinculadas a um pino do mapa (osm_id) — usado
  /// no detalhe da instituição. Retorna lista vazia em caso de erro.
  Future<List<OpportunityModel>> fetchByInstitution(String osmId) async {
    final uri = Uri.parse(
        '${ApiConfig.institutions}/${Uri.encodeComponent(osmId)}/opportunities');
    try {
      final response = await http
          .get(uri, headers: await _authHeaders())
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final List<dynamic> body =
            json.decode(utf8.decode(response.bodyBytes)) as List<dynamic>;
        return body
            .map((e) => OpportunityModel.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      print('[OpportunitiesService] Erro HTTP ${response.statusCode} (por instituição)');
    } catch (e) {
      print('[OpportunitiesService] Exceção (por instituição): $e');
    }
    return [];
  }
}
