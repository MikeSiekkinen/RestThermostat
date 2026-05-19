import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/theme/colors.dart';
import 'package:rest_thermostat/theme/ember_theme.dart';

void main() {
  // Touching `emberTheme` triggers google_fonts lookups, which need the
  // services binding for asset bundle resolution.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('emberTheme', () {
    test('is dark and Material 3', () {
      expect(emberTheme.brightness, Brightness.dark);
      expect(emberTheme.useMaterial3, true);
    });

    test(
      'scaffold and canvas are transparent so EmberBackground shines through',
      () {
        expect(emberTheme.scaffoldBackgroundColor, Colors.transparent);
        expect(emberTheme.canvasColor, Colors.transparent);
      },
    );

    test('color scheme primaries map to Ember accents', () {
      expect(emberTheme.colorScheme.primary, EmberColors.heatGlow);
      expect(emberTheme.colorScheme.secondary, EmberColors.coolGlow);
      expect(emberTheme.colorScheme.tertiary, EmberColors.eco);
    });

    test('text theme exposes the three spec Material roles', () {
      // Per docs/PRD.md §4.3, the four spec styles are displayLarge,
      // bodyMedium, labelSmall (Material roles) plus bodyMediumItalic
      // (non-Material). bodyMediumItalic lives on EmberTypography directly.
      expect(emberTheme.textTheme.displayLarge, isNotNull);
      expect(emberTheme.textTheme.bodyMedium, isNotNull);
      expect(emberTheme.textTheme.labelSmall, isNotNull);
    });

    test('app bar matches edge-to-edge dark intent', () {
      expect(emberTheme.appBarTheme.backgroundColor, Colors.transparent);
      expect(emberTheme.appBarTheme.foregroundColor, EmberColors.textPrimary);
      expect(emberTheme.appBarTheme.elevation, 0);
    });
  });
}
