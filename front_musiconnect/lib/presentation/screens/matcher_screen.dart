import 'package:flutter/material.dart';
import '../../data/models/opportunity_model.dart';
import '../../data/models/providers/opportunities_service.dart';
import '../widgets/app_loading_indicator.dart';
import '../widgets/opportunity_card.dart';
import '../widgets/opportunity_carousel_section.dart';
import '../widgets/filter_modal.dart';
import 'opportunity_detail_screen.dart';
import 'opportunity_list_screen.dart';

/// Prévia de uma categoria (tipo de oportunidade) pro carrossel da aba
/// "Todas as oportunidades".
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

const _pink = Color(0xFFEC4899);
const _purple = Color(0xFF7C3AED);

/// Tela Matcher com duas abas:
///   1. Minhas oportunidades (placeholder)
///   2. Todas as oportunidades (lista real do backend)
class MatcherScreen extends StatefulWidget {
  /// Chamado quando o usuário quer ver uma instituição no mapa.
  final VoidCallback? onSwitchToMap;

  const MatcherScreen({super.key, this.onSwitchToMap});

  @override
  State<MatcherScreen> createState() => _MatcherScreenState();
}

class _MatcherScreenState extends State<MatcherScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _service = OpportunitiesService();

  // Estado da listagem (modo busca/filtro — lista plana)
  List<OpportunityModel> _opportunities = [];
  // Total real que atende aos filtros no backend — pode ser maior que
  // _opportunities.length, já que a busca é limitada por `limit`.
  int _totalCount = 0;
  bool _loading = true;
  String? _error;

  // Estado dos carrosséis por categoria (modo padrão — navegação por tipo)
  List<_CategoryPreview> _categories = [];
  bool _categoriesLoading = true;

  // Categoria aberta (subpágina "Ver todas") — embutida aqui em vez de
  // empurrada via Navigator.push, pra manter o header/navbar globais do
  // app visíveis (um push cobriria o Scaffold inteiro de MainNavigation).
  String? _openCategoryType;
  String? _openCategoryLabel;

  // Filtros ativos — cada campo aceita múltiplos valores selecionados.
  final _searchController = TextEditingController();
  List<String> _activeInstruments = [];
  List<String> _activeCountries = [];
  List<String> _activeStates = [];
  List<String> _activeCities = [];
  // Rótulo por extenso dos estados ativos (ex: "MT" -> "MT | Montana"),
  // devolvido pelo modal junto com a seleção — usado nos chips abaixo.
  Map<String, String> _stateLabels = {};

  // Enquanto não há busca/filtro ativo, mostra os carrosséis por categoria;
  // assim que o usuário busca ou filtra, mostra a lista plana de resultados.
  bool get _searchMode =>
      _searchController.text.isNotEmpty || _activeFiltersCount > 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 1);
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _categoriesLoading = true);

    final entries = kOpportunityTypeLabels.entries.toList();
    final results = await Future.wait(
      entries.map(
        (e) => _service.fetchOpportunities(
          type: e.key,
          onlyActive: false,
          limit: 10,
        ),
      ),
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

  void _openCategory(String typeKey, String label) {
    setState(() {
      _openCategoryType = typeKey;
      _openCategoryLabel = label;
    });
  }

  void _closeCategory() {
    setState(() {
      _openCategoryType = null;
      _openCategoryLabel = null;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadOpportunities() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _service.fetchOpportunities(
        q: _searchController.text.isEmpty ? null : _searchController.text,
        instruments: _activeInstruments,
        countries: _activeCountries,
        states: _activeStates,
        cities: _activeCities,
        onlyActive: false, // mostra todas, inclusive sem prazo
        limit: 500,
      );
      setState(() {
        _opportunities = result.items;
        _totalCount = result.total;
        _loading = false;
      });
    } catch (e) {
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
        initialInstruments: _activeInstruments,
        initialCountries: _activeCountries,
        initialStates: _activeStates,
        initialCities: _activeCities,
        initialStateLabels: _stateLabels,
        service: _service,
        onApply: ({
          required instruments,
          required countries,
          required states,
          required cities,
          required stateLabels,
        }) {
          setState(() {
            _activeInstruments = instruments;
            _activeCountries = countries;
            _activeStates = states;
            _activeCities = cities;
            _stateLabels = stateLabels;
          });
          _loadOpportunities();
        },
      ),
    );
  }

  int get _activeFiltersCount =>
      _activeInstruments.length +
      _activeCountries.length +
      _activeStates.length +
      _activeCities.length;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── TabBar ───────────────────────────────────────────────
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: _pink,
            unselectedLabelColor: Colors.grey[500],
            indicatorColor: _pink,
            indicatorWeight: 2.5,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 13.5,
            ),
            tabs: const [
              Tab(text: 'Minhas oportunidades'),
              Tab(text: 'Todas as oportunidades'),
            ],
          ),
        ),

        // ── Conteúdo das abas ────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildMyOpportunitiesTab(),
              _buildAllOpportunitiesTab(),
            ],
          ),
        ),
      ],
    );
  }

  // ── Aba 1: Minhas oportunidades (placeholder) ─────────────────
  Widget _buildMyOpportunitiesTab() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [_purple, _pink],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 56,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Minhas oportunidades',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Em breve você verá aqui as oportunidades que mais combinam com o seu perfil musical.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () {
              _tabController.animateTo(1);
            },
            icon: const Icon(Icons.search_rounded, size: 18),
            label: const Text('Ver todas as oportunidades'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _pink,
              side: const BorderSide(color: _pink, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ── Aba 2: Todas as oportunidades ────────────────────────────
  Widget _buildAllOpportunitiesTab() {
    if (_openCategoryType != null) {
      // Chave diferente por categoria — força recriar o estado da
      // subpágina (busca/filtros) ao trocar de categoria, em vez de
      // reaproveitar o estado da categoria anterior.
      return OpportunityListScreen(
        key: ValueKey(_openCategoryType),
        type: _openCategoryType,
        title: _openCategoryLabel!,
        onBack: _closeCategory,
        onOpenMap: widget.onSwitchToMap,
      );
    }

    return Column(
      children: [
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
                    onSubmitted: (_) => _loadOpportunities(),
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      hintText: 'Busque por oportunidades...',
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
                                _loadOpportunities();
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
                    for (final v in _activeInstruments)
                      _ActiveFilterChip(
                        label: v,
                        onRemove: () {
                          setState(() => _activeInstruments =
                              _activeInstruments.where((x) => x != v).toList());
                          _loadOpportunities();
                        },
                      ),
                    for (final v in _activeCountries)
                      _ActiveFilterChip(
                        label: v,
                        onRemove: () {
                          setState(() => _activeCountries =
                              _activeCountries.where((x) => x != v).toList());
                          _loadOpportunities();
                        },
                      ),
                    for (final v in _activeStates)
                      _ActiveFilterChip(
                        label: _stateLabels[v] ?? v,
                        onRemove: () {
                          setState(() => _activeStates =
                              _activeStates.where((x) => x != v).toList());
                          _loadOpportunities();
                        },
                      ),
                    for (final v in _activeCities)
                      _ActiveFilterChip(
                        label: v,
                        onRemove: () {
                          setState(() => _activeCities =
                              _activeCities.where((x) => x != v).toList());
                          _loadOpportunities();
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
        child: Text(
          'Nenhuma oportunidade disponível.',
          style: TextStyle(fontSize: 14, color: Colors.grey[500]),
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
              onSeeAll: () => _openCategory(category.typeKey, category.label),
              onCardTap: (opp) => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => OpportunityDetailScreen(
                    opportunity: opp,
                    onOpenMap: widget.onSwitchToMap,
                  ),
                ),
              ),
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
              onPressed: _loadOpportunities,
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
            Text(
              _searchController.text.isNotEmpty
                  ? 'Nenhuma oportunidade encontrada para\n"${_searchController.text}"'
                  : 'Nenhuma oportunidade disponível.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            if (_activeFiltersCount > 0) ...[
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _activeInstruments = [];
                    _activeCountries = [];
                    _activeStates = [];
                    _activeCities = [];
                  });
                  _loadOpportunities();
                },
                child: Text(
                  'Limpar filtros',
                  style: const TextStyle(
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
      onRefresh: _loadOpportunities,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: _opportunities.length,
        itemBuilder: (context, index) {
          final opp = _opportunities[index];
          return OpportunityCard(
            opportunity: opp,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => OpportunityDetailScreen(
                  opportunity: opp,
                  onOpenMap: widget.onSwitchToMap,
                ),
              ),
            ),
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
