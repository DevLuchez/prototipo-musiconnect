import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/data/models/opportunity_model.dart';
import 'package:prototipo_musiconnect/presentation/widgets/opportunity_card.dart';

import '../helpers/api.dart';

DateTime _inDays(int days) => DateTime.now().add(Duration(days: days));

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('prazo', () {
    test('rótulo curto: relativo quando urgente, data quando não', () {
      expect(deadlineShortLabel(null), 'Prazo não informado');
      expect(deadlineShortLabel(_inDays(0)), 'Fecha hoje');
      expect(deadlineShortLabel(_inDays(1)), 'Fecha amanhã');
      expect(deadlineShortLabel(_inDays(4)), 'Fecha em 4 dias');
      expect(deadlineShortLabel(DateTime(2030, 3, 5)), 'Até 05/03/2030');
    });

    test('vencido ou distante não é urgente', () {
      expect(isDeadlineUrgent(_inDays(-1)), isFalse);
      expect(isDeadlineUrgent(_inDays(6)), isTrue);
      expect(isDeadlineUrgent(_inDays(7)), isFalse);
    });

    test('cada tipo tem a sua cor', () {
      final colors = {
        for (final t in ['curso', 'competicao', 'audicao', 'emprego', null]) opportunityTypeColor(t),
      };
      expect(colors.length, 5);
      expect(opportunityTypeColor('Competição'), opportunityTypeColor('competicao'));
    });
  });

  Future<void> pumpCard(WidgetTester tester, Widget card) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: card))));
    await tester.pumpAndSettle();
  }

  testWidgets('card completo: descrição, instrumentos extras e prazo urgente', (tester) async {
    var taps = 0;
    await FakeApi((_) => jsonResponse({})).run(() async {
      await pumpCard(tester, OpportunityCard(
        opportunity: OpportunityModel(
          id: 1,
          title: 'Concurso de piano',
          type: 'competicao',
          description: 'Para jovens pianistas.',
          instruments: const ['Piano', 'Cravo', 'Órgão', 'Celesta'],
          city: 'Curitiba',
          deadline: _inDays(1),
        ),
        matchPercentage: 72,
        showFavorite: false,
        onTap: () => taps++,
      ));

      expect(find.text('Para jovens pianistas.'), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);
      final deadline = tester.widget<Text>(find.textContaining('Até '));
      expect(deadline.style!.color, Colors.red);
      expect(find.text('72% de match'), findsOneWidget);

      await tester.tap(find.text('Concurso de piano'));
      expect(taps, 1);
    });
  });

  testWidgets('card compacto com e sem match', (tester) async {
    await pumpCard(tester, SizedBox(
      width: 220,
      height: 160,
      child: OpportunityCompactCard(
        opportunity: OpportunityModel(id: 2, title: 'Curso de verão', type: 'curso',
            matchPercentage: 91, deadline: _inDays(0)),
        onTap: () {},
      ),
    ));
    expect(find.text('91%'), findsOneWidget);
    expect(find.text('Fecha hoje'), findsOneWidget);

    await pumpCard(tester, SizedBox(
      width: 220,
      height: 160,
      child: OpportunityCompactCard(
        opportunity: const OpportunityModel(id: 3, title: 'Vaga', type: 'emprego'),
        onTap: () {},
      ),
    ));
    expect(find.textContaining('%'), findsNothing);
    expect(find.text('Prazo não informado'), findsOneWidget);
  });
}
