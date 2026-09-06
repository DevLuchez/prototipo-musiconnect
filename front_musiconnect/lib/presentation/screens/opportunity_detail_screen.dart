import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/api_config.dart';
import '../../data/models/opportunity_model.dart';

const _pink = Color(0xFFEC4899);
const _purple = Color(0xFFDF2881);

/// Tela de detalhes de uma oportunidade musical.
class OpportunityDetailScreen extends StatefulWidget {
  final OpportunityModel opportunity;

  /// Callback para navegar para a aba Mapa (recebido do MainNavigation).
  final VoidCallback? onOpenMap;

  const OpportunityDetailScreen({
    super.key,
    required this.opportunity,
    this.onOpenMap,
  });

  @override
  State<OpportunityDetailScreen> createState() =>
      _OpportunityDetailScreenState();
}

class _OpportunityDetailScreenState extends State<OpportunityDetailScreen> {
  bool _mapSearchLoading = false;

  OpportunityModel get opp => widget.opportunity;

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
      backgroundColor: const Color(0xFFF8F8FA),
      body: CustomScrollView(
        slivers: [
          // ── SliverAppBar com gradiente ──────────────────────────
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
            leading: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back_rounded,
                    color: Color(0xFF1F2937)),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.25),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.music_note_rounded,
                            size: 40,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            opp.sourceLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Conteúdo ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Título
                  Text(
                    opp.title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                      height: 1.3,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Descrição
                  if (opp.description != null &&
                      opp.description!.isNotEmpty) ...[
                    const _SectionTitle('Descrição'),
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

                  // ── Informações ──────────────────────────────────────
                  // Ordem: Prazo → Tipo → Instrumentos → Instituição → Endereço
                  // (sem container/cartão — segue no fluxo junto da descrição)
                  _buildDeadlineInfo(),
                  const SizedBox(height: 20),
                  _InfoRow(
                    label: 'Tipo de evento',
                    value: opp.typeLabel,
                  ),
                  const SizedBox(height: 20),
                  _InstrumentsRow(instruments: _displayInstruments),
                  const SizedBox(height: 20),
                  _InfoRow(
                    label: 'Instituição',
                    value: opp.institution?.isNotEmpty == true
                        ? opp.institution!
                        : 'Instituição não informada',
                  ),
                  const SizedBox(height: 20),
                  _AddressRow(
                    locationLabel: opp.locationLabel,
                    isRemote: opp.isRemote,
                    loading: _mapSearchLoading,
                    onMapTap:
                        widget.onOpenMap != null ? _onMapButtonTapped : null,
                  ),
                  if (opp.isRemote) ...[
                    const SizedBox(height: 20),
                    _InfoRow(
                      label: 'Modalidade',
                      value: 'Remoto',
                      valueColor: const Color(0xFF059669),
                    ),
                  ],

                  // Conteúdo completo
                  if (opp.rawText != null &&
                      opp.rawText!.length >
                          (opp.description?.length ?? 0) + 20) ...[
                    const SizedBox(height: 20),
                    const _SectionTitle('Conteúdo completo'),
                    const SizedBox(height: 8),
                    _ExpandableText(text: opp.rawText!),
                  ],

                  const SizedBox(height: 32),

                  // Botão "Saiba mais" — abre a página da fonte (Musical
                  // Chairs). Rótulo deliberadamente não diz "Inscreva-se":
                  // o destino às vezes é a página geral de vagas da
                  // instituição (não uma inscrição específica pra este
                  // instrumento/posição), e prometer "inscrição" no botão
                  // criaria uma expectativa que o destino nem sempre cumpre.
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: opp.sourceUrl != null
                          ? () => _launchUrl(opp.sourceUrl!)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _pink,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
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

                  const SizedBox(height: 16),

                  // Aviso IA + link fonte
                  Center(
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style:
                            TextStyle(fontSize: 11, color: Colors.grey[400]),
                        children: [
                          const TextSpan(
                            text:
                                'O MusiConnect é uma IA e pode cometer erros.\nVerifique as informações na fonte oficial: ',
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

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
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

  Widget _buildDeadlineInfo() {
    final deadline = opp.deadline;
    final urgent = deadline != null && _isDeadlineUrgent(deadline);
    final value =
        deadline != null ? 'Até ${_fmtDate(deadline)}' : 'Prazo não informado';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Prazo de inscrição'),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            color: urgent ? Colors.red : const Color(0xFF374151),
            fontWeight: urgent ? FontWeight.w700 : FontWeight.w400,
            height: 1.6,
          ),
        ),
      ],
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
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
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

/// Seção com label no topo (estilo igual ao de "Descrição") e valor abaixo.
class _InfoRow extends StatelessWidget {
  final String label;
  final String? value;
  final Color? valueColor;
  const _InfoRow({
    required this.label,
    this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(label),
          const SizedBox(height: 8),
          Text(
            value ?? '—',
            style: TextStyle(
              fontSize: 14,
              color: valueColor ?? const Color(0xFF374151),
              height: 1.6,
            ),
          ),
        ],
      );
}

/// Linha de instrumentos com chips.
class _InstrumentsRow extends StatelessWidget {
  final List<String> instruments;
  const _InstrumentsRow({required this.instruments});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Instrumentos'),
          const SizedBox(height: 8),
          if (instruments.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: instruments
                  .map(
                    (inst) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _purple.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        inst,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _purple,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            )
          else
            const Text(
              'Não informado',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF374151),
                height: 1.6,
              ),
            ),
        ],
      );
}

/// Linha de endereço com botão "Mapa" vertical.
class _AddressRow extends StatelessWidget {
  final String locationLabel;
  final bool isRemote;
  final bool loading;
  final VoidCallback? onMapTap;
  const _AddressRow({
    required this.locationLabel,
    required this.isRemote,
    required this.loading,
    this.onMapTap,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('Endereço'),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  locationLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF374151),
                    height: 1.6,
                  ),
                ),
              ),
              if (!isRemote && onMapTap != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: loading ? null : onMapTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _purple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _purple.withOpacity(0.3)),
                    ),
                    child: loading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              color: _purple,
                              strokeWidth: 2,
                            ),
                          )
                        : const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.location_on_rounded,
                                  size: 13, color: _purple),
                              SizedBox(width: 4),
                              Text(
                                'Ver no mapa',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _purple,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ],
          ),
        ],
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
