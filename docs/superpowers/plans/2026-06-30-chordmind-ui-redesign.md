# ChordMind UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the ChordMind Flutter UI into a polished, product-grade, vibrant (Spotify-like) experience — light + dark, **responsive (web shows a web layout, mobile shows a mobile layout)** — without changing app logic.

**Architecture:** A token-driven theme (`core/theme/`) + reusable widget library (`core/widgets/`) + an adaptive shell (`AppScaffold`) that swaps NavigationRail (web) vs bottom navigation (mobile) by breakpoint. Screens (Home, Player, Diagrams) are rebuilt on these. A `/preview` route renders each screen with canned data so any screen is screenshottable headlessly without the server.

**Tech Stack:** Flutter 3.44, Dart 3, Riverpod, go_router, `google_fonts` (Sora + Inter). Screenshots via headless Google Chrome against the built web bundle.

## Global Constraints

- Style: **vibrant, Spotify-like, product-grade**. Brand gradient **`#8B5CF6` → `#EC4899`** (135°).
- **Light + dark both polished**; default follows system. Token values per spec §2 (tunable via screenshots).
- **Responsive, platform-distinct:** compact `<600` = mobile (stacked, bottom nav, bottom-sheet diagrams); medium `600–1024`; expanded `≥1024` = web (NavigationRail, multi-column, persistent right diagram panel, hover). Same features, different presentation.
- **Do NOT change logic:** `grid_sync.activeChordIndex`, `models.dart`, `api.dart`, `song_repository.dart`, server. Only theme + layout + widgets.
- Only new dependency allowed: `google_fonts`. Effects (gradient/shadow/blur) use built-in Flutter.
- Validation gate is **screenshots** (web, light+dark, compact+expanded) + existing tests still green + `flutter build web` ok.
- Each task: light widget test (renders / key behavior) first, then implement, then commit. App at `app/`, package `chordmind`. No `Co-Authored-By` trailer.

---

### Task 1: Design tokens, theme, typography

**Files:**
- Modify: `app/lib/core/theme.dart` (replace with token-driven theme)
- Modify: `app/pubspec.yaml` (add `google_fonts`)
- Test: `app/test/theme_test.dart` (update)

**Interfaces:**
- Produces: `chordMindLight`/`chordMindDark` `ThemeData`; `ChordMindColors` extension with `chordActive, chordIdle, beatMarker, surfaceAlt, textMuted, border, segmentVerse, segmentChorus, segmentOther, danger`; `AppGradients.brand` (`LinearGradient`); `AppRadii` (sm8/md12/lg16/xl20/pill999); `AppSpace` (s4..s48); `AppShadows.soft(brightness)`. Text theme uses Sora (display/title) + Inter (body) via `google_fonts`.

- [ ] **Step 1: Add dependency**

Run: `cd app && flutter pub add google_fonts`
Expected: `google_fonts` appears in `pubspec.yaml`, `pub get` succeeds.

- [ ] **Step 2: Write the failing test**

```dart
// app/test/theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/theme.dart';

void main() {
  test('themes expose vibrant ChordMind tokens for light and dark', () {
    for (final t in [chordMindLight, chordMindDark]) {
      final c = t.extension<ChordMindColors>();
      expect(c, isNotNull);
      expect(c!.chordActive, isNot(c.chordIdle));
      expect(c.textMuted, isNot(c.border));
    }
    expect(AppGradients.brand.colors.first, const Color(0xFF8B5CF6));
    expect(AppGradients.brand.colors.last, const Color(0xFFEC4899));
    expect(AppRadii.lg, 16.0);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd app && flutter test test/theme_test.dart`
Expected: FAIL (missing `AppGradients`, `ChordMindColors.chordIdle`, etc.)

- [ ] **Step 4: Implement the token-driven theme**

