import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Abridor de links simulado (url_launcher): devolve a lista de links que o
/// app pediu para abrir. Com [canLaunch] falso, nenhum abre.
List<String> mockUrlLauncher({bool canLaunch = true}) {
  final opened = <String>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/url_launcher'),
    (call) async {
      final url = (call.arguments as Map)['url'] as String;
      if (call.method == 'canLaunch') return canLaunch;
      opened.add(url);
      return canLaunch;
    },
  );
  addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/url_launcher'), null));
  return opened;
}

/// Tela de teste alta (como um celular comprido): listas longas constroem
/// todos os itens, sem precisar rolar até cada um. Volta ao tamanho padrão
/// no fim do teste.
void useTallScreen(WidgetTester tester, {double height = 2600}) {
  tester.view.physicalSize = Size(1080, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Link dentro de um texto (ex: "Não tem uma conta? Cadastre-se"): aciona
/// o trecho clicável [label].
Future<void> tapLink(WidgetTester tester, String label) async {
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    TapGestureRecognizer? found;
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.text == label && span.recognizer is TapGestureRecognizer) {
        found = span.recognizer as TapGestureRecognizer;
        return false;
      }
      return true;
    });
    if (found != null) {
      found!.onTap!();
      await tester.pumpAndSettle();
      return;
    }
  }
  fail('link "$label" não encontrado');
}
