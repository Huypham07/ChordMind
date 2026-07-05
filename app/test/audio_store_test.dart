import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:chordmind/core/audio_store.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('audiostore');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('persist copies the file into <support>/songs and returns its path', () async {
    final src = File(p.join(tmp.path, 'orig.mp3'))..writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4]));
    final stored = await AudioStore().persist('file:My Song.mp3', src.path);

    expect(stored, startsWith(p.join(tmp.path, 'songs')));
    expect(stored, endsWith('.mp3'));
    expect(File(stored).existsSync(), isTrue);
    expect(File(stored).readAsBytesSync(), [1, 2, 3, 4]);

    // Re-persist with different bytes overwrites the same target.
    final src2 = File(p.join(tmp.path, 'orig2.mp3'))..writeAsBytesSync(Uint8List.fromList([9]));
    final stored2 = await AudioStore().persist('file:My Song.mp3', src2.path);
    expect(stored2, stored);
    expect(File(stored2).readAsBytesSync(), [9]);
  });
}