```dart
// app/lib/core/theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppRadii {
  static const sm = 8.0, md = 12.0, lg = 16.0, xl = 20.0, pill = 999.0;
}

class AppSpace {
  static const s4 = 4.0, s8 = 8.0, s12 = 12.0, s16 = 16.0, s24 = 24.0, s32 = 32.0, s48 = 48.0;
}

class AppGradients {
  static const brand = LinearGradient(
    colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppShadows {
  static List<BoxShadow> soft(Brightness b) => [
        BoxShadow(
          color: b == Brightness.dark
              ? Colors.black.withValues(alpha: 0.40)
              : const Color(0xFF141020).withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];
}

@immutable
class ChordMindColors extends ThemeExtension<ChordMindColors> {
  final Color chordActive, chordIdle, beatMarker, surfaceAlt, textMuted, border;
  final Color segmentVerse, segmentChorus, segmentOther, danger;
  const ChordMindColors({
    required this.chordActive,
    required this.chordIdle,
    required this.beatMarker,
    required this.surfaceAlt,
    required this.textMuted,
    required this.border,
    required this.segmentVerse,
    required this.segmentChorus,
    required this.segmentOther,
    required this.danger,
  });
  @override
  ChordMindColors copyWith({
    Color? chordActive, Color? chordIdle, Color? beatMarker, Color? surfaceAlt,
    Color? textMuted, Color? border, Color? segmentVerse, Color? segmentChorus,
    Color? segmentOther, Color? danger,
  }) =>
      ChordMindColors(
        chordActive: chordActive ?? this.chordActive,
        chordIdle: chordIdle ?? this.chordIdle,
        beatMarker: beatMarker ?? this.beatMarker,
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        textMuted: textMuted ?? this.textMuted,
        border: border ?? this.border,
        segmentVerse: segmentVerse ?? this.segmentVerse,
        segmentChorus: segmentChorus ?? this.segmentChorus,
        segmentOther: segmentOther ?? this.segmentOther,
        danger: danger ?? this.danger,
      );
  @override
  ChordMindColors lerp(ChordMindColors? o, double t) {
    if (o == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return ChordMindColors(
      chordActive: l(chordActive, o.chordActive),
      chordIdle: l(chordIdle, o.chordIdle),
      beatMarker: l(beatMarker, o.beatMarker),
      surfaceAlt: l(surfaceAlt, o.surfaceAlt),
      textMuted: l(textMuted, o.textMuted),
      border: l(border, o.border),
      segmentVerse: l(segmentVerse, o.segmentVerse),
      segmentChorus: l(segmentChorus, o.segmentChorus),
      segmentOther: l(segmentOther, o.segmentOther),
      danger: l(danger, o.danger),
    );
  }
}

const _primary = Color(0xFF8B5CF6);
const _secondary = Color(0xFFEC4899);

ThemeData _theme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: _primary,
    brightness: b,
    primary: _primary,
    secondary: _secondary,
    surface: dark ? const Color(0xFF1A1820) : Colors.white,
  ).copyWith(
    surface: dark ? const Color(0xFF1A1820) : Colors.white,
  );
  final bg = dark ? const Color(0xFF0E0D12) : const Color(0xFFFAFAFB);
  final text = dark ? const Color(0xFFECEAF2) : const Color(0xFF1A1820);

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: bg);
  return base.copyWith(
    textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displaySmall: GoogleFonts.sora(fontSize: 28, fontWeight: FontWeight.w700, color: text),
      headlineSmall: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.w700, color: text),
      titleLarge: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w600, color: text),
      titleMedium: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w600, color: text),
    ),
    extensions: [
      ChordMindColors(
        chordActive: _primary, // gradient drawn at widget level; this is the fallback solid
        chordIdle: dark ? const Color(0xFF232030) : const Color(0xFFF2F1F5),
        beatMarker: _primary,
        surfaceAlt: dark ? const Color(0xFF232030) : const Color(0xFFF2F1F5),
        textMuted: dark ? const Color(0xFF9D98AD) : const Color(0xFF6B6878),
        border: dark ? const Color(0xFF2A2733) : const Color(0xFFE6E4EC),
        segmentVerse: _primary.withValues(alpha: 0.14),
        segmentChorus: _secondary.withValues(alpha: 0.14),
        segmentOther: (dark ? Colors.white : Colors.black).withValues(alpha: 0.06),
        danger: const Color(0xFFF43F5E),
      ),
    ],
  );
}

final chordMindLight = _theme(Brightness.light);
final chordMindDark = _theme(Brightness.dark);
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd app && flutter test test/theme_test.dart`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add app/lib/core/theme.dart app/pubspec.yaml app/pubspec.lock app/test/theme_test.dart
git commit -m "feat(app): token-driven vibrant theme (brand gradient, Sora/Inter, light+dark)"
```

---

### Task 2: Core widget library + sample data + `/preview` route

**Files:**
- Create: `app/lib/core/widgets/gradient_button.dart`
- Create: `app/lib/core/widgets/app_card.dart`
- Create: `app/lib/core/widgets/info_chip.dart`
- Create: `app/lib/core/widgets/section_header.dart`
- Create: `app/lib/core/widgets/pill_tabs.dart`
- Create: `app/lib/core/widgets/search_pill.dart`
- Create: `app/lib/core/sample.dart` (canned `AnalysisResult` for previews)
- Create: `app/lib/features/preview/preview_screen.dart`
- Modify: `app/lib/core/router.dart` (add `/preview`)
- Test: `app/test/widgets_test.dart`

**Interfaces:**
- Consumes: theme tokens (Task 1), `AnalysisResult` (`core/models.dart`).
- Produces:
  - `GradientButton({required String label, VoidCallback? onPressed, bool busy})` — pill, brand gradient, disabled/busy state.
  - `AppCard({required Widget child, EdgeInsets? padding, VoidCallback? onTap})` — surface + radius lg + soft shadow + ink.
  - `InfoChip({required String label, IconData? icon})`.
  - `SectionHeader({required String title})`.
  - `PillTabs({required List<String> tabs, required int index, required ValueChanged<int> onChanged})`.
  - `SearchPill({required TextEditingController controller, required VoidCallback onSubmit, String hint})`.
  - `sampleAnalysis` (a `const`-built `AnalysisResult` via `AnalysisResult.fromJson`) for previews.
  - `PreviewScreen` and route `/preview` rendering the component gallery (screenshot target).

- [ ] **Step 1: Write the failing test**

```dart
// app/test/widgets_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/core/widgets/gradient_button.dart';
import 'package:chordmind/core/widgets/pill_tabs.dart';

Widget _wrap(Widget w) => MaterialApp(theme: chordMindLight, home: Scaffold(body: w));

void main() {
  testWidgets('GradientButton shows label and fires onPressed', (t) async {
    var tapped = false;
    await t.pumpWidget(_wrap(GradientButton(label: 'Analyze', onPressed: () => tapped = true)));
    expect(find.text('Analyze'), findsOneWidget);
    await t.tap(find.text('Analyze'));
    expect(tapped, isTrue);
  });

  testWidgets('PillTabs reports tapped index', (t) async {
    var idx = 0;
    await t.pumpWidget(_wrap(StatefulBuilder(
      builder: (_, set) => PillTabs(
        tabs: const ['Chords', 'Lyrics'], index: idx,
        onChanged: (i) => set(() => idx = i)),
    )));
    await t.tap(find.text('Lyrics'));
    await t.pump();
    expect(idx, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/widgets_test.dart`
Expected: FAIL (widgets not found)

- [ ] **Step 3: Implement the widgets**

```dart
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
```

```dart
// app/lib/core/widgets/app_card.dart
import 'package:flutter/material.dart';
import '../theme.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  const AppCard({super.key, required this.child, this.padding, this.onTap});
  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: cm.border),
        boxShadow: AppShadows.soft(Theme.of(context).brightness),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding ?? const EdgeInsets.all(AppSpace.s16), child: child),
        ),
      ),
    );
  }
}
```

```dart
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
```

```dart
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
```

```dart
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
```

```dart
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
            decoration: InputDecoration(hintText: hint, border: InputBorder.none),
          ),
        ),
      ]),
    );
  }
}
```

```dart
// app/lib/core/sample.dart
import 'models.dart';

