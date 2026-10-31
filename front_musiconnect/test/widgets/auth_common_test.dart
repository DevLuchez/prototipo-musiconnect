import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/presentation/widgets/auth/auth_common.dart';

Future<void> pumpField(WidgetTester tester, Widget Function(StateSetter setState) build) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: StatefulBuilder(builder: (context, setState) => build(setState)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('senha: o olho mostra e esconde', (tester) async {
    final controller = TextEditingController(text: 'segredo');
    await pumpField(tester, (_) => AuthTextField(
        label: 'Senha', hint: 'Digite', controller: controller, isPassword: true));

    bool obscured() => tester.widget<TextField>(find.byType(TextField)).obscureText;
    expect(obscured(), isTrue);
    await tester.tap(find.byType(IconButton));
    await tester.pump();
    expect(obscured(), isFalse);
  });

  testWidgets('várias opções: remover pelo chip e abrir/fechar pela seta', (tester) async {
    var selected = ['Piano', 'Flauta'];
    await pumpField(tester, (setState) => AuthMultiSelectField(
          label: 'Instrumentos',
          hint: 'Selecione...',
          options: const ['Piano', 'Flauta', 'Harpa'],
          selected: selected,
          onChanged: (v) => setState(() => selected = v),
        ));

    expect(find.text('Instrumentos'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();
    expect(selected, ['Flauta']);

    final arrow = find.descendant(
        of: find.byType(TextField), matching: find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.tap(arrow);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Harpa'), findsOneWidget);
    await tester.tap(arrow);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Harpa'), findsNothing);
  });

  testWidgets('uma opção: o X limpa a escolha', (tester) async {
    String? selected = 'Brasil';
    await pumpField(tester, (setState) => AuthSingleSelectField<String>(
          label: 'País',
          hint: 'Selecione o país',
          options: const ['Brasil', 'Chile'],
          selected: selected,
          displayString: (o) => o,
          onChanged: (v) => setState(() => selected = v),
        ));

    expect(find.widgetWithText(TextField, 'Brasil'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(selected, isNull);
    expect(find.widgetWithText(TextField, 'Selecione o país'), findsOneWidget);
  });

  testWidgets('caixa de seleção também responde ao toque na própria caixa', (tester) async {
    var value = false;
    await pumpField(tester, (setState) => CheckRow(
        label: 'Estudante', value: value, onChanged: (v) => setState(() => value = v)));

    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    expect(value, isTrue);
  });
}
