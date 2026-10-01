import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/text_utils.dart';
import '../../data/models/opportunity_model.dart';
import '../../data/models/place_model.dart';
import '../../data/models/providers/auth_service.dart';
import '../../data/models/providers/favorites_service.dart';
import '../widgets/app_loading_indicator.dart';
import '../widgets/auth/auth_common.dart';
import '../widgets/favorite_button.dart';
import '../widgets/opportunity_card.dart';
import 'opportunity_detail_screen.dart';

// Estrela de "tem oportunidade aberta" — mesma cor dos pinos do mapa.
const _starColor = Color.fromARGB(255, 255, 183, 0);

/// Ordens disponíveis nas listas de favoritos. "Recentes/antigas" é pela
/// data em que o usuário salvou (não pela data da oportunidade).
enum FavoritesSort {
  deadline('Prazo mais próximo'),
  newest('Mais recentes'),
  oldest('Mais antigas'),
  az('A–Z'),
  za('Z–A');

  final String label;
  const FavoritesSort(this.label);
}

/// Oportunidades salvas — aberta pelo menu lateral.
///
/// Remover o coração de um card tira a oportunidade da lista na hora. As
/// que vencem o prazo já não vêm do backend.
class SavedOpportunitiesScreen extends StatefulWidget {
  final AuthUser user;
  final OpenOpportunityOnMap onOpenMap;

  const SavedOpportunitiesScreen({
    super.key,
    required this.user,
    required this.onOpenMap,
  });

  @override
  State<SavedOpportunitiesScreen> createState() => _SavedOpportunitiesScreenState();
}

class _SavedOpportunitiesScreenState extends State<SavedOpportunitiesScreen> {
  final _favorites = FavoritesService.instance;
  late Future<List<OpportunityModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _favorites.fetchSavedOpportunities();
  }

  Future<void> _reload() async {
    final future = _favorites.fetchSavedOpportunities();
    setState(() => _future = future);
    await future.catchError((_) => <OpportunityModel>[]);
  }

  void _open(OpportunityModel opp) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OpportunityDetailScreen(
        opportunity: opp,
        user: widget.user,
        onOpenMap: widget.onOpenMap,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return _FavoritesScaffold(
      title: 'Oportunidades salvas',
      future: _future,
      onRetry: _reload,
      empty: const _EmptyState(
        icon: Icons.favorite_border_rounded,
        message: 'Nenhuma oportunidade salva ainda.\n'
            'Toque no coração de uma oportunidade para salvá-la aqui.',
      ),
      builder: (List<OpportunityModel> items) => _FavoritesBrowser<OpportunityModel>(
        items: items,
        isSaved: (o) => _favorites.isOpportunitySaved(o.id),
        searchHint: 'Busque por título, instrumento, endereço...',
        searchText: (o) => [
          o.title,
          o.institution,
          o.city,
          o.state,
          o.country,
          ...o.instruments,
        ].whereType<String>().join(' '),
        sortOptions: FavoritesSort.values,
        defaultSort: FavoritesSort.deadline,
        prefsKey: 'favorites_sort_opportunities',
        name: (o) => o.title,
        savedAt: (o) => o.savedAt,
        deadline: (o) => o.deadline,
        countLabel: (n) =>
            n == 1 ? '1 oportunidade salva' : '$n oportunidades salvas',
        onRefresh: _reload,
        empty: const _EmptyState(
          icon: Icons.favorite_border_rounded,
          message: 'Nenhuma oportunidade salva.',
        ),
        itemBuilder: (opp) => OpportunityCard(
          key: ValueKey(opp.id),
          opportunity: opp,
          matchPercentage: opp.matchPercentage,
          margin: const EdgeInsets.symmetric(vertical: 6),
          onTap: () => _open(opp),
        ),
      ),
    );
  }
}

/// Instituições favoritas — aberta pelo menu lateral. Tocar numa delas
/// leva à aba Mapa, centralizada no pino e com o detalhe aberto.
class FavoriteInstitutionsScreen extends StatefulWidget {
  final void Function(PlaceModel place) onOpenMap;

  const FavoriteInstitutionsScreen({super.key, required this.onOpenMap});

  @override
  State<FavoriteInstitutionsScreen> createState() =>
      _FavoriteInstitutionsScreenState();
}

