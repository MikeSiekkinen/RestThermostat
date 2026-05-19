import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

/// Ember typography per `docs/PRD.md` §4.3 and `docs/DESIGN.md` §10/§11.1.
///
/// Font families are bundled under `assets/fonts/` and declared in
/// `pubspec.yaml`. Runtime fetching is disabled in `main()` so any
/// missing-family lookup fails loudly instead of silently hitting the network.
class EmberTypography {
  EmberTypography._();

  /// Fraunces serif, used for big temperature displays and screen titles.
  static TextStyle displayLarge({Color color = EmberColors.textPrimary}) {
    return GoogleFonts.fraunces(
      fontSize: 96,
      fontWeight: FontWeight.w300,
      height: 1.0,
      letterSpacing: -2.0,
      color: color,
    );
  }

  /// Geist sans-serif body copy.
  static TextStyle bodyMedium({Color color = EmberColors.textPrimary}) {
    return GoogleFonts.geist(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.4,
      color: color,
    );
  }

  /// JetBrains Mono uppercase tracked label for status pills and chips.
  static TextStyle labelSmall({Color color = EmberColors.textSecondary}) {
    return GoogleFonts.jetBrainsMono(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 1.5,
      height: 1.2,
      color: color,
    );
  }

  /// Instrument Serif italic accent for flourish copy (current temp readout
  /// under the dial, etc).
  static TextStyle bodyMediumItalic({Color color = EmberColors.textSecondary}) {
    return GoogleFonts.instrumentSerif(
      fontSize: 18,
      fontStyle: FontStyle.italic,
      height: 1.3,
      color: color,
    );
  }

  /// Build the `TextTheme` that gets wired into `emberTheme.textTheme`. The
  /// non-spec roles (headlineLarge, bodyLarge, etc) cover Material widgets
  /// the app hasn't yet styled explicitly — so a stray `Text` in some unseen
  /// Material widget still renders on-theme.
  static TextTheme textTheme() {
    return TextTheme(
      displayLarge: displayLarge(),
      headlineLarge: GoogleFonts.fraunces(
        fontSize: 32,
        fontWeight: FontWeight.w400,
        color: EmberColors.textPrimary,
      ),
      bodyLarge: GoogleFonts.geist(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: EmberColors.textPrimary,
      ),
      bodyMedium: bodyMedium(),
      bodySmall: GoogleFonts.geist(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: EmberColors.textSecondary,
      ),
      labelLarge: GoogleFonts.jetBrainsMono(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.5,
        color: EmberColors.textPrimary,
      ),
      labelSmall: labelSmall(),
    );
  }
}
