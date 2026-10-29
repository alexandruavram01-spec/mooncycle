import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/cycle_engine.dart';
import '../../domain/enums.dart';
import '../theme.dart';

/// The ring on the home screen: one segment per day of the predicted cycle,
/// coloured by phase, with today marked.
class CycleWheel extends StatelessWidget {
  const CycleWheel({
    super.key,
    required this.status,
    this.size = 260,
    this.showFertileWindow = true,
    this.child,
  });

  final CycleStatus status;
  final double size;
  final bool showFertileWindow;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _WheelPainter(
          status: status,
          showFertileWindow: showFertileWindow,
          trackColor: scheme.surfaceContainerHighest,
          markerColor: scheme.onSurface,
          surfaceColor: scheme.surface,
        ),
        // The ring has a fixed size, so its centre text grows only so far.
        child: Center(
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.25,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({
    required this.status,
    required this.showFertileWindow,
    required this.trackColor,
    required this.markerColor,
    required this.surfaceColor,
  });

  final CycleStatus status;
  final bool showFertileWindow;
  final Color trackColor;
  final Color markerColor;
  final Color surfaceColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    // A thick ring, with room outside it for the fertile-days bracket.
    const stroke = 26.0;
    final radius = math.min(size.width, size.height) / 2 - stroke / 2 - 10;
    final rect = Rect.fromCircle(center: centre, radius: radius);

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = trackColor,
    );

    if (!status.hasData) return;

    final total = math.max(status.typicalCycleLength, 1);
    final sweepPerDay = (2 * math.pi) / total;
    // Start at 12 o'clock.
    const startAngle = -math.pi / 2;

    final cycleStart = status.currentCycleStart!;
    final ovulation = status.predictedOvulation;
    final periodLength = status.typicalPeriodLength;

    for (var i = 0; i < total; i++) {
      final day = cycleStart.addDays(i);
      final dayOfCycle = i + 1;

      CyclePhase phase;
      if (dayOfCycle <= periodLength) {
        phase = CyclePhase.menstrual;
      } else if (ovulation != null) {
        final fromOvulation = day.differenceInDays(ovulation);
        if (fromOvulation >= -1 && fromOvulation <= 1) {
          phase = CyclePhase.ovulatory;
        } else if (fromOvulation < -1) {
          phase = CyclePhase.follicular;
        } else {
          phase = CyclePhase.luteal;
        }
      } else {
        phase = CyclePhase.follicular;
      }

      final isPast = dayOfCycle <= status.dayOfCycle;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = MoonColors.forPhase(phase)
            .withValues(alpha: isPast ? 0.95 : 0.32);

      canvas.drawArc(
        rect,
        startAngle + i * sweepPerDay,
        sweepPerDay * 0.92,
        false,
        paint,
      );
    }

    // Fertile window bracket, drawn just outside the ring.
    final fertileStart = status.fertileWindowStart;
    final fertileEnd = status.fertileWindowEnd;
    if (showFertileWindow && fertileStart != null && fertileEnd != null) {
      final offset = fertileStart.differenceInDays(cycleStart);
      final span = fertileEnd.differenceInDays(fertileStart) + 1;
      if (offset >= 0 && offset < total) {
        canvas.drawArc(
          Rect.fromCircle(center: centre, radius: radius + stroke / 2 + 6),
          startAngle + offset * sweepPerDay,
          sweepPerDay * span,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = MoonColors.ovulatory,
        );
      }
    }

    // Today marker.
    final todayIndex = (status.dayOfCycle - 1).clamp(0, total - 1);
    final angle = startAngle + (todayIndex + 0.5) * sweepPerDay;
    final markerCentre = centre +
        Offset(math.cos(angle), math.sin(angle)) * radius;
    // Today is a small half-lit moon sitting on the ring.
    canvas
      ..drawCircle(markerCentre, 13, Paint()..color = markerColor)
      ..drawCircle(markerCentre, 11, Paint()..color = surfaceColor)
      ..drawArc(
        Rect.fromCircle(center: markerCentre, radius: 11),
        -math.pi / 2,
        math.pi,
        true,
        Paint()..color = MoonColors.moonGold,
      );
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.status.dayOfCycle != status.dayOfCycle ||
      old.status.currentCycleStart != status.currentCycleStart ||
      old.status.typicalCycleLength != status.typicalCycleLength ||
      old.showFertileWindow != showFertileWindow ||
      old.trackColor != trackColor;
}
