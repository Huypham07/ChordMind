// app/lib/core/transpose.dart
//
// Key-aware chord spelling. Instead of a blanket "all sharps" or "all flats",
// each accidental is chosen by its position on the line of fifths relative to
// the (transposed) key centre — so e.g. in C major we get Eb/Ab/Bb (flats) for
// the borrowed bIII/bVI/bVII but F#/C# (sharps) for the #IV/#I, matching how a
// musician would actually write them.

const _index = {
  'C': 0, 'B#': 0, 'C#': 1, 'DB': 1, 'D': 2, 'D#': 3, 'EB': 3, 'E': 4, 'FB': 4,
  'F': 5, 'E#': 5, 'F#': 6, 'GB': 6, 'G': 7, 'G#': 8, 'AB': 8, 'A': 9, 'A#': 10,
  'BB': 10, 'B': 11, 'CB': 11,
};

// Natural (white-key) pitch classes → letter.
const _natural = {0: 'C', 2: 'D', 4: 'E', 5: 'F', 7: 'G', 9: 'A', 11: 'B'};
// Black-key pitch classes → the two spellings and their line-of-fifths position.
const _sharpName = {1: 'C#', 3: 'D#', 6: 'F#', 8: 'G#', 10: 'A#'};
const _flatName = {1: 'Db', 3: 'Eb', 6: 'Gb', 8: 'Ab', 10: 'Bb'};
const _sharpFifths = {1: 7, 3: 9, 6: 6, 8: 8, 10: 10};
const _flatFifths = {1: -5, 3: -3, 6: -6, 8: -4, 10: -2};

/// Harte quality suffix (after ':') -> common short form.
const _shortQuality = {
  'maj': '', '': '', 'major': '',
  'min': 'm', 'minor': 'm',
  'dim': 'dim', 'aug': 'aug',
  '7': '7', 'maj7': 'maj7', 'min7': 'm7', 'minmaj7': 'm(maj7)',
  '6': '6', 'maj6': '6', 'min6': 'm6',
  '9': '9', 'maj9': 'maj9', 'min9': 'm9',
  'dim7': 'dim7', 'hdim7': 'm7b5', 'min7b5': 'm7b5',
  'sus2': 'sus2', 'sus4': 'sus4', 'sus4(b7)': '7sus4',
};

/// Abbreviate a Harte-style chord label ("A:min7", "F#:maj", "C:min/b3") to the
/// short form musicians write ("Am7", "F#", "Cm/b3"). Leaves 'N'/'X' and the
/// empty/placeholder markers untouched. Root spelling is preserved (call
/// [transposeChord] first if transposing).
String shortChord(String chord) {
  // 'N' (no chord) and 'X' (unknown) render as nothing — we only show real chords.
  if (chord == 'N' || chord == 'X') return '';
  if (chord.isEmpty || chord == '—' || chord == '·') return chord;
  final slash = chord.split('/');
  final parts = slash[0].split(':');
  final root = parts[0];
  final qual = parts.length > 1 ? parts[1] : '';
  final suffix = _shortQuality[qual] ?? qual; // unknown quality: keep as-is
  final bass = slash.length > 1 ? '/${slash[1]}' : '';
  return '$root$suffix$bass';
}

/// Transpose [chord] by [semitones], spelling accidentals to fit the resulting
/// key. [key] is the song key ("C major" / "A minor"). Preserves the suffix and
/// slash-bass; unrecognized roots are left alone.
String transposeChord(String chord, int semitones, {String key = 'C major'}) {
  if (semitones % 12 == 0) return chord;
  final centre = _spellCentre(key, semitones);
  return chord.split('/').map((p) => _shiftRoot(p, semitones, centre)).join('/');
}

String _shiftRoot(String part, int semitones, int centre) {
  if (part.isEmpty) return part;
  final rootLen = (part.length > 1 && (part[1] == '#' || part[1] == 'b')) ? 2 : 1;
  final pc = _index[part.substring(0, rootLen).toUpperCase()];
  if (pc == null) return part;
  final target = ((pc + semitones) % 12 + 12) % 12;
  return _spell(target, centre) + part.substring(rootLen);
}

/// Spell a pitch class near the key centre (on the line of fifths). White keys
/// stay natural; black keys pick the sharp/flat closest to the centre (ties → flat).
String _spell(int pc, int centre) {
  final nat = _natural[pc];
  if (nat != null) return nat;
  final ds = (_sharpFifths[pc]! - centre).abs();
  final df = (_flatFifths[pc]! - centre).abs();
  return ds < df ? _sharpName[pc]! : _flatName[pc]!;
}

/// Line-of-fifths centre used to spell chords in [key] after transposing by
/// [semitones]. Minor keys borrow their relative major's signature.
int _spellCentre(String key, int semitones) {
  final rootName = key.trim().split(RegExp(r'\s+')).first;
  final pc = _index[rootName.toUpperCase()] ?? 0;
  final tonic = ((pc + semitones) % 12 + 12) % 12;
  final majorPc = key.toLowerCase().contains('min') ? (tonic + 3) % 12 : tonic;
  return _tonicFifths(majorPc) + 2; // +2 keeps the diatonic notes inside the window
}

/// Fifths position of a major tonic, choosing the spelling with fewer
/// accidentals (e.g. Db over C# for pitch class 1).
int _tonicFifths(int pc) {
  final sharp = (pc * 7) % 12; // 0..11, sharp-side representative
  final flat = sharp - 12;
  return sharp.abs() <= flat.abs() ? sharp : flat;
}
