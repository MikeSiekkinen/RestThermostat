import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/auth_config.dart';
import '../models/device.dart';
import '../screens/logs/logs_screen.dart';
import '../services/device_display_name.dart';
import '../services/nle_error.dart';
import '../services/nle_error_messages.dart';
import '../services/onboarding_store.dart';
import '../services/url_normalizer.dart';
import '../state/providers.dart';
import '../theme/colors.dart';
import 'backup_flow.dart';
import 'numeral_font.dart';
import 'time_field_palette.dart';

/// GitHub repo link shown in the About section. Centralized so tests can
/// assert against it without re-typing the URL.
const String settingsRepoUrl =
    'https://github.com/MikeSiekkinen/RestThermostat';
const String settingsNleDocsUrl = 'https://docs.nolongerevil.com';
const String settingsNleCredit = "For Cody Kociemba's NoLongerEvil project";

/// Settings screen per DESIGN §7.6 + §12.7. Sections, top-to-bottom:
/// Connection (URL + auth re-edit, gated by a successful re-test), Devices
/// (per-row rename), About (version + credits + repo link), Danger zone
/// (Disconnect, wipes everything).
class SettingsScreen extends ConsumerStatefulWidget {
  /// Invoked after Disconnect completes its wipe. The host wires this to
  /// re-route back to Welcome (see `lib/main.dart`).
  final VoidCallback onDisconnect;

  /// Invoked after a successful Restore-from-backup so the host can re-read the
  /// now-replaced config and rebuild (pop Settings + re-bootstrap). Distinct
  /// from [onDisconnect] because restore lands the user connected, not at
  /// Welcome. See `lib/main.dart`.
  final VoidCallback? onConfigRestored;

  /// When true, the Connection section's "Advanced" (auth) expander starts
  /// expanded — used by the auth-failure deep-link snackbar so the user
  /// lands directly on the credentials form.
  final bool initiallyExpandAuth;

  const SettingsScreen({
    super.key,
    required this.onDisconnect,
    this.onConfigRestored,
    this.initiallyExpandAuth = false,
  });

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _tokenCtrl;
  late final TextEditingController _cfClientIdCtrl;
  late final TextEditingController _cfClientSecretCtrl;
  late _AuthChoice _authChoice;
  bool _advancedExpanded = false;
  bool _passwordVisible = false;
  bool _tokenVisible = false;
  bool _cfClientSecretVisible = false;
  bool _testing = false;
  bool _testPassed = false;
  // Guards the backup Export/Restore flows against a double-tap launching two
  // interleaved flows (there's a one-frame window before the dialog covers the
  // tile).
  bool _backupBusy = false;
  String? _testError;
  String? _testSuccessMsg;
  Map<String, String> _latestOverrides = const {};

  // The URL+auth combination that produced the most recent successful test;
  // Save is only enabled when the *current* form values match these. Any edit
  // after a successful test invalidates the gate and re-disables Save, per the
  // issue spec.
  String? _gatedUrl;
  AuthConfig? _gatedAuth;

  Future<OnboardingConfig>? _initialLoadFuture;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController();
    _userCtrl = TextEditingController();
    _passCtrl = TextEditingController();
    _tokenCtrl = TextEditingController();
    _cfClientIdCtrl = TextEditingController();
    _cfClientSecretCtrl = TextEditingController();
    _authChoice = _AuthChoice.none;
    if (widget.initiallyExpandAuth) {
      _advancedExpanded = true;
    }

    _urlCtrl.addListener(_invalidateGate);
    _userCtrl.addListener(_invalidateGate);
    _passCtrl.addListener(_invalidateGate);
    _tokenCtrl.addListener(_invalidateGate);
    _cfClientIdCtrl.addListener(_invalidateGate);
    _cfClientSecretCtrl.addListener(_invalidateGate);

