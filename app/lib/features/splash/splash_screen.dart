import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme.dart';

/// Launch screen: the music-note logo bounces in (elastic) and bobs (jumps)
/// over a themed radial glow, then routes to Home.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _bob;

  @override
  void initState() {
    super.initState();
    // continuous up/down "jump"
    _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))
      ..repeat(reverse: true);
    Timer(const Duration(seconds: 3), () {
      if (mounted) context.go('/');
    });
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 1.0,
            colors: dark ? [const Color(0xFF231A3D), bg] : [const Color(0xFFF1E9FF), bg],
          ),
        ),
        child: Center(
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            tween: Tween(begin: 0.4, end: 1.0),
            builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
            child: AnimatedBuilder(
              animation: _bob,
              builder: (context, child) {
                final t = Curves.easeInOut.transform(_bob.value);
                return Transform.translate(offset: Offset(0, -18 * t), child: child);
              },
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEC4899).withValues(alpha: 0.30),
                        blurRadius: 48,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                  child: Image.asset('assets/images/music_note.png', width: 104, height: 104),
                ),
                const SizedBox(height: 24),
                ShaderMask(
                  shaderCallback: (r) => AppGradients.brand.createShader(r),
                  child: Text(
                    'ChordMind',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
