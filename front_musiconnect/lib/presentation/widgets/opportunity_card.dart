import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../data/models/opportunity_model.dart';
import 'favorite_button.dart';

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
        return const Color(0xFF7C3AED); // roxo (kAuthPurple)
      case 'emprego':
        return const Color(0xFF2563EB); // azul
      default:
        return const Color(0xFF6B7280);
    }
  }
}

/// Cor de cada tipo de oportunidade (badge do card, faixa do card compacto,
/// blocos "Explorar" do Início).
Color opportunityTypeColor(String? type) => _MatcherTheme.typeColor(type);

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
  // Percentual de compatibilidade com o usuário logado (0-100) — null
  // esconde a tag (ex: sem sessão, backend não calculou).
  final int? matchPercentage;
  // Coração de salvar no canto inferior direito.
  final bool showFavorite;

  const OpportunityCard({
    super.key,
    required this.opportunity,
    required this.onTap,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    this.expandToFill = false,
    this.matchPercentage,
    this.showFavorite = true,
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
              // ── Linha superior: match (esquerda) + prazo (direita) ──
              Row(
                children: [
                  if (matchPercentage != null) _buildMatchTag(),
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
              // Coração à direita, centralizado na altura das duas últimas
              // linhas (tipo/instrumentos + endereço) — não aumenta o card.
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Uma linha só (nunca quebra): no carrossel o card
                        // tem altura fixa e uma segunda linha de chips o
                        // estourava. Nome de instrumento longo é abreviado
                        // com "…" só quando não cabe.
                        Row(
                          children: [
                            // Badge de tipo (Edital, Curso, etc.)
                            _TypeBadge(
                              type: opportunity.typeLabel,
                              color: _MatcherTheme.typeColor(opportunity.type),
                            ),
                            const SizedBox(width: 6),
                            // Separador (mesmo "•" usado no resumo de filtros)
                            Text('•',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[400])),
                            const SizedBox(width: 6),
                            if (opportunity.instruments.isNotEmpty) ...[
                              ...opportunity.instruments.take(2).map(
                                    (inst) => Flexible(
                                      child: Container(
                                        margin: const EdgeInsets.only(right: 6),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF3F4F6),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          inst,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            color: Color(0xFF4B5563),
                                            fontWeight: FontWeight.w500,
                                          ),
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
                              Flexible(
                                child: Text(
                                  'Instrumentos não informados',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[400],
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        // ── Rodapé: endereço ────────────────────────────
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined,
                                size: 13, color: Colors.grey[400]),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                opportunity.locationLabel,
                                style: TextStyle(
                                    fontSize: 11.5, color: Colors.grey[500]),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (showFavorite) ...[
                    const SizedBox(width: 4),
                    FavoriteButton.opportunity(opportunity.id),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMatchTag() {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _MatcherTheme.purple.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$matchPercentage% de match',
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: _MatcherTheme.purple,
        ),
      ),
    );
  }

  Widget _buildDeadline() {
    final deadline = opportunity.deadline;
    final urgent = deadline != null && isDeadlineUrgent(deadline);
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

// ── Prazo: regras compartilhadas (card, card compacto e destaque do Início) ──

/// Data sem horário (o prazo é um dia, não um instante).
DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Dias até o prazo (0 = hoje, negativo = já venceu).
int _daysUntil(DateTime deadline) =>
    _dayOnly(deadline).difference(_dayOnly(DateTime.now())).inDays;

/// Prazo com menos de [kUrgentDeadlineDays] dias até hoje (e ainda não
/// vencido) → destaque em vermelho.
bool isDeadlineUrgent(DateTime deadline) {
  final diff = _daysUntil(deadline);
  return diff >= 0 && diff < kUrgentDeadlineDays;
}

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Prazo em poucas palavras: relativo quando é urgente ("Fecha amanhã"),
/// data quando não ("Até 25/10/2026").
String deadlineShortLabel(DateTime? deadline) {
  if (deadline == null) return 'Prazo não informado';
  if (!isDeadlineUrgent(deadline)) return 'Até ${_formatDate(deadline)}';
  return switch (_daysUntil(deadline)) {
    0 => 'Fecha hoje',
    1 => 'Fecha amanhã',
    final n => 'Fecha em $n dias',
  };
}

/// Card enxuto dos carrosséis do Início: faixa na cor do tipo, tipo + % de
/// match, título e prazo — sem descrição/instrumentos/local (o detalhe
/// está a um toque). Precisa de largura/altura fixas vindas de fora.
class OpportunityCompactCard extends StatelessWidget {
  final OpportunityModel opportunity;
  final VoidCallback onTap;
  final EdgeInsetsGeometry margin;

  const OpportunityCompactCard({
    super.key,
    required this.opportunity,
    required this.onTap,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final opp = opportunity;
    final typeColor = _MatcherTheme.typeColor(opp.type);
    final match = opp.matchPercentage;
    final urgent = opp.deadline != null && isDeadlineUrgent(opp.deadline!);

    return Container(
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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: _MatcherTheme.pink.withOpacity(0.12),
          highlightColor: _MatcherTheme.pink.withOpacity(0.05),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Faixa na cor do tipo — identifica a categoria de relance.
              Container(height: 5, color: typeColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Row(
                          children: [
                            _TypeBadge(type: opp.typeLabel, color: typeColor),
                            const Spacer(),
                            if (match != null)
                              Text(
                                '$match%',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: _MatcherTheme.purple,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          opp.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F2937),
                            height: 1.3,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 13,
                            color: urgent ? Colors.red[800] : Colors.grey[400],
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              deadlineShortLabel(opp.deadline),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: urgent ? FontWeight.w700 : FontWeight.w500,
                                color: urgent ? Colors.red[800] : Colors.grey[500],
                              ),
                            ),
                          ),
                          FavoriteButton.opportunity(opp.id),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
