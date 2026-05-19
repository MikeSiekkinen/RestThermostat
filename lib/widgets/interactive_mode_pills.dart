import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/device.dart';
import '../state/providers.dart';
import 'mode_pills.dart';

/// Stateful Riverpod consumer that adds the interactive write-path around
/// [ModePills] per `docs/DESIGN.md` §3.4 + §9.7.
///
/// Responsibilities the read-only [ModePills] does **not** own:
/// 1. **Optimistic mode override.** As soon as the user taps, the active pill
///    flips locally so the row + EmberBackground gradient transitions feel
///    immediate. We hold an `_optimisticMode` that overrides
///    [Device.mode] until reconciliation arrives.
/// 2. **POST `set_mode` + reconciliation kick.** Translates the tapped
///    [ModePillOption] back through `toDeviceMode().toApi()` (the AUTO ↔
///    `heat-cool` converter from #8) and POSTs via [NleApiClient.sendCommand],
///    then calls [DeviceStateSource.refresh] so the +1/+3/+7s reconciliation
///    polls fire per #5.
/// 3. **Failure path.** A `DioException` after the internal retry surfaces
///    a snackbar — server-side rejections (4xx) carry the server message
///    when present so the user knows *why* the change was refused — and
///    reverts the optimistic mode.
/// 4. **Haptic.** `HapticFeedback.lightImpact()` on tap per §11.5.
///
/// Reconciliation match isn't actively watched here (unlike the dial's
/// temperature flow) — the snapshot stream replaces the optimistic mode
/// the next time it emits a snapshot whose `mode` equals the optimistic
/// pick. If it never does, the next legitimate snapshot from the server
/// just overrides our local view; users see the dial/gradient revert to
/// whatever the device reports. That's the §9.7 "defense in depth" path.
class InteractiveModePills extends ConsumerStatefulWidget {
  final Device device;

  const InteractiveModePills({super.key, required this.device});

  @override
  ConsumerState<InteractiveModePills> createState() =>
      _InteractiveModePillsState();
}

class _InteractiveModePillsState extends ConsumerState<InteractiveModePills> {
  /// Local override of the active mode while we wait for the snapshot stream
  /// to reflect the server's confirmation. `null` means "trust the device".
  DeviceMode? _optimisticMode;

  @override
  void didUpdateWidget(covariant InteractiveModePills oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Once the device snapshot reflects our optimistic pick, clear it so the
    // pill row goes back to passively rendering the server's truth.
    if (_optimisticMode != null && widget.device.mode == _optimisticMode) {
      _optimisticMode = null;
    }
  }

  Future<void> _onTap(ModePillOption option) async {
    final newMode = option.toDeviceMode();
    if (newMode == _displayedMode) return; // Already this mode; no-op.

    HapticFeedback.lightImpact();
    setState(() => _optimisticMode = newMode);

    final client = ref.read(nleApiClientProvider);
    try {
      await client.sendCommand(
        serial: widget.device.serial,
        command: 'set_mode',
        value: newMode.toApi(),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      _revert(_messageFor(e));
      return;
    } catch (_) {
      if (!mounted) return;
      _revert('Couldn\'t change mode');
      return;
    }

    if (!mounted) return;
    ref.read(deviceStateSourceProvider).refresh();
  }

  DeviceMode get _displayedMode => _optimisticMode ?? widget.device.mode;

  void _revert(String message) {
    setState(() => _optimisticMode = null);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Pulls a human-readable message out of a [DioException] response body.
  /// Server payloads aren't standardized — try `error`, then `message`, then
  /// the raw decoded body. Fall back to mode-specific copy.
  String _messageFor(DioException e) {
    final body = e.response?.data;
    if (body is Map) {
      final candidate = body['error'] ?? body['message'];
      if (candidate is String && candidate.isNotEmpty) return candidate;
    } else if (body is String && body.isNotEmpty) {
      return body;
    }
    final code = e.response?.statusCode ?? 0;
    if (code >= 400 && code < 500) return 'Server rejected mode change';
    return 'Couldn\'t change mode';
  }

  @override
  Widget build(BuildContext context) {
    return ModePills(
      currentMode: _displayedMode,
      capabilities: widget.device.capabilities,
      onModeTap: _onTap,
    );
  }
}
