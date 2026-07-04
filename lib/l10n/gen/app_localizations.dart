import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// Application title shown in the home AppBar and OS task switcher.
  ///
  /// In en, this message translates to:
  /// **'Rest Thermostat'**
  String get appTitle;

  /// Title rendered in the home-screen AppBar.
  ///
  /// In en, this message translates to:
  /// **'Rest Thermostat'**
  String get homeAppBarTitle;

  /// Tooltip for the gear/settings IconButton in the home AppBar.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get homeSettingsTooltip;

  /// Body shown when the server returns a successful response with zero devices.
  ///
  /// In en, this message translates to:
  /// **'No devices'**
  String get homeNoDevices;

  /// Body shown when the devices-snapshot stream surfaces an unexpected error.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String homeErrorPrefix(Object error);

  /// SnackBar copy when an auth failure (401/403) is detected anywhere in the app.
  ///
  /// In en, this message translates to:
  /// **'Authentication failed.'**
  String get homeAuthFailed;

  /// SnackBar action button label that deep-links to Settings with the auth section pre-expanded.
  ///
  /// In en, this message translates to:
  /// **'OPEN SETTINGS'**
  String get homeAuthOpenSettingsAction;

  /// One-time SnackBar shown when the persisted active serial isn't in the latest /api/devices response and the source falls back to the first device per DESIGN §4.5.
  ///
  /// In en, this message translates to:
  /// **'Active device changed — it wasn\'t in the latest device list.'**
  String get homeActiveDeviceFallback;

  /// Display name used when a device's server-side name is null or empty AND no local override exists.
  ///
  /// In en, this message translates to:
  /// **'unnamed'**
  String get deviceUnnamedFallback;

  /// Chip rendered on top of the home body when the active device reports is_available=false.
  ///
  /// In en, this message translates to:
  /// **'DEVICE OFFLINE'**
  String get deviceOfflineLabel;

  /// Status-row text when the heater is running.
  ///
  /// In en, this message translates to:
  /// **'Heating'**
  String get statusHeating;

  /// Status-row text when the A/C is running.
  ///
  /// In en, this message translates to:
  /// **'Cooling'**
  String get statusCooling;

  /// Status-row text when only the fan is running.
  ///
  /// In en, this message translates to:
  /// **'Fan only'**
  String get statusFanOnly;

  /// Status-row text when no equipment is running but a heating/cooling mode is selected.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get statusIdle;

  /// Status-row text when the device is off and no fan is running.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get statusOff;

  /// Label for the off mode pill in the home screen.
  ///
  /// In en, this message translates to:
  /// **'OFF'**
  String get modePillOff;

  /// Label for the heat mode pill in the home screen.
  ///
  /// In en, this message translates to:
  /// **'HEAT'**
  String get modePillHeat;

  /// Label for the cool mode pill in the home screen.
  ///
  /// In en, this message translates to:
  /// **'COOL'**
  String get modePillCool;

  /// Label for the heat-cool (auto) mode pill in the home screen.
  ///
  /// In en, this message translates to:
  /// **'AUTO'**
  String get modePillAuto;

  /// Snackbar copy when a set_mode write returns a 4xx without a server-provided message.
  ///
  /// In en, this message translates to:
  /// **'Server rejected mode change'**
  String get modeChangeServerRejected;

  /// Generic snackbar copy when a set_mode write fails for non-4xx reasons.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t change mode'**
  String get modeChangeFailed;

  /// Visible label below the fan widget when the fan is in auto mode.
  ///
  /// In en, this message translates to:
  /// **'FAN AUTO'**
  String get fanLabelAuto;

  /// Visible label below the fan widget when the timer is active. Countdown is pre-formatted M:SS.
  ///
  /// In en, this message translates to:
  /// **'FAN ON • {countdown}'**
  String fanLabelOn(String countdown);

  /// TalkBack/VoiceOver announcement for the fan widget when in auto mode.
  ///
  /// In en, this message translates to:
  /// **'Fan auto, tap to turn on'**
  String get fanSemanticAuto;

  /// Screen-reader announcement for the fan widget when the timer is active.
  ///
  /// In en, this message translates to:
  /// **'Fan on for {countdown}, tap to switch to auto'**
  String fanSemanticOn(String countdown);

  /// Snackbar copy when a set_fan write returns a 4xx without a server message.
  ///
  /// In en, this message translates to:
  /// **'Server rejected fan command'**
  String get fanChangeServerRejected;

  /// Generic snackbar copy when a set_fan write fails for non-4xx reasons.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t change fan'**
  String get fanChangeFailed;

  /// Header inside the fan-duration bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'RUN FAN FOR'**
  String get fanDurationSheetTitle;

  /// Fan duration choice for less than an hour, e.g. 15 MINUTES.
  ///
  /// In en, this message translates to:
  /// **'{minutes} MINUTES'**
  String fanDurationMinutes(int minutes);

  /// Fan duration choice for exactly 1 hour (singular).
  ///
  /// In en, this message translates to:
  /// **'1 HOUR'**
  String get fanDuration1Hour;

  /// Fan duration choice for 2+ hours.
  ///
  /// In en, this message translates to:
  /// **'{hours} HOURS'**
  String fanDurationHours(int hours);

  /// Text inside the AWAY chip when the device is in away/eco mode.
  ///
  /// In en, this message translates to:
  /// **'AWAY'**
  String get awayChipLabel;

  /// Screen-reader announcement when the AWAY chip is active.
  ///
  /// In en, this message translates to:
  /// **'Away mode on, tap to disable. Long press to edit eco temperatures.'**
  String get awaySemanticOn;

  /// Screen-reader announcement when the AWAY chip is inactive.
  ///
  /// In en, this message translates to:
  /// **'Away mode off, tap to enable. Long press to edit eco temperatures.'**
  String get awaySemanticOff;

  /// Generic snackbar copy when set_away fails for non-4xx reasons.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t toggle away'**
  String get awayToggleFailed;

  /// Snackbar copy when set_away returns a 4xx without a server message.
  ///
  /// In en, this message translates to:
  /// **'Server rejected away change'**
  String get awayToggleServerRejected;

  /// Generic snackbar copy when set_eco_temperatures fails for non-4xx reasons.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save eco temperatures'**
  String get awayEcoSaveFailed;

  /// Snackbar copy when set_eco_temperatures returns a 4xx without a server message.
  ///
  /// In en, this message translates to:
  /// **'Server rejected eco temps change'**
  String get awayEcoSaveServerRejected;

  /// Header inside the eco-temperatures bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'ECO TEMPERATURES'**
  String get ecoSheetTitle;

  /// Slider label for the eco low/heat setpoint.
  ///
  /// In en, this message translates to:
  /// **'LOW (HEAT)'**
  String get ecoSheetLowLabel;

  /// Slider label for the eco high/cool setpoint.
  ///
  /// In en, this message translates to:
  /// **'HIGH (COOL)'**
  String get ecoSheetHighLabel;

  /// Inline error when the user sets low ≥ high.
  ///
  /// In en, this message translates to:
  /// **'Low must be lower than high.'**
  String get ecoSheetValidationLowHigh;

  /// Cancel button in the eco-temperatures bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'CANCEL'**
  String get ecoSheetCancel;

  /// Save button in the eco-temperatures bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get ecoSheetSave;

  /// Snackbar copy when a set_temperature write fails outright.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update temperature'**
  String get dialTemperatureFailed;

  /// Snackbar copy when set_temperature succeeds but no reconciliation match arrives within 7s.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t confirm new temperature'**
  String get dialTemperatureNotConfirmed;

  /// Action label on dial-failure snackbars that re-issues the write.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get dialRetry;

  /// Retry button in the home-screen stale-state pill.
  ///
  /// In en, this message translates to:
  /// **'RETRY'**
  String get stalePillRetry;

  /// Pill copy during an active reconnection attempt after a poll failure.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get stalePillReconnecting;

  /// Pill copy when polling is paused due to a 429 rate-limit.
  ///
  /// In en, this message translates to:
  /// **'Server busy — retrying'**
  String get stalePillRateLimited;

  /// Pill copy when no successful poll has happened yet and the source is failing.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get stalePillNotConnected;

  /// Pill copy when stale with a known prior successful poll.
  ///
  /// In en, this message translates to:
  /// **'Last updated {elapsed}'**
  String stalePillLastUpdated(String elapsed);

  /// Elapsed bucket inserted into stalePillLastUpdated when <60s have passed.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get stalePillElapsedJustNow;

  /// Elapsed bucket for 60–119s.
  ///
  /// In en, this message translates to:
  /// **'1 min ago'**
  String get stalePillElapsedOneMinute;

  /// Elapsed bucket for 2–59 minutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min ago'**
  String stalePillElapsedMinutes(int minutes);

  /// Elapsed bucket for 60–119 minutes.
  ///
  /// In en, this message translates to:
  /// **'1 hour ago'**
  String get stalePillElapsedOneHour;

  /// Elapsed bucket for 2+ hours.
  ///
  /// In en, this message translates to:
  /// **'{hours} hours ago'**
  String stalePillElapsedHours(int hours);

  /// Welcome-screen headline.
  ///
  /// In en, this message translates to:
  /// **'Rest Thermostat'**
  String get welcomeTitle;

  /// Welcome-screen body paragraph.
  ///
  /// In en, this message translates to:
  /// **'Connect to your NoLongerEvil server to control your Gen 1/2 Nest thermostats.'**
  String get welcomeBody;

  /// Selectable docs link rendered under the welcome body.
  ///
  /// In en, this message translates to:
  /// **'Docs: {url}'**
  String welcomeDocsLink(String url);

  /// Welcome-screen primary CTA.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get welcomeStartButton;

  /// AppBar title on the Server Setup screen.
  ///
  /// In en, this message translates to:
  /// **'Server Setup'**
  String get serverSetupTitle;

  /// Text field label for the NLE server URL.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get serverAddressLabel;

  /// Hint text shown inside the empty server-address field.
  ///
  /// In en, this message translates to:
  /// **'nest.home or 192.168.1.42'**
  String get serverAddressHint;

  /// Inline validation error when the server-address field is empty.
  ///
  /// In en, this message translates to:
  /// **'Server address is required.'**
  String get serverAddressRequired;

  /// Expander title that reveals the authentication picker.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get advancedSectionTitle;

  /// Dropdown label for the authentication type.
  ///
  /// In en, this message translates to:
  /// **'Authentication'**
  String get authChoiceLabel;

  /// Dropdown option: no authentication (default).
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get authChoiceNone;

  /// Dropdown option: HTTP Basic authentication.
  ///
  /// In en, this message translates to:
  /// **'Basic'**
  String get authChoiceBasic;

  /// Dropdown option: Bearer-token authentication.
  ///
  /// In en, this message translates to:
  /// **'Bearer'**
  String get authChoiceBearer;

  /// Username text field label (HTTP Basic auth).
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get authUsernameLabel;

  /// Password text field label (HTTP Basic auth).
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPasswordLabel;

  /// Visibility-toggle tooltip when the password field is obscured.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get authPasswordShow;

  /// Visibility-toggle tooltip when the password field is visible.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get authPasswordHide;

  /// Bearer-token text field label.
  ///
  /// In en, this message translates to:
  /// **'Token'**
  String get authTokenLabel;

  /// Visibility-toggle tooltip when the bearer-token field is obscured.
  ///
  /// In en, this message translates to:
  /// **'Show token'**
  String get authTokenShow;

  /// Visibility-toggle tooltip when the bearer-token field is visible.
  ///
  /// In en, this message translates to:
  /// **'Hide token'**
  String get authTokenHide;

  /// Primary submit button on the Server Setup screen.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connectButton;

  /// Inline error after Test Connection when the server rejected credentials (401/403).
  ///
  /// In en, this message translates to:
  /// **'Authentication failed.'**
  String get connectFailedAuth;

  /// Inline error after Test Connection for any non-auth failure.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach server.'**
  String get connectFailedUnreachable;

  /// AppBar title on the onboarding device-picker screen.
  ///
  /// In en, this message translates to:
  /// **'Choose a thermostat'**
  String get devicePickerTitle;

  /// Blocking copy headline when the server has no devices registered.
  ///
  /// In en, this message translates to:
  /// **'No thermostats registered.'**
  String get noDevicesTitle;

  /// Blocking copy body when the server has no devices registered.
  ///
  /// In en, this message translates to:
  /// **'Pair your Nest Gen 1/2 with your NoLongerEvil server before continuing.'**
  String get noDevicesBody;

  /// Button on the no-devices screen that returns to Server Setup.
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get noDevicesGoBack;

  /// Header inside the home-screen device-picker bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devicePickerSheetHeader;

  /// AppBar title on the Settings screen.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Settings section header for the URL+auth re-edit form.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get settingsConnectionSection;

  /// Outlined button that triggers a test fetch against the entered URL.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get settingsTestConnection;

  /// Filled button that persists the URL+auth after a successful test.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get settingsSave;

  /// Generic Cancel button label used in Settings dialogs.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get settingsCancel;

  /// Confirmation snackbar after Save succeeds.
  ///
  /// In en, this message translates to:
  /// **'Connection settings saved.'**
  String get settingsConnectionSaved;

  /// Inline success message after Test Connection. Uses ICU plural for device count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Connected — 1 device found.} other{Connected — {count} devices found.}}'**
  String settingsTestSuccess(int count);

  /// Settings section header for the per-device rename list.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get settingsDevicesSection;

  /// Inline error when the Settings Devices section can't fetch /api/devices.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load devices: {error}'**
  String settingsDevicesLoadError(Object error);

  /// Placeholder shown when /api/devices returns an empty list inside the Settings Devices section.
  ///
  /// In en, this message translates to:
  /// **'No devices.'**
  String get settingsNoDevices;

  /// Settings section header for the diagnostics row that opens the logs screen.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get settingsDiagnosticsSection;

  /// ListTile title that opens the diagnostic logs screen.
  ///
  /// In en, this message translates to:
  /// **'View logs'**
  String get settingsViewLogs;

  /// ListTile subtitle for the View logs row.
  ///
  /// In en, this message translates to:
  /// **'In-memory diagnostic log of recent app activity.'**
  String get settingsViewLogsSubtitle;

  /// Settings section header for the About/version/credit block.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAboutSection;

  /// Version + build line in the About section.
  ///
  /// In en, this message translates to:
  /// **'Rest Thermostat {version} (build {buildNumber})'**
  String settingsAboutVersion(String version, String buildNumber);

  /// Single-line credit to the NLE project, rendered under the version.
  ///
  /// In en, this message translates to:
  /// **'For Cody Kociemba\'s NoLongerEvil project'**
  String get settingsAboutCredit;

  /// Docs URL line in the About section.
  ///
  /// In en, this message translates to:
  /// **'NLE docs: {url}'**
  String settingsAboutDocsLink(String url);

  /// Source-repo URL line in the About section.
  ///
  /// In en, this message translates to:
  /// **'Source: {url}'**
  String settingsAboutSourceLink(String url);

  /// Section header above the Disconnect button.
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get settingsDangerZoneSection;

  /// Destructive button that wipes the saved config + cache + secure storage.
  ///
  /// In en, this message translates to:
  /// **'Disconnect from server'**
  String get settingsDisconnect;

  /// Title of the confirm-disconnect dialog.
  ///
  /// In en, this message translates to:
  /// **'Disconnect from server?'**
  String get settingsDisconnectDialogTitle;

  /// Body of the confirm-disconnect dialog.
  ///
  /// In en, this message translates to:
  /// **'This will remove your server settings and saved credentials. Continue?'**
  String get settingsDisconnectDialogBody;

  /// Destructive action label inside the confirm-disconnect dialog.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get settingsDisconnectConfirm;

  /// Title of the per-device rename dialog.
  ///
  /// In en, this message translates to:
  /// **'Rename thermostat'**
  String get settingsRenameDialogTitle;

  /// Text-field label for the new display name.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get settingsRenameDisplayLabel;

  /// Helper text under the rename field; empty = clear the override.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use the server name'**
  String get settingsRenameHelp;

  /// AppBar title on the Schedule screen.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get scheduleTitle;

  /// Tooltip on the AppBar + IconButton that opens the new-event editor.
  ///
  /// In en, this message translates to:
  /// **'Add event'**
  String get scheduleAddEventTooltip;

  /// Empty-state title shown for a day with no events.
  ///
  /// In en, this message translates to:
  /// **'No events scheduled'**
  String get scheduleEmptyTitle;

  /// Empty-state subtitle hinting at the + button.
  ///
  /// In en, this message translates to:
  /// **'Tap + to add one'**
  String get scheduleEmptyHint;

  /// Body shown when /api/schedule fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load schedule: {error}'**
  String scheduleLoadError(Object error);

  /// Type label rendered on schedule event rows for HEAT events.
  ///
  /// In en, this message translates to:
  /// **'HEAT'**
  String get scheduleEventTypeHeat;

  /// Type label rendered on schedule event rows for COOL events.
  ///
  /// In en, this message translates to:
  /// **'COOL'**
  String get scheduleEventTypeCool;

  /// Type label rendered on schedule event rows for RANGE/auto events.
  ///
  /// In en, this message translates to:
  /// **'RANGE'**
  String get scheduleEventTypeRange;

  /// Merged Semantics label TalkBack/VoiceOver reads for each schedule event row.
  ///
  /// In en, this message translates to:
  /// **'Event at {time}, {temp} {modeLower}, tap to edit.'**
  String scheduleEventSemanticLabel(String time, String temp, String modeLower);

  /// AppBar title when creating a new schedule event.
  ///
  /// In en, this message translates to:
  /// **'New Event'**
  String get editEventTitleNew;

  /// AppBar title when editing an existing schedule event.
  ///
  /// In en, this message translates to:
  /// **'Edit Event'**
  String get editEventTitleEdit;

  /// AppBar leading button on the edit-event screen.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get editEventCancel;

  /// AppBar trailing button that submits the edit-event form.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get editEventSave;

  /// Section header above the time picker.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get editEventTimeLabel;

  /// Section header above the repeat-days row (new-event mode only).
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get editEventRepeatLabel;

  /// Destructive button at the bottom of the edit-event screen (edit-mode only).
  ///
  /// In en, this message translates to:
  /// **'Delete Event'**
  String get editEventDeleteButton;

  /// Title of the delete-event confirm dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete event?'**
  String get editEventDeleteDialogTitle;

  /// Body of the delete-event confirm dialog.
  ///
  /// In en, this message translates to:
  /// **'This will remove the event from this day.'**
  String get editEventDeleteDialogBody;

  /// Destructive action label inside the delete-event confirm dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get editEventDeleteConfirm;

  /// Snackbar shown after a successful set_schedule write.
  ///
  /// In en, this message translates to:
  /// **'Schedule saved'**
  String get editEventSavedSnack;

  /// Snackbar shown when set_schedule fails — pairs with the Retry action.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save schedule. Retry?'**
  String get editEventSaveFailedSnack;

  /// Action button on the save-failed snackbar that re-issues set_schedule.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get editEventRetryAction;

  /// Section header above the current humidity + setpoint tiles on the Details tab.
  ///
  /// In en, this message translates to:
  /// **'CURRENT'**
  String get detailsSectionCurrent;

  /// Section header above the system-info rows on the Details tab.
  ///
  /// In en, this message translates to:
  /// **'SYSTEM'**
  String get detailsSectionSystem;

  /// Label for the humidity stat tile.
  ///
  /// In en, this message translates to:
  /// **'HUMIDITY'**
  String get detailsHumidity;

  /// Label for the setpoint stat tile.
  ///
  /// In en, this message translates to:
  /// **'SETPOINT'**
  String get detailsSetpoint;

  /// Long-press tooltip body explaining the (Derived) suffix.
  ///
  /// In en, this message translates to:
  /// **'Source is derived locally from schedule + away state. (Derived)'**
  String get detailsSetpointSourceTooltip;

  /// Comfort-label subtitle on the humidity tile when humidity < 30%.
  ///
  /// In en, this message translates to:
  /// **'Dry'**
  String get detailsComfortDry;

  /// Comfort-label subtitle when 30–50% humidity.
  ///
  /// In en, this message translates to:
  /// **'Comfortable'**
  String get detailsComfortComfortable;

  /// Comfort-label subtitle when humidity > 50%.
  ///
  /// In en, this message translates to:
  /// **'Humid'**
  String get detailsComfortHumid;

  /// Setpoint-source subtitle when the device is in eco/away mode.
  ///
  /// In en, this message translates to:
  /// **'Away'**
  String get detailsSetpointSourceAway;

  /// Setpoint-source subtitle when the target matches the active scheduled event.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get detailsSetpointSourceScheduled;

  /// Setpoint-source subtitle when the target doesn't match any other source.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get detailsSetpointSourceManual;

  /// Row label for the device connectivity status.
  ///
  /// In en, this message translates to:
  /// **'STATUS'**
  String get detailsStatus;

  /// Row value when device.isAvailable is true.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get detailsStatusConnected;

  /// Row value when device.isAvailable is false.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get detailsStatusOffline;

  /// Row label for the server URL.
  ///
  /// In en, this message translates to:
  /// **'SERVER'**
  String get detailsServer;

  /// Row label for the NLE firmware version.
  ///
  /// In en, this message translates to:
  /// **'FIRMWARE'**
  String get detailsFirmware;

  /// Row label for the thermostat's LAN IP address. Row is hidden when the server doesn't report one (pre-2026-06-29 NLE servers).
  ///
  /// In en, this message translates to:
  /// **'LOCAL IP'**
  String get detailsLocalIp;

  /// Row label for the thermostat's MAC address. Row is hidden when the server doesn't report one (pre-2026-06-29 NLE servers).
  ///
  /// In en, this message translates to:
  /// **'MAC ADDRESS'**
  String get detailsMacAddress;

  /// Row label for the last-successful-poll timestamp.
  ///
  /// In en, this message translates to:
  /// **'LAST SYNC'**
  String get detailsLastSync;

  /// Placeholder em-dash for empty fields in the system-info section.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get detailsLastSyncEmpty;

  /// Tooltip when no successful poll has happened yet.
  ///
  /// In en, this message translates to:
  /// **'No successful poll yet'**
  String get detailsLastSyncNoPoll;

  /// Relative-time bucket: < 5 seconds.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get detailsLastSyncJustNow;

  /// Relative-time bucket: 5–59 seconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds} seconds ago'**
  String detailsLastSyncSeconds(int seconds);

  /// Relative-time bucket: exactly 1 minute.
  ///
  /// In en, this message translates to:
  /// **'1 minute ago'**
  String get detailsLastSyncOneMinute;

  /// Relative-time bucket: 2–59 minutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} minutes ago'**
  String detailsLastSyncMinutes(int minutes);

  /// Relative-time bucket: exactly 1 hour.
  ///
  /// In en, this message translates to:
  /// **'1 hour ago'**
  String get detailsLastSyncOneHour;

  /// Relative-time bucket: 2–23 hours.
  ///
  /// In en, this message translates to:
  /// **'{hours} hours ago'**
  String detailsLastSyncHours(int hours);

  /// Relative-time bucket: exactly 1 day.
  ///
  /// In en, this message translates to:
  /// **'1 day ago'**
  String get detailsLastSyncOneDay;

  /// Relative-time bucket: 2+ days.
  ///
  /// In en, this message translates to:
  /// **'{days} days ago'**
  String detailsLastSyncDays(int days);

  /// AppBar title on the diagnostic logs screen.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic logs'**
  String get logsTitle;

  /// Tooltip for the Copy IconButton in the logs AppBar.
  ///
  /// In en, this message translates to:
  /// **'Copy to clipboard'**
  String get logsCopyTooltip;

  /// Tooltip for the Share IconButton in the logs AppBar.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get logsShareTooltip;

  /// Tooltip for the Clear IconButton in the logs AppBar.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get logsClearTooltip;

  /// Snackbar shown after copying logs to clipboard succeeds.
  ///
  /// In en, this message translates to:
  /// **'Logs copied to clipboard.'**
  String get logsCopiedSnack;

  /// Title of the confirm-clear-logs dialog.
  ///
  /// In en, this message translates to:
  /// **'Clear logs?'**
  String get logsClearDialogTitle;

  /// Body of the confirm-clear-logs dialog.
  ///
  /// In en, this message translates to:
  /// **'This removes all in-memory log entries. The buffer will start fresh from the next event.'**
  String get logsClearDialogBody;

  /// Destructive action label inside the confirm-clear-logs dialog.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get logsClearConfirm;

  /// Cancel button in the clear-logs dialog.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get logsCancel;

  /// Center placeholder when the log buffer is empty.
  ///
  /// In en, this message translates to:
  /// **'No log entries yet.'**
  String get logsEmpty;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
