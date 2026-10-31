import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/data/models/opportunity_model.dart';
import 'package:prototipo_musiconnect/data/services/dashboard_service.dart';
import 'package:prototipo_musiconnect/presentation/screens/dashboard_screen.dart';
import 'package:prototipo_musiconnect/presentation/screens/help_screen.dart';
import 'package:prototipo_musiconnect/presentation/screens/opportunity_detail_screen.dart';
import 'package:prototipo_musiconnect/presentation/view_models/dashboard_view_model.dart';

import '../helpers/api.dart';
import '../helpers/fakes.dart';
import '../helpers/screen.dart';

void main() {
  late FakeDashboardService service;
  late FakeFavoritesService favorites;
  late List<int> openedMatcherTabs;

  Future<void> pumpDashboard(WidgetTester tester,
      {String name = 'Laura Heloísa', Listenable? refreshRequest, DashboardViewModel? viewModel}) async {
    final user = fakeUser(name: name);
    useTallScreen(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DashboardScreen(
          user: user,
          onOpenMatcher: openedMatcherTabs.add,
          refreshRequest: refreshRequest,
          viewModel: viewModel ??
              DashboardViewModel(user: user, service: service, favorites: favorites),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  const empty = DashboardData(matchCount: 0, topMatches: [], urgentSaved: [], newMatches: []);

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'session_token': 'tok'});
    favorites = FakeFavoritesService();
    openedMatcherTabs = [];
  });

  testWidgets('mostra saudação, melhor match, Explorar e prazos das salvas', (tester) async {
    service = FakeDashboardService(data: DashboardData(
      matchCount: 1,
      topMatches: [fakeOpportunity(1, title: 'Audição na Filarmônica', matchPercentage: 97)],
      urgentSaved: [fakeOpportunity(2, title: 'Curso de verão', deadline: DateTime.now())],
      newMatches: const [],
      typeCounts: const {'audicao': 3, 'curso': 1},
    ));
    favorites.saved.add(2);

    await pumpDashboard(tester);

    expect(find.textContaining('Laura!'), findsOneWidget);
    expect(find.text('SEU MELHOR MATCH'), findsOneWidget);
    expect(find.text('Audição na Filarmônica'), findsOneWidget);
    expect(find.text('Explorar'), findsOneWidget);
    expect(find.text('Audições'), findsOneWidget);
    expect(find.text('3 abertas'), findsOneWidget);
    expect(find.text('1 aberta'), findsOneWidget);
    expect(find.text('Competições'), findsNothing); // tipo sem nada aberto some
    expect(find.text('Última chance para seus favoritos'), findsOneWidget);
  });

  testWidgets('desmarcar a salva tira ela dos prazos na hora', (tester) async {
    service = FakeDashboardService(data: DashboardData(
      matchCount: 0,
      topMatches: const [],
      urgentSaved: [fakeOpportunity(2)],
      newMatches: const [],
    ));
    favorites.saved.add(2);
    await pumpDashboard(tester);
    expect(find.text('Última chance para seus favoritos'), findsOneWidget);

    favorites.unsave(2);
    await tester.pumpAndSettle();

    expect(find.text('Última chance para seus favoritos'), findsNothing);
    expect(find.text('Nenhuma novidade por aqui ainda.'), findsOneWidget);
  });

  testWidgets('sem novidades, convida a explorar todas as oportunidades', (tester) async {
    service = FakeDashboardService(data: const DashboardData(
      matchCount: 0, topMatches: [], urgentSaved: [], newMatches: [],
    ));
    await pumpDashboard(tester);

    await tester.tap(find.text('Explorar todas as oportunidades'));

    expect(openedMatcherTabs, [1]); // aba "Todas as oportunidades"
  });

  testWidgets('erro mostra aviso e tentar de novo recarrega', (tester) async {
    service = FakeDashboardService();
    service.error = Exception('HTTP 500');
    await pumpDashboard(tester);
    expect(find.text('Não foi possível carregar o Início.'), findsOneWidget);

    service
      ..error = null
      ..data = const DashboardData(matchCount: 0, topMatches: [], urgentSaved: [], newMatches: []);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível carregar o Início.'), findsNothing);
    expect(service.calls, 2);
  });

  testWidgets('atalho das perguntas frequentes abre a Ajuda', (tester) async {
    service = FakeDashboardService(data: const DashboardData(
      matchCount: 0, topMatches: [], urgentSaved: [], newMatches: [],
    ));
    await pumpDashboard(tester);

    await tester.tap(find.text('Dúvidas? Veja as perguntas frequentes'));
    await tester.pumpAndSettle();

    expect(find.byType(HelpScreen), findsOneWidget);
  });

  testWidgets('sem nome, a saudação fica só com o cumprimento', (tester) async {
    service = FakeDashboardService(data: const DashboardData(
      matchCount: 0, topMatches: [], urgentSaved: [], newMatches: [],
    ));
    await pumpDashboard(tester, name: '');

    expect(find.textContaining(RegExp(r'^(Bom dia|Boa tarde|Boa noite)!$')), findsOneWidget);
  });

  testWidgets('melhor match mostra cidade e instituição e abre o detalhe', (tester) async {
    service = FakeDashboardService(data: const DashboardData(
      matchCount: 1,
      topMatches: [OpportunityModel(id: 1, title: 'Vaga de spalla', type: 'emprego',
          city: 'Blumenau', institution: 'Orquestra de Blumenau', matchPercentage: 90)],
      urgentSaved: [],
      newMatches: [],
    ));
    await FakeApi((_) => jsonResponse({})).run(() async {
      await pumpDashboard(tester);

      expect(find.text('Blumenau'), findsOneWidget);
      expect(find.text('Orquestra de Blumenau'), findsOneWidget);

      await tester.tap(find.text('Vaga de spalla'));
      await tester.pumpAndSettle();
      expect(find.byType(OpportunityDetailScreen), findsOneWidget);
    });
  });

  testWidgets('categoria do Explorar abre a lista daquele tipo', (tester) async {
    service = FakeDashboardService(data: const DashboardData(
      matchCount: 0, topMatches: [], urgentSaved: [], newMatches: [],
      typeCounts: {'audicao': 2, 'curso': 1, 'emprego': 4},
    ));
    final api = FakeApi((r) => r.url.path.endsWith('filter-options')
        ? jsonResponse(<String, dynamic>{})
        : jsonResponse([]));
    await api.run(() async {
      await pumpDashboard(tester);

      await tester.tap(find.text('Empregos'));
      await tester.pumpAndSettle();
      expect(api.requests.any((r) => r.url.queryParameters['type'] == 'emprego'), isTrue);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Explorar'), findsOneWidget);
    });
  });

  testWidgets('recarrega a pedido do menu, mesmo trocando o aviso', (tester) async {
    service = FakeDashboardService(data: empty);
    final first = ValueNotifier(0);
    final second = ValueNotifier(0);
    final viewModel = DashboardViewModel(user: fakeUser(), service: service, favorites: favorites);

    await pumpDashboard(tester, refreshRequest: first, viewModel: viewModel);
    first.value++;
    await tester.pumpAndSettle();
    expect(service.calls, 2);

    await pumpDashboard(tester, refreshRequest: second, viewModel: viewModel, name: 'Outra');
    expect(service.calls, 3); // usuário mudou: recarrega
    expect(find.textContaining('Outra!'), findsOneWidget);

    first.value++; // o aviso antigo não vale mais
    await tester.pumpAndSettle();
    expect(service.calls, 3);
    second.value++;
    await tester.pumpAndSettle();
    expect(service.calls, 4);
  });
}
