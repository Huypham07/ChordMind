// app/lib/core/transpose.dart

const _sharp = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];

const _index = {
  'C': 0, 'B#': 0, 'C#': 1, 'DB': 1, 'D': 2, 'D#': 3, 'EB': 3, 'E': 4, 'FB': 4,
  'F': 5, 'E#': 5, 'F#': 6, 'GB': 6, 'G': 7, 'G#': 8, 'AB': 8, 'A': 9, 'A#': 10,
  'BB': 10, 'B': 11, 'CB': 11,
};

/// Shift a chord label by [semitones] (e.g. "Am7" +2 → "Bm7", "C/G" +2 → "D/A").
/// Preserves the suffix and slash-bass; unrecognized roots are left untouched.
String transposeChord(String chord, int semitones) {
  if (semitones % 12 == 0) return chord;
  return chord.split('/').map((p) => _shiftRoot(p, semitones)).join('/');
}

String _shiftRoot(String part, int semitones) {
  if (part.isEmpty) return part;
  final rootLen = (part.length > 1 && (part[1] == '#' || part[1] == 'b')) ? 2 : 1;
  final i = _index[part.substring(0, rootLen).toUpperCase()];
  if (i == null) return part;
  return _sharp[(i + semitones) % 12] + part.substring(rootLen);
}
