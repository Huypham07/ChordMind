import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copies picked audio into persistent app storage so uploaded songs survive
/// the file-picker cache being cleared, enabling re-open and re-generate.
/// ponytail: no eviction yet — add cleanup when a delete-song UI exists.
class AudioStore {
  /// Copies [srcPath] to `<appSupport>/songs/<safeId>.<ext>` and returns the
  /// stored path. The song id is sanitized to a safe filename with an id-hash
  /// suffix so distinct ids never collide (e.g. `a-b` vs `a b`, which sanitize
  /// to the same base); the source extension is preserved. Overwrites an
  /// existing copy for the SAME id.
  Future<String> persist(String songId, String srcPath) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'songs'));
    await dir.create(recursive: true);
    final ext = p.extension(srcPath); // includes the dot, may be empty
    final base = songId.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    // Short hash of the raw id disambiguates ids that sanitize to the same
    // base, so two different uploads never overwrite each other's audio.
    final hash = sha1.convert(utf8.encode(songId)).toString().substring(0, 8);
    final dest = p.join(dir.path, '${base}_$hash$ext');
    await File(srcPath).copy(dest);
    return dest;
  }
}

final audioStoreProvider = Provider((_) => AudioStore());
