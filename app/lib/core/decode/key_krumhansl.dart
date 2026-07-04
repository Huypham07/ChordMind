// app/lib/core/decode/key_krumhansl.dart
//
// Plan B Task B1.4: estimates the overall key of a decoded chord sequence
// using the Krumhansl-Schmuckler key-finding algorithm.
//
// Pipeline:
//   1. Parse each Chord's label into a root pitch class (0=C .. 11=B) and
//      a set of chord-tone pitch classes (root + quality intervals). 'N'
//      (no chord) and 'X' (unknown) are skipped.
//   2. Build a 12-bin pitch-class histogram, weighting each chord's tones
//      by its duration (end - start), so long-held chords contribute more
//      than fleeting ones.
//   3. Correlate (Pearson) the histogram against the Krumhansl-Schmuckler
//      major and minor key profiles, rotated to all 12 tonics (24
//      candidates total), and pick the highest-correlation candidate.
//   4. Format the winner as "<Note> major" / "<Note> minor" using sharp
//      spelling, matching sample.dart's `'key': 'C major'` convention.
//
// Quality -> chord-tone mapping (semitone intervals from the root). This
// is deliberately approximate for anything beyond triads/7ths: for key
// estimation the triad (root/third/fifth) dominates the profile
// correlation, so extended/altered qualities collapse to their nearest
// triad-plus-seventh shape rather than getting bespoke handling.
//   (no suffix), 'maj'            -> [0, 4, 7]
//   'min', 'm'                    -> [0, 3, 7]
//   'dim'                         -> [0, 3, 6]
//   'aug'                         -> [0, 4, 8]
//   '7' (dominant 7th)            -> [0, 4, 7, 10]
//   'maj7'                        -> [0, 4, 7, 11]
//   'min7', 'm7'                  -> [0, 3, 7, 10]
//   'dim7'                        -> [0, 3, 6, 9]
//   'hdim7', 'm7b5'               -> [0, 3, 6, 10]
//   'sus2'                        -> [0, 2, 7]
//   'sus4'                        -> [0, 5, 7]
//   anything else / unrecognized  -> [0, 4, 7] (major triad fallback)
//
// A bass/inversion suffix after '/' (e.g. "C:maj/5") is ignored: it
// doesn't change the chord's pitch-class *set*, only which tone sounds
// lowest, which is irrelevant to key correlation.
import 'dart:math' as math;

import '../models.dart';

const _noteNames = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
];

const _pitchClassByLetter = {
  'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11,
};

const _qualityIntervals = <String, List<int>>{
  '': [0, 4, 7],
  'maj': [0, 4, 7],
  'min': [0, 3, 7],
  'm': [0, 3, 7],
  'dim': [0, 3, 6],
  'aug': [0, 4, 8],
  '7': [0, 4, 7, 10],
  'maj7': [0, 4, 7, 11],
  'min7': [0, 3, 7, 10],
  'm7': [0, 3, 7, 10],
  'dim7': [0, 3, 6, 9],
  'hdim7': [0, 3, 6, 10],
  'm7b5': [0, 3, 6, 10],
  'sus2': [0, 2, 7],
  'sus4': [0, 5, 7],
};

const _majorProfile = [
  6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88,
];
const _minorProfile = [
  6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17,
];

const defaultKey = 'C major';

/// Parses a root note name (e.g. "C", "C#", "Db", "F#") into a pitch class
/// 0..11, or null if unparseable.
int? _parseRoot(String note) {
  if (note.isEmpty) return null;
  final letter = note[0].toUpperCase();
  final base = _pitchClassByLetter[letter];
  if (base == null) return null;
  var pc = base;
  for (var i = 1; i < note.length; i++) {
    final c = note[i];
    if (c == '#') {
      pc += 1;
    } else if (c == 'b') {
      pc -= 1;
    }
  }
  return pc % 12;
}

/// Parses a chord label (e.g. "C", "C:min", "F#:maj7", "C:maj/5") into its
/// set of pitch classes, or null for 'N'/'X'/unparseable labels.
Set<int>? _chordPitchClasses(String label) {
  if (label == 'N' || label == 'X' || label.isEmpty) return null;

  // Drop bass/inversion suffix; it doesn't change the pitch-class set.
  final withoutBass = label.split('/').first;
  final parts = withoutBass.split(':');
  final rootStr = parts[0];
  final qualityStr = parts.length > 1 ? parts[1] : '';

  final root = _parseRoot(rootStr);
  if (root == null) return null;

  final intervals = _qualityIntervals[qualityStr] ?? _qualityIntervals['maj']!;
  return {for (final iv in intervals) (root + iv) % 12};
}

/// Pearson correlation between two equal-length numeric lists.
double _pearson(List<double> a, List<double> b) {
  final n = a.length;
  final meanA = a.reduce((x, y) => x + y) / n;
  final meanB = b.reduce((x, y) => x + y) / n;
  var num = 0.0, denA = 0.0, denB = 0.0;
  for (var i = 0; i < n; i++) {
    final da = a[i] - meanA;
    final db = b[i] - meanB;
    num += da * db;
    denA += da * da;
    denB += db * db;
  }
  final den = math.sqrt(denA * denB);
  if (den == 0) return 0;
  return num / den;
}

List<double> _rotate(List<double> profile, int tonic) =>
    [for (var i = 0; i < 12; i++) profile[(i - tonic) % 12]];

/// Estimates the overall key of [chords] using the Krumhansl-Schmuckler
/// key-finding algorithm applied to a duration-weighted pitch-class
/// histogram of the chord tones. Returns e.g. "C major" / "A minor".
///
/// Falls back to [defaultKey] ("C major") when there are no usable chords
/// (empty input, or all chords are 'N'/'X'/unparseable).
String estimateKey(List<Chord> chords) {
  final histogram = List<double>.filled(12, 0.0);
  var anyWeight = false;

  for (final chord in chords) {
    final pcs = _chordPitchClasses(chord.chord);
    if (pcs == null) continue;
    final weight = chord.end - chord.start;
    if (weight <= 0) continue;
    for (final pc in pcs) {
      histogram[pc] += weight;
    }
    anyWeight = true;
  }

  if (!anyWeight) return defaultKey;

  var bestScore = double.negativeInfinity;
  var bestTonic = 0;
  var bestIsMajor = true;

  for (var tonic = 0; tonic < 12; tonic++) {
    final majorScore = _pearson(histogram, _rotate(_majorProfile, tonic));
    if (majorScore > bestScore) {
      bestScore = majorScore;
      bestTonic = tonic;
      bestIsMajor = true;
    }
    final minorScore = _pearson(histogram, _rotate(_minorProfile, tonic));
    if (minorScore > bestScore) {
      bestScore = minorScore;
      bestTonic = tonic;
      bestIsMajor = false;
    }
  }

  return '${_noteNames[bestTonic]} ${bestIsMajor ? 'major' : 'minor'}';
}
