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
  String get homeSetTemperature => 'Set temperature';

  @override
  String get homeTempEntryTitle => 'Set temperature';

  @override
  String get homeTempEntryConfirm => 'Set';

  @override
  String get homeTempEntryCancel => 'Cancel';

  @override
  String get homeDialHeatLabel => 'HEAT';

  @override
  String get homeDialCoolLabel => 'COOL';

  @override
  String homeDialRangeSemantics(
    String low,
    String high,
    String current,
    String humidity,
  ) {
    return 'Temperature range: heat set to $low, cool set to $high. Current temperature $current.$humidity Tap to type a new range.';
  }

  @override
  String get homeRangeEntryTitle => 'Set temperature range';

  @override
  String get homeRangeEntryHeatField => 'Heat';

  @override
  String get homeRangeEntryCoolField => 'Cool';

  @override
  String homeRangeEntryDeadbandError(String gap) {
    return 'Heat must be at least $gap below cool.';
  }

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
  String get authChoiceCfServiceToken => 'Cloudflare Access';

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
  String get authCfClientIdLabel => 'Service token client ID';

  @override
  String get authCfClientSecretLabel => 'Service token client secret';

  @override
  String get authCfClientSecretShow => 'Show client secret';

  @override
  String get authCfClientSecretHide => 'Hide client secret';

  @override
  String get connectButton => 'Connect';

  @override
  String get connectFailedAuth => 'Authentication failed.';

  @override
  String get connectFailedCloudflareAccess =>
      'Blocked by Cloudflare Access. Add a valid service token under Advanced → Cloudflare Access.';

  @override
  String get connectFailedUnreachable => 'Couldn\'t reach server.';

  @override
  String connectFailedTimeout(String target) {
    return 'Connection to $target timed out. The server didn\'t respond.';
  }

  @override
  String connectFailedRefused(String target) {
    return 'Connection to $target was refused. Check the address and port.';
  }

  @override
  String connectFailedDns(String target) {
    return 'Couldn\'t find server $target. Check the address.';
  }

  @override
  String connectFailedTls(String target) {
    return 'Secure (TLS) connection to $target failed. Check the address and certificate.';
  }

  @override
  String connectFailedNetwork(String target) {
    return 'Couldn\'t reach $target. Check your network and the address.';
  }

  @override
  String connectFailedRedirect(String target) {
    return 'Server at $target redirected the request. Check the address — if your proxy upgrades to HTTPS, use the https:// URL directly.';
  }

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
  String get settingsAppearanceSection => 'Appearance';

  @override
  String get settingsTimeFieldPaletteLabel => 'Schedule time boxes';

  @override
  String get settingsTimeFieldPaletteHelp =>
      'How the Hour/Minute boxes on Edit Event are colored.';

  @override
  String get settingsTimeFieldPaletteMatchMode => 'Match mode';

  @override
  String get settingsTimeFieldPaletteNeutral => 'Neutral';

  @override
  String get scheduleSyncing => 'Updating schedule for the new mode…';

  @override
  String get settingsNumeralFontLabel => 'Schedule numerals';

  @override
  String get settingsNumeralFontHelp =>
      'Font for the numbers on the schedule time & temperature displays.';

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
  String get settingsBackupSection => 'Backup';

  @override
  String get settingsExportBackup => 'Export backup…';

  @override
  String get settingsExportBackupSubtitle =>
      'Save an encrypted copy of your settings and credentials.';

  @override
  String get settingsRestoreBackup => 'Restore from backup…';

  @override
  String get settingsRestoreBackupSubtitle =>
      'Import settings and credentials from a backup file.';

  @override
  String get backupSetPassphraseTitle => 'Set a backup passphrase';

  @override
  String get backupPassphraseLabel => 'Passphrase';

  @override
  String get backupPassphraseConfirmLabel => 'Confirm passphrase';

  @override
  String get backupPassphraseHelp => 'At least 8 characters.';

  @override
  String get backupPassphraseWarning =>
      'There is no way to recover this backup if you forget the passphrase.';

  @override
  String get backupPassphraseTooShort => 'Use at least 8 characters.';

  @override
  String get backupPassphraseMismatch => 'Passphrases don\'t match.';

  @override
  String get backupPassphraseShow => 'Show passphrase';

  @override
  String get backupPassphraseHide => 'Hide passphrase';

  @override
  String get backupExportAction => 'Export';

  @override
  String get backupImportAction => 'Continue';

  @override
  String get backupExportedSnack => 'Backup saved.';

  @override
  String get backupEncrypting => 'Encrypting…';

  @override
  String get backupDecrypting => 'Decrypting…';

  @override
  String get backupEnterPassphraseTitle => 'Enter backup passphrase';

  @override
  String get backupEnterPassphraseBody =>
      'Enter the passphrase this backup was created with.';

  @override
  String get backupWrongPassphrase => 'Wrong passphrase. Try again.';

  @override
  String get backupErrorForeignFile =>
      'That file isn\'t a Rest Thermostat backup.';

  @override
  String get backupErrorTooNew =>
      'This backup was made by a newer version of the app. Update Rest Thermostat and try again.';

  @override
  String get backupErrorMalformed =>
      'That backup file is damaged or unreadable.';

  @override
  String backupExportFailed(Object error) {
    return 'Couldn\'t create the backup: $error';
  }

  @override
  String backupRestoreFailed(Object error) {
    return 'Couldn\'t restore the backup: $error';
  }

  @override
  String get backupRestorePartial =>
      'Restore failed and your settings may be partly changed. Reconnect from Settings or try restoring again.';

  @override
  String get backupConfirmTitle => 'Restore this backup?';

  @override
  String get backupConfirmBody =>
      'This replaces your current server, credentials, and appearance with the values in the backup.';

  @override
  String backupConfirmServer(String url) {
    return 'Server: $url';
  }

  @override
  String get backupConfirmServerNone => 'Server: not set';

  @override
  String backupConfirmAuth(String type) {
    return 'Sign-in: $type';
  }

  @override
  String backupConfirmDeviceNames(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count saved device names',
      one: '1 saved device name',
      zero: 'No saved device names',
    );
    return '$_temp0';
  }

  @override
  String get backupConfirmAction => 'Restore';

  @override
  String get backupRestoredSnack => 'Backup restored.';

  @override
  String get welcomeRestoreButton => 'Restore from backup';

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
  String scheduleHeaderNow(String measured, String humidity) {
    return 'Now $measured · $humidity';
  }

  @override
  String scheduleHeaderSet(String target) {
    return 'Set $target';
  }

  @override
  String scheduleHeaderTempsSemantics(
    String measured,
    String humidity,
    String target,
  ) {
    return 'Now $measured, humidity $humidity, set to $target';
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
  String get detailsSectionSystem => 'SYSTEM';

  @override
  String get detailsHumidity => 'HUMIDITY';

  @override
  String get detailsTemperature => 'TEMP';

  @override
  String get detailsSetpoint => 'SETPOINT';

  @override
  String detailsCurrentHeader(String name, String mode) {
    return '$name · $mode';
  }

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
  String get detailsUnits => 'UNITS';

  @override
  String get detailsUnitsFahrenheit => 'Fahrenheit';

  @override
  String get detailsUnitsCelsius => 'Celsius';

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
