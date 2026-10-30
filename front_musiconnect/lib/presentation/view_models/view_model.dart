import 'package:flutter/foundation.dart';

/// Base dos ViewModels do app (MVVM): um [ChangeNotifier] que a tela escuta
/// com `ListenableBuilder`.
///
/// Ignora avisos depois de descartado — uma carga pode terminar depois que
/// a pessoa saiu da tela (o equivalente ao `if (!mounted) return` que as
/// telas faziam antes de chamar `setState`).
abstract class ViewModel extends ChangeNotifier {
  bool _disposed = false;

  bool get isDisposed => _disposed;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
