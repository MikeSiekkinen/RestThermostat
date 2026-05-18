# Rest Thermostat — Product Requirements Document

> A community-built mobile app for the NoLongerEvil thermostat firmware, restoring smart control to deprecated Nest Learning Thermostats (Gen 1 & 2).

---

## 1. Project Overview

### 1.1 Background
Google ended support for first- and second-generation Nest Learning Thermostats in October 2025, removing remote control and cloud features. The open-source **NoLongerEvil (NLE)** project provides replacement firmware that intercepts the Nest device's communication layer and reroutes it to a self-hosted server. Currently, users can only control their devices via a web-based PWA. No native mobile app exists.

**Rest Thermostat** is a Flutter-based mobile app (Android primary, iOS via free portability) that talks directly to the user's self-hosted NLE server via its REST API. The name is a play on REST (the API technology) and rhymes with "Nest" without using the trademark.

### 1.2 Goals
- Provide a polished native mobile experience for NLE users
- Support all core NLE thermostat functionality (temp, mode, fan, schedule, away)
- Look intentionally designed — premium dark "Ember" aesthetic with mode-aware glow
- Be openly released to the NLE community (open source, GitHub)
- Ship cross-platform from a single codebase

### 1.3 Non-Goals (v1)
- Voice assistant integration (Alexa, Google Assistant)
- Multi-thermostat support beyond what NLE natively provides
- Home Assistant integration (NLE already provides this directly)
- Geofencing or location-based automation
- Energy reporting / analytics dashboards
- Notifications / push alerts
- User accounts or multi-user permissions

---

## 2. References & Resources

### 2.1 NoLongerEvil Project
- **Documentation**: https://docs.nolongerevil.com
- **Self-hosted prerequisites**: https://docs.nolongerevil.com/self-hosted/prerequisites
- **Self-hosted installation**: https://docs.nolongerevil.com/self-hosted/installation
- **API reference**: https://docs.nolongerevil.com/api-reference
- **Docker image**: `ghcr.io/codykociemba/nolongerevil-selfhosted:latest`

### 2.2 API Endpoints (from NLE API reference)
The self-hosted NLE server exposes these endpoints. Claude Code: confirm exact paths and request/response shapes against the live docs at https://docs.nolongerevil.com/api-reference before implementing.

| Endpoint Function | Notes |
|---|---|
| Authentication | API key / token model — verify in docs |
| List devices | Returns device IDs for thermostat selection |
| Get device status | Current temp, target temp, mode, humidity, runtime |
| Set temperature | Single target temp |
| Set HVAC mode | heat / cool / auto / off |
| Set temperature range | Used in auto mode (low / high bounds) |
| Set away mode | Boolean toggle, may have eco target temp |
| Control fan | on / auto / off |
| Set temperature lock | Prevents manual changes at the device |
| Get schedule | Retrieve current schedule |
| Update schedule | Replace or modify schedule |

### 2.3 Fallback Source of Truth
The NLE docs have had reported inconsistencies. If anything is ambiguous, check the open-source server code in the NLE GitHub repo (search "NoLongerEvil" on GitHub for the official repository) as ground truth, particularly the `server/` directory.

### 2.4 Visual Mockups
Five reference screens have been designed in HTML. The implementation should match their aesthetic intent (Ember dark theme, mode-aware glow, Fraunces serif for temps, JetBrains Mono for labels):
- Heating main screen (warm orange glow, spinning fan icon on)
- Cooling main screen (blue glow, fan auto)
- Details screen (technical readouts, humidity / outside / runtime / system status)
- Schedule overview (day tabs, event list)
- Edit event (temp picker, mode/time/repeat form)

---

## 3. Technical Stack

### 3.1 Required
- **Framework**: Flutter (latest stable)
- **Language**: Dart
- **Min Android SDK**: 24 (Android 7.0) — covers >95% of active devices
- **Min iOS**: 14.0
- **State management**: Riverpod (preferred for testability and Claude Code familiarity) or Provider
- **HTTP**: `dio` package (better error handling than stock `http`)
- **Persistence**: `shared_preferences` for settings; no database needed

### 3.2 Architecture
- Layered: `models/` → `services/` (API client) → `providers/` (state) → `screens/` (UI) → `widgets/` (shared components)
- Single API service class encapsulating all NLE endpoints
- Strongly-typed models for device, schedule, schedule event
- Settings persist locally only — no cloud sync

### 3.3 Network Configuration
- Server URL is **fully user-configurable** (set on first launch, editable in settings)
- Default expectation: user has set up local DNS pointing `nest.home` (or similar) to their server IP
- Support both `http://` and `https://` schemes
- Support custom ports
- No port forwarding required — app works on local network only by default
- Reasonable timeouts (5s connect, 10s read), with retry on transient failures

