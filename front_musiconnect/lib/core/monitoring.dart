import 'dart:ui';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
/// - A pessoa pode desligar o envio no Perfil ("Enviar dados de uso e
///   erros"); a escolha fica salva no aparelho e vale desde a abertura.
/// - Sem ID de publicidade (desligado no AndroidManifest.xml).
class Monitoring {
  Monitoring._();

  static const _prefsKey = 'usage_data_enabled';

  static bool _enabled = false;
  static FirebaseAnalytics? _analytics;

  /// Escolha da pessoa no Perfil (padrão: ligado).
  static final ValueNotifier<bool> usageDataEnabled = ValueNotifier(true);

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      usageDataEnabled.value = prefs.getBool(_prefsKey) ?? true;
    } catch (_) {
      // Sem acesso às preferências: segue com o padrão (ligado).
    }

    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[Monitoring] Firebase não iniciado — seguindo sem monitoramento: $e');
      return;
    }
    _enabled = true;
    _analytics = FirebaseAnalytics.instance;
    await _applyCollection();

    final crashlytics = FirebaseCrashlytics.instance;
    // Erros do Flutter (telas) e erros assíncronos fora do Flutter.
    FlutterError.onError = crashlytics.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      crashlytics.recordError(error, stack, fatal: true);
      return true;
    };
  }

  /// Liga/desliga o envio de dados de uso (Analytics) e de erros
  /// (Crashlytics) e guarda a escolha no aparelho.
  static Future<void> setUsageDataEnabled(bool value) async {
    usageDataEnabled.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (_) {
      // Não conseguiu salvar: vale só até fechar o app.
    }
    if (_enabled) await _applyCollection();
  }

  static Future<void> _applyCollection() async {
    final on = usageDataEnabled.value;
    await _analytics?.setAnalyticsCollectionEnabled(on);
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(on && !kDebugMode);
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
