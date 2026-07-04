// app/lib/core/song_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api.dart';
import 'local_store.dart';
import 'models.dart';
import 'on_device_analyzer.dart';

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
  DefaultSongRepository(this._api, this._local, [OnDeviceAnalyzer? analyzer])
      : _analyzer = analyzer ?? OnDeviceAnalyzer();

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
    final json = await _analyzer.analyze(youtubeId, title: title);
    await _local.save(youtubeId, json);
    return AnalysisResult.fromJson(json);
  }
}

final songRepositoryProvider = Provider<SongRepository>(
    (ref) => DefaultSongRepository(ref.read(apiProvider), ref.read(localStoreProvider)));
