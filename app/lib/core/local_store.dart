// app/lib/core/local_store.dart
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'search/song_search.dart';

/// On-device store of analyses, keyed by youtubeId. Kept as raw JSON so we never
/// need per-model toJson, and so a future server sync can push the stored map
/// straight up.
/// ponytail: SharedPreferences is plenty for a handful of songs; move to sqflite
/// only if the library grows large.
class LocalStore {
  // Bumped to v1 to invalidate any pre-B1.5 cached demo/sample analyses so the
  // real on-device model runs instead of returning stale placeholder data.
  static const _prefix = 'song:v1:';

  Future<AnalysisResult?> get(String youtubeId) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('$_prefix$youtubeId');
    if (raw == null) return null;
    return AnalysisResult.fromJson(jsonDecode(raw) as Map);
  }

  Future<void> save(String youtubeId, Map<String, dynamic> json) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('$_prefix$youtubeId', jsonEncode(json));
  }

  /// Every stored analysis as a lightweight [StoredSong], for search/recents.
  /// Corrupt entries are skipped rather than throwing.
  Future<List<StoredSong>> all() async {
    final p = await SharedPreferences.getInstance();
    final out = <StoredSong>[];
    for (final key in p.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final raw = p.getString(key);
      if (raw == null) continue;
      try {
        final src = (jsonDecode(raw) as Map)['source'] as Map;
        out.add(StoredSong(
          src['youtubeId'] as String,
          src['title'] as String,
          src['audioPath'] as String?,
        ));
      } catch (_) {
        // Skip unreadable/legacy entries.
      }
    }
    return out;
  }
}

final localStoreProvider = Provider((_) => LocalStore());
