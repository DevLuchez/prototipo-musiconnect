import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../widgets/auth/auth_common.dart';

/// Pergunta frequente da tela de ajuda.
class _Faq {
  final String question;
  final String answer;
  const _Faq(this.question, this.answer);
}

// Respostas descrevem o comportamento real do app — atualizar junto se a
// regra mudar (ex: corte de match, fontes de oportunidades).
const _faqs = [
  _Faq(
    'O que é o percentual de match?',
    'É o quanto uma oportunidade combina com o seu perfil, de 0 a 100%. '
        'Ele compara os instrumentos que você toca com os exigidos, se você é '
        'estudante ou profissional com o tipo da oportunidade (curso, audição, '
        'emprego, competição) e a sua localização com a da oportunidade. '
        'Em "Minhas oportunidades" aparecem as que têm $kHighMatchThreshold% '
        'ou mais.',
  ),
  _Faq(
    'Como melhorar os meus matches?',
    'Mantenha o seu perfil atualizado: instrumentos, ramo de atuação '
        '(estudante/profissional) e localização. Toque em Perfil → Editar '
        'para alterar. O número de Matches do Perfil é recalculado na hora.',
  ),
  _Faq(
    'De onde vêm as oportunidades?',
    'São coletadas automaticamente de fontes públicas de vagas e editais de '
        'música e organizadas pelo MusiConnect. O MusiConnect não faz '
        'inscrições: o botão "Saiba mais" leva à página original, onde a '
        'inscrição é feita.',
  ),
  _Faq(
    'Por que uma oportunidade sumiu dos meus salvos?',
    'Quando o prazo de inscrição termina, a oportunidade sai das listas do '
        'app, inclusive dos salvos — não há mais como se inscrever nela.',
  ),
  _Faq(
    'O que significa a estrela no mapa?',
    'Um pino com estrela é uma instituição com oportunidades abertas. A '
        'bolinha rosa com estrela reúne as oportunidades de uma cidade cuja '
        'instituição organizadora não tem endereço exato no mapa.',
  ),
  _Faq(
    'Como salvar oportunidades e instituições?',
    'Toque no coração — no card ou no detalhe de uma oportunidade, ou no '
        'detalhe de uma instituição do mapa. Os salvos ficam no menu lateral '
        'e também podem ser abertos pelos números do Perfil.',
  ),
  _Faq(
    'Encontrei uma informação errada. O que faço?',
    'Use o "Fale conosco" abaixo e conte qual oportunidade ou instituição '
        'está errada — isso ajuda a melhorar os dados para todo mundo.',
  ),
];

/// Ajuda e suporte — aberta pelo menu lateral: perguntas frequentes e um
/// "Fale conosco" que abre o app de e-mail.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  Future<void> _contactUs(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: kSupportEmail,
      query: 'subject=${Uri.encodeComponent('MusiConnect — Ajuda')}',
    );
    final messenger = ScaffoldMessenger.of(context);
    final opened = await launchUrl(uri).catchError((_) => false);
    if (opened) return;
    // Sem app de e-mail configurado: copia o endereço pra pessoa colar.
    await Clipboard.setData(const ClipboardData(text: kSupportEmail));
    messenger.showSnackBar(const SnackBar(
      content: Text('Nenhum app de e-mail encontrado. Endereço copiado: $kSupportEmail'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Row(
              children: [
                AuthBackButton(onTap: () => Navigator.of(context).pop()),
                const Expanded(child: Center(child: AuthLogo(fontSize: 17))),
                const SizedBox(width: 36),
              ],
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 20, 4, 4),
              child: Text(
                'Ajuda e suporte',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: kAuthTextDark,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
              child: Text(
                'Perguntas frequentes',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ),
            for (final faq in _faqs) _FaqCard(faq: faq),
            const SizedBox(height: 24),
            Text(
              'Não encontrou o que precisava?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => _contactUs(context),
                icon: const Icon(Icons.mail_outline_rounded, size: 20),
                label: const Text('Fale conosco'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAuthPink,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              kSupportEmail,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaqCard extends StatelessWidget {
  final _Faq faq;
  const _FaqCard({required this.faq});

  @override
  Widget build(BuildContext context) {
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
      child: Theme(
        // Sem as linhas que o ExpansionTile desenha ao abrir.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const RoundedRectangleBorder(),
          collapsedShape: const RoundedRectangleBorder(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          iconColor: kAuthPink,
          collapsedIconColor: Colors.grey[500],
          title: Text(
            faq.question,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                faq.answer,
                style: TextStyle(fontSize: 13.5, color: Colors.grey[700], height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
