import 'package:flutter/material.dart';
import '../../data/models/opportunity_model.dart';
import '../../data/models/providers/auth_service.dart';
import '../../data/models/providers/opportunities_service.dart';
import '../screens/opportunity_detail_screen.dart';
import 'app_loading_indicator.dart';
import 'filter_modal.dart';
import 'opportunity_card.dart';
import 'opportunity_carousel_section.dart';

const _pink = Color(0xFFEC4899);

/// Prévia de uma categoria (tipo de oportunidade) pro carrossel do modo
/// padrão (sem busca/filtro ativo).
class _CategoryPreview {
  final String typeKey;
  final String label;
  final List<OpportunityModel> items;
  final int total;

  const _CategoryPreview({
    required this.typeKey,
    required this.label,
    required this.items,
    required this.total,
  });
}

/// Busca + filtro + carrosséis por categoria + lista plana de resultados —
/// o layout completo usado tanto pela aba "Todas as oportunidades" quanto
/// por "Minhas oportunidades" (mesmo widget, só muda a faixa da Escala de
/// Match). A subpágina "Ver todas" de uma categoria é o próprio widget se
/// renderizando de novo, travado num tipo ([lockedType]) — ver [build].
class OpportunityBrowserView extends StatefulWidget {
  final OpportunitiesService service;

  /// Chamado quando o usuário quer ver uma instituição no mapa.
  final OpenOpportunityOnMap? onOpenMap;

  // Limites do slider "Escala de Match" no FilterModal — "Todas as
  // oportunidades" usa 0-100 (livre, sem filtrar por padrão); "Minhas
  // oportunidades" trava em 85-100 (nunca mostra abaixo do que promete).
  final double matchScaleMin;
  final double matchScaleMax;

  final String emptyCategoriesMessage;
  final String emptySearchMessage;

  // Perfil do usuário logado — usado pelos filtros opcionais "Meu
  // instrumento"/"Perto de Mim" no FilterModal (iguais nas duas abas:
  // começam desligados, o usuário decide se liga) e passado adiante pra
  // tela de detalhes (aba MusiMatch: "seu perfil vs. edital").
  final AuthUser user;

  // Só usados no modo "subpágina de categoria" (drill-down interno — ver
  // [build]): quando [lockedType] não é nulo, trava a busca nesse tipo,
  // esconde os carrosséis e mostra o cabeçalho local de voltar.
  final String? lockedType;
  final String? lockedTitle;
  final VoidCallback? onBack;

  const OpportunityBrowserView({
    super.key,
    required this.service,
    required this.user,
    this.onOpenMap,
    this.matchScaleMin = 0,
    this.matchScaleMax = 100,
    this.emptyCategoriesMessage = 'Nenhuma oportunidade disponível.',
    this.emptySearchMessage = 'Nenhuma oportunidade disponível.',
    this.lockedType,
    this.lockedTitle,
    this.onBack,
  }) : assert(lockedType == null || lockedTitle != null);

  @override
  State<OpportunityBrowserView> createState() =>
      _OpportunityBrowserViewState();
}

class _OpportunityBrowserViewState extends State<OpportunityBrowserView> {
  // Estado da listagem (modo busca/filtro — lista plana)
  List<OpportunityModel> _opportunities = [];
  // Total real que atende aos filtros no backend — pode ser maior que
  // _opportunities.length, já que a busca é limitada por `limit`.
  int _totalCount = 0;
  bool _loading = true;
  String? _error;

  // Estado dos carrosséis por categoria (modo padrão — navegação por tipo)
  // — só usado quando widget.lockedType == null.
  List<_CategoryPreview> _categories = [];
  bool _categoriesLoading = true;

  // Categoria aberta (subpágina "Ver todas") — embutida aqui em vez de
  // empurrada via Navigator.push, pra manter o header/navbar globais do
  // app visíveis (um push cobriria o Scaffold inteiro de MainNavigation).
  String? _drillType;
  String? _drillLabel;

  // Filtros ativos — cada campo aceita múltiplos valores selecionados.
  final _searchController = TextEditingController();
  List<String> _activeTypes = [];
  List<String> _activeInstruments = [];
  List<String> _activeCountries = [];
  List<String> _activeStates = [];
  List<String> _activeCities = [];
  // Rótulo por extenso dos estados ativos (ex: "MT" -> "MT | Montana"),
  // devolvido pelo modal junto com a seleção — usado nos chips abaixo.
  Map<String, String> _stateLabels = {};

