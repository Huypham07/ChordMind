// app/lib/core/router.dart
import 'package:go_router/go_router.dart';
import 'package:chordmind/features/home/home_screen.dart';
import 'package:chordmind/features/player/player_screen.dart';
import 'package:chordmind/features/preview/preview_screen.dart';
import 'package:chordmind/features/splash/splash_screen.dart';

final router = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
    GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
    GoRoute(path: '/player/:id', builder: (_, s) => PlayerScreen(s.pathParameters['id']!)),
    GoRoute(path: '/preview', builder: (_, _) => const PreviewScreen()),
  ],
);
