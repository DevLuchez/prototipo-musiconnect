import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/api_config.dart';
import '../../data/models/opportunity_model.dart';
import '../../data/models/providers/auth_service.dart';
import '../widgets/app_loading_indicator.dart';

const _pink = Color(0xFFEC4899);
const _purple = Color(0xFFDF2881);
const _green = Color(0xFF059669);
// Fundo sólido do card com o título da oportunidade e o percentual — sem
// gradiente.
const _heroColor = Color(0xFF3D2556);

/// Cor da tag de percentual (e do destaque do subcard "Edital") de acordo
/// com o quanto um fator atingiu do seu próprio máximo — mesma faixa usada
/// no anel de match: rosa < 50%, âmbar 50-84%, verde >= 85%.
Color _scoreColor(int earned, int max) {
  if (max <= 0) return Colors.grey;
  final pct = earned / max * 100;
  if (pct >= 85) return _green;
  if (pct >= 50) return const Color(0xFFF59E0B);
  return const Color.fromARGB(255, 236, 72, 72);
}

/// Tela de detalhes de uma oportunidade musical — duas abas arrastáveis
/// (igual ao gesto da tela Matcher): "Informações do Edital" (conteúdo do
/// edital) e "MusiMatch" (comparação do [MatchBreakdown] com o perfil do
/// usuário logado).
class OpportunityDetailScreen extends StatefulWidget {
  final OpportunityModel opportunity;
  final AuthUser user;

  /// Callback para navegar para a aba Mapa (recebido do MainNavigation).
  final VoidCallback? onOpenMap;

  const OpportunityDetailScreen({
    super.key,
    required this.opportunity,
    required this.user,
    this.onOpenMap,
  });

  @override
  State<OpportunityDetailScreen> createState() =>
      _OpportunityDetailScreenState();
}

