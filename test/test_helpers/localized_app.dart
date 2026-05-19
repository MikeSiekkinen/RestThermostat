import 'package:flutter/material.dart';
import 'package:rest_thermostat/l10n/gen/app_localizations.dart';

/// Build a [MaterialApp] pre-wired with the AppLocalizations delegates so
/// widget tests can call `AppLocalizations.of(context)` without the runtime
/// throwing.
///
/// Pass [child] in either `home:` form (use [LocalizedMaterialApp]) or wrap
/// existing test scaffolding via the [withL10n] helper.
MaterialApp localizedApp({required Widget home, Locale? locale}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}
