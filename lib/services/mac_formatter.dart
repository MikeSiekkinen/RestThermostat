/// Formats a MAC address for display.
///
/// The NLE server sends the MAC as bare hex with no separators (e.g.
/// `18b430aabbcc`) — verified against a live Gen 1 device during upstream
/// NoLongerEvil-SelfHosted PR #24. A 12-hex-digit value is rendered as
/// lowercase colon-separated pairs (`18:b4:30:aa:bb:cc`); anything else is
/// returned verbatim rather than mangled.
String formatMacAddress(String raw) {
  final bareHex = RegExp(r'^[0-9a-fA-F]{12}$');
  if (!bareHex.hasMatch(raw)) return raw;
  final hex = raw.toLowerCase();
  return List.generate(6, (i) => hex.substring(i * 2, i * 2 + 2)).join(':');
}
