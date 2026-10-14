import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../widgets/auth/auth_common.dart';

/// Seção da política: título + parágrafos; linhas começando com "• " viram
/// itens de lista.
class _PolicySection {
  final String title;
  final List<String> paragraphs;
  const _PolicySection(this.title, this.paragraphs);
}

// O texto descreve o que o app faz HOJE — atualizar junto (e trocar
// kPrivacyPolicyVersion) sempre que mudar algum dado coletado, serviço de
// terceiros ou forma de armazenamento.
const _sections = [
  _PolicySection('Quem é responsável pelos seus dados', [
    'O MusiConnect é um projeto acadêmico (Trabalho de Conclusão de Curso de '
        'Engenharia de Software do Centro Universitário Católica de Santa '
        'Catarina). A responsável pelo tratamento dos dados é Laura Heloísa '
        'Luchez, pessoa física.',
    'Contato para qualquer assunto sobre privacidade: $kSupportEmail.',
  ]),
  _PolicySection('Quais dados coletamos', [
    'Só coletamos o que você informa no cadastro e o que você salva no app:',
    '• Nome, e-mail e senha. A senha nunca é guardada como você digitou: '
        'guardamos apenas uma versão embaralhada (hash), que não permite '
        'recuperá-la.',
    '• Instrumentos, ramo de atuação (estudante e/ou profissional) e '
        'localização (país, estado e cidade), escolhidos por você em listas.',
    '• Oportunidades e instituições que você salva como favoritas.',
    '• A data e a versão desta política quando você a aceitou.',
    'Não acessamos a localização GPS do seu celular, seus contatos, fotos, '
        'câmera ou microfone, e não coletamos dados de pagamento.',
  ]),
  _PolicySection('Para que usamos', [
    '• Criar e manter a sua conta e permitir o login.',
    '• Enviar e-mails de confirmação de cadastro e de redefinição de senha. '
        'Não enviamos propaganda.',
    '• Calcular o percentual de compatibilidade (match) entre o seu perfil '
        'e cada oportunidade.',
    '• Mostrar e guardar os seus favoritos.',
    'Usamos esses dados com base no seu consentimento e para prestar o '
        'serviço que você pediu ao se cadastrar (art. 7º, incisos I e V, da '
        'Lei Geral de Proteção de Dados — Lei nº 13.709/2018).',
  ]),
  _PolicySection('Com quem compartilhamos', [
    'Não vendemos nem alugamos seus dados. Para funcionar, o app usa alguns '
        'serviços de terceiros:',
    '• Resend: envia os e-mails de confirmação e de redefinição de senha. '
        'Recebe o seu endereço de e-mail.',
    '• Google Maps: exibe o mapa de instituições. Ao carregar o mapa, o '
        'Google recebe dados técnicos do aparelho (como o endereço IP), '
        'conforme a política de privacidade do próprio Google.',
    '• GeoNames: fornece as listas de países, estados e cidades do cadastro. '
        'Recebe apenas a consulta da lista, sem nenhum dado seu.',
    '• Google Gemini: lê os textos públicos dos anúncios de oportunidades '
        'para organizá-los. Nenhum dado de usuário é enviado a ele.',
  ]),
  _PolicySection('O que fica guardado no seu celular', [
    '• O código da sua sessão, para você não precisar fazer login toda vez. '
        'Ele fica em armazenamento criptografado do aparelho e é apagado ao '
        'sair da conta.',
    '• Preferências de exibição, como a ordenação das listas de favoritos.',
  ]),
  _PolicySection('Por quanto tempo guardamos', [
    'Seus dados ficam guardados enquanto a sua conta existir. Ao excluir a '
        'conta, a conta e os seus favoritos são apagados na hora, de forma '
        'definitiva.',
    'Oportunidades salvas cujo prazo de inscrição terminou são removidas '
        'automaticamente dos seus favoritos.',
  ]),
  _PolicySection('Seus direitos', [
    'A LGPD garante a você, entre outros, os direitos de:',
    '• Saber quais dados temos sobre você e pedir uma cópia.',
    '• Corrigir seus dados: Perfil → Editar.',
    '• Excluir seus dados e revogar o consentimento: Perfil → Excluir conta.',
    '• Tirar dúvidas ou fazer qualquer outro pedido pelo e-mail '
        '$kSupportEmail.',
  ]),
  _PolicySection('Segurança', [
    'Adotamos medidas para proteger seus dados: senhas guardadas apenas em '
        'forma de hash, sessão guardada em armazenamento criptografado no '
        'celular e exclusão de conta protegida por senha. Nenhum sistema é '
        'totalmente imune a falhas; se algo acontecer, avisaremos você.',
  ]),
  _PolicySection('Menores de idade', [
    'Se você tem menos de 18 anos, use o MusiConnect com o conhecimento dos '
        'seus pais ou responsáveis.',
  ]),
  _PolicySection('Mudanças nesta política', [
    'Se esta política mudar, a nova versão será publicada no app com a data '
        'de atualização. Mudanças importantes serão avisadas no próprio app.',
  ]),
];

/// Política de privacidade (LGPD) — aberta pelo cadastro (antes de aceitar)
/// e por Ajuda e suporte.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  /// "2026-10-13" → "13/10/2026".
  static String get _versionLabel {
    final parts = kPrivacyPolicyVersion.split('-');
    return parts.length == 3 ? '${parts[2]}/${parts[1]}/${parts[0]}' : kPrivacyPolicyVersion;
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
                'Política de privacidade',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: kAuthTextDark,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                'Atualizada em $_versionLabel',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ),
            for (final section in _sections) _SectionView(section: section),
          ],
        ),
      ),
    );
  }
}

class _SectionView extends StatelessWidget {
  final _PolicySection section;
  const _SectionView({required this.section});

  @override
  Widget build(BuildContext context) {
    final bodyStyle = TextStyle(fontSize: 13.5, color: Colors.grey[800], height: 1.5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: kAuthTextDark,
            ),
          ),
          const SizedBox(height: 6),
          for (final p in section.paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: p.startsWith('• ')
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
                          child: Text('•', style: bodyStyle.copyWith(color: kAuthPink)),
                        ),
                        Expanded(child: Text(p.substring(2), style: bodyStyle)),
                      ],
                    )
                  : Text(p, style: bodyStyle),
            ),
        ],
      ),
    );
  }
}
