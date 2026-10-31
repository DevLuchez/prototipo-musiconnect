import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:prototipo_musiconnect/data/models/place_model.dart';
import 'package:prototipo_musiconnect/presentation/screens/favorites_screens.dart';
import 'package:prototipo_musiconnect/presentation/screens/opportunity_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/api.dart';
import '../helpers/fakes.dart';
import '../helpers/screen.dart';

Map<String, dynamic> _saved(int id, String title, {String? deadline, String? savedAt, String? city}) => {
      'id': id,
      'title': title,
      'type': 'audicao',
      'deadline': deadline,
      'saved_at': savedAt,
      'city': city,
      'instruments': ['Violino'],
    };

Map<String, dynamic> _favorite(String osmId, String name, {String? savedAt, int opportunities = 0}) => {
      ...placeJson(osmId, opportunities: opportunities),
      'name': name,
      'address': 'Rua $name',
      'saved_at': savedAt,
    };

Future<void> pumpScreen(WidgetTester tester, Widget screen) async {
  useTallScreen(tester);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

List<String> titlesOnScreen(WidgetTester tester, List<String> candidates) {
  final positions = {
    for (final t in candidates)
      if (find.text(t).evaluate().isNotEmpty) t: tester.getTopLeft(find.text(t)).dy,
  };
  return positions.keys.toList()..sort((a, b) => positions[a]!.compareTo(positions[b]!));
}

Future<void> chooseSort(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Ordenar'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, label));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'session_token': 'tok'});
    SharedPreferences.setMockInitialValues({});
  });

  group('Oportunidades salvas', () {
    final saved = [
      _saved(1, 'Bolsa em Viena', deadline: '2026-12-20', savedAt: '2026-10-01T00:00:00', city: 'Viena'),
      _saved(2, 'Audição em Berlim', deadline: '2026-11-10', savedAt: '2026-10-20T00:00:00'),
      _saved(3, 'Curso sem prazo', savedAt: '2026-09-01T00:00:00'),
    ];

    FakeApi api() => FakeApi((r) => r.method == 'GET' ? jsonResponse(saved) : http.Response('', 204));
    Widget screen() => SavedOpportunitiesScreen(user: fakeUser(), onOpenMap: (_) {});
    const titles = ['Bolsa em Viena', 'Audição em Berlim', 'Curso sem prazo'];

    testWidgets('lista por prazo mais próximo (sem prazo no fim)', (tester) async {
      await api().run(() async {
        await pumpScreen(tester, screen());

        expect(find.text('3 oportunidades salvas'), findsOneWidget);
        expect(titlesOnScreen(tester, titles), ['Audição em Berlim', 'Bolsa em Viena', 'Curso sem prazo']);
      });
    });

    testWidgets('ordenar e lembrar a escolha', (tester) async {
      await api().run(() async {
        await pumpScreen(tester, screen());

        await chooseSort(tester, 'A–Z');
        expect(titlesOnScreen(tester, titles).first, 'Audição em Berlim');
        await chooseSort(tester, 'Z–A');
        expect(titlesOnScreen(tester, titles).first, 'Curso sem prazo');
        await chooseSort(tester, 'Mais recentes');
        expect(titlesOnScreen(tester, titles).first, 'Audição em Berlim');
        await chooseSort(tester, 'Mais antigas');
        expect(titlesOnScreen(tester, titles).first, 'Curso sem prazo');

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('favorites_sort_opportunities'), 'oldest');
      });
    });

    testWidgets('ordem salva é usada ao abrir', (tester) async {
      SharedPreferences.setMockInitialValues({'favorites_sort_opportunities': 'za'});
      await api().run(() async {
        await pumpScreen(tester, screen());
        expect(find.text('Z–A'), findsOneWidget);
      });
    });

    testWidgets('busca ignora acentos e mostra quando não acha', (tester) async {
      await api().run(() async {
        await pumpScreen(tester, screen());

        await tester.enterText(find.byType(TextField), 'viena');
        await tester.pumpAndSettle();
        expect(find.text('1 resultado'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'tuba');
        await tester.pumpAndSettle();
        expect(find.text('Nenhum resultado para "tuba".'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();
        expect(find.text('3 oportunidades salvas'), findsOneWidget);
      });
    });

    testWidgets('desmarcar o coração tira da lista', (tester) async {
      await api().run(() async {
        await pumpScreen(tester, screen());

        await tester.tap(find.byIcon(Icons.favorite_rounded).first);
        await tester.pumpAndSettle();

        expect(find.text('2 oportunidades salvas'), findsOneWidget);
      });
    });

    testWidgets('tocar abre o detalhe', (tester) async {
      await api().run(() async {
        await pumpScreen(tester, screen());

        await tester.tap(find.text('Bolsa em Viena'));
        await tester.pumpAndSettle();

        expect(find.byType(OpportunityDetailScreen), findsOneWidget);
      });
    });

    testWidgets('lista vazia e erro com nova tentativa', (tester) async {
      await FakeApi((_) => jsonResponse([])).run(() async {
        await pumpScreen(tester, screen());
        expect(find.textContaining('Nenhuma oportunidade salva ainda.'), findsOneWidget);
      });
      await tester.pumpWidget(const SizedBox()); // descarta a tela anterior

      var fail = true;
      await FakeApi((_) => fail ? http.Response('x', 500) : jsonResponse(saved)).run(() async {
        await pumpScreen(tester, screen());
        expect(find.text('Não foi possível carregar seus favoritos.'), findsOneWidget);

        fail = false;
        await tester.tap(find.text('Tentar novamente'));
        await tester.pumpAndSettle();
        expect(find.text('3 oportunidades salvas'), findsOneWidget);
      });
    });
  });

  group('Instituições favoritas', () {
    final favorites = [
      _favorite('node_1', 'Conservatório', savedAt: '2026-10-01T00:00:00', opportunities: 1),
      _favorite('node_2', 'Arena', savedAt: '2026-10-25T00:00:00', opportunities: 3),
    ];

    testWidgets('lista mais recentes primeiro; tocar leva ao mapa', (tester) async {
      final opened = <PlaceModel>[];
      await FakeApi((r) => r.method == 'GET' ? jsonResponse(favorites) : http.Response('', 204))
          .run(() async {
        await pumpScreen(tester, FavoriteInstitutionsScreen(onOpenMap: opened.add));

        expect(find.text('2 instituições favoritas'), findsOneWidget);
        expect(titlesOnScreen(tester, ['Conservatório', 'Arena']), ['Arena', 'Conservatório']);
        expect(find.text('1 oportunidade aberta'), findsOneWidget);
        expect(find.text('3 oportunidades abertas'), findsOneWidget);

        await chooseSort(tester, 'A–Z');
        expect(titlesOnScreen(tester, ['Conservatório', 'Arena']), ['Arena', 'Conservatório']);
        expect(find.text('Prazo mais próximo'), findsNothing); // instituição não tem prazo

        await tester.tap(find.text('Conservatório'));
        expect(opened.single.osmId, 'node_1');
      });
    });

    testWidgets('desmarcar todas mostra o vazio; voltar fecha a tela', (tester) async {
      await FakeApi((r) => r.method == 'GET' ? jsonResponse([favorites.first]) : http.Response('', 204))
          .run(() async {
        await tester.pumpWidget(MaterialApp(
          home: Builder(builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FavoriteInstitutionsScreen(onOpenMap: (_) {}))),
            child: const Text('abrir'),
          )),
        ));
        await tester.tap(find.text('abrir'));
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.favorite_rounded));
        await tester.pumpAndSettle();
        expect(find.text('Nenhuma instituição favorita.'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
        await tester.pumpAndSettle();
        expect(find.text('abrir'), findsOneWidget);
      });
    });

    testWidgets('erro com nova tentativa', (tester) async {
      var fail = true;
      await FakeApi((_) => fail ? http.Response('x', 500) : jsonResponse(favorites)).run(() async {
        await pumpScreen(tester, FavoriteInstitutionsScreen(onOpenMap: (_) {}));
        expect(find.text('Não foi possível carregar seus favoritos.'), findsOneWidget);

        fail = false;
        await tester.tap(find.text('Tentar novamente'));
        await tester.pumpAndSettle();
        expect(find.text('2 instituições favoritas'), findsOneWidget);
      });
    });

    testWidgets('sem favoritas', (tester) async {
      await FakeApi((_) => jsonResponse([])).run(() async {
        await pumpScreen(tester, FavoriteInstitutionsScreen(onOpenMap: (_) {}));
        expect(find.textContaining('Nenhuma instituição favorita ainda.'), findsOneWidget);
      });
    });
  });
}
