import '../../core/models.dart';

/// The local audio file to play/analyze for this song: the router-provided
/// path (fresh upload) if present, else the persisted path recorded on a
/// re-opened file song's analysis.
String? effectiveAudioPath(String? widgetPath, AnalysisResult? result) =>
    widgetPath ?? result?.source.audioPath;
