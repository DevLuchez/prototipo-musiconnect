import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/app_update_service.dart';
import 'auth/auth_common.dart';

/// Aviso de versão nova: o app só segue depois de atualizar — o aviso não
/// fecha, nem pelo voltar. "Atualizar" abre o download no navegador; a
/// pessoa instala por cima e continua conectada.
Future<void> showAppUpdatePrompt(BuildContext context, AppUpdate update) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AuthDialog.message(
        title: 'Atualize o MusiConnect',
        message: 'A versão ${update.version} já está disponível, com melhorias e '
            'correções. Baixe e instale por cima para continuar usando — '
            'você continua conectado e não perde nada.',
        primaryLabel: 'Atualizar',
        onPrimary: () => launchUrl(
          Uri.parse(update.downloadUrl),
          mode: LaunchMode.externalApplication,
        ).catchError((_) => false),
      ),
    ),
  );
}
