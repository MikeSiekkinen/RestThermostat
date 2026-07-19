import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';

class WelcomeScreen extends StatelessWidget {
  final VoidCallback onStart;

  /// Optional "Restore from backup" affordance (Issue #109). When null the
  /// secondary button is hidden — keeps the screen usable in contexts that
  /// don't wire up the backup service.
  final VoidCallback? onRestore;
  static const nleDocsUrl = 'https://docs.nolongerevil.com';

  const WelcomeScreen({super.key, required this.onStart, this.onRestore});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text(
                l.welcomeTitle,
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(l.welcomeBody, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              SelectableText(
                l.welcomeDocsLink(nleDocsUrl),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              FilledButton(
                onPressed: onStart,
                child: Text(l.welcomeStartButton),
              ),
              if (onRestore != null)
                TextButton(
                  onPressed: onRestore,
                  child: Text(l.welcomeRestoreButton),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
