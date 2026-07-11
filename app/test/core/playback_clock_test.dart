import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/playback_clock.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 0, 0, 0);
  DateTime at(double s) => t0.add(Duration(microseconds: (s * 1e6).round()));

  test('interpolates forward while playing', () {
    final c = PlaybackClock();
    c.anchor(5.0, playing: true, now: t0);
    expect(c.estimate(at(0.5)), closeTo(5.5, 1e-6));
  });

  test('frozen at anchor while paused', () {
    final c = PlaybackClock();
    c.anchor(5.0, playing: false, now: t0);
    expect(c.estimate(at(2.0)), closeTo(5.0, 1e-9));
  });

  test('new anchor re-bases (seek back allowed)', () {
    final c = PlaybackClock();
    c.anchor(30.0, playing: true, now: t0);
    c.anchor(2.0, playing: true, now: at(1.0)); // user sought backward
    expect(c.estimate(at(1.2)), closeTo(2.2, 1e-6));
  });

  test('clamps to duration', () {
    final c = PlaybackClock()..duration = 10.0;
    c.anchor(9.8, playing: true, now: t0);
    expect(c.estimate(at(1.0)), closeTo(10.0, 1e-9)); // 9.8+1.0 clamped to 10
  });

  test('clamps to maxExtrapolation when stream stalls', () {
    final c = PlaybackClock(maxExtrapolation: 1.5);
    c.anchor(5.0, playing: true, now: t0);
    expect(c.estimate(at(10.0)), closeTo(6.5, 1e-9)); // 5.0 + 1.5 cap
  });

  test('forward-only: a slightly-late now never goes below the anchor', () {
    final c = PlaybackClock();
    c.anchor(5.0, playing: true, now: t0);
    expect(c.estimate(at(-0.1)), closeTo(5.0, 1e-9));
  });
}
