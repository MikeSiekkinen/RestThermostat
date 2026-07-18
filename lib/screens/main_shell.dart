import 'package:flutter/material.dart';

import '../models/device.dart';
import '../theme/colors.dart';
import 'details/details_screen.dart';
import 'schedule/schedule_screen.dart';

/// Three-tab home shell per `docs/PRD.md` §5.2 + the bottom-nav addition
/// from issue #16: Home, Schedule, Details.
///
/// All three tabs read from the same [device] resolved by the parent — the
/// shell doesn't watch the snapshot itself, so the active-serial scope
/// lives one level up. The shell is presentation-only: each tab body is
/// kept alive across switches via [IndexedStack] so animation state (the
/// dial tween, the status-row pulse, the fan ripple) survives switching
/// away and back.
///
/// Icons are intentionally generic geometric shapes to stay clear of any
/// thermostat-derivative iconography (DESIGN §1).
class MainShell extends StatefulWidget {
  /// The currently-active device, resolved by the parent.
  final Device device;

  /// Per-device display-name overrides forwarded to the Home tab.
  final Map<String, String> overrides;

  /// Last successful poll timestamp forwarded to the Details tab.
  final DateTime? lastSyncAt;

  /// The Home tab's content. Passed in by the parent so the shell stays
  /// presentation-only and doesn't have to know about Riverpod-watched
  /// providers.
  final Widget homeTab;

  /// `now()` injection for time-dependent tab logic: the Details tab's
  /// relative-time formatting and the Schedule tab's setpoint-source
  /// derivation for the in-control event highlight (Issue #97).
  final DateTime Function() now;

  const MainShell({
    super.key,
    required this.device,
    required this.overrides,
    required this.lastSyncAt,
    required this.homeTab,
    this.now = DateTime.now,
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
        children: [
          widget.homeTab,
          ScheduleScreen(
            serial: widget.device.serial,
            temperatureScale: widget.device.temperatureScale,
            deviceMode: widget.device.mode,
            scheduleMode: widget.device.scheduleMode,
            capabilities: widget.device.capabilities,
            device: widget.device,
            now: widget.now,
          ),
          DetailsScreen(
            device: widget.device,
            lastSyncAt: widget.lastSyncAt,
            now: widget.now,
          ),
        ],
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
