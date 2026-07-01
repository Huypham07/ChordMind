// app/lib/core/widgets/search_pill.dart
import 'package:flutter/material.dart';
import '../theme.dart';

class SearchPill extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmit;
  final String hint;
  const SearchPill({super.key, required this.controller, required this.onSubmit, this.hint = 'Dán link YouTube…'});
  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: cm.border),
        boxShadow: AppShadows.soft(Theme.of(context).brightness),
      ),
      padding: const EdgeInsets.only(left: AppSpace.s16, right: AppSpace.s4),
      child: Row(children: [
        Icon(Icons.link, color: cm.textMuted, size: 20),
        const SizedBox(width: AppSpace.s8),
        Expanded(
          child: TextField(
            controller: controller,
            onSubmitted: (_) => onSubmit(),
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            decoration: InputDecoration(hintText: hint, border: InputBorder.none),
          ),
        ),
      ]),
    );
  }
}
