import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Font used for the big numeric displays on the schedule screens (time boxes,
/// temperatures, repeat-day dates). Shipped as a runtime-selectable A/B so the
/// numerals can be evaluated on-device without a rebuild — the top three picks
/// from the numeral study. See Settings → Appearance.
///
/// [oswald] and [anton] are bundled via the pubspec `fonts:` block; [jetBrainsMono]
/// is the family already shipped for code/label text.
enum NumeralFont {
  oswald,
  anton,
  jetBrainsMono;

  /// Human-facing name for the Settings dropdown.
  String get label => switch (this) {
    NumeralFont.oswald => 'Oswald',
    NumeralFont.anton => 'Anton',
    NumeralFont.jetBrainsMono => 'JetBrains Mono',
  };

  /// Family + fixed weight for this face. Merged onto a base display style so
  /// the base's size/color survive; only the family and weight are replaced.
  TextStyle get style => switch (this) {
    NumeralFont.oswald => const TextStyle(
      fontFamily: 'Oswald',
      fontWeight: FontWeight.w600,
    ),
    NumeralFont.anton => const TextStyle(
      fontFamily: 'Anton',
      fontWeight: FontWeight.w400,
    ),
    NumeralFont.jetBrainsMono => GoogleFonts.jetBrainsMono(
      fontWeight: FontWeight.w500,
    ),
  };
}

/// Persists the chosen [NumeralFont] in SharedPreferences and exposes it to the
/// widget tree. Hydrates asynchronously; until the stored value loads the
/// default ([NumeralFont.oswald]) is used.
class NumeralFontNotifier extends Notifier<NumeralFont> {
  static const _key = 'numeralFont';

  @override
  NumeralFont build() {
    _hydrate();
    return NumeralFont.oswald;
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final restored = NumeralFont.values.where((f) => f.name == raw).firstOrNull;
    if (restored != null && restored != state) state = restored;
  }

  Future<void> set(NumeralFont font) async {
    state = font;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, font.name);
  }
}

final numeralFontProvider = NotifierProvider<NumeralFontNotifier, NumeralFont>(
  NumeralFontNotifier.new,
);
