import 'package:flutter/material.dart';
import 'package:rest_thermostat/l10n/gen/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rest_thermostat/widgets/device_offline_overlay.dart';

void main() {
  testWidgets('passes through when offline=false', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DeviceOfflineOverlay(
            offline: false,
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('TAP ME'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('DEVICE OFFLINE'), findsNothing);
    await tester.tap(find.text('TAP ME'));
    expect(taps, 1);
  });

  testWidgets('renders DEVICE OFFLINE label when offline=true', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DeviceOfflineOverlay(
            offline: true,
            child: const Text('cached content'),
          ),
        ),
      ),
    );

    expect(find.text('DEVICE OFFLINE'), findsOneWidget);
    // Cached content is still in the tree (visible at reduced opacity).
    expect(find.text('cached content'), findsOneWidget);
  });

  testWidgets('blocks pointer events when offline=true', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DeviceOfflineOverlay(
            offline: true,
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('TAP ME'),
            ),
          ),
        ),
      ),
    );

    // The text is laid out but inside an AbsorbPointer — tapping the
    // (semi-visible) button should not fire its callback.
    await tester.tap(find.text('TAP ME'), warnIfMissed: false);
    await tester.pump();
    expect(taps, 0);
  });
}
