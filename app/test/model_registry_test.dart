// app/test/model_registry_test.dart
//
// Plan B Task B1.1: model registry loads the bundled device manifest
// (app/assets/models/manifest.json) and exposes a ModelSpec per entry.
//
// The sha256-verify test needs the real chord_cnn_lstm.onnx bytes bundled
// as an asset (1.9MB, cheap) — run `bash tool/sync_models.sh` before
// `flutter test test/model_registry_test.dart` to populate
// app/assets/models/*.onnx locally (gitignored, not committed).
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/model_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads all 3 manifest entries', () async {
    final registry = await ModelRegistry.load();
    expect(registry.available.map((m) => m.name).toSet(),
        {'chordnet_2e1d', 'btc', 'chord_cnn_lstm'});
  });

  test('chordnet_2e1d: pcm/vote with 170 labels + windowSamples', () async {
    final registry = await ModelRegistry.load();
    final m = registry.byName('chordnet_2e1d');
    expect(m.input, 'pcm');
    expect(m.decode, 'vote');
    expect(m.fs, 22050);
    expect(m.windowSamples, 219136);
    expect(m.labels, isNotNull);
    expect(m.labels!.length, 170);
    expect(m.heads, isNull);
    expect(m.feature, isNull);
    expect(m.sha256, 'ccfadd452262059c8a050f0cfdb3a6916a0dd0f47d0582bc696b38c5c48dbb85');
  });

  test('btc: pcm/vote with 170 labels + windowSamples', () async {
    final registry = await ModelRegistry.load();
    final m = registry.byName('btc');
    expect(m.input, 'pcm');
    expect(m.decode, 'vote');
    expect(m.windowSamples, 219136);
    expect(m.labels, isNotNull);
    expect(m.labels!.length, 170);
  });

  test('chord_cnn_lstm: cqtv2_feature/xhmm with 6 heads + feature map',
      () async {
    final registry = await ModelRegistry.load();
    final m = registry.byName('chord_cnn_lstm');
    expect(m.input, 'cqtv2_feature');
    expect(m.decode, 'xhmm');
    expect(m.windowSamples, isNull);
    expect(m.labels, isNull);
    expect(m.heads, isNotNull);
    expect(m.heads!.length, 6);
    expect(m.heads!.map((h) => h.name).toList(),
        ['triad', 'bass', 'seventh', 'ninth', 'eleventh', 'thirteenth']);
    expect(m.heads!.first.dim, 73);
    expect(m.feature, isNotNull);
    expect(m.feature!['type'], 'hybrid_cqt');
    expect(m.feature!['n_bins'], 288);
  });

  test('default model is btc', () async {
    final registry = await ModelRegistry.load();
    expect(registry.byName(null).name, 'btc');
    expect(registry.defaultModel.name, 'btc');
  });

  test('byName throws for unknown model', () async {
    final registry = await ModelRegistry.load();
    expect(() => registry.byName('nope'), throwsArgumentError);
  });

  test(
      'sha256 of bundled chord_cnn_lstm.onnx matches manifest '
      '(run `bash tool/sync_models.sh` first)', () async {
    final registry = await ModelRegistry.load();
    final m = registry.byName('chord_cnn_lstm');
    final ok = await registry.verifySha256(m);
    expect(ok, isTrue,
        reason: 'run `bash tool/sync_models.sh` to populate '
            'app/assets/models/*.onnx before this test');
  }, skip: false);
}
