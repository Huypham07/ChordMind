/// Client-side YouTube id extraction — the app parses the id itself; the
/// storage server only ever receives an id, never a URL.
String? parseYoutubeId(String input) {
  final s = input.trim();
  final patterns = [
    RegExp(r'[?&]v=([\w-]{11})'),
    RegExp(r'youtu\.be/([\w-]{11})'),
    RegExp(r'/(?:embed|shorts|live)/([\w-]{11})'),
    RegExp(r'^([\w-]{11})$'),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(s);
    if (m != null) return m.group(1);
  }
  return null;
}
