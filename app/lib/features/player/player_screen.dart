// app/lib/features/player/player_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:chordmind/core/song_repository.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/features/chord_grid/chord_grid.dart';
import 'package:chordmind/features/diagrams/chord_diagram_sheet.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String youtubeId;
  const PlayerScreen(this.youtubeId, {super.key});
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final YoutubePlayerController _yt;
  AnalysisResult? _r;
  double _pos = 0;

  @override
  void initState() {
    super.initState();
    _yt = YoutubePlayerController.fromVideoId(
        videoId: widget.youtubeId, params: const YoutubePlayerParams(showControls: true));
    _yt.videoStateStream.listen((s) {
      if (mounted) setState(() => _pos = s.position.inMilliseconds / 1000.0);
    });
    ref.read(songRepositoryProvider).get(widget.youtubeId).then((r) => mounted ? setState(() => _r = r) : null);
  }

  @override
  void dispose() {
    _yt.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: Text(r?.source.title ?? 'Loading…'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Chords'), Tab(text: 'Lyrics'), Tab(text: 'Re-harm'),
            Tab(text: 'Band'), Tab(text: 'Versions'),
          ]),
        ),
        body: Column(children: [
          YoutubePlayer(controller: _yt),
          Expanded(
            child: r == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(children: [
                    ChordGrid(
                        result: r,
                        positionSeconds: _pos,
                        onTapChord: (c) => showChordDiagram(context, c)),
                    const Center(child: Text('Lyrics coming soon')),
                    const Center(child: Text('On-device re-harmonization coming soon')),
                    const Center(child: Text('Band sync coming soon')),
                    const Center(child: Text('Versions coming soon')),
                  ]),
          ),
        ]),
      ),
    );
  }
}