/// Canned analysis for the /preview route and screenshots (no server needed).
final sampleAnalysis = AnalysisResult.fromJson({
  'songId': 'sample',
  'source': {'youtubeId': 'sample', 'title': 'Sample Song — Demo', 'duration': 16.0, 'bpm': 120.0, 'timeSignature': 4},
  'key': 'C major',
  'beats': [for (var i = 0; i < 32; i++) {'time': i * 0.5, 'beatNum': (i % 4) + 1}],
  'downbeats': [for (var i = 0; i < 8; i++) i * 2.0],
  'chords': [
    for (var i = 0; i < 8; i++)
      {'chord': ['C', 'G', 'Am', 'F'][i % 4], 'start': i * 2.0, 'end': i * 2.0 + 2.0, 'confidence': 0.95}
  ],
  'synchronizedChords': [
    for (var i = 0; i < 8; i++) {'chord': ['C', 'G', 'Am', 'F'][i % 4], 'beatIndex': i * 4}
  ],
  'segments': [
    {'label': 'verse', 'start': 0.0, 'end': 8.0},
    {'label': 'chorus', 'start': 8.0, 'end': 16.0},
  ],
});
```

```dart
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
```

```dart
// app/lib/core/router.dart  (add the preview route)
import 'package:go_router/go_router.dart';
import 'package:chordmind/features/home/home_screen.dart';
import 'package:chordmind/features/player/player_screen.dart';
import 'package:chordmind/features/preview/preview_screen.dart';

final router = GoRouter(routes: [
  GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
  GoRoute(path: '/player/:id', builder: (_, s) => PlayerScreen(s.pathParameters['id']!)),
  GoRoute(path: '/preview', builder: (_, _) => const PreviewScreen()),
]);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/widgets_test.dart`
Expected: PASS

- [ ] **Step 5: Screenshot checkpoint**

Run from `app/`:
```bash
flutter build web
( cd build/web && python3 -m http.server 8099 >/tmp/web.log 2>&1 & echo $! > /tmp/web.pid )
sleep 2
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=1280,1400 \
  --screenshot=/tmp/cm-preview.png "http://localhost:8099/#/preview"
kill $(cat /tmp/web.pid)
```
Expected: `/tmp/cm-preview.png` shows buttons/chips/tabs/card/search with the brand gradient and Sora/Inter fonts. (Controller reviews the image.)

- [ ] **Step 6: Commit**

```bash
git add app/lib/core/widgets app/lib/core/sample.dart app/lib/features/preview app/lib/core/router.dart app/test/widgets_test.dart
git commit -m "feat(app): core widget library + /preview gallery + sample data"
```

---

### Task 3: Adaptive shell (NavigationRail vs bottom nav)

**Files:**
- Create: `app/lib/core/widgets/app_scaffold.dart`
- Create: `app/lib/core/breakpoints.dart`
- Test: `app/test/app_scaffold_test.dart`

**Interfaces:**
- Consumes: theme tokens.
- Produces:
  - `breakpoints.dart`: `enum FormFactor { compact, medium, expanded }`, `FormFactor formFactorFor(double width)` (compact `<600`, medium `<1024`, else expanded).
  - `AppScaffold({required String title, required Widget body, Widget? rightPanel, int navIndex = 0, ValueChanged<int>? onNav, List<Widget>? actions})`: on expanded → `NavigationRail` (Home/Library/Settings) + body + optional persistent `rightPanel`; on compact → `AppBar` + body + `NavigationBar` (bottom). `rightPanel` is ignored on compact (caller uses a bottom sheet instead).

- [ ] **Step 1: Write the failing test**

```dart
// app/test/app_scaffold_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/core/breakpoints.dart';
import 'package:chordmind/core/widgets/app_scaffold.dart';

