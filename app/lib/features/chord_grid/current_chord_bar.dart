import 'package:flutter/material.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/core/transpose.dart';

class CurrentChordBar extends StatelessWidget {
  final AnalysisResult result;
  final double positionSeconds;
  final int semitones;
  final String songKey;
  const CurrentChordBar(
      {super.key,
      required this.result,
      required this.positionSeconds,
      this.semitones = 0,
      this.songKey = 'C major'});
  @override
  Widget build(BuildContext context) {
    // Real chord segments (skip N/X), matched to real playback time — same basis
    // as ChordTimeline, so the banner stays in sync with the audio.
    final segs = <({String label, double start, double end})>[];
    for (final c in result.chords) {
      final lbl = shortChord(transposeChord(c.chord, semitones, key: songKey));
      if (lbl.isNotEmpty) segs.add((label: lbl, start: c.start, end: c.end));
    }
    final i = segs.indexWhere((s) => positionSeconds >= s.start && positionSeconds < s.end);
    final current = i >= 0 ? segs[i].label : '—';
    final next = (i >= 0 && i + 1 < segs.length) ? segs[i + 1].label : null;
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
