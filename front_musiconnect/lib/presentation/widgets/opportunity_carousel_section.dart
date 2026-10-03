import 'package:flutter/material.dart';
import '../../data/models/opportunity_model.dart';
import 'opportunity_card.dart';

const _pink = Color(0xFFEC4899);

/// Seção de carrossel horizontal com uma prévia das oportunidades de uma
/// categoria (tipo), usada dentro da aba "Todas as oportunidades" e no
/// Início. Tocar no cabeçalho leva pra lista completa — sem [onSeeAll], o
/// "Ver todas" não aparece.
class OpportunityCarouselSection extends StatelessWidget {
  final String title;
  // Linha menor abaixo do título (ex: "Prazos se aproximando" no Início).
  final String? subtitle;
  final int total;
  final List<OpportunityModel> items;
  final VoidCallback? onSeeAll;
  final ValueChanged<OpportunityModel> onCardTap;
  // Cards enxutos e mais estreitos (OpportunityCompactCard) — usado no
  // Início; o Matcher usa o card completo.
  final bool compact;

  const OpportunityCarouselSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.total,
    required this.items,
    this.onSeeAll,
    required this.onCardTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: GestureDetector(
            onTap: onSeeAll,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(fontSize: 12.5, color: Colors.grey[500]),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onSeeAll != null) ...[
                  Text(
                    'Ver todas ($total)',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _pink,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      size: 16, color: _pink),
                ],
              ],
            ),
          ),
        ),
        SizedBox(
          // Altura generosa o bastante pro card não ficar espremido — na
          // lista vertical a altura era livre (o Column só cresce conforme
          // o conteúdo); aqui precisa de um valor fixo porque é uma lista
          // horizontal, então damos folga de sobra em vez de cortar rente.
          height: compact ? 176 : 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 16, right: 6),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final opp = items[index];
              if (compact) {
                return SizedBox(
                  // Estreito o bastante pra mostrar o próximo card pela
                  // metade — indica que dá pra arrastar.
                  width: 210,
                  child: OpportunityCompactCard(
                    opportunity: opp,
                    margin: const EdgeInsets.only(right: 12, bottom: 8, top: 2),
                    onTap: () => onCardTap(opp),
                  ),
                );
              }
              return SizedBox(
                // Mesma largura que o card tinha na lista vertical (tela
                // inteira menos a margem de 16 de cada lado).
                width: MediaQuery.of(context).size.width - 32,
                child: OpportunityCard(
                  opportunity: opp,
                  matchPercentage: opp.matchPercentage,
                  margin: const EdgeInsets.only(right: 12, bottom: 6, top: 2),
                  onTap: () => onCardTap(opp),
                  // Altura do card aqui é fixa (o SizedBox acima) — gruda
                  // instrumentos+endereço no fundo em vez de deixar espaço
                  // em branco embaixo quando título/descrição são curtos.
                  expandToFill: true,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
