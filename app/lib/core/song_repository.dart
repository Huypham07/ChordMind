// app/lib/core/song_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api.dart';
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
  Future<AnalysisResult> generate(String youtubeId, {String? title});
}

class DefaultSongRepository implements SongRepository {
  final ChordMindApi _api;
  final LocalStore _local;
  final OnDeviceAnalyzer _analyzer;

  /// Reads the currently-selected chord model name (see
  /// `settings_store.dart`) at generate()-call time, so a later selection
  /// change is honored without rebuilding the repository. Defaults to
  /// always returning the registry default (chordnet_2e1d).
  final String Function() _selectedChordModel;

  DefaultSongRepository(this._api, this._local,
      [OnDeviceAnalyzer? analyzer, String Function()? selectedChordModel])
      : _analyzer = analyzer ?? OnDeviceAnalyzer(),
        _selectedChordModel = selectedChordModel ?? (() => defaultModelName);

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
  Future<AnalysisResult> generate(String youtubeId, {String? title}) async {
    final json = await _analyzer.analyze(youtubeId, title: title, modelName: _selectedChordModel());
    await _local.save(youtubeId, json);
    return AnalysisResult.fromJson(json);
  }
}

final songRepositoryProvider = Provider<SongRepository>((ref) => DefaultSongRepository(
      ref.read(apiProvider),
      ref.read(localStoreProvider),
      null,
      () => ref.read(selectedChordModelProvider),
    ));
