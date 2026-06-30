import 'package:flutter/material.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/core/theme.dart';
import 'grid_sync.dart';

class CurrentChordBar extends StatelessWidget {
  final AnalysisResult result;
  final double positionSeconds;
  const CurrentChordBar({super.key, required this.result, required this.positionSeconds});
  @override
  Widget build(BuildContext context) {
    final i = activeChordIndex(result, positionSeconds);
    final cells = result.synchronizedChords;
    final current = i >= 0 ? cells[i].chord : '—';
    final next = (i >= 0 && i + 1 < cells.length) ? cells[i + 1].chord : null;
    return Container(
      padding: const EdgeInsets.all(AppSpace.s16),
      decoration: BoxDecoration(gradient: AppGradients.brand, borderRadius: BorderRadius.circular(AppRadii.lg)),
      child: Row(children: [
        Text(current, style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800)),
        const Spacer(),
        if (next != null)
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('Tiếp theo', style: TextStyle(color: Colors.white70, fontSize: 12)),
            Text(next, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
          ]),
      ]),
    );
  }
}