void main() {
  test('formFactorFor maps widths', () {
    expect(formFactorFor(500), FormFactor.compact);
    expect(formFactorFor(800), FormFactor.medium);
    expect(formFactorFor(1300), FormFactor.expanded);
  });

  testWidgets('expanded shows NavigationRail, compact shows NavigationBar', (t) async {
    await t.binding.setSurfaceSize(const Size(1300, 900));
    await t.pumpWidget(MaterialApp(theme: chordMindLight,
      home: const AppScaffold(title: 'X', body: SizedBox())));
    expect(find.byType(NavigationRail), findsOneWidget);

    await t.binding.setSurfaceSize(const Size(420, 900));
    await t.pumpWidget(MaterialApp(theme: chordMindLight,
      home: const AppScaffold(title: 'X', body: SizedBox())));
    expect(find.byType(NavigationBar), findsOneWidget);
    await t.binding.setSurfaceSize(null);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/app_scaffold_test.dart`
Expected: FAIL (missing files)

- [ ] **Step 3: Implement**

```dart
// app/lib/core/breakpoints.dart
enum FormFactor { compact, medium, expanded }

FormFactor formFactorFor(double width) {
  if (width < 600) return FormFactor.compact;
  if (width < 1024) return FormFactor.medium;
  return FormFactor.expanded;
}
```

```dart
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
    final ff = formFactorFor(MediaQuery.sizeOf(context).width);
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/app_scaffold_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib/core/breakpoints.dart app/lib/core/widgets/app_scaffold.dart app/test/app_scaffold_test.dart
git commit -m "feat(app): adaptive shell — NavigationRail (web) vs bottom nav (mobile)"
```

---

### Task 4: Home redesign (responsive)

**Files:**
- Modify: `app/lib/features/home/home_screen.dart`
- Test: `app/test/home_test.dart` (update)

**Interfaces:**
- Consumes: `AppScaffold`, `SearchPill`, `GradientButton`, `AppCard`, `InfoChip` (Tasks 2–3), `songRepositoryProvider` (`core/song_repository.dart`), `formFactorFor`.
- Produces: redesigned `HomeScreen` — hero with brand gradient + tagline, `SearchPill` + `GradientButton` Analyze (calls `songRepositoryProvider.submit`, routes to `/player/{id}`, SnackBar on error), and a "Recent" section: a vertical list of `AppCard` on compact, a responsive wrap/grid of cards on expanded. Keeps `_ctrl` disposal + `mounted` guards.

- [ ] **Step 1: Update the widget test**

```dart
// app/test/home_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/features/home/home_screen.dart';
import 'package:chordmind/core/widgets/search_pill.dart';
import 'package:chordmind/core/widgets/gradient_button.dart';

void main() {
  testWidgets('home shows search pill and analyze button', (t) async {
    await t.binding.setSurfaceSize(const Size(1300, 900));
    await t.pumpWidget(ProviderScope(
      child: MaterialApp(theme: chordMindLight, home: const HomeScreen())));
    expect(find.byType(SearchPill), findsOneWidget);
    expect(find.widgetWithText(GradientButton, 'Analyze'), findsOneWidget);
    await t.binding.setSurfaceSize(null);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/home_test.dart`
Expected: FAIL (no SearchPill/GradientButton yet in HomeScreen)

- [ ] **Step 3: Implement**

```dart
// app/lib/features/home/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:chordmind/core/song_repository.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/core/breakpoints.dart';
import 'package:chordmind/core/widgets/app_scaffold.dart';
import 'package:chordmind/core/widgets/search_pill.dart';
import 'package:chordmind/core/widgets/gradient_button.dart';
import 'package:chordmind/core/widgets/app_card.dart';
import 'package:chordmind/core/widgets/info_chip.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    if (_ctrl.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(songRepositoryProvider).submit(_ctrl.text.trim());
      if (mounted) context.go('/player/${r.source.youtubeId}');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không phân tích được link. Kiểm tra URL YouTube.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = formFactorFor(MediaQuery.sizeOf(context).width) != FormFactor.compact;
    return AppScaffold(
      title: 'ChordMind',
      navIndex: 0,
      body: ListView(
        padding: const EdgeInsets.all(AppSpace.s24),
        children: [
          _Hero(),
          const SizedBox(height: AppSpace.s24),
          Row(children: [
            Expanded(child: SearchPill(controller: _ctrl, onSubmit: _analyze)),
            const SizedBox(width: AppSpace.s12),
            GradientButton(label: 'Analyze', busy: _busy, onPressed: _busy ? null : _analyze),
          ]),
          const SizedBox(height: AppSpace.s32),
          Text('Gần đây', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpace.s12),
          // recent list/grid (placeholder cards until a real recents source is wired)
          if (wide)
            Wrap(spacing: AppSpace.s16, runSpacing: AppSpace.s16, children: [
              for (var i = 0; i < 4; i++) SizedBox(width: 260, child: _RecentCard(index: i)),
            ])
          else
            Column(children: [for (var i = 0; i < 3; i++) Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.s12), child: _RecentCard(index: i))]),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.s32),
      decoration: BoxDecoration(
        gradient: AppGradients.brand,
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hợp âm cho mọi bài hát',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(color: Colors.white)),
        const SizedBox(height: AppSpace.s8),
        const Text('Dán link YouTube để xem hợp âm, thế bấm và chơi cùng.',
            style: TextStyle(color: Colors.white70)),
      ]),
    );
  }
}

class _RecentCard extends StatelessWidget {
  final int index;
  const _RecentCard({required this.index});
  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    return AppCard(
      onTap: () {},
      child: Row(children: [
        Container(width: 48, height: 48,
          decoration: BoxDecoration(gradient: AppGradients.brand, borderRadius: BorderRadius.circular(AppRadii.md)),
          child: const Icon(Icons.music_note, color: Colors.white)),
        const SizedBox(width: AppSpace.s12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Bài mẫu #${index + 1}', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const InfoChip(label: 'C major'),
        ])),
        Icon(Icons.chevron_right, color: cm.textMuted),
      ]),
    );
  }
}
```

- [ ] **Step 4: Run test + screenshot checkpoint**

Run: `cd app && flutter test test/home_test.dart` → PASS.
Then screenshot light + dark at compact + expanded (reuse the serve+chrome snippet from Task 2 Step 5, URL `http://localhost:8099/#/`, window sizes `420,900` and `1300,900`; for dark, the headless capture uses system theme — capture both by temporarily setting `themeMode` is not needed: capture default and note light/dark visually from the two `ThemeData`s via the `/preview` route too). Controller reviews images for "product-grade" look.

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/home/home_screen.dart app/test/home_test.dart
git commit -m "feat(app): redesign Home — hero, search pill, recent cards (responsive)"
```

---

### Task 5: Chord grid redesign + CurrentChordBar

**Files:**
- Modify: `app/lib/features/chord_grid/chord_grid.dart`
- Create: `app/lib/features/chord_grid/current_chord_bar.dart`
- Test: `app/test/chord_grid_widget_test.dart`

**Interfaces:**
- Consumes: `AnalysisResult`, `activeChordIndex` (unchanged `grid_sync.dart`), theme tokens, `SectionHeader`.
- Produces:
  - `ChordGrid({required AnalysisResult result, required double positionSeconds, void Function(String)? onTapChord})` — cells grouped into rows by `source.timeSignature` (one bar per group via `synchronizedChords` order), `SectionHeader` inserted at segment boundaries (by each cell's beat time falling into a `segments[]` range), active cell painted with `AppGradients.brand` + glow shadow, idle cell `chordIdle`.
  - `CurrentChordBar({required AnalysisResult result, required double positionSeconds})` — large current chord (from `activeChordIndex`) + a smaller "Tiếp theo" next chord; shows "—" when none active.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/chord_grid_widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/core/sample.dart';
import 'package:chordmind/features/chord_grid/current_chord_bar.dart';
import 'package:chordmind/features/chord_grid/chord_grid.dart';

Widget _wrap(Widget w) => MaterialApp(theme: chordMindLight, home: Scaffold(body: w));

void main() {
  testWidgets('CurrentChordBar shows the active chord at a position', (t) async {
    await t.pumpWidget(_wrap(CurrentChordBar(result: sampleAnalysis, positionSeconds: 0.5)));
    expect(find.text('C'), findsWidgets); // C is active at t=0.5
  });

  testWidgets('ChordGrid renders all cells and a section header', (t) async {
    await t.binding.setSurfaceSize(const Size(900, 1400));
    await t.pumpWidget(_wrap(ChordGrid(result: sampleAnalysis, positionSeconds: 0.0)));
    expect(find.text('VERSE'), findsOneWidget); // SectionHeader uppercases
    await t.binding.setSurfaceSize(null);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/chord_grid_widget_test.dart`
