import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../widgets/auth/auth_common.dart';
import '../widgets/auth/logout_flow.dart';

/// Seção da política: título + parágrafos; linhas começando com "• " viram
/// itens de lista. Cada parágrafo é um texto ou um [_Changed].
class _PolicySection {
  final String title;
  final List<Object> paragraphs;
  const _PolicySection(this.title, this.paragraphs);

  bool get hasChanges => paragraphs.any((p) => p is _Changed);
}

/// Parágrafo novo ou alterado na versão atual — aparece destacado, para quem
/// já aceitou a anterior achar o que mudou sem reler tudo.
class _Changed {
  final String text;
  const _Changed(this.text);
}

// O texto descreve o que o app faz HOJE — atualizar junto (e trocar
// kPrivacyPolicyVersion) sempre que mudar algum dado coletado, serviço de
// terceiros ou forma de armazenamento. A cada nova versão: reescrever
// _changesSummary e marcar com _Changed só o que mudou NELA (tirando a
// marcação da versão anterior).
//
// A mesma política fica pública em https://musiconnect.app.br/privacidade:
// depois de mudar o texto, rode `python deploy/gerar_privacidade.py` e
// commite a página junto (o CI confere se as duas estão iguais).

/// Resumo do que mudou na versão atual em relação à anterior.
const _changesSummary = [
  'Explicamos que, além das oportunidades com prazo encerrado, também saem '
      'dos seus favoritos as oportunidades cujo anúncio foi retirado da fonte '
      'e as instituições que deixaram de existir no mapa.',
  'Incluímos o que acontece quando você entra sem uma conta cadastrada.',
];

