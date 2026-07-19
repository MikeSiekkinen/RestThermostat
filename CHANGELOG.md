# Changelog

All notable changes to Rest Thermostat will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.0] - 2026-07-18

### Added

- Cloudflare Access service-token authentication. The Advanced auth picker on
  the Server Setup and Settings screens gains a "Cloudflare Access" option with
  client-ID and client-secret fields, sent as the `CF-Access-Client-Id` /
  `CF-Access-Client-Secret` header pair so the app can reach an NLE proxy
  fronted by Cloudflare Access. Credentials are stored in secure storage under
  `auth_cf_client_id` / `auth_cf_client_secret`. See `docs/DESIGN.md` §7.2/§7.3.
  (Community contribution, [#69](https://github.com/MikeSiekkinen/RestThermostat/pull/69).)
- Numeral-font picker in Settings → Appearance (Oswald / Anton / JetBrains
  Mono), applied to the Home dial and the schedule numerics. ([#103](https://github.com/MikeSiekkinen/RestThermostat/issues/103))
- Current relative humidity is shown next to the temperature on the Home dial
  and in the Schedule "Now" header. ([#104](https://github.com/MikeSiekkinen/RestThermostat/issues/104))
- The Schedule header now shows the scheduled thermostat's name with its
  current measured and target temperatures. ([#100](https://github.com/MikeSiekkinen/RestThermostat/issues/100))
- The Edit Event time-field color can be set to match the event mode or stay
  neutral (Settings → Appearance). ([#105](https://github.com/MikeSiekkinen/RestThermostat/issues/105))
- Repeat-day selection shows weekday + next-occurrence date panels, and New
  Event gains a day/date context header. ([#106](https://github.com/MikeSiekkinen/RestThermostat/issues/106))
- The scheduled event currently driving the setpoint is highlighted in the
  schedule list. ([#97](https://github.com/MikeSiekkinen/RestThermostat/issues/97))

### Changed

- Connection errors now report the specific cause instead of a single
  "Couldn't reach server." Timeouts, refused connections, DNS failures, TLS
  failures, and redirects each get distinct copy that includes the `host:port`
  the attempt was aimed at, and the diagnostics log records the target and the
  underlying socket reason (no credentials). Shared by onboarding and the
  Settings connection editor. ([#69](https://github.com/MikeSiekkinen/RestThermostat/pull/69))
- Edit Event time entry replaces the wheel picker with hour/minute text inputs
  and tap-to-type temperature. ([#96](https://github.com/MikeSiekkinen/RestThermostat/issues/96))
- The Home dial's current-temperature line drops the "Currently" label and
  italic and adopts the chosen numeral font. ([#104](https://github.com/MikeSiekkinen/RestThermostat/issues/104))

### Fixed

- **Schedules now execute.** `set_schedule` writes are conformed to the Gen 2
  device bucket contract (map-not-array entries, required `name` /
  `entry_type`, `schedule_mode` gating), fixing scheduled setpoints that the
  device silently ignored. ([#93](https://github.com/MikeSiekkinen/RestThermostat/issues/93))
- Switching the device mode no longer leaves the Schedule tab showing the
  previous mode's events; a spinner holds until the device publishes the
  new-mode schedule. ([#107](https://github.com/MikeSiekkinen/RestThermostat/issues/107))
- URL normalization now uses a scheme-aware default port: `https` URLs without
  an explicit port default to `:443` instead of `:8082`. Forcing `:8082` onto
  `https` addresses made Cloudflare-fronted (and other reverse-proxied)
  deployments unreachable with the generic "Couldn't reach server." Note:
  addresses saved before this fix keep their stored `:8082` port — re-enter
  the address in Settings → Connection to pick up the new default.
  ([#69](https://github.com/MikeSiekkinen/RestThermostat/pull/69))
- The API client no longer follows HTTP redirects. On an `https` target, a
  redirect to Cloudflare Access (or a `WWW-Authenticate: Cloudflare-Access`
  challenge) is classified as an access-gate auth failure with specific
  guidance to add a service token; any other redirect gets its own
  "server redirected" copy naming the target instead of being misreported as
  a network or authentication failure. ([#69](https://github.com/MikeSiekkinen/RestThermostat/pull/69))

## [1.1.0] - 2026-07-04

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

[Unreleased]: https://github.com/MikeSiekkinen/RestThermostat/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/MikeSiekkinen/RestThermostat/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/MikeSiekkinen/RestThermostat/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/MikeSiekkinen/RestThermostat/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/MikeSiekkinen/RestThermostat/releases/tag/v1.0.0
