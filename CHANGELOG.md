# Changelog

All notable changes to Rest Thermostat will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.2] - 2026-07-04

### Added

- Details screen now shows the thermostat's **Local IP** and **MAC address**
  in the System section, when the NLE server provides them. Requires an
  NLE-SelfHosted server running a build newer than 2026-06-29 (upstream
  [PR #24](https://github.com/codykociemba/NoLongerEvil-SelfHosted/pull/24));
  on older servers the rows are hidden and the screen is unchanged.

### Changed

- Bumped dependencies: `package_info_plus` 10.1.0 → 10.2.0, `share_plus`
  13.1.0 → 13.2.0, `shared_preferences_android` 2.4.23 → 2.4.26 (all three
  migrated off applying the Kotlin Gradle Plugin, which a future Flutter
  release makes a build failure), plus transitive updates including `dio`
  5.9.2 → 5.10.0.
- Raised the minimum Flutter SDK to `>=3.44.0` (required by
  `shared_preferences_android` 2.4.26).
- Command retry/error classification now covers dio 5.10's new
  `transformTimeout` exception type (treated as a transient timeout).

## [1.0.1] - 2026-05-29

### Changed

- Bumped dependencies: `flutter_secure_storage` 10.2.0 → 10.3.1,
  `package_info_plus` 9.0.0 → 10.1.0, `share_plus` 11.1.0 → 13.1.0.
- Raised the minimum Flutter SDK to `>=3.38.1` (required by the
  `package_info_plus` and `share_plus` updates).
- The build number (`+N`) now increments on any change to the resolved
  dependency set (`pubspec.lock`), enforced by a new `dependency-build-bump`
  CI job. See `docs/DESIGN.md` §13.4.

### Security

- Pinned all GitHub Actions to full commit SHAs and set
  `persist-credentials: false` on checkout steps.
- Added a Sigstore build-provenance attestation to released APKs
  (verify with `gh attestation verify rest-thermostat.apk --owner MikeSiekkinen`).
- Configured Dependabot for the `pub`, `github-actions`, and `gradle`
  ecosystems.

## [1.0.0] - 2026-05-20

### Added

- Flutter project scaffold for Android, iOS, macOS, and web platforms.
- GitHub Actions CI workflow running `flutter analyze`, `flutter test`, and
  `dart format --output=none --set-exit-if-changed .` on every pull request.
- NLE device data models (`Device`, `DevicesResponse`) backed by
  fixture-driven tests.
- `NleApiClient` with `GET /api/devices` for fetching paired thermostats.
- Four-screen onboarding flow per `docs/DESIGN.md` §7: welcome, server
  setup, device picker, connect outcome. Persists server URL and optional
  reverse-proxy credentials in `flutter_secure_storage`.
- URL normalizer that accepts bare hosts, ports, and full URLs.
- Riverpod state management with `PollingDeviceStateSource`, lifecycle-aware
  pause/resume, and an in-memory `StateCache` keyed by device id.
- `DevicesSnapshot` model that distinguishes fresh, stale, and error states
  for the home screen consumer.
- Ember theme: dark palette, Fraunces/Geist/JetBrains Mono bundled fonts, and
  the `EmberBackground` gradient widget. Edge-to-edge dark system overlays.
- Settings screen with connection re-edit, device rename, About, and
  Disconnect (clears credentials and re-routes to onboarding).
- `AppLogger` ring buffer wired into the dio request/response interceptor
  and the polling lifecycle bridge. Settings → View logs surfaces Copy /
  Share / Clear actions.
- Read-only Schedule screen with locale-aware day tabs backed by a
  `scheduleProvider` and `GET /api/schedule`.
- App icon (concentric arcs, Ember-themed) and native splash assets
  generated for Android and iOS via `flutter_launcher_icons` and
  `flutter_native_splash`.
- Project documentation: `README.md`, `LICENSE` (MIT), `CHANGELOG.md`, and
  `docs/IOS_BUILD.md` build-from-source guide.

[Unreleased]: https://github.com/MikeSiekkinen/RestThermostat/compare/v1.0.2...HEAD
[1.0.2]: https://github.com/MikeSiekkinen/RestThermostat/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/MikeSiekkinen/RestThermostat/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/MikeSiekkinen/RestThermostat/releases/tag/v1.0.0