class _FavoriteInstitutionsScreenState extends State<FavoriteInstitutionsScreen> {
  final _favorites = FavoritesService.instance;
  late Future<List<PlaceModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _favorites.fetchFavoriteInstitutions();
  }

  Future<void> _reload() async {
    final future = _favorites.fetchFavoriteInstitutions();
    setState(() => _future = future);
    await future.catchError((_) => <PlaceModel>[]);
  }

  @override
  Widget build(BuildContext context) {
    return _FavoritesScaffold(
      title: 'Instituições favoritas',
      future: _future,
      onRetry: _reload,
      empty: const _EmptyState(
        icon: Icons.favorite_border_rounded,
        message: 'Nenhuma instituição favorita ainda.\n'
            'Toque no coração no detalhe de uma instituição do mapa.',
      ),
      builder: (List<PlaceModel> items) => _FavoritesBrowser<PlaceModel>(
        items: items,
        isSaved: (p) => p.osmId != null && _favorites.isInstitutionFavorite(p.osmId!),
        searchHint: 'Busque por nome, tipo, endereço...',
        searchText: (p) =>
            [p.name, p.categoryLabel, p.address].whereType<String>().join(' '),
        // Instituição não tem prazo — sem "Prazo mais próximo".
        sortOptions: const [
          FavoritesSort.newest,
          FavoritesSort.oldest,
          FavoritesSort.az,
          FavoritesSort.za,
        ],
        defaultSort: FavoritesSort.newest,
        prefsKey: 'favorites_sort_institutions',
        name: (p) => p.name,
        savedAt: (p) => p.savedAt,
        countLabel: (n) =>
            n == 1 ? '1 instituição favorita' : '$n instituições favoritas',
        onRefresh: _reload,
        empty: const _EmptyState(
          icon: Icons.favorite_border_rounded,
          message: 'Nenhuma instituição favorita.',
        ),
        itemBuilder: (place) => _InstitutionTile(
          key: ValueKey(place.osmId),
          place: place,
          onTap: () => widget.onOpenMap(place),
        ),
      ),
    );
  }
}

// ── Peças compartilhadas ─────────────────────────────────────────────────────

/// Busca (local, ignorando acentos/maiúsculas) + ordenação da lista de
/// favoritos. A ordem escolhida fica salva no aparelho, uma por tela
/// ([prefsKey]).
class _FavoritesBrowser<T> extends StatefulWidget {
  final List<T> items;
  // Ainda marcado com coração — desmarcar tira o item da lista na hora.
  final bool Function(T) isSaved;
  final String searchHint;
  final String Function(T) searchText;
  final List<FavoritesSort> sortOptions;
  final FavoritesSort defaultSort;
  final String prefsKey;
  final String Function(T) name;
  final DateTime? Function(T) savedAt;
  final DateTime? Function(T)? deadline;
  final String Function(int) countLabel;
  final Future<void> Function() onRefresh;
  // Mostrado quando o usuário desmarca todos os itens da lista.
  final Widget empty;
  final Widget Function(T) itemBuilder;

  const _FavoritesBrowser({
    super.key,
    required this.items,
    required this.isSaved,
    required this.searchHint,
    required this.searchText,
    required this.sortOptions,
    required this.defaultSort,
    required this.prefsKey,
    required this.name,
    required this.savedAt,
    this.deadline,
    required this.countLabel,
    required this.onRefresh,
    required this.empty,
    required this.itemBuilder,
  });

  @override
  State<_FavoritesBrowser<T>> createState() => _FavoritesBrowserState<T>();
}

class _FavoritesBrowserState<T> extends State<_FavoritesBrowser<T>> {
  final _searchController = TextEditingController();
  String _query = '';
  late FavoritesSort _sort = widget.defaultSort;

