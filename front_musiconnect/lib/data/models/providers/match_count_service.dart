import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/config/api_config.dart';
import 'auth_service.dart';

/// Número de Matches do Perfil: quantas oportunidades abertas são
/// compatíveis com o perfil do usuário logado (match >= 85%, o mesmo
/// corte da aba "Minhas oportunidades") — ver
/// GET /api/opportunities/matches/count no backend.
///
/// Instância única ([MatchCountService.instance]): o [MainNavigation] e o
/// Perfil pedem [refresh] (ao abrir o app, ao tocar na aba Perfil e depois
/// de editar o perfil) e o card de estatísticas escuta as mudanças.
class MatchCountService extends ChangeNotifier {
  MatchCountService._();
  static final MatchCountService instance = MatchCountService._();

  static const Duration _timeout = Duration(seconds: 15);

  final _authService = AuthService();

  /// null = ainda não carregou ou a última consulta falhou (o Perfil
  /// mostra "–", nunca um número inventado).
  int? _count;
  int? get count => _count;

  /// [clear]: zera antes de consultar (mostra "–") — usado ao entrar no
  /// app, pra nunca mostrar o número de quem estava logado antes neste
  /// aparelho. Nas demais atualizações o número antigo fica até o novo
  /// chegar, sem piscar.
  Future<void> refresh({bool clear = false}) async {
    if (clear) {
      _count = null;
      notifyListeners();
    }
    try {
      final token = await _authService.getStoredToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.opportunities}matches/count'),
        headers: {if (token != null) 'Authorization': 'Bearer $token'},
      ).timeout(_timeout);
      if (response.statusCode == 200) {
        final body = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        _count = body['count'] as int?;
        notifyListeners();
        return;
      }
      print('[MatchCountService] Erro HTTP ${response.statusCode}');
    } catch (e) {
      print('[MatchCountService] Exceção: $e');
    }
    _count = null;
    notifyListeners();
  }
}
