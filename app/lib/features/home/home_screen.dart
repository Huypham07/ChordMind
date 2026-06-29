// app/lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:chordmind/core/song_repository.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  Future<void> _analyze() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(songRepositoryProvider).submit(_ctrl.text);
      if (mounted) context.go('/player/${r.source.youtubeId}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ChordMind')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            TextField(
              controller: _ctrl,
              decoration: const InputDecoration(
                  labelText: 'YouTube link', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _busy ? null : _analyze, child: const Text('Analyze')),
          ]),
        ),
      );
}