Expected: FAIL (CurrentChordBar missing; grid has no section headers)

- [ ] **Step 3: Implement**

```dart
// app/lib/features/chord_grid/current_chord_bar.dart
import 'package:flutter/material.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/core/theme.dart';
import 'grid_sync.dart';

class CurrentChordBar extends StatelessWidget {
  final AnalysisResult result;
  final double positionSeconds;
  const CurrentChordBar({super.key, required this.result, required this.positionSeconds});
  @override
  Widget build(BuildContext context) {
    final i = activeChordIndex(result, positionSeconds);
    final cells = result.synchronizedChords;
    final current = i >= 0 ? cells[i].chord : '—';
    final next = (i >= 0 && i + 1 < cells.length) ? cells[i + 1].chord : null;
    return Container(
      padding: const EdgeInsets.all(AppSpace.s16),
      decoration: BoxDecoration(gradient: AppGradients.brand, borderRadius: BorderRadius.circular(AppRadii.lg)),
      child: Row(children: [
        Text(current, style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800)),
        const Spacer(),
        if (next != null)
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const Text('Tiếp theo', style: TextStyle(color: Colors.white70, fontSize: 12)),
            Text(next, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
          ]),
      ]),
    );
  }
}
```

```dart
// app/lib/features/chord_grid/chord_grid.dart
import 'package:flutter/material.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/core/widgets/section_header.dart';
import 'grid_sync.dart';

class ChordGrid extends StatelessWidget {
  final AnalysisResult result;
  final double positionSeconds;
  final void Function(String chord)? onTapChord;
  const ChordGrid({super.key, required this.result, required this.positionSeconds, this.onTapChord});

  String? _segmentAt(double time) {
    for (final s in result.segments) {
      if (time >= s.start && time < s.end) return s.label;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    final active = activeChordIndex(result, positionSeconds);
    final perRow = result.source.timeSignature.clamp(2, 4);
    final cells = result.synchronizedChords;

    final children = <Widget>[];
    String? lastSeg;
    for (var i = 0; i < cells.length; i += perRow) {
      final rowStartTime = result.beats.isNotEmpty ? result.beats[cells[i].beatIndex].time : 0.0;
      final seg = _segmentAt(rowStartTime);
      if (seg != null && seg != lastSeg) {
        children.add(SectionHeader(title: seg));
        lastSeg = seg;
      }
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.s8),
        child: Row(children: [
          for (var j = i; j < i + perRow && j < cells.length; j++)
            Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s4),
              child: _Cell(label: cells[j].chord, active: j == active, cm: cm,
                  onTap: () => onTapChord?.call(cells[j].chord)),
            )),
        ]),
      ));
    }
    return ListView(padding: const EdgeInsets.all(AppSpace.s16), children: children);
  }
}

class _Cell extends StatelessWidget {
  final String label;
  final bool active;
  final ChordMindColors cm;
  final VoidCallback onTap;
  const _Cell({required this.label, required this.active, required this.cm, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: active ? AppGradients.brand : null,
          color: active ? null : cm.chordIdle,
          borderRadius: BorderRadius.circular(AppRadii.md),
          boxShadow: active
              ? [BoxShadow(color: const Color(0xFFEC4899).withValues(alpha: 0.45), blurRadius: 18, spreadRadius: 1)]
              : null,
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 20,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: active ? Colors.white : null)),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/chord_grid_widget_test.dart`
Expected: PASS (both tests)

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/chord_grid app/test/chord_grid_widget_test.dart
git commit -m "feat(app): redesign chord grid (measure rows, segments, glowing active) + CurrentChordBar"
```

---

### Task 6: Player redesign (adaptive two-pane)

**Files:**
- Modify: `app/lib/features/player/player_screen.dart`
- Test: update `app/test/home_test.dart` is unaffected; add `app/test/player_smoke_test.dart`

**Interfaces:**
- Consumes: `AppScaffold`, `PillTabs`, `AppCard`, `InfoChip` (Tasks 2–3), `ChordGrid` + `CurrentChordBar` (Task 5), `showChordDiagram` / diagram panel (Task 7 provides `ChordDiagramView`), `songRepositoryProvider`, `youtube_player_iframe`, `formFactorFor`.
- Produces: redesigned `PlayerScreen(youtubeId)` — loads analysis via repo; **compact**: stacked (player card → `CurrentChordBar` → `PillTabs` → `ChordGrid`), tap chord → bottom sheet diagram; **expanded**: `AppScaffold` with body = player + info chips + `CurrentChordBar` + `ChordGrid`, and `rightPanel` = persistent `ChordDiagramView` for the selected chord. Disposes `_yt` + `_sub`; `mounted` guards. Tabs: Chords/Lyrics/Re-harm/Band/Versions (last three placeholders).

> Task 7 produces `ChordDiagramView({String? chord})` (the panel/sheet body) and keeps `showChordDiagram(context, chord)` for compact. To avoid a circular dependency, implement Task 7 BEFORE wiring the panel here — this task consumes Task 7's `ChordDiagramView`.

- [ ] **Step 1: Write a smoke test (loads with a fake repo, renders tabs)**

```dart
// app/test/player_smoke_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/core/sample.dart';
import 'package:chordmind/core/song_repository.dart';
import 'package:chordmind/features/player/player_screen.dart';

