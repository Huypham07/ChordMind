// app/test/api_test.dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/api.dart';

class _FakeAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(opts, stream, future) async => ResponseBody.fromString(
      '{"songId":"abc","source":{"youtubeId":"abc","title":"T","duration":100.0,"bpm":120.0,"timeSignature":4},"key":"C major","beats":[],"downbeats":[],"chords":[],"synchronizedChords":[],"segments":[]}',
      200,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  @override
  void close({bool force = false}) {}
}

void main() {
  test('submit parses AnalysisResult', () async {
    final dio = Dio()..httpClientAdapter = _FakeAdapter();
    final api = ChordMindApi(dio, baseUrl: 'http://x');
    final r = await api.submit('https://youtu.be/abc');
    expect(r.songId, 'abc');
    expect(r.key, 'C major');
  });
}
