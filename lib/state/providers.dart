import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/auth_config.dart';
import '../onboarding/onboarding_flow.dart';
import '../services/app_info.dart';
import '../services/app_logger.dart';
import '../services/nle_api_client.dart';
import '../services/onboarding_store.dart';
import 'device_state_source.dart';
import 'devices_snapshot.dart';
import 'polling_device_state_source.dart';
import 'state_cache.dart';

/// (url, auth) pair the rest of the state graph reacts to. `null` while
/// onboarding is incomplete; Bootstrap pushes the persisted config in once
/// the user finishes setup.
typedef ActiveServer = ({String url, AuthConfig auth});

class ActiveServerNotifier extends Notifier<ActiveServer?> {
  @override
  ActiveServer? build() => null;

  void set(ActiveServer config) => state = config;
  void clear() => state = null;
}

final activeServerProvider =
    NotifierProvider<ActiveServerNotifier, ActiveServer?>(
      ActiveServerNotifier.new,
    );

NleApiClient _defaultClientFactory(String url, AuthConfig auth) =>
    NleApiClient.create(
      baseUrl: url,
      authorizationHeader: auth.authorizationHeader,
      logger: AppLogger.instance,
    );

/// Default production factory. Tests override this provider to inject a
/// Dio-backed mock client.
final clientFactoryProvider = Provider<NleClientFactory>(
  (_) => _defaultClientFactory,
);

final stateCacheProvider = Provider<StateCache>((_) => SharedPrefsStateCache());

/// Bound in `main.dart` to the same [OnboardingStore] instance Bootstrap uses,
/// so Settings reads/writes hit the same persistence layer. Tests override
/// with [FakeOnboardingStore].
final onboardingStoreProvider = Provider<OnboardingStore>((_) {
  throw StateError(
    'onboardingStoreProvider read without an override. main.dart should '
    'override it with the platform-backed FlutterOnboardingStore.',
  );
});

/// Overridden in tests with a [StaticAppInfo]. Production binding is set up in
/// `main.dart` after `PackageInfo.fromPlatform()` resolves.
final appInfoProvider = Provider<AppInfo>((_) {
  throw StateError(
    'appInfoProvider read without an override. main.dart should override it '
    'with the loaded PackageInfo before runApp.',
  );
});

final nleApiClientProvider = Provider<NleApiClient>((ref) {
  final config = ref.watch(activeServerProvider);
  if (config == null) {
    throw StateError(
      'nleApiClientProvider read before activeServerProvider was populated. '
      'Bootstrap should set the active server before mounting Home.',
    );
  }
  final factory = ref.watch(clientFactoryProvider);
  return factory(config.url, config.auth);
});

/// Auto-disposes when the last subscriber goes away. Per DESIGN §3.2 this is
/// the refcounting hook that pauses polling when the UI isn't watching.
final deviceStateSourceProvider = Provider.autoDispose<DeviceStateSource>((
  ref,
) {
  final client = ref.watch(nleApiClientProvider);
  final source = PollingDeviceStateSource(
    fetchJson: client.fetchDevicesJson,
    cache: ref.watch(stateCacheProvider),
    logger: ref.watch(appLoggerProvider),
  );
  source.start();
  ref.onDispose(source.dispose);
  return source;
});

final devicesSnapshotProvider = StreamProvider.autoDispose<DevicesSnapshot>((
  ref,
) {
  return ref.watch(deviceStateSourceProvider).watch();
});
