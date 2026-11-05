import 'package:flutter/material.dart';

/// Foco dos campos de texto no app inteiro. Sem isso, no Android o campo
/// continua selecionado depois de a pessoa abaixar o teclado, e o teclado
/// volta sozinho ao trocar de tela, fechar uma janela ou voltar.

/// `onTapOutside` de todo campo: tocar fora tira o foco (e o teclado). No
/// Android o Flutter não faz isso sozinho. A lista de sugestões e a barra de
/// copiar/colar contam como dentro do campo.
void unfocusOnTapOutside(PointerDownEvent _) => FocusManager.instance.primaryFocus?.unfocus();

/// Foco de campo com lista de sugestões (RawAutocomplete): ele fica
/// selecionado mesmo com o teclado abaixado, porque a lista só aparece com
/// o campo selecionado (a pessoa abaixa o teclado para ver as opções).
class KeepsFocusWithoutKeyboard extends FocusNode {}

/// No topo do app (MaterialApp.builder): abaixar o teclado tira o foco do
/// campo, para que ele não seja selecionado de novo ao voltar à tela.
class KeyboardFocusGuard extends StatefulWidget {
  const KeyboardFocusGuard({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardFocusGuard> createState() => _KeyboardFocusGuardState();
}

class _KeyboardFocusGuardState extends State<KeyboardFocusGuard> with WidgetsBindingObserver {
  bool _keyboardOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final open = View.of(context).viewInsets.bottom > 0;
    if (_keyboardOpen && !open) {
      final focus = FocusManager.instance.primaryFocus;
      if (focus is! KeepsFocusWithoutKeyboard) focus?.unfocus();
    }
    _keyboardOpen = open;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
