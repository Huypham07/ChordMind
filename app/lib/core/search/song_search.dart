// app/lib/core/search/song_search.dart
//
// Search value types + interface. See docs/superpowers/specs/2026-07-06-song-search-design.md.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../local_store.dart';

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

typedef YoutubeSearcher = Future<List<YtResult>> Function(String query);

abstract interface class SongSearch {
  /// Analyzed songs whose title contains [query] (case-insensitive).
  Future<List<StoredSong>> searchLocal(String query);

  /// YouTube search results for [query].
  Future<List<YtResult>> searchYoutube(String query);
}

class DefaultSongSearch implements SongSearch {
  DefaultSongSearch(this._local, {YoutubeSearcher? youtubeSearcher})
      : _youtubeSearcher = youtubeSearcher ?? _realYoutubeSearch;

  final LocalStore _local;
  final YoutubeSearcher _youtubeSearcher;

  @override
  Future<List<StoredSong>> searchLocal(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final all = await _local.all();
    return [for (final s in all) if (s.title.toLowerCase().contains(q)) s];
  }

  @override
  Future<List<YtResult>> searchYoutube(String query) async {
    if (query.trim().isEmpty) return const [];
    return _youtubeSearcher(query);
  }
}

/// Real YouTube search via youtube_explode_dart. Closes the client after use.
Future<List<YtResult>> _realYoutubeSearch(String query) async {
  final yt = YoutubeExplode();
  try {
    final results = await yt.search.search(query);
    return [
      for (final v in results)
        YtResult(v.id.value, v.title, v.author, v.duration),
    ];
  } finally {
    yt.close();
  }
}

final songSearchProvider = Provider<SongSearch>(
    (ref) => DefaultSongSearch(ref.read(localStoreProvider)));
