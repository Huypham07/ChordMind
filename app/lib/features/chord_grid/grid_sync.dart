import 'package:chordmind/core/models.dart';

/// Playback→highlight lead compensation (seconds). The highlight otherwise
/// trails the music: onset/beat detection lags the audio by ~1 onset frame,
/// and the device plays sound a little after the reported playback position.
/// We look up the active chord slightly AHEAD of the reported position to
/// cancel that, so the label changes right when you hear the chord.
/// ponytail: one global calibration knob — promote to a per-device settings
/// slider if a single value doesn't fit all devices.
const chordSyncLeadSeconds = 0.15;

/// Index into [r.beats] of the beat sounding at [pos] seconds, or -1.
/// Each beat spans from its time to the next beat's time (last → song end).
int activeBeatIndex(AnalysisResult r, double pos) {
  final b = r.beats;
  final p = pos + chordSyncLeadSeconds;
  for (var i = 0; i < b.length; i++) {
    final end = (i + 1 < b.length) ? b[i + 1].time : r.source.duration;
    if (p >= b[i].time && p < end) return i;
  }
  return -1;
}

/// Index into [r.synchronizedChords] of the cell sounding at [pos] seconds, or -1.
/// Each cell spans from its beat time to the next cell's beat time
/// (the last cell extends to the song's end).
int activeChordIndex(AnalysisResult r, double pos) {
  final cells = r.synchronizedChords;
  final p = pos + chordSyncLeadSeconds;
  for (var i = 0; i < cells.length; i++) {
    final start = r.beats[cells[i].beatIndex].time;
    final end = (i + 1 < cells.length)
        ? r.beats[cells[i + 1].beatIndex].time
        : r.source.duration;
    if (p >= start && p < end) return i;
  }
  return -1;
}
