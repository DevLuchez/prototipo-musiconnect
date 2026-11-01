import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/api_config.dart';
import 'auth_service.dart';

/// Endpoints de notificação do backend (/api/notifications/*): o aparelho
/// que recebe e as chaves do Perfil.
class NotificationsService {
  static const Duration _timeout = Duration(seconds: 15);

  final _authService = AuthService();

  Future<Map<String, String>> _headers() async {
    final token = await _authService.getStoredToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Registra o identificador do aparelho no Firebase (sem sessão, nada).
  Future<void> registerDevice(String token) async {
    if (await _authService.getStoredToken() == null) return;
    final response = await http
        .put(Uri.parse(ApiConfig.notificationsDevice),
            headers: await _headers(), body: json.encode({'token': token}))
        .timeout(_timeout);
    if (response.statusCode >= 400) {
      throw http.ClientException('HTTP ${response.statusCode}', Uri.parse(ApiConfig.notificationsDevice));
    }
  }

  /// Liga/desliga cada tipo de notificação; devolve o usuário atualizado.
  Future<AuthUser> updatePreferences({
    required bool newMatches,
    required bool deadlines,
  }) async {
    try {
      final response = await http
          .put(
            Uri.parse(ApiConfig.notificationsPreferences),
            headers: await _headers(),
            body: json.encode({'notify_new_matches': newMatches, 'notify_deadlines': deadlines}),
          )
          .timeout(_timeout);
      if (response.statusCode >= 400) {
        throw const AuthException('Não foi possível salvar. Tente de novo.');
      }
      return AuthUser.fromJson(
          json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>);
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException(
          'Não foi possível conectar ao servidor. Verifique sua conexão.');
    }
  }
}
