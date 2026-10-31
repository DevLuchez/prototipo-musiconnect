import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:prototipo_musiconnect/core/constants.dart';
import 'package:prototipo_musiconnect/data/services/auth_service.dart';
import 'package:prototipo_musiconnect/data/services/dashboard_service.dart';
import 'package:prototipo_musiconnect/data/services/favorites_service.dart';
import 'package:prototipo_musiconnect/data/services/geo_service.dart';
import 'package:prototipo_musiconnect/data/services/match_count_service.dart';
import 'package:prototipo_musiconnect/data/services/musicconnect_api_service.dart';
import 'package:prototipo_musiconnect/data/services/opportunities_service.dart';

import '../helpers/api.dart';

const _offlineMessage = 'Não foi possível conectar ao servidor. Verifique sua conexão.';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({'session_token': 'tok'}));

  group('MusicConnectApiService (mapa)', () {
    final service = MusicConnectApiService();

    test('instituições por raio, todas, busca e por id', () async {
      final api = FakeApi((r) {
        if (r.url.path.endsWith('/search')) return jsonResponse([placeJson('n9')]);
        if (r.url.path.endsWith('/node_5')) return jsonResponse(placeJson('node_5'));
        return jsonResponse([placeJson('n1'), {'name': 'sem coordenadas'}]);
      });

      await api.run(() async {
        final nearby = await service.fetchNearby(lat: -26.4, lng: -49.0, radiusM: 1000, limit: 10);
        expect(nearby.single.osmId, 'n1'); // sem coordenadas é descartada
        expect(api.last.url.queryParameters, {'lat': '-26.4', 'lng': '-49.0', 'radius_m': '1000', 'limit': '10'});
        expect((await service.fetchAll(limit: 3)).length, 1);
        expect((await service.search('scar'))!.single.osmId, 'n9');
        expect((await service.fetchById('node_5'))!.osmId, 'node_5');
      });
    });

    test('estatísticas e saúde do servidor', () async {
      final api = FakeApi((r) => r.url.path.endsWith('/stats')
          ? jsonResponse({'total': 82652, 'with_active_opportunities': 80})
          : jsonResponse({'status': 'ok'}));

      await api.run(() async {
        final stats = await service.fetchStats();
        expect((stats!.total, stats.withOpportunities), (82652, 80));
        expect(await service.isReachable(), isTrue);
      });
    });

    test('erro HTTP: listas vazias e nulls (o mapa não quebra)', () async {
      final api = FakeApi((_) => http.Response('erro interno', 500));

      await api.run(() async {
        expect(await service.fetchNearby(lat: 0, lng: 0), isEmpty);
        expect(await service.fetchAll(), isEmpty);
        expect(await service.fetchStats(), isNull);
        expect(await service.search('x'), isNull); // null = o mapa busca localmente
        expect(await service.fetchById('x'), isNull);
        expect(await service.isReachable(), isFalse);
      });
    });

    test('sem rede: mesmos valores seguros', () async {
      await FakeApi(offline).run(() async {
        expect(await service.fetchNearby(lat: 0, lng: 0), isEmpty);
        expect(await service.fetchAll(), isEmpty);
        expect(await service.fetchStats(), isNull);
        expect(await service.search('x'), isNull);
        expect(await service.fetchById('x'), isNull);
        expect(await service.isReachable(), isFalse);
      });
    });
  });

  group('OpportunitiesService', () {
    final service = OpportunitiesService();

    test('busca com filtros, total pelo cabeçalho e sessão', () async {
      final api = FakeApi((_) => jsonResponse(
            [opportunityJson(1), opportunityJson(2)],
            headers: {'x-total-count': '40'},
          ));

      final result = await api.run(() => service.fetchOpportunities(
            q: 'violino', types: ['audicao'], instruments: ['Violino'], countries: ['Brasil'],
            states: ['SC'], cities: ['Joinville'], cityLocationId: 3, limit: 2, offset: 4,
          ));

      expect(result.items.length, 2);
      expect(result.total, 40);
      final params = api.last.url.queryParametersAll;
      expect(params['q'], ['violino']);
      expect(params['type'], ['audicao']);
      expect(params['city_location_id'], ['3']);
      expect(params['offset'], ['4']);
      expect(api.last.headers['Authorization'], 'Bearer tok');
    });

    test('sem o cabeçalho de total, usa o tamanho da página', () async {
      final api = FakeApi((_) => jsonResponse([opportunityJson(1)]));
      expect((await api.run(() => service.fetchOpportunities())).total, 1);
    });

    test('opções de filtro em ordem alfabética', () async {
      final api = FakeApi((_) => jsonResponse({
            'instruments': ['Violino', 'Piano'],
            'countries': ['Brasil', 'Alemanha'],
            'states': [
              {'value': 'SP', 'label': 'SP | São Paulo'},
              {'value': 'SC', 'label': 'SC | Santa Catarina'},
            ],
            'cities': ['Joinville'],
          }));

      final options = await api.run(() => service.fetchFilterOptions(q: ' violino ', instruments: ['Piano']));

      expect(options.instruments, ['Piano', 'Violino']);
      expect(options.countries, ['Alemanha', 'Brasil']);
      expect(options.states.map((s) => s.value), ['SC', 'SP']);
      expect(api.last.url.queryParameters['q'], 'violino');
    });

    test('cidades e oportunidades de um pino', () async {
      final api = FakeApi((r) => r.url.path.endsWith('/cities')
          ? jsonResponse([{'id': 1, 'city': 'Norfolk', 'state': 'VA', 'country': 'Estados Unidos',
              'lat': 1, 'lng': 2, 'opportunities_count': 3}])
          : jsonResponse([opportunityJson(5)]));

      await api.run(() async {
        final city = (await service.fetchCities()).single;
        expect(city.label, 'Norfolk, VA, Estados Unidos');
        expect(city.count, 3);
        expect((await service.fetchByInstitution('way_1')).single.id, 5);
        expect(api.last.url.path, endsWith('/institutions/way_1/opportunities'));
      });
    });

    test('erro HTTP ou sem rede: resultados vazios', () async {
      for (final api in [FakeApi((_) => http.Response('x', 500)), FakeApi(offline)]) {
        await api.run(() async {
          final result = await service.fetchOpportunities();
          expect(result.items, isEmpty);
          expect(result.total, 0);
          expect((await service.fetchFilterOptions()).instruments, isEmpty);
          expect(await service.fetchCities(), isEmpty);
          expect(await service.fetchByInstitution('x'), isEmpty);
        });
      }
    });
  });

  group('DashboardService (Início)', () {
    test('lê o resumo com a sessão', () async {
      final api = FakeApi((_) => jsonResponse({
            'match_count': 2,
            'urgent_saved': [opportunityJson(1)],
            'top_matches': [opportunityJson(2), opportunityJson(3)],
            'new_matches': [],
            'type_counts': {'audicao': 3},
          }));

      final data = await api.run(() => DashboardService().fetch());

      expect(data.matchCount, 2);
      expect(data.topMatches.length, 2);
      expect(data.typeCounts, {'audicao': 3});
      expect(api.last.headers['Authorization'], 'Bearer tok');
    });

    test('erro lança exceção (a tela mostra o estado de erro)', () async {
      final api = FakeApi((_) => http.Response('x', 500));
      await expectLater(api.run(() => DashboardService().fetch()), throwsException);
    });
  });

  group('MatchCountService (número do Perfil)', () {
    test('atualiza o número e avisa quem escuta', () async {
      final service = MatchCountService.instance;
      var notified = 0;
      void listener() => notified++;
      service.addListener(listener);
      addTearDown(() => service.removeListener(listener));

      await FakeApi((_) => jsonResponse({'count': 12})).run(() => service.refresh(clear: true));
      expect(service.count, 12);
      expect(notified, 2); // zerou ("–") e depois chegou o número

      await FakeApi((_) => http.Response('x', 500)).run(() => service.refresh());
      expect(service.count, isNull); // falhou: traço, nunca número inventado

      await FakeApi(offline).run(() => service.refresh());
      expect(service.count, isNull);
    });
  });

  group('FavoritesService', () {
    final service = FavoritesService.instance;

    test('carrega os ids e marca/desmarca com o backend', () async {
      final api = FakeApi((r) {
        if (r.url.path.endsWith('/ids')) {
          return jsonResponse({'opportunities': [1, 2], 'institutions': ['node_1']});
        }
        return http.Response('', 204);
      });

      await api.run(() async {
        await service.load();
        expect(service.opportunityCount, 2);
        expect(service.isInstitutionFavorite('node_1'), isTrue);

        expect(await service.toggleOpportunity(3), isTrue);
        expect(api.last.method, 'PUT');
        expect(service.isOpportunitySaved(3), isTrue);

        expect(await service.toggleOpportunity(3), isTrue);
        expect(api.last.method, 'DELETE');
        expect(service.isOpportunitySaved(3), isFalse);

        expect(await service.toggleInstitution('way/9'), isTrue);
        expect(api.last.url.path, endsWith('/institutions/way%2F9'));
        expect(await service.toggleInstitution('way/9'), isTrue);
      });
    });

    test('backend recusou: o coração volta ao estado anterior', () async {
      await FakeApi((r) => r.url.path.endsWith('/ids')
              ? jsonResponse({'opportunities': [], 'institutions': []})
              : http.Response('', 500))
          .run(() async {
        await service.load();
        expect(await service.toggleOpportunity(8), isFalse);
        expect(service.isOpportunitySaved(8), isFalse);
      });

      await FakeApi(offline).run(() async {
        expect(await service.toggleInstitution('node_9'), isFalse);
        expect(service.isInstitutionFavorite('node_9'), isFalse);
      });
    });

    test('listas de salvas e favoritas sincronizam a contagem', () async {
      final api = FakeApi((r) => r.url.path.endsWith('/opportunities')
          ? jsonResponse([opportunityJson(4)])
          : jsonResponse([placeJson('node_2')]));

      await api.run(() async {
        expect((await service.fetchSavedOpportunities()).single.id, 4);
        expect(service.opportunityCount, 1);
        expect((await service.fetchFavoriteInstitutions()).single.osmId, 'node_2');
        expect(service.institutionCount, 1);
      });
    });

    test('erro ao carregar ids ou listas', () async {
      await FakeApi((_) => http.Response('x', 500)).run(() async {
        await service.load();
        expect(service.opportunityCount, 0);
        await expectLater(service.fetchSavedOpportunities(), throwsException);
      });
      await FakeApi(offline).run(() => service.load());
      expect(service.institutionCount, 0);
    });
  });

  group('GeoService (cadastro)', () {
    final service = GeoService();

    test('países, estados e cidades em cascata', () async {
      final api = FakeApi((r) {
        if (r.url.path.endsWith('/countryInfoJSON')) {
          return jsonResponse({'geonames': [
            {'countryName': 'Brasil', 'countryCode': 'BR'},
            {'countryName': 'Alemanha', 'countryCode': 'DE'},
          ]});
        }
        if (r.url.queryParameters['featureCode'] == 'ADM1') {
          return jsonResponse({'geonames': [
            {'name': 'Santa Catarina', 'adminCode1': '26'},
            {'name': 'Paraná', 'adminCode1': '18'},
          ]});
        }
        return jsonResponse({'geonames': [{'name': 'Joinville'}, {'name': 'Jaraguá do Sul'}]});
      });

      await api.run(() async {
        expect((await service.fetchCountries()).map((c) => c.name), ['Alemanha', 'Brasil']);
        final states = await service.fetchStates('BR');
        expect(states.map((s) => s.adminCode1), ['18', '26']); // por nome
        expect(api.last.url.queryParameters['username'], isNotEmpty);
        // Cidades na ordem do GeoNames (por população)
        expect((await service.fetchCities('BR', '26')).map((c) => c.name), ['Joinville', 'Jaraguá do Sul']);
      });
    });

    test('erro ou sem rede: listas vazias', () async {
      for (final api in [FakeApi((_) => http.Response('x', 500)), FakeApi(offline)]) {
        await api.run(() async {
          expect(await service.fetchCountries(), isEmpty);
          expect(await service.fetchStates('BR'), isEmpty);
          expect(await service.fetchCities('BR', '26'), isEmpty);
        });
      }
    });
  });

  group('AuthService (conta)', () {
    final service = AuthService();

    test('cadastro manda o consentimento com a política', () async {
      final api = FakeApi((_) => jsonResponse({'status': 'pending'}, status: 201));

      await api.run(() => service.signup(
            email: 'a@b.com', password: 'Senha#123', name: 'A', instruments: ['Piano'],
            isProfessional: false, isStudent: true, country: 'Brasil',
          ));

      final body = jsonDecode(api.last.body) as Map<String, dynamic>;
      expect(body['privacy_accepted'], isTrue);
      expect(body['privacy_policy_version'], kPrivacyPolicyVersion);
      expect(body['instruments'], ['Piano']);
    });

    test('login guarda a sessão e o usuário logado é lido dela', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = FakeApi((r) => r.url.path.endsWith('/login')
          ? jsonResponse(userJson(token: 'nova-sessao'))
          : jsonResponse(userJson(privacyVersion: '2026-10-29')));

      await api.run(() async {
        final user = await service.login(email: 'aluna@example.com', password: 'x');
        expect(user.name, 'Aluna');
        expect(await service.getStoredToken(), 'nova-sessao');

        final current = await service.getCurrentUser();
        expect(current!.privacyPolicyVersion, '2026-10-29');
        expect(api.last.headers['Authorization'], 'Bearer nova-sessao');
      });
    });

    test('sem sessão salva, ninguém está logado (nem consulta o backend)', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = FakeApi((_) => jsonResponse(userJson()));
      expect(await api.run(() => service.getCurrentUser()), isNull);
      expect(api.requests, isEmpty);
    });

    test('sessão inválida é apagada; sem rede, a sessão fica', () async {
      await FakeApi(offline).run(() async => expect(await service.getCurrentUser(), isNull));
      expect(await service.getStoredToken(), 'tok');

      await FakeApi((_) => detailError('Sessão inválida.', status: 401))
          .run(() async => expect(await service.getCurrentUser(), isNull));
      expect(await service.getStoredToken(), isNull);
    });

    test('confirmação, status e reenvio', () async {
      final api = FakeApi((r) {
        if (r.url.path.endsWith('/status')) return jsonResponse({'confirmed': true});
        if (r.url.path.endsWith('/confirm')) return jsonResponse({'status': 'confirmed'});
        return jsonResponse({'status': 'sent'});
      });

      await api.run(() async {
        expect(await service.confirm('t'), isTrue);
        expect(await service.isConfirmed('a@b.com'), isTrue);
        await service.resend('a@b.com');
      });
      expect(await FakeApi(offline).run(() => service.confirm('t')), isFalse);
      expect(await FakeApi((_) => http.Response('', 404)).run(() => service.isConfirmed('x')), isFalse);
      expect(await FakeApi(offline).run(() => service.isConfirmed('x')), isFalse);
    });

    test('perfil, troca de senha e novo aceite da política', () async {
      final api = FakeApi((r) {
        if (r.url.path.endsWith('/change-password')) return jsonResponse(userJson(token: 'sessao-2'));
        if (r.url.path.endsWith('/accept-privacy')) return jsonResponse(userJson(privacyVersion: '2026-10-29'));
        return jsonResponse(userJson());
      });

      await api.run(() async {
        final updated = await service.updateProfile(
            name: 'Aluna', instruments: ['Violino'], isProfessional: false, isStudent: true);
        expect(updated.city, 'Jaraguá do Sul');
        expect(api.last.method, 'PATCH');

        await service.changePassword(currentPassword: 'a', newPassword: 'b');
        expect(await service.getStoredToken(), 'sessao-2');

        expect((await service.acceptPrivacyPolicy()).privacyPolicyVersion, '2026-10-29');
        expect(jsonDecode(api.last.body), {'privacy_policy_version': kPrivacyPolicyVersion});
      });
    });

    test('esqueci a senha, redefinir, sair e excluir conta', () async {
      final api = FakeApi((_) => jsonResponse({'status': 'ok'}));

      await api.run(() async {
        await service.forgotPassword('a@b.com');
        await service.resetPassword(token: 't', newPassword: 'Nova#1234');
        await service.deleteAccount('Senha#123');
        expect(await service.getStoredToken(), isNull);
      });

      FlutterSecureStorage.setMockInitialValues({'session_token': 'tok'});
      await FakeApi(offline).run(() => service.logout()); // sem rede ainda desloga
      expect(await service.getStoredToken(), isNull);
    });

    test('erros do backend chegam com a mensagem dele', () async {
      final api = FakeApi((_) => detailError('E-mail ou senha inválidos.', status: 401));

      final calls = <Future<Object?> Function()>[
        () => service.signup(email: 'a', password: 'b', name: 'c', instruments: [],
            isProfessional: false, isStudent: false),
        () => service.resend('a'),
        () => service.login(email: 'a', password: 'b'),
        () => service.forgotPassword('a'),
        () => service.resetPassword(token: 't', newPassword: 'p'),
        () => service.updateProfile(name: 'a', instruments: [], isProfessional: false, isStudent: false),
        () => service.changePassword(currentPassword: 'a', newPassword: 'b'),
        () => service.acceptPrivacyPolicy(),
        () => service.deleteAccount('a'),
      ];
      for (final call in calls) {
        await expectLater(api.run(call),
            throwsA(isA<AuthException>().having((e) => e.message, 'message', 'E-mail ou senha inválidos.')));
      }

      // Sem "detail" no corpo: mensagem padrão de cada ação
      await expectLater(FakeApi((_) => http.Response('x', 500)).run(() => service.login(email: 'a', password: 'b')),
          throwsA(isA<AuthException>().having((e) => e.toString(), 'toString', 'E-mail ou senha inválidos.')));
    });

    test('sem rede: mensagem de conexão em todas as ações', () async {
      final calls = <Future<Object?> Function()>[
        () => service.signup(email: 'a', password: 'b', name: 'c', instruments: [],
            isProfessional: false, isStudent: false),
        () => service.resend('a'),
        () => service.login(email: 'a', password: 'b'),
        () => service.forgotPassword('a'),
        () => service.resetPassword(token: 't', newPassword: 'p'),
        () => service.updateProfile(name: 'a', instruments: [], isProfessional: false, isStudent: false),
        () => service.changePassword(currentPassword: 'a', newPassword: 'b'),
        () => service.acceptPrivacyPolicy(),
        () => service.deleteAccount('a'),
      ];
      for (final call in calls) {
        await expectLater(FakeApi(offline).run(call),
            throwsA(isA<AuthException>().having((e) => e.message, 'message', _offlineMessage)));
      }
    });
  });
}
