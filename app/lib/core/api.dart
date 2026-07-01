// app/lib/core/api.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models.dart';

class ChordMindApi {
  final Dio _dio;
  final String baseUrl;
  ChordMindApi(this._dio, {this.baseUrl = 'http://localhost:8000'});

  Future<AnalysisResult> submit(String url) async {
    final r = await _dio.post('$baseUrl/songs', data: {'url': url});
    return AnalysisResult.fromJson(r.data as Map);
  }

  Future<AnalysisResult> get(String youtubeId) async {
    final r = await _dio.get('$baseUrl/songs/$youtubeId');
    return AnalysisResult.fromJson(r.data as Map);
  }

  Future<List<({String youtubeId, String title})>> recent() async {
    final r = await _dio.get('$baseUrl/songs');
    return [for (final s in r.data as List) (youtubeId: s['youtubeId'] as String, title: s['title'] as String)];
  }
}

// Short timeouts so an offline/unreachable server fails fast and we fall back
// to the on-device store instead of hanging.
final apiProvider = Provider((_) => ChordMindApi(Dio(BaseOptions(
      connectTimeout: const Duration(milliseconds: 1500),
      receiveTimeout: const Duration(milliseconds: 1500),
    ))));
