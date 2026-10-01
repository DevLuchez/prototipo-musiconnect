import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../opportunity_model.dart';
import '../place_model.dart';
import '../../../core/config/api_config.dart';
import 'auth_service.dart';

/// Oportunidades salvas (Matcher) e instituições favoritas (mapa) do
/// usuário logado — ver /api/favorites no backend.
///
/// Instância única pro app todo ([FavoritesService.instance]): o coração
/// de um card, do detalhe da oportunidade e do detalhe do pino precisam
/// mostrar o mesmo estado, então todos escutam este [ChangeNotifier].
///
/// Os IDs são carregados uma vez ao entrar no app ([load]); marcar/desmarcar
/// atualiza o coração na hora e desfaz a mudança se o backend recusar.
class FavoritesService extends ChangeNotifier {
  FavoritesService._();
  static final FavoritesService instance = FavoritesService._();

  static const Duration _timeout = Duration(seconds: 15);

  final _authService = AuthService();

  final Set<int> _opportunityIds = {};
  final Set<String> _institutionIds = {};

  int get opportunityCount => _opportunityIds.length;
  int get institutionCount => _institutionIds.length;

  bool isOpportunitySaved(int id) => _opportunityIds.contains(id);
  bool isInstitutionFavorite(String osmId) => _institutionIds.contains(osmId);

  Future<Map<String, String>> _authHeaders() async {
    final token = await _authService.getStoredToken();
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }

  /// Carrega os IDs salvos do usuário logado — chamado ao abrir o
  /// [MainNavigation]. Limpa antes, pra nunca mostrar os favoritos de quem
  /// estava logado antes neste aparelho.
  Future<void> load() async {
    _opportunityIds.clear();
    _institutionIds.clear();
    notifyListeners();
    try {
      final response = await http
          .get(Uri.parse('${ApiConfig.favorites}/ids'), headers: await _authHeaders())
          .timeout(_timeout);
      if (response.statusCode == 200) {
        final body = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        _opportunityIds.addAll(
          (body['opportunities'] as List<dynamic>? ?? []).map((e) => e as int),
        );
        _institutionIds.addAll(
          (body['institutions'] as List<dynamic>? ?? []).map((e) => e as String),
        );
        notifyListeners();
        return;
      }
      print('[FavoritesService] Erro HTTP ${response.statusCode} (ids)');
    } catch (e) {
      print('[FavoritesService] Exceção (ids): $e');
    }
  }

  /// Salva/remove a oportunidade. Retorna false se o backend recusou (o
  /// coração volta ao estado anterior — cabe a quem chamou avisar o usuário).
  Future<bool> toggleOpportunity(int id) =>
      _toggle(_opportunityIds, id, '${ApiConfig.favorites}/opportunities/$id');

  /// Favorita/desfavorita a instituição. Mesmo contrato de [toggleOpportunity].
  Future<bool> toggleInstitution(String osmId) => _toggle(
        _institutionIds,
        osmId,
        '${ApiConfig.favorites}/institutions/${Uri.encodeComponent(osmId)}',
      );

  Future<bool> _toggle<T>(Set<T> ids, T id, String url) async {
    final adding = !ids.contains(id);
    adding ? ids.add(id) : ids.remove(id);
    notifyListeners();

    try {
      final uri = Uri.parse(url);
      final headers = await _authHeaders();
      final response = await (adding
              ? http.put(uri, headers: headers)
              : http.delete(uri, headers: headers))
          .timeout(_timeout);
      if (response.statusCode == 204) return true;
      print('[FavoritesService] Erro HTTP ${response.statusCode} ($url)');
    } catch (e) {
      print('[FavoritesService] Exceção ($url): $e');
    }

    adding ? ids.remove(id) : ids.add(id);
    notifyListeners();
    return false;
  }

  /// Oportunidades salvas ainda abertas (prazo mais próximo primeiro).
  /// Lança exceção em caso de erro — a tela mostra o estado de erro.
  Future<List<OpportunityModel>> fetchSavedOpportunities() async {
    final body = await _getList('${ApiConfig.favorites}/opportunities');
    final items = body
        .map((e) => OpportunityModel.fromJson(e as Map<String, dynamic>))
        .toList();
    // Sincroniza a contagem com o que o backend considera visível hoje.
    _opportunityIds
      ..clear()
      ..addAll(items.map((o) => o.id));
    notifyListeners();
    return items;
  }

  /// Instituições favoritas em ordem alfabética. Lança exceção em caso de erro.
  Future<List<PlaceModel>> fetchFavoriteInstitutions() async {
    final body = await _getList('${ApiConfig.favorites}/institutions');
    final items = body
        .map((e) => PlaceModel.fromBackend(e as Map<String, dynamic>))
        .toList();
    _institutionIds
      ..clear()
      ..addAll(items.map((p) => p.osmId).whereType<String>());
    notifyListeners();
    return items;
  }

  Future<List<dynamic>> _getList(String url) async {
    final response = await http
        .get(Uri.parse(url), headers: await _authHeaders())
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    return json.decode(utf8.decode(response.bodyBytes)) as List<dynamic>;
  }
}
