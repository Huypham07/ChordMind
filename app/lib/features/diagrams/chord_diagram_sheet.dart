import 'package:flutter/material.dart';
import 'package:chordmind/core/theme.dart';
import 'voicings.dart';
import 'guitar_diagram.dart';
import 'piano_diagram.dart';

class ChordDiagramView extends StatefulWidget {
  final String? chord;
  const ChordDiagramView({super.key, this.chord});
  @override
  State<ChordDiagramView> createState() => _ChordDiagramViewState();
}

class _ChordDiagramViewState extends State<ChordDiagramView> {
  int _pos = 0;

  @override
  void didUpdateWidget(ChordDiagramView old) {
    super.didUpdateWidget(old);
    if (old.chord != widget.chord) _pos = 0; // reset position when chord changes
  }

  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    final chord = widget.chord;
    if (chord == null) {
      return Center(child: Text('Chọn một hợp âm để xem thế bấm',
          style: TextStyle(color: cm.textMuted)));
    }
    final voicings = guitarVoicings(chord);
    final pos = voicings.isEmpty ? 0 : _pos.clamp(0, voicings.length - 1);
    return Padding(
      padding: const EdgeInsets.all(AppSpace.s24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text(chord, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpace.s24),
        if (voicings.isNotEmpty) ...[
          GuitarDiagram(voicings[pos], name: chord),
          if (voicings.length > 1) _PositionSelector(
            index: pos,
            count: voicings.length,
            onPrev: () => setState(() => _pos = (pos - 1) % voicings.length),
            onNext: () => setState(() => _pos = (pos + 1) % voicings.length),
          ),
        ],
        const SizedBox(height: AppSpace.s24),
        PianoDiagram(pianoNotes(chord)),
      ]),
    );
  }
}

/// ‹ 2/5 › cycler for a chord's alternative fingerings.
class _PositionSelector extends StatelessWidget {
  final int index, count;
  final VoidCallback onPrev, onNext;
  const _PositionSelector(
      {required this.index, required this.count, required this.onPrev, required this.onNext});
  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton(icon: const Icon(Icons.chevron_left), onPressed: onPrev, visualDensity: VisualDensity.compact),
      Text('Thế ${index + 1}/$count', style: TextStyle(color: cm.textMuted, fontWeight: FontWeight.w600)),
      IconButton(icon: const Icon(Icons.chevron_right), onPressed: onNext, visualDensity: VisualDensity.compact),
    ]);
  }
}

void showChordDiagram(BuildContext context, String chord) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    // Scrollable + safe-area padded so tall diagrams never bottom-overflow on
    // small screens.
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: ChordDiagramView(chord: chord),
      ),
    ),
  );
}
