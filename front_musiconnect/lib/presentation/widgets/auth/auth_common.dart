import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../core/text_utils.dart';
import '../app_loading_indicator.dart';

/// Paleta e widgets compartilhados pelas telas de autenticação
/// (Entrada, Login, Cadastro), seguindo o protótipo.
const kAuthPink = Color(0xFFDF2881);
const kAuthPurple = Color(0xFF7C3AED);
const kAuthTextDark = Color(0xFF111827);

/// Logo "MusiConnect" com "Musi" em preto e "Connect" em rosa, como no
/// protótipo (header das telas de onboarding).
class AuthLogo extends StatelessWidget {
  final double fontSize;
  const AuthLogo({super.key, this.fontSize = 20});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800),
        children: const [
          TextSpan(text: 'Musi', style: TextStyle(color: kAuthTextDark)),
          TextSpan(text: 'Connect', style: TextStyle(color: kAuthPink)),
        ],
      ),
    );
  }
}

/// Container cinza simbolizando uma imagem/ilustração ainda não definida,
/// com um ícone de contexto centralizado.
class AuthImagePlaceholder extends StatelessWidget {
  final double? height;
  final IconData icon;
  final double iconSize;
  final double borderRadius;

  const AuthImagePlaceholder({
    super.key,
    this.height,
    this.icon = Icons.image_outlined,
    this.iconSize = 48,
    this.borderRadius = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFDADADA),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(icon, size: iconSize, color: Colors.grey[500]),
    );
  }
}

/// Campo de texto rotulado, no estilo do protótipo (label acima, campo
/// arredondado com fundo levemente cinza). Suporta senha (com botão de
/// mostrar/ocultar) e um visual de "dropdown" (seta), puramente cosmético.
class AuthTextField extends StatefulWidget {
  final String label;
  final String hint;
  final TextEditingController? controller;
  final bool isPassword;
  final bool isDropdown;
  final bool required;
  final bool enabled;
  final TextInputType keyboardType;
  final Widget? labelTrailing;
  // Conteúdo livre abaixo do campo — usado pro medidor de força da senha
  // e pro aviso de "as senhas coincidem/não coincidem".
  final Widget? helper;

  const AuthTextField({
    super.key,
    required this.label,
    required this.hint,
    this.controller,
    this.isPassword = false,
    this.isDropdown = false,
    this.required = false,
    this.enabled = true,
    this.keyboardType = TextInputType.text,
    this.labelTrailing,
    this.helper,
  });

  @override
  State<AuthTextField> createState() => _AuthTextFieldState();
}

class _AuthTextFieldState extends State<AuthTextField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              widget.label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: kAuthTextDark,
              ),
            ),
            if (widget.required) ...[
              const SizedBox(width: 3),
              const Text(
                '*',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: kAuthPink,
                ),
              ),
            ],
            if (widget.labelTrailing != null) ...[
              const Spacer(),
              widget.labelTrailing!,
            ],
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: TextField(
            controller: widget.controller,
            enabled: widget.enabled,
            obscureText: widget.isPassword && _obscure,
            keyboardType: widget.keyboardType,
            style: const TextStyle(fontSize: 14, color: kAuthTextDark),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: TextStyle(fontSize: 13.5, color: Colors.grey[400]),
              border: InputBorder.none,
              disabledBorder: InputBorder.none,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              suffixIcon: widget.isPassword
                  ? IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 19,
                        color: Colors.grey[500],
                      ),
                      onPressed: widget.enabled
                          ? () => setState(() => _obscure = !_obscure)
                          : null,
                    )
                  : (widget.isDropdown
                      ? Icon(Icons.keyboard_arrow_down_rounded,
                          color: Colors.grey[500])
                      : null),
            ),
          ),
        ),
        if (widget.helper != null) ...[
          const SizedBox(height: 6),
          widget.helper!,
        ],
      ],
    );
  }
}

