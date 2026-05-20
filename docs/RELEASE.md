# Release process

This repo ships Android releases via GitHub Actions on git tag push. Tagging `vX.Y.Z` triggers `.github/workflows/release.yml`, which builds a signed APK and attaches it to a GitHub Release.

iOS is not in CI (per `docs/DESIGN.md` §13.3) — built locally via Xcode and attached manually if needed.

## One-time signing setup (maintainer)

The release workflow needs four repo secrets. Until they're configured, the workflow will fail at the keystore-decode step.

### 1. Generate the release keystore

Run locally (anywhere you trust — the file is sensitive):

```sh
keytool -genkey -v \
  -keystore keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

`keytool` prompts for:

- **Keystore password** — for the `.jks` file itself.
- **Key password** — for the key entry. Conventionally the same as the keystore password.
- **Distinguished name fields** (CN, O, etc.) — any reasonable values; the public APK includes them.

**Back up `keystore.jks` and both passwords to a password manager immediately.** If this key is lost, future releases cannot be signed with the same identity and existing installs cannot be upgraded in place — users would have to uninstall + reinstall.

The `-alias` value (`upload` above) is the **key alias**; remember it.

### 2. Base64-encode the keystore for the secret

On macOS:

```sh
base64 -i keystore.jks | pbcopy
```

On Linux:

```sh
base64 -w 0 keystore.jks | xclip -selection clipboard
```

(Or `base64 keystore.jks > keystore.b64` and copy the contents.)

### 3. Add repo secrets

In **Settings → Secrets and variables → Actions → New repository secret**, add:

| Secret name         | Value                                                        |
| ------------------- | ------------------------------------------------------------ |
| `KEYSTORE_BASE64`   | Base64-encoded contents of `keystore.jks` (from step 2).     |
| `KEYSTORE_PASSWORD` | The keystore password from step 1.                           |
| `KEY_PASSWORD`      | The key password from step 1.                                |
| `KEY_ALIAS`         | The alias from `keytool -alias` (e.g. `upload`).             |

The workflow generates `android/key.properties` from these at build time. `android/key.properties` and `*.jks` are gitignored (`.gitignore` enforces this).

## Cutting a release

1. **Bump `pubspec.yaml`** — update `version: X.Y.Z+N`. Semver before the `+`; build number after. Commit on `main`.
2. **(Optional) Update `CHANGELOG.md`** — add a `## [X.Y.Z] - YYYY-MM-DD` section. The release workflow extracts the matching section for the GitHub Release body. Without `CHANGELOG.md`, the body falls back to `Release vX.Y.Z`.
3. **Tag and push:**

   ```sh
   git tag v1.0.0
   git push origin v1.0.0
   ```

4. **Watch the workflow** under **Actions → Release**. On success, the GitHub Release at `v1.0.0` will have `app-release.apk` attached.

The workflow guards against tag/`pubspec.yaml` mismatch and fails fast if they disagree.

## Dry-run procedure

To exercise the workflow without cutting a real public release:

```sh
git tag v0.0.0-test
git push origin v0.0.0-test
```

**Note:** the tag-vs-pubspec version check will fail (`0.0.0-test` won't match `pubspec.yaml`). To bypass for a dry-run, either:

- Temporarily set `pubspec.yaml` to `version: 0.0.0-test+1` on a throwaway branch, tag from that branch, then revert. **Or**
- Comment out the verification step in `release.yml` on a throwaway branch and tag from there.

After the dry-run finishes, clean up:

```sh
# Delete the local + remote tag
git tag -d v0.0.0-test
git push origin :refs/tags/v0.0.0-test

# Delete the draft/published Release via the GH UI or:
gh release delete v0.0.0-test --yes
```

## Switching to App Bundle (Play Store route, future)

If the project ever submits to Play Store, swap one line in `.github/workflows/release.yml`:

```yaml
- run: flutter build apk --release          # current
- run: flutter build appbundle --release    # AAB instead
```

…and update the upload step's `files:` path to `build/app/outputs/bundle/release/app-release.aab`. APK shipping should continue alongside for sideload users; the workflow can build both in sequence and upload both artifacts.

## License

Released artifacts are MIT-licensed per `docs/DESIGN.md` §13.5.
