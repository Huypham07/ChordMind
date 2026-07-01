// app/lib/core/widgets/section_header.dart
import 'package:flutter/material.dart';
import '../theme.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader({super.key, required this.title});
  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s8),
      child: Row(children: [
        Text(title.toUpperCase(),
            style: TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: cm.textMuted)),
        const SizedBox(width: AppSpace.s12),
        Expanded(child: Divider(color: cm.border, height: 1)),
      ]),
    );
  }
}