const _sections = [
  _PolicySection('Quem é responsável pelos seus dados', [
    'O MusiConnect é um projeto acadêmico (Trabalho de Conclusão de Curso de '
        'Engenharia de Software do Centro Universitário Católica de Santa '
        'Catarina). A responsável pelo tratamento dos dados é Laura Heloísa '
        'Luchez, pessoa física.',
    'Contato para qualquer assunto sobre privacidade: $kSupportEmail.',
  ]),
  _PolicySection('Quais dados coletamos', [
    'Coletamos o que você informa no cadastro e o que você salva no app:',
    '• Nome, e-mail e senha. A senha nunca é guardada como você digitou: '
        'guardamos apenas uma versão embaralhada (hash), que não permite '
        'recuperá-la.',
    '• Instrumentos, ramo de atuação (estudante e/ou profissional) e '
        'localização (país, estado e cidade), escolhidos por você em listas.',
    '• Oportunidades e instituições que você salva como favoritas.',
    '• A data e a versão desta política quando você a aceitou.',
    'E, enquanto você usa o app, dados técnicos que não identificam você '
        'pelo nome ou e-mail:',
    '• Dados de uso: telas abertas e ações como entrar, cadastrar-se, salvar '
        'ou abrir uma oportunidade e aplicar um filtro — sem o conteúdo do '
        'que você digita ou busca.',
    '• Relatórios de erro: quando o app trava ou falha, o que estava '
        'acontecendo no código naquele momento.',
    '• Junto com eles, informações do aparelho: modelo, versão do Android, '
        'idioma, país aproximado e um identificador aleatório da instalação '
        'do app.',
    _Changed(
        'Se você entrar sem uma conta cadastrada, não coletamos dados de '
        'cadastro: só os dados técnicos de uso e erros descritos acima, e a '
        'visita termina quando o app é fechado.'),
    'Não usamos o ID de publicidade do celular, não acessamos a localização '
        'GPS, seus contatos, fotos, câmera ou microfone, e não coletamos dados '
        'de pagamento.',
  ]),
  _PolicySection('Para que usamos', [
    '• Criar e manter a sua conta e permitir o login.',
    '• Enviar e-mails de confirmação de cadastro e de redefinição de senha. '
        'Não enviamos propaganda.',
    '• Calcular o percentual de compatibilidade (match) entre o seu perfil '
        'e cada oportunidade.',
    '• Mostrar e guardar os seus favoritos.',
    '• Entender como o app é usado e corrigir erros (dados de uso e '
        'relatórios de erro).',
    'Usamos os dados da conta com base no seu consentimento e para prestar o '
        'serviço que você pediu ao se cadastrar (art. 7º, incisos I e V, da '
        'Lei Geral de Proteção de Dados — Lei nº 13.709/2018). Os dados de uso '
        'e os relatórios de erro são tratados com base no legítimo interesse '
        'de manter o app funcionando e melhorá-lo (art. 7º, inciso IX) — e '
        'você pode desligar esse envio quando quiser: Perfil → Enviar dados '
        'de uso e erros.',
  ]),
  _PolicySection('Com quem compartilhamos', [
    'Não vendemos nem alugamos seus dados. Para funcionar, o app usa alguns '
        'serviços de terceiros:',
    '• Hostinger: hospeda o servidor do MusiConnect, no Brasil. É lá que '
        'ficam guardados os dados da sua conta e os seus favoritos.',
    '• Resend: envia os e-mails de confirmação e de redefinição de senha. '
        'Recebe o seu endereço de e-mail.',
    '• Google Maps: exibe o mapa de instituições. Ao carregar o mapa, o '
        'Google recebe dados técnicos do aparelho (como o endereço IP), '
        'conforme a política de privacidade do próprio Google.',
    '• GeoNames: fornece as listas de países, estados e cidades do cadastro. '
        'Recebe apenas a consulta da lista, sem nenhum dado seu.',
    '• Google Gemini: lê os textos públicos dos anúncios de oportunidades '
        'para organizá-los. Nenhum dado de usuário é enviado a ele.',
    '• Google Firebase (Analytics e Crashlytics): recebe os dados de uso e '
        'os relatórios de erro descritos acima, sem o seu nome nem o seu '
        'e-mail. Os servidores do Google podem ficar fora do Brasil; o Google '
        'trata esses dados conforme os termos de proteção de dados do '
        'Firebase.',
  ]),
  _PolicySection('O que fica guardado no seu celular', [
    '• O código da sua sessão, para você não precisar fazer login toda vez. '
        'Ele fica em armazenamento criptografado do aparelho e é apagado ao '
        'sair da conta.',
    '• Preferências de exibição, como a ordenação das listas de favoritos, '
        'e a sua escolha de enviar ou não dados de uso e erros.',
    _Changed(
        '• Se você entrou sem conta, a versão desta política que aceitou — para '
        'não pedir o aceite a cada visita.'),
  ]),
  _PolicySection('Por quanto tempo guardamos', [
    'Seus dados ficam guardados enquanto a sua conta existir. Ao excluir a '
        'conta, a conta e os seus favoritos são apagados na hora, de forma '
        'definitiva.',
    _Changed(
        'Oportunidades salvas cujo prazo de inscrição terminou ou cujo anúncio '
        'foi retirado da fonte, e instituições favoritas que deixaram de existir '
        'no mapa, são removidas automaticamente dos seus favoritos.'),
    'No Firebase, os dados de uso ligados ao identificador da instalação '
        'ficam guardados por até 2 meses, e os relatórios de erro por até 90 '
        'dias; depois disso, só restam números agregados (ex: quantas pessoas '
        'abriram o mapa).',
  ]),
  _PolicySection('Seus direitos', [
    'A LGPD garante a você, entre outros, os direitos de:',
    '• Saber quais dados temos sobre você e pedir uma cópia.',
    '• Corrigir seus dados: Perfil → Editar.',
    '• Excluir seus dados e revogar o consentimento: Perfil → Excluir conta.',
    '• Se opor ao envio de dados de uso e erros: Perfil → Enviar dados de uso '
        'e erros.',
    '• Tirar dúvidas ou fazer qualquer outro pedido pelo e-mail '
        '$kSupportEmail.',
  ]),
  _PolicySection('Segurança', [
    'Adotamos medidas para proteger seus dados: comunicação criptografada '
        '(HTTPS) entre o app e o servidor, senhas guardadas apenas em forma de '
        'hash, sessão guardada em armazenamento criptografado no celular e '
        'exclusão de conta protegida por senha. Nenhum sistema é totalmente '
        'imune a falhas; se algo acontecer, avisaremos você.',
  ]),
  _PolicySection('Menores de idade', [
    'Se você tem menos de 18 anos, use o MusiConnect com o conhecimento dos '
        'seus pais ou responsáveis.',
  ]),
  _PolicySection('Mudanças nesta política', [
    'Se esta política mudar, a nova versão será publicada no app com a data '
        'de atualização. Quando a mudança envolver os seus dados, o app pede '
        'que você leia e aceite a nova versão para continuar usando a conta.',
  ]),
];

/// Política de privacidade (LGPD) — aberta pelo cadastro (antes de aceitar)
/// e por Ajuda e suporte.
///
/// Com [onAccept], vira o pedido de novo aceite de quem já tem conta (a
/// política mudou desde o último aceite): não dá para voltar sem escolher —
/// aceitar ou sair da conta.
///
/// [highlightChanges] mostra o resumo "O que mudou" e destaca os trechos
/// alterados — desligado no cadastro, onde tudo é novo para a pessoa.
class PrivacyPolicyScreen extends StatelessWidget {
  final Future<void> Function()? onAccept;
  final bool highlightChanges;

  const PrivacyPolicyScreen({
    super.key,
    this.onAccept,
    this.highlightChanges = true,
  });

  bool get _askingAcceptance => onAccept != null;

