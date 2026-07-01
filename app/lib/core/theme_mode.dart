import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App theme mode. Defaults to following the device (system) light/dark.
final themeModeProvider = StateProvider<ThemeMode>((_) => ThemeMode.system);
