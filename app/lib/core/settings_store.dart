// app/lib/core/settings_store.dart
//
// Task S1: persists the user's selected on-device chord model (name from
// ModelRegistry) so OnDeviceAnalyzer.analyze uses it instead of always
// running the registry default. See
// docs/superpowers/plans/2026-07-04-flutter-ondevice-inference.md.
//
// Only chordnet_2e1d and btc (ModelSpec.input == 'pcm') are usable
// on-device today; chord_cnn_lstm (input == 'cqtv2_feature') is deferred
// (see model_registry.dart). A persisted value that no longer resolves to
// a usable on-device model (unknown name, or a non-pcm model like
// chord_cnn_lstm) falls back to the default at load time.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'model_registry.dart';

const _chordModelKey = 'settings:chordModel';

/// Holds the currently-selected chord model name, backed by
/// SharedPreferences. State starts as [defaultModelName] and is updated
/// once the persisted value (if any) has been loaded and validated.
class SettingsStore extends StateNotifier<String> {
  SettingsStore() : super(defaultModelName) {
    ready = _load();
  }

  /// Resolves once the persisted selection (if any) has been loaded and
  /// validated against the registry. Tests can await this for determinism.
  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_chordModelKey);
    if (raw == null) return;
    if (await _isOnDeviceUsable(raw)) {
      state = raw;
    }
  }

  Future<bool> _isOnDeviceUsable(String name) async {
    try {
      final registry = await ModelRegistry.load();
      return registry.byName(name).input == 'pcm';
    } catch (_) {
      return false;
    }
  }

  /// Persists [name] as the selected chord model and updates state
  /// immediately (no validation: this is the user actively choosing a
  /// model the UI already knows is on-device-usable).
  Future<void> setChordModel(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chordModelKey, name);
    state = name;
  }
}

final settingsStoreProvider = StateNotifierProvider<SettingsStore, String>(
  (_) => SettingsStore(),
);

/// The currently-selected chord model name (defaults to
/// [defaultModelName] until the persisted value has loaded/validated).
final selectedChordModelProvider = Provider<String>(
  (ref) => ref.watch(settingsStoreProvider),
);
