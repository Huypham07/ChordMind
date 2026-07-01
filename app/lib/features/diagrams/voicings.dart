import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// One guitar fingering. [frets] is 6 strings low→high; -1 muted, 0 open, else a
/// fret **relative to [baseFret]** (the first fret of the shown window). [barres]
/// lists barred fret values (relative).
class GuitarVoicing {
  final List<int> frets;
  final int baseFret;
  final List<int> barres;
  const GuitarVoicing(this.frets, {this.baseFret = 1, this.barres = const []});
}

// Parsed chords-db dataset: dbKey → suffix → all positions. Loaded once.
Map<String, Map<String, List<GuitarVoicing>>>? _db;

/// Load & cache the bundled chords-db voicings. Call once at startup.
/// ponytail: global cache; the dataset is tiny and read-only.
Future<void> loadGuitarDb() async {
  if (_db != null) return;
  final raw = jsonDecode(await rootBundle.loadString('assets/data/guitar.json')) as Map;
  final out = <String, Map<String, List<GuitarVoicing>>>{};
  (raw['chords'] as Map).forEach((key, entries) {
    final bySuffix = <String, List<GuitarVoicing>>{};
    for (final e in entries as List) {
      bySuffix[e['suffix'] as String] = [
        for (final pos in e['positions'] as List)
          GuitarVoicing(
            [for (final f in pos['frets'] as List) (f as num).toInt()],
            baseFret: (pos['baseFret'] as num?)?.toInt() ?? 1,
            barres: [for (final b in (pos['barres'] as List? ?? const [])) (b as num).toInt()],
          ),
      ];
    }
    out[key as String] = bySuffix;
  });
  _db = out;
}

// Our chord root → the dataset's key name (sharps: Csharp/Fsharp; rest flats).
const _dbKey = {
  'C': 'C', 'B#': 'C', 'C#': 'Csharp', 'Db': 'Csharp', 'D': 'D', 'D#': 'Eb',
  'Eb': 'Eb', 'E': 'E', 'Fb': 'E', 'F': 'F', 'E#': 'F', 'F#': 'Fsharp',
  'Gb': 'Fsharp', 'G': 'G', 'G#': 'Ab', 'Ab': 'Ab', 'A': 'A', 'A#': 'Bb',
  'Bb': 'Bb', 'B': 'B', 'Cb': 'B',
};

// Our chord suffix → the dataset's suffix. Unmapped suffixes are tried verbatim.
const _sfx = {
  '': 'major', 'maj': 'major', 'M': 'major',
  'm': 'minor', 'min': 'minor',
  'm7': 'm7', 'min7': 'm7',
  'maj7': 'maj7', 'M7': 'maj7',
  '7': '7', 'dom7': '7',
  '6': '6', 'm6': 'm6', '69': '69',
  '9': '9', 'm9': 'm9', 'maj9': 'maj9',
  'add9': 'add9', 'madd9': 'madd9',
  'dim': 'dim', 'dim7': 'dim7', 'm7b5': 'm7b5',
  'aug': 'aug', '+': 'aug',
  'sus2': 'sus2', 'sus4': 'sus4', 'sus': 'sus4', '7sus4': '7sus4',
  '11': '11', '13': '13', 'maj11': 'maj11', 'maj13': 'maj13',
};

/// All guitar fingerings for [chord] (e.g. "F#m7"), easiest first, or empty if
/// unknown / not loaded. Slash bass is ignored — we show the base chord shape.
List<GuitarVoicing> guitarVoicings(String chord) {
  final db = _db;
  if (db == null || chord.isEmpty) return const [];
  final base = chord.split('/').first;
  if (base.isEmpty) return const [];
  final rootLen = (base.length > 1 && (base[1] == '#' || base[1] == 'b')) ? 2 : 1;
  final key = _dbKey[base.substring(0, rootLen)];
  if (key == null) return const [];
  final rem = base.substring(rootLen);
  final suffix = _sfx[rem] ?? rem;
  final byS = db[key];
  if (byS == null) return const [];
  // Fall back to the plain triad shape (keeping major/minor quality) if the exact
  // suffix isn't in the dataset.
  final fallback = (rem.startsWith('m') && !rem.startsWith('maj')) ? 'minor' : 'major';
  return byS[suffix] ?? byS[fallback] ?? const [];
}

const _roots = {'C': 0, 'C#': 1, 'Db': 1, 'D': 2, 'D#': 3, 'Eb': 3, 'E': 4, 'F': 5,
  'F#': 6, 'Gb': 6, 'G': 7, 'G#': 8, 'Ab': 8, 'A': 9, 'A#': 10, 'Bb': 10, 'B': 11};

List<int> pianoNotes(String chord) {
  final isMinor = chord.contains('m') && !chord.contains('maj');
  final rootName = chord.replaceAll(RegExp(r'(m|maj|7|dim|aug|sus).*$'), '');
  final root = _roots[rootName] ?? 0;
  final third = isMinor ? 3 : 4;
  return [root, (root + third) % 12, (root + 7) % 12];
}
