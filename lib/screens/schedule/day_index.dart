/// Helpers for translating between the app's internal day index (Monday=0..
/// Sunday=6 per `docs/DESIGN.md` §6.1) and the locale-aware display order
/// (Mon-first vs Sun-first per §15.4).
///
/// The model is *always* Monday=0. The UI rotates that into the user's locale
/// at the boundary — never the other way around. Internal indexes never leak
/// into UI state and locale-relative indexes never leak back into the model.
library;

import 'dart:ui';

/// Returns the seven day indexes (Monday=0..Sunday=6) in the order they
/// should be displayed for [locale]. Sun-first locales — currently just `en_US`
/// and a handful of other Americas locales by Unicode CLDR — get
/// `[6, 0, 1, 2, 3, 4, 5]`. Everywhere else gets `[0, 1, 2, 3, 4, 5, 6]`.
///
/// We intentionally don't pull `package:intl` for this — the rule is short
/// and the dependency would be the only consumer.
List<int> localeDayOrder(Locale locale) {
  return isSundayFirst(locale)
      ? const [6, 0, 1, 2, 3, 4, 5]
      : const [0, 1, 2, 3, 4, 5, 6];
}

/// `true` when the user's locale conventionally displays Sunday as the first
/// day of the week. Conservative set — when in doubt, default to Mon-first.
bool isSundayFirst(Locale locale) {
  // Match by country code where present; otherwise by language. The set below
  // is the common CLDR "firstDay = sun" countries.
  const sundayFirstCountries = <String>{
    'US',
    'CA',
    'MX',
    'BR',
    'CO',
    'PE',
    'IL',
    'JP',
    'KR',
    'TW',
    'PH',
    'ZA',
  };
  final country = locale.countryCode;
  if (country != null) {
    return sundayFirstCountries.contains(country.toUpperCase());
  }
  // No country code: a few languages default to Sun-first regardless of region.
  const sundayFirstLanguages = <String>{'en'};
  return sundayFirstLanguages.contains(locale.languageCode);
}

/// Map `DateTime.weekday` (Mon=1..Sun=7) to the app's internal index
/// (Mon=0..Sun=6).
int weekdayToIndex(int dartWeekday) => dartWeekday - 1;

/// Single-letter labels in internal order — `displayDayLabels` rotates these
/// to locale order. Sunday and Saturday are both `'S'`; that's intentional —
/// the tab strip is narrow enough that it relies on position for disambiguation.
const List<String> _internalLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// Returns the seven single-letter labels in the display order for [locale].
List<String> displayDayLabels(Locale locale) {
  return [for (final i in localeDayOrder(locale)) _internalLabels[i]];
}

/// Full English day name for accessibility / tooltip use. Indexed by the
/// internal day index (Mon=0..Sun=6).
const List<String> fullDayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
