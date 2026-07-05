// app/lib/features/player/player_screen.dart
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:youtube_player_iframe/youtube_player_iframe.dart' hide PlayerState;
import 'package:chordmind/core/models.dart';
import 'package:chordmind/core/song_repository.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/core/breakpoints.dart';
import 'package:chordmind/core/widgets/app_scaffold.dart';
import 'package:chordmind/core/widgets/gradient_button.dart';
import 'package:chordmind/core/widgets/info_chip.dart';
import 'package:chordmind/core/widgets/pill_tabs.dart';
import 'package:chordmind/core/widgets/empty_state.dart';
import 'package:chordmind/features/chord_grid/chord_timeline.dart';
import 'package:chordmind/features/chord_grid/current_chord_bar.dart';
import 'package:chordmind/features/diagrams/chord_diagram_sheet.dart';
import 'effective_audio_path.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String youtubeId;

  /// When set, the player runs in "file mode": it plays this local audio file
  /// (via just_audio) instead of the YouTube video, and analyzes the file.
  final String? audioFilePath;
  const PlayerScreen(this.youtubeId, {super.key, this.audioFilePath});
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  YoutubePlayerController? _yt;
  AudioPlayer? _audio;
  StreamSubscription? _sub;
  /// The local audio file to play/analyze: the router-provided path (fresh
  /// upload) if present, else the persisted path recorded on a re-opened
  /// file song's analysis (Task 6).
  String? get _audioPath => effectiveAudioPath(widget.audioFilePath, _r);
  bool get _fileMode => _audioPath != null;
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
    if (_fileMode) {
      _initFilePlayer();
      _loadAnalysis(); // like YouTube: don't auto-analyze; user taps "Sinh hợp âm"
    } else {
      _loadAnalysis();
      // The WebView is a heavy platform view; creating it in initState janks the
      // push transition ("khựng 1 nhịp"). Defer it until the slide-in finishes —
      // the video slot shows a placeholder until then, so the transition stays smooth.
      WidgetsBinding.instance.addPostFrameCallback((_) => _initPlayerWhenSettled());
    }
  }

  /// File mode: load the local audio into just_audio and drive the beat cursor
  /// from its position stream (same `_pos` the grid listens to).
  Future<void> _initFilePlayer() async {
    final player = AudioPlayer();
    _audio = player;
    _sub = player.positionStream.listen((d) => _pos.value = d.inMilliseconds / 1000.0);
    try {
      await player.setFilePath(_audioPath!);
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('file player load failed: $e');
    }
  }

  /// Opened-by-id file songs have no `widget.audioFilePath` (no router
  /// `extra`), so file playback can't start in `initState` — `_audioPath`
  /// only becomes available once the persisted analysis (`_r`) loads. Called
  /// after every `_r` update; a no-op once `_audio` exists (covers the
  /// fresh-upload case, where `_initFilePlayer` already ran synchronously
  /// from `initState`, and repeat analysis loads/regenerates).
  void _maybeInitFilePlayer() {
    if (_audio == null && _audioPath != null) _initFilePlayer();
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
      if (mounted) {
        setState(() => _r = r);
        _maybeInitFilePlayer();
      }
    } catch (_) {
      if (mounted) setState(() => _analysisFailed = true);
    }
  }

  /// No analysis on server or on-device → build a placeholder, save it locally,
  /// and show it. Lets us play along offline until the real analyzer lands.
  // Re-analyze: in file mode re-run on the same local file; otherwise via YouTube.
  Future<void> _generate() => _runGenerate(audioFilePath: _audioPath);

  /// Fallback: pick a local audio file (mp3/m4a/…) and analyze it through the
  /// same on-device pipeline. Useful when YouTube extraction is rate-limited.
  Future<void> _pickAndAnalyze() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.audio);
    final path = res?.files.single.path;
    if (path == null) return; // user cancelled
    await _runGenerate(audioFilePath: path);
  }

  Future<void> _runGenerate({String? audioFilePath}) async {
    setState(() => _generating = true);
    try {
      final r = await ref
          .read(songRepositoryProvider)
          .generate(widget.youtubeId, title: _r?.source.title, audioFilePath: audioFilePath);
      if (mounted) {
        setState(() {
          _r = r;
          _analysisFailed = false;
          _generating = false;
        });
        _maybeInitFilePlayer();
      }
    } catch (e, st) {
      // Surface analysis failures instead of silently hanging the button
      // (previously any throw left _generating stuck true forever).
      debugPrint('on-device analyze failed: $e\n$st');
      if (mounted) {
        setState(() {
          _generating = false;
          _analysisFailed = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Phân tích lỗi: $e'),
            duration: const Duration(seconds: 10),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _yt?.close();
    _audio?.dispose();
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
      // Playback source: YouTube video (default) or a local-file audio card.
      _topPlayer(),
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

    // Re-analyze on demand: re-runs the on-device model (using the model
    // currently selected in Settings) and updates the local analysis. Available
    // whether or not an analysis already exists.
    final actions = <Widget>[
      IconButton(
        tooltip: 'Tải file nhạc lên',
        onPressed: _generating ? null : _pickAndAnalyze,
        icon: const Icon(Icons.upload_file_rounded),
      ),
      IconButton(
        tooltip: 'Phân tích lại (YouTube)',
        onPressed: _generating ? null : _generate,
        icon: _generating
            ? const SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.refresh_rounded),
      ),
    ];
    if (wide) {
      return AppScaffold(
        title: 'ChordMind',
        navIndex: 0,
        rightPanel: ChordDiagramView(chord: _selectedChord),
        actions: actions,
        body: body,
      );
    }
    // Detail screen: no bottom nav, just the AppBar back button.
    return AppScaffold(
        title: r?.source.title ?? 'ChordMind', actions: actions, body: body, showNav: false);
  }

  Widget _topPlayer() {
    if (_fileMode) return _audioCard();
    // Video (YouTube). Square (no rounding): the WebView is a platform view
    // painted on top and can't be clipped.
    return Padding(
      padding: const EdgeInsets.all(AppSpace.s16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: _yt != null
                ? YoutubePlayer(controller: _yt!)
                : Container(
                    color: Colors.black,
                    child: const Center(
                        child: Icon(Icons.play_circle_outline, color: Colors.white54, size: 64))),
          ),
        ),
      ),
    );
  }

  static String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Widget _audioCard() {
    final audio = _audio;
    final name = p.basename(_audioPath!);
    return Padding(
      padding: const EdgeInsets.all(AppSpace.s16),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.s16),
        decoration: BoxDecoration(
            gradient: AppGradients.brand, borderRadius: BorderRadius.circular(AppRadii.lg)),
        child: Column(children: [
          Row(children: [
            const Icon(Icons.audiotrack_rounded, color: Colors.white, size: 28),
            const SizedBox(width: AppSpace.s12),
            Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          ]),
          if (audio == null)
            const Padding(
              padding: EdgeInsets.all(AppSpace.s16),
              child: CircularProgressIndicator(color: Colors.white),
            )
          else
            StreamBuilder<Duration>(
              stream: audio.positionStream,
              builder: (_, posSnap) {
                final pos = posSnap.data ?? Duration.zero;
                final dur = audio.duration ?? Duration.zero;
                final maxMs = dur.inMilliseconds.toDouble();
                final valMs = pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble();
                return Column(children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor: Colors.white24,
                    ),
                    child: Slider(
                      value: maxMs > 0 ? valMs : 0,
                      max: maxMs > 0 ? maxMs : 1,
                      onChanged: (v) => audio.seek(Duration(milliseconds: v.round())),
                    ),
                  ),
                  Row(children: [
                    Text(_fmt(pos), style: const TextStyle(color: Colors.white70)),
                    const Spacer(),
                    StreamBuilder<PlayerState>(
                      stream: audio.playerStateStream,
                      builder: (_, s) {
                        final playing = s.data?.playing ?? false;
                        return IconButton(
                          iconSize: 48,
                          color: Colors.white,
                          icon: Icon(
                              playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
                          onPressed: () => playing ? audio.pause() : audio.play(),
                        );
                      },
                    ),
                    const Spacer(),
                    Text(_fmt(dur), style: const TextStyle(color: Colors.white70)),
                  ]),
                ]);
              },
            ),
        ]),
      ),
    );
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
          builder: (_, pos, _) => ChordTimeline(
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
