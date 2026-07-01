import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/youtube.dart';

void main() {
  test('parses id from common YouTube URL forms (client-side)', () {
    expect(parseYoutubeId('https://www.youtube.com/watch?v=abcdefghijk'), 'abcdefghijk');
    expect(parseYoutubeId('https://youtu.be/abcdefghijk'), 'abcdefghijk');
    expect(parseYoutubeId('https://www.youtube.com/shorts/abcdefghijk'), 'abcdefghijk');
    expect(parseYoutubeId('  abcdefghijk  '), 'abcdefghijk');
    expect(parseYoutubeId('not a youtube link'), isNull);
  });
}