class _FakeRepo implements SongRepository {
  @override
  Future<AnalysisResult> get(String id) async => sampleAnalysis;
  @override
  Future<AnalysisResult> submit(String url) async => sampleAnalysis;
  @override
  Future<List<({String youtubeId, String title})>> recent() async => [];
}

void main() {
  testWidgets('player loads analysis and shows Chords tab', (t) async {
    await t.binding.setSurfaceSize(const Size(1300, 900));
    await t.pumpWidget(ProviderScope(
      overrides: [songRepositoryProvider.overrideWithValue(_FakeRepo())],
      child: MaterialApp(theme: chordMindLight, home: const PlayerScreen('sample')),
    ));
    await t.pump(); // let the future resolve
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('Chords'), findsOneWidget);
    await t.binding.setSurfaceSize(null);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/player_smoke_test.dart`
Expected: FAIL (old player uses default TabBar text differently / no PillTabs)

- [ ] **Step 3: Implement**

```dart
// app/lib/features/player/player_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:chordmind/core/models.dart';
import 'package:chordmind/core/song_repository.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/core/breakpoints.dart';
import 'package:chordmind/core/widgets/app_scaffold.dart';
import 'package:chordmind/core/widgets/app_card.dart';
import 'package:chordmind/core/widgets/info_chip.dart';
import 'package:chordmind/core/widgets/pill_tabs.dart';
import 'package:chordmind/features/chord_grid/chord_grid.dart';
import 'package:chordmind/features/chord_grid/current_chord_bar.dart';
import 'package:chordmind/features/diagrams/chord_diagram_sheet.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String youtubeId;
  const PlayerScreen(this.youtubeId, {super.key});
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final YoutubePlayerController _yt;
  StreamSubscription? _sub;
  AnalysisResult? _r;
  double _pos = 0;
  int _tab = 0;
  String? _selectedChord;

  static const _tabs = ['Chords', 'Lyrics', 'Re-harm', 'Band', 'Versions'];

  @override
  void initState() {
    super.initState();
    _yt = YoutubePlayerController.fromVideoId(
        videoId: widget.youtubeId, params: const YoutubePlayerParams(showControls: true));
    _sub = _yt.videoStateStream.listen((s) {
      if (mounted) setState(() => _pos = s.position.inMilliseconds / 1000.0);
    });
    ref.read(songRepositoryProvider).get(widget.youtubeId).then((r) {
      if (mounted) setState(() => _r = r);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _yt.close();
    super.dispose();
  }

  void _onTapChord(String c) {
    final wide = formFactorFor(MediaQuery.sizeOf(context).width) != FormFactor.compact;
    if (wide) {
      setState(() => _selectedChord = c);
    } else {
      showChordDiagram(context, c);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final wide = formFactorFor(MediaQuery.sizeOf(context).width) != FormFactor.compact;
    final body = r == null
        ? const Center(child: CircularProgressIndicator())
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.all(AppSpace.s16),
              child: AppCard(padding: EdgeInsets.zero, child: AspectRatio(
                aspectRatio: 16 / 9, child: YoutubePlayer(controller: _yt))),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
              child: Row(children: [
                Expanded(child: Text(r.source.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge)),
                const SizedBox(width: AppSpace.s8),
                InfoChip(label: r.key, icon: Icons.music_note),
                const SizedBox(width: 6),
                InfoChip(label: '${r.source.bpm.round()} BPM', icon: Icons.speed),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpace.s16),
              child: CurrentChordBar(result: r, positionSeconds: _pos),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
              child: SingleChildScrollView(scrollDirection: Axis.horizontal,
                  child: PillTabs(tabs: _tabs, index: _tab, onChanged: (i) => setState(() => _tab = i))),
            ),
            Expanded(child: _tabBody(r)),
          ]);

    if (wide) {
      return AppScaffold(
        title: 'ChordMind',
        navIndex: 0,
        rightPanel: ChordDiagramView(chord: _selectedChord),
        body: body,
      );
    }
    return AppScaffold(title: r?.source.title ?? 'Đang tải…', body: body);
  }

  Widget _tabBody(AnalysisResult r) {
    switch (_tab) {
      case 0:
        return ChordGrid(result: r, positionSeconds: _pos, onTapChord: _onTapChord);
      case 1:
        return const Center(child: Text('Lyrics — sắp có'));
      case 2:
        return const Center(child: Text('Biến tấu hợp âm on-device — sắp có'));
      case 3:
        return const Center(child: Text('Đồng bộ ban nhạc — sắp có'));
      default:
        return const Center(child: Text('Versions — sắp có'));
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/player_smoke_test.dart`
Expected: PASS

- [ ] **Step 5: Screenshot checkpoint**

Serve build/web; with the local server (sqlite) running so `/player/<id>` works after a submit, OR screenshot the player via the smoke path is not possible headlessly — instead extend `/preview` (optional) or screenshot Home + grid via `/preview`. Minimum: capture Home + `/preview` at compact + expanded, light + dark. Controller reviews.

- [ ] **Step 6: Commit**

```bash
git add app/lib/features/player/player_screen.dart app/test/player_smoke_test.dart
git commit -m "feat(app): redesign Player — adaptive two-pane, current-chord bar, pill tabs"
```

---

### Task 7: Diagrams redesign (guitar + piano) + view/sheet

**Files:**
- Modify: `app/lib/features/diagrams/guitar_diagram.dart`
- Modify: `app/lib/features/diagrams/piano_diagram.dart`
- Modify: `app/lib/features/diagrams/chord_diagram_sheet.dart`
- Test: `app/test/diagrams_test.dart`

**Interfaces:**
- Consumes: `voicings.dart` (`guitarVoicings`, `pianoNotes` — unchanged), theme tokens.
- Produces:
  - `GuitarDiagram(GuitarVoicing v, {String? name})` — draws nut, fret lines, **X/O markers above muted/open strings**, finger dots, **barre bar**, optional chord name.
  - `PianoDiagram(List<int> notes)` — one octave with **white + black keys**, chord notes glow with `AppGradients.brand`.
  - `ChordDiagramView({String? chord})` — a column showing chord name + GuitarDiagram (if a voicing exists) + PianoDiagram; shows an empty hint when `chord == null` (used as the web right panel).
  - `showChordDiagram(BuildContext, String chord)` — bottom sheet wrapping `ChordDiagramView(chord: chord)` (mobile).

- [ ] **Step 1: Write the failing test**

```dart
// app/test/diagrams_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/theme.dart';
import 'package:chordmind/features/diagrams/chord_diagram_sheet.dart';

Widget _wrap(Widget w) => MaterialApp(theme: chordMindLight, home: Scaffold(body: w));

void main() {
  testWidgets('ChordDiagramView shows chord name for a known chord', (t) async {
    await t.pumpWidget(_wrap(const ChordDiagramView(chord: 'C')));
    expect(find.text('C'), findsWidgets);
  });
  testWidgets('ChordDiagramView shows empty hint when chord is null', (t) async {
    await t.pumpWidget(_wrap(const ChordDiagramView(chord: null)));
    expect(find.textContaining('Chọn'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/diagrams_test.dart`
Expected: FAIL (`ChordDiagramView` not defined)

- [ ] **Step 3: Implement** (guitar painter with nut/X/O/barre; piano with black keys; the view + sheet)

```dart
// app/lib/features/diagrams/guitar_diagram.dart
import 'package:flutter/material.dart';
import 'voicings.dart';

class GuitarDiagram extends StatelessWidget {
  final GuitarVoicing v;
  final String? name;
  const GuitarDiagram(this.v, {super.key, this.name});
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      height: 180, width: 160,
      child: CustomPaint(painter: _GuitarPainter(v, color)),
    );
  }
}

class _GuitarPainter extends CustomPainter {
  final GuitarVoicing v;
  final Color color;
  _GuitarPainter(this.v, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    const strings = 6, frets = 5;
    final top = 24.0;
    final gridH = size.height - top;
    final dx = size.width / (strings - 1);
    final dy = gridH / frets;
    final line = Paint()..color = color..strokeWidth = 1;
    // nut (thick top line)
    canvas.drawRect(Rect.fromLTWH(0, top - 3, size.width, 3), Paint()..color = color);
    for (var i = 0; i < strings; i++) {
      canvas.drawLine(Offset(i * dx, top), Offset(i * dx, top + gridH), line);
    }
    for (var f = 0; f <= frets; f++) {
      canvas.drawLine(Offset(0, top + f * dy), Offset(size.width, top + f * dy), line);
    }
    final tp = (String s) => TextPainter(
        text: TextSpan(text: s, style: TextStyle(color: color, fontSize: 12)),
        textDirection: TextDirection.ltr)
      ..layout();
    final dot = Paint()..color = color..style = PaintingStyle.fill;
    for (var s = 0; s < strings; s++) {
      final fret = v.frets[s];
      final x = s * dx;
      if (fret < 0) {
        final t = tp('×'); t.paint(canvas, Offset(x - t.width / 2, 4));
      } else if (fret == 0) {
        canvas.drawCircle(Offset(x, 12), 5, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.5);
      } else {
        canvas.drawCircle(Offset(x, top + (fret - 0.5) * dy), 8, dot);
      }
    }
    // barre
    for (final b in v.barres) {
      final ys = top + (b - 0.5) * dy;
      canvas.drawLine(Offset(0, ys), Offset(size.width, ys),
          Paint()..color = color..strokeWidth = 10..strokeCap = StrokeCap.round);
    }
  }
  @override
  bool shouldRepaint(_) => false;
}
```

```dart
// app/lib/features/diagrams/piano_diagram.dart
import 'package:flutter/material.dart';
import 'package:chordmind/core/theme.dart';

class PianoDiagram extends StatelessWidget {
  final List<int> notes; // semitone offsets 0..11
  const PianoDiagram(this.notes, {super.key});
  static const _white = [0, 2, 4, 5, 7, 9, 11];
  static const _blackAfter = {0: 1, 1: 3, 3: 6, 4: 8, 5: 10}; // white index -> black semitone

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 110, child: LayoutBuilder(builder: (context, c) {
      final ww = c.maxWidth / 7;
      return Stack(children: [
        Row(children: [
          for (final w in _white)
            Container(
              width: ww, height: 110,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                gradient: notes.contains(w) ? AppGradients.brand : null,
                color: notes.contains(w) ? null : Colors.white,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(6)),
                border: Border.all(color: Colors.black26),
              ),
            ),
        ]),
        for (final e in _blackAfter.entries)
          Positioned(
            left: (e.key + 1) * ww - ww * 0.3,
            child: Container(
              width: ww * 0.6, height: 68,
              decoration: BoxDecoration(
                gradient: notes.contains(e.value) ? AppGradients.brand : null,
                color: notes.contains(e.value) ? null : Colors.black,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)),
              ),
            ),
          ),
      ]);
    }));
  }
}
```

```dart
// app/lib/features/diagrams/chord_diagram_sheet.dart
import 'package:flutter/material.dart';
import 'package:chordmind/core/theme.dart';
import 'voicings.dart';
import 'guitar_diagram.dart';
import 'piano_diagram.dart';

class ChordDiagramView extends StatelessWidget {
  final String? chord;
  const ChordDiagramView({super.key, this.chord});
  @override
  Widget build(BuildContext context) {
    final cm = Theme.of(context).extension<ChordMindColors>()!;
    if (chord == null) {
      return Center(child: Text('Chọn một hợp âm để xem thế bấm',
          style: TextStyle(color: cm.textMuted)));
    }
    final v = guitarVoicings[chord];
    return Padding(
      padding: const EdgeInsets.all(AppSpace.s24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text(chord!, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpace.s24),
        if (v != null) GuitarDiagram(v, name: chord),
        const SizedBox(height: AppSpace.s24),
        PianoDiagram(pianoNotes(chord!)),
      ]),
    );
  }
}

void showChordDiagram(BuildContext context, String chord) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (_) => ChordDiagramView(chord: chord),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd app && flutter test test/diagrams_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add app/lib/features/diagrams app/test/diagrams_test.dart
git commit -m "feat(app): redesign diagrams (guitar nut/X-O/barre, piano black keys, panel+sheet)"
```

> Implementation order note: do Task 7 BEFORE Task 6 Step 3 (Player consumes `ChordDiagramView`). If executing in order, swap the build order of 6 and 7, or stub `ChordDiagramView` import is satisfied because Task 7 modifies the same `chord_diagram_sheet.dart` that already exists.

---

### Task 8: Theme toggle, main wiring, final screenshot verification

**Files:**
- Modify: `app/lib/main.dart` (ensure `MaterialApp.router` uses both themes + `themeMode`)
- Create: `app/lib/core/theme_mode.dart` (Riverpod `themeModeProvider`)
- Modify: `app/lib/core/widgets/app_scaffold.dart` (add a theme-toggle action on expanded top bar / mobile app bar)
- Test: `app/test/theme_toggle_test.dart`

**Interfaces:**
- Produces: `themeModeProvider` (`StateProvider<ThemeMode>` default `system`); a toggle action (icon button) cycling light/dark, wired into `AppScaffold` actions by default.

- [ ] **Step 1: Write the failing test**

```dart
// app/test/theme_toggle_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chordmind/core/theme_mode.dart';

void main() {
  test('themeModeProvider defaults to system', () {
    final c = ProviderContainer();
    expect(c.read(themeModeProvider), ThemeMode.system);
    c.read(themeModeProvider.notifier).state = ThemeMode.dark;
    expect(c.read(themeModeProvider), ThemeMode.dark);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd app && flutter test test/theme_toggle_test.dart`
Expected: FAIL (no `themeModeProvider`)

- [ ] **Step 3: Implement**

```dart
// app/lib/core/theme_mode.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final themeModeProvider = StateProvider<ThemeMode>((_) => ThemeMode.system);
```

```dart
// app/lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'core/theme_mode.dart';
import 'core/router.dart';

void main() => runApp(const ProviderScope(child: ChordMindApp()));

class ChordMindApp extends ConsumerWidget {
  const ChordMindApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: 'ChordMind',
        theme: chordMindLight,
        darkTheme: chordMindDark,
        themeMode: ref.watch(themeModeProvider),
        routerConfig: router,
      );
}
```

Add to `app_scaffold.dart` a default theme-toggle action when `actions == null`: a `Consumer` icon button that flips `themeModeProvider` between light/dark. (Import `flutter_riverpod` + `theme_mode.dart`; place the icon in both the compact AppBar `actions` and the expanded `_TopBar`.)

- [ ] **Step 4: Run tests + full suite**

Run: `cd app && flutter test`
Expected: ALL pass.

- [ ] **Step 5: Final screenshot verification**

Run from `app/`: build web, serve, and capture the matrix:
```bash
flutter build web
( cd build/web && python3 -m http.server 8099 >/tmp/web.log 2>&1 & echo $! > /tmp/web.pid )
sleep 2
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for size in 420,900 1300,900; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=$size \
    --screenshot=/tmp/cm-home-$size.png "http://localhost:8099/#/"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=$size \
    --screenshot=/tmp/cm-preview-$size.png "http://localhost:8099/#/preview"
done
kill $(cat /tmp/web.pid)
```
For Player + diagrams: run the server on sqlite, `flutter run -d chrome`, submit a URL, and capture the player at both widths (manual/controller). Controller reviews ALL images for product-grade quality in light AND dark (toggle via the new action), then iterates token values in `theme.dart` if needed.

- [ ] **Step 6: Commit**

```bash
git add app/lib/main.dart app/lib/core/theme_mode.dart app/lib/core/widgets/app_scaffold.dart app/test/theme_toggle_test.dart
git commit -m "feat(app): theme toggle + final wiring"
```

---

## Self-Review

**Spec coverage:** §2 tokens → Task 1. §3 components → Task 2. §4 responsive shell → Task 3. §5 Home → Task 4; Player → Task 6; chord grid (measure grouping, active glow, current-chord bar) → Task 5; Diagrams (guitar nut/X-O/barre, piano black keys, panel vs sheet) → Task 7. §6 web≠mobile → Tasks 3/6 (rail+rightPanel vs bottom nav+sheet). §7 light+dark → Tasks 1 & 8. §8 validate via screenshots → screenshot checkpoints in Tasks 2/4/8. §9 done criteria → Task 8 Step 5.

**Placeholder scan:** No TBD/TODO. Recent-songs cards use placeholder content (no recents source wired yet) — this is intentional and labeled, not a plan gap. Visual values (exact colors/spacing) are real, runnable code, tuned later via screenshots per spec §8.

**Type consistency:** `ChordMindColors` fields used in Tasks 4–7 all defined in Task 1. `AppGradients.brand`, `AppRadii.*`, `AppSpace.*` consistent across tasks. `formFactorFor`/`FormFactor` (Task 3) used in Tasks 4/6. `ChordDiagramView({chord})` produced in Task 7, consumed in Task 6 (build order note added). `activeChordIndex` unchanged (Task 5 consumes, does not redefine). `CurrentChordBar`/`ChordGrid` signatures consistent Task 5 ↔ Task 6. `themeModeProvider` Task 8.

**Build-order caveat:** Task 6 (Player) consumes `ChordDiagramView` from Task 7 — execute Task 7 before Task 6's implementation step (noted in both tasks).
