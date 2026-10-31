// Dados de exemplo e serviços falsos para testar os ViewModels sem rede.
//
// Em Dart toda classe também é uma interface: os falsos `implements` o
// serviço real e respondem o que cada teste definir. Métodos que um teste
// não usa caem no noSuchMethod e falham se forem chamados.

import 'package:flutter/foundation.dart';
import 'package:prototipo_musiconnect/data/models/opportunity_model.dart';
import 'package:prototipo_musiconnect/data/services/auth_service.dart';
import 'package:prototipo_musiconnect/data/services/dashboard_service.dart';
import 'package:prototipo_musiconnect/data/services/favorites_service.dart';
import 'package:prototipo_musiconnect/data/services/match_count_service.dart';
import 'package:prototipo_musiconnect/data/services/opportunities_service.dart';

AuthUser fakeUser({
  int id = 1,
  String name = 'Laura Heloísa',
  List<String> instruments = const ['Violino'],
  bool isStudent = true,
  bool isProfessional = false,
  String? country = 'Brasil',
  String? state = 'SC',
  String? city = 'Jaraguá do Sul',
  String? privacyPolicyVersion,
}) =>
    AuthUser(
      id: id,
      email: 'aluna@example.com',
      name: name,
      instruments: instruments,
      isStudent: isStudent,
      isProfessional: isProfessional,
      country: country,
      state: state,
      city: city,
      privacyPolicyVersion: privacyPolicyVersion,
    );

OpportunityModel fakeOpportunity(
  int id, {
  String? title,
  String type = 'audicao',
  int? matchPercentage,
  DateTime? deadline,
}) =>
    OpportunityModel(
      id: id,
      title: title ?? 'Oportunidade $id',
      type: type,
      matchPercentage: matchPercentage,
      deadline: deadline,
    );

/// Favoritos em memória: começa com [saved] e marca/desmarca sem backend.
class FakeFavoritesService extends ChangeNotifier implements FavoritesService {
  FakeFavoritesService({Set<int>? saved, Set<String>? institutions})
      : saved = saved ?? {},
        institutions = institutions ?? {};

  final Set<int> saved;
  final Set<String> institutions;

  @override
  bool isOpportunitySaved(int id) => saved.contains(id);

  @override
  int get opportunityCount => saved.length;

  @override
  int get institutionCount => institutions.length;

  /// Se alguma tela/ViewModel ainda está escutando.
  bool get isListened => hasListeners;

  /// Simula o usuário desmarcando o coração em outra tela.
  void unsave(int id) {
    saved.remove(id);
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Número de matches do Perfil: [count] fixo e conta os pedidos de refresh.
class FakeMatchCountService extends ChangeNotifier implements MatchCountService {
  FakeMatchCountService({this.count});

  @override
  int? count;
  int refreshCalls = 0;

  @override
  Future<void> refresh({bool clear = false}) async => refreshCalls++;

  /// Simula a consulta ao backend terminando com um número novo.
  void arrive(int? value) {
    count = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Conta: [deleteError] faz a exclusão falhar com essa mensagem.
class FakeAuthService implements AuthService {
  String? deleteError;
  String? deletedWith;

  @override
  Future<void> deleteAccount(String password) async {
    if (deleteError != null) throw AuthException(deleteError!);
    deletedWith = password;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Resumo da Início: responde [data] (ou lança [error]) e conta as chamadas.
class FakeDashboardService implements DashboardService {
  FakeDashboardService({this.data});

  DashboardData? data;
  Object? error;
  int calls = 0;

  @override
  Future<DashboardData> fetch() async {
    calls++;
    if (error != null) throw error!;
    return data!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Uma chamada a fetchOpportunities, para os testes conferirem o pedido.
class OpportunitiesCall {
  final String? q;
  final List<String>? types;
  final List<String>? instruments;
  final List<String>? countries;
  final int limit;
  OpportunitiesCall(this.q, this.types, this.instruments, this.countries, this.limit);
}

/// Oportunidades: responde [byType] (ou [all] quando o pedido não tem tipo),
/// [filterOptions] para o modal de filtros, e registra os pedidos em
/// [calls]. [fail] faz a próxima busca lançar erro.
class FakeOpportunitiesService implements OpportunitiesService {
  Map<String, List<OpportunityModel>> byType = {};
  List<OpportunityModel> all = [];
  FilterOptions filterOptions = const FilterOptions();
  bool fail = false;
  final calls = <OpportunitiesCall>[];

  @override
  Future<OpportunitiesResult> fetchOpportunities({
    String? q,
    List<String>? types,
    List<String>? instruments,
    List<String>? countries,
    List<String>? states,
    List<String>? cities,
    int? cityLocationId,
    bool onlyActive = true,
    int limit = 100,
    int offset = 0,
  }) async {
    calls.add(OpportunitiesCall(q, types, instruments, countries, limit));
    if (fail) throw Exception('sem rede');
    final items = types == null || types.isEmpty
        ? all
        : [for (final t in types) ...?byType[t]];
    return OpportunitiesResult(items: items.take(limit).toList(), total: items.length);
  }

  @override
  Future<FilterOptions> fetchFilterOptions({
    String? q,
    List<String>? instruments,
    List<String>? countries,
    List<String>? states,
    List<String>? cities,
  }) async =>
      filterOptions;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
