import '../l10n/gen/app_localizations.dart';
import '../services/nle_error.dart';

/// Maps a typed [NleError] from a Test-Connection attempt to user-facing copy.
/// Shared by the onboarding flow and the Settings connection editor so both
/// surface the same cause-specific message. Network failures include the
/// `host:port` the attempt was aimed at — the detail that makes a wrong-port
/// or wrong-scheme mistake obvious at a glance.
String connectErrorMessage(AppLocalizations l, NleError error) {
  switch (error) {
    case NleAuthError(:final isCloudflareAccess):
      return isCloudflareAccess
          ? l.connectFailedCloudflareAccess
          : l.connectFailedAuth;
    case NleNetworkError(:final kind, :final target):
      final shown = target.isEmpty ? '?' : target;
      return switch (kind) {
        NleNetworkErrorKind.connectionTimeout ||
        NleNetworkErrorKind.receiveTimeout ||
        NleNetworkErrorKind.sendTimeout => l.connectFailedTimeout(shown),
        NleNetworkErrorKind.connectionRefused => l.connectFailedRefused(shown),
        NleNetworkErrorKind.dnsFailure => l.connectFailedDns(shown),
        NleNetworkErrorKind.tlsFailure => l.connectFailedTls(shown),
        NleNetworkErrorKind.unknown => l.connectFailedNetwork(shown),
      };
    case NleRateLimitError():
    case NleServerError():
    case NleClientError():
    case NleParseError():
      return l.connectFailedUnreachable;
  }
}

/// Result of a Test-Connection attempt from the Server Setup screen.
sealed class ConnectOutcome {
  const ConnectOutcome();
}

/// Connection succeeded; the orchestrator has already routed onward (to
/// Device Picker or Home). The Server Setup screen takes no further action.
class ConnectSuccess extends ConnectOutcome {
  const ConnectSuccess();
}

/// Connection failed in a recoverable way (network down, bad credentials).
/// The Server Setup screen surfaces [message] inline so the user can adjust
/// inputs and retry.
class ConnectInlineError extends ConnectOutcome {
  final String message;
  const ConnectInlineError(this.message);
}

/// Server reached, but zero devices registered. The orchestrator has already
/// routed to a blocking error screen.
class ConnectBlocking extends ConnectOutcome {
  const ConnectBlocking();
}
