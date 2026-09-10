import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

/// Indicador de carregamento padrão do app — SpinKitThreeInOut
/// (flutter_spinkit) na cor rosa da paleta, no lugar do círculo genérico
/// do Material nos popups de carregamento.
class AppLoadingIndicator extends StatelessWidget {
  final double size;
  final Color color;

  const AppLoadingIndicator({
    super.key,
    this.size = 32,
    this.color = const Color(0xFFDF2881), // kAuthPink
  });

  @override
  Widget build(BuildContext context) {
    return SpinKitThreeInOut(size: size, color: color);
  }
}
