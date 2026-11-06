import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/data/services/app_update_service.dart';
import 'package:prototipo_musiconnect/presentation/widgets/app_update_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/api.dart';

const _url = 'https://exemplo/musiconnect.apk';

FakeApi server({String? latest, String? minimum}) => FakeApi((_) => jsonResponse(
    {'latest': latest, 'minimum': minimum, 'download_url': _url}));

AppUpdateService installed(String version) =>
    AppUpdateService(installedVersion: () async => version);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('compara versões número a número', () {
    expect(compareVersions('1.2.10', '1.2.9'), greaterThan(0));
    expect(compareVersions('1.2.2', '1.3.0'), lessThan(0));
    expect(compareVersions('1.2', '1.2.0'), 0);
  });

  group('consulta ao abrir', () {
    test('versão nova sugere atualizar', () async {
      final update = await server(latest: '1.3.0').run(() => installed('1.2.2').check());

      expect(update?.need, UpdateNeed.optional);
      expect(update?.version, '1.3.0');
      expect(update?.downloadUrl, _url);
    });

    test('já na mais recente não mostra nada', () async {
      expect(await server(latest: '1.2.2').run(() => installed('1.2.2').check()), isNull);
    });

    test('abaixo da mínima exige atualizar', () async {
      final update = await server(latest: '1.3.0', minimum: '1.3.0')
          .run(() => installed('1.2.2').check());

      expect(update?.need, UpdateNeed.required);
    });

    test('"Agora não" não pergunta de novo pela mesma versão, só pela próxima', () async {
      final service = installed('1.2.2');
      await service.dismiss('1.3.0');

      expect(await server(latest: '1.3.0').run(service.check), isNull);
      expect((await server(latest: '1.4.0').run(service.check))?.need, UpdateNeed.optional);
    });

    test('"Agora não" não vale para a atualização obrigatória', () async {
      final service = installed('1.2.2');
      await service.dismiss('1.3.0');

      final update = await server(latest: '1.3.0', minimum: '1.3.0').run(service.check);

      expect(update?.need, UpdateNeed.required);
    });

    test('sem internet ou sem versão conhecida não mostra nada', () async {
      expect(await FakeApi(offline).run(() => installed('1.2.2').check()), isNull);
      expect(await server().run(() => installed('1.2.2').check()), isNull);
    });
  });

  group('aviso', () {
    Future<void> pumpPrompt(WidgetTester tester, AppUpdate update, AppUpdateService service) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showAppUpdatePrompt(context, update, service),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('opcional: "Agora não" fecha e guarda a versão', (tester) async {
      const update = AppUpdate(UpdateNeed.optional, '1.3.0', _url);
      await pumpPrompt(tester, update, installed('1.2.2'));

      expect(find.text('Nova versão do MusiConnect'), findsOneWidget);
      await tester.tap(find.text('Agora não'));
      await tester.pumpAndSettle();

      expect(find.text('Nova versão do MusiConnect'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppUpdateService.dismissedKey), '1.3.0');
    });

    testWidgets('obrigatório: só "Atualizar" e não fecha pelo voltar', (tester) async {
      const update = AppUpdate(UpdateNeed.required, '1.3.0', _url);
      await pumpPrompt(tester, update, installed('1.2.2'));

      expect(find.text('Atualize o MusiConnect'), findsOneWidget);
      expect(find.text('Agora não'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Atualize o MusiConnect'), findsOneWidget);
    });
  });
}
