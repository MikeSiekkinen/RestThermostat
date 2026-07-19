import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Color treatment for the schedule Edit Event time-entry boxes. Shipped as a
/// runtime-selectable A/B so the look can be evaluated on-device without a
/// rebuild (see Settings → Appearance).
///
/// - [matchMode]: boxes echo the event's mode tint (cool → blue, heat →
///   orange, range → neutral), consistent with the mode pill and event rows.
/// - [neutral]: boxes stay a mode-agnostic gray and the cursor is de-warmed,
///   so nothing in the time section reads as heat.
enum TimeFieldPalette { matchMode, neutral }

/// Persists the chosen [TimeFieldPalette] in SharedPreferences and exposes it
/// to the widget tree. Hydrates asynchronously on first build; until the stored
/// value loads, the default ([TimeFieldPalette.matchMode]) is used — a brief
/// cold-start flash that's acceptable for a dev-eval toggle.
class TimeFieldPaletteNotifier extends Notifier<TimeFieldPalette> {
  static const _key = 'timeFieldPalette';

  @override
  TimeFieldPalette build() {
    _hydrate();
    return TimeFieldPalette.matchMode;
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final restored = TimeFieldPalette.values
        .where((p) => p.name == raw)
        .firstOrNull;
    if (restored != null && restored != state) state = restored;
  }

  Future<void> set(TimeFieldPalette palette) async {
    state = palette;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, palette.name);
  }
}

final timeFieldPaletteProvider =
    NotifierProvider<TimeFieldPaletteNotifier, TimeFieldPalette>(
      TimeFieldPaletteNotifier.new,
    );
