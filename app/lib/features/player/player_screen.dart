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
import 'package:chordmind/core/widgets/gradient_button.dart';
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
  bool _generating = false;
  // Playback position drives the beat cursor ~10x/sec. Kept as a notifier so only
  // the chord widgets rebuild on each tick, not the whole screen (incl. the
  // WebView) — that was making the video controls feel laggy.
  final _pos = ValueNotifier<double>(0);
  int _tab = 0;
  int _transpose = 0;
  String? _selectedChord;

  static const _tabs = ['Chords', 'Lyrics', 'Re-harm', 'Band', 'Versions'];

  @override
  void initState() {
    super.initState();
    _loadAnalysis();
    // The WebView is a heavy platform view; creating it in initState janks the
    // push transition ("khựng 1 nhịp"). Defer it until the slide-in finishes —
    // the video slot shows a placeholder until then, so the transition stays smooth.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initPlayerWhenSettled());
  }

  void _initPlayerWhenSettled() {
    if (!mounted) return;
    final anim = ModalRoute.of(context)?.animation;
    if (anim == null || anim.isCompleted) {
      _initPlayer();
      return;
    }
    void onStatus(AnimationStatus s) {
      if (s == AnimationStatus.completed) {
        anim.removeStatusListener(onStatus);
        _initPlayer();
      }
    }
    anim.addStatusListener(onStatus);
  }

  void _initPlayer() {
    if (!mounted) return;
    try {
      _yt = YoutubePlayerController.fromVideoId(
          videoId: widget.youtubeId,
          // strictRelatedVideos keeps the end screen from wandering off to other
          // songs — we only ever want this one video.
          params: const YoutubePlayerParams(showControls: true, strictRelatedVideos: true));
      _sub = _yt!.videoStateStream.listen((s) {
        _pos.value = s.position.inMilliseconds / 1000.0;
      });
      setState(() {}); // swap the placeholder for the real player
    } catch (_) {
      // YoutubePlayerController may throw in test/headless environments;
      // the rest of the screen still renders without the player.
    }
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

  /// No analysis on server or on-device → build a placeholder, save it locally,
  /// and show it. Lets us play along offline until the real analyzer lands.
  Future<void> _generate() async {
    setState(() => _generating = true);
    final r = await ref.read(songRepositoryProvider).generate(widget.youtubeId, title: _r?.source.title);
    if (mounted) {
      setState(() {
        _r = r;
        _analysisFailed = false;
        _generating = false;
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _yt?.close();
    _pos.dispose();
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
            // Square (no card/rounding): the WebView is a platform view painted on
            // top and can't be clipped, so a rounded card behind it just peeks out.
            child: AspectRatio(
                aspectRatio: 16 / 9,
                child: _yt != null
                    ? YoutubePlayer(controller: _yt!)
                    : Container(
                        color: Colors.black,
                        child: const Center(
                            child: Icon(Icons.play_circle_outline,
                                color: Colors.white54, size: 64)))),
          ),
        ),
      ),
      if (r != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
          child: Row(children: [
            InfoChip(label: r.key, icon: Icons.music_note),
            const SizedBox(width: 6),
            InfoChip(label: '${r.source.bpm.round()} BPM', icon: Icons.speed),
            const Spacer(),
            _TransposeControl(
              value: _transpose,
              onChanged: (v) => setState(() => _transpose = v.clamp(-12, 12)),
            ),
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
    // Detail screen: no bottom nav, just the AppBar back button.
    return AppScaffold(title: r?.source.title ?? 'ChordMind', body: body, showNav: false);
  }

  Widget _analysisArea(AnalysisResult? r) {
    if (r != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.all(AppSpace.s16),
          child: ValueListenableBuilder<double>(
            valueListenable: _pos,
            builder: (_, pos, _) => CurrentChordBar(
                result: r, positionSeconds: pos, semitones: _transpose, songKey: r.key),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
          child: PillTabs(tabs: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i)),
        ),
        const SizedBox(height: AppSpace.s8),
        Expanded(child: _tabBody(r)),
      ]);
    }
    if (_analysisFailed) {
      return EmptyState(
        icon: Icons.graphic_eq_rounded,
        title: 'Chưa có hợp âm',
        subtitle: 'Tạo hợp âm mẫu để chơi thử (lưu trên máy).',
        action: GradientButton(
          label: 'Sinh hợp âm',
          busy: _generating,
          onPressed: _generating ? null : _generate,
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }

  Widget _tabBody(AnalysisResult r) {
    switch (_tab) {
      case 0:
        return ValueListenableBuilder<double>(
          valueListenable: _pos,
          builder: (_, pos, _) => ChordGrid(
              result: r,
              positionSeconds: pos,
              semitones: _transpose,
              songKey: r.key,
              onTapChord: _onTapChord),
        );
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

/// Compact −/+ semitone control for transposing the displayed chords.
class _TransposeControl extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _TransposeControl({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    final label = value == 0 ? '±0' : (value > 0 ? '+$value' : '$value');
    return Container(
      margin: const EdgeInsets.only(left: AppSpace.s8),
      decoration: BoxDecoration(
        color: cm.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: cm.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove, size: 18),
          onPressed: value > -12 ? () => onChanged(value - 1) : null,
        ),
        GestureDetector(
          onTap: value != 0 ? () => onChanged(0) : null,
          child: SizedBox(
            width: 28,
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface, // explicit → no theme fade
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add, size: 18),
          onPressed: value < 12 ? () => onChanged(value + 1) : null,
        ),
      ]),
    );
  }
}
