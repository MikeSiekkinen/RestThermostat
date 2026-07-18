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
