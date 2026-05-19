# Building Rest Thermostat for iOS

Rest Thermostat ships pre-built `.apk`s on
[GitHub Releases](https://github.com/MikeSiekkinen/RestThermostat/releases)
for Android. iOS is distributed as **source only** — there are no IPAs or
TestFlight builds. You will build and sign the app yourself.

This is intentional: a Mac, Xcode, and an Apple ID are required to install
any iOS app outside the App Store, and the maintainers do not run a paid
Apple Developer Program account for distribution. See
[`docs/DESIGN.md` §13.1](DESIGN.md) for the rationale.

---

## Prerequisites

- **A Mac.** macOS 13 (Ventura) or newer is recommended.
- **Xcode 14 or newer** from the Mac App Store. After install, open Xcode
  once to accept the license and let it install additional components.
- **Xcode Command Line Tools:** `xcode-select --install`.
- **CocoaPods:** `sudo gem install cocoapods` (or via Homebrew:
  `brew install cocoapods`).
- **Flutter SDK** matching the range pinned in
  [`pubspec.yaml`](../pubspec.yaml) (currently `>=3.24.0 <4.0.0`). Install
  via the [official Flutter instructions](https://docs.flutter.dev/get-started/install/macos).
  Verify with `flutter doctor` — every iOS-related row should be green.
- **An iPhone or iPad** running a recent iOS version, plus a USB-C / Lightning
  cable. The iOS Simulator also works for trying the app out, but you
  cannot install simulator builds onto a physical device.
- **An Apple ID.** A free Apple ID is sufficient for personal sideloading;
  no paid Apple Developer Program membership is required for the 7-day
  signing path described below.

---

## One-time setup

### 1. Clone the repository

```sh
git clone https://github.com/MikeSiekkinen/RestThermostat.git
cd RestThermostat
```

### 2. Install Flutter dependencies

```sh
flutter pub get
```

### 3. Install CocoaPods dependencies

```sh
cd ios
pod install
cd ..
```

If `pod install` fails, see [Gotchas](#gotchas) below.

### 4. Open the project in Xcode (first run only)

```sh
open ios/Runner.xcworkspace
```

> Open `.xcworkspace`, **not** `.xcodeproj`. Pods only resolve from the
> workspace.

In Xcode:

1. Select the **Runner** target in the project navigator.
2. Go to **Signing & Capabilities**.
3. Set **Team** to your personal Apple ID. If your Apple ID is not listed,
   click **Add an Account…** under Xcode → Settings → Accounts and sign in.
4. Change the **Bundle Identifier** to something unique to you, e.g.
   `com.yourname.restthermostat`. The default identifier is reserved for
   the upstream project and Apple's free signing tier rejects duplicates.
5. Xcode will automatically provision a free development certificate and a
   matching provisioning profile. You should see a green check next to
   "Provisioning Profile: Xcode Managed Profile".

Close Xcode when done.

---

## Running on a connected device

1. Plug your iPhone or iPad into the Mac with a cable.
2. On the device, accept the "Trust This Computer" prompt.
3. From the repo root:
   ```sh
   flutter devices
   ```
   You should see your device listed. If it shows
   "[unsupported]", you may need to enable Developer Mode on iOS 16+:
   **Settings → Privacy & Security → Developer Mode → On** (the device
   will prompt you to reboot).
4. Run a release build onto the device:
   ```sh
   flutter run --release
   ```
   First launch may take several minutes while Xcode compiles and signs.

After the build is installed, you may also need to trust the developer
profile on the device: **Settings → General → VPN & Device Management →
[your Apple ID] → Trust**.

---

## The 7-day expiry (free signing tier)

Apps signed with a free Apple ID expire after **7 days**. After that, the
app icon stays on your home screen but launching it shows "Unable to
verify app".

You have a few options:

- **Re-run `flutter run --release` weekly.** Free, requires the Mac and
  cable each time.
- **AltStore** (recommended for hands-off renewal). Install
  [AltStore](https://altstore.io/) on your Mac and iOS device, side-load
  the `.ipa` produced by
  `flutter build ipa --release --export-method=development`, and AltStore
  will refresh the signature every ~7 days in the background while your
  device is on the same Wi-Fi as the Mac running AltServer.
- **Sideloadly** is a similar tool with comparable functionality.
- **Apple Developer Program** ($99/year). Apps signed with a paid team
  certificate are valid for 1 year, and you unlock TestFlight (which
  lets you distribute builds to up to 10,000 testers via App Store
  Connect). Rest Thermostat does not provide official TestFlight builds.

---

## Running in the iOS Simulator

The Simulator is the fastest way to try the app on iOS without a device:

```sh
open -a Simulator
flutter run -d "iPhone 15"  # or whichever device is booted
```

Note that Simulator builds cannot be installed on a physical iPhone, and
some features (haptics, the real network stack against a LAN-hosted NLE
server) will behave differently from a device.

---

## Gotchas

### `pod install` fails

- **`[!] CDN: trunk URL couldn't be downloaded`** — your CocoaPods spec
  repo is stale. Run `pod repo update` and retry. On a fresh install you
  may also need `pod setup`.
- **`[!] CocoaPods could not find compatible versions for pod ...`** —
  delete `ios/Podfile.lock` and `ios/Pods/`, then re-run `pod install`.
  Make sure your Flutter SDK is on a version inside the
  `pubspec.yaml`-pinned range.
- **Apple Silicon (M1/M2/M3) issues** — if CocoaPods or `pod install`
  errors out with ffi or native-extension build failures, run under
  Rosetta once with `arch -x86_64 pod install`.

### "Signing for 'Runner' requires a development team"

You skipped step 4 of the one-time setup. Open
`ios/Runner.xcworkspace` in Xcode and set Team + Bundle Identifier on the
Runner target.

### "Untrusted Developer" on the device

You installed the app but iOS won't launch it. Go to **Settings → General
→ VPN & Device Management**, find your Apple ID under "Developer App",
and tap **Trust**.

### Free signing limits

A free Apple ID allows up to **3 app IDs registered at a time** and **10
provisioning profile renewals per 7 days**. If you hit these limits,
delete unused app IDs from <https://developer.apple.com/account/resources/>
or wait out the renewal window.

### Build hangs at "Running Xcode build…"

Usually a slow first-time Pods compile. Watch
`flutter run --verbose` for actual progress, or open the project in Xcode
and run from there to see the full build log.

### iOS 16+ "Developer Mode" required

If `flutter devices` shows the device as unsupported, enable Developer
Mode (see step 3 of "Running on a connected device" above).

---

## Going further

- For Android sideloading, see the
  [Installation section of the README](../README.md#installation).
- For overall architecture, state management, and design decisions, see
  [`docs/DESIGN.md`](DESIGN.md).
- For product scope and audience, see [`docs/PRD.md`](PRD.md).

If you hit a problem not covered here, please file an issue at
<https://github.com/MikeSiekkinen/RestThermostat/issues> with the output
of `flutter doctor -v` and the failing command.
