// app/lib/features/player/player_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/core/song_repository.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/core/breakpoints.dart';
import 'package:chordmind/core/widgets/app_scaffold.dart';
import 'package:chordmind/core/widgets/app_card.dart';
import 'package:chordmind/core/widgets/info_chip.dart';
import 'package:chordmind/core/widgets/pill_tabs.dart';
import 'package:chordmind/core/widgets/empty_state.dart';
import 'package:chordmind/features/chord_grid/chord_grid.dart';
import 'package:chordmind/features/chord_grid/current_chord_bar.dart';
import 'package:chordmind/features/diagrams/chord_diagram_sheet.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String youtubeId;
  const PlayerScreen(this.youtubeId, {super.key});
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  YoutubePlayerController? _yt;
  StreamSubscription? _sub;
  AnalysisResult? _r;
  bool _analysisFailed = false;
  double _pos = 0;
  int _tab = 0;
  String? _selectedChord;

  static const _tabs = ['Chords', 'Lyrics', 'Re-harm', 'Band', 'Versions'];

  @override
  void initState() {
    super.initState();
    try {
      _yt = YoutubePlayerController.fromVideoId(
          videoId: widget.youtubeId,
          params: const YoutubePlayerParams(showControls: true));
      _sub = _yt!.videoStateStream.listen((s) {
        if (mounted) setState(() => _pos = s.position.inMilliseconds / 1000.0);
      });
    } catch (_) {
      // YoutubePlayerController may throw in test/headless environments;
      // the rest of the screen still renders without the player.
    }
    _loadAnalysis();
  }

  /// Best-effort: the video plays regardless. We only ask the storage server for
  /// an analysis already stored under this id (server does storage only, id only).
  /// Missing/offline → degrade gracefully. On-device analysis will fill this in (A1).
  Future<void> _loadAnalysis() async {
    try {
      final r = await ref.read(songRepositoryProvider).get(widget.youtubeId);
      if (mounted) setState(() => _r = r);
    } catch (_) {
      if (mounted) setState(() => _analysisFailed = true);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _yt?.close();
    super.dispose();
  }

  void _onTapChord(String c) {
    final wide = formFactorFor(MediaQuery.sizeOf(context).width) != FormFactor.compact;
    if (wide) {
      setState(() => _selectedChord = c);
    } else {
      showChordDiagram(context, c);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final wide = formFactorFor(MediaQuery.sizeOf(context).width) != FormFactor.compact;
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Video always plays — it does not depend on our backend.
      Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: AppCard(
                padding: EdgeInsets.zero,
                child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _yt != null
                        ? YoutubePlayer(controller: _yt!)
                        : Container(
                            color: Colors.black,
                            child: const Center(
                                child: Icon(Icons.play_circle_outline,
                                    color: Colors.white54, size: 64))))),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
        child: Row(children: [
          Expanded(
              child: Text(r?.source.title ?? 'Video YouTube',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge)),
          if (r != null) ...[
            const SizedBox(width: AppSpace.s8),
            InfoChip(label: r.key, icon: Icons.music_note),
            const SizedBox(width: 6),
            InfoChip(label: '${r.source.bpm.round()} BPM', icon: Icons.speed),
          ],
        ]),
      ),
      Expanded(child: _analysisArea(r)),
    ]);

    if (wide) {
      return AppScaffold(
        title: 'ChordMind',
        navIndex: 0,
        rightPanel: ChordDiagramView(chord: _selectedChord),
        body: body,
      );
    }
    return AppScaffold(title: r?.source.title ?? 'ChordMind', body: body);
  }

  Widget _analysisArea(AnalysisResult? r) {
    if (r != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.all(AppSpace.s16),
          child: CurrentChordBar(result: r, positionSeconds: _pos),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
          child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: PillTabs(tabs: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i))),
        ),
        const SizedBox(height: AppSpace.s8),
        Expanded(child: _tabBody(r)),
      ]);
    }
    if (_analysisFailed) {
      return const EmptyState(icon: Icons.graphic_eq_rounded, title: 'Chưa có hợp âm');
    }
    return const Center(child: CircularProgressIndicator());
  }

  Widget _tabBody(AnalysisResult r) {
    switch (_tab) {
      case 0:
        return ChordGrid(result: r, positionSeconds: _pos, onTapChord: _onTapChord);
      case 1:
        return const EmptyState(icon: Icons.lyrics_outlined, title: 'Lời bài hát', subtitle: 'Sắp ra mắt');
      case 2:
        return const EmptyState(icon: Icons.auto_awesome_outlined, title: 'Biến tấu hợp âm', subtitle: 'Sắp ra mắt');
      case 3:
        return const EmptyState(icon: Icons.groups_outlined, title: 'Chơi cùng ban nhạc', subtitle: 'Sắp ra mắt');
      default:
        return const EmptyState(icon: Icons.history_outlined, title: 'Phiên bản', subtitle: 'Sắp ra mắt');
    }
  }
}
