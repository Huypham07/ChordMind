// app/lib/core/widgets/info_chip.dart
import 'package:flutter/material.dart';
import '../theme.dart';

class InfoChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  const InfoChip({super.key, required this.label, this.icon});
  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12, vertical: AppSpace.s4 + 2),
      decoration: BoxDecoration(
        color: cm.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: cm.textMuted), const SizedBox(width: 6)],
        Text(label, style: TextStyle(fontSize: 13, color: cm.textMuted, fontWeight: FontWeight.w500)),
      ]),
    );
  }
}
