import 'package:flutter/material.dart';

/// Ember color palette per `docs/PRD.md` §4.2 and `docs/DESIGN.md` §10.
///
/// All colors are constants so they participate in `const` widget constructors
/// (animations on `BoxDecoration` need const-friendly stops).
class EmberColors {
  EmberColors._();

  // ---------------------------------------------------------------------------
  // Background radial-gradient color stops.
  //
  // Each list is (inner -> outer). Used as the `colors` field on a
  // `RadialGradient` whose `radius` extends past the visible viewport.
  // ---------------------------------------------------------------------------

  /// Heat-mode background gradient: deep magenta-tinted black.
  static const List<Color> heatBackground = [
    Color(0xFF1A0A1A),
    Color(0xFF050108),
    Color(0xFF000000),
  ];

  /// Cool-mode background gradient: deep blue-tinted black.
  static const List<Color> coolBackground = [
    Color(0xFF0A1424),
    Color(0xFF02060C),
    Color(0xFF000000),
  ];

  /// Neutral (off / auto / eco) background gradient: charcoal.
  static const List<Color> neutralBackground = [
    Color(0xFF0D0D12),
    Color(0xFF050507),
    Color(0xFF000000),
  ];

  // ---------------------------------------------------------------------------
  // Mode accents (heat / cool / eco / fan).
  // ---------------------------------------------------------------------------

  /// Heat primary glow.
  static const Color heatGlow = Color(0xFFFF6432);

  /// Heat accent gradient (high -> low).
  static const List<Color> heatGradient = [
    Color(0xFFFF8A50),
    Color(0xFFFF4516),
  ];

  /// Heat text gradient.
  static const List<Color> heatText = [Color(0xFFFFFFFF), Color(0xFFFFB89A)];

  /// Cool primary glow.
  static const Color coolGlow = Color(0xFF50AAFF);

  /// Cool accent gradient.
  static const List<Color> coolGradient = [
    Color(0xFF80C8FF),
    Color(0xFF3070D0),
  ];

  /// Cool text gradient.
  static const List<Color> coolText = [Color(0xFFFFFFFF), Color(0xFFA8D4FF)];

  /// Eco / away accent (single green).
  static const Color eco = Color(0xFF4ADE80);

  /// Fan active gradient (white -> silver -> graphite).
  static const List<Color> fanActiveGradient = [
    Color(0xFFFFFFFF),
    Color(0xFFD8DEE8),
    Color(0xFF8A91A0),
  ];

  /// Fan inactive gradient.
  static const List<Color> fanInactiveGradient = [
    Color(0xFF9AA0AC),
    Color(0xFF5A5E68),
  ];

  // ---------------------------------------------------------------------------
  // Text opacity tiers (white-based).
  // ---------------------------------------------------------------------------

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0x99FFFFFF); // 60%
  static const Color textTertiary = Color(0x66FFFFFF); // 40%
  static const Color textDisabled = Color(0x4DFFFFFF); // 30%

  /// Surface seed for `ColorScheme.dark` — pure black.
  static const Color surface = Color(0xFF000000);

  /// Opaque surface for floating menus (dropdown popups, bottom sheets) that
  /// would otherwise inherit the theme's transparent `canvasColor` and render
  /// see-through (Issue #70). Slightly lifted off pure black so the menu reads
  /// as elevated against the background gradient.
  static const Color menuSurface = Color(0xFF111114);
}
