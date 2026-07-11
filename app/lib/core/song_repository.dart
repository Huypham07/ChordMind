// app/lib/core/song_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api.dart';
import 'audio_store.dart';
import 'local_store.dart';
import 'model_registry.dart';
import 'models.dart';
import 'on_device_analyzer.dart';
import 'settings_store.dart';

/// Clean-arch boundary: features depend on this, not on ChordMindApi/LocalStore.
abstract class SongRepository {
  /// Server first (source of truth); on failure/offline fall back to the
  /// on-device store. Throws if neither has it (caller offers "generate").
  Future<AnalysisResult> get(String youtubeId);

  /// Run the on-device analyzer (YouTube audio -> PCM -> ONNX chord
  /// inference -> decode -> AnalysisResult) and persist it locally. A
  /// future sync can push locally-generated songs to the server once both
  /// are connected.
  /// [audioFilePath], when given, analyzes that local audio file instead of
  /// fetching from YouTube (fallback for rate-limiting / user-supplied audio).
  Future<AnalysisResult> generate(String youtubeId, {String? title, String? audioFilePath});
}

class DefaultSongRepository implements SongRepository {
  final ChordMindApi _api;
  final LocalStore _local;
  final OnDeviceAnalyzer _analyzer;

  /// Reads the currently-selected chord model name (see
  /// `settings_store.dart`) at generate()-call time, so a later selection
  /// change is honored without rebuilding the repository. Defaults to
  /// always returning the registry default (btc).
  final String Function() _selectedChordModel;
  final AudioStore _audioStore;

  DefaultSongRepository(this._api, this._local,
      [OnDeviceAnalyzer? analyzer, String Function()? selectedChordModel, AudioStore? audioStore])
      : _analyzer = analyzer ?? OnDeviceAnalyzer(),
        _selectedChordModel = selectedChordModel ?? (() => defaultModelName),
        _audioStore = audioStore ?? AudioStore();

  @override
  Future<AnalysisResult> get(String youtubeId) async {
    try {
      return await _api.get(youtubeId);
    } catch (_) {
      final local = await _local.get(youtubeId);
      if (local != null) return local;
      rethrow;
    }
  }

  @override
  Future<AnalysisResult> generate(String youtubeId, {String? title, String? audioFilePath}) async {
    final json = await _analyzer.analyze(youtubeId,
        title: title, modelName: _selectedChordModel(), audioFilePath: audioFilePath);
    if (audioFilePath != null) {
      final stored = await _audioStore.persist(youtubeId, audioFilePath);
      (json['source'] as Map)['audioPath'] = stored;
    }
    await _local.save(youtubeId, json);
    return AnalysisResult.fromJson(json);
  }
}

final songRepositoryProvider = Provider<SongRepository>((ref) => DefaultSongRepository(
      ref.read(apiProvider),
      ref.read(localStoreProvider),
      null,
      () => ref.read(selectedChordModelProvider),
      ref.read(audioStoreProvider),
    ));
