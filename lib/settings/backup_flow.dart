import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/gen/app_localizations.dart';
import '../services/backup/backup_errors.dart';
import '../services/backup/backup_service.dart';
import '../services/backup/config_snapshot.dart';

/// Filename suggested to the OS share sheet / file dialog for an export.
const _backupFileName = 'rest-thermostat-backup.json';

/// UI orchestration for encrypted config backup/restore (Issue #109, ADR-0001),
/// shared by the Settings screen and the onboarding welcome screen so both
/// entry points behave identically.

/// Export flow: prompt for a new passphrase (with confirm + "no recovery"
/// warning) → encrypt off the UI thread behind a spinner → hand the file to the
/// system share sheet. No-ops silently if the user cancels the passphrase step.
Future<void> runBackupExport(
  BuildContext context,
  BackupService service,
) async {
  final l = AppLocalizations.of(context);
  final passphrase = await showDialog<String>(
    context: context,
    builder: (_) => const _SetPassphraseDialog(),
  );
  if (passphrase == null || !context.mounted) return;

  final String envelope;
  try {
    envelope = await _withProgress(
      context,
      l.backupEncrypting,
      () => service.exportEncrypted(passphrase),
    );
  } catch (e) {
    if (context.mounted) _snack(context, l.backupExportFailed(e));
    return;
  }

  final bytes = Uint8List.fromList(utf8.encode(envelope));
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          bytes,
          mimeType: 'application/json',
          name: _backupFileName,
        ),
      ],
      fileNameOverrides: const [_backupFileName],
    ),
  );
}

/// Import flow: pick a file → reject foreign/too-new/damaged files *before*
/// prompting → ask for the passphrase (re-prompting on a wrong one) → decrypt
/// behind a spinner → confirm the summary → apply. On success, runs [onApplied]
/// (callers refresh live state and navigate there). Returns true iff a backup
/// was applied.
Future<bool> runBackupImport(
  BuildContext context,
  BackupService service, {
  required Future<void> Function() onApplied,
}) async {
  final l = AppLocalizations.of(context);

  const typeGroup = XTypeGroup(
    label: 'Rest Thermostat backup',
    extensions: ['json'],
    mimeTypes: ['application/json'],
    uniformTypeIdentifiers: ['public.json'],
  );
  final file = await openFile(acceptedTypeGroups: [typeGroup]);
  if (file == null || !context.mounted) return false;

  final String text;
  try {
    text = await file.readAsString();
  } catch (_) {
    if (context.mounted) _snack(context, l.backupErrorMalformed);
    return false;
  }
  if (!context.mounted) return false;

  // Header gate — cheap, no passphrase needed.
  try {
    service.inspect(text);
  } on BackupForeignFile {
    _snack(context, l.backupErrorForeignFile);
    return false;
  } on BackupTooNewSchema {
    _snack(context, l.backupErrorTooNew);
    return false;
  } on BackupMalformed {
    _snack(context, l.backupErrorMalformed);
    return false;
  }

  // Passphrase loop — re-prompt on a wrong passphrase, abort on cancel.
  ConfigSnapshot snapshot;
  String? inlineError;
  while (true) {
    if (!context.mounted) return false;
    final passphrase = await showDialog<String>(
      context: context,
      builder: (_) => _EnterPassphraseDialog(errorText: inlineError),
    );
    if (passphrase == null || !context.mounted) return false;
    try {
      snapshot = await _withProgress(
        context,
        l.backupDecrypting,
        () => service.decrypt(text, passphrase),
      );
      break;
    } on BackupWrongPassphrase {
      inlineError = l.backupWrongPassphrase;
      if (!context.mounted) return false;
      continue;
    } on BackupMalformed {
      if (context.mounted) _snack(context, l.backupErrorMalformed);
      return false;
    }
  }
  if (!context.mounted) return false;

  final confirmed =
      await showDialog<bool>(
        context: context,
        builder: (_) => _ConfirmRestoreDialog(snapshot: snapshot),
      ) ??
      false;
  if (!confirmed || !context.mounted) return false;

  try {
    await service.apply(snapshot);
  } catch (e) {
    if (context.mounted) _snack(context, l.backupRestoreFailed(e));
    return false;
  }

  await onApplied();
  return true;
}