class _OpportunityDetailScreenState extends State<OpportunityDetailScreen>
    with SingleTickerProviderStateMixin {
  bool _mapSearchLoading = false;
  late final TabController _tabController;

  OpportunityModel get opp => widget.opportunity;
  AuthUser get user => widget.user;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Normalização client-side de instrumentos ───────────────────────────────
  static const _instrumentPt = {
    'violin': 'Violino', 'viola': 'Viola',
    'cello': 'Violoncelo', 'violoncello': 'Violoncelo',
    'double bass': 'Contrabaixo', 'contrabass': 'Contrabaixo', 'bass': 'Contrabaixo',
    'harp': 'Harpa', 'flute': 'Flauta', 'oboe': 'Oboé',
    'clarinet': 'Clarinete', 'bassoon': 'Fagote',
    'horn': 'Trompa', 'french horn': 'Trompa',
    'trumpet': 'Trompete', 'trombone': 'Trombone', 'tuba': 'Tuba',
    'piano': 'Piano', 'organ': 'Órgão',
    'guitar': 'Violão', 'percussion': 'Percussão',
    'voice': 'Vocal', 'singing': 'Vocal', 'singer': 'Vocal',
    'soprano': 'Soprano', 'mezzo-soprano': 'Mezzo-Soprano',
    'alto': 'Contralto', 'tenor': 'Tenor',
    'baritone': 'Barítono',
    'conducting': 'Regência', 'conductor': 'Regência',
    'composition': 'Composição',
    'saxophone': 'Saxofone',
  };

  String _normalizeInstrument(String raw) {
    final key = raw.toLowerCase().trim();
    if (_instrumentPt.containsKey(key)) return _instrumentPt[key]!;
    // Capitaliza a primeira letra de cada palavra
    return raw
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  List<String> get _displayInstruments =>
      opp.instruments.map(_normalizeInstrument).toSet().toList();

  // ── Comparação "seu perfil vs. edital" (aba MusiMatch) ──────────────────

  List<String> get _userAffinityItems {
    final items = <String>[];
    if (user.isStudent) items.add('Estudante');
    if (user.isProfessional) items.add('Profissional');
    return items;
  }

  String get _userLocationLabel {
    final parts = <String>[
      if ((user.city ?? '').isNotEmpty) user.city!,
      if ((user.state ?? '').isNotEmpty) user.state!,
      if ((user.country ?? '').isNotEmpty) user.country!,
    ];
    return parts.isEmpty ? 'Não informado' : parts.join(', ');
  }

  // ── Fluxo de buscar/adicionar instituição no mapa ─────────────────────────

  Future<void> _onMapButtonTapped() async {
    final institution = opp.institution;
    if (institution == null || institution.isEmpty) {
      // Sem instituição identificada → apenas vai para o mapa
      _navigateToMap();
      return;
    }

    setState(() => _mapSearchLoading = true);

    try {
      final uri = Uri.parse(ApiConfig.institutionSearch)
          .replace(queryParameters: {'name': institution});
      final response = await http.get(uri).timeout(const Duration(seconds: 8));

      if (!mounted) return;

      final found = response.statusCode == 200 &&
          (jsonDecode(response.body) as List).isNotEmpty;

      if (found) {
        // Instituição encontrada no mapa → navega
        _navigateToMap(message: '📍 ${institution} encontrada no mapa!');
      } else {
        // Não encontrada → exibe BottomSheet para adicionar
        await _showAddToMapSheet(institution);
      }
    } catch (_) {
      // Falha de rede → vai para o mapa mesmo assim
      if (mounted) _navigateToMap();
    } finally {
      if (mounted) setState(() => _mapSearchLoading = false);
    }
  }

  void _navigateToMap({String? message}) {
    Navigator.of(context).pop();
    widget.onOpenMap?.call();
    if (message != null) {
      // Exibe snackbar após a transição
      Future.delayed(const Duration(milliseconds: 400), () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF059669),
          ),
        );
      });
    }
  }

  Future<void> _showAddToMapSheet(String institutionName) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddToMapSheet(
        institutionName: institutionName,
        city: opp.city,
        country: opp.country,
      ),
    );
    if (result == true && mounted) {
      _navigateToMap(message: '✅ ${institutionName} adicionada ao mapa!');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeaderCard(),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildTabBar(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTabScroll(
                    key: const PageStorageKey('edict'),
                    child: _buildEdictTab(),
                  ),
                  _buildTabScroll(
                    key: const PageStorageKey('musimatch'),
                    child: _buildMusiMatchTab(),
                  ),
                ],
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  /// Card do topo — nome da oportunidade à esquerda, círculo de match à
  /// direita, mesma linha. Sem dinâmica de scroll: fica onde está, normal.
  Widget _buildHeaderCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Stack(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 44, 20, 20),
            decoration: BoxDecoration(
              color: _heroColor,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    opp.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                if (opp.matchPercentage != null)
                  _MatchRing(percentage: opp.matchPercentage!, size: 58)
                else
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.music_note_rounded,
                      size: 28,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
          // Botão de voltar — sobreposto ao card, canto superior esquerdo.
          Positioned(
            top: 0,
            left: 4,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  shape: BoxShape.circle,
                ),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.arrow_back_rounded,
                      size: 20, color: Color(0xFF1F2937)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Abas de verdade (TabController) — dá pra arrastar de uma pra outra,
  /// igual à aba Matcher. Pílula clara com a aba ativa preenchida (rosa
  /// sólido, texto branco), mantendo a fonte e o ícone de brilho já usados.
  Widget _buildTabBar() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: const Color(0xFFFFE6F2),
          borderRadius: BorderRadius.circular(26),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: EdgeInsets.zero,
        dividerColor: Colors.transparent,
        splashBorderRadius: BorderRadius.circular(26),
        labelColor: _purple,
        unselectedLabelColor: Colors.grey[500],
        labelStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        tabs: [
          const Tab(height: 44, text: 'Sobre o Edital'),
          Tab(
            height: 44,
            child: AnimatedBuilder(
              animation: _tabController.animation ?? _tabController,
              builder: (context, _) {
                final t = _tabController.animation?.value ?? _tabController.index.toDouble();
                final active = t.round() == 1;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 14,
                      color: active ? _purple : Colors.grey[500],
                    ),
                    const SizedBox(width: 5),
                    const Text('MusiMatcher'),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabScroll({required Key key, required Widget child}) {
    return SingleChildScrollView(
      key: key,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          child,
          const SizedBox(height: 14),
          // Aviso IA + link fonte
          Center(
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                children: [
                  const TextSpan(
                    text:
                        'O MusiMatcher é uma IA e pode cometer erros.\nVerifique as informações na fonte oficial: ',
                  ),
                  TextSpan(
                    text: opp.sourceLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      color: _pink,
                      fontWeight: FontWeight.w600,
                    ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        if (opp.sourceUrl != null) {
                          _launchUrl(opp.sourceUrl!);
                        }
                      },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Rodapé fixo (fora do scroll): coração (só visual — sem interação,
  /// favoritos fica pra depois) + botão "Saiba mais". Rótulo
  /// deliberadamente não diz "Inscreva-se": o destino às vezes é a página
  /// geral de vagas da instituição (não uma inscrição específica pra este
  /// instrumento/posição), e prometer "inscrição" no botão criaria uma
  /// expectativa que o destino nem sempre cumpre.
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: const Icon(
              Icons.favorite_border_rounded,
              color: _pink,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_purple, _pink],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(26),
              ),
              child: ElevatedButton(
                onPressed:
                    opp.sourceUrl != null ? () => _launchUrl(opp.sourceUrl!) : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Saiba mais'),
                    SizedBox(width: 8),
                    Icon(Icons.open_in_new_rounded, size: 18),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Aba "Informações do Edital" ─────────────────────────────────────────

  Widget _buildEdictTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (opp.description != null && opp.description!.isNotEmpty) ...[
          const _SectionTitle('Descrição do Edital'),
          const SizedBox(height: 8),
          Text(
            opp.description!,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF374151),
              height: 1.6,
            ),
          ),
          const SizedBox(height: 20),
        ],

        const _SectionTitle('Destaques da Oportunidade'),
        const SizedBox(height: 12),

        _HighlightCard(
          icon: Icons.music_note_rounded,
          label: 'INSTRUMENTOS SOLICITADOS',
          child: _displayInstruments.isNotEmpty
              ? Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _displayInstruments
                      .map((inst) => _ProfileStyleChip(label: inst))
                      .toList(),
                )
              : Text(
                  'Não informado',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
        ),
        const SizedBox(height: 12),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildSimpleHighlight(
                icon: Icons.event_note_rounded,
                label: 'TIPO',
                value: opp.typeLabel,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _buildDeadlineHighlight()),
          ],
        ),
        const SizedBox(height: 12),

        // Instituição e Localização ficam uma abaixo da outra (em vez de
        // lado a lado) — a Localização pode ter uma segunda linha ("Ver no
        // mapa"), então precisa da largura toda pra caber direito.
        _buildSimpleHighlight(
          icon: Icons.account_balance_rounded,
          label: 'INSTITUIÇÃO',
          value: opp.institution?.isNotEmpty == true
              ? opp.institution!
              : 'Não informada',
        ),
        const SizedBox(height: 12),
        _buildLocationHighlight(),

        if (opp.isRemote) ...[
          const SizedBox(height: 12),
          _buildSimpleHighlight(
            icon: Icons.wifi_rounded,
            label: 'MODALIDADE',
            value: 'Remoto',
            valueColor: _green,
          ),
        ],

        // Conteúdo completo
        if (opp.rawText != null &&
            opp.rawText!.length > (opp.description?.length ?? 0) + 20) ...[
          const SizedBox(height: 20),
          const _SectionTitle('Conteúdo completo'),
          const SizedBox(height: 8),
          _ExpandableText(text: opp.rawText!),
        ],
      ],
    );
  }

  Widget _buildSimpleHighlight({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return _HighlightCard(
      icon: icon,
      label: label,
      child: Text(
        value,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: valueColor ?? const Color(0xFF111827),
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Prazo com menos de 7 dias até hoje (e ainda não vencido) → destaque.
  bool _isDeadlineUrgent(DateTime deadline) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(deadline.year, deadline.month, deadline.day);
    final diff = day.difference(today).inDays;
    return diff >= 0 && diff < 7;
  }

  Widget _buildDeadlineHighlight() {
    final deadline = opp.deadline;
    final urgent = deadline != null && _isDeadlineUrgent(deadline);
    final value =
        deadline != null ? 'Até ${_fmtDate(deadline)}' : 'Não informado';
    return _buildSimpleHighlight(
      icon: Icons.access_time_rounded,
      label: 'PRAZO',
      value: value,
      valueColor: urgent ? Colors.red : null,
    );
  }

  Widget _buildLocationHighlight() {
    final showMapLink = !opp.isRemote && widget.onOpenMap != null;
    return _HighlightCard(
      icon: Icons.location_on_rounded,
      label: 'LOCALIZAÇÃO',
      trailing: showMapLink
          ? GestureDetector(
              onTap: _mapSearchLoading ? null : _onMapButtonTapped,
              child: _mapSearchLoading
                  ? const AppLoadingIndicator(size: 12, color: _purple)
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_on_rounded, size: 12, color: _purple),
                        SizedBox(width: 3),
                        Text(
                          'Ver no mapa',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: _purple,
                          ),
                        ),
                      ],
                    ),
            )
          : null,
      child: Text(
        opp.locationLabel,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF111827),
        ),
      ),
    );
  }

  // ── Aba "MusiMatch" ──────────────────────────────────────────────────────

  Widget _buildMusiMatchTab() {
    final b = opp.matchBreakdown;
    if (b == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'Compatibilidade indisponível no momento.',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ),
      );
    }

    final rawConfidence = (opp.llmConfidence * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [_purple, _pink],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ).createShader(bounds),
                    child: const Text(
                      'COMPATIBILIDADE MUSICAL',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Seu Perfil vs. Edital',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${opp.matchPercentage}%',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: _pink,
                  ),
                ),
                Text(
                  'MATCH TOTAL',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[400],
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        _ComparisonCard(
          icon: Icons.music_note_rounded,
          title: 'Instrumentos',
          description: 'Compara os instrumentos do seu perfil com os exigidos pelo edital',
          accentColor: _purple,
          earned: b.instrument,
          max: b.instrumentMax,
          yourLabel: 'SEUS INSTRUMENTOS',
          yourValue: _bulletText(user.instruments),
          edictLabel: 'EDITAL',
          edictValue: _bulletText(_displayInstruments),
        ),
        const SizedBox(height: 12),

        _ComparisonCard(
          icon: Icons.event_note_rounded,
          title: 'Tipo de Oportunidade',
          description: 'Compara seu ramo de atuação com o tipo desta oportunidade',
          accentColor: _green,
          earned: b.affinity,
          max: b.affinityMax,
          yourLabel: 'SEU RAMO DE ATUAÇÃO',
          yourValue: _bulletText(_userAffinityItems),
          edictLabel: 'EDITAL',
          edictValue: _bulletText([opp.typeLabel]),
        ),
        const SizedBox(height: 12),

        _ComparisonCard(
          icon: Icons.location_on_rounded,
          title: 'Localização',
          description: 'Compara sua localização com a do edital',
          accentColor: _pink,
          earned: b.location,
          max: b.locationMax,
          yourLabel: 'SUA LOCALIZAÇÃO',
          yourValue: _bulletText([_userLocationLabel]),
          edictLabel: 'EDITAL',
          edictValue: _bulletText([opp.locationLabel]),
        ),
        const SizedBox(height: 12),

        // Mesmo card padrão dos três de cima, só que sem os subcards de
        // comparação (não é "seu perfil vs. edital", é uma nota de
        // qualidade do dado).
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFF3F4F6)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'MusiMatch AI avaliou este edital com $rawConfidence% de confiança',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.4),
                ),
              ),
              const SizedBox(width: 8),
              _PercentPill(
                earned: b.confidence,
                max: b.confidenceMax,
                color: _scoreColor(b.confidence, b.confidenceMax),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Vários itens separados pela mesma bolinha "•" usada no card de
  /// oportunidades do Matcher, em vez de vírgula.
  Widget _bulletText(List<String> items) {
    final clean = items.where((s) => s.trim().isNotEmpty).toList();
    if (clean.isEmpty) {
      return const Text(
        'Não informado',
        style: TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.4),
      );
    }
    final spans = <InlineSpan>[];
    for (var i = 0; i < clean.length; i++) {
      if (i > 0) {
        spans.add(TextSpan(text: '  •  ', style: TextStyle(color: Colors.grey[400])));
      }
      spans.add(TextSpan(text: clean[i]));
    }
    return Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.4),
        children: spans,
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o link.')),
      );
    }
  }
}