---

## 4. Visual Design System

### 4.1 Aesthetic: "Ember"
Dark, cinematic, atmospheric. Premium feel. Cozy at night. The glow color signals the active HVAC mode at a glance.

### 4.2 Color Palette

**Backgrounds (radial gradients)**
- Heat mode: `#1a0a1a` → `#050108` → `#000000`, with a warm orange glow overlay
- Cool mode: `#0a1424` → `#02060c` → `#000000`, with a cool blue glow overlay
- Neutral (off/auto): `#0d0d12` → `#050507` → `#000000`

**Accent — Heat**
- Primary glow: `#ff6432`
- Gradient: `#ff8a50` → `#ff4516`
- Text on heat: gradient from `#ffffff` to `#ffb89a`

**Accent — Cool**
- Primary glow: `#50aaff`
- Gradient: `#80c8ff` → `#3070d0`
- Text on cool: gradient from `#ffffff` to `#a8d4ff`

**Accent — Eco/Away**: `#4ade80` (green)

**Fan (silver)**
- Active: gradient `#ffffff` → `#d8dee8` → `#8a91a0`, with subtle blue-white glow
- Inactive: gradient `#9aa0ac` → `#5a5e68`, no glow

**Text**
- Primary: `#ffffff`
- Secondary: `rgba(255,255,255,0.6)`
- Tertiary: `rgba(255,255,255,0.4)`
- Disabled: `rgba(255,255,255,0.3)`

### 4.3 Typography
- **Display (temperatures, screen titles)**: Fraunces — serif, weights 300-500
- **Body**: Geist — sans-serif
- **Mono (labels, status, technical readouts)**: JetBrains Mono — weights 400-600
- **Accents (subtitles, italic flourishes)**: Instrument Serif — italic

All Google Fonts. Use the `google_fonts` Flutter package.

### 4.4 Motion
- Glow rings: subtle pulse on status indicators (2.5s ease-in-out)
- Fan icon: 1.6s linear infinite rotation when "on"
- Mode switches: 300ms color/glow transition on background and accents
- Temperature changes: animated number tween, ~400ms
- All easing: prefer `Curves.easeInOutCubic` for transitions; linear for the fan

### 4.5 Component Specs

**Temperature Dial (main screen)**
- Circular ring, ~240dp diameter
- Background track: `rgba(255,255,255,0.06)`, 1dp stroke
- Active arc: mode gradient, 8dp stroke, rounded line caps
- Drop shadow / glow filter on the active arc
- Tap and drag along ring to set target temp
- Tap +/- buttons (optional) for fine adjustment

**Fan Toggle**
- 52dp circle, top-right of heating/cooling screens
- Silver gradient base (see palette)
- Three curved blades + center hub SVG (or `CustomPaint`)
- When on: spins continuously, glowing outline
- When auto: dim, no spin, label says "Fan Auto"
- When off: dim, no spin, label says "Fan Off"
- Small uppercase mono label below ("FAN ON", "FAN AUTO", "FAN OFF")
- Tap cycles On → Auto → Off → On

**Mode Pills**
- Rounded pills (100dp border radius)
- Inactive: 1dp border `rgba(255,255,255,0.1)`, 2% white fill, mono uppercase text
- Active: mode-tinted border and fill, mode-colored text, soft outer glow

---

## 5. Functional Requirements

### 5.1 First Launch / Onboarding
- Setup screen asks for:
  - Server URL (e.g., `http://nest.home:8000`)
  - API key / auth token (whatever NLE requires — verify against docs)
- Test connection button — pings the server, validates response
- "Continue" enabled only after successful test
- All inputs editable later in Settings

### 5.2 Home Screen (Heating or Cooling mode)
- Status row: pulsing dot + current state ("Heating" / "Cooling" / "Idle"), device name
- Fan toggle (top-right) — see component spec
- Temperature dial (center) showing target temp prominently, current temp below in italic
- Stats strip: humidity, outside temp, today's runtime
- Mode pills: Heat / Cool / Auto / Off
- Bottom nav: Home / Schedule / Details

Background gradient and glow color update to match active mode.

### 5.3 Details Screen
- Larger data grid: humidity (with comfort label), outside temp (with conditions), runtime (with % of day), current setpoint with source ("manual" / "scheduled" / "away")
- System info block: status, server URL/IP, NLE firmware version, last sync time
- Read-only — purely informational

### 5.4 Schedule Screen
- Day-of-week tab strip (M T W T F S S) — tapping shows that day's events
- List of events for selected day, each showing time, name (e.g., "Wake", "Away", "Sleep"), and target temp
- Color-coded by mode: heat (orange), cool (blue), eco/away (green)
- "+" button (top-right) opens Edit Event screen for a new event
- Tapping any event opens Edit Event screen pre-populated

