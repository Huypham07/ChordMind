// app/lib/core/widgets/gradient_button.dart
import 'package:flutter/material.dart';
import '../theme.dart';

class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  const GradientButton({super.key, required this.label, this.onPressed, this.busy = false});
  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppGradients.brand,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s24, vertical: AppSpace.s12),
              child: busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ),
    );
  }
}
