import '../../core/monitoring.dart';
import '../../data/models/opportunity_model.dart';
import '../../data/services/opportunities_service.dart';
import 'view_model.dart';

/// Prévia de uma categoria (tipo de oportunidade) para os carrosséis do
/// modo padrão (sem busca/filtro ativo).
class CategoryPreview {
  final String typeKey;
  final String label;
  final List<OpportunityModel> items;
  final int total;

  const CategoryPreview({
    required this.typeKey,
    required this.label,
    required this.items,
    required this.total,
  });
}

/// Estado e regras do navegador de oportunidades ([OpportunityBrowserView]),
/// usado pelas duas abas do Matcher e pela página de uma categoria:
/// carrosséis por tipo, busca, filtros, Escala de Match e a subpágina
/// "Ver todas".
///
/// Com [lockedType], fica travado num tipo (página de categoria): começa
/// direto na lista, sem carrosséis.
class OpportunityBrowserViewModel extends ViewModel {
  OpportunityBrowserViewModel({
    required OpportunitiesService service,
    this.matchScaleMin = 0,
    this.matchScaleMax = 100,
    this.lockedType,
    this.lockedTitle,
    void Function(String event)? logEvent,
  })  : _service = service,
        _logEvent = logEvent ?? Monitoring.logEvent,
        _matchStart = matchScaleMin,
        _matchEnd = matchScaleMax;

  final OpportunitiesService _service;
  final void Function(String event) _logEvent;

  /// Limites da Escala de Match: "Todas" usa 0-100 (não filtra por padrão);
  /// "Minhas oportunidades" trava em 85-100.
  final double matchScaleMin;
  final double matchScaleMax;

  final String? lockedType;
  final String? lockedTitle;

  // ── Lista plana (modo busca/filtro) ────────────────────────────────────
  List<OpportunityModel> _opportunities = [];
  int _totalCount = 0;
  bool _loading = true;
  String? _error;

  List<OpportunityModel> get opportunities => _opportunities;

  /// Total real que atende aos filtros — pode ser maior que a lista, que é
  /// limitada no backend.
  int get totalCount => _totalCount;
  bool get isLoading => _loading;
  String? get error => _error;

  // ── Carrosséis por categoria (modo padrão) ─────────────────────────────
  List<CategoryPreview> _categories = [];
  bool _categoriesLoading = true;

  List<CategoryPreview> get categories => _categories;
  bool get categoriesLoading => _categoriesLoading;

  // ── Subpágina "Ver todas" de uma categoria ─────────────────────────────
  String? _drillType;
  String? _drillLabel;

  String? get drillType => _drillType;
  String? get drillLabel => _drillLabel;

  void openDrill(String typeKey, String label) {
    _drillType = typeKey;
    _drillLabel = label;
    notifyListeners();
  }

  void closeDrill() {
    _drillType = null;
    _drillLabel = null;
    notifyListeners();
  }

  // ── Busca e filtros ────────────────────────────────────────────────────
  /// Texto digitado na barra de busca. Mudar não recarrega nem avisa a
  /// tela — a busca roda ao enviar ([search]) ou ao aplicar filtros.
  String query = '';

  List<String> _types = [];
  List<String> _instruments = [];
  List<String> _countries = [];
  List<String> _states = [];
  List<String> _cities = [];

  /// Rótulo por extenso dos estados ativos ("MT" → "MT | Montana").
  Map<String, String> _stateLabels = {};
  double _matchStart;
  double _matchEnd;

  // "Meu instrumento" / "Perto de Mim" do modal — começam desligados.
  bool _myInstrumentToggle = false;
  bool _myLocationToggle = false;

  List<String> get activeTypes => _types;
  List<String> get activeInstruments => _instruments;
  List<String> get activeCountries => _countries;
  List<String> get activeStates => _states;
  List<String> get activeCities => _cities;
  Map<String, String> get stateLabels => _stateLabels;
  double get matchScaleStart => _matchStart;
  double get matchScaleEnd => _matchEnd;
  bool get myInstrumentToggle => _myInstrumentToggle;
  bool get myLocationToggle => _myLocationToggle;

  /// O usuário estreitou a Escala de Match em relação aos limites da aba.
  bool get matchScaleActive => _matchStart > matchScaleMin || _matchEnd < matchScaleMax;

  int get activeFiltersCount =>
      _types.length +
      _instruments.length +
      _countries.length +
      _states.length +
      _cities.length +
      (matchScaleActive ? 1 : 0);

  /// Sem busca nem filtro: carrosséis por categoria. Com busca ou filtro
  /// (ou numa página de categoria): lista plana de resultados.
  bool get searchMode => query.isNotEmpty || activeFiltersCount > 0 || lockedType != null;

  String get searchHint {
    if (lockedType == null) return 'Busque por oportunidades...';
    final plural = kOpportunityTypePluralLabels[lockedType] ?? lockedTitle!.toLowerCase();
    return 'Busque por $plural...';
  }

