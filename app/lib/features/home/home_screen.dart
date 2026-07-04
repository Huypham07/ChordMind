// app/lib/features/home/home_screen.dart
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:chordmind/core/youtube.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/core/breakpoints.dart';
import 'package:chordmind/core/nav_helper.dart';
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
  String? _pickedFilePath; // selected local mp3, shown until Analyze is pressed

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // One "Analyze" for both entry points: a picked mp3 file, else a YouTube link.
  void _analyze() {
    if (_pickedFilePath != null) {
      final path = _pickedFilePath!;
      final id = 'file:${p.basename(path)}';
      context.push('/player/${Uri.encodeComponent(id)}', extra: path);
      return;
    }
    final id = parseYoutubeId(_ctrl.text);
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link YouTube không hợp lệ')),
      );
      return;
    }
    context.push('/player/$id');
  }

  // Pick a local mp3 and show it on Home (like typing a link). Analyze proceeds.
  Future<void> _pickFile() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['mp3']);
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    setState(() => _pickedFilePath = path);
  }

  @override
  Widget build(BuildContext context) {
    final wide = formFactorFor(MediaQuery.sizeOf(context).width) != FormFactor.compact;
    return AppScaffold(
      title: 'ChordMind',
      navIndex: 0,
      onNav: (i) => onNavTap(context, i),
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.s24),
        children: [
          _Hero(),
          const SizedBox(height: AppSpace.s24),
          Row(children: [
            Expanded(
              child: _pickedFilePath == null
                  ? SearchPill(controller: _ctrl, onSubmit: _analyze)
                  : _PickedFile(
                      name: p.basename(_pickedFilePath!),
                      onClear: () => setState(() => _pickedFilePath = null),
                    ),
            ),
            const SizedBox(width: AppSpace.s12),
            GradientButton(label: 'Analyze', onPressed: _analyze),
          ]),
          const SizedBox(height: AppSpace.s16),
          Row(children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12),
              child: Text('hoặc', style: Theme.of(context).textTheme.bodySmall),
            ),
            const Expanded(child: Divider()),
          ]),
          const SizedBox(height: AppSpace.s16),
          OutlinedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.upload_file_rounded),
            label: Text(_pickedFilePath == null ? 'Tải file MP3 lên' : 'Chọn file MP3 khác'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
            ),
          ),
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

/// Shows the selected mp3 (name + clear button) in place of the link field,
/// styled like the search pill.
class _PickedFile extends StatelessWidget {
  final String name;
  final VoidCallback onClear;
  const _PickedFile({required this.name, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
      decoration: BoxDecoration(
        color: cm.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: cm.border),
      ),
      child: Row(children: [
        const Icon(Icons.audiotrack_rounded, size: 20),
        const SizedBox(width: AppSpace.s8),
        Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
        IconButton(
          icon: const Icon(Icons.close_rounded, size: 20),
          onPressed: onClear,
          tooltip: 'Bỏ chọn',
        ),
      ]),
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
