import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/services/app_logger.dart';

void main() {
  group('AppLogger', () {
    test('appends entries with the requested level and message', () {
      final logger = AppLogger(capacity: 10);
      logger.info('hello');
      logger.warn('careful');
      logger.error('boom');

      final entries = logger.entries;
      expect(entries, hasLength(3));
      expect(entries[0].level, LogLevel.info);
      expect(entries[0].message, 'hello');
      expect(entries[1].level, LogLevel.warn);
      expect(entries[2].level, LogLevel.error);
    });

    test('stamps each entry with the injected clock', () {
      var t = DateTime.utc(2026, 1, 1, 0, 0, 0);
      final logger = AppLogger(capacity: 10, clock: () => t);
      logger.info('a');
      t = t.add(const Duration(seconds: 5));
      logger.info('b');

      expect(logger.entries[0].timestamp, DateTime.utc(2026, 1, 1, 0, 0, 0));
      expect(logger.entries[1].timestamp, DateTime.utc(2026, 1, 1, 0, 0, 5));
    });

    test('drops the oldest entry when capacity is exceeded', () {
      final logger = AppLogger(capacity: 3);
      logger.info('one');
      logger.info('two');
      logger.info('three');
      logger.info('four');
      logger.info('five');

      final messages = logger.entries.map((e) => e.message).toList();
      expect(messages, ['three', 'four', 'five']);
    });

    test('ring buffer caps at 500 entries by default and drops oldest', () {
      final logger = AppLogger(); // default capacity 500
      for (var i = 0; i < 600; i++) {
        logger.info('entry-$i');
      }
      expect(logger.entries, hasLength(500));
      // Oldest 100 were dropped (entry-0 .. entry-99). Surviving range is
      // entry-100 .. entry-599.
      expect(logger.entries.first.message, 'entry-100');
      expect(logger.entries.last.message, 'entry-599');
    });

    test('notifier emits the current snapshot after each append', () {
      final logger = AppLogger(capacity: 5);
      final snapshots = <List<LogEntry>>[];
      logger.notifier.addListener(() => snapshots.add(logger.notifier.value));

      logger.info('a');
      logger.info('b');

      expect(snapshots, hasLength(2));
      expect(snapshots[0].map((e) => e.message), ['a']);
      expect(snapshots[1].map((e) => e.message), ['a', 'b']);
    });

    test('clear() empties the buffer and notifies', () {
      final logger = AppLogger(capacity: 5);
      logger.info('a');
      logger.info('b');
      expect(logger.entries, hasLength(2));

      var notified = false;
      logger.notifier.addListener(() => notified = true);
      logger.clear();

      expect(logger.entries, isEmpty);
      expect(logger.notifier.value, isEmpty);
      expect(notified, isTrue);
    });

    test('commandIssued() writes an info entry with command name + value, '
        'never the auth credential', () {
      final logger = AppLogger(capacity: 10);
      logger.commandIssued('set_mode', 'heat');

      expect(logger.entries, hasLength(1));
      final entry = logger.entries.first;
      expect(entry.level, LogLevel.info);
      expect(entry.message, 'POST /command set_mode value=heat');
      // Sanity: no synthetic credential strings should appear in this hook.
      expect(entry.message.toLowerCase(), isNot(contains('bearer')));
      expect(entry.message.toLowerCase(), isNot(contains('basic')));
    });
  });
}
