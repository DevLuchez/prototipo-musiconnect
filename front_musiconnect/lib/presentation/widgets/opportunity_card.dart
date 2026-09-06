import 'package:flutter/material.dart';
import '../../data/models/opportunity_model.dart';

/// Cores e utilitários de estilo da aba Matcher.
class _MatcherTheme {
  static const pink = Color(0xFFEC4899);
  static const purple = Color(0xFFDF2881);
  static const cardBg = Colors.white;
  static const pageBg = Color(0xFFF8F8FA);

  static Color sourceColor(String? source) {
    // Musical Chairs é a fonte principal — verde distinto
    return const Color(0xFF059669);
  }

  static Color typeColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'curso':
        return const Color(0xFF059669);
      case 'competicao':
      case 'competição':
        return const Color(0xFFF59E0B); // âmbar
      case 'audicao':
      case 'audição':
        return const Color(0xFFDF2881); // roxo
      case 'emprego':
        return const Color(0xFF2563EB); // azul
      default:
        return const Color(0xFF6B7280);
    }
  }
}

/// Card de oportunidade usado na listagem "Todas as oportunidades".
class OpportunityCard extends StatelessWidget {
  final OpportunityModel opportunity;
  final VoidCallback onTap;
  final EdgeInsetsGeometry margin;
  // Quando o card está numa altura fixa (ex: carrossel horizontal), gruda
  // instrumentos+endereço no fundo do card, com a folga (se o título/
  // descrição forem curtos) absorvida logo acima desse grupo — em vez de
  // sobrar espaço em branco embaixo de tudo. Só funciona com altura fixa
  // vinda de fora; na lista vertical (altura livre) fica desligado.
  final bool expandToFill;

  const OpportunityCard({
    super.key,
    required this.opportunity,
    required this.onTap,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    this.expandToFill = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: margin,
        decoration: BoxDecoration(
          color: _MatcherTheme.cardBg,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: expandToFill ? MainAxisSize.max : MainAxisSize.min,
            children: [
              // ── Linha superior: prazo (alinhado à direita) ──────
              Row(
                children: [
                  const Spacer(),
                  _buildDeadline(),
                ],
              ),
              const SizedBox(height: 10),

              // ── Título ───────────────────────────────────────────
              Text(
                opportunity.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                  height: 1.35,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              // ── Descrição ────────────────────────────────────────
              if (opportunity.description != null &&
                  opportunity.description!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  opportunity.description!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // Folga entre a descrição e o grupo instrumentos+endereço —
              // se título/descrição forem curtos, é aqui que o espaço
              // sobrando fica, em vez de embaixo do endereço.
              if (expandToFill) const Expanded(child: SizedBox()),

              // ── Instrumentos (chips) + separador + tipo ─────────
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Badge de tipo (Edital, Curso, etc.)
                  _TypeBadge(
                    type: opportunity.typeLabel,
                    color: _MatcherTheme.typeColor(opportunity.type),
                  ),
                  // Separador (mesmo "•" usado no resumo de filtros)
                  Text('•', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                  if (opportunity.instruments.isNotEmpty) ...[
                    ...opportunity.instruments.take(2).map(
                      (inst) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          inst,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF4B5563),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    if (opportunity.instruments.length > 2)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '+${opportunity.instruments.length - 2}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Color(0xFF9CA3AF),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ] else
                    Text(
                      'Instrumentos não informados',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[400],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 10),

              // ── Rodapé: endereço ────────────────────────────
              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 13, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      opportunity.locationLabel,
                      style: TextStyle(fontSize: 11.5, color: Colors.grey[500]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  /// Prazo com menos de 7 dias até hoje (e ainda não vencido) → destaque.
  bool _isDeadlineUrgent(DateTime deadline) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(deadline.year, deadline.month, deadline.day);
    final diff = day.difference(today).inDays;
    return diff >= 0 && diff < 7;
  }

  Widget _buildDeadline() {
    final deadline = opportunity.deadline;
    final urgent = deadline != null && _isDeadlineUrgent(deadline);
    final text = deadline != null
        ? 'Até ${_formatDate(deadline)}'
        : 'Prazo não informado';

    // Padding/borda calibrados pra fechar na mesma altura do _TypeBadge
    // (padding vertical 3 + sem borda) — senão o Row do topo cresce e o
    // card estoura a altura fixa do carrossel (expandToFill).
    if (urgent) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: Colors.red,
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.access_time_rounded, size: 11, color: Colors.grey[400]),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
      ],
    );
  }
}

/// Badge da fonte da oportunidade (DOU, Funarte...).
class _SourceBadge extends StatelessWidget {
  final String source;
  const _SourceBadge({required this.source});

  @override
  Widget build(BuildContext context) {
    final color = _MatcherTheme.sourceColor(source);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        source,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Badge do tipo da oportunidade (Edital, Curso...).
class _TypeBadge extends StatelessWidget {
  final String type;
  final Color color;
  const _TypeBadge({required this.type, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        type,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
