// app/lib/core/search/song_search.dart
//
// Search value types + interface. See docs/superpowers/specs/2026-07-06-song-search-design.md.

/// A song already in the local store (analyzed). [audioPath] is set for
/// uploaded-file songs, null for YouTube songs.
class StoredSong {
  final String youtubeId;
  final String title;
  final String? audioPath;
  const StoredSong(this.youtubeId, this.title, this.audioPath);
}

/// A YouTube search hit (not yet analyzed).
class YtResult {
  final String videoId;
  final String title;
  final String author;
  final Duration? duration;
  const YtResult(this.videoId, this.title, this.author, this.duration);
}
