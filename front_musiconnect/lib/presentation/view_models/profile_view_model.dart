import 'package:flutter/foundation.dart';
import '../../core/monitoring.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/favorites_service.dart';
import '../../data/services/match_count_service.dart';
import 'view_model.dart';

/// Estado e regras da aba Perfil ([ProfileScreen]): dados do usuário já
/// formatados para exibir, números do card de estatísticas, a chave de
/// dados de uso e as ações da conta. Abrir telas e diálogos fica na tela.
///
/// Escuta os favoritos, o número de matches e a chave de dados de uso — os
/// números mudam na hora quando um coração é marcado em qualquer tela.
class ProfileViewModel extends ViewModel {
  ProfileViewModel({
    required AuthUser user,
    AuthService? authService,
    FavoritesService? favorites,
    MatchCountService? matchCount,
    ValueListenable<bool>? usageDataEnabled,
    Future<void> Function(bool enabled)? setUsageDataEnabled,
  })  : _user = user,
        _authService = authService ?? AuthService(),
        _favorites = favorites ?? FavoritesService.instance,
        _matchCount = matchCount ?? MatchCountService.instance,
        _usageDataEnabled = usageDataEnabled ?? Monitoring.usageDataEnabled,
        _setUsageDataEnabled = setUsageDataEnabled ?? Monitoring.setUsageDataEnabled {
    _favorites.addListener(notifyListeners);
    _matchCount.addListener(notifyListeners);
    _usageDataEnabled.addListener(notifyListeners);
  }

  final AuthService _authService;
  final FavoritesService _favorites;
  final MatchCountService _matchCount;
  final ValueListenable<bool> _usageDataEnabled;
  final Future<void> Function(bool enabled) _setUsageDataEnabled;

  AuthUser _user;
  AuthUser get user => _user;

  /// Perfil editado fora daqui (ex: pelo MainNavigation).
  set user(AuthUser value) {
    if (identical(value, _user)) return;
    _user = value;
    notifyListeners();
  }

  /// Letra do avatar.
  String get initial => _user.name.isNotEmpty ? _user.name[0].toUpperCase() : '?';

  List<String> get ramoLabels => [
        if (_user.isProfessional) 'Profissional',
        if (_user.isStudent) 'Estudante',
      ];

  /// "Jaraguá do Sul, SC, Brasil" — ou "Não informada".
  String get location {
    final parts = [_user.city, _user.state, _user.country]
        .where((p) => p != null && p.isNotEmpty)
        .toList();
    return parts.isEmpty ? 'Não informada' : parts.join(', ');
  }

  /// Matches do card: "–" enquanto carrega ou se a consulta falhar (nunca
  /// um número inventado).
  String get matchCountLabel => '${_matchCount.count ?? '–'}';
  int get savedOpportunitiesCount => _favorites.opportunityCount;
  int get favoriteInstitutionsCount => _favorites.institutionCount;

  bool get usageDataEnabled => _usageDataEnabled.value;
  Future<void> setUsageDataEnabled(bool enabled) => _setUsageDataEnabled(enabled);

  /// Depois de salvar a edição: instrumentos/ramo/localização mudam o match
  /// de cada oportunidade, então o número de matches é recalculado.
  void profileEdited(AuthUser updated) {
    _user = updated;
    notifyListeners();
    _matchCount.refresh();
  }

  /// Exclui a conta (pede a senha). Devolve a mensagem de erro para exibir,
  /// ou null se deu certo.
  Future<String?> deleteAccount(String password) async {
    try {
      await _authService.deleteAccount(password);
      return null;
    } on AuthException catch (e) {
      return e.message;
    }
  }

  @override
  void dispose() {
    _favorites.removeListener(notifyListeners);
    _matchCount.removeListener(notifyListeners);
    _usageDataEnabled.removeListener(notifyListeners);
    super.dispose();
  }
}