  late RangeValues _matchScale =
      RangeValues(widget.matchScaleMin, widget.matchScaleMax);

  // "Meu instrumento" / "Perto de Mim" — opcionais e iguais nas duas abas:
  // começam desligados, o usuário decide se liga.
  bool _myInstrumentToggle = false;
  bool _myLocationToggle = false;

  bool get _matchScaleActive =>
      _matchScale.start > widget.matchScaleMin ||
      _matchScale.end < widget.matchScaleMax;

  // Enquanto não há busca/filtro ativo, mostra os carrosséis por categoria;
  // assim que o usuário busca ou filtra (inclusive estreitando a Escala de
  // Match), mostra a lista plana de resultados.
  bool get _searchMode =>
      _searchController.text.isNotEmpty ||
      _activeFiltersCount > 0 ||
      widget.lockedType != null;

  int get _activeFiltersCount =>
      _activeTypes.length +
      _activeInstruments.length +
      _activeCountries.length +
      _activeStates.length +
      _activeCities.length +
      (_matchScaleActive ? 1 : 0);

  String get _searchHint {
    if (widget.lockedType == null) return 'Busque por oportunidades...';
    final plural = kOpportunityTypePluralLabels[widget.lockedType] ??
        widget.lockedTitle!.toLowerCase();
    return 'Busque por $plural...';
  }

