import 'package:rest_thermostat/models/auth_config.dart';
import 'package:rest_thermostat/services/onboarding_store.dart';

class FakeOnboardingStore implements OnboardingStore {
  String? serverUrl;
  AuthConfig auth = const AuthNone();
  String? activeSerial;
  bool complete = false;

  @override
  Future<OnboardingConfig> read() async => OnboardingConfig(
    serverUrl: serverUrl,
    auth: auth,
    activeSerial: activeSerial,
    isComplete: complete,
  );

  @override
  Future<void> saveServerUrl(String url) async => serverUrl = url;

  @override
  Future<void> saveAuth(AuthConfig newAuth) async => auth = newAuth;

  @override
  Future<void> saveActiveSerial(String serial) async => activeSerial = serial;

  @override
  Future<void> markComplete() async => complete = true;
}
