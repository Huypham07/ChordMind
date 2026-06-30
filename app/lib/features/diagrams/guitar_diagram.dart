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
      height: 180, width: 160,
      child: CustomPaint(painter: _GuitarPainter(v, color)),
    );
  }
}

class _GuitarPainter extends CustomPainter {
  final GuitarVoicing v;
  final Color color;
  _GuitarPainter(this.v, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    const strings = 6, frets = 5;
    final top = 24.0;
    final gridH = size.height - top;
    final dx = size.width / (strings - 1);
    final dy = gridH / frets;
    final line = Paint()..color = color..strokeWidth = 1;
    // nut (thick top line)
    canvas.drawRect(Rect.fromLTWH(0, top - 3, size.width, 3), Paint()..color = color);
    for (var i = 0; i < strings; i++) {
      canvas.drawLine(Offset(i * dx, top), Offset(i * dx, top + gridH), line);
    }
    for (var f = 0; f <= frets; f++) {
      canvas.drawLine(Offset(0, top + f * dy), Offset(size.width, top + f * dy), line);
    }
    TextPainter tp(String s) => TextPainter(
        text: TextSpan(text: s, style: TextStyle(color: color, fontSize: 12)),
        textDirection: TextDirection.ltr)
      ..layout();
    final dot = Paint()..color = color..style = PaintingStyle.fill;
    for (var s = 0; s < strings; s++) {
      final fret = v.frets[s];
      final x = s * dx;
      if (fret < 0) {
        final t = tp('×'); t.paint(canvas, Offset(x - t.width / 2, 4));
      } else if (fret == 0) {
        canvas.drawCircle(Offset(x, 12), 5, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.5);
      } else {
        canvas.drawCircle(Offset(x, top + (fret - 0.5) * dy), 8, dot);
      }
    }
    // barre
    for (final b in v.barres) {
      final ys = top + (b - 0.5) * dy;
      canvas.drawLine(Offset(0, ys), Offset(size.width, ys),
          Paint()..color = color..strokeWidth = 10..strokeCap = StrokeCap.round);
    }
  }
  @override
  bool shouldRepaint(_) => false;
}