// ── BottomSheet: adicionar instituição ao mapa ─────────────────────────────

class _AddToMapSheet extends StatefulWidget {
  final String institutionName;
  final String? city;
  final String? country;

  const _AddToMapSheet({
    required this.institutionName,
    this.city,
    this.country,
  });

  @override
  State<_AddToMapSheet> createState() => _AddToMapSheetState();
}

class _AddToMapSheetState extends State<_AddToMapSheet> {
  bool _loading = false;
  String? _error;

  Future<void> _addToMap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final body = jsonEncode({
        'name': widget.institutionName,
        'city': widget.city,
        'country': widget.country,
        'category': 'music',
      });
      final response = await http
          .post(
            Uri.parse(ApiConfig.institutionCreate),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode == 201 || response.statusCode == 200) {
        Navigator.of(context).pop(true); // sucesso
      } else {
        final msg = jsonDecode(response.body)['detail'] ?? 'Erro desconhecido';
        setState(() => _error = msg.toString());
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Falha de conexão. Tente novamente.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'Instituição não encontrada no mapa',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: const TextStyle(
                  fontSize: 13, color: Color(0xFF6B7280), height: 1.5),
              children: [
                const TextSpan(text: ''),
                TextSpan(
                  text: widget.institutionName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                const TextSpan(
                  text:
                      ' ainda não está cadastrada no mapa do MusiConnect.\n\nDeseja adicioná-la? Vamos geocodificar o endereço automaticamente usando OpenStreetMap.',
                ),
              ],
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          ],

          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Agora não',
                    style: TextStyle(color: Color(0xFF6B7280)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _loading ? null : _addToMap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _loading
                      ? const AppLoadingIndicator(size: 18, color: Colors.white)
                      : const Text(
                          'Adicionar ao mapa',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
        ],
      ),
    );
  }
}

