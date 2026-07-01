import 'package:flutter/material.dart';
import 'voicings.dart';

class GuitarDiagram extends StatelessWidget {
  final GuitarVoicing v;
  final String? name;
  const GuitarDiagram(this.v, {super.key, this.name});
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      height: 190,
      width: 180,
      child: CustomPaint(painter: _GuitarPainter(v, color, color.withValues(alpha: 0.45))),
    );
  }
}

class _GuitarPainter extends CustomPainter {
  final GuitarVoicing v;
  final Color color;
  final Color muted;
  _GuitarPainter(this.v, this.color, this.muted);

  static const _strings = 6;
  static const _frets = 5; // fret rows shown in the window

  @override
  void paint(Canvas canvas, Size size) {
    const top = 26.0;
    const left = 20.0; // room for per-row fret numbers
    final gridW = size.width - left;
    final gridH = size.height - top;
    final dx = gridW / (_strings - 1);
    final dy = gridH / _frets;
    double sx(int s) => left + s * dx;

    final line = Paint()
      ..color = color
      ..strokeWidth = 1;
    final atNut = v.baseFret <= 1;

    // Top edge: thick nut only when the window starts at fret 1.
    if (atNut) {
      canvas.drawRect(Rect.fromLTWH(left, top - 3, gridW, 3), Paint()..color = color);
    } else {
      canvas.drawLine(const Offset(left, top), Offset(left + gridW, top), line);
    }
    for (var i = 0; i < _strings; i++) {
      canvas.drawLine(Offset(sx(i), top), Offset(sx(i), top + gridH), line);
    }
    for (var f = 0; f <= _frets; f++) {
      canvas.drawLine(Offset(left, top + f * dy), Offset(left + gridW, top + f * dy), line);
      // Always number the frets so the player knows the position.
      if (f < _frets) {
        _text(canvas, '${v.baseFret + f}', Offset(2, top + (f + 0.5) * dy - 6), 9, muted);
      }
    }

    // Barres first (under the dots): span the strings pressed at that fret.
    final barre = Paint()
      ..color = color
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round;
    final barred = <int>{...v.barres};
    for (final bf in v.barres) {
      var lo = _strings, hi = -1;
      for (var s = 0; s < _strings; s++) {
        if (v.frets[s] == bf) {
          if (s < lo) lo = s;
          if (s > hi) hi = s;
        }
      }
      if (hi < 0) continue;
      final y = top + (bf - 0.5) * dy;
      canvas.drawLine(Offset(sx(lo), y), Offset(sx(hi), y), barre);
    }

    final dot = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (var s = 0; s < _strings; s++) {
      final fret = v.frets[s];
      final x = sx(s);
      if (fret < 0) {
        _text(canvas, '×', Offset(x, 4), 12, color, center: true);
      } else if (fret == 0) {
        canvas.drawCircle(Offset(x, 13), 5,
            Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.5);
      } else if (!barred.contains(fret)) {
        // A barred string is already covered by the barre bar — no extra dot.
        canvas.drawCircle(Offset(x, top + (fret - 0.5) * dy), 8, dot);
      }
    }
  }

  void _text(Canvas canvas, String s, Offset at, double fontSize, Color c, {bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: c, fontSize: fontSize)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center ? Offset(at.dx - tp.width / 2, at.dy) : at);
  }

  @override
  bool shouldRepaint(_GuitarPainter old) => old.v != v;
}