/// Human-facing label for an auth scheme tag, reusing the connection-form
/// strings so "Basic" / "Bearer" / "Cloudflare" read the same everywhere.
String authTypeLabel(AppLocalizations l, String tag) => switch (tag) {
  'basic' => l.authChoiceBasic,
  'bearer' => l.authChoiceBearer,
  'cf_service_token' => l.authChoiceCfServiceToken,
  _ => l.authChoiceNone,
};

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Shows a non-dismissible progress dialog for the duration of [task]. The
/// Argon2id KDF (~1 s) runs inside [task] on an isolate, so the UI stays
/// responsive behind the spinner.
Future<T> _withProgress<T>(
  BuildContext context,
  String caption,
  Future<T> Function() task,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProgressDialog(caption: caption),
  );
  try {
    return await task();
  } finally {
    // Pop only the progress dialog we pushed.
    navigator.pop();
  }
}

class _ProgressDialog extends StatelessWidget {
  final String caption;
  const _ProgressDialog({required this.caption});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Row(
        children: [
          const SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 20),
          Expanded(child: Text(caption)),
        ],
      ),
    );
  }
}

/// Export passphrase dialog: passphrase + confirm, min-length + match
/// validation, reveal toggle, and an explicit unrecoverable-if-forgotten
/// warning. Pops the validated passphrase, or null on cancel.
class _SetPassphraseDialog extends StatefulWidget {
  const _SetPassphraseDialog();

  @override
  State<_SetPassphraseDialog> createState() => _SetPassphraseDialogState();
}

class _SetPassphraseDialogState extends State<_SetPassphraseDialog> {
  static const _minLength = 8;
  final _formKey = GlobalKey<FormState>();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _visible = false;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(_passCtrl.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.backupSetPassphraseTitle),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _passCtrl,
              autofocus: true,
              obscureText: !_visible,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: l.backupPassphraseLabel,
                helperText: l.backupPassphraseHelp,
                suffixIcon: IconButton(
                  icon: Icon(
                    _visible ? Icons.visibility_off : Icons.visibility,
                  ),
                  tooltip: _visible
                      ? l.backupPassphraseHide
                      : l.backupPassphraseShow,
                  onPressed: () => setState(() => _visible = !_visible),
                ),
              ),
              validator: (v) => (v ?? '').length < _minLength
                  ? l.backupPassphraseTooShort
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _confirmCtrl,
              obscureText: !_visible,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: l.backupPassphraseConfirmLabel,
              ),
              validator: (v) =>
                  v != _passCtrl.text ? l.backupPassphraseMismatch : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.backupPassphraseWarning,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.settingsCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l.backupExportAction)),
      ],
    );
  }
}

/// Import passphrase prompt. Shows [errorText] inline (set after a wrong
/// passphrase). Pops the entered passphrase, or null on cancel.
class _EnterPassphraseDialog extends StatefulWidget {
  final String? errorText;
  const _EnterPassphraseDialog({this.errorText});

  @override
  State<_EnterPassphraseDialog> createState() => _EnterPassphraseDialogState();
}

class _EnterPassphraseDialogState extends State<_EnterPassphraseDialog> {
  final _ctrl = TextEditingController();
  bool _visible = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_ctrl.text.isNotEmpty) Navigator.of(context).pop(_ctrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.backupEnterPassphraseTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.backupEnterPassphraseBody),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            obscureText: !_visible,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l.backupPassphraseLabel,
              errorText: widget.errorText,
              suffixIcon: IconButton(
                icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
                tooltip: _visible
                    ? l.backupPassphraseHide
                    : l.backupPassphraseShow,
                onPressed: () => setState(() => _visible = !_visible),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.settingsCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l.backupImportAction)),
      ],
    );
  }
}

/// Confirms overwriting current config, summarizing what the backup will apply:
/// server, sign-in type, and how many device names it carries.
class _ConfirmRestoreDialog extends StatelessWidget {
  final ConfigSnapshot snapshot;
  const _ConfirmRestoreDialog({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final dim = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return AlertDialog(
      title: Text(l.backupConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.backupConfirmBody),
          const SizedBox(height: 12),
          Text(
            snapshot.serverUrl == null
                ? l.backupConfirmServerNone
                : l.backupConfirmServer(snapshot.serverUrl!),
            style: dim,
          ),
          Text(
            l.backupConfirmAuth(authTypeLabel(l, snapshot.auth.tag)),
            style: dim,
          ),
          Text(
            l.backupConfirmDeviceNames(snapshot.deviceNameOverrides.length),
            style: dim,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.settingsCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l.backupConfirmAction),
        ),
      ],
    );
  }
}
