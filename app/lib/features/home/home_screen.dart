// app/lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:chordmind/core/youtube.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/core/breakpoints.dart';
import 'package:chordmind/core/widgets/app_scaffold.dart';
import 'package:chordmind/core/widgets/search_pill.dart';
import 'package:chordmind/core/widgets/gradient_button.dart';
import 'package:chordmind/core/widgets/app_card.dart';
import 'package:chordmind/core/widgets/info_chip.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // The app extracts the id itself and opens the player (video plays with no
  // backend); chord analysis is fetched/computed on the player screen.
  void _analyze() {
    final id = parseYoutubeId(_ctrl.text);
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link YouTube không hợp lệ')),
      );
      return;
    }
    context.go('/player/$id');
  }

  @override
  Widget build(BuildContext context) {
    final wide = formFactorFor(MediaQuery.sizeOf(context).width) != FormFactor.compact;
    return AppScaffold(
      title: 'ChordMind',
      navIndex: 0,
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.s24),
        children: [
          _Hero(),
          const SizedBox(height: AppSpace.s24),
          Row(children: [
            Expanded(child: SearchPill(controller: _ctrl, onSubmit: _analyze)),
            const SizedBox(width: AppSpace.s12),
            GradientButton(label: 'Analyze', onPressed: _analyze),
          ]),
          const SizedBox(height: AppSpace.s32),
          Text('Gần đây', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpace.s12),
          // recent list/grid (placeholder cards until a real recents source is wired)
          if (wide)
            Wrap(spacing: AppSpace.s16, runSpacing: AppSpace.s16, children: [
              for (var i = 0; i < 4; i++) SizedBox(width: 260, child: _RecentCard(index: i)),
            ])
          else
            Column(children: [for (var i = 0; i < 3; i++) Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.s12), child: _RecentCard(index: i))]),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.s32),
      decoration: BoxDecoration(
        gradient: AppGradients.brand,
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hợp âm cho mọi bài hát',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white)),
        const SizedBox(height: AppSpace.s8),
        const Text('Dán link YouTube để xem hợp âm, thế bấm và chơi cùng.',
            style: TextStyle(color: Colors.white70)),
      ]),
    );
  }
}

class _RecentCard extends StatelessWidget {
  final int index;
  const _RecentCard({required this.index});
  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    return AppCard(
      onTap: () {},
      child: Row(children: [
        Container(width: 48, height: 48,
          decoration: BoxDecoration(gradient: AppGradients.brand, borderRadius: BorderRadius.circular(AppRadii.md)),
          child: const Icon(Icons.music_note, color: Colors.white)),
        const SizedBox(width: AppSpace.s12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Bài mẫu #${index + 1}', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const InfoChip(label: 'C major'),
        ])),
        Icon(Icons.chevron_right, color: cm.textMuted),
      ]),
    );
  }
}
