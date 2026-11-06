import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/config/api_config.dart';

/// Versão para a qual o app precisa ser atualizado.
class AppUpdate {
  final String version;
  final String downloadUrl;

  const AppUpdate(this.version, this.downloadUrl);
}

/// Compara versões "1.2.10" × "1.2.9" número a número. Negativo se [a] é
/// mais antiga, zero se iguais, positivo se mais nova.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < pa.length || i < pb.length; i++) {
    final diff = (i < pa.length ? pa[i] : 0) - (i < pb.length ? pb[i] : 0);
    if (diff != 0) return diff;
  }
  return 0;
}

/// Versão nova do app (GET /api/app/version): o servidor diz a mais
/// recente publicada e a mínima aceita. O app instalado pelo site não se
/// atualiza sozinho — sem este aviso, a pessoa não fica sabendo.
///
/// Toda versão nova é obrigatória (decisão da Laura, 06/11/2026): assim
/// ninguém testa uma versão com erro já corrigido. A mínima só conta se
/// o GitHub não responder (sem a mais recente).
class AppUpdateService {
  AppUpdateService({Future<String> Function()? installedVersion})
      : _installedVersion = installedVersion ?? _fromPlatform;

  static const Duration _timeout = Duration(seconds: 10);

  final Future<String> Function() _installedVersion;

  static Future<String> _fromPlatform() async => (await PackageInfo.fromPlatform()).version;

  /// A versão para a qual atualizar, ou `null` para seguir normalmente
  /// (já atualizado, sem internet ou servidor fora do ar).
  Future<AppUpdate?> check() async {
    try {
      final response = await http.get(Uri.parse(ApiConfig.appVersion)).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final body = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final target = body['latest'] as String? ?? body['minimum'] as String?;
      final installed = await _installedVersion();

      if (target == null || compareVersions(installed, target) >= 0) return null;
      return AppUpdate(target, body['download_url'] as String);
    } catch (e) {
      debugPrint('[Versão] Não deu para consultar: $e');
      return null;
    }
  }
}
