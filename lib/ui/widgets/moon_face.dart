import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/enums.dart';
import '../theme.dart';

/// The moon character. Its face follows her cycle: asleep during her period,
/// waking as energy rises, beaming at the peak, and level-eyed in the
/// wind-down.
///
/// Drawn in code, so it needs no image files and stays sharp at any size.
class MoonFace extends StatelessWidget {
  const MoonFace({super.key, required this.phase, this.size = 48});

  final CyclePhase phase;
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _MoonFacePainter(phase),
      );
}

class _MoonFacePainter extends CustomPainter {
  _MoonFacePainter(this.phase);

  final CyclePhase phase;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = phase == CyclePhase.menstrual
            ? MoonColors.moonPale
            : MoonColors.moonGold,
    );

    final crater = Paint()..color = MoonColors.moonInk.withValues(alpha: 0.08);
    canvas
      ..drawCircle(c + Offset(r * 0.48, -r * 0.5), r * 0.14, crater)
      ..drawCircle(c + Offset(-r * 0.58, r * 0.42), r * 0.1, crater);

    final line = Paint()
      ..color = MoonColors.moonInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, r * 0.09)
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = MoonColors.moonInk;

    final eyes = [
      c + Offset(-r * 0.34, -r * 0.12),
      c + Offset(r * 0.34, -r * 0.12),
    ];
    final eye = r * 0.16;
    final mouth = c + Offset(0, r * 0.34);

    // Angles run clockwise from three o'clock, so 0..pi is the lower half of
    // a circle (a smile) and pi..2pi the upper half (a happy, closed eye).
    switch (phase) {
      case CyclePhase.menstrual:
        // Asleep: closed eyes and a small round mouth.
        for (final e in eyes) {
          canvas.drawArc(
            Rect.fromCircle(center: e, radius: eye),
            0,
            math.pi,
            false,
            line,
          );
        }
        canvas.drawCircle(mouth, r * 0.07, fill);
      case CyclePhase.follicular:
        // Waking up: open eyes and a small smile.
        for (final e in eyes) {
          canvas.drawCircle(e, eye * 0.6, fill);
        }
        canvas.drawArc(
          Rect.fromCircle(
            center: mouth + Offset(0, -r * 0.12),
            radius: r * 0.24,
          ),
          math.pi * 0.2,
          math.pi * 0.6,
          false,
          line,
        );
      case CyclePhase.ovulatory:
        // Beaming: happy eyes, a wide open smile and rosy cheeks.
        for (final e in eyes) {
          canvas.drawArc(
            Rect.fromCircle(center: e, radius: eye),
            math.pi,
            math.pi,
            false,
            line,
          );
        }
        canvas.drawArc(
          Rect.fromCircle(
            center: mouth + Offset(0, -r * 0.1),
            radius: r * 0.3,
          ),
          0,
          math.pi,
          true,
          fill,
        );
        final cheek = Paint()
          ..color = MoonColors.menstrual.withValues(alpha: 0.35);
        canvas
          ..drawCircle(c + Offset(-r * 0.62, r * 0.2), r * 0.11, cheek)
          ..drawCircle(c + Offset(r * 0.62, r * 0.2), r * 0.11, cheek);
      case CyclePhase.luteal:
        // Winding down: half-closed eyes and a level mouth.
        for (final e in eyes) {
          canvas.drawLine(e + Offset(-eye, 0), e + Offset(eye, 0), line);
        }
        canvas.drawLine(
          mouth + Offset(-r * 0.16, 0),
          mouth + Offset(r * 0.16, 0),
          line,
        );
    }
  }

  @override
  bool shouldRepaint(_MoonFacePainter old) => old.phase != phase;
}

/// One of the four moons that stand for the phases of her cycle: new for her
/// period, waxing as energy rises, full at the peak, waning in the wind-down.
class MoonPhaseIcon extends StatelessWidget {
  const MoonPhaseIcon({
    super.key,
    required this.phase,
    this.size = 36,
    this.highlighted = false,
  });

  final CyclePhase phase;
  final double size;

  /// The current phase is lit in gold; the others stay dim.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      size: Size.square(size),
      painter: _MoonPhasePainter(
        phase: phase,
        lit: highlighted ? MoonColors.moonGold : MoonColors.moonDim,
        shadow: dark ? MoonColors.nightLine : MoonColors.dawnLine,
      ),
    );
  }
}

class _MoonPhasePainter extends CustomPainter {
  _MoonPhasePainter({
    required this.phase,
    required this.lit,
    required this.shadow,
  });

  final CyclePhase phase;
  final Color lit;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 1;
    final rect = Rect.fromCircle(center: c, radius: r);
    final litPaint = Paint()..color = lit;
    final shadowPaint = Paint()..color = shadow;

    switch (phase) {
      case CyclePhase.menstrual:
        canvas
          ..drawCircle(c, r, shadowPaint)
          ..drawCircle(
            c,
            r,
            Paint()
              ..color = lit
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
      case CyclePhase.follicular:
        canvas
          ..drawCircle(c, r, shadowPaint)
          ..drawArc(rect, -math.pi / 2, math.pi, true, litPaint);
      case CyclePhase.ovulatory:
        canvas.drawCircle(c, r, litPaint);
      case CyclePhase.luteal:
        canvas
          ..drawCircle(c, r, shadowPaint)
          ..drawArc(rect, math.pi / 2, math.pi, true, litPaint);
    }
  }

  @override
  bool shouldRepaint(_MoonPhasePainter old) =>
      old.phase != phase || old.lit != lit || old.shadow != shadow;
}
