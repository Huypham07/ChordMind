// app/lib/features/settings/settings_screen.dart
//
// Task S2: Settings screen. Home for all model-related settings; today
// that's just the chord-model picker. On-device-usable models (input ==
// "pcm": chordnet_2e1d, btc) are selectable and persist via
// SettingsStore.setChordModel. chord_cnn_lstm (input == "cqtv2_feature")
// is shown but disabled ("Sắp có") -- it's deferred until an on-device CQT
// feature extractor exists (see model_registry.dart).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chordmind/core/model_registry.dart';
import 'package:chordmind/core/nav_helper.dart';
import 'package:chordmind/core/settings_store.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/core/widgets/app_scaffold.dart';

class _ModelInfo {
  final String title;
  final String subtitle;
  const _ModelInfo(this.title, this.subtitle);
}

const _modelInfo = <String, _ModelInfo>{
  'chordnet_2e1d': _ModelInfo('ChordNet 2E1D', 'Nhẹ, nhanh — mặc định'),
  'btc': _ModelInfo('BTC', 'Bi-directional Transformer'),
  'chord_cnn_lstm': _ModelInfo('Chord-CNN-LSTM', 'Chưa hỗ trợ trên máy'),
};

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registryAsync = ref.watch(modelRegistryProvider);
    final selected = ref.watch(selectedChordModelProvider);

    return AppScaffold(
      title: 'Settings',
      navIndex: 2,
      onNav: (i) => onNavTap(context, i),
      body: registryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Không tải được danh sách model: $e')),
        data: (registry) => _Body(registry: registry, selected: selected),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final ModelRegistry registry;
  final String selected;
  const _Body({required this.registry, required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final specs = registry.available.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final cm = Theme.of(context).extension<ChordMindColors>()!;

    return ListView(
      padding: const EdgeInsets.all(AppSpace.s24),
      children: [
        Text('Chord model', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpace.s8),
        Text(
          'Chọn model nhận diện hợp âm chạy trên máy.',
          style: TextStyle(color: cm.textMuted),
        ),
        const SizedBox(height: AppSpace.s16),
        for (final spec in specs) _ModelTile(spec: spec, selected: selected),
      ],
    );
  }
}

class _ModelTile extends ConsumerWidget {
  final ModelSpec spec;
  final String selected;
  const _ModelTile({required this.spec, required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usable = spec.input == 'pcm';
    final info = _modelInfo[spec.name] ?? _ModelInfo(spec.name, spec.input);
    final cm = Theme.of(context).extension<ChordMindColors>()!;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.s12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Material(
        color: cm.surfaceAlt,
        child: RadioListTile<String>(
        key: Key('model-tile-${spec.name}'),
        value: spec.name,
        groupValue: usable ? selected : null,
        onChanged: usable
            ? (name) {
                if (name != null) {
                  ref.read(settingsStoreProvider.notifier).setChordModel(name);
                }
              }
            : null,
        title: Text(info.title),
        subtitle: Text(info.subtitle),
        secondary: usable
            ? null
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.s8, vertical: 4),
                decoration: BoxDecoration(
                  color: cm.border,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: const Text('Sắp có', style: TextStyle(fontSize: 12)),
              ),
        ),
      ),
    );
  }
}
