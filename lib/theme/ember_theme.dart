import 'package:flutter/material.dart';

import 'colors.dart';
import 'typography.dart';

/// The Ember `ThemeData` per `docs/DESIGN.md` §10/§11.
///
/// Used as `MaterialApp.darkTheme` and forced via `themeMode: ThemeMode.dark`.
/// No light theme is provided — system-light users still see Ember.
ThemeData buildEmberTheme() {
  final colorScheme = ColorScheme.dark(
    primary: EmberColors.heatGlow,
    secondary: EmberColors.coolGlow,
    tertiary: EmberColors.eco,
    surface: EmberColors.surface,
    onSurface: EmberColors.textPrimary,
    onPrimary: EmberColors.textPrimary,
    onSecondary: EmberColors.textPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: Colors.transparent,
    textTheme: EmberTypography.textTheme(),
    iconTheme: const IconThemeData(color: EmberColors.textPrimary),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: EmberColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
  );
}

/// Convenience singleton for use in `MaterialApp(darkTheme: emberTheme)`.
final ThemeData emberTheme = buildEmberTheme();
