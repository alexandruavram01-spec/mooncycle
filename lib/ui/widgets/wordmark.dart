import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The MoonCycle logo as text, with a crescent moon standing in for the
/// capital C: Moon☾ycle.
///
/// The crescent is drawn rather than typed, so it looks the same everywhere
/// instead of depending on which fonts a phone or browser has.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 24, this.color});

  final double size;

  /// Defaults to the theme's primary colour: rose in Dawn, gold in Night.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colour = color ?? Theme.of(context).colorScheme.primary;
    return Semantics(
      label: 'MoonCycle',
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          style: GoogleFonts.gelasio(
            fontSize: size,
            color: colour,
            fontWeight: FontWeight.w500,
          ),
          children: [
            const TextSpan(text: 'Moon'),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: EdgeInsets.only(left: size * 0.04, right: size * 0.02),
                child: CustomPaint(
                  size: Size(size * 0.5, size * 0.78),
                  painter: _CrescentPainter(colour),
                ),
              ),
            ),
            const TextSpan(text: 'ycle'),
          ],
        ),
      ),
    );
  }
}

/// A crescent opening to the right, like the letter C it replaces.
class _CrescentPainter extends CustomPainter {
  _CrescentPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;
    final centre = Offset(r, size.height / 2);
    final moon = Path()..addOval(Rect.fromCircle(center: centre, radius: r));
    final shadow = Path()
      ..addOval(
        Rect.fromCircle(center: centre + Offset(r * 0.42, 0), radius: r * 0.9),
      );
    canvas.drawPath(
      Path.combine(PathOperation.difference, moon, shadow),
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_CrescentPainter old) => old.color != color;
}
