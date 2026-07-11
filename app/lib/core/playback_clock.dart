/// Smooths a low-frequency / jittery playback position stream into a
/// per-frame estimate so the chord highlight tracks the audio without
/// stepping (esp. the ~1 Hz YouTube position stream). Assumes playback
/// rate 1.0.
///
/// Feed real position ticks via [anchor]; read the interpolated position via
/// [estimate] each frame.
class PlaybackClock {
  PlaybackClock({this.maxExtrapolation = 1.5});

  /// Max seconds to extrapolate past the last anchor before clamping, so a
  /// stalled/buffering stream can't run the estimate away from reality.
  final double maxExtrapolation;

  /// Song length (seconds) for the upper clamp; 0 = unknown (no clamp).
  double duration = 0;

  double _anchorPos = 0;
  DateTime? _anchorWall;
  bool _playing = false;

  /// Records a real position tick. [now] defaults to `DateTime.now()`
  /// (injectable for tests).
  void anchor(double posSeconds, {required bool playing, DateTime? now}) {
    _anchorPos = posSeconds;
    _anchorWall = now ?? DateTime.now();
    _playing = playing;
  }

  /// Interpolated position at [now]: frozen at the last anchor when paused;
  /// forward-only extrapolation while playing, clamped to [maxExtrapolation]
  /// past the anchor and to [duration].
  double estimate(DateTime now) {
    final wall = _anchorWall;
    if (wall == null || !_playing) return _clampTop(_anchorPos);
    var elapsed = now.difference(wall).inMicroseconds / 1e6;
    if (elapsed < 0) elapsed = 0; // forward-only between anchors
    if (elapsed > maxExtrapolation) elapsed = maxExtrapolation;
    return _clampTop(_anchorPos + elapsed);
  }

  double _clampTop(double v) => (duration > 0 && v > duration) ? duration : v;
}
