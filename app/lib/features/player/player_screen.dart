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
    ref.read(songRepositoryProvider).get(widget.youtubeId).then((r) {
      if (mounted) setState(() => _r = r);
    });
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
    final body = r == null
        ? const Center(child: CircularProgressIndicator())
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.all(AppSpace.s16),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
              child: Row(children: [
                Expanded(
                    child: Text(r.source.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge)),
                const SizedBox(width: AppSpace.s8),
                InfoChip(label: r.key, icon: Icons.music_note),
                const SizedBox(width: 6),
                InfoChip(label: '${r.source.bpm.round()} BPM', icon: Icons.speed),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpace.s16),
              child: CurrentChordBar(result: r, positionSeconds: _pos),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
              child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: PillTabs(
                      tabs: _tabs,
                      index: _tab,
                      onChanged: (i) => setState(() => _tab = i))),
            ),
            Expanded(child: _tabBody(r)),
          ]);

    if (wide) {
      return AppScaffold(
        title: 'ChordMind',
        navIndex: 0,
        rightPanel: ChordDiagramView(chord: _selectedChord),
        body: body,
      );
    }
    return AppScaffold(title: r?.source.title ?? 'Đang tải…', body: body);
  }

  Widget _tabBody(AnalysisResult r) {
    switch (_tab) {
      case 0:
        return ChordGrid(result: r, positionSeconds: _pos, onTapChord: _onTapChord);
      case 1:
        return const Center(child: Text('Lyrics — sắp có'));
      case 2:
        return const Center(child: Text('Biến tấu hợp âm on-device — sắp có'));
      case 3:
        return const Center(child: Text('Đồng bộ ban nhạc — sắp có'));
      default:
        return const Center(child: Text('Versions — sắp có'));
    }
  }
}
