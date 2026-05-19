import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_logger.dart';
import 'polling_device_state_source.dart';
import 'providers.dart';

/// Wraps the home subtree, observes app lifecycle, and forwards
/// `paused`/`resumed` to the [PollingDeviceStateSource] per DESIGN §12.3.
class LifecycleBridge extends ConsumerStatefulWidget {
  final Widget child;
  const LifecycleBridge({super.key, required this.child});

  @override
  ConsumerState<LifecycleBridge> createState() => _LifecycleBridgeState();
}

class _LifecycleBridgeState extends ConsumerState<LifecycleBridge>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final source = ref.read(deviceStateSourceProvider);
    final logger = ref.read(appLoggerProvider);
    if (source is! PollingDeviceStateSource) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        logger.info('app paused');
        source.pause();
      case AppLifecycleState.resumed:
        logger.info('app resumed');
        source.resume();
      case AppLifecycleState.inactive:
        // No-op per DESIGN §12.3.
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
