// app/lib/core/model_registry.dart
//
// Plan B Task B1.1: loads the device manifest (artifacts/onnx/manifest.json,
// copied verbatim to assets/models/manifest.json) and exposes each chord
// model's spec. Do not hardcode model params that live in the manifest —
// see docs/superpowers/plans/2026-07-04-flutter-ondevice-inference.md.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _manifestAsset = 'assets/models/manifest.json';
const _modelsAssetDir = 'assets/models';
const defaultModelName = 'chordnet_2e1d';

/// One classification head of the chord_cnn_lstm multi-head model
/// (triad/bass/seventh/ninth/eleventh/thirteenth), each with its own
/// output dimension. See manifest `heads` + `heads_semantics`.
class ModelHead {
  final String name;
  final int dim;
  ModelHead.fromJson(Map j) : name = j['name'] as String, dim = j['dim'] as int;
}

/// A parsed `manifest.json` entry for one on-device chord model.
class ModelSpec {
  final String name;
  final String file;

  /// "pcm" (chordnet/btc feed raw waveform windows, CQT baked into the
  /// net) or "cqtv2_feature" (chord_cnn_lstm feeds a precomputed
  /// hybrid_cqt feature; see Global Constraints).
  final String input;
  final int fs;

  /// Sliding-window length in samples. Only set for "pcm" models.
  final int? windowSamples;

  /// "vote" (chordnet/btc: sliding-window majority vote) or "xhmm"
  /// (chord_cnn_lstm: Viterbi decode over the 6 head outputs).
  final String decode;

  /// Flat 170-class chord label list, for "vote"-decoded flat models.
  final List<String>? labels;

  /// Per-head output dims, for the chord_cnn_lstm multi-head model.
  final List<ModelHead>? heads;

  /// Feature-extraction params (hybrid_cqt: sr/hop_length/n_bins/...),
  /// for "cqtv2_feature" models.
  final Map<String, dynamic>? feature;

  final String sha256;

  ModelSpec._({
    required this.name,
    required this.file,
    required this.input,
    required this.fs,
    required this.windowSamples,
    required this.decode,
    required this.labels,
    required this.heads,
    required this.feature,
    required this.sha256,
  });

  factory ModelSpec.fromJson(Map j) {
    return ModelSpec._(
      name: j['name'] as String,
      file: j['file'] as String,
      // chordnet/btc entries omit "input" entirely (pcm is implicit).
      input: (j['input'] as String?) ?? 'pcm',
      // ccl uses "sample_rate" instead of "fs".
      fs: (j['fs'] ?? j['sample_rate']) as int,
      windowSamples: j['window_samples'] as int?,
      decode: j['decode'] as String,
      labels: j['labels'] == null
          ? null
          : List<String>.from(j['labels'] as List),
      heads: j['heads'] == null
          ? null
          : [for (final h in j['heads'] as List) ModelHead.fromJson(h as Map)],
      feature: j['feature'] == null
          ? null
          : Map<String, dynamic>.from(j['feature'] as Map),
      sha256: j['sha256'] as String,
    );
  }

  /// Asset key for the bundled .onnx (gitignored, synced locally via
  /// tool/sync_models.sh; not committed to git).
  String get assetKey => '$_modelsAssetDir/$file';
}

/// Loads the bundled device manifest and exposes each model's [ModelSpec].
class ModelRegistry {
  final Map<String, ModelSpec> _byName;

  ModelRegistry._(this._byName);

  static Future<ModelRegistry> load() async {
    final raw = await rootBundle.loadString(_manifestAsset);
    final decoded = jsonDecode(raw) as Map;
    final byName = <String, ModelSpec>{
      for (final entry in decoded.entries)
        entry.key as String: ModelSpec.fromJson(entry.value as Map),
    };
    return ModelRegistry._(byName);
  }

  List<ModelSpec> get available => _byName.values.toList(growable: false);

  ModelSpec get defaultModel => byName(defaultModelName);

  /// Looks up a model by name; `null` resolves to [defaultModelName].
  ModelSpec byName(String? name) {
    final key = name ?? defaultModelName;
    final spec = _byName[key];
    if (spec == null) {
      throw ArgumentError('unknown model: $key (available: ${_byName.keys})');
    }
    return spec;
  }

  /// Verifies the bundled .onnx asset's sha256 against the manifest.
  /// Guards against a stale/corrupt bundled model. On-demand (not run at
  /// construction) since it reads the full model bytes.
  Future<bool> verifySha256(ModelSpec spec) async {
    final bytes = await rootBundle.load(spec.assetKey);
    final digest = sha256.convert(Uint8List.sublistView(bytes.buffer.asUint8List(
        bytes.offsetInBytes, bytes.lengthInBytes)));
    return digest.toString() == spec.sha256;
  }
}

/// Loads [ModelRegistry] once per app (or provider container). Screens that
/// list/select models (e.g. Settings) watch this instead of calling
/// [ModelRegistry.load] directly; tests can override it with an in-memory
/// registry to avoid asset loading.
final modelRegistryProvider = FutureProvider<ModelRegistry>((_) => ModelRegistry.load());
