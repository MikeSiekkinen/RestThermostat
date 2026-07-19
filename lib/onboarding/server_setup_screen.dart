import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../models/auth_config.dart';
import '../services/url_normalizer.dart';
import '../theme/colors.dart';
import 'connect_outcome.dart';

typedef ConnectFn =
    Future<ConnectOutcome> Function(String normalizedUrl, AuthConfig auth);

enum _AuthChoice { none, basic, bearer, cfServiceToken }

class ServerSetupScreen extends StatefulWidget {
  final String? initialUrl;
  final AuthConfig initialAuth;
  final ConnectFn onConnect;

  /// Optional "Restore from backup" affordance (Issue #109). Reached here
  /// (not just Welcome) because a signing-key blowout can wipe the Keystore
  /// credentials while the persisted URL survives, resuming the flow straight
  /// on this screen and skipping Welcome. Null hides the button.
  final VoidCallback? onRestore;

  const ServerSetupScreen({
    super.key,
    required this.initialUrl,
    required this.initialAuth,
    required this.onConnect,
    this.onRestore,
  });

  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends State<ServerSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _tokenCtrl;
  late final TextEditingController _cfClientIdCtrl;
  late final TextEditingController _cfClientSecretCtrl;
  late _AuthChoice _authChoice;
  bool _advancedExpanded = false;
  bool _busy = false;
  String? _inlineError;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.initialUrl ?? '');
    _userCtrl = TextEditingController();
    _passCtrl = TextEditingController();
    _tokenCtrl = TextEditingController();
    _cfClientIdCtrl = TextEditingController();
    _cfClientSecretCtrl = TextEditingController();
    switch (widget.initialAuth) {
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
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _tokenCtrl.dispose();
    _cfClientIdCtrl.dispose();
    _cfClientSecretCtrl.dispose();
    super.dispose();
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

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final String url;
    try {
      url = normalizeServerUrl(_urlCtrl.text);
    } on UrlNormalizationException catch (e) {
      setState(() => _inlineError = e.message);
      return;
    }

    setState(() {
      _busy = true;
      _inlineError = null;
    });

    final outcome = await widget.onConnect(url, _buildAuth());
    if (!mounted) return;

    setState(() {
      _busy = false;
      if (outcome is ConnectInlineError) {
        _inlineError = outcome.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.serverSetupTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                    if (raw.trim().isEmpty) {
                      return l.serverAddressRequired;
                    }
                    try {
                      normalizeServerUrl(raw);
                      return null;
                    } on UrlNormalizationException catch (e) {
                      return e.message;
                    }
                  },
                ),
                const SizedBox(height: 16),
                ExpansionTile(
                  title: Text(l.advancedSectionTitle),
                  initiallyExpanded: _advancedExpanded,
                  onExpansionChanged: (v) =>
                      setState(() => _advancedExpanded = v),
                  childrenPadding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    DropdownButtonFormField<_AuthChoice>(
                      initialValue: _authChoice,
                      // The ember theme's canvasColor is transparent, which the
                      // dropdown menu popup would otherwise inherit and render
                      // see-through (Issue #70). Pin the app's opaque menu
                      // surface.
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
                        if (v != null) setState(() => _authChoice = v);
                      },
                    ),
                    if (_authChoice == _AuthChoice.basic) ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _userCtrl,
                        decoration: InputDecoration(
                          labelText: l.authUsernameLabel,
                        ),
                        autocorrect: false,
                        enableSuggestions: false,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _passCtrl,
                        decoration: InputDecoration(
                          labelText: l.authPasswordLabel,
                        ),
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                      ),
                    ] else if (_authChoice == _AuthChoice.bearer) ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _tokenCtrl,
                        decoration: InputDecoration(
                          labelText: l.authTokenLabel,
                        ),
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                      ),
                    ] else if (_authChoice == _AuthChoice.cfServiceToken) ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _cfClientIdCtrl,
                        decoration: InputDecoration(
                          labelText: l.authCfClientIdLabel,
                        ),
                        autocorrect: false,
                        enableSuggestions: false,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _cfClientSecretCtrl,
                        decoration: InputDecoration(
                          labelText: l.authCfClientSecretLabel,
                        ),
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
                if (_inlineError != null) ...[
                  Text(
                    _inlineError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l.connectButton),
                ),
                if (widget.onRestore != null)
                  TextButton(
                    onPressed: _busy ? null : widget.onRestore,
                    child: Text(l.welcomeRestoreButton),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
