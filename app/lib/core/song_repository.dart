// app/lib/core/song_repository.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api.dart';
import 'models.dart';

/// Clean-arch boundary: features depend on this, not on ChordMindApi/Dio.
abstract class SongRepository {
  Future<AnalysisResult> submit(String url);
  Future<AnalysisResult> get(String youtubeId);
  Future<List<({String youtubeId, String title})>> recent();
}

class ApiSongRepository implements SongRepository {
  final ChordMindApi _api;
  ApiSongRepository(this._api);
  @override
  Future<AnalysisResult> submit(String url) => _api.submit(url);
  @override
  Future<AnalysisResult> get(String youtubeId) => _api.get(youtubeId);
  @override
  Future<List<({String youtubeId, String title})>> recent() => _api.recent();
}

final songRepositoryProvider =
    Provider<SongRepository>((ref) => ApiSongRepository(ref.read(apiProvider)));