  @override
  void initState() {
    super.initState();
    if (widget.lockedType != null) {
      // Subpágina de categoria: já entra buscando a lista travada nesse tipo.
      _load();
    } else {
      _loadCategories();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Busca oportunidades e, se a Escala de Match estiver restrita (fora dos
  /// limites completos do widget), filtra o resultado por
  /// `matchPercentage` — buscando um lote maior antes de cortar por
  /// [limit], senão o corte aconteceria ANTES do filtro e a prévia (ex: do
  /// carrossel) ficaria incompleta. Sem filtro de match ativo, o
  /// comportamento e o payload são idênticos a uma chamada direta ao
  /// serviço (mesmo `limit` pedido).
  Future<OpportunitiesResult> _fetch({
    String? q,
    List<String>? types,
    List<String>? instruments,
    List<String>? countries,
    List<String>? states,
    List<String>? cities,
    required int limit,
  }) async {
    // Diferente de [_matchScaleActive] (que só reflete se o usuário mexeu
    // no slider): aqui o que importa é se o range atual exclui QUALQUER
    // oportunidade possível (0-100) — em "Minhas oportunidades", o range
    // de repouso já é 85-100, então o filtro precisa rodar mesmo sem o
    // usuário ter tocado no slider, senão a aba mostraria tudo (0-100%).
    final filterNeeded = _matchScale.start > 0 || _matchScale.end < 100;

    final result = await widget.service.fetchOpportunities(
      q: q,
      types: types,
      instruments: instruments,
      countries: countries,
      states: states,
      cities: cities,
      // O backend já deixa passar quem não tem prazo informado
      // (deadline IS NULL OR deadline >= hoje) — só exclui quem
      // realmente já venceu.
      onlyActive: true,
      limit: filterNeeded ? 500 : limit,
    );
    if (!filterNeeded) return result;

    final filtered = result.items.where((o) {
      final m = o.matchPercentage ?? 0;
      return m >= _matchScale.start && m <= _matchScale.end;
    }).toList()
      ..sort(
        (a, b) => (b.matchPercentage ?? 0).compareTo(a.matchPercentage ?? 0),
      );
    return OpportunitiesResult(
      items: filtered.take(limit).toList(),
      total: filtered.length,
    );
  }

  Future<void> _loadCategories() async {
    setState(() => _categoriesLoading = true);

    final entries = kOpportunityTypeLabels.entries.toList();
    final results = await Future.wait(
      entries.map((e) => _fetch(types: [e.key], limit: 10)),
    );

    final categories = <_CategoryPreview>[];
    for (var i = 0; i < entries.length; i++) {
      final result = results[i];
      if (result.total == 0) continue; // esconde categoria sem nada
      categories.add(_CategoryPreview(
        typeKey: entries[i].key,
        label: entries[i].value,
        items: result.items,
        total: result.total,
      ));
    }

    if (!mounted) return;
    setState(() {
      _categories = categories;
      _categoriesLoading = false;
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _fetch(
        q: _searchController.text.isEmpty ? null : _searchController.text,
        types: widget.lockedType != null
            ? [widget.lockedType!]
            : (_activeTypes.isEmpty ? null : _activeTypes),
        instruments: _activeInstruments,
        countries: _activeCountries,
        states: _activeStates,
        cities: _activeCities,
        limit: 500,
      );
      if (!mounted) return;
      setState(() {
        _opportunities = result.items;
        _totalCount = result.total;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Não foi possível carregar as oportunidades.';
        _loading = false;
      });
    }
  }

  void _openFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FilterModal(
        // O filtro de tipo fica escondido dentro de uma subpágina de
        // categoria — o tipo já está travado pela navegação ali.
        showTypeFilter: widget.lockedType == null,
        initialTypes: _activeTypes,
        initialInstruments: _activeInstruments,
        initialCountries: _activeCountries,
        initialStates: _activeStates,
        initialCities: _activeCities,
        initialStateLabels: _stateLabels,
        service: widget.service,
        searchQuery: _searchController.text,
        matchScaleMin: widget.matchScaleMin,
        matchScaleMax: widget.matchScaleMax,
        initialMatchScale: _matchScale,
        myInstruments: widget.user.instruments,
        myCountry: widget.user.country,
        myState: widget.user.state,
        myCity: widget.user.city,
        initialInstrumentToggle: _myInstrumentToggle,
        initialLocationToggle: _myLocationToggle,
        onApply: ({
          required types,
          required instruments,
          required countries,
          required states,
          required cities,
          required stateLabels,
          required matchScale,
          required instrumentToggle,
          required locationToggle,
        }) {
          setState(() {
            _activeTypes = types;
            _activeInstruments = instruments;
            _activeCountries = countries;
            _activeStates = states;
            _activeCities = cities;
            _stateLabels = stateLabels;
            _matchScale = matchScale;
            _myInstrumentToggle = instrumentToggle;
            _myLocationToggle = locationToggle;
          });
          _load();
        },
      ),
    );
  }

  void _openDrill(String typeKey, String label) {
    setState(() {
      _drillType = typeKey;
      _drillLabel = label;
    });
  }

  void _closeDrill() {
    setState(() {
      _drillType = null;
      _drillLabel = null;
    });
  }

  void _openDetail(OpportunityModel opp) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OpportunityDetailScreen(
          opportunity: opp,
          user: widget.user,
          onOpenMap: widget.onOpenMap,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Subpágina "Ver todas" de uma categoria — mesmo widget, travado no
    // tipo escolhido, com o header local de voltar e sem carrosséis.
    if (widget.lockedType == null && _drillType != null) {
      return OpportunityBrowserView(
        key: ValueKey(_drillType),
        service: widget.service,
        user: widget.user,
        onOpenMap: widget.onOpenMap,
        matchScaleMin: widget.matchScaleMin,
        matchScaleMax: widget.matchScaleMax,
        emptyCategoriesMessage: widget.emptyCategoriesMessage,
        emptySearchMessage: widget.emptySearchMessage,
        lockedType: _drillType,
        lockedTitle: _drillLabel,
        onBack: _closeDrill,
      );
    }

    return Column(
      children: [
        if (widget.lockedType != null)
          // Cabeçalho local (voltar + título da categoria) — não é um
          // AppBar de verdade, pra não competir com o header global do app.
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Color(0xFF111827)),
                  tooltip: 'Voltar',
                  onPressed: widget.onBack,
                ),
                Expanded(
                  child: Text(
                    widget.lockedTitle!,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),

        // Barra de busca + filtros
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              // Campo de busca
              Expanded(
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(1, 1),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: (_) => _load(),
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      hintText: _searchHint,
                      hintStyle: TextStyle(
                          fontSize: 13.5, color: Colors.grey[400]),
                      prefixIcon: Icon(Icons.search_rounded,
                          size: 18, color: Colors.grey[400]),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 40, minHeight: 0),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                _load();
                              },
                              child: Icon(Icons.close_rounded,
                                  size: 16, color: Colors.grey[400]),
                            )
                          : null,
                      suffixIconConstraints:
                          const BoxConstraints(minWidth: 40, minHeight: 0),
                      border: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 11),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Botão de filtros
              GestureDetector(
                onTap: _openFilters,
                child: Container(
                  height: 42,
                  width: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(1, 1),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(
                        Icons.tune_rounded,
                        size: 20,
                        color: Color(0xFFDF2881),
                      ),
                      if (_activeFiltersCount > 0)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: const BoxDecoration(
                              color: _pink,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '$_activeFiltersCount',
                                style: const TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        if (_searchMode) ...[
          // Contagem de resultados
          if (!_loading && _error == null)
            Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(
                  16, 8, 16, _activeFiltersCount > 0 ? 4 : 10),
              child: SizedBox(
                width: double.infinity,
                child: Text(
                  (_opportunities.length < _totalCount
                          ? '${_opportunities.length} de $_totalCount oportunidades encontradas'
                          : '$_totalCount oportunidades encontradas') +
                      (_activeFiltersCount > 0 ? ' contendo os filtros:' : ''),
                  textAlign: TextAlign.left,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),

          // Chips de filtros ativos
          if (_activeFiltersCount > 0)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (_matchScaleActive)
                      _ActiveFilterChip(
                        label:
                            '${_matchScale.start.round()}-${_matchScale.end.round()}% match',
                        onRemove: () {
                          setState(() => _matchScale = RangeValues(
                              widget.matchScaleMin, widget.matchScaleMax));
                          _load();
                        },
                      ),
                    for (final v in _activeTypes)
                      _ActiveFilterChip(
                        label: kOpportunityTypeLabels[v] ?? v,
                        onRemove: () {
                          setState(() => _activeTypes =
                              _activeTypes.where((x) => x != v).toList());
                          _load();
                        },
                      ),
                    for (final v in _activeInstruments)
                      _ActiveFilterChip(
                        label: v,
                        onRemove: () {
                          setState(() => _activeInstruments =
                              _activeInstruments.where((x) => x != v).toList());
                          _load();
                        },
                      ),
                    for (final v in _activeCountries)
                      _ActiveFilterChip(
                        label: v,
                        onRemove: () {
                          setState(() => _activeCountries =
                              _activeCountries.where((x) => x != v).toList());
                          _load();
                        },
                      ),
                    for (final v in _activeStates)
                      _ActiveFilterChip(
                        label: _stateLabels[v] ?? v,
                        onRemove: () {
                          setState(() => _activeStates =
                              _activeStates.where((x) => x != v).toList());
                          _load();
                        },
                      ),
                    for (final v in _activeCities)
                      _ActiveFilterChip(
                        label: v,
                        onRemove: () {
                          setState(() => _activeCities =
                              _activeCities.where((x) => x != v).toList());
                          _load();
                        },
                      ),
                  ],
                ),
              ),
            ),

          // Lista / Loading / Erro / Vazio
          Expanded(child: _buildContent()),
        ] else
          // Modo padrão: navegar por categoria (carrosséis por tipo)
          Expanded(child: _buildCategoriesBrowser()),
      ],
    );
  }

  Widget _buildCategoriesBrowser() {
    if (_categoriesLoading) {
      return const Center(
        child: AppLoadingIndicator(size: 28, color: _pink),
      );
    }

    if (_categories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            widget.emptyCategoriesMessage,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: _pink,
      onRefresh: _loadCategories,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (final category in _categories)
            OpportunityCarouselSection(
              title: category.label,
              total: category.total,
              items: category.items,
              onSeeAll: () => _openDrill(category.typeKey, category.label),
              onCardTap: _openDetail,
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLoadingIndicator(size: 28, color: _pink),
            SizedBox(height: 16),
            Text(
              'Carregando oportunidades...',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _load,
              style: OutlinedButton.styleFrom(
                foregroundColor: _pink,
                side: const BorderSide(color: _pink),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      );
    }

    if (_opportunities.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _searchController.text.isNotEmpty
                    ? 'Nenhuma oportunidade encontrada para\n"${_searchController.text}"'
                    : widget.emptySearchMessage,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ),
            if (_activeFiltersCount > 0) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _activeTypes = [];
                    _activeInstruments = [];
                    _activeCountries = [];
                    _activeStates = [];
                    _activeCities = [];
                    _matchScale = RangeValues(
                        widget.matchScaleMin, widget.matchScaleMax);
                  });
                  _load();
                },
                child: const Text(
                  'Limpar filtros',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _pink,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _pink,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: _opportunities.length,
        itemBuilder: (context, index) {
          final opp = _opportunities[index];
          return OpportunityCard(
            opportunity: opp,
            matchPercentage: opp.matchPercentage,
            onTap: () => _openDetail(opp),
          );
        },
      ),
    );
  }
}

/// Chip de filtro ativo com botão de remoção.
class _ActiveFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _ActiveFilterChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _pink.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _pink.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _pink,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded, size: 14, color: _pink),
          ),
        ],
      ),
    );
  }
}
