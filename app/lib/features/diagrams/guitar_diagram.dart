import 'package:flutter/material.dart';
import 'voicings.dart';

class GuitarDiagram extends StatelessWidget {
  final GuitarVoicing v;
  const GuitarDiagram(this.v, {super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 160,
        child: CustomPaint(painter: _GuitarPainter(v, Theme.of(context).colorScheme.onSurface)),
      );
}

class _GuitarPainter extends CustomPainter {
  final GuitarVoicing v;
  final Color color;
  _GuitarPainter(this.v, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    const strings = 6, frets = 5;
    final dx = size.width / (strings - 1), dy = size.height / frets;
    final p = Paint()..color = color..strokeWidth = 1;
    for (var i = 0; i < strings; i++) {
      canvas.drawLine(Offset(i * dx, 0), Offset(i * dx, size.height), p);
    }
    for (var f = 0; f <= frets; f++) {
      canvas.drawLine(Offset(0, f * dy), Offset(size.width, f * dy), p);
    }
    final dot = Paint()..color = color..style = PaintingStyle.fill;
    for (var s = 0; s < strings; s++) {
      final fret = v.frets[s];
      if (fret > 0) {
        canvas.drawCircle(Offset(s * dx, (fret - 0.5) * dy), 7, dot);
      }
    }
  }
  @override
  bool shouldRepaint(_) => false;
}