/// Botão principal em formato pílula (preenchido rosa por padrão — passe
/// [color] pra variantes como a de excluir conta, em vermelho).
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? trailingIcon;
  final Color color;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.trailingIcon,
    this.color = kAuthPink,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.grey[400],
        disabledForegroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
      child: loading
          ? const AppLoadingIndicator(size: 18, color: Colors.white)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style:
                        const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                if (trailingIcon != null) ...[
                  const SizedBox(width: 4),
                  Icon(trailingIcon, size: 17),
                ],
              ],
            ),
    );
  }
}

/// Botão secundário em formato pílula (contorno rosa por padrão — passe
/// [color] pra variantes como a de excluir conta, em vermelho).
class AuthOutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final Color color;

  const AuthOutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.leadingIcon,
    this.trailingIcon,
    this.color = kAuthPink,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        disabledForegroundColor: Colors.grey[400],
        side: BorderSide(
          color: onPressed == null ? Colors.grey[300]! : color,
          width: 1.5,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 17),
            const SizedBox(width: 6),
          ],
          Text(label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          if (trailingIcon != null) ...[
            const SizedBox(width: 4),
            Icon(trailingIcon, size: 17),
          ],
        ],
      ),
    );
  }
}

/// Título de seção com subtítulo explicativo, opcionalmente marcado como
/// obrigatório (*) — usado para agrupar campos relacionados em um passo do
/// cadastro ou da edição de perfil (ex: "Instrumentos", "Ramo de atuação").
class SectionLabel extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool required;

  const SectionLabel({
    super.key,
    required this.title,
    required this.subtitle,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: kAuthTextDark,
              ),
            ),
            if (required)
              const Text(
                ' *',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: kAuthPink,
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.35),
        ),
      ],
    );
  }
}

/// Checkbox com rótulo, toda a linha clicável — usado para "Profissional" /
/// "Estudante" no cadastro e na edição de perfil.
class CheckRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const CheckRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: kAuthPink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(fontSize: 13.5, color: kAuthTextDark),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rodapé "Já tem uma conta? Faça login" / "Não tem uma conta? Cadastre-se".
class AuthFooterLink extends StatelessWidget {
  final String question;
  final String action;
  final VoidCallback onTap;

  const AuthFooterLink({
    super.key,
    required this.question,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          children: [
            TextSpan(text: '$question '),
            TextSpan(
              text: action,
              style: const TextStyle(
                color: kAuthPink,
                fontWeight: FontWeight.w700,
              ),
              recognizer: TapGestureRecognizer()..onTap = onTap,
            ),
          ],
        ),
      ),
    );
  }
}

/// Seta "voltar" simples, discreta, alinhada ao protótipo (sem AppBar).
class AuthBackButton extends StatelessWidget {
  final VoidCallback onTap;
  const AuthBackButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.arrow_back_ios_new_rounded,
            size: 16, color: kAuthTextDark),
      ),
    );
  }
}

