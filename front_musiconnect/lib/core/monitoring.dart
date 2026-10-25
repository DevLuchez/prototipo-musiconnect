import 'dart:ui';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Monitoramento do app: Firebase Crashlytics (travamentos e erros) e
/// Firebase Analytics (uso). Ponto único — as telas só chamam
/// [Monitoring.logEvent]/[Monitoring.logScreen].
///
/// Regras:
/// - Se o Firebase não iniciar (ex: iOS ainda sem GoogleService-Info.plist,
///   ou testes), o app segue normalmente, só sem monitoramento.
/// - Nada que identifique a pessoa é enviado (sem nome, e-mail ou texto
///   digitado) — ver a Política de privacidade.
/// - Em modo debug (flutter run) os travamentos não vão para o Crashlytics,
///   para não misturar erros de desenvolvimento com os de quem usa o app.
class Monitoring {
  Monitoring._();

  static bool _enabled = false;
  static FirebaseAnalytics? _analytics;

  static Future<void> init() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[Monitoring] Firebase não iniciado — seguindo sem monitoramento: $e');
      return;
    }
    _enabled = true;
    _analytics = FirebaseAnalytics.instance;

    final crashlytics = FirebaseCrashlytics.instance;
    await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
    // Erros do Flutter (telas) e erros assíncronos fora do Flutter.
    FlutterError.onError = crashlytics.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      crashlytics.recordError(error, stack, fatal: true);
      return true;
    };
  }

  /// Evento de uso (ex: 'save_opportunity'). Parâmetros só com valores
  /// não pessoais (tipo, aba, contagem…).
  static void logEvent(String name, [Map<String, Object>? parameters]) {
    if (!_enabled) return;
    _analytics?.logEvent(name: name, parameters: parameters);
  }

  /// Tela visitada — as abas não são rotas, então são registradas à mão.
  static void logScreen(String screenName) {
    if (!_enabled) return;
    _analytics?.logScreenView(screenName: screenName);
  }

  /// Erro tratado que vale acompanhar (ex: falha ao falar com o backend).
  static void recordError(Object error, StackTrace? stack, {String? reason}) {
    if (!_enabled) return;
    FirebaseCrashlytics.instance.recordError(error, stack, reason: reason);
  }
}
