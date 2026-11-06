import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/api_config.dart';

enum UpdateNeed {
  /// Há versão nova: o app sugere ("Atualizar" ou "Agora não").
  optional,

  /// Esta versão ficou abaixo da mínima: o app só segue depois de atualizar.
  required,
}

class AppUpdate {
  final UpdateNeed need;
  final String version;
  final String downloadUrl;

  const AppUpdate(this.need, this.version, this.downloadUrl);
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
class AppUpdateService {
  AppUpdateService({Future<String> Function()? installedVersion})
      : _installedVersion = installedVersion ?? _fromPlatform;

  static const Duration _timeout = Duration(seconds: 10);

  /// Versão em que a pessoa tocou "Agora não" — não sugere de novo a mesma.
  static const dismissedKey = 'update_dismissed_version';

  final Future<String> Function() _installedVersion;

  static Future<String> _fromPlatform() async => (await PackageInfo.fromPlatform()).version;

  /// O que mostrar ao abrir o app, ou `null` para nada (já atualizado,
  /// versão nova já dispensada, sem internet ou servidor fora do ar).
  Future<AppUpdate?> check() async {
    try {
      final response = await http.get(Uri.parse(ApiConfig.appVersion)).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final body = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final latest = body['latest'] as String?;
      final minimum = body['minimum'] as String?;
      final url = body['download_url'] as String;
      final installed = await _installedVersion();

      if (minimum != null && compareVersions(installed, minimum) < 0) {
        return AppUpdate(UpdateNeed.required, latest ?? minimum, url);
      }
      if (latest == null || compareVersions(installed, latest) >= 0) return null;
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(dismissedKey) == latest) return null;
      return AppUpdate(UpdateNeed.optional, latest, url);
    } catch (e) {
      debugPrint('[Versão] Não deu para consultar: $e');
      return null;
    }
  }

  Future<void> dismiss(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(dismissedKey, version);
  }
}
