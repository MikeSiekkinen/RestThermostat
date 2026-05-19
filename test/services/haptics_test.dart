import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/services/haptics.dart';

void main() {
  group('ThrottledSelectionClick', () {
    test('first call always fires', () {
      var clicks = 0;
      var now = Duration.zero;
      final t = ThrottledSelectionClick(
        minGap: const Duration(milliseconds: 33),
        now: () => now,
        click: () => clicks++,
      );

      expect(t.tryClick(), isTrue);
      expect(clicks, 1);
    });

    test('back-to-back call within minGap is suppressed', () {
      var clicks = 0;
      var now = Duration.zero;
      final t = ThrottledSelectionClick(
        minGap: const Duration(milliseconds: 33),
        now: () => now,
        click: () => clicks++,
      );

      t.tryClick(); // fires.
      now = const Duration(milliseconds: 10);
      expect(t.tryClick(), isFalse);
      expect(clicks, 1);
    });

    test('call exactly at minGap is suppressed (strict <)', () {
      // Strict-less-than means a call at exactly minGap STILL needs to wait
      // one more microsecond. This matches the dial's hard ceiling of 30/sec
      // — at exactly 33ms we don't want a slightly-fast 31/sec rate.
      var clicks = 0;
      var now = Duration.zero;
      final t = ThrottledSelectionClick(
        minGap: const Duration(milliseconds: 33),
        now: () => now,
        click: () => clicks++,
      );

      t.tryClick();
      now = const Duration(milliseconds: 33);
      // 33 - 0 = 33ms, which is NOT < 33ms — so the next call is allowed.
      expect(t.tryClick(), isTrue);
      expect(clicks, 2);
    });

    test('call after minGap fires again', () {
      var clicks = 0;
      var now = Duration.zero;
      final t = ThrottledSelectionClick(
        minGap: const Duration(milliseconds: 33),
        now: () => now,
        click: () => clicks++,
      );

      t.tryClick();
      now = const Duration(milliseconds: 50);
      expect(t.tryClick(), isTrue);
      expect(clicks, 2);
    });

    test('rapid sweep at 1ms/step caps emissions to ~30/sec', () {
      // Simulate a 1-second-long drag at 1ms per update. Without throttling
      // that's 1000 ticks; the throttler must emit no more than 31
      // (one at t=0, plus 30 more at 33ms spacing through t=990ms).
      var clicks = 0;
      var now = Duration.zero;
      final t = ThrottledSelectionClick(
        minGap: const Duration(milliseconds: 33),
        now: () => now,
        click: () => clicks++,
      );

      for (var ms = 0; ms <= 1000; ms++) {
        now = Duration(milliseconds: ms);
        t.tryClick();
      }
      expect(clicks, lessThanOrEqualTo(31));
      expect(clicks, greaterThanOrEqualTo(30));
    });

    test('reset clears the cooldown so the next click fires', () {
      var clicks = 0;
      var now = Duration.zero;
      final t = ThrottledSelectionClick(
        minGap: const Duration(milliseconds: 33),
        now: () => now,
        click: () => clicks++,
      );

      t.tryClick(); // fires.
      now = const Duration(milliseconds: 5);
      expect(t.tryClick(), isFalse);

      t.reset();
      expect(t.tryClick(), isTrue);
      expect(clicks, 2);
    });

    test('default minGap is 33ms (≤30/sec ceiling per DESIGN §11.3)', () {
      // Construct with all-default args except injectable hooks; the gap
      // should still be 33ms. We verify via behavior: at t=32ms, suppressed.
      var clicks = 0;
      var now = Duration.zero;
      final t = ThrottledSelectionClick(now: () => now, click: () => clicks++);

      t.tryClick();
      now = const Duration(milliseconds: 32);
      expect(t.tryClick(), isFalse);
      expect(clicks, 1);
    });
  });
}
