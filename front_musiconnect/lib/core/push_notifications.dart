import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/services/notifications_service.dart';
import 'monitoring.dart';

/// Aviso depois do "Agora não" (ou da permissão negada no Android).
const kNotificationsLaterMessage =
    'Você pode ligar as notificações quando quiser no Perfil.';

/// Uma notificação recebida (com o app aberto) ou tocada. [data] diz o que
/// abrir: {"open": "opportunity", "opportunity_id": "12"}, {"open":
/// "matches"} ou {"open": "favorites"} — montado pelo servidor
/// (back_musiconnect/app/services/notifications.py).
class PushMessage {
  final String? title;
  final String? body;
  final Map<String, dynamic> data;

  const PushMessage({this.title, this.body, this.data = const {}});
}

/// O que o app usa do Firebase Cloud Messaging — trocável nos testes.
abstract class PushBackend {
  Future<bool> requestPermission();
  Future<bool> isPermitted();
  Future<String?> getToken();
  Stream<String> get onTokenRefresh;
  Future<void> deleteToken();

  /// Notificação tocada com o app fechado (a que abriu o app).
  Future<PushMessage?> initialTap();

  /// Notificação tocada com o app em segundo plano.
  Stream<PushMessage> get taps;

  /// Notificação que chegou com o app aberto (o Android não mostra).
  Stream<PushMessage> get foreground;
}

class FirebasePushBackend implements PushBackend {
  FirebaseMessaging get _fcm => FirebaseMessaging.instance;

  static PushMessage _from(RemoteMessage m) => PushMessage(
        title: m.notification?.title,
        body: m.notification?.body,
        data: m.data,
      );

  static bool _allowed(NotificationSettings s) =>
      s.authorizationStatus == AuthorizationStatus.authorized ||
      s.authorizationStatus == AuthorizationStatus.provisional;

  @override
  Future<bool> requestPermission() async => _allowed(await _fcm.requestPermission());

  @override
  Future<bool> isPermitted() async => _allowed(await _fcm.getNotificationSettings());

  @override
  Future<String?> getToken() => _fcm.getToken();

  @override
  Stream<String> get onTokenRefresh => _fcm.onTokenRefresh;

  @override
  Future<void> deleteToken() => _fcm.deleteToken();

  @override
  Future<PushMessage?> initialTap() async {
    final message = await _fcm.getInitialMessage();
    return message == null ? null : _from(message);
  }

  @override
  Stream<PushMessage> get taps => FirebaseMessaging.onMessageOpenedApp.map(_from);

  @override
  Stream<PushMessage> get foreground => FirebaseMessaging.onMessage.map(_from);
}

/// Notificações (novas para você + prazos dos favoritos). Ponto único:
/// pedir a permissão, registrar o aparelho no servidor, parar no "Sair" e
/// entregar à navegação as notificações tocadas.
///
/// Sem Firebase (testes, iOS sem configuração) tudo vira no-op e o app
/// segue normalmente — mesma regra do [Monitoring]. Visitante não usa.
class PushNotifications {
  PushNotifications({PushBackend? backend, NotificationsService? service})
      : _backend = backend,
        _service = service ?? NotificationsService();

  static PushNotifications instance = PushNotifications();

  /// O convite "Quer ser avisado...?" já apareceu neste aparelho.
  static const offeredKey = 'notifications_offered';

  PushBackend? _backend;
  final NotificationsService _service;
  StreamSubscription<String>? _refreshSubscription;

  bool get available => _backend != null;

  /// Permissão do Android, atualizada a cada consulta e pedido — o Perfil
  /// escuta para mostrar as chaves certas (ex: logo depois do "Permitir").
  final ValueNotifier<bool> permitted = ValueNotifier(false);

  /// Depois do [Monitoring.init] (que inicia o Firebase).
  void init() {
    if (_backend == null && Monitoring.firebaseReady) _backend = FirebasePushBackend();
  }

  Future<bool> isPermitted() async {
    try {
      permitted.value = await _backend?.isPermitted() ?? false;
    } catch (e) {
      debugPrint('[Push] Não deu para ler a permissão: $e');
      permitted.value = false;
    }
    return permitted.value;
  }

  /// Pede a permissão do Android e, se a pessoa permitir, registra o
  /// aparelho. Devolve se ficou permitido.
  Future<bool> enable() async {
    final backend = _backend;
    if (backend == null) return false;
    try {
      permitted.value = await backend.requestPermission();
    } catch (e) {
      debugPrint('[Push] Falha ao pedir a permissão: $e');
      permitted.value = false;
    }
    if (!permitted.value) return false;
    await register();
    return true;
  }

  /// Registra (de novo) o aparelho no servidor, se a permissão já existe —
  /// chamado a cada abertura com conta: cobre login em outro aparelho,
  /// reinstalação e troca do identificador pelo Firebase.
  Future<void> register() async {
    final backend = _backend;
    if (backend == null || !await isPermitted()) return;
    try {
      final token = await backend.getToken();
      if (token != null) await _service.registerDevice(token);
      _refreshSubscription ??= backend.onTokenRefresh.listen(_service.registerDevice);
    } catch (e) {
      debugPrint('[Push] Falha ao registrar o aparelho: $e');
    }
  }

  /// "Sair"/excluir a conta: o servidor já apaga o aparelho; aqui o
  /// identificador local é descartado (o próximo login gera outro).
  Future<void> unregister() async {
    await _refreshSubscription?.cancel();
    _refreshSubscription = null;
    try {
      await _backend?.deleteToken();
    } catch (e) {
      debugPrint('[Push] Falha ao descartar o identificador: $e');
    }
  }

  Future<PushMessage?> initialTap() async {
    try {
      return await _backend?.initialTap();
    } catch (_) {
      return null;
    }
  }

  Stream<PushMessage> get taps => _backend?.taps ?? const Stream.empty();
  Stream<PushMessage> get foreground => _backend?.foreground ?? const Stream.empty();

  static Future<bool> wasOffered() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(offeredKey) ?? false;
  }

  static Future<void> markOffered() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(offeredKey, true);
  }
}
