import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copies picked audio into persistent app storage so uploaded songs survive
/// the file-picker cache being cleared, enabling re-open and re-generate.
/// ponytail: no eviction yet — add cleanup when a delete-song UI exists.
class AudioStore {
  /// Copies [srcPath] to <appSupport>/songs/<safeId>.<ext> and returns the
  /// stored path. The song id is sanitized to a safe filename; the source
  /// extension is preserved. Overwrites an existing copy for the same id.
  Future<String> persist(String songId, String srcPath) async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'songs'));
    await dir.create(recursive: true);
    final ext = p.extension(srcPath); // includes the dot, may be empty
    final safeId = songId.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final dest = p.join(dir.path, '$safeId$ext');
    await File(srcPath).copy(dest);
    return dest;
  }
}

final audioStoreProvider = Provider((_) => AudioStore());
