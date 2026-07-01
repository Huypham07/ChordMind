import 'package:flutter/material.dart';
import '../theme.dart';

/// A clean, consistent empty/placeholder state: muted icon + short title
/// (+ optional one-line subtitle). Used for pending features and no-data views.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: cm.textMuted),
          const SizedBox(height: AppSpace.s12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: TextStyle(color: cm.textMuted), textAlign: TextAlign.center),
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpace.s16),
            action!,
          ],
        ]),
      ),
    );
  }
}