  /// "12 de 40 oportunidades encontradas contendo os filtros:"
  String get resultCountLabel {
    final found = _opportunities.length < _totalCount
        ? '${_opportunities.length} de $_totalCount oportunidades encontradas'
        : '$_totalCount oportunidades encontradas';
    return activeFiltersCount > 0 ? '$found contendo os filtros:' : found;
  }

  /// Carga inicial: a lista (página de categoria) ou os carrosséis.
  Future<void> start() => lockedType != null ? load() : loadCategories();

  void search(String text) {
    query = text;
    load();
  }

  void applyFilters({
    required List<String> types,
    required List<String> instruments,
    required List<String> countries,
    required List<String> states,
    required List<String> cities,
    required Map<String, String> stateLabels,
    required double matchStart,
    required double matchEnd,
    required bool instrumentToggle,
    required bool locationToggle,
  }) {
    _types = types;
    _instruments = instruments;
    _countries = countries;
    _states = states;
    _cities = cities;
    _stateLabels = stateLabels;
    _matchStart = matchStart;
    _matchEnd = matchEnd;
    _myInstrumentToggle = instrumentToggle;
    _myLocationToggle = locationToggle;
    _logEvent('apply_filter');
    load();
  }

  // Remoção de um chip de filtro ativo.
  void removeType(String value) => _removeAndLoad(() => _types = _without(_types, value));
  void removeInstrument(String value) =>
      _removeAndLoad(() => _instruments = _without(_instruments, value));
  void removeCountry(String value) =>
      _removeAndLoad(() => _countries = _without(_countries, value));
  void removeState(String value) => _removeAndLoad(() => _states = _without(_states, value));
  void removeCity(String value) => _removeAndLoad(() => _cities = _without(_cities, value));
  void resetMatchScale() => _removeAndLoad(() {
        _matchStart = matchScaleMin;
        _matchEnd = matchScaleMax;
      });

  /// "Limpar filtros" do estado vazio.
  void clearFilters() => _removeAndLoad(() {
        _types = [];
        _instruments = [];
        _countries = [];
        _states = [];
        _cities = [];
        _matchStart = matchScaleMin;
        _matchEnd = matchScaleMax;
      });

  static List<String> _without(List<String> list, String value) =>
      list.where((x) => x != value).toList();

  void _removeAndLoad(void Function() change) {
    change();
    load();
  }

  // ── Carregamento ───────────────────────────────────────────────────────

  /// Busca oportunidades e, se a Escala de Match exclui alguma faixa de
  /// 0-100, filtra por `matchPercentage` — pedindo um lote maior antes de
  /// cortar por [limit], senão o corte viria ANTES do filtro e a prévia
  /// ficaria incompleta. Em "Minhas oportunidades" a faixa de repouso já é
  /// 85-100, então o filtro roda mesmo sem o usuário mexer no slider.
  Future<OpportunitiesResult> _fetch({
    String? q,
    List<String>? types,
    List<String>? instruments,
    List<String>? countries,
    List<String>? states,
    List<String>? cities,
    required int limit,
  }) async {
    final filterNeeded = _matchStart > 0 || _matchEnd < 100;

    final result = await _service.fetchOpportunities(
      q: q,
      types: types,
      instruments: instruments,
      countries: countries,
      states: states,
      cities: cities,
      // O backend já deixa passar quem não tem prazo informado — só exclui
      // quem realmente já venceu.
      onlyActive: true,
      limit: filterNeeded ? 500 : limit,
    );
    if (!filterNeeded) return result;

    final filtered = result.items.where((o) {
      final m = o.matchPercentage ?? 0;
      return m >= _matchStart && m <= _matchEnd;
    }).toList()
      ..sort((a, b) => (b.matchPercentage ?? 0).compareTo(a.matchPercentage ?? 0));
    return OpportunitiesResult(items: filtered.take(limit).toList(), total: filtered.length);
  }

  Future<void> loadCategories() async {
    _categoriesLoading = true;
    notifyListeners();

    final entries = kOpportunityTypeLabels.entries.toList();
    final results = await Future.wait(
      entries.map((e) => _fetch(types: [e.key], limit: 10)),
    );

    _categories = [
      for (var i = 0; i < entries.length; i++)
        // Categoria sem nada aberto some.
        if (results[i].total > 0)
          CategoryPreview(
            typeKey: entries[i].key,
            label: entries[i].value,
            items: results[i].items,
            total: results[i].total,
          ),
    ];
    _categoriesLoading = false;
    notifyListeners();
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _fetch(
        q: query.isEmpty ? null : query,
        types: lockedType != null ? [lockedType!] : (_types.isEmpty ? null : _types),
        instruments: _instruments,
        countries: _countries,
        states: _states,
        cities: _cities,
        limit: 500,
      );
      _opportunities = result.items;
      _totalCount = result.total;
    } catch (_) {
      _error = 'Não foi possível carregar as oportunidades.';
    }
    _loading = false;
    notifyListeners();
  }
}
