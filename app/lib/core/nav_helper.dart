// app/lib/core/nav_helper.dart
//
// Task S2: shared bottom-nav/rail tap handler for AppScaffold users (Home,
// Settings, ...), mapping nav index -> route. Keeps the index->route mapping
// in one place instead of duplicating it per screen.
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Handles an [AppScaffold] `onNav` tap: 0 -> Home, 2 -> Settings.
/// 1 (Library) has no route yet, so it's a no-op for now.
void onNavTap(BuildContext context, int index) {
  switch (index) {
    case 0:
      context.go('/');
    case 2:
      context.go('/settings');
  }
}
