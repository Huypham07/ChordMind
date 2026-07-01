// app/lib/core/models.dart

class Source {
  final String youtubeId, title;
  final double duration, bpm;
  final int timeSignature;
  Source.fromJson(Map j)
      : youtubeId = j['youtubeId'],
        title = j['title'],
        duration = (j['duration'] as num).toDouble(),
        bpm = (j['bpm'] as num).toDouble(),
        timeSignature = j['timeSignature'];
}

class Beat {
  final double time;
  final int beatNum;
  Beat.fromJson(Map j) : time = (j['time'] as num).toDouble(), beatNum = j['beatNum'];
}

class Chord {
  final String chord;
  final double start, end, confidence;
  Chord.fromJson(Map j)
      : chord = j['chord'],
        start = (j['start'] as num).toDouble(),
        end = (j['end'] as num).toDouble(),
        confidence = (j['confidence'] as num).toDouble();
}

class SyncChord {
  final String chord;
  final int beatIndex;
  SyncChord.fromJson(Map j) : chord = j['chord'], beatIndex = j['beatIndex'];
}

class Segment {
  final String label;
  final double start, end;
  Segment.fromJson(Map j)
      : label = j['label'], start = (j['start'] as num).toDouble(), end = (j['end'] as num).toDouble();
}

class AnalysisResult {
  final String songId, key;
  final Source source;
  final List<Beat> beats;
  final List<double> downbeats;
  final List<Chord> chords;
  final List<SyncChord> synchronizedChords;
  final List<Segment> segments;
  AnalysisResult.fromJson(Map j)
      : songId = j['songId'],
        key = j['key'],
        source = Source.fromJson(j['source']),
        beats = [for (final b in j['beats']) Beat.fromJson(b)],
        downbeats = [for (final d in j['downbeats']) (d as num).toDouble()],
        chords = [for (final c in j['chords']) Chord.fromJson(c)],
        synchronizedChords = [for (final s in j['synchronizedChords']) SyncChord.fromJson(s)],
        segments = [for (final s in j['segments']) Segment.fromJson(s)];
}
