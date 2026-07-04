import 'package:flutter/material.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/core/transpose.dart';
import 'grid_sync.dart';

/// ChordMiniApp-style grid: fixed per-beat cells grouped into measures, chords
/// sit in the cell where they start, and a cursor sweeps beat-by-beat with playback.
class ChordGrid extends StatelessWidget {
  final AnalysisResult result;
  final double positionSeconds;
  final int semitones;
  final String songKey;
  final void Function(String chord)? onTapChord;
  const ChordGrid({
    super.key,
    required this.result,
    required this.positionSeconds,
    this.semitones = 0,
    this.songKey = 'C major',
    this.onTapChord,
  });

  String? _segmentAt(double time) {
    for (final s in result.segments) {
      if (time >= s.start && time < s.end) return s.label;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    final beats = result.beats;
    if (beats.isEmpty) {
      return Center(child: Text('Chưa có dữ liệu hợp âm', style: TextStyle(color: cm.textMuted)));
    }
    final ts = result.source.timeSignature.clamp(2, 4);
    final activeBeat = activeBeatIndex(result, positionSeconds);

    // chord label at each chord-start beat + the chord in effect on every beat
    final labelAt = <int, String>{};
    for (final sc in result.synchronizedChords) {
      if (sc.beatIndex >= 0 && sc.beatIndex < beats.length) {
        final lbl = shortChord(transposeChord(sc.chord, semitones, key: songKey));
        if (lbl.isNotEmpty) labelAt[sc.beatIndex] = lbl; // skip N/X (no chord)
      }
    }
    final chordPerBeat = List<String?>.filled(beats.length, null);
    String? cur;
    for (var i = 0; i < beats.length; i++) {
      if (labelAt.containsKey(i)) cur = labelAt[i];
      chordPerBeat[i] = cur;
    }

    final nMeasures = (beats.length + ts - 1) ~/ ts;

    return LayoutBuilder(builder: (context, c) {
      final measuresPerRow = c.maxWidth < 600 ? 2 : 4;
      final children = <Widget>[];
      var m = 0;
      String? lastSeg;
      while (m < nMeasures) {
        final seg = _segmentAt(beats[m * ts].time);
        if (seg != lastSeg) {
          children.add(_SegHeader(label: seg ?? '', color: AppAccents.segment(seg ?? '')));
          lastSeg = seg;
        }
        final rowMeasures = <int>[];
        while (rowMeasures.length < measuresPerRow && m < nMeasures) {
          if (_segmentAt(beats[m * ts].time) != lastSeg) break;
          rowMeasures.add(m);
          m++;
        }
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.s8),
          child: Row(children: [
            for (final mm in rowMeasures)
              _Measure(
                startBeat: mm * ts,
                ts: ts,
                beats: beats,
                labelAt: labelAt,
                chordPerBeat: chordPerBeat,
                activeBeat: activeBeat,
                segColor: AppAccents.segment(lastSeg ?? ''),
                cm: cm,
                onTapChord: onTapChord,
              ),
            for (var k = rowMeasures.length; k < measuresPerRow; k++) const Expanded(child: SizedBox()),
          ]),
        ));
      }
      return ListView(padding: const EdgeInsets.all(AppSpace.s16), children: children);
    });
  }
}

class _SegHeader extends StatelessWidget {
  final String label;
  final Color color;
  const _SegHeader({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s8),
      child: Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: AppSpace.s8),
        Text(label.toUpperCase(),
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 1.2, color: color)),
        const SizedBox(width: AppSpace.s12),
        Expanded(child: Divider(color: cm.border, height: 1)),
      ]),
    );
  }
}

class _Measure extends StatelessWidget {
  final int startBeat;
  final int ts;
  final List<Beat> beats;
  final Map<int, String> labelAt;
  final List<String?> chordPerBeat;
  final int activeBeat;
  final Color segColor;
  final ChordMindColors cm;
  final void Function(String chord)? onTapChord;
  const _Measure({
    required this.startBeat,
    required this.ts,
    required this.beats,
    required this.labelAt,
    required this.chordPerBeat,
    required this.activeBeat,
    required this.segColor,
    required this.cm,
    required this.onTapChord,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          border: Border.all(color: segColor.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(children: [
          for (var b = startBeat; b < startBeat + ts && b < beats.length; b++)
            _BeatCell(
              label: labelAt[b],
              chord: chordPerBeat[b],
              active: b == activeBeat,
              cm: cm,
              onTapChord: onTapChord,
            ),
        ]),
      ),
    );
  }
}

class _BeatCell extends StatelessWidget {
  final String? label;
  final String? chord;
  final bool active;
  final ChordMindColors cm;
  final void Function(String chord)? onTapChord;
  const _BeatCell({
    required this.label,
    required this.chord,
    required this.active,
    required this.cm,
    required this.onTapChord,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.sm);
    return Expanded(
      child: GestureDetector(
        onTap: chord != null ? () => onTapChord?.call(chord!) : null,
        // Base: theme-driven colour, changes instantly on theme toggle (no tween).
        child: Container(
          height: 50,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: label != null ? cm.chordIdle : Colors.transparent,
            borderRadius: radius,
          ),
          // Highlight: only the beat cursor animates, and it uses fixed colours,
          // so switching theme has nothing to tween here.
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              gradient: active ? const LinearGradient(colors: [AppAccents.cyan, AppAccents.blue]) : null,
              borderRadius: radius,
              boxShadow: active
                  ? [BoxShadow(color: AppAccents.cyan.withValues(alpha: 0.5), blurRadius: 14, spreadRadius: 1)]
                  : null,
            ),
            alignment: Alignment.center,
            child: label != null
                ? Text(label!,
                    maxLines: 1,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        // Explicit colour (not null) so it doesn't inherit Material's
                        // AnimatedDefaultTextStyle, which fades text over ~200ms on
                        // theme change. Explicit → instant, like the home screen.
                        color: active ? Colors.white : Theme.of(context).colorScheme.onSurface))
                : Text(active ? '' : '·', style: TextStyle(color: cm.textMuted, fontSize: 12)),
          ),
        ),
      ),
    );
  }
}
