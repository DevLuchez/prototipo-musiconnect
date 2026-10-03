import 'dart:convert';
import 'package:http/http.dart' as http;
import '../opportunity_model.dart';
import '../../../core/config/api_config.dart';
import 'auth_service.dart';

/// Resumo da aba Início — ver GET /api/dashboard no backend.
class DashboardData {
  /// Oportunidades abertas com match alto (= "Minhas oportunidades").
  final int matchCount;

  /// Salvas com prazo nos próximos [kUrgentDeadlineDays] dias, mais
  /// urgente primeiro.
  final List<OpportunityModel> urgentSaved;

  /// Maior match primeiro (só as de match alto).
  final List<OpportunityModel> topMatches;

  /// Compatíveis que entraram no app nos últimos 7 dias.
  final List<OpportunityModel> newMatches;

  /// Quantas abertas há de cada tipo ("audicao" → 48) — bloco "Explorar".
  final Map<String, int> typeCounts;

  const DashboardData({
    required this.matchCount,
    required this.urgentSaved,
    required this.topMatches,
    required this.newMatches,
    this.typeCounts = const {},
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) {
    List<OpportunityModel> opportunities(String key) =>
        (json[key] as List<dynamic>? ?? [])
            .map((e) => OpportunityModel.fromJson(e as Map<String, dynamic>))
            .toList();
    return DashboardData(
      matchCount: json['match_count'] as int? ?? 0,
      urgentSaved: opportunities('urgent_saved'),
      topMatches: opportunities('top_matches'),
      newMatches: opportunities('new_matches'),
      typeCounts: (json['type_counts'] as Map<String, dynamic>? ?? {})
          .map((type, count) => MapEntry(type, count as int)),
    );
  }
}

class DashboardService {
  static const Duration _timeout = Duration(seconds: 20);

  final _authService = AuthService();

  /// Lança exceção em caso de erro — a tela mostra o estado de erro.
  Future<DashboardData> fetch() async {
    final token = await _authService.getStoredToken();
    final response = await http.get(
      Uri.parse(ApiConfig.dashboard),
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
    ).timeout(_timeout);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }
    return DashboardData.fromJson(
      json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }
}
