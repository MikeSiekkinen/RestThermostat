# Rest Thermostat — Engineering Design

> Companion to `PRD.md`. This document captures architectural and design decisions resolved during a Q1–Q18 design grilling. The PRD is the product-intent reference; this is the engineering reference. Where the two diverge, this document takes precedence (divergences listed in [§18](#18-prd-divergences)).

---

## Table of contents

1. [Scope and posture](#1-scope-and-posture)
2. [Connection model](#2-connection-model)
3. [State sync](#3-state-sync)
4. [Multi-device](#4-multi-device)
5. [Missing data sources](#5-missing-data-sources)
6. [Schedule model](#6-schedule-model)
7. [Setup and auth](#7-setup-and-auth)
8. [Capabilities and temperature units](#8-capabilities-and-temperature-units)
9. [Modes, fan, away](#9-modes-fan-away)
10. [Visual identity](#10-visual-identity)
11. [Rendering specifics](#11-rendering-specifics)
12. [Lifecycle and persistence](#12-lifecycle-and-persistence)
13. [Build and distribution](#13-build-and-distribution)
14. [Testing](#14-testing)
15. [Edge cases, logging, privacy, i18n](#15-edge-cases-logging-privacy-i18n)
16. [NLE API reference](#16-nle-api-reference)
17. [Open items for implementation](#17-open-items-for-implementation)
18. [PRD divergences](#18-prd-divergences)

---

## 1. Scope and posture

Rest Thermostat is a Flutter mobile app for the NoLongerEvil (NLE) self-hosted server, controlling Nest Gen 1 & 2 thermostats. Audience is the open-source NLE community; v1 ships via sideload.

**The app is NLE-only forever.** There is no `ThermostatApiClient` interface with NLE as one implementation; an `NleApiClient` is the data layer. No abstraction for hypothetical other thermostat vendors.

**Legal posture: no Nest-derivative imagery.** Beyond the PRD's "no trademarks" rule, the visual design must avoid iconography that could read as derivative of Nest's design language (the leaf, three-blade fan, specific dial proportions). Substitute distinct alternatives. See [§10](#10-visual-identity).

---

## 2. Connection model

### 2.1 One URL, no reachability detection

The user configures a single Server URL. The app is reachability-agnostic — if the user wants remote access, they solve it externally (Tailscale, WireGuard, Cloudflare Tunnel, hairpin NAT). The app doesn't know or care which network it's on.

There is **no** SSID detection, **no** subnet matching, **no** Wi-Fi-vs-cellular pre-check. Asking for the location permission required to read SSIDs would be a poor trade for the brittleness it introduces (mesh-network SSID splits, captive portals, Tailscale users who'd be wrongly blocked).

### 2.2 Connection failure UX

When a request times out or fails:
- Show "Cannot reach server" banner with a retry button.
- Suggest in the error copy: "Check that you're on the right network, or that your VPN/tunnel is connected if you've set up remote access."
- Cached state (if any) remains visible. Writes are disabled. See [§12.4](#124-stale-state-indicator).

### 2.3 Timeouts

- Connect timeout: 5 seconds.
- Receive timeout: 10 seconds.
- Per-request retry: 1 retry with 2-second backoff for `POST /command`. Read polls do not retry; the next cadence cycle is the retry.

---

## 3. State sync

### 3.1 Polling-only in v1

NLE exposes SSE at `GET /api/events`, but v1 uses HTTP polling only. The architectural seam is preserved so SSE can plug in later (see [§3.2](#32-devicestatesource-abstraction)).

### 3.2 `DeviceStateSource` abstraction

```dart
abstract class DeviceStateSource {
  Stream<DevicesSnapshot> watch();
  void refresh();              // pull-to-refresh, post-command, on resume
  Future<void> dispose();
}

class PollingDeviceStateSource implements DeviceStateSource { ... }
// future: SseDeviceStateSource implements DeviceStateSource
```

The Riverpod provider holds a `DeviceStateSource` typed as the abstract. UI consumes the stream and never knows which implementation is wired. The data source owns its own timer lifecycle (not UI, not the provider). Refcounted via Riverpod auto-dispose — when the last subscriber goes away, polling pauses; first subscriber resumes it.

### 3.3 Polling cadence

- **Foreground idle:** `GET /api/devices` every **20 seconds**. `/api/devices` returns all devices' full state in one response, so a single fetch covers every device.
- **After any successful `POST /command`:** schedule reconciliation polls at **+1s, +3s, +7s** (then resume normal 20s cadence). NLE's command path is async — the server queues the command for the thermostat's long-poll-subscribe channel, and the state update appears in `/api/devices` only after the thermostat picks it up and PUTs back.
- **Pull-to-refresh:** immediate `/api/devices`.
- **App resume from background:** immediate `/api/devices`, then 20s cadence.
- **Background:** all polling stopped.

### 3.4 Optimistic updates and reconciliation

1. User taps/drags → local state updates immediately, UI re-renders.
2. `POST /command` with new value.
3. The +1s/+3s/+7s reconciliation polls fetch `/api/devices`.
4. **Match found** (current state == optimistic value): considered confirmed; no UI change.
5. **Mismatch** (server clamped 90°F to a max-temp limit, etc.): tween-animate from optimistic to confirmed value over ~300ms.
6. **No reconciliation match within 7s**: show "Couldn't confirm" toast with retry. **Do not** auto-revert the UI — keep the optimistic value visible so the user can re-issue.

The "couldn't confirm" toast will fire occasionally on a healthy network (thermostat napping). Silent UI/server disagreement is the worse failure mode.

---

## 4. Multi-device

### 4.1 Full multi-device UI in v1

NLE supports multiple devices natively; the UI exposes them. All providers are keyed by `serial`:

```dart
final activeDeviceSerialProvider = StateProvider<String>(...);
final deviceStateProvider = Provider.family<DeviceState, String>(...);
final scheduleProvider = AsyncNotifierProvider.family<...>(...);
```

### 4.2 Switcher UI — hybrid

Two affordances:

- **Header dropdown.** Device name at the top of Home is tappable → bottom sheet with the device list.
- **Horizontal page swipe.** `PageView` on Home; swipe left/right between devices. Page indicator dots at the bottom of the dial area.

For users with a single device: no dots, no swipe (just static header text). Scales gracefully up to ~4 devices.

### 4.3 Per-device theming

Each device has its own `mode` (heat/cool/auto/off). Background gradient and glow color are per-device. Swiping between devices animates the background gradient (`AnimatedContainer`, 300ms `easeInOutCubic`).

### 4.4 Device naming

NLE has no "set device name" endpoint. Display name resolution:

```
displayName(device) =
  localOverride(serial)             // user-renamed in app Settings
  ?? device.name                    // from NLE (if non-null, non-"unnamed")
  ?? "Thermostat (${serial.takeLast(4)})"
```

Local overrides stored in `shared_preferences`, keyed by serial. Rename action lives in Settings → per-device row.

### 4.5 Active device persistence

Selected device persists across app launches in `shared_preferences`. If the persisted serial isn't in the latest `/api/devices` response, fall back to the first device and show a one-time snackbar.

### 4.6 Bottom-nav scope

Home/Schedule/Details bottom nav. Each tab renders for `activeDeviceSerialProvider`. Switching device on Home updates everything.

---

## 5. Missing data sources

Two PRD-promised features are not surfaceable from NLE:

### 5.1 Outside temperature — dropped in v1

NLE's weather proxy (`/nest/weather/v1`) is exclusively on port 8000 for thermostat firmware — not exposed on the Control API. **Outside temperature is removed from Home stats strip and Details grid in v1.**

If a future version adds it, the recommended source is Open-Meteo (no API key) with user-entered zip code, behind a Settings toggle that defaults off.

### 5.2 Daily runtime — dropped in v1

`/api/stats` returns server stats (device counts, subscription health), not HVAC runtime. Verified by live probe against the reference NLE server. **Runtime display is removed from Home stats strip and Details grid in v1.**

Computing runtime client-side is unreliable (20s polling resolution + gaps when backgrounded would produce a misleading number).

---

## 6. Schedule model

### 6.1 Data shape

Schedules are keyed Monday=0..Sunday=6 (note: not JavaScript-standard). Each day has indexed setpoint events. All temperatures are Celsius floats. Schedule writes are **full-replace** — must POST the complete schedule (all 7 days). Partial updates are unsupported.

### 6.2 Dart model

```dart
enum DayOfWeek { mon, tue, wed, thu, fri, sat, sun }   // ordinals = NLE indexes
enum ScheduleType { heat, cool, range }

class ScheduleEvent {
  final Duration timeOfDay;        // since midnight, 0..86399s resolution
  final ScheduleType type;
  final double? tempC;             // present for heat | cool
  final double? tempMinC;          // present for range
  final double? tempMaxC;          // present for range
}

class Schedule {
  final int version;
  final String? name;
  final ScheduleType mode;         // schedule-level mode (HEAT/COOL/RANGE)
  final Map<DayOfWeek, List<ScheduleEvent>> days;
}
```

Display layer handles °C↔°F conversion. UI shows days in locale-appropriate order (Mon-first vs Sun-first) while the model is always Monday=0.

### 6.3 No per-event names

NLE's data model has no name field per event. PRD's "Wake/Away/Sleep" labels are Nest UX convention, not API-backed. **Events are rendered as time + temp** (e.g., "6:00 AM • 68°F").

### 6.4 Repeat-days at creation only

Events are single-day in the data model and the UI. The Edit Event screen does **not** have a repeat-days toggle. The New Event screen has a "Add to multiple days" affordance that clones the event into each selected day at save time. After creation, each day's events are edited independently.

### 6.5 Optimistic schedule saves

1. User edits local schedule model → UI updates immediately.
2. App derives the write's `schedule_mode` from the device's operating mode (§6.6) and coerces any stale event types to it.
3. When the derived mode differs from the device's shared-bucket `schedule_mode` (`Device.scheduleMode` from `/api/devices`), app issues `POST /command set_schedule_mode` first.
4. App serializes full week → `POST /command set_schedule` (wire shape in §6.8).
5. On success → done. The server stores and pushes the bucket to the device's long-poll connection immediately — but the *server* echoing the payload back on `GET /api/schedule` only proves storage, not device acceptance (§6.8).
6. On failure → revert local model + snackbar with retry (retry re-runs steps 3–4; re-sending `set_schedule_mode` is idempotent).

### 6.6 `schedule_mode` field handling

Derived deliberately at save time from the device's operating mode — never preserved-as-loaded or defaulted (the pre-#93 behavior of defaulting to `"HEAT"` made devices in other modes silently ignore the schedule): heat/emergency → `HEAT`, cool → `COOL`, heat-cool → `RANGE`. A device in `off` keeps the stored shared-bucket mode when one is set and capability-valid — and then sends no `set_schedule_mode`; when the stored mode is unset (`null` — the common state, since nothing populates it until this app does) or outside the device's capabilities, the app falls back to a capability-derived mode and does sync it with `set_schedule_mode` (a `null` bucket mode can never match the payload, so skipping the sync would leave the schedule ignored). Event-type pills on Edit Event are constrained to the single type matching the derived mode, and stale events from before a mode switch are coerced at save, so a written payload never contains an event whose `type` contradicts its `schedule_mode` (the device ignores such schedules). Not surfaced in UI in v1.

### 6.7 Empty days

A day with empty events is valid (empty map on the wire, §6.8). PRD's "No events scheduled — tap + to add one" placeholder handles this.

### 6.8 `set_schedule` write contract (Issue #93 live ablation, 2026-07-18)

Gen 2 firmware silently ignores the **entire** schedule bucket unless all of the following hold. The NLE server validates only `time`/`type`/temps and forwards the payload verbatim, so a nonconforming payload still round-trips through `GET /api/schedule` looking healthy:

- `days` values are **maps keyed by string index** (`{"0": ev, "1": ev}`) in time-sorted order — **not arrays**, despite the upstream Control API docs' write example. All seven day keys present; empty day → empty map.
- A top-level **`name`** is present (preserve from the last read, else `"Current Schedule"`).
- Every event carries **`entry_type: "setpoint"`** (`continuation` entries are server-generated; they're dropped on read and never written back).
- The payload's `schedule_mode` matches the shared bucket's `schedule_mode` (synced via `set_schedule_mode`, §6.5–6.6).

### 6.9 Schedule-in-control event highlight (Issue #97)

When the [§9.5](#95-setpoint-source-details-screen) derivation returns `scheduled`, the Schedule screen highlights the **specific event row** that is currently driving the setpoint — the one `findActiveEvent` returns — with a full-strength, type-colored border and glow (`HEAT` → heat red, `COOL` → cool blue; the standard `EmberColors` glow family). Every other state — `manual`, `away`, no schedule loaded, fetch error, or an active `RANGE` event (which §9.5 deliberately never matches in v1; maintainer reaffirmed 2026-07-18) — leaves all rows in their normal (dimmed-border) treatment.

**Why a per-row highlight, not a background wash:** an earlier draft tinted the whole screen background. In practice that was near-invisible whenever the device was in heat/cool mode, because the app-level `EmberBackground` already washes the screen in the same heat-red/cool-blue — tint-on-same-color. The maintainer reversed it (2026-07-18) to a per-event-row highlight, which reads in every mode and points at *which* event is holding, matching how users think about the schedule.

The highlight only appears on the active event's own row, so it shows only while its day is the one being viewed; other days show no highlight. It reuses `deriveSetpointSource` unchanged, keeping the highlight and the Details screen's Scheduled/Manual row in agreement by construction, and the row's border/glow animates on and off with the standard 300ms `easeInOutCubic` idiom (§4.3, §11.4) as the clock crosses into a new event or a poll changes the match. It recomputes on rebuild (each poll, refetch, or provider invalidation); there is no dedicated timer for the crossing instant. Non-visual users get the state through a Semantics label that prepends "Currently active." to the row's announcement.

### 6.10 Schedule header — device name + live temps (Issue #100)

The Schedule screen's header shows **which** thermostat is being scheduled and what it's doing now: the device's resolved display name (`displayNameFor`, §4.4 — local override → server name → `Thermostat (XXXX)`) over a small `Now <measured> • Set <target>` line, both in the device's unit. The "Set" value mirrors the Details screen's `_setpointDisplay` — a heat-cool device with both bounds shows the `low – high` band (the scalar `targetTemperature` is a midpoint/sentinel in that mode), every other mode the single target — so header and Details never disagree. When no `Device` is available (e.g. before first resolution, or in tests) the header falls back to the plain "Schedule" title with no temps. The two-line title's `toolbarHeight` scales with the text scaler so large accessibility fonts grow the header rather than clipping it, and a Semantics label spells the temps out ("Now 77°F, set to 76°F") in place of the middot line.

---

## 7. Setup and auth

### 7.1 Four-screen flow

1. **Welcome** — brief intro, "Connect to your NoLongerEvil server" + Get started button + NLE docs link.
2. **Server Setup** — URL field, "Advanced" expander (auth picker), Connect button.
3. **Device Picker** — only when 2+ devices returned. List with name + serial.
4. **Home** — done.

Onboarding-complete flag set only after URL stored + connection tested + active device chosen. Mid-flow kill resumes at the appropriate step.

### 7.2 Auth UX

The "Advanced" expander is collapsed by default. Reveals an auth-type picker: `None` (default) / `Basic` / `Bearer` / `Cloudflare Access`.

- `None`: no auth headers sent.
- `Basic`: username + password fields → standard `Authorization: Basic <base64>` header.
- `Bearer`: token field → `Authorization: Bearer <token>`.
- `Cloudflare Access`: service-token client-ID + client-secret fields → `CF-Access-Client-Id` + `CF-Access-Client-Secret` header pair (no `Authorization` header).

NLE's self-hosted Control API has **no auth by default**; the auth headers are for users running a reverse proxy (Caddy/nginx) in front of NLE.

The auth choices are **mutually exclusive**. Cloudflare Access authenticates the client to the Cloudflare Access edge in front of the proxy; Cloudflare strips the `CF-Access-Client-*` headers before the request reaches the origin, so the origin sees no auth. Layering Cloudflare Access on top of origin Basic/Bearer is not supported (would require a second header set) — the common NLE-behind-Cloudflare-Tunnel deployment relies on Access as the sole gate.

The model (`AuthConfig` in `lib/models/auth_config.dart`) exposes each choice's contribution as a `Map<String,String> headers` so the HTTP client merges header-based schemes uniformly; `authorizationHeader` remains a convenience accessor (null for `None` and `Cloudflare Access`).

**Redirect handling.** The API client does not follow redirects (a JSON control API never legitimately redirects). A 3xx bearing Cloudflare Access markers (`WWW-Authenticate: Cloudflare-Access`, or a `Location` on `*.cloudflareaccess.com`) — like a 401/403 with the same markers — is classified as a Cloudflare Access gate and the UI points the user at the service-token fields. Any other redirect (a reverse proxy's http→https upgrade, a trailing-slash rewrite) surfaces as its own "server redirected — check the address" error, **not** an auth failure: no credential was rejected, and routing the user to auth settings would misdiagnose an address problem.

**The Cloudflare classification is trusted only for `https` targets.** A real Access deployment always terminates TLS; over plain http the markers are forgeable by anyone on-path, and acting on them would turn the "add a service token" guidance into an elicitation surface for an org-scoped credential the app would then send in cleartext. On http, such responses fall through to the generic auth/redirect copy.

### 7.3 Credential storage

`flutter_secure_storage` for credentials (Keychain on iOS, EncryptedSharedPreferences on Android). Keys:
- `auth_type` (`none` / `basic` / `bearer` / `cf_service_token`)
- `auth_basic_username`
- `auth_basic_password`
- `auth_bearer_token`
- `auth_cf_client_id`
- `auth_cf_client_secret`

Switching auth type clears every credential key before writing the active set, so a secret from a previous type never lingers. `shared_preferences` for everything else (non-secret). See [§12.1](#121-three-tier-persistence).

### 7.4 Test Connection target

`GET /api/devices`. Single round-trip validates: reachability + auth + returns the device list needed for the next setup step.

### 7.5 URL normalization

- Accept `http://hostname[:port]`, `https://hostname[:port]`, `http://ip[:port]`.
- Missing scheme → default `http://`.
- Missing port → **scheme-aware** default: `:8082` for `http` (a direct-LAN NLE server), `:443` for `https` (a reverse proxy / Cloudflare front terminating TLS on the standard port). Forcing `:8082` onto every URL broke `https` deployments behind Cloudflare Access.
- Strip trailing slash for canonical storage.
- Reject malformed input with inline validation.

Examples:
- `nest.home` → `http://nest.home:8082`
- `192.168.1.42` → `http://192.168.1.42:8082`
- `https://nest.example.com` → `https://nest.example.com:443`
- `https://nest.example.com:8443` → `https://nest.example.com:8443`
- `http://nest.home:9000` → `http://nest.home:9000`

### 7.6 Re-edit in Settings

All onboarding fields are editable post-setup in Settings. Re-saving triggers a re-test. Re-test failure keeps the previous working config in place until the new one is confirmed.

---

## 8. Capabilities and temperature units

### 8.1 Server is source of truth for units

Each device's `temperature_scale` field ("C" or "F") is the unit shown on the physical thermostat dial. The app honors that per-device value. **There is no app-level unit toggle in Settings.**

If a user changes the unit on the physical dial, the next polling cycle picks it up and the app re-renders accordingly.

### 8.2 Strict capability gating

NLE returns a `capabilities` block per device (`can_heat`, `can_cool`, `has_fan`, `has_emer_heat`, `has_humidifier`, `has_dehumidifier`). The UI gates strictly on these.

| Capability | UI effect |
|---|---|
| `can_heat = false` | Hide Heat pill, hide Auto pill (auto requires heat) |
| `can_cool = false` | Hide Cool pill, hide Auto pill |
| `has_fan = false` | Omit fan toggle entirely (layout collapses) |
| `has_emer_heat`, `has_humidifier`, `has_dehumidifier` | Ignored in v1; no UI affordances |

Schedule event creation also respects this — when creating a setpoint, the mode picker offers only modes the device supports. Pre-existing schedule events with unsupported modes are displayed as-is with a warning indicator.

---

## 9. Modes, fan, away

### 9.1 Mode pills

| UI label | API value |
|---|---|
| `Off` | `"off"` |
| `Heat` | `"heat"` |
| `Cool` | `"cool"` |
| `Auto` | `"heat-cool"` |

`"emergency"` (aux heat) is **not surfaced in v1** — niche, no PRD requirement.

Command issuance: `POST /command` with `{serial, command: "set_mode", value: <api value>}`.

### 9.2 Status row derivation

Derived from the `hvac` block (current activity), not from `mode` (user intent):

| `mode` | `hvac.heater` | `hvac.ac` | `hvac.fan` | Status text |
|---|---|---|---|---|
| any | true | — | — | "Heating" |
| any | — | true | — | "Cooling" |
| heat / cool / heat-cool | false | false | false | "Idle" |
| heat / cool / heat-cool | false | false | true | "Fan only" |
| off | — | — | true (timer) | "Fan only" |
| off | — | — | false | "Off" |

Pulsing dot color matches mode (orange for heating, blue for cooling, silver for fan-only, dim for idle/off).

### 9.3 Fan toggle

NLE's fan has no "off" state. Setting fan to `"auto"` is the closest equivalent — fan only runs when HVAC needs it. PRD's three-state cycle (On → Auto → Off → On) is replaced with:

- **Tap** toggles between `"auto"` and `"on"` (default 1-hour timer).
- **Long-press** → bottom sheet with duration options: 15 min, 30 min, 1 hour, 2 hours, 4 hours, 8 hours. Selecting a duration issues `set_fan` with the corresponding seconds value.
- **Label states:**
  - Auto: `FAN AUTO`
  - On (timer active): `FAN ON • 0:43`, countdown derived from `fan_timer_timeout`
- **Timer expiry:** next polling cycle reflects `fan_timer_active=false`, UI returns to `FAN AUTO`.

### 9.4 Away mode

Surfaced as an `AWAY` text chip in the home-screen header, below the device name.

- Inactive: chip not shown (or subtle outline).
- Active: chip in Ember-green accent.
- Tap → `POST /command set_away` with the opposite boolean.
- Long-press → bottom sheet for `set_eco_temperatures` (high/low).

No "house" or "leaf" iconography (legal posture). Text-only.

### 9.5 Setpoint source (Details screen)

NLE doesn't have a single "setpoint source" field. Derive client-side:

```
if (device.away) → "Away"
else if (schedule has an active event AND device.target_temperature == active event's temp) → "Scheduled"
else → "Manual"
```

"Active event" = most recent setpoint event before *now* in the weekly schedule, walking back across days if today has no prior event. Computed locally from the loaded schedule.

A small "(Derived)" tooltip on long-press explains the derivation. Fuzziness: a manual set to the exact scheduled value will read "Scheduled." Acceptable v1.

### 9.6 has_leaf, time_to_target

**Deferred to v1.1.** `has_leaf` would be derivative iconography (legal posture); a non-derivative efficiency indicator can be designed later. `time_to_target` is a polish detail.

### 9.7 Mode change semantics

User picks a mode → `POST /command set_mode`. Server validates against capabilities (defense in depth, though UI already gates). Successful → optimistic UI update → reconciliation. Server rejection → revert + snackbar.

Setting `Off` does not clear the schedule — schedule resumes when mode is set back to heat/cool/heat-cool. No special UI surfacing.

---

## 10. Visual identity

### 10.1 Theme: "Ember"

Dark, cinematic, mode-aware. Single dark theme — no light mode in v1. Force-dark regardless of system setting.

Color palette per PRD §4.2 (heat/cool/eco/fan accents, background gradients).

### 10.2 Fan widget — concentric pulsing rings

Replace PRD's three-curved-blade design (legal posture). Three thin concentric rings pulse outward in sequence (1.6s linear infinite) when on. Inactive: dim, no pulse.

Label below: `FAN AUTO` / `FAN ON • 0:43` in JetBrains Mono uppercase.

### 10.3 Temperature dial — segmented ring

A circular ring composed of 60–80 discrete tick marks, progressively filled to indicate target temp. Strong visual differentiation from Nest's continuous-arc dial.

- Diameter: ~240dp.
- Tick stroke: ~3dp.
- Active ticks: mode gradient + `MaskFilter.blur` for glow.
- Inactive ticks: `rgba(255,255,255,0.06)`.
- Current temp shown in italic Instrument Serif below the target.

Ticks light up sequentially on temperature changes for a satisfying animation.

**Heat-cool dual band (Issue #116, ADR-0002).** In `heat-cool` mode with both bounds reported, the dial shows **two** setpoints instead of one:

- **Two markers** — a HEAT (low) and a COOL (high) handle — with the active fill painted **only between them** (not from tick 0), as a **warm→cool gradient** (`heatGradient`-warm at HEAT → `coolGradient`-cool at COOL). Ticks outside the band are inactive.
- **Stacked center readout:** `HEAT` label / value / divider / value / `COOL` label, sized so the pair is ≈ the single-setpoint number's height. The whole stack is one tap target opening the dual-field range dialog (§11.3).
- **Fallback:** a heat-cool device that reports a **null** bound falls back to the single-marker rendering (the neutral grey gradient of §10.3), i.e. today's behavior.

### 10.4 App icon — concentric arcs

Abstract geometric mark: two or three concentric arc segments forming a partial circle, in Ember-orange-to-blue gradient on dark. Recognizable as "thermostat-ish" without referencing Nest. Generated for both platforms via `flutter_launcher_icons`.

### 10.5 Away affordance — `AWAY` text chip

No icon. Pure typography. Sits below the device name in the header. Active = Ember-green tint.

### 10.6 Mode pills

Rounded pills (100dp border radius). Inactive: 1dp border `rgba(255,255,255,0.1)`, 2% white fill, JetBrains Mono uppercase. Active: mode-tinted border + fill + soft outer glow via `BoxShadow`.

### 10.7 Background gradients

Per PRD §4.2. Radial gradient `Container` layers. Mode swap: `AnimatedContainer`, 300ms `easeInOutCubic`.

---

## 11. Rendering specifics

### 11.1 Fonts — bundled assets

Bundle .ttf files for: Fraunces (300, 400, 500), Geist (400, 500, 700), JetBrains Mono (400, 500, 600), Instrument Serif (italic). Declare in `pubspec.yaml`. Use `google_fonts` with `GoogleFonts.config.allowRuntimeFetching = false` for offline guarantees.

### 11.2 Glow effects

- **Outer glows on pills, fan rings, buttons:** `BoxShadow` with large blur radius.
- **Active arc on dial:** `Paint..maskFilter = MaskFilter.blur(BlurStyle.normal, σ)` in `CustomPaint`.
- **Background radial overlays:** layered `Container`s with `RadialGradient` + opacity.
- **`BackdropFilter` avoided** on the home screen — GPU-expensive on Android API 24-26 hardware (minimum supported). Reserve for non-critical surfaces only.

### 11.3 Dial gesture

- `GestureDetector` wrapping the dial with `onPanStart` / `onPanUpdate` / `onPanEnd` and `onTapUp`.
- Angle math: `angle = atan2(dy - center.y, dx - center.x)`, normalized to [0, 2π], mapped to N ticks.
- **Tap-to-jump:** tap a tick → target jumps with 400ms tween.
- **Drag-anywhere:** finger angle from center determines target.
- **Tick-snap haptic:** `HapticFeedback.selectionClick()` per tick crossed, throttled to ≤30/sec.
- **POST debouncing:** issue `set_temperature` only on `onPanEnd` (and at least 250ms of stillness). Optimistic update during drag.
- **Range:** clamp to NLE's 4.5°C–32°C (40°F–90°F). Above/below: ticks light but value stays clamped with a subtle resistance animation.

**Heat-cool dual band (Issue #116, ADR-0002).** The single-target gesture above generalizes to two markers:

- **Grab + push:** the gesture grabs whichever marker is **nearest** the touch (tie → HEAT), resolved once at `onPanStart` and held for the drag. Moving one marker into the **deadband** (a single app-wide **1.5°C ≈ 3°F** constant, `TemperatureDial.deadbandCelsius`, shared with the Schedule Auto editor #102) **shoves the other** to preserve the gap; when the shoved marker hits a 4.5/32°C rail the dragged one stops too. One drag may therefore write **both** bounds. Per-tick selection-click haptics fire on the moving marker.
- **Explicit write:** heat-cool commits POST the explicit `{"low": l, "high": h}` the user set — the pre-#116 nearest-bound heuristic is dropped for the dual path (it survives only for the null-bound fallback).
- **Paired optimistic + reconciliation:** the optimistic override is a `(low, high)` pair; the +1/+3/+7s confirm-watch reconciles **both** bounds (±½-tick each) against the snapshot's `targetTemperatureLow`/`targetTemperatureHigh`, and a POST failure reverts **both**. Both markers tween together (one `_DialBand` tween) so reduced-motion and reconciliation move them in lockstep.
- **Keyboard entry:** tapping the stacked readout opens a **dual-field `RangeEntryDialog`** (Heat + Cool, integer, unit-aware — reuses `TempEntryDialog`'s parse/clamp/°C-°F helpers). The deadband is enforced **in the form**: Set is disabled with an inline error until `heat + 1.5°C ≤ cool`; both values commit together. Single-setpoint modes keep the single `TempEntryDialog`.

### 11.4 Animation specs

| Animation | Mechanism | Duration | Curve |
|---|---|---|---|
| Background gradient mode swap | `AnimatedContainer` | 300ms | `easeInOutCubic` |
| Schedule-in-control event highlight (§6.9) | `AnimatedContainer` | 300ms | `easeInOutCubic` |
| Fan concentric ring pulse | `AnimationController` (repeat) | 1.6s | linear |
| Status dot glow pulse | `AnimationController` (repeat) | 2.5s | `easeInOut` |
| Dial target temp tween | `TweenAnimationBuilder` | 400ms | `easeInOutCubic` |
| Device swap (page swipe) | `PageView` + AnimatedContainer | matches swipe | system |
| Mode pill state change | `AnimatedContainer` | 200ms | `easeOut` |
| "Reconnecting…" pill appearance | `AnimatedSwitcher` | 200ms | `easeOut` |

Long-lived `AnimationController`s (fan, glow pulse) pause on app `paused` lifecycle state.

### 11.5 Haptics

- `HapticFeedback.lightImpact()`: mode pill tap, fan tap, away toggle.
- `HapticFeedback.selectionClick()`: tick-snap during dial drag (throttled).
- `HapticFeedback.mediumImpact()`: schedule save success.

### 11.6 System UI

- Force dark: `MaterialApp(themeMode: ThemeMode.dark, darkTheme: emberTheme)` only. No `theme: lightTheme`.
- Status bar: transparent with light icons.
- Navigation bar (Android): transparent or matching dark.
- Edge-to-edge content with `SafeArea` for interactive elements.

### 11.7 Reduced motion

Check `MediaQuery.disableAnimations`. When true:
- Pause fan ring pulse.
- Pause status dot glow pulse.
- Disable dial tween (snap instead).
- Mode-change gradient transitions still fade (not strictly motion).

---

## 12. Lifecycle and persistence

### 12.1 Three-tier persistence

| Data | Storage |
|---|---|
| `auth_type`, `auth_basic_username`, `auth_basic_password`, `auth_bearer_token`, `auth_cf_client_id`, `auth_cf_client_secret` | `flutter_secure_storage` |
| `server_url`, `active_device_serial`, `device_name_overrides`, `onboarding_complete` | `shared_preferences` |
| `last_state_cache` (JSON), `last_schedule_cache_{serial}` (JSON with timestamp) | `shared_preferences` |

Cache values are JSON-encoded strings inside `shared_preferences`. Small enough that a database is unnecessary.

### 12.2 Cold-start sequence

1. Read `onboarding_complete` and `server_url`.
2. If incomplete → Onboarding flow.
3. If complete + cache exists → render Home immediately with cached state, subtle "Updating…" pill.
4. If complete + no cache → render Home skeleton (faint dial outline, `—` placeholders).
5. Fire `GET /api/devices` in background.
6. On success → hide "Updating…", silently swap to fresh data.
7. On failure → show "Last updated {time-ago} • Retry" banner. Cached state remains visible; controls disabled.

Never show a blank screen if cached data is available.

### 12.3 Lifecycle transitions

`WidgetsBindingObserver` hooks:

| State | Action |
|---|---|
| `inactive` | No-op |
| `paused` | Stop polling timer; save state cache; pause long-lived `AnimationController`s; close in-flight HTTP if possible |
| `resumed` | Show "Updating…" pill; fire immediate `/api/devices` poll; restart 20s cadence; resume animations |
| `detached` | Same as `paused`; best-effort flush |

No background work, no widget, no push, no background isolate. App is fully asleep when not foregrounded.

### 12.4 Stale-state indicator

Two-state model (no graduated thresholds):

- **Fresh** (last successful poll < 60s ago): no indicator.
- **Stale** (poll older than 60s, or actively failing): subtle pill — "Last updated 3 min ago • Retry." Mode pills, dial, fan, away toggle disabled at 40% opacity. Schedule screen still navigable for reading cached data.
- **Active retry**: pill text becomes "Reconnecting…" with subtle spinner.

### 12.5 Writes when stale

**Fail immediately.** Optimistic UI reverts; snackbar "Cannot save — check your connection." No queueing.

### 12.6 Cache invalidation

- Successful poll → overwrite state cache.
- Server URL changed → clear state + schedule cache before testing new URL.
- Auth changed → same.
- Active device changed → no cache clear (cache covers all devices).
- Settings "Disconnect from server" → clear everything (cache, prefs, secure storage), return to Welcome.

### 12.7 Disconnect action

Settings → "Disconnect from server" (destructive style, red text, bottom of Settings). Confirmation dialog → wipe → back to Welcome.

### 12.8 Encrypted config backup/restore

Reinstalls, new devices, and Android signing-key changes wipe local config (at minimum the server URL). Because `flutter_secure_storage` + Android Auto Backup is a known footgun — the encrypted blob backs up but the Keystore key does not, yielding an undecryptable restore — the app offers an **explicit, passphrase-encrypted JSON backup** the user controls. On import the app re-writes credentials into the *new* device's Keystore fresh. See **[ADR-0001](adr/0001-encrypted-config-backup-format.md)** for the envelope format, crypto choices, and forward-compatibility policy — the backup format is a contract and the ADR is its record.

**Scope.** Backed up: `server_url`, all auth (type + credentials from secure storage), `device_name_overrides`, `active_device_serial`, and the two appearance keys (`numeralFont`, `timeFieldPalette`). **Not** backed up: `last_state_cache` (device *state*, not config) and temperature scale (server-driven per [§8.1](#81-server-is-source-of-truth-for-units) — there is no user-owned temp-scale setting; the Issue #109 scope line naming it was corrected). Restore sets `onboarding_complete` so the user lands connected, not back in setup.

**Flows.** Export (Settings → Backup): set a passphrase (confirm + "no recovery if forgotten" warning) → encrypt off the UI thread → write the file to a user-chosen location via the OS save-document dialog (`FlutterFileDialog.saveFile`). Restore (Settings → Backup, and a "Restore from backup" affordance on both onboarding screens — Welcome and Server Setup, since a signing-key blowout can wipe the Keystore credentials while the persisted URL survives, resuming the flow straight on Server Setup and skipping Welcome): pick a file (`FlutterFileDialog.pickFile`) → reject foreign/too-new/damaged files *before* prompting → enter passphrase (re-prompt on wrong) → confirm summary → apply → the host refreshes appearance providers and re-bootstraps to Home. Implementation: `lib/services/backup/` (codec + service) and `lib/settings/backup_flow.dart` (shared UI).

A real filesystem save (choose a folder) is used rather than a share sheet — `share_plus` (kept for the logs screen) can only hand the file to another app, not save it where the user wants. `flutter_file_dialog` supplies both the save and open dialogs via the OS document picker (Android SAF; iOS `UIDocumentPicker`) and, being Android/iOS-only, carries **no `win32` dependency** — sidestepping the `file_picker` (win32 5.x) vs `share_plus` (win32 6.x) conflict that a dependency override couldn't fix (`file_picker`'s Windows Dart code won't compile against win32 6, and `flutter test` compiles every platform's sources). Neither the SAF nor the `UIDocumentPicker` path needs a manifest permission or Info.plist key.

---

## 13. Build and distribution

### 13.1 v1 distribution

GitHub Releases only. `.apk` for Android sideload (signed). iOS distributed as source — README documents the Xcode-build process.

F-Droid is a stretch goal for stable v1.x. Play Store / App Store deferred to later — avoid blocking v1 ship on policy review.

### 13.2 Android signing

- Release keystore (`keystore.jks`) generated locally; backed up to password manager.
- `android/key.properties` (gitignored) provides path + passwords to Gradle.
- Builds: `flutter build apk --release` and `flutter build appbundle --release`.
- Pin Flutter SDK version range in `pubspec.yaml`.

### 13.3 CI/CD

GitHub Actions, free for public repos:

- **On PR:** `flutter analyze`, `flutter test`, `dart format --output=none --set-exit-if-changed .`.
- **On tag push (`vX.Y.Z`):** build signed APK, attach to GitHub Release. Keystore via repo secrets.
- **No iOS in CI** (requires macOS runners + Apple Dev signing). Manual local builds for iOS.

### 13.4 Versioning

- Semver in `pubspec.yaml`: `version: <semver>+<build>` (e.g. `1.0.0+2`).
- **The build number (`+N`) is incremented on any change to the resolved dependency set, i.e. `pubspec.lock`** — the precise record of compiled-in libraries. Every distinct `pubspec.lock` produces a distinct build number, so an installed APK is traceable to the exact libraries it was built from. (A `pubspec.yaml` edit that does not change `pubspec.lock` — e.g. loosening a constraint, or the SDK/description fields — ships identical libraries and needs no bump.) This is enforced by the `dependency-build-bump` CI job.
- The marketing version (`1.0.0`) follows semver and changes on feature/fix releases, independent of the build number.
- Git tags: `v1.0.0`. The release tag-match check in `release.yml` compares only the marketing version, so build-number bumps never affect tagging.
- `CHANGELOG.md` updated per release.

### 13.5 License

**MIT.**

### 13.6 Time entry — hour/minute text fields

Not platform-adaptive, and not a wheel. PRD's "native iOS/Android time wheel" is overridden in favor of direct text entry: two Ember-themed numeric fields (hour, minute) with an AM/PM selector shown only in 12-hour mode (`MediaQueryData.alwaysUse24HourFormat` is the format source). Out-of-range or empty input disables Save with an inline error — never silently clamped. This supersedes the earlier custom wheel picker (`EmberTimePicker`), removed in Issue #96; the maintainer reversed that decision in favor of faster direct entry.

### 13.7 Icons and splash

- `flutter_launcher_icons` — generate app icon assets for both platforms from a single 1024×1024 source.
- `flutter_native_splash` — generate `LaunchScreen.storyboard` (iOS) + drawable resources (Android) with Ember dark background.

### 13.8 iOS parity notes

Things needing platform-specific attention:
- Status bar overlay: set explicitly via `SystemUiOverlayStyle.light`.
- Pull-to-refresh: `RefreshIndicator` with bouncing physics on iOS.
- Back navigation: every screen has an explicit back affordance (no reliance on Android system back).
- Out of v1 scope: iOS widgets, Siri/Shortcuts, iCloud sync.

---

## 14. Testing

### 14.1 API client style

Hand-written `NleApiClient` with hand-written models. No codegen from the OpenAPI spec. Reason: small surface (~10 endpoints), custom transforms needed (°C↔display, schedule day-key Monday=0 to typed enum).

### 14.2 Testing pyramid

| Layer | Coverage approach |
|---|---|
| Unit (heavy) | `NleApiClient` (mock HTTP), schedule serialization, status-row derivation, setpoint-source derivation, °C/°F conversion, time-of-week math, polling controller with `fake_async` |
| Widget (medium) | Smoke tests per screen — mode variants, onboarding flow, schedule, edit event. Verify key text/widgets present, taps fire expected callbacks |
| Integration (light) | Optional: one happy-path flow against mocked `DeviceStateSource` |
| Golden tests | **Skip in v1.** Revisit if visual regressions become a pattern |

### 14.3 Tooling

- `flutter_test` for unit + widget.
- `mocktail` for mocks (null-safe, no codegen).
- `fake_async` for time-based polling tests.
- `http_mock_adapter` for `dio` HTTP responses.

### 14.4 Test fixtures

Real JSON responses captured against the live NLE server, stored in `test/fixtures/`:

- `device_idle.json`, `device_heating.json`, `device_cooling.json`
- `device_fan_timer.json`, `device_away.json`
- `device_heat_only.json` (capability-restricted)
- `schedule_full.json`, `schedule_empty.json`
- `devices_two.json` (multi-device)

Hand-curated, not synthesized.

### 14.5 Accessibility

Required work (per PRD §7):

- `Semantics` widgets on all interactive elements.
- Dial uses `Semantics(label, value, increased: ..., decreased: ...)` to expose screen-reader gestures for ± adjustment without the visual ring.
- Mode pills, fan toggle, away chip get clear labels.
- Color is never the sole signal — text labels carry meaning.
- Touch targets ≥ 48dp. Away chip and any small icons padded to meet minimum.
- `MediaQuery.textScaleFactor` honored, capped via `clampTextScaleFactor(0.85, 1.4)` to prevent dial blowout.
- Reduced motion handled per [§11.7](#117-reduced-motion).
- Contrast: dark theme passes AA broadly; review 0.4-opacity tertiary text case by case.

Verification: manual TalkBack (Android) + VoiceOver (iOS) walkthrough on real devices before release. Not in CI.

---

## 15. Edge cases, logging, privacy, i18n

### 15.1 Error behavior

| Scenario | Behavior |
|---|---|
| Network drops mid-command | 1 retry with 2s backoff; on second failure, fail with snackbar + retry. Optimistic UI reverts. |
| Device offline (`is_available=false`) | Subtle overlay on that device's home screen. Writes disabled. Cached reads visible. |
| Schedule push fails (4xx/5xx) | Full revert + snackbar "Couldn't save schedule. Retry?" |
| Malformed/unexpected JSON | Log to diagnostic buffer; show generic "Unexpected response" with retry. Don't crash. |
| Auth failure (401/403) | Snackbar "Authentication failed" → tap → Settings with auth section expanded. |
| Rate limit (429) | Respect `Retry-After` if present; else back off 30s. Status pill "Server busy — retrying." |
| Server restart mid-poll | Standard "Cannot reach server" path with retry. Next poll cycle reconnects. |

### 15.2 Diagnostic logging

In-memory ring buffer, last 500 entries. Captures HTTP request/response summaries (URLs, status codes, **never credentials**), lifecycle events, command issuances, errors. Accessible via Settings → "View logs" → "Copy to clipboard" / "Share." Not persisted. Cleared on app kill.

### 15.3 No analytics, no remote crash reporting

Privacy-by-default. The audience self-hosts firmware to avoid Google's data collection — they will be hostile to telemetry. Bug reports happen via GitHub Issues with attached logs from [§15.2](#152-diagnostic-logging).

### 15.4 Internationalization

Set up `flutter_localizations` + `app_en.arb` at launch. Ship English. All user-facing strings extracted to .arb. Locale-aware day-of-week display (Mon-first vs Sun-first), locale-aware time formatting (12h vs 24h). Temperature unit is server-driven (independent of locale).

Future languages: community PRs.

---

## 16. NLE API reference

Documentation: https://docs.nolongerevil.com (sitemap at `/llms.txt`, OpenAPI at `/api-reference/openapi.json`).
Source fallback: https://github.com/codykociemba/NoLongerEvil-Thermostat.

### 16.1 Surface used by this app

The **Control API on port 8082**. The V1 API (`/api/v1/*`) is for the hosted service. The thermostat protocol (port 8000) is not for client use.

### 16.2 Authentication

No auth by default. Server passes through `Authorization` headers unchanged from a reverse proxy. App supports optional Basic, Bearer, or Cloudflare Access service-token auth per [§7.2](#72-auth-ux). Cloudflare Access sends the `CF-Access-Client-Id` / `CF-Access-Client-Secret` header pair (no `Authorization` header) to authenticate the client to the Cloudflare Access edge in front of the proxy.

### 16.3 Endpoints used

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/devices` | All devices' full state in one response (primary poll endpoint) |
| GET | `/status?serial=X` | Single-device state (for explicit per-device refresh if needed) |
| GET | `/api/schedule?serial=X` | Current schedule for a device |
| GET | `/health` | Server health check (not used in setup — `/api/devices` does that job) |
| POST | `/command` | All write actions; body `{serial, command, value}` |

### 16.4 `/command` actions used

| `command` | `value` shape |
|---|---|
| `set_temperature` | number (°C) or `{"high": number, "low": number}` for heat-cool |
| `set_mode` | `"off"` / `"heat"` / `"cool"` / `"heat-cool"` (`"emergency"` not used) |
| `set_away` | boolean |
| `set_fan` | `"auto"` / `"on"` / number (seconds) |
| `set_eco_temperatures` | `{"high": number, "low": number}` |
| `set_schedule` | full schedule object — wire contract in [§6.8](#68-set_schedule-write-contract-issue-93-live-ablation-2026-07-18) |
| `set_schedule_mode` | bare mode string `"HEAT"` / `"COOL"` / `"RANGE"` — must match the written schedule's `schedule_mode` (§6.5) |

### 16.5 Load-bearing facts

- **All temperatures in the API are Celsius floats.** Range 4.5–32°C. Conversion to display unit happens at the UI boundary using the per-device `temperature_scale`.
- **`/api/devices` returns all devices in one response.** Use this as the polling endpoint, not per-device `/status`.
- **Schedules are keyed Monday=0..Sunday=6.** Not JS-standard.
- **Schedule writes are full-replace.** No partial updates supported.
- **The server accepts schedule payloads the firmware ignores.** `GET /api/schedule` echoing a write back proves storage, not device acceptance — conform to §6.8 exactly.
- **`/api/stats` is server stats** (subscription counts, availability) — not HVAC runtime. Daily runtime is unavailable from NLE.
- **Weather is on port 8000 only** for thermostats. Outside temperature is unavailable for clients.
- **SSE exists at `/api/events`** but is not used in v1 (architectural seam preserved).

---

## 17. Open items for implementation

These need live-server validation during build, not pre-resolved here:

1. **`/api/devices` field optionality** — confirm which fields are *actually* always present vs documented-as-guaranteed-but-sometimes-missing. Capture an exhaustive fixture set.
2. **Schedule write round-trip** — does the server normalize the schedule on `set_schedule`? If yes, display the normalized version after a successful write, not the user's input.
3. **`set_fan "on"` behavior with no prior duration** — what duration does the server use if `"on"` is the first command after server start? Probe and document.
4. **Reverse-proxy auth pass-through** — verify with an actual Caddy/nginx in front, including 401 surfacing.
5. **Polling cadence in practice** — 20s + (1/3/7)s reconciliation needs real-world validation. Tune after a few days of live use; constants live in one file.

---

## 18. PRD divergences

Where this document deviates from `PRD.md` literal text:

| PRD section | Divergence |
|---|---|
| §4.5 Fan toggle | Concentric pulsing rings, not three blades. No "Off" state — fan is Auto or On-with-timer. |
| §4.5 Mode pills | Conditional on capabilities, not always four. |
| §5.5 Edit Event | No per-event name field; no repeat-days circles on Edit Event (creation-only repeat). |
| §5.6 Settings | No temperature unit toggle (server is source of truth). |
| §5.2, §5.3 Stats | No outside temp slot; no runtime slot. |
| §5.5 Time picker | Hour/minute text inputs (12/24h-aware), not a platform-native wheel — nor the custom wheel this row previously recorded. |
| §7 App icon | Concentric arcs, not "silver fan blade or stylized flame." |
| §9 Q1 (auth) | Resolved: no auth default, optional reverse-proxy Basic/Bearer. |
| §9 Q4 (weather) | Resolved: NLE doesn't expose weather to clients; feature dropped. |
| §9 Q6 (runtime) | Resolved: not in `/api/stats`; feature dropped. |
| §9 Q7 (push) | SSE exists but polling-only v1 with architectural seam. |

The PRD remains the product-intent reference and should be read for goals and audience. This document is the engineering reference for *how* v1 is built.
