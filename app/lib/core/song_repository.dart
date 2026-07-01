// app/lib/core/song_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api.dart';
import 'local_store.dart';
import 'models.dart';
import 'sample.dart';

/// Clean-arch boundary: features depend on this, not on ChordMindApi/LocalStore.
abstract class SongRepository {
  /// Server first (source of truth); on failure/offline fall back to the
  /// on-device store. Throws if neither has it (caller offers "generate").
  Future<AnalysisResult> get(String youtubeId);

  /// Create a placeholder analysis on-device and persist it locally.
  /// ponytail: fake sample until the real analyzer lands; a future sync can
  /// push locally-generated songs to the server once both are connected.
  Future<AnalysisResult> generate(String youtubeId, {String? title});
}

class DefaultSongRepository implements SongRepository {
  final ChordMindApi _api;
  final LocalStore _local;
  DefaultSongRepository(this._api, this._local);

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
    final json = generateSampleJson(youtubeId, title: title);
    await _local.save(youtubeId, json);
    return AnalysisResult.fromJson(json);
  }
}

final songRepositoryProvider = Provider<SongRepository>(
    (ref) => DefaultSongRepository(ref.read(apiProvider), ref.read(localStoreProvider)));