### 5.5 Edit Event Screen
- Event name (text input)
- Target temperature picker: large display with +/- buttons
- Time picker (native iOS/Android time wheel)
- Mode selector (heat / cool / auto)
- Repeat day circles (M T W T F S S) — tap to toggle each day
- Cancel / Save buttons in header
- "Delete Event" link at bottom (with confirmation, only for existing events)

### 5.6 Settings Screen
- Server URL (editable)
- API key (editable, masked by default with reveal toggle)
- Temperature unit (°F / °C)
- Test connection button
- App version footer
- Link to NLE project (https://docs.nolongerevil.com)

### 5.7 Away Mode
- Accessible from home screen (small icon or via long-press / overflow)
- Toggle on/off
- Optional: set away temp (if NLE API supports it)

---

## 6. Error Handling & States

### 6.1 Connection States
- **Connecting** (first load): skeleton loader on dial and stats
- **Connected**: normal operation
- **Disconnected**: banner at top "Cannot reach server" with retry button; cached last-known values shown dimmed
- **Auth failed**: prompt to re-enter API key

### 6.2 Empty / Error States
- No schedule events for a day: friendly placeholder ("No events scheduled — tap + to add one")
- API error on save: snackbar with error message and retry
- Invalid input (e.g., temp out of range): inline validation, prevent save

---

## 7. Quality & Polish Requirements

- All temperature changes optimistically update UI, then reconcile with server response
- Pull-to-refresh on home and details screens
- Haptic feedback on mode/fan toggles (light impact)
- No janky animations — target 60fps
- Respect system dark mode (app is always dark — no light mode in v1)
- Accessibility: all interactive elements have semantic labels, support TalkBack/VoiceOver
- App icon: simple, recognizable — silver fan blade or stylized flame on dark background

---

## 8. Deliverables

### 8.1 v1 Definition of Done
- Functional Flutter app running on Android (primary) and iOS (parity verified)
- All five core screens implemented per mockups: Home (heat & cool), Details, Schedule, Edit Event, Settings
- Connects to a user-provided NLE server, performs all listed API operations
- Onboarding flow validates connection
- README in repo covers: project description, setup instructions, NLE server requirement, screenshots
- MIT or Apache 2.0 license
- Ready for sideload distribution (`.apk` build); App Store / Play Store submission optional in v1

### 8.2 Repository Structure (suggested)
```
rest_thermostat/
├── lib/
│   ├── main.dart
│   ├── models/
│   │   ├── device.dart
│   │   ├── schedule_event.dart
│   │   └── ...
│   ├── services/
│   │   └── nle_api_client.dart
│   ├── providers/
│   ├── screens/
│   │   ├── onboarding/
│   │   ├── home/
│   │   ├── details/
│   │   ├── schedule/
│   │   └── settings/
│   ├── widgets/
│   │   ├── temperature_dial.dart
│   │   ├── fan_toggle.dart
│   │   ├── mode_pills.dart
│   │   └── ...
│   └── theme/
│       ├── ember_theme.dart
│       └── colors.dart
├── android/
├── ios/
├── assets/
├── pubspec.yaml
└── README.md
```

---

## 9. Open Questions for Implementation

These items need confirmation against live NLE docs/source before or during implementation:

1. **Authentication model** — Bearer token? Static API key? Where to send it (header / query param)?
2. **Exact endpoint paths and HTTP verbs** for each operation listed in 2.2
3. **Response shape** for `get device status` — what fields are guaranteed to be present?
4. **Outside temperature source** — does NLE proxy a weather API, or should the app integrate something like OpenWeatherMap directly? (The NLE server reportedly returns a `weather_url` — verify what it serves.)
5. **Schedule data model** — how does NLE represent recurring events? Per-day arrays? Cron-style?
6. **HVAC runtime tracking** — is this returned by the API, or does the app need to compute it from state transitions?
7. **WebSocket / SSE support** — does NLE push state changes, or does the app need to poll? If polling, what's a reasonable interval (15s? 30s?)
8. **Temperature lock** — what UX surface should expose this? Settings only, or a quick action?

Claude Code: when starting implementation, fetch the live API docs first and answer these questions. Implement a stub `NleApiClient` interface so the rest of the app can be built and tested while details firm up.

---

## 10. Branding Notes

- **App name**: Rest Thermostat
- **Tagline candidate**: "Your thermostat. Your server. Your control."
- **No use of "Nest" or "Google" trademarks anywhere in the app, listings, or marketing**
- README and store listing can describe the app as "for NoLongerEvil firmware" or "for Cody Kociemba's NoLongerEvil project"
- Credit the NLE project prominently in app About screen and README
