import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/state/auth_failure_coordinator.dart';

void main() {
  test('fire() notifies listeners on first call', () {
    final c = AuthFailureCoordinator();
    var n = 0;
    c.addListener(() => n++);

    c.fire();
    expect(n, 1);
  });

  test('subsequent fires within throttle window are dropped', () {
    var now = DateTime.utc(2026, 5, 19, 12, 0, 0);
    final c = AuthFailureCoordinator(clock: () => now);
    var n = 0;
    c.addListener(() => n++);

    c.fire();
    expect(n, 1);
    now = now.add(const Duration(seconds: 10));
    c.fire();
    expect(n, 1, reason: 'inside 30s throttle');
    now = now.add(const Duration(seconds: 25));
    c.fire();
    expect(n, 2, reason: 'past 30s throttle');
  });

  test('reset() clears the throttle so the next fire goes through', () {
    var now = DateTime.utc(2026, 5, 19, 12, 0, 0);
    final c = AuthFailureCoordinator(clock: () => now);
    var n = 0;
    c.addListener(() => n++);

    c.fire();
    expect(n, 1);
    now = now.add(const Duration(seconds: 1));
    c.reset();
    c.fire();
    expect(n, 2);
  });
}
