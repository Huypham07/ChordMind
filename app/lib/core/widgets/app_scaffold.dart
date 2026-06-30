// app/lib/core/widgets/app_scaffold.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../breakpoints.dart';
import '../theme.dart';
import '../theme_mode.dart';

typedef _Dest = ({IconData icon, IconData sel, String label});

const _dests = <_Dest>[
  (icon: Icons.home_outlined, sel: Icons.home_rounded, label: 'Home'),
  (icon: Icons.library_music_outlined, sel: Icons.library_music_rounded, label: 'Library'),
  (icon: Icons.tune_outlined, sel: Icons.tune_rounded, label: 'Settings'),
];

class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final Widget? rightPanel;
  final int navIndex;
  final ValueChanged<int>? onNav;
  final List<Widget>? actions;
  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    this.rightPanel,
    this.navIndex = 0,
    this.onNav,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) => _build(context, constraints.maxWidth));
  }

  Widget _build(BuildContext context, double width) {
    final ff = formFactorFor(width);
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    final navActions = actions ?? const [_ThemeToggle()];

    if (ff == FormFactor.compact) {
      return Scaffold(
        extendBody: true,
        appBar: AppBar(title: Text(title), actions: navActions, scrolledUnderElevation: 0),
        body: SafeArea(bottom: false, child: body),
        bottomNavigationBar: _MusicBottomNav(index: navIndex, onTap: onNav),
      );
    }

    final content = Row(children: [
      Expanded(child: body),
      if (rightPanel != null) ...[
        VerticalDivider(width: 1, color: cm.border),
        SizedBox(width: 360, child: rightPanel),
      ],
    ]);

    return Scaffold(
      body: SafeArea(
        child: Row(children: [
          _MusicRail(index: navIndex, onTap: onNav),
          VerticalDivider(width: 1, color: cm.border),
          Expanded(
            child: Column(children: [
              _TopBar(title: title, actions: navActions),
              Expanded(child: content),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Brand mark: a gradient waveform/EQ glyph.
class _BrandMark extends StatelessWidget {
  final double size;
  const _BrandMark({this.size = 30});
  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => AppGradients.brand.createShader(r),
      child: Icon(Icons.graphic_eq_rounded, size: size, color: Colors.white),
    );
  }
}

/// Floating, rounded mobile nav. Active item is a gradient pill that lifts (glow)
/// and reveals its label — raised + smooth.
class _MusicBottomNav extends StatelessWidget {
  final int index;
  final ValueChanged<int>? onTap;
  const _MusicBottomNav({required this.index, this.onTap});
  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    return SafeArea(
      top: false,
      child: Container(
        key: const Key('nav-bottom'),
        margin: const EdgeInsets.fromLTRB(AppSpace.s16, 0, AppSpace.s16, AppSpace.s12),
        padding: const EdgeInsets.all(AppSpace.s8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: cm.border),
          boxShadow: AppShadows.soft(Theme.of(context).brightness),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < _dests.length; i++)
              _NavPill(dest: _dests[i], active: i == index, onTap: () => onTap?.call(i)),
          ],
        ),
      ),
    );
  }
}

class _NavPill extends StatelessWidget {
  final _Dest dest;
  final bool active;
  final VoidCallback onTap;
  const _NavPill({required this.dest, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: active ? AppSpace.s16 : AppSpace.s12, vertical: 10),
        decoration: BoxDecoration(
          gradient: active ? AppGradients.brand : null,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          boxShadow: active
              ? [BoxShadow(color: const Color(0xFFEC4899).withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 4))]
              : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(active ? dest.sel : dest.icon, size: 22, color: active ? Colors.white : cm.textMuted),
          if (active) ...[
            const SizedBox(width: AppSpace.s8),
            Text(dest.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ]),
      ),
    );
  }
}

/// Custom web rail: gradient brand mark + vertical items; active item is a
/// gradient rounded tile with glow.
class _MusicRail extends StatelessWidget {
  final int index;
  final ValueChanged<int>? onTap;
  const _MusicRail({required this.index, this.onTap});
  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('nav-rail'),
      width: 84,
      color: Theme.of(context).colorScheme.surface,
      child: Column(children: [
        const SizedBox(height: AppSpace.s24),
        const _BrandMark(size: 34),
        const SizedBox(height: AppSpace.s32),
        for (var i = 0; i < _dests.length; i++)
          _RailTile(dest: _dests[i], active: i == index, onTap: () => onTap?.call(i)),
      ]),
    );
  }
}

class _RailTile extends StatelessWidget {
  final _Dest dest;
  final bool active;
  final VoidCallback onTap;
  const _RailTile({required this.dest, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            width: 52,
            height: 44,
            decoration: BoxDecoration(
              gradient: active ? AppGradients.brand : null,
              color: active ? null : cm.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              boxShadow: active
                  ? [BoxShadow(color: const Color(0xFFEC4899).withValues(alpha: 0.40), blurRadius: 16, offset: const Offset(0, 4))]
                  : null,
            ),
            child: Icon(active ? dest.sel : dest.icon, size: 22, color: active ? Colors.white : cm.textMuted),
          ),
          const SizedBox(height: 4),
          Text(dest.label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active ? Theme.of(context).colorScheme.onSurface : cm.textMuted)),
        ]),
      ),
    );
  }
}

/// Light/dark toggle, shown by default in the nav top bar / app bar.
class _ThemeToggle extends ConsumerWidget {
  const _ThemeToggle();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final dark = mode == ThemeMode.dark ||
        (mode == ThemeMode.system && MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    return IconButton(
      tooltip: 'Đổi sáng/tối',
      icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
      onPressed: () =>
          ref.read(themeModeProvider.notifier).state = dark ? ThemeMode.light : ThemeMode.dark,
    );
  }
}

class _TopBar extends StatelessWidget {
  final String title;
  final List<Widget>? actions;
  const _TopBar({required this.title, this.actions});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.s24, AppSpace.s16, AppSpace.s16, AppSpace.s8),
      child: Row(children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const Spacer(),
        ...?actions,
      ]),
    );
  }
}
