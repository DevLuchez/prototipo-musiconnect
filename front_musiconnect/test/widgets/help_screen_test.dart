import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/core/constants.dart';
import 'package:prototipo_musiconnect/presentation/screens/help_screen.dart';

import '../helpers/screen.dart';

void main() {
  Future<void> pumpHelp(WidgetTester tester) async {
    useTallScreen(tester);
    await tester.pumpWidget(const MaterialApp(home: HelpScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('"Fale conosco" abre o e-mail de suporte', (tester) async {
    final opened = mockUrlLauncher();
    await pumpHelp(tester);

    await tester.tap(find.text('Fale conosco'));
    await tester.pumpAndSettle();

    expect(opened.single, startsWith('mailto:$kSupportEmail'));
    expect(find.textContaining('Endereço copiado'), findsNothing);
  });

  testWidgets('sem app de e-mail, copia o endereço', (tester) async {
    mockUrlLauncher(canLaunch: false);
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
        (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() =>
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await pumpHelp(tester);

    await tester.tap(find.text('Fale conosco'));
    await tester.pumpAndSettle();

    expect(copied, [kSupportEmail]);
    expect(find.textContaining('Endereço copiado'), findsOneWidget);
  });
}
