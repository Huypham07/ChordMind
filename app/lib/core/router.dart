// app/lib/core/router.dart
import 'package:go_router/go_router.dart';
import 'package:chordmind/features/home/home_screen.dart';
import 'package:chordmind/features/player/player_screen.dart';

final router = GoRouter(routes: [
  GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
  GoRoute(path: '/player/:id', builder: (_, s) => PlayerScreen(s.pathParameters['id']!)),
]);
