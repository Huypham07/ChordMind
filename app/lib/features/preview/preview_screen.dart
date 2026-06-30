// app/lib/features/preview/preview_screen.dart
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../core/widgets/gradient_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/info_chip.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/pill_tabs.dart';
import '../../core/widgets/search_pill.dart';

/// Screenshot target: renders the component gallery. Not part of normal navigation.
class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key});
  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  int _tab = 0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Component preview')),
      body: ListView(padding: const EdgeInsets.all(AppSpace.s24), children: [
        const SectionHeader(title: 'Buttons'),
        Row(children: [
          GradientButton(label: 'Analyze', onPressed: () {}),
          const SizedBox(width: AppSpace.s12),
          const GradientButton(label: 'Busy', busy: true),
        ]),
        const SizedBox(height: AppSpace.s24),
        const SectionHeader(title: 'Chips & tabs'),
        Wrap(spacing: AppSpace.s8, children: const [
          InfoChip(label: 'C major', icon: Icons.music_note),
          InfoChip(label: '120 BPM', icon: Icons.speed),
        ]),
        const SizedBox(height: AppSpace.s12),
        PillTabs(tabs: const ['Chords', 'Lyrics', 'Band'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
        const SizedBox(height: AppSpace.s24),
        const SectionHeader(title: 'Card & search'),
        AppCard(child: Text('A surface card', style: Theme.of(context).textTheme.titleMedium)),
        const SizedBox(height: AppSpace.s12),
        SearchPill(controller: TextEditingController(), onSubmit: () {}),
      ]),
    );
  }
}