// ── Widgets auxiliares ──────────────────────────────────────────────────────

/// Chip de instrumento — mesmo estilo do `_InfoChip` da tela de Perfil
/// (`profile_screen.dart`): pílula clara com borda, texto na cor cheia.
class _ProfileStyleChip extends StatelessWidget {
  final String label;
  const _ProfileStyleChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _purple.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _purple.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _purple),
      ),
    );
  }
}

/// Card de destaque (aba "Informações do Edital"): ícone + rótulo pequeno +
/// conteúdo livre (texto, chips, etc.).
class _HighlightCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;
  // Widget opcional no canto superior direito, mesma linha do label (ex:
  // "Ver no mapa" no card de Localização).
  final Widget? trailing;

  const _HighlightCard({
    required this.icon,
    required this.label,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3F4F6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: _purple),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[500],
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// Card de comparação (aba "MusiMatch"): ícone + título + pill de pontos,
/// duas colunas ("seus dados" vs "edital"), cada uma dentro de um card
/// interno (não só texto solto).
class _ComparisonCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color accentColor;
  final int earned;
  final int max;
  final String yourLabel;
  final Widget yourValue;
  final String edictLabel;
  final Widget edictValue;

  const _ComparisonCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.accentColor,
    required this.earned,
    required this.max,
    required this.yourLabel,
    required this.yourValue,
    required this.edictLabel,
    required this.edictValue,
  });

  @override
  Widget build(BuildContext context) {
    // Cor da tag de pontos — de acordo com o percentual atingido nesse
    // fator, não a cor fixa do card — e reaproveitada no subcard "Edital"
    // pra dar destaque (mesma cor nos dois, reforça a leitura do porquê).
    final scoreColor = _scoreColor(earned, max);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3F4F6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accentColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              _PercentPill(earned: earned, max: max, color: scoreColor),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(fontSize: 11.5, color: Colors.grey[500], height: 1.3),
          ),
          const SizedBox(height: 12),
          // Seus dados e os do edital ficam um abaixo do outro (em vez de
          // lado a lado) pra caber listas maiores (ex: vários instrumentos)
          // sem espremer o texto.
          _ComparisonColumn(label: yourLabel, value: yourValue),
          const SizedBox(height: 8),
          _ComparisonColumn(label: edictLabel, value: edictValue, accentColor: scoreColor),
        ],
      ),
    );
  }
}

