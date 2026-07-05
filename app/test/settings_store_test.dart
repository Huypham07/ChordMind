// app/test/settings_store_test.dart
//
// Task S1: SettingsStore persists the user's selected on-device chord
// model (SharedPreferences, key "settings:chordModel"), defaulting to
// chordnet_2e1d, and falls back to the default if the persisted value no
// longer resolves to an on-device-usable model (unknown, or
// input != "pcm", e.g. a stale chord_cnn_lstm selection).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chordmind/core/model_registry.dart';
import 'package:chordmind/core/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsStore', () {
    test('defaults to btc when nothing persisted', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(settingsStoreProvider.notifier).ready;

      expect(container.read(selectedChordModelProvider), defaultModelName);
      expect(defaultModelName, 'btc');
    });

    test('setChordModel persists and round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(settingsStoreProvider.notifier).ready;

      await container.read(settingsStoreProvider.notifier).setChordModel('btc');

      expect(container.read(selectedChordModelProvider), 'btc');

      // Round-trips: a fresh store reads the persisted value back.
      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      await container2.read(settingsStoreProvider.notifier).ready;
      expect(container2.read(selectedChordModelProvider), 'btc');
    });

    test('falls back to default when the persisted value is not usable on-device', () async {
      // chord_cnn_lstm exists in the registry but is input=cqtv2_feature,
      // not on-device-usable (see model_registry.dart); a stale selection
      // (e.g. from before ccl was disabled) must not stick.
      SharedPreferences.setMockInitialValues({'settings:chordModel': 'chord_cnn_lstm'});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(settingsStoreProvider.notifier).ready;

      expect(container.read(selectedChordModelProvider), defaultModelName);
    });

    test('falls back to default when the persisted value is unknown', () async {
      SharedPreferences.setMockInitialValues({'settings:chordModel': 'not_a_real_model'});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(settingsStoreProvider.notifier).ready;

      expect(container.read(selectedChordModelProvider), defaultModelName);
    });
  });
}