/// Campo de busca com autocomplete para seleção múltipla a partir de uma
/// lista fixa de opções (ex: instrumentos) — cada valor escolhido vira um
/// chip removível acima do campo. Mesmo padrão do `_PickerField` usado no
/// filtro de oportunidades (aba Matcher), mas autocontido (sem depender de
/// um serviço de backend) e reutilizável nas telas de autenticação.
class AuthMultiSelectField extends StatefulWidget {
  final String? label;
  final String hint;
  final List<String> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  const AuthMultiSelectField({
    super.key,
    this.label,
    required this.hint,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<AuthMultiSelectField> createState() => _AuthMultiSelectFieldState();
}

class _AuthMultiSelectFieldState extends State<AuthMultiSelectField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggle(String value) {
    final next = List<String>.of(widget.selected);
    if (next.contains(value)) {
      next.remove(value);
    } else {
      next.add(value);
    }
    widget.onChanged(next);
    _refreshOptionsCache();
  }

  // RawAutocomplete só recalcula sua lista interna de opções quando o
  // valor do campo de texto muda de verdade — nunca só porque a lista
  // `available` mudou. Sem isso, o item recém-selecionado continuava
  // aparecendo no dropdown até a seleção seguinte forçar essa mudança.
  // Agendamos pro fim do frame (depois que este widget já recebeu a
  // seleção atualizada) um vaivém de texto imperceptível que força o
  // recálculo, sem mexer no foco nem no texto visível.
  void _refreshOptionsCache() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = _controller.value;
      // Caractere invisível (zero-width space) só pra forçar um valor
      // diferente do atual — nunca chega a aparecer na tela.
      _controller.value = current.copyWith(text: String.fromCharCode(0x200B));
      _controller.value = current;
    });
  }

  @override
  Widget build(BuildContext context) {
    final available =
        widget.options.where((o) => !widget.selected.contains(o)).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.label != null) ...[
              Text(
                widget.label!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: kAuthTextDark,
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (widget.selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: widget.selected
                      .map((v) => _RemovableChip(
                            label: v,
                            onRemove: () => _toggle(v),
                          ))
                      .toList(),
                ),
              ),
            RawAutocomplete<String>(
              textEditingController: _controller,
              focusNode: _focusNode,
              displayStringForOption: (o) => o,
              optionsBuilder: (textEditingValue) {
                final query = normalizeForSearch(textEditingValue.text);
                if (query.isEmpty) return available;
                return available
                    .where((o) => normalizeForSearch(o).contains(query));
              },
              onSelected: (selection) {
                _toggle(selection);
                _controller.clear();
                _focusNode.unfocus();
              },
              fieldViewBuilder: (context, controller, focusNode, _) {
                return Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: const TextStyle(fontSize: 14, color: kAuthTextDark),
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      hintStyle:
                          TextStyle(fontSize: 13.5, color: Colors.grey[400]),
                      suffixIcon: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (focusNode.hasFocus) {
                            focusNode.unfocus();
                          } else {
                            focusNode.requestFocus();
                          }
                        },
                        child: Icon(Icons.keyboard_arrow_down_rounded,
                            color: Colors.grey[500]),
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                    ),
                  ),
                );
              },
              optionsViewBuilder: (context, onSelectedCb, opts) {
                final list = opts.toList();
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: Colors.white,
                    elevation: 4,
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: constraints.maxWidth,
                      height: list.length > 5 ? 220 : list.length * 44.0,
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final option = list[index];
                          return ListTile(
                            dense: true,
                            title: Text(option,
                                style: const TextStyle(fontSize: 13)),
                            onTap: () => onSelectedCb(option),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _RemovableChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _RemovableChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRemove,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: kAuthPink.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kAuthPink.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.close_rounded, size: 13, color: kAuthPink),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: kAuthPink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Campo de seleção única com busca (não multi-seleção — escolher uma
/// opção substitui a anterior, e ela fica escrita no próprio campo, sem
/// virar chip). Usado por país/estado/cidade no cadastro: [enabled]
/// desliga o campo enquanto o nível anterior da cascata não tem valor
/// escolhido (ex: Estado começa desligado até haver um País), e [loading]
/// mostra que as opções daquele nível ainda estão sendo buscadas.
class AuthSingleSelectField<T extends Object> extends StatefulWidget {
  final String label;
  final String hint;
  final List<T> options;
  final T? selected;
  final String Function(T option) displayString;
  final ValueChanged<T?> onChanged;
  final bool enabled;
  final bool loading;
  final bool required;
  final Widget? labelTrailing;

  const AuthSingleSelectField({
    super.key,
    required this.label,
    required this.hint,
    required this.options,
    required this.selected,
    required this.displayString,
    required this.onChanged,
    this.enabled = true,
    this.loading = false,
    this.required = false,
    this.labelTrailing,
  });

  @override
  State<AuthSingleSelectField<T>> createState() => _AuthSingleSelectFieldState<T>();
}

class _AuthSingleSelectFieldState<T extends Object> extends State<AuthSingleSelectField<T>> {
  late final TextEditingController _controller =
      TextEditingController(text: _textFor(widget.selected));
  final _focusNode = FocusNode();

  String _textFor(T? value) => value == null ? '' : widget.displayString(value);

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      // Seleciona todo o texto ao focar, pra digitar já substituir o
      // valor atual — sem apagar o campo sozinho: um clear "silencioso"
      // (só no controller) deixava o campo com cara de vazio enquanto a
      // seleção de verdade (no widget pai) continuava a mesma por trás,
      // o que mantinha "Avançar" habilitado mesmo parecendo limpo.
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    } else if (_controller.text != _textFor(widget.selected)) {
      // Perdeu o foco sem escolher nada novo — restaura o texto da
      // seleção atual (ou deixa vazio, se nada estiver selecionado).
      _controller.text = _textFor(widget.selected);
    }
  }

  // Limpeza de verdade: avisa o widget pai (desfazendo a seleção real,
  // o que reflete corretamente em validações como o botão "Avançar") e
  // só então limpa o texto exibido.
  void _clear() {
    widget.onChanged(null);
    _controller.clear();
  }

  @override
  void didUpdateWidget(covariant AuthSingleSelectField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && widget.selected != oldWidget.selected) {
      _controller.text = _textFor(widget.selected);
    }
    // As opções deste nível chegam de forma assíncrona (ex: Estado só
    // carrega depois de escolher o País) — sem isso, o RawAutocomplete
    // continuaria mostrando a lista vazia/antiga até o texto mudar de
    // verdade.
    if (widget.options != oldWidget.options) {
      _refreshOptionsCache();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _refreshOptionsCache() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = _controller.value;
      _controller.value = current.copyWith(text: String.fromCharCode(0x200B));
      _controller.value = current;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: kAuthTextDark,
                  ),
                ),
                if (widget.required) ...[
                  const SizedBox(width: 3),
                  const Text(
                    '*',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kAuthPink,
                    ),
                  ),
                ],
                if (widget.labelTrailing != null) ...[
                  const Spacer(),
                  widget.labelTrailing!,
                ],
              ],
            ),
            const SizedBox(height: 6),
            IgnorePointer(
              ignoring: !widget.enabled,
              child: Opacity(
                opacity: widget.enabled ? 1 : 0.55,
                child: RawAutocomplete<T>(
                  textEditingController: _controller,
                  focusNode: _focusNode,
                  displayStringForOption: widget.displayString,
                  optionsBuilder: (textEditingValue) {
                    final query = normalizeForSearch(textEditingValue.text);
                    if (query.isEmpty) return widget.options;
                    return widget.options.where((o) =>
                        normalizeForSearch(widget.displayString(o)).contains(query));
                  },
                  onSelected: (selection) {
                    widget.onChanged(selection);
                    _focusNode.unfocus();
                  },
                  fieldViewBuilder: (context, controller, focusNode, _) {
                    return Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        style: const TextStyle(fontSize: 14, color: kAuthTextDark),
                        decoration: InputDecoration(
                          hintText: widget.loading ? 'Carregando...' : widget.hint,
                          hintStyle: TextStyle(fontSize: 13.5, color: Colors.grey[400]),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 13),
                          suffixIcon: widget.loading
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: AppLoadingIndicator(size: 16),
                                )
                              : (widget.selected != null
                                  ? IconButton(
                                      icon: Icon(Icons.close_rounded,
                                          size: 18, color: Colors.grey[500]),
                                      onPressed: _clear,
                                      tooltip: 'Limpar',
                                    )
                                  : Icon(Icons.keyboard_arrow_down_rounded,
                                      color: Colors.grey[500])),
                        ),
                      ),
                    );
                  },
                  optionsViewBuilder: (context, onSelectedCb, opts) {
                    final list = opts.toList();
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        color: Colors.white,
                        elevation: 4,
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          width: constraints.maxWidth,
                          height: list.length > 5 ? 220 : list.length * 44.0,
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: list.length,
                            itemBuilder: (context, index) {
                              final option = list[index];
                              return ListTile(
                                dense: true,
                                title: Text(widget.displayString(option),
                                    style: const TextStyle(fontSize: 13)),
                                onTap: () => onSelectedCb(option),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Popup padronizado das telas de autenticação/perfil: fundo branco e
/// tipografia da mesma paleta do resto do app. Com um único botão, ele vem
/// centralizado e preenchido (rosa); com dois, segue o mesmo padrão de
/// botões da tela de Entrada — um preenchido e outro só com borda, lado a
/// lado.
class AuthDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  // Ações irreversíveis (ex: excluir conta) trocam o rosa padrão por
  // vermelho nos dois botões, deixando o risco visualmente explícito.
  final bool destructive;

  const AuthDialog({
    super.key,
    required this.title,
    required this.content,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.destructive = false,
  });

  /// Atalho para o caso mais comum: título + mensagem em texto simples.
  factory AuthDialog.message({
    Key? key,
    required String title,
    required String message,
    required String primaryLabel,
    required VoidCallback? onPrimary,
    String? secondaryLabel,
    VoidCallback? onSecondary,
    bool destructive = false,
  }) {
    return AuthDialog(
      key: key,
      title: title,
      content: Text(
        message,
        style: TextStyle(fontSize: 13.5, color: Colors.grey[600], height: 1.4),
      ),
      primaryLabel: primaryLabel,
      onPrimary: onPrimary,
      secondaryLabel: secondaryLabel,
      onSecondary: onSecondary,
      destructive: destructive,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasTwoButtons = secondaryLabel != null;
    final accent = destructive ? Colors.red : kAuthPink;
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: kAuthTextDark,
        ),
      ),
      content: content,
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        if (hasTwoButtons)
          Row(
            children: [
              Expanded(
                child: AuthOutlineButton(
                  label: secondaryLabel!,
                  onPressed: onSecondary,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AuthPrimaryButton(
                  label: primaryLabel,
                  onPressed: onPrimary,
                  color: accent,
                ),
              ),
            ],
          )
        else
          SizedBox(
            width: double.infinity,
            child: AuthPrimaryButton(label: primaryLabel, onPressed: onPrimary, color: accent),
          ),
      ],
    );
  }
}