class _ComparisonColumn extends StatelessWidget {
  final String label;
  final Widget value;
  // Quando definido, destaca o subcard com essa cor (usado no "Edital",
  // pra reforçar de onde vem a tag de pontos do card).
  final Color? accentColor;
  const _ComparisonColumn({required this.label, required this.value, this.accentColor});

  @override
  Widget build(BuildContext context) {
    final color = accentColor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color != null ? color.withOpacity(0.08) : const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color != null ? color.withOpacity(0.35) : const Color(0xFFF3F4F6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color ?? Colors.grey[500],
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          value,
        ],
      ),
    );
  }
}

/// Pill "{earned}% / {max}%" — pontos ganhos de um fator, do máximo dele
/// (pesos diferentes por fator, não uma fração de 100 cada).
class _PercentPill extends StatelessWidget {
  final int earned;
  final int max;
  final Color color;

  const _PercentPill({required this.earned, required this.max, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$earned% / $max%',
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

/// Círculo com preenchimento transparente (mostra o gradiente do card por
/// trás), percentual de match no centro em branco, e um contorno colorido
/// de acordo com a faixa do percentual (rosa < 50%, âmbar 50-84%, verde
/// >= 85% — mesmo corte usado pra "Minhas oportunidades") que preenche
/// proporcionalmente a partir do topo no sentido horário (ex: 50% vai do
/// centro superior até o centro inferior).
class _MatchRing extends StatelessWidget {
  final int percentage;
  final double size;
  const _MatchRing({required this.percentage, this.size = 72});

  Color get _ringColor {
    if (percentage >= 85) return _green;
    if (percentage >= 50) return const Color(0xFFF59E0B);
    return const Color.fromARGB(255, 236, 72, 72);
  }

  @override
  Widget build(BuildContext context) {
    final strokeWidth = size / 16;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(size, size),
                painter: _MatchRingPainter(percentage / 100, strokeWidth, _ringColor),
              ),
              Text(
                '$percentage%',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: size * 0.26,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'MATCH',
          style: TextStyle(
            color: Colors.white.withOpacity(0.85),
            fontSize: 8,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _MatchRingPainter extends CustomPainter {
  final double fraction;
  final double strokeWidth;
  final Color color;
  const _MatchRingPainter(this.fraction, this.strokeWidth, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;

    // Trilha do anel (contorno completo, translúcida) — sem disco de fundo,
    // o preenchimento é transparente (mostra o gradiente do card atrás).
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    // Progresso — cor de acordo com a faixa do percentual, começa no topo
    // (12h) e vai no sentido horário.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * fraction.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_MatchRingPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.color != color;
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1F2937),
        ),
      );
}

class _ExpandableText extends StatefulWidget {
  final String text;
  const _ExpandableText({required this.text});

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    const maxChars = 400;
    final isLong = widget.text.length > maxChars;
    final display = _expanded || !isLong
        ? widget.text
        : '${widget.text.substring(0, maxChars)}...';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          display,
          style: const TextStyle(
            fontSize: 13.5,
            color: Color(0xFF4B5563),
            height: 1.6,
          ),
        ),
        if (isLong) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              _expanded ? 'Ver menos' : 'Ver mais',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _pink,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