  /// "2026-10-13" → "13/10/2026".
  static String get _versionLabel {
    final parts = kPrivacyPolicyVersion.split('-');
    return parts.length == 3
        ? '${parts[2]}/${parts[1]}/${parts[0]}'
        : kPrivacyPolicyVersion;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_askingAcceptance,
      child: Scaffold(
        backgroundColor: Colors.white,
        bottomNavigationBar:
            _askingAcceptance ? _AcceptBar(onAccept: onAccept!) : null,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Row(
                children: [
                  if (_askingAcceptance)
                    const SizedBox(width: 36)
                  else
                    AuthBackButton(onTap: () => Navigator.of(context).pop()),
                  const Expanded(child: Center(child: AuthLogo(fontSize: 17))),
                  const SizedBox(width: 36),
                ],
              ),
              if (_askingAcceptance)
                const _ChangesSummary(
                  intro: 'Atualizamos a nossa Política de privacidade. Veja o '
                      'que mudou e aceite para continuar usando o MusiConnect:',
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
              // Fora do novo aceite (ex: aberta pela Ajuda), o resumo vem
              // depois do título, para quem quiser saber o que mudou.
              if (highlightChanges && !_askingAcceptance)
                const _ChangesSummary(
                  intro: 'O que mudou nesta versão:',
                ),
              if (highlightChanges) const _ChangedLegend(),
              for (final section in _sections)
                _SectionView(section: section, highlight: highlightChanges),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rodapé do novo aceite: "Aceitar e continuar" registra o aceite no
/// backend; "Sair da conta" recusa (mesmo fluxo do Perfil).
class _AcceptBar extends StatefulWidget {
  final Future<void> Function() onAccept;
  const _AcceptBar({required this.onAccept});

  @override
  State<_AcceptBar> createState() => _AcceptBarState();
}

class _AcceptBarState extends State<_AcceptBar> {
  bool _loading = false;
  String? _error;

  Future<void> _accept() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.onAccept();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey[200]!)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: Colors.red[800]),
                ),
              ),
            AuthPrimaryButton(
              label: 'Aceitar e continuar',
              onPressed: _accept,
              loading: _loading,
            ),
            TextButton(
              onPressed: _loading ? null : () => confirmAndLogout(context),
              style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
              child: const Text('Não aceito — sair da conta'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Caixa "O que mudou": resumo das mudanças da versão atual.
class _ChangesSummary extends StatelessWidget {
  final String intro;
  const _ChangesSummary({required this.intro});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 13.5, color: kAuthTextDark, height: 1.4);
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 16, 4, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kAuthPink.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.new_releases_outlined,
                  size: 18, color: kAuthPink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(intro,
                    style: style.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final change in _changesSummary)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(2, 0, 8, 0),
                    child: Text('•', style: TextStyle(color: kAuthPink)),
                  ),
                  Expanded(child: Text(change, style: style)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Explica o destaque usado nos trechos alterados.
class _ChangedLegend extends StatelessWidget {
  const _ChangedLegend();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: kAuthPink.withOpacity(0.08),
              border:
                  const Border(left: BorderSide(color: kAuthPink, width: 3)),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Trechos novos ou alterados nesta versão',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

class _SectionView extends StatelessWidget {
  final _PolicySection section;
  final bool highlight;
  const _SectionView({required this.section, required this.highlight});

  @override
  Widget build(BuildContext context) {
    final bodyStyle =
        TextStyle(fontSize: 13.5, color: Colors.grey[800], height: 1.5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  section.title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: kAuthTextDark,
                  ),
                ),
              ),
              if (highlight && section.hasChanges) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: kAuthPink,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Atualizado',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          for (final p in section.paragraphs)
            _ParagraphView(
              text: p is _Changed ? p.text : p as String,
              changed: highlight && p is _Changed,
              style: bodyStyle,
            ),
        ],
      ),
    );
  }
}

/// Parágrafo ou item de lista; os alterados ganham fundo e barra rosa.
class _ParagraphView extends StatelessWidget {
  final String text;
  final bool changed;
  final TextStyle style;

  const _ParagraphView({
    required this.text,
    required this.changed,
    required this.style,
  });

  @override
  Widget build(BuildContext context) {
    final content = text.startsWith('• ')
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
                child: Text('•', style: style.copyWith(color: kAuthPink)),
              ),
              Expanded(child: Text(text.substring(2), style: style)),
            ],
          )
        : Text(text, style: style);

    if (!changed) {
      return Padding(padding: const EdgeInsets.only(bottom: 6), child: content);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
      decoration: BoxDecoration(
        color: kAuthPink.withOpacity(0.08),
        border: const Border(left: BorderSide(color: kAuthPink, width: 3)),
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
      ),
      child: content,
    );
  }
}
