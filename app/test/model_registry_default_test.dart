// app/test/model_registry_default_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/model_registry.dart';

void main() {
  test('default model is BTC', () {
    expect(defaultModelName, 'btc');
  });
}