    _initialLoadFuture = _loadInitial();
  }

  Future<OnboardingConfig> _loadInitial() async {
    final store = ref.read(onboardingStoreProvider);
    final config = await store.read();
    if (!mounted) return config;
    setState(() {
      _urlCtrl.text = config.serverUrl ?? '';
      switch (config.auth) {
        case AuthNone():
          _authChoice = _AuthChoice.none;
        case AuthBasic(:final username, :final password):
          _authChoice = _AuthChoice.basic;
          _userCtrl.text = username;
          _passCtrl.text = password;
          _advancedExpanded = true;
        case AuthBearer(:final token):
          _authChoice = _AuthChoice.bearer;
          _tokenCtrl.text = token;
          _advancedExpanded = true;
        case AuthCfServiceToken(:final clientId, :final clientSecret):
          _authChoice = _AuthChoice.cfServiceToken;
          _cfClientIdCtrl.text = clientId;
          _cfClientSecretCtrl.text = clientSecret;
          _advancedExpanded = true;
      }
      _latestOverrides = config.deviceNameOverrides;
    });
    return config;
  }

  @override
  void dispose() {
    _urlCtrl.removeListener(_invalidateGate);
    _userCtrl.removeListener(_invalidateGate);
    _passCtrl.removeListener(_invalidateGate);
    _tokenCtrl.removeListener(_invalidateGate);
    _cfClientIdCtrl.removeListener(_invalidateGate);
    _cfClientSecretCtrl.removeListener(_invalidateGate);
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _tokenCtrl.dispose();
    _cfClientIdCtrl.dispose();
    _cfClientSecretCtrl.dispose();
    super.dispose();
  }

  void _invalidateGate() {
    // Any edit to URL/auth fields invalidates the prior test pass — the user
    // must re-test before Save re-enables.
    if (_gatedUrl == null) return;
    final currentNormalized = _tryNormalize(_urlCtrl.text);
    if (currentNormalized == _gatedUrl && _matchesGatedAuth(_buildAuth())) {
      return;
    }
    setState(() {
      _testPassed = false;
      _testSuccessMsg = null;
    });
  }

  String? _tryNormalize(String raw) {
    try {
      return normalizeServerUrl(raw);
    } on UrlNormalizationException {
      return null;
    }
  }

  bool _matchesGatedAuth(AuthConfig current) {
    final gated = _gatedAuth;
    if (gated == null) return false;
    if (current.tag != gated.tag) return false;
    // Compare the full header contribution rather than just the Authorization
    // header — schemes like Cloudflare Access carry their credentials in custom
    // headers and have no Authorization value to compare.
    return _headersEqual(current.headers, gated.headers);
  }

  static bool _headersEqual(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  AuthConfig _buildAuth() => switch (_authChoice) {
    _AuthChoice.none => const AuthNone(),
    _AuthChoice.basic => AuthBasic(
      username: _userCtrl.text,
      password: _passCtrl.text,
    ),
    _AuthChoice.bearer => AuthBearer(token: _tokenCtrl.text),
    _AuthChoice.cfServiceToken => AuthCfServiceToken(
      clientId: _cfClientIdCtrl.text,
      clientSecret: _cfClientSecretCtrl.text,
    ),
  };

  Future<void> _onTestConnection() async {
    if (_testing) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final String url;
    try {
      url = normalizeServerUrl(_urlCtrl.text);
    } on UrlNormalizationException catch (e) {
      setState(() {
        _testError = e.message;
        _testSuccessMsg = null;
        _testPassed = false;
      });
      return;
    }

    final auth = _buildAuth();
    setState(() {
      _testing = true;
      _testError = null;
      _testSuccessMsg = null;
    });

    final factory = ref.read(clientFactoryProvider);
    final client = factory(url, auth);
    final l = AppLocalizations.of(context);
    try {
      final response = await client.getDevices();
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testPassed = true;
        _gatedUrl = url;
        _gatedAuth = auth;
        _testSuccessMsg = l.settingsTestSuccess(response.devices.length);
      });
    } on NleError catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testPassed = false;
        _testError = connectErrorMessage(l, e);
      });
    }
  }

  Future<void> _onSave() async {
    if (!_testPassed || _gatedUrl == null) return;
    final url = _gatedUrl!;
    final auth = _gatedAuth!;
    final store = ref.read(onboardingStoreProvider);

    // Persist new config first, then clear cache, then push into the active
    // server provider — this order matches DESIGN §12.6 (clear cache before
    // the new URL takes effect on the polling source) and ensures the next
    // poll uses the fresh credentials.
    await store.saveServerUrl(url);
    await store.saveAuth(auth);
    await ref.read(stateCacheProvider).clear();
    ref.read(activeServerProvider.notifier).set((url: url, auth: auth));

    if (!mounted) return;
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.settingsConnectionSaved)));
  }

  Future<void> _onRenameDevice(Device device, String currentDisplay) async {
    // Dialog pops `null` on Cancel, or a trimmed string on Save. An empty
    // string means "clear the override" per the issue spec; setDeviceNameOverride
    // collapses that to a removal.
    final result = await showDialog<String>(
      context: context,
      builder: (_) =>
          _RenameDeviceDialog(serial: device.serial, initial: currentDisplay),
    );
    if (result == null) return;
    final store = ref.read(onboardingStoreProvider);
    await store.setDeviceNameOverride(
      device.serial,
      result.isEmpty ? null : result,
    );
    final config = await store.read();
    if (!mounted) return;
    setState(() {
      _latestOverrides = config.deviceNameOverrides;
    });
  }

  Future<void> _onDisconnect() async {
    final l = AppLocalizations.of(context);
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l.settingsDisconnectDialogTitle),
            content: Text(l.settingsDisconnectDialogBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l.settingsCancel),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l.settingsDisconnectConfirm),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    final store = ref.read(onboardingStoreProvider);
    await store.clear();
    await ref.read(stateCacheProvider).clear();
    ref.read(activeServerProvider.notifier).clear();

    if (!mounted) return;
    widget.onDisconnect();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OnboardingConfig>(
      future: _initialLoadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(AppLocalizations.of(context).settingsTitle),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildConnectionSection(context),
                    const Divider(),
                    _buildDevicesSection(context),
                    const Divider(),
                    _buildDiagnosticsSection(context),
                    const Divider(),
                    _buildBackupSection(context),
                    const Divider(),
                    _buildAppearanceSection(context),
                    const Divider(),
                    _buildAboutSection(context),
                    const Divider(),
                    _buildDangerZone(context),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildConnectionSection(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(text: l.settingsConnectionSection),
          TextFormField(
            controller: _urlCtrl,
            decoration: InputDecoration(
              labelText: l.serverAddressLabel,
              hintText: l.serverAddressHint,
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            validator: (v) {
              final raw = v ?? '';
              if (raw.trim().isEmpty) return l.serverAddressRequired;
              try {
                normalizeServerUrl(raw);
                return null;
              } on UrlNormalizationException catch (e) {
                return e.message;
              }
            },
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            title: Text(l.advancedSectionTitle),
            initiallyExpanded: _advancedExpanded,
            onExpansionChanged: (v) => setState(() => _advancedExpanded = v),
            childrenPadding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              DropdownButtonFormField<_AuthChoice>(
                initialValue: _authChoice,
                // Opaque menu surface — without it the popup inherits the
                // theme's transparent canvasColor and renders see-through
                // (Issue #70), same as the onboarding auth picker.
                dropdownColor: EmberColors.menuSurface,
                decoration: InputDecoration(labelText: l.authChoiceLabel),
                items: [
                  DropdownMenuItem(
                    value: _AuthChoice.none,
                    child: Text(l.authChoiceNone),
                  ),
                  DropdownMenuItem(
                    value: _AuthChoice.basic,
                    child: Text(l.authChoiceBasic),
                  ),
                  DropdownMenuItem(
                    value: _AuthChoice.bearer,
                    child: Text(l.authChoiceBearer),
                  ),
                  DropdownMenuItem(
                    value: _AuthChoice.cfServiceToken,
                    child: Text(l.authChoiceCfServiceToken),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _authChoice = v);
                    _invalidateGate();
                  }
                },
              ),
              if (_authChoice == _AuthChoice.basic) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _userCtrl,
                  decoration: InputDecoration(labelText: l.authUsernameLabel),
                  autocorrect: false,
                  enableSuggestions: false,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passCtrl,
                  decoration: InputDecoration(
                    labelText: l.authPasswordLabel,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _passwordVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _passwordVisible = !_passwordVisible),
                      tooltip: _passwordVisible
                          ? l.authPasswordHide
                          : l.authPasswordShow,
                    ),
                  ),
                  obscureText: !_passwordVisible,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              ] else if (_authChoice == _AuthChoice.bearer) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _tokenCtrl,
                  decoration: InputDecoration(
                    labelText: l.authTokenLabel,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _tokenVisible ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _tokenVisible = !_tokenVisible),
                      tooltip: _tokenVisible
                          ? l.authTokenHide
                          : l.authTokenShow,
                    ),
                  ),
                  obscureText: !_tokenVisible,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              ] else if (_authChoice == _AuthChoice.cfServiceToken) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _cfClientIdCtrl,
                  decoration: InputDecoration(labelText: l.authCfClientIdLabel),
                  autocorrect: false,
                  enableSuggestions: false,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _cfClientSecretCtrl,
                  decoration: InputDecoration(
                    labelText: l.authCfClientSecretLabel,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _cfClientSecretVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () => setState(
                        () => _cfClientSecretVisible = !_cfClientSecretVisible,
                      ),
                      tooltip: _cfClientSecretVisible
                          ? l.authCfClientSecretHide
                          : l.authCfClientSecretShow,
                    ),
                  ),
                  obscureText: !_cfClientSecretVisible,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (_testError != null) ...[
            Text(
              _testError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 8),
          ],
          if (_testSuccessMsg != null) ...[
            Text(
              _testSuccessMsg!,
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _testing ? null : _onTestConnection,
                  child: _testing
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l.settingsTestConnection),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _testPassed ? _onSave : null,
                  child: Text(l.settingsSave),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceRow(Device d) {
    final name = displayNameFor(d, _latestOverrides);
    return _DeviceRow(
      device: d,
      displayName: name,
      onTap: () => _onRenameDevice(d, name),
    );
  }

  Widget _buildDevicesSection(BuildContext context) {
    final async = ref.watch(devicesSnapshotProvider);
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(text: l.settingsDevicesSection),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text(
              l.settingsDevicesLoadError(e),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            data: (snapshot) {
              if (snapshot.devices.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(l.settingsNoDevices),
                );
              }
              return Column(
                children: snapshot.devices.map(_buildDeviceRow).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsSection(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(text: l.settingsDiagnosticsSection),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.settingsViewLogs),
            subtitle: Text(l.settingsViewLogsSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const LogsScreen()));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBackupSection(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(text: l.settingsBackupSection),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.settingsExportBackup),
            subtitle: Text(l.settingsExportBackupSubtitle),
            trailing: const Icon(Icons.ios_share),
            onTap: _onExportBackup,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l.settingsRestoreBackup),
            subtitle: Text(l.settingsRestoreBackupSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: _onRestoreBackup,
          ),
        ],
      ),
    );
  }

  Future<void> _onExportBackup() async {
    if (_backupBusy) return;
    setState(() => _backupBusy = true);
    try {
      await runBackupExport(context, ref.read(backupServiceProvider));
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _onRestoreBackup() async {
    if (_backupBusy) return;
    setState(() => _backupBusy = true);
    try {
      await _runRestore();
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<void> _runRestore() async {
    final applied = await runBackupImport(
      context,
      ref.read(backupServiceProvider),
      onApplied: () async {
        // Appearance notifiers hydrated once at startup — force a re-read of the
        // restored prefs. Clear the state cache so the next poll uses the
        // restored server + credentials rather than the old device's snapshot.
        ref.invalidate(numeralFontProvider);
        ref.invalidate(timeFieldPaletteProvider);
        await ref.read(stateCacheProvider).clear();
      },
    );
    if (!applied || !mounted) return;
    final l = AppLocalizations.of(context);
    // MaterialApp's root ScaffoldMessenger survives the pop below, so this shows
    // on the freshly-loaded Home.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l.backupRestoredSnack)));
    widget.onConfigRestored?.call();
  }

  Widget _buildAppearanceSection(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = ref.watch(timeFieldPaletteProvider);
    final numeral = ref.watch(numeralFontProvider);
    final dim = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(text: l.settingsAppearanceSection),
          Text(
            l.settingsTimeFieldPaletteLabel,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(l.settingsTimeFieldPaletteHelp, style: dim),
          const SizedBox(height: 12),
          SegmentedButton<TimeFieldPalette>(
            segments: [
              ButtonSegment(
                value: TimeFieldPalette.matchMode,
                label: Text(l.settingsTimeFieldPaletteMatchMode),
              ),
              ButtonSegment(
                value: TimeFieldPalette.neutral,
                label: Text(l.settingsTimeFieldPaletteNeutral),
              ),
            ],
            selected: {palette},
            onSelectionChanged: (selection) => ref
                .read(timeFieldPaletteProvider.notifier)
                .set(selection.first),
          ),
          const SizedBox(height: 20),
          Text(
            l.settingsNumeralFontLabel,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(l.settingsNumeralFontHelp, style: dim),
          const SizedBox(height: 8),
          DropdownButton<NumeralFont>(
            key: const ValueKey('numeral-font-dropdown'),
            isExpanded: true,
            // Opaque menu surface — see the auth dropdown above (Issue #70).
            dropdownColor: EmberColors.menuSurface,
            value: numeral,
            items: [
              for (final font in NumeralFont.values)
                DropdownMenuItem(
                  value: font,
                  child: Text(
                    // Preview each option in its own face, with a numeric sample.
                    '${font.label}   012 · 34°',
                    style: font.style.copyWith(fontSize: 18),
                  ),
                ),
            ],
            onChanged: (font) {
              if (font != null) {
                ref.read(numeralFontProvider.notifier).set(font);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    final info = ref.watch(appInfoProvider);
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(text: l.settingsAboutSection),
          Text(l.settingsAboutVersion(info.version, info.buildNumber)),
          const SizedBox(height: 8),
          Text(l.settingsAboutCredit),
          const SizedBox(height: 8),
          SelectableText(l.settingsAboutDocsLink(settingsNleDocsUrl)),
          SelectableText(l.settingsAboutSourceLink(settingsRepoUrl)),
        ],
      ),
    );
  }

  Widget _buildDangerZone(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(text: l.settingsDangerZoneSection),
          TextButton(
            onPressed: _onDisconnect,
            style: TextButton.styleFrom(foregroundColor: errorColor),
            child: Text(l.settingsDisconnect),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  final Device device;
  final String displayName;
  final VoidCallback onTap;

  const _DeviceRow({
    required this.device,
    required this.displayName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(displayName),
      subtitle: Text(
        device.serial,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.edit, size: 18),
      onTap: onTap,
    );
  }
}

enum _AuthChoice { none, basic, bearer, cfServiceToken }

class _RenameDeviceDialog extends StatefulWidget {
  final String serial;
  final String initial;

  const _RenameDeviceDialog({required this.serial, required this.initial});

  @override
  State<_RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

class _RenameDeviceDialogState extends State<_RenameDeviceDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.settingsRenameDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.serial,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            decoration: InputDecoration(
              labelText: l.settingsRenameDisplayLabel,
              helperText: l.settingsRenameHelp,
            ),
            autofocus: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(l.settingsCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
          child: Text(l.settingsSave),
        ),
      ],
    );
  }
}
