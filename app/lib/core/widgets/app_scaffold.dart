// app/lib/core/widgets/app_scaffold.dart
import 'package:flutter/material.dart';
import '../breakpoints.dart';
import '../theme.dart';

const _dests = [
  (icon: Icons.home_outlined, sel: Icons.home, label: 'Home'),
  (icon: Icons.library_music_outlined, sel: Icons.library_music, label: 'Library'),
  (icon: Icons.settings_outlined, sel: Icons.settings, label: 'Settings'),
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

    if (ff == FormFactor.compact) {
      return Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        body: SafeArea(child: body),
        bottomNavigationBar: NavigationBar(
          selectedIndex: navIndex,
          onDestinationSelected: onNav,
          destinations: [
            for (final d in _dests)
              NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.sel), label: d.label),
          ],
        ),
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
          NavigationRail(
            selectedIndex: navIndex,
            onDestinationSelected: onNav,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ShaderMask(
                shaderCallback: (r) => AppGradients.brand.createShader(r),
                child: const Icon(Icons.graphic_eq, size: 32, color: Colors.white),
              ),
            ),
            destinations: [
              for (final d in _dests)
                NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.sel), label: Text(d.label)),
            ],
          ),
          VerticalDivider(width: 1, color: cm.border),
          Expanded(
            child: Column(children: [
              _TopBar(title: title, actions: actions),
              Expanded(child: content),
            ]),
          ),
        ]),
      ),
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
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 8),
      child: Row(children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const Spacer(),
        ...?actions,
      ]),
    );
  }
}
