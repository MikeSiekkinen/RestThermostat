import 'package:flutter/material.dart';

import '../models/device.dart';
import '../theme/colors.dart';

/// Three-tab home shell per `docs/PRD.md` §5.2 + the bottom-nav addition
/// from issue #16: Home, Schedule, Details.
///
/// The shell is presentation-only: each tab body is built by the parent and
/// passed in, so the shell doesn't have to know about Riverpod-watched
/// providers or the device list. Tab bodies are kept alive across switches
/// via [IndexedStack] so animation state (the dial tween, the status-row
/// pulse, the fan ripple) — and each tab's device-swipe `PageView` position
/// (Issue #125) — survives switching away and back. The single active
/// [device] is still forwarded, but only to tint the bottom nav.
///
/// Icons are intentionally generic geometric shapes to stay clear of any
/// thermostat-derivative iconography (DESIGN §1).
class MainShell extends StatefulWidget {
  /// The currently-active device, resolved by the parent. Used only to tint
  /// the bottom navigation bar in the active device's mode color.
  final Device device;

  /// The Home tab's content. Passed in by the parent so the shell stays
  /// presentation-only and doesn't have to know about Riverpod-watched
  /// providers. Wraps a device-swipe `PageView` when 2+ devices are present.
  final Widget homeTab;

  /// The Schedule tab's content, built by the parent. Like [homeTab], wraps a
  /// device-swipe `PageView` when 2+ devices are present (Issue #125).
  final Widget scheduleTab;

  /// The Details tab's content, built by the parent. Like [homeTab], wraps a
  /// device-swipe `PageView` when 2+ devices are present (Issue #125).
  final Widget detailsTab;

  const MainShell({
    super.key,
    required this.device,
    required this.homeTab,
    required this.scheduleTab,
    required this.detailsTab,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  Color _accentFor(DeviceMode mode) => switch (mode) {
    DeviceMode.heat || DeviceMode.emergency => EmberColors.heatGlow,
    DeviceMode.cool => EmberColors.coolGlow,
    DeviceMode.heatCool || DeviceMode.off => EmberColors.textPrimary,
  };

  @override
  Widget build(BuildContext context) {
    final accent = _accentFor(widget.device.mode);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: IndexedStack(
        index: _index,
        children: [widget.homeTab, widget.scheduleTab, widget.detailsTab],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Colors.black.withValues(alpha: 0.4),
          indicatorColor: accent.withValues(alpha: 0.16),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.5,
              color: selected ? accent : EmberColors.textTertiary,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selected ? accent : EmberColors.textTertiary,
              size: 22,
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.circle_outlined),
              selectedIcon: Icon(Icons.circle),
              label: 'HOME',
            ),
            NavigationDestination(
              icon: Icon(Icons.calendar_today_outlined),
              selectedIcon: Icon(Icons.calendar_today),
              label: 'SCHEDULE',
            ),
            NavigationDestination(
              icon: Icon(Icons.list_alt_outlined),
              selectedIcon: Icon(Icons.list_alt),
              label: 'DETAILS',
            ),
          ],
        ),
      ),
    );
  }
}
