import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/data/models/opportunity_model.dart';
import 'package:prototipo_musiconnect/data/services/auth_service.dart';
import 'package:prototipo_musiconnect/presentation/screens/opportunity_detail_screen.dart';

import '../helpers/api.dart';
import '../helpers/fakes.dart';
import '../helpers/screen.dart';

final _full = OpportunityModel(
  id: 5,
  title: 'Audição para a Orquestra Jovem',
  type: 'audicao',
  sourceUrl: 'https://orquestra.org/audicao',
  sourceName: 'Musical Chairs',
  description: 'Vagas para cordas.',
  rawText: 'Edital completo. ' * 40,
  institution: 'Orquestra Jovem',
  institutionId: 'node_1',
  instruments: ['violin', 'french horn', 'Violin', 'soprano sax'],
  city: 'Joinville',
  state: 'SC',
  country: 'Brasil',
  llmConfidence: 0.8,
  deadline: DateTime.now().add(const Duration(days: 3)),
  matchPercentage: 62,
  matchBreakdown: const MatchBreakdown(
    instrument: 45, affinity: 10, location: 0, confidence: 7,
    instrumentMax: 45, affinityMax: 25, locationMax: 20, confidenceMax: 10,
  ),
);

/// Oportunidade remota, quase sem dados e sem cálculo de match.
const _sparse = OpportunityModel(id: 6, title: 'Masterclass online', isRemote: true);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({'session_token': 'tok'}));

  final api = FakeApi((_) => jsonResponse({'opportunities': [], 'institutions': []}));

  /// Abre o detalhe por cima de uma tela inicial (para testar o voltar).
  Future<List<OpportunityModel>> openDetail(WidgetTester tester, OpportunityModel opp,
      {AuthUser? user}) async {
    final openedOnMap = <OpportunityModel>[];
    useTallScreen(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => OpportunityDetailScreen(
                opportunity: opp, user: user ?? fakeUser(), onOpenMap: openedOnMap.add),
          )),
          child: const Text('início'),
        )),
      ),
    ));
    await tester.tap(find.text('início'));
    await tester.pumpAndSettle();
    return openedOnMap;
  }

  group('Sobre o Edital', () {
    testWidgets('mostra os destaques, com instrumentos traduzidos', (tester) async {
      await api.run(() async {
        await openDetail(tester, _full);

        expect(find.text('Audição para a Orquestra Jovem'), findsOneWidget);
        expect(find.text('Vagas para cordas.'), findsOneWidget);
        for (final chip in ['Violino', 'Trompa', 'Soprano Sax']) {
          expect(find.text(chip), findsOneWidget);
        }
        expect(find.text('Audição'), findsOneWidget);
        expect(find.textContaining('Até '), findsOneWidget);
        expect(find.text('Orquestra Jovem'), findsOneWidget);
        expect(find.text('Joinville, SC, Brasil'), findsOneWidget);
      });
    });

    testWidgets('conteúdo completo abre e fecha', (tester) async {
      await api.run(() async {
        await openDetail(tester, _full);

        await tester.tap(find.text('Ver mais'));
        await tester.pumpAndSettle();
        expect(find.text('Ver menos'), findsOneWidget);
        await tester.tap(find.text('Ver menos'));
        await tester.pumpAndSettle();
        expect(find.text('Ver mais'), findsOneWidget);
      });
    });

    testWidgets('"Ver no mapa" fecha o detalhe e foca a oportunidade', (tester) async {
      await api.run(() async {
        final openedOnMap = await openDetail(tester, _full);

        await tester.tap(find.text('Ver no mapa'));
        await tester.pumpAndSettle();

        expect(openedOnMap.single.id, 5);
        expect(find.text('início'), findsOneWidget);
      });
    });

    testWidgets('"Saiba mais" e o link da fonte abrem o edital', (tester) async {
      final opened = mockUrlLauncher();
      await api.run(() async {
        await openDetail(tester, _full);

        await tester.tap(find.text('Saiba mais'));
        await tester.pumpAndSettle();
        await tapLink(tester, 'Musical Chairs');

        expect(opened, ['https://orquestra.org/audicao', 'https://orquestra.org/audicao']);
      });
    });

    testWidgets('link que não abre avisa', (tester) async {
      mockUrlLauncher(canLaunch: false);
      await api.run(() async {
        await openDetail(tester, _full);

        await tester.tap(find.text('Saiba mais'));
        await tester.pumpAndSettle();

        expect(find.text('Não foi possível abrir o link.'), findsOneWidget);
      });
    });

    testWidgets('oportunidade remota com poucos dados', (tester) async {
      await api.run(() async {
        await openDetail(tester, _sparse);

        expect(find.text('Não informado'), findsNWidgets(2)); // instrumentos e prazo
        expect(find.text('Não informada'), findsOneWidget); // instituição
        expect(find.text('Remoto'), findsNWidgets(2)); // localização e modalidade
        expect(find.text('Ver no mapa'), findsNothing);
        expect(find.byIcon(Icons.music_note_rounded), findsWidgets);

        await tapLink(tester, 'Desconhecido'); // sem link: não faz nada
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
        expect(find.text('início'), findsOneWidget);
      });
    });
  });

  group('Matcher', () {
    Future<void> openMatcherTab(WidgetTester tester) async {
      await tester.tap(find.text('Matcher'));
      await tester.pumpAndSettle();
    }

    testWidgets('compara o perfil com o edital', (tester) async {
      await api.run(() async {
        await openDetail(tester, _full,
            user: fakeUser(instruments: ['Violino', 'Piano'], isProfessional: true));
        await openMatcherTab(tester);

        expect(find.text('62%'), findsNWidgets(2)); // anel do topo e total do Matcher
        expect(find.text('45% / 45%'), findsOneWidget);
        expect(find.text('10% / 25%'), findsOneWidget);
        expect(find.text('0% / 20%'), findsOneWidget);
        expect(find.text('7% / 10%'), findsOneWidget);
        expect(find.textContaining('80% de confiança'), findsOneWidget);
        expect(find.text('Violino  •  Piano'), findsOneWidget);
        expect(find.text('Estudante  •  Profissional'), findsOneWidget);
        expect(find.text('Jaraguá do Sul, SC, Brasil'), findsOneWidget);

        await tester.tap(find.text('O que é match?'));
        await tester.pumpAndSettle();
        expect(find.text('Entendi'), findsOneWidget);
      });
    });

    testWidgets('perfil sem ramo nem local', (tester) async {
      await api.run(() async {
        await openDetail(tester, _full,
            user: fakeUser(isStudent: false, country: null, state: null, city: null));
        await openMatcherTab(tester);

        expect(find.text('Não informado'), findsNWidgets(2)); // ramo e local (como lista)
      });
    });

    testWidgets('sem cálculo de match', (tester) async {
      await api.run(() async {
        await openDetail(tester, _sparse);
        await openMatcherTab(tester);

        expect(find.text('Compatibilidade indisponível no momento.'), findsOneWidget);
      });
    });

    testWidgets('anel de match muda de cor pela faixa', (tester) async {
      await api.run(() async {
        for (final pct in [20, 90]) {
          await openDetail(tester, OpportunityModel(id: pct, title: 'x', matchPercentage: pct));
          expect(find.text('$pct%'), findsWidgets);
          await tester.pumpWidget(const SizedBox());
        }
      });
    });
  });
}
