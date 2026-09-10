import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../../../core/config/api_config.dart';

/// Erro de autenticação com a mensagem já pronta pra exibir ao usuário
/// (o backend manda mensagens em português, sem detalhe técnico).
class AuthException implements Exception {
  final String message;
  const AuthException(this.message);

  @override
  String toString() => message;
}

class AuthUser {
  final int id;
  final String email;
  final String name;
  final List<String> instruments;
  final bool isProfessional;
  final bool isStudent;
  final String? country;
  final String? state;
  final String? city;

  const AuthUser({
    required this.id,
    required this.email,
    required this.name,
    required this.instruments,
    required this.isProfessional,
    required this.isStudent,
    this.country,
    this.state,
    this.city,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as int,
        email: json['email'] as String,
        name: json['name'] as String,
        instruments: (json['instruments'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(),
        isProfessional: json['is_professional'] as bool? ?? false,
        isStudent: json['is_student'] as bool? ?? false,
        country: json['country'] as String?,
        state: json['state'] as String?,
        city: json['city'] as String?,
      );
}

/// Cadastro, login, sessão persistida e perfil — fala com os endpoints
/// reais do backend (/api/auth/*).
///
/// O token de sessão fica guardado em armazenamento criptografado do
/// dispositivo (`flutter_secure_storage`) — sobrevive fechar/abrir o app,
/// mas nunca em texto puro (diferente de SharedPreferences).
class AuthService {
  static const Duration _timeout = Duration(seconds: 15);
  static const _tokenKey = 'session_token';

  final _storage = const FlutterSecureStorage();

  /// Extrai a mensagem de erro do corpo da resposta (`{"detail": "..."}`,
  /// padrão do FastAPI/HTTPException), com um fallback genérico.
  String _errorDetail(http.Response response, String fallback) {
    try {
      final body = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return body['detail'] as String? ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<String?> getStoredToken() => _storage.read(key: _tokenKey);

  Future<void> _saveToken(String token) => _storage.write(key: _tokenKey, value: token);

  Future<void> _clearToken() => _storage.delete(key: _tokenKey);

  Future<Map<String, String>> _authHeaders() async {
    final token = await getStoredToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> signup({
    required String email,
    required String password,
    required String name,
    required List<String> instruments,
    required bool isProfessional,
    required bool isStudent,
    String? country,
    String? state,
    String? city,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(ApiConfig.authSignup),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'email': email,
              'password': password,
              'name': name,
              'instruments': instruments,
              'is_professional': isProfessional,
              'is_student': isStudent,
              'country': country,
              'state': state,
              'city': city,
            }),
          )
          .timeout(_timeout);
      if (response.statusCode >= 400) {
        throw AuthException(_errorDetail(response, 'Não foi possível criar o cadastro.'));
      }
    } on AuthException {
      rethrow;
    } catch (e) {
      throw const AuthException(
          'Não foi possível conectar ao servidor. Verifique sua conexão.');
    }
  }

  Future<void> resend(String email) async {
    try {
      final response = await http
          .post(
            Uri.parse(ApiConfig.authResend),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'email': email}),
          )
          .timeout(_timeout);
      if (response.statusCode >= 400) {
        throw AuthException(_errorDetail(response, 'Não foi possível reenviar o e-mail.'));
      }
    } on AuthException {
      rethrow;
    } catch (e) {
      throw const AuthException(
          'Não foi possível conectar ao servidor. Verifique sua conexão.');
    }
  }

  /// Retorna true se o token confirmou com sucesso (ou já estava
  /// confirmado antes — idempotente).
  Future<bool> confirm(String token) async {
    try {
      final response = await http
          .post(
            Uri.parse(ApiConfig.authConfirm),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'token': token}),
          )
          .timeout(_timeout);
      return response.statusCode < 400;
    } catch (e) {
      return false;
    }
  }

  Future<bool> isConfirmed(String email) async {
    try {
      final uri = Uri.parse(ApiConfig.authStatus).replace(queryParameters: {'email': email});
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode >= 400) return false;
      final body = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return body['confirmed'] as bool? ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Autentica e guarda o token de sessão localmente — próxima vez que o
  /// app abrir, [getCurrentUser] já entra logado sem pedir e-mail/senha
  /// de novo.
  Future<AuthUser> login({required String email, required String password}) async {
    try {
      final response = await http
          .post(
            Uri.parse(ApiConfig.authLogin),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'email': email, 'password': password}),
          )
          .timeout(_timeout);
      if (response.statusCode >= 400) {
        throw AuthException(_errorDetail(response, 'E-mail ou senha inválidos.'));
      }
      final body = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final token = body['token'] as String?;
      if (token != null) await _saveToken(token);
      return AuthUser.fromJson(body);
    } on AuthException {
      rethrow;
    } catch (e) {
      throw const AuthException(
          'Não foi possível conectar ao servidor. Verifique sua conexão.');
    }
  }

  /// Sempre "funciona" do ponto de vista da UI — o backend responde
  /// genérico mesmo se o e-mail não existir (evita revelar quais e-mails
  /// têm conta cadastrada).
  Future<void> forgotPassword(String email) async {
    try {
      final response = await http
          .post(
            Uri.parse(ApiConfig.authForgotPassword),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'email': email}),
          )
          .timeout(_timeout);
      if (response.statusCode >= 400) {
        throw AuthException(
            _errorDetail(response, 'Não foi possível enviar o e-mail de redefinição.'));
      }
    } on AuthException {
      rethrow;
    } catch (e) {
      throw const AuthException(
          'Não foi possível conectar ao servidor. Verifique sua conexão.');
    }
  }

  Future<void> resetPassword({required String token, required String newPassword}) async {
    try {
      final response = await http
          .post(
            Uri.parse(ApiConfig.authResetPassword),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'token': token, 'password': newPassword}),
          )
          .timeout(_timeout);
      if (response.statusCode >= 400) {
        throw AuthException(_errorDetail(response, 'Não foi possível redefinir a senha.'));
      }
    } on AuthException {
      rethrow;
    } catch (e) {
      throw const AuthException(
          'Não foi possível conectar ao servidor. Verifique sua conexão.');
    }
  }

  /// Valida o token guardado localmente e devolve o usuário logado — ou
  /// `null` se não há sessão (ainda não logou, ou o token não é mais
  /// válido em nenhum dispositivo). Usado na abertura do app.
  Future<AuthUser?> getCurrentUser() async {
    final token = await getStoredToken();
    if (token == null) return null;
    try {
      final response =
          await http.get(Uri.parse(ApiConfig.authMe), headers: await _authHeaders()).timeout(
                _timeout,
              );
      if (response.statusCode >= 400) {
        await _clearToken();
        return null;
      }
      final body = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return AuthUser.fromJson(body);
    } catch (e) {
      // Falha de rede não deve deslogar o usuário — tenta de novo na
      // próxima abertura do app, mantendo o token salvo.
      return null;
    }
  }

  Future<AuthUser> updateProfile({
    required String name,
    required List<String> instruments,
    required bool isProfessional,
    required bool isStudent,
    String? country,
    String? state,
    String? city,
  }) async {
    try {
      final response = await http
          .patch(
            Uri.parse(ApiConfig.authMe),
            headers: await _authHeaders(),
            body: json.encode({
              'name': name,
              'instruments': instruments,
              'is_professional': isProfessional,
              'is_student': isStudent,
              'country': country,
              'state': state,
              'city': city,
            }),
          )
          .timeout(_timeout);
      if (response.statusCode >= 400) {
        throw AuthException(_errorDetail(response, 'Não foi possível salvar o perfil.'));
      }
      final body = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return AuthUser.fromJson(body);
    } on AuthException {
      rethrow;
    } catch (e) {
      throw const AuthException(
          'Não foi possível conectar ao servidor. Verifique sua conexão.');
    }
  }

  /// Troca de senha estando logado (pede a senha atual) — diferente de
  /// [resetPassword], que é o fluxo de "esqueci minha senha".
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(ApiConfig.authChangePassword),
            headers: await _authHeaders(),
            body: json.encode({
              'current_password': currentPassword,
              'new_password': newPassword,
            }),
          )
          .timeout(_timeout);
      if (response.statusCode >= 400) {
        throw AuthException(_errorDetail(response, 'Não foi possível trocar a senha.'));
      }
      final body = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final token = body['token'] as String?;
      if (token != null) await _saveToken(token);
    } on AuthException {
      rethrow;
    } catch (e) {
      throw const AuthException(
          'Não foi possível conectar ao servidor. Verifique sua conexão.');
    }
  }

  /// Invalida a sessão no servidor e apaga o token guardado localmente.
  Future<void> logout() async {
    try {
      await http
          .post(Uri.parse(ApiConfig.authLogout), headers: await _authHeaders())
          .timeout(_timeout);
    } catch (e) {
      // Mesmo se a chamada falhar (sem internet, etc.), ainda assim
      // desloga localmente — não vale travar o usuário no app.
    }
    await _clearToken();
  }

  /// Exclui a conta permanentemente (pede confirmação de senha) e apaga
  /// o token guardado localmente.
  Future<void> deleteAccount(String password) async {
    try {
      final response = await http
          .delete(
            Uri.parse(ApiConfig.authMe),
            headers: await _authHeaders(),
            body: json.encode({'password': password}),
          )
          .timeout(_timeout);
      if (response.statusCode >= 400) {
        throw AuthException(_errorDetail(response, 'Não foi possível excluir a conta.'));
      }
      await _clearToken();
    } on AuthException {
      rethrow;
    } catch (e) {
      throw const AuthException(
          'Não foi possível conectar ao servidor. Verifique sua conexão.');
    }
  }
}
