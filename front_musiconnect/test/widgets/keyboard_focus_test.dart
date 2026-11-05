import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/core/keyboard_focus.dart';

/// Campo de texto + botão que abre outra tela, com a proteção do app.
Future<FocusNode> pumpField(WidgetTester tester, {FocusNode? focus}) async {
  final node = focus ?? FocusNode();
  addTearDown(node.dispose);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => KeyboardFocusGuard(child: child!),
    home: Builder(
      builder: (context) => Scaffold(
        body: Column(children: [
          TextField(focusNode: node, onTapOutside: unfocusOnTapOutside),
          ElevatedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('Outra tela')),
            )),
            child: const Text('Abrir'),
          ),
        ]),
      ),
    ),
  ));
  return node;
}

Future<void> openKeyboard(WidgetTester tester) async {
  await tester.tap(find.byType(TextField));
  tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  await tester.pump();
}

Future<void> lowerKeyboard(WidgetTester tester) async {
  tester.view.resetViewInsets();
  await tester.pump();
}

Future<void> openAndComeBack(WidgetTester tester) async {
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
  Navigator.of(tester.element(find.text('Outra tela'))).pop();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('abaixar o teclado tira o foco e ele não volta ao voltar à tela', (tester) async {
    final field = await pumpField(tester);
    await openKeyboard(tester);
    expect(field.hasFocus, isTrue);

    await lowerKeyboard(tester);
    expect(field.hasFocus, isFalse);

    await openAndComeBack(tester);
    expect(field.hasFocus, isFalse);
  });

  testWidgets('tocar fora do campo tira o foco antes de trocar de tela', (tester) async {
    final field = await pumpField(tester);
    await openKeyboard(tester);

    await openAndComeBack(tester);

    expect(field.hasFocus, isFalse);
  });

  testWidgets('campo com lista de sugestões continua selecionado ao abaixar o teclado',
      (tester) async {
    final field = await pumpField(tester, focus: KeepsFocusWithoutKeyboard());
    await openKeyboard(tester);

    await lowerKeyboard(tester);

    expect(field.hasFocus, isTrue);
  });
}