  @override
  void initState() {
    super.initState();
    _loadSort();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSort() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(widget.prefsKey);
      final sort = widget.sortOptions.where((s) => s.name == saved).firstOrNull;
      if (sort != null && mounted) setState(() => _sort = sort);
    } catch (e) {
      print('[Favorites] Não foi possível ler a ordenação salva: $e');
    }
  }

  Future<void> _setSort(FavoritesSort sort) async {
    setState(() => _sort = sort);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(widget.prefsKey, sort.name);
    } catch (e) {
      print('[Favorites] Não foi possível salvar a ordenação: $e');
    }
  }

  /// Datas nulas sempre no fim, qualquer que seja a direção.
  static int _compareDates(DateTime? a, DateTime? b, {bool descending = false}) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return descending ? b.compareTo(a) : a.compareTo(b);
  }

  int _compareNames(T a, T b) => normalizeForSearch(widget.name(a))
      .compareTo(normalizeForSearch(widget.name(b)));

  int _compare(T a, T b) {
    final result = switch (_sort) {
      FavoritesSort.deadline =>
        _compareDates(widget.deadline?.call(a), widget.deadline?.call(b)),
      FavoritesSort.newest =>
        _compareDates(widget.savedAt(a), widget.savedAt(b), descending: true),
      FavoritesSort.oldest => _compareDates(widget.savedAt(a), widget.savedAt(b)),
      FavoritesSort.az => _compareNames(a, b),
      FavoritesSort.za => _compareNames(b, a),
    };
    // Desempate pelo nome (ex: oportunidades sem prazo).
    return result != 0 ? result : _compareNames(a, b);
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Text(
                'Ordenar por',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: kAuthTextDark,
                ),
              ),
            ),
            for (final option in widget.sortOptions)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                title: Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: option == _sort ? FontWeight.w700 : FontWeight.w500,
                    color: option == _sort ? kAuthPink : kAuthTextDark,
                  ),
                ),
                trailing: option == _sort
                    ? const Icon(Icons.check_rounded, color: kAuthPink)
                    : null,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _setSort(option);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // Mesmo visual da barra de busca/botão de filtros do Matcher
  // (opportunity_browser_view.dart): branco, cantos 12 e esta sombra.
  static final _controlDecoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.1),
        blurRadius: 10,
        offset: const Offset(1, 1),
      ),
    ],
  );

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 42,
              decoration: _controlDecoration,
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  hintStyle: TextStyle(fontSize: 13.5, color: Colors.grey[400]),
                  prefixIcon:
                      Icon(Icons.search_rounded, size: 18, color: Colors.grey[400]),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 40, minHeight: 0),
                  suffixIcon: _query.isEmpty
                      ? null
                      : GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          child: Icon(Icons.close_rounded,
                              size: 16, color: Colors.grey[400]),
                        ),
                  suffixIconConstraints:
                      const BoxConstraints(minWidth: 40, minHeight: 0),
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Ordenar',
            child: Container(
              width: 42,
              height: 42,
              decoration: _controlDecoration,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _showSortOptions,
                  splashColor: kAuthPink.withOpacity(0.18),
                  highlightColor: kAuthPink.withOpacity(0.08),
                  child: const Icon(
                    Icons.swap_vert_rounded,
                    size: 20,
                    color: kAuthPink,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FavoritesService.instance,
      builder: (context, _) {
        final saved = widget.items.where(widget.isSaved).toList();
        if (saved.isEmpty) return widget.empty;

        final query = normalizeForSearch(_query.trim());
        final shown = query.isEmpty
            ? saved
            : saved
                .where((item) =>
                    normalizeForSearch(widget.searchText(item)).contains(query))
                .toList();
        shown.sort(_compare);

        final countLabel = query.isEmpty
            ? widget.countLabel(saved.length)
            : (shown.length == 1 ? '1 resultado' : '${shown.length} resultados');

        return Column(
          children: [
            _buildControls(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: widget.onRefresh,
                color: kAuthPink,
                child: ListView(
                  // Sempre rolável — senão o "puxar pra atualizar" não
                  // funciona com poucos itens.
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              countLabel,
                              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                            ),
                          ),
                          // Ordem atual — tocar também abre as opções.
                          GestureDetector(
                            onTap: _showSortOptions,
                            child: Text(
                              _sort.label,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: kAuthPink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 48),
                        child: _EmptyState(
                          icon: Icons.search_off_rounded,
                          message: 'Nenhum resultado para "${_query.trim()}".',
                        ),
                      )
                    else
                      ...shown.map(widget.itemBuilder),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Cabeçalho (voltar + logo + título, mesmo padrão das telas do Perfil) e
/// os estados de carregando/erro/vazio em volta da lista.
class _FavoritesScaffold<T> extends StatelessWidget {
  final String title;
  final Future<List<T>> future;
  final Future<void> Function() onRetry;
  final Widget empty;
  final Widget Function(List<T> items) builder;

  const _FavoritesScaffold({
    required this.title,
    required this.future,
    required this.onRetry,
    required this.empty,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  AuthBackButton(onTap: () => Navigator.of(context).pop()),
                  const Expanded(child: Center(child: AuthLogo(fontSize: 17))),
                  const SizedBox(width: 36),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: kAuthTextDark,
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<T>>(
                future: future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: AppLoadingIndicator());
                  }
                  if (snapshot.hasError) {
                    return _EmptyState(
                      icon: Icons.cloud_off_rounded,
                      message: 'Não foi possível carregar seus favoritos.',
                      action: TextButton(
                        onPressed: onRetry,
                        child: const Text('Tentar novamente'),
                      ),
                    );
                  }
                  final items = snapshot.data ?? [];
                  return items.isEmpty ? empty : builder(items);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Widget? action;

  const _EmptyState({required this.icon, required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[500], height: 1.4),
            ),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}

/// Linha de uma instituição favorita: nome, tipo, endereço e — se houver —
/// quantas oportunidades abertas ela tem (com a estrela do mapa).
class _InstitutionTile extends StatelessWidget {
  final PlaceModel place;
  final VoidCallback onTap;

  const _InstitutionTile({super.key, required this.place, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final count = place.activeOpportunitiesCount;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(
              children: [
                const Icon(Icons.business_rounded, color: kAuthPink),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        place.categoryLabel,
                        style: const TextStyle(fontSize: 12, color: kAuthPink),
                      ),
                      if (place.address != null) ...[
                        const SizedBox(height: 4),
                        // Mesmo pin do endereço no card de oportunidade.
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 13, color: Colors.grey[400]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                place.address!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11.5, color: Colors.grey[500]),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (count > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, size: 14, color: _starColor),
                            const SizedBox(width: 3),
                            Text(
                              count == 1
                                  ? '1 oportunidade aberta'
                                  : '$count oportunidades abertas',
                              style: TextStyle(fontSize: 11.5, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                FavoriteButton.institution(place.osmId!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
