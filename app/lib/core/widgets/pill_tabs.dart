// app/lib/core/widgets/pill_tabs.dart
import 'package:flutter/material.dart';
import '../theme.dart';

class PillTabs extends StatelessWidget {
  final List<String> tabs;
  final int index;
  final ValueChanged<int> onChanged;
  const PillTabs({super.key, required this.tabs, required this.index, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    return Container(
      padding: const EdgeInsets.all(AppSpace.s4),
      decoration: BoxDecoration(color: cm.surfaceAlt, borderRadius: BorderRadius.circular(AppRadii.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < tabs.length; i++)
          GestureDetector(
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s8),
              decoration: BoxDecoration(
                gradient: i == index ? AppGradients.brand : null,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Text(tabs[i],
                  style: TextStyle(
                      color: i == index ? Colors.white : cm.textMuted,
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ),
      ]),
    );
  }
}
