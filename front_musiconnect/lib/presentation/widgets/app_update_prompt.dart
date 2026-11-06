import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/app_update_service.dart';
import 'auth/auth_common.dart';

/// Aviso de versão nova ao abrir o app. "Atualizar" abre o download no
/// navegador; a pessoa instala por cima e continua conectada.
///
/// Opcional: "Agora não" fecha e não pergunta de novo por esta versão.
/// Obrigatório (abaixo da versão mínima): não fecha — nem pelo voltar.
Future<void> showAppUpdatePrompt(
  BuildContext context,
  AppUpdate update,
  AppUpdateService service,
) {
  final required = update.need == UpdateNeed.required;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: !required,
      child: AuthDialog.message(
        title: required ? 'Atualize o MusiConnect' : 'Nova versão do MusiConnect',
        message: required
            ? 'Esta versão do app não funciona mais. Baixe a versão '
                '${update.version} e instale por cima para continuar usando '
                '— você continua conectado e não perde nada.'
            : 'A versão ${update.version} já está disponível, com melhorias e '
                'correções. Baixe e instale por cima — você continua '
                'conectado e não perde nada.',
        primaryLabel: 'Atualizar',
        onPrimary: () {
          if (!required) Navigator.of(dialogContext).pop();
          launchUrl(Uri.parse(update.downloadUrl), mode: LaunchMode.externalApplication)
              .catchError((_) => false);
        },
        secondaryLabel: required ? null : 'Agora não',
        onSecondary: required
            ? null
            : () {
                Navigator.of(dialogContext).pop();
                service.dismiss(update.version);
              },
      ),
    ),
  );
}
