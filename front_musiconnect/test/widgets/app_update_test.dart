import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototipo_musiconnect/data/services/app_update_service.dart';
import 'package:prototipo_musiconnect/presentation/widgets/app_update_prompt.dart';

import '../helpers/api.dart';

const _url = 'https://exemplo/musiconnect.apk';

FakeApi server({String? latest, String? minimum}) => FakeApi((_) => jsonResponse(
    {'latest': latest, 'minimum': minimum, 'download_url': _url}));

Future<AppUpdate?> check(FakeApi api, {String installed = '1.2.3'}) =>
    api.run(() => AppUpdateService(installedVersion: () async => installed).check());

void main() {
  test('compara versões número a número', () {
    expect(compareVersions('1.2.10', '1.2.9'), greaterThan(0));
    expect(compareVersions('1.2.2', '1.3.0'), lessThan(0));
    expect(compareVersions('1.2', '1.2.0'), 0);
  });

  group('consulta ao abrir', () {
    test('versão nova exige atualizar', () async {
      final update = await check(server(latest: '1.2.4'));

      expect(update?.version, '1.2.4');
      expect(update?.downloadUrl, _url);
    });

    test('já na mais recente segue normalmente', () async {
      expect(await check(server(latest: '1.2.3')), isNull);
    });

    test('sem a mais recente (GitHub fora do ar), vale a mínima', () async {
      expect((await check(server(minimum: '1.2.4')))?.version, '1.2.4');
      expect(await check(server(minimum: '1.2.0')), isNull);
    });

    test('sem internet ou sem versão conhecida segue normalmente', () async {
      expect(await check(FakeApi(offline)), isNull);
      expect(await check(server()), isNull);
    });
  });

  testWidgets('aviso: só "Atualizar" e não fecha pelo voltar nem tocando fora', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showAppUpdatePrompt(context, const AppUpdate('1.2.4', _url)),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Atualize o MusiConnect'), findsOneWidget);
    expect(find.textContaining('1.2.4'), findsOneWidget);
    expect(find.text('Atualizar'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('Atualize o MusiConnect'), findsOneWidget);
  });
}
