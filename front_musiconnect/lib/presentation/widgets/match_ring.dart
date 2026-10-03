import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'auth/auth_common.dart';

/// Gradiente roxo→rosa do app — anel e etiquetas do "Seu melhor match".
const kBrandGradientColors = [kAuthPurple, kAuthPink];

/// Fundo do card do topo do detalhe da oportunidade: degradê bem claro
/// roxo→rosa, sem borda — discreto, com o destaque no [MatchRing].
BoxDecoration highlightCardDecoration({double radius = 20}) => BoxDecoration(
      gradient: LinearGradient(
        colors: [
          kAuthPurple.withOpacity(0.07),
          kAuthPink.withOpacity(0.10),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(radius),
    );

/// Anel de % de match sobre trilha clara, com o número escuro e "match"
/// dentro — usado nos cartões de destaque.
///
/// Cor do traço: [gradientColors] (ex: roxo→rosa no Início, indo do topo
/// até a ponta do progresso) ou, sem gradiente, [color] sólida (o detalhe
/// da oportunidade passa a cor da faixa do %).
class MatchRing extends StatelessWidget {
  final int percent;
  final double size;
  final Color color;
  final List<Color>? gradientColors;

  const MatchRing({
    super.key,
    required this.percent,
    this.size = 68,
    this.color = kAuthPink,
    this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    // Trilha: tom claro da cor do traço (a última do gradiente, se houver).
    final trackColor = (gradientColors?.last ?? color).withOpacity(0.15);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _MatchRingPainter(
              fraction: percent / 100,
              strokeWidth: size * 0.09,
              color: color,
              gradientColors: gradientColors,
              trackColor: trackColor,
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$percent%',
                  style: TextStyle(
                    fontSize: size * 0.25,
                    fontWeight: FontWeight.w800,
                    color: kAuthTextDark,
                    height: 1.1,
                  ),
                ),
                Text(
                  'match',
                  style: TextStyle(
                    fontSize: size * 0.15,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchRingPainter extends CustomPainter {
  final double fraction;
  final double strokeWidth;
  final Color color;
  final List<Color>? gradientColors;
  final Color trackColor;

  const _MatchRingPainter({
    required this.fraction,
    required this.strokeWidth,
    required this.color,
    required this.gradientColors,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    final sweep = 2 * math.pi * fraction.clamp(0.0, 1.0);
    if (sweep <= 0) return;

    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final colors = gradientColors;
    if (colors != null && colors.length > 1) {
      // Gradiente ao longo do arco: começa no topo (12h) e termina na
      // ponta do progresso — 100% vai de roxo a rosa na volta inteira.
      progress.shader = SweepGradient(
        colors: colors,
        endAngle: sweep,
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    } else {
      progress.color = color;
    }
    canvas.drawArc(rect, -math.pi / 2, sweep, false, progress);
  }

  @override
  bool shouldRepaint(_MatchRingPainter old) =>
      old.fraction != fraction ||
      old.strokeWidth != strokeWidth ||
      old.color != color ||
      old.gradientColors != gradientColors ||
      old.trackColor != trackColor;
}
