// app/test/decode/key_krumhansl_test.dart
import 'package:chordmind/core/decode/key_krumhansl.dart';
import 'package:chordmind/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

Chord _c(String chord, double start, double end) =>
    Chord.fromJson({'chord': chord, 'start': start, 'end': end, 'confidence': 1.0});

void main() {
  group('estimateKey', () {
    test('C-F-G-C equal durations -> C major', () {
      final chords = [
        _c('C', 0, 2),
        _c('F', 2, 4),
        _c('G', 4, 6),
        _c('C', 6, 8),
      ];
      expect(estimateKey(chords), 'C major');
    });

    test('Am-Dm-E-Am equal durations -> A minor', () {
      final chords = [
        _c('A:min', 0, 2),
        _c('D:min', 2, 4),
        _c('E', 4, 6),
        _c('A:min', 6, 8),
      ];
      expect(estimateKey(chords), 'A minor');
    });

    test('G-C-D-G equal durations -> G major', () {
      final chords = [
        _c('G', 0, 2),
        _c('C', 2, 4),
        _c('D', 4, 6),
        _c('G', 6, 8),
      ];
      expect(estimateKey(chords), 'G major');
    });

    test('duration weighting: long-held chord outweighs many short ones', () {
      // Ten brief, unrelated minor stabs (1s total) vs. one long C major
      // triad (100s). If chords were counted one-vote-each regardless of
      // duration, the ten minor stabs would win; duration-weighting must
      // let the single long C dominate instead.
      final chords = [
        for (var i = 0; i < 10; i++) _c('F#:min', i * 0.1, i * 0.1 + 0.1),
        _c('C', 10, 110),
      ];
      expect(estimateKey(chords), 'C major');
    });

    test('N and X are ignored', () {
      final chords = [
        _c('N', 0, 100),
        _c('C', 100, 102),
        _c('F', 102, 104),
        _c('G', 104, 106),
        _c('C', 106, 108),
        _c('X', 108, 200),
      ];
      expect(estimateKey(chords), 'C major');
    });

    test('empty list -> default C major', () {
      expect(estimateKey([]), 'C major');
    });

    test('all N -> default C major', () {
      expect(estimateKey([_c('N', 0, 10)]), 'C major');
    });
  });
}