/// Checklist de requisitos de senha (8+ caracteres, maiúscula+minúscula,
/// número, caractere especial) com uma barra de progresso — cada item
/// fica verde assim que atendido. Some por completo enquanto o campo
/// está vazio. Usado no cadastro e na redefinição de senha.
class AuthPasswordRequirements extends StatelessWidget {
  final String password;
  const AuthPasswordRequirements({super.key, required this.password});

  static bool _hasMinLength(String p) => p.length >= 8;
  static bool _hasUpperLower(String p) =>
      RegExp(r'[a-z]').hasMatch(p) && RegExp(r'[A-Z]').hasMatch(p);
  static bool _hasNumber(String p) => RegExp(r'[0-9]').hasMatch(p);
  static bool _hasSpecial(String p) =>
      RegExp(r'''[!@#$%^&*(),.?":{}|<>_\-+=/\\\[\];~`]''').hasMatch(p);

  /// Mínimo pra contar como válida: 8+ caracteres, mais pelo menos 2 dos
  /// outros 3 critérios (maiúscula+minúscula, número, especial).
  static bool isValid(String password) {
    if (!_hasMinLength(password)) return false;
    final extra = [
      _hasUpperLower(password),
      _hasNumber(password),
      _hasSpecial(password),
    ].where((ok) => ok).length;
    return extra >= 2;
  }

  List<bool> get _checks => [
        _hasMinLength(password),
        _hasUpperLower(password),
        _hasNumber(password),
        _hasSpecial(password),
      ];

  static const _labels = [
    'Pelo menos 8 caracteres',
    'Letra maiúscula e minúscula',
    'Pelo menos um número',
    'Um caractere especial (!@#\$...)',
  ];

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();
    final checks = _checks;
    const okColor = Color(0xFF16A34A);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(checks.length, (i) {
            return Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i < checks.length - 1 ? 4 : 0),
                height: 4,
                decoration: BoxDecoration(
                  color: checks[i] ? okColor : Colors.grey[200],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  checks[i] ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 13,
                  color: checks[i] ? okColor : Colors.grey[400],
                ),
                const SizedBox(width: 6),
                Text(
                  _labels[i],
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: checks[i] ? FontWeight.w600 : FontWeight.w400,
                    color: checks[i] ? okColor : Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
