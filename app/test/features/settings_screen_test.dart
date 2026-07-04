// app/test/features/settings_screen_test.dart
//
// Task S2: Settings screen chord-model picker. Loads the real bundled
// manifest (app/assets/models/manifest.json, committed to git) via
// ModelRegistry.load() -- no .onnx bytes are needed for this screen (only
// spec metadata), so no override/mock of modelRegistryProvider is required
// and `bash tool/sync_models.sh` is not needed for this test.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chordmind/core/model_registry.dart';
import 'package:chordmind/core/settings_store.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/features/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester t, ProviderContainer container) async {
    // Pre-resolve the registry so the first build already sees
    // AsyncValue.data -- avoids ever rendering the loading spinner, whose
    // indefinite animation would make pumpAndSettle time out.
    await container.read(modelRegistryProvider.future);
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: chordMindLight, home: const SettingsScreen()),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('renders PCM models selectable, chord_cnn_lstm disabled with "Sắp có", default selected',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsStoreProvider.notifier).ready;

    await pump(t, container);

    expect(find.text('ChordNet 2E1D'), findsOneWidget);
    expect(find.text('BTC'), findsOneWidget);
    expect(find.text('Chord-CNN-LSTM'), findsOneWidget);
    expect(find.text('Sắp có'), findsOneWidget);

    final chordnetTile = t.widget<RadioListTile<String>>(
        find.byKey(const Key('model-tile-chordnet_2e1d')));
    expect(chordnetTile.groupValue, 'chordnet_2e1d');
    expect(chordnetTile.value, chordnetTile.groupValue);

    final btcTile =
        t.widget<RadioListTile<String>>(find.byKey(const Key('model-tile-btc')));
    expect(btcTile.onChanged, isNotNull);

    final cclTile = t.widget<RadioListTile<String>>(
        find.byKey(const Key('model-tile-chord_cnn_lstm')));
    expect(cclTile.onChanged, isNull);
  });

  testWidgets('tapping the BTC tile updates the selected chord model', (t) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(settingsStoreProvider.notifier).ready;

    await pump(t, container);

    await t.tap(find.byKey(const Key('model-tile-btc')));
    await t.pumpAndSettle();

    expect(container.read(selectedChordModelProvider), 'btc');
  });
}
