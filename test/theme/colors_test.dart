import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/theme/colors.dart';

void main() {
  group('EmberColors palette', () {
    test('background gradient lists each have 3 stops', () {
      expect(EmberColors.heatBackground, hasLength(3));
      expect(EmberColors.coolBackground, hasLength(3));
      expect(EmberColors.neutralBackground, hasLength(3));
    });

    test('heat palette matches PRD §4.2 spec', () {
      expect(EmberColors.heatBackground[0], const Color(0xFF1A0A1A));
      expect(EmberColors.heatBackground[2], const Color(0xFF000000));
      expect(EmberColors.heatGlow, const Color(0xFFFF6432));
      expect(EmberColors.heatGradient.first, const Color(0xFFFF8A50));
      expect(EmberColors.heatGradient.last, const Color(0xFFFF4516));
    });

    test('cool palette matches PRD §4.2 spec', () {
      expect(EmberColors.coolBackground[0], const Color(0xFF0A1424));
      expect(EmberColors.coolGlow, const Color(0xFF50AAFF));
      expect(EmberColors.coolGradient.first, const Color(0xFF80C8FF));
      expect(EmberColors.coolGradient.last, const Color(0xFF3070D0));
    });

    test('eco accent is the spec green', () {
      expect(EmberColors.eco, const Color(0xFF4ADE80));
    });

    test('text opacity tiers descend monotonically', () {
      final tiers = [
        EmberColors.textPrimary,
        EmberColors.textSecondary,
        EmberColors.textTertiary,
        EmberColors.textDisabled,
      ];
      for (var i = 1; i < tiers.length; i++) {
        expect(
          tiers[i].a,
          lessThan(tiers[i - 1].a),
          reason: 'tier $i should be more transparent than tier ${i - 1}',
        );
      }
    });
  });
}
