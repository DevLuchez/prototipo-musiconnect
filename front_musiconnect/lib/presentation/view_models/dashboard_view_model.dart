import '../../data/models/opportunity_model.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/dashboard_service.dart';
import '../../data/services/favorites_service.dart';
import 'view_model.dart';

/// Estado e regras da aba Início ([DashboardScreen]): carrega o resumo do
/// backend e decide o que aparece (melhor match, prazos das salvas, estado
/// vazio). A tela só desenha a partir daqui.
///
/// Escuta o [FavoritesService]: remover uma salva tira ela de "Última
/// chance" na hora, sem recarregar.
class DashboardViewModel extends ViewModel {
  DashboardViewModel({
    required AuthUser user,
    DashboardService? service,
    FavoritesService? favorites,
  })  : _user = user,
        _service = service ?? DashboardService(),
        _favorites = favorites ?? FavoritesService.instance {
    _favorites.addListener(notifyListeners);
  }

  final DashboardService _service;
  final FavoritesService _favorites;

  AuthUser _user;
  DashboardData? _data;
  bool _isLoading = true;
  bool _hasError = false;

  bool get isLoading => _isLoading;
  bool get hasError => _hasError;

  /// Perfil editado (aba Perfil) muda os matches: troca o usuário e recarrega.
  set user(AuthUser value) {
    if (identical(value, _user)) return;
    _user = value;
    load();
  }

  /// Primeiro nome para a saudação ("Laura Heloísa" → "Laura").
  String get firstName {
    final name = _user.name.trim();
    return name.isEmpty ? '' : name.split(RegExp(r'\s+')).first;
  }

  /// Só o melhor match vai pro Início (destaque); os demais ficam em Minhas
  /// oportunidades.
  OpportunityModel? get bestMatch {
    final top = _data?.topMatches ?? const [];
    return top.isEmpty ? null : top.first;
  }

  /// Salvas que fecham nos próximos dias — e que continuam salvas agora.
  List<OpportunityModel> get urgentSaved => (_data?.urgentSaved ?? const [])
      .where((o) => _favorites.isOpportunitySaved(o.id))
      .toList();

  /// Quantas abertas há de cada tipo (bloco "Explorar").
  Map<String, int> get typeCounts => _data?.typeCounts ?? const {};

  /// Sem prazos nem matches: a tela convida a explorar todas.
  bool get nothingToShow => urgentSaved.isEmpty && bestMatch == null;

  Future<void> load() async {
    _isLoading = true;
    _hasError = false;
    notifyListeners();
    try {
      _data = await _service.fetch();
    } catch (_) {
      _hasError = true;
    }
    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _favorites.removeListener(notifyListeners);
    super.dispose();
  }
}
