import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/screens/schedule/day_index.dart';

void main() {
  group('weekdayToIndex', () {
    test('maps Dart Mon=1..Sun=7 to internal Mon=0..Sun=6', () {
      expect(weekdayToIndex(DateTime.monday), 0);
      expect(weekdayToIndex(DateTime.tuesday), 1);
      expect(weekdayToIndex(DateTime.wednesday), 2);
      expect(weekdayToIndex(DateTime.thursday), 3);
      expect(weekdayToIndex(DateTime.friday), 4);
      expect(weekdayToIndex(DateTime.saturday), 5);
      expect(weekdayToIndex(DateTime.sunday), 6);
    });
  });

  group('localeDayOrder', () {
    test('en_US is Sunday-first (Sun=6 leads)', () {
      expect(localeDayOrder(const Locale('en', 'US')), [6, 0, 1, 2, 3, 4, 5]);
    });

    test('en_GB is Monday-first', () {
      expect(localeDayOrder(const Locale('en', 'GB')), [0, 1, 2, 3, 4, 5, 6]);
    });

    test('de_DE is Monday-first', () {
      expect(localeDayOrder(const Locale('de', 'DE')), [0, 1, 2, 3, 4, 5, 6]);
    });

    test('ja_JP is Sunday-first', () {
      expect(localeDayOrder(const Locale('ja', 'JP')), [6, 0, 1, 2, 3, 4, 5]);
    });
  });

  group('isSundayFirst', () {
    test(
      'en with no country defaults to Sun-first (matches US convention)',
      () {
        expect(isSundayFirst(const Locale('en')), isTrue);
      },
    );

    test('fr (no country) defaults to Mon-first', () {
      expect(isSundayFirst(const Locale('fr')), isFalse);
    });
  });

  group('displayDayLabels', () {
    test('en_GB returns M T W T F S S in Monday-first order', () {
      expect(displayDayLabels(const Locale('en', 'GB')), [
        'M',
        'T',
        'W',
        'T',
        'F',
        'S',
        'S',
      ]);
    });

    test('en_US returns S M T W T F S in Sunday-first order', () {
      expect(displayDayLabels(const Locale('en', 'US')), [
        'S',
        'M',
        'T',
        'W',
        'T',
        'F',
        'S',
      ]);
    });
  });

  group('fullDayNames', () {
    test('is internal-order: Monday=0..Sunday=6', () {
      expect(fullDayNames[0], 'Monday');
      expect(fullDayNames[6], 'Sunday');
    });
  });
}
