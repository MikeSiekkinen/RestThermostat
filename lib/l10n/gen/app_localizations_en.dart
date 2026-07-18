// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Rest Thermostat';

  @override
  String get homeAppBarTitle => 'Rest Thermostat';

  @override
  String get homeSettingsTooltip => 'Settings';

  @override
  String get homeNoDevices => 'No devices';

  @override
  String homeErrorPrefix(Object error) {
    return 'Error: $error';
  }

  @override
  String get homeAuthFailed => 'Authentication failed.';

  @override
  String get homeAuthOpenSettingsAction => 'OPEN SETTINGS';

  @override
  String get homeActiveDeviceFallback =>
      'Active device changed — it wasn\'t in the latest device list.';

  @override
  String get deviceUnnamedFallback => 'unnamed';

  @override
  String get deviceOfflineLabel => 'DEVICE OFFLINE';

  @override
  String get statusHeating => 'Heating';

  @override
  String get statusCooling => 'Cooling';

  @override
  String get statusFanOnly => 'Fan only';

  @override
  String get statusIdle => 'Idle';

  @override
  String get statusOff => 'Off';

  @override
  String get modePillOff => 'OFF';

  @override
  String get modePillHeat => 'HEAT';

  @override
  String get modePillCool => 'COOL';

  @override
  String get modePillAuto => 'AUTO';

  @override
  String get modeChangeServerRejected => 'Server rejected mode change';

  @override
  String get modeChangeFailed => 'Couldn\'t change mode';

  @override
  String get fanLabelAuto => 'FAN AUTO';

  @override
  String fanLabelOn(String countdown) {
    return 'FAN ON • $countdown';
  }

  @override
  String get fanSemanticAuto => 'Fan auto, tap to turn on';

  @override
  String fanSemanticOn(String countdown) {
    return 'Fan on for $countdown, tap to switch to auto';
  }

  @override
  String get fanChangeServerRejected => 'Server rejected fan command';

  @override
  String get fanChangeFailed => 'Couldn\'t change fan';

  @override
  String get fanDurationSheetTitle => 'RUN FAN FOR';

  @override
  String fanDurationMinutes(int minutes) {
    return '$minutes MINUTES';
  }

  @override
  String get fanDuration1Hour => '1 HOUR';

  @override
  String fanDurationHours(int hours) {
    return '$hours HOURS';
  }

  @override
  String get awayChipLabel => 'AWAY';

  @override
  String get awaySemanticOn =>
      'Away mode on, tap to disable. Long press to edit eco temperatures.';

  @override
  String get awaySemanticOff =>
      'Away mode off, tap to enable. Long press to edit eco temperatures.';

  @override
  String get awayToggleFailed => 'Couldn\'t toggle away';

  @override
  String get awayToggleServerRejected => 'Server rejected away change';

  @override
  String get awayEcoSaveFailed => 'Couldn\'t save eco temperatures';

  @override
  String get awayEcoSaveServerRejected => 'Server rejected eco temps change';

  @override
  String get ecoSheetTitle => 'ECO TEMPERATURES';

  @override
  String get ecoSheetLowLabel => 'LOW (HEAT)';

  @override
  String get ecoSheetHighLabel => 'HIGH (COOL)';

  @override
  String get ecoSheetValidationLowHigh => 'Low must be lower than high.';

  @override
  String get ecoSheetCancel => 'CANCEL';

  @override
  String get ecoSheetSave => 'SAVE';

  @override
  String get dialTemperatureFailed => 'Couldn\'t update temperature';

  @override
  String get dialTemperatureNotConfirmed => 'Couldn\'t confirm new temperature';

  @override
  String get dialRetry => 'Retry';

  @override
  String get stalePillRetry => 'RETRY';

  @override
  String get stalePillReconnecting => 'Reconnecting…';

  @override
  String get stalePillRateLimited => 'Server busy — retrying';

  @override
  String get stalePillNotConnected => 'Not connected';

  @override
  String stalePillLastUpdated(String elapsed) {
    return 'Last updated $elapsed';
  }

  @override
  String get stalePillElapsedJustNow => 'just now';

  @override
  String get stalePillElapsedOneMinute => '1 min ago';

  @override
  String stalePillElapsedMinutes(int minutes) {
    return '$minutes min ago';
  }

  @override
  String get stalePillElapsedOneHour => '1 hour ago';

  @override
  String stalePillElapsedHours(int hours) {
    return '$hours hours ago';
  }

  @override
  String get welcomeTitle => 'Rest Thermostat';

  @override
  String get welcomeBody =>
      'Connect to your NoLongerEvil server to control your Gen 1/2 Nest thermostats.';

  @override
  String welcomeDocsLink(String url) {
    return 'Docs: $url';
  }

  @override
  String get welcomeStartButton => 'Get started';

  @override
  String get serverSetupTitle => 'Server Setup';

  @override
  String get serverAddressLabel => 'Server address';

  @override
  String get serverAddressHint => 'nest.home or 192.168.1.42';

  @override
  String get serverAddressRequired => 'Server address is required.';

  @override
  String get advancedSectionTitle => 'Advanced';

  @override
  String get authChoiceLabel => 'Authentication';

  @override
  String get authChoiceNone => 'None';

  @override
  String get authChoiceBasic => 'Basic';

  @override
  String get authChoiceBearer => 'Bearer';

  @override
  String get authUsernameLabel => 'Username';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authPasswordShow => 'Show password';

  @override
  String get authPasswordHide => 'Hide password';

  @override
  String get authTokenLabel => 'Token';

  @override
  String get authTokenShow => 'Show token';

  @override
  String get authTokenHide => 'Hide token';

  @override
  String get connectButton => 'Connect';

  @override
  String get connectFailedAuth => 'Authentication failed.';

  @override
  String get connectFailedUnreachable => 'Couldn\'t reach server.';

  @override
  String get devicePickerTitle => 'Choose a thermostat';

  @override
  String get noDevicesTitle => 'No thermostats registered.';

  @override
  String get noDevicesBody =>
      'Pair your Nest Gen 1/2 with your NoLongerEvil server before continuing.';

  @override
  String get noDevicesGoBack => 'Go back';

  @override
  String get devicePickerSheetHeader => 'Devices';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsConnectionSection => 'Connection';

  @override
  String get settingsTestConnection => 'Test connection';

  @override
  String get settingsSave => 'Save';

  @override
  String get settingsCancel => 'Cancel';

  @override
  String get settingsConnectionSaved => 'Connection settings saved.';

  @override
  String settingsTestSuccess(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Connected — $count devices found.',
      one: 'Connected — 1 device found.',
    );
    return '$_temp0';
  }

  @override
  String get settingsDevicesSection => 'Devices';

  @override
  String settingsDevicesLoadError(Object error) {
    return 'Couldn\'t load devices: $error';
  }

  @override
  String get settingsNoDevices => 'No devices.';

  @override
  String get settingsDiagnosticsSection => 'Diagnostics';

  @override
  String get settingsViewLogs => 'View logs';

  @override
  String get settingsViewLogsSubtitle =>
      'In-memory diagnostic log of recent app activity.';

  @override
  String get settingsAboutSection => 'About';

  @override
  String settingsAboutVersion(String version, String buildNumber) {
    return 'Rest Thermostat $version (build $buildNumber)';
  }

  @override
  String get settingsAboutCredit => 'For Cody Kociemba\'s NoLongerEvil project';

  @override
  String settingsAboutDocsLink(String url) {
    return 'NLE docs: $url';
  }

  @override
  String settingsAboutSourceLink(String url) {
    return 'Source: $url';
  }

  @override
  String get settingsDangerZoneSection => 'Danger zone';

  @override
  String get settingsDisconnect => 'Disconnect from server';

  @override
  String get settingsDisconnectDialogTitle => 'Disconnect from server?';

  @override
  String get settingsDisconnectDialogBody =>
      'This will remove your server settings and saved credentials. Continue?';

  @override
  String get settingsDisconnectConfirm => 'Disconnect';

  @override
  String get settingsRenameDialogTitle => 'Rename thermostat';

  @override
  String get settingsRenameDisplayLabel => 'Display name';

  @override
  String get settingsRenameHelp => 'Leave empty to use the server name';

  @override
  String get scheduleTitle => 'Schedule';

  @override
  String get scheduleAddEventTooltip => 'Add event';

  @override
  String get scheduleEmptyTitle => 'No events scheduled';

  @override
  String get scheduleEmptyHint => 'Tap + to add one';

  @override
  String scheduleLoadError(Object error) {
    return 'Couldn\'t load schedule: $error';
  }

  @override
  String get scheduleEventTypeHeat => 'HEAT';

  @override
  String get scheduleEventTypeCool => 'COOL';

  @override
  String get scheduleEventTypeRange => 'RANGE';

  @override
  String scheduleEventSemanticLabel(
    String time,
    String temp,
    String modeLower,
  ) {
    return 'Event at $time, $temp $modeLower, tap to edit.';
  }

  @override
  String scheduleActiveEventSemanticLabel(String event) {
    return 'Currently active. $event';
  }

  @override
  String scheduleHeaderTemps(String measured, String target) {
    return 'Now $measured • Set $target';
  }

  @override
  String scheduleHeaderTempsSemantics(String measured, String target) {
    return 'Now $measured, set to $target';
  }

  @override
  String get editEventTitleNew => 'New Event';

  @override
  String get editEventTitleEdit => 'Edit Event';

  @override
  String get editEventCancel => 'Cancel';

  @override
  String get editEventSave => 'Save';

  @override
  String get editEventTimeLabel => 'Time';

  @override
  String get editEventRepeatLabel => 'Repeat';

  @override
  String get editEventDeleteButton => 'Delete Event';

  @override
  String get editEventDeleteDialogTitle => 'Delete event?';

  @override
  String get editEventDeleteDialogBody =>
      'This will remove the event from this day.';

  @override
  String get editEventDeleteConfirm => 'Delete';

  @override
  String get editEventHourLabel => 'Hour';

  @override
  String get editEventMinuteLabel => 'Minute';

  @override
  String get editEventAmLabel => 'AM';

  @override
  String get editEventPmLabel => 'PM';

  @override
  String get editEventHourError24 => 'Enter an hour from 0–23';

  @override
  String get editEventHourError12 => 'Enter an hour from 1–12';

  @override
  String get editEventMinuteError => 'Enter minutes from 0–59';

  @override
  String get editEventSavedSnack => 'Schedule saved';

  @override
  String get editEventSaveFailedSnack => 'Couldn\'t save schedule. Retry?';

  @override
  String get editEventRetryAction => 'Retry';

  @override
  String get editEventTempEntryTitle => 'Set temperature';

  @override
  String get editEventTempEntryConfirm => 'Set';

  @override
  String get detailsSectionCurrent => 'CURRENT';

  @override
  String get detailsSectionSystem => 'SYSTEM';

  @override
  String get detailsHumidity => 'HUMIDITY';

  @override
  String get detailsSetpoint => 'SETPOINT';

  @override
  String get detailsSetpointSourceTooltip =>
      'Source is derived locally from schedule + away state. (Derived)';

  @override
  String get detailsComfortDry => 'Dry';

  @override
  String get detailsComfortComfortable => 'Comfortable';

  @override
  String get detailsComfortHumid => 'Humid';

  @override
  String get detailsSetpointSourceAway => 'Away';

  @override
  String get detailsSetpointSourceScheduled => 'Scheduled';

  @override
  String get detailsSetpointSourceManual => 'Manual';

  @override
  String get detailsStatus => 'STATUS';

  @override
  String get detailsStatusConnected => 'Connected';

  @override
  String get detailsStatusOffline => 'Offline';

  @override
  String get detailsServer => 'SERVER';

  @override
  String get detailsFirmware => 'FIRMWARE';

  @override
  String get detailsLocalIp => 'LOCAL IP';

  @override
  String get detailsMacAddress => 'MAC ADDRESS';

  @override
  String get detailsLastSync => 'LAST SYNC';

  @override
  String get detailsLastSyncEmpty => '—';

  @override
  String get detailsLastSyncNoPoll => 'No successful poll yet';

  @override
  String get detailsLastSyncJustNow => 'just now';

  @override
  String detailsLastSyncSeconds(int seconds) {
    return '$seconds seconds ago';
  }

  @override
  String get detailsLastSyncOneMinute => '1 minute ago';

  @override
  String detailsLastSyncMinutes(int minutes) {
    return '$minutes minutes ago';
  }

  @override
  String get detailsLastSyncOneHour => '1 hour ago';

  @override
  String detailsLastSyncHours(int hours) {
    return '$hours hours ago';
  }

  @override
  String get detailsLastSyncOneDay => '1 day ago';

  @override
  String detailsLastSyncDays(int days) {
    return '$days days ago';
  }

  @override
  String get logsTitle => 'Diagnostic logs';

  @override
  String get logsCopyTooltip => 'Copy to clipboard';

  @override
  String get logsShareTooltip => 'Share';

  @override
  String get logsClearTooltip => 'Clear';

  @override
  String get logsCopiedSnack => 'Logs copied to clipboard.';

  @override
  String get logsClearDialogTitle => 'Clear logs?';

  @override
  String get logsClearDialogBody =>
      'This removes all in-memory log entries. The buffer will start fresh from the next event.';

  @override
  String get logsClearConfirm => 'Clear';

  @override
  String get logsCancel => 'Cancel';

  @override
  String get logsEmpty => 'No log entries yet.';
}
