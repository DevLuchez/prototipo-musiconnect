import 'package:flutter/material.dart';
import '../../core/constants.dart';
import 'auth/auth_common.dart';

/// Explica o que é "match" para quem não conhece o termo — aberta pela
/// faixa do Matcher ([MatchExplainerBanner]) e pela aba Matcher do detalhe.
/// Mesmos critérios do FAQ "O que é o percentual de match?" (atualizar
/// junto se a regra mudar).
void showMatchExplanation(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: kAuthPink, size: 22),
                SizedBox(width: 8),
                Text(
                  'O que é match?',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: kAuthTextDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Match é a combinação entre você e uma oportunidade. A '
              'porcentagem mostra o quanto ela combina com o seu perfil: '
              'quanto maior, mais ela tem a ver com você.',
              style: TextStyle(fontSize: 14, color: Colors.grey[700], height: 1.45),
            ),
            const SizedBox(height: 16),
            const Text(
              'O Matcher compara:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: kAuthTextDark,
              ),
            ),
            const SizedBox(height: 10),
            const _Criterion(
              icon: Icons.music_note_rounded,
              text: 'Os instrumentos que você toca com os pedidos no edital',
            ),
            const _Criterion(
              icon: Icons.event_note_rounded,
              text: 'Se você é estudante ou profissional com o tipo da '
                  'oportunidade (curso, audição, emprego, competição)',
            ),
            const _Criterion(
              icon: Icons.location_on_rounded,
              text: 'A sua localização com a da oportunidade',
            ),
            const SizedBox(height: 6),
            Text(
              'Em "Minhas oportunidades" aparecem as que têm '
              '$kHighMatchThreshold% de match ou mais. Para melhorar seus '
              'matches, mantenha o seu Perfil atualizado.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.45),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: kAuthPink,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Entendi',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Criterion extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Criterion({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: kAuthPink.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 15, color: kAuthPink),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                text,
                style: TextStyle(fontSize: 13.5, color: Colors.grey[800], height: 1.35),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Faixa fixa do topo do Matcher (acima das abas): define "match" numa
/// frase e abre a explicação completa ([showMatchExplanation]) ao tocar.
class MatchExplainerBanner extends StatelessWidget {
  const MatchExplainerBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kAuthPink.withOpacity(0.07),
      child: InkWell(
        onTap: () => showMatchExplanation(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 16, color: kAuthPink),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[700], height: 1.3),
                    children: const [
                      TextSpan(
                        text: 'Match ',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: kAuthTextDark,
                        ),
                      ),
                      TextSpan(
                        text: 'é o quanto cada oportunidade combina com o seu perfil.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Saiba mais',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: kAuthPink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
