# Bundling

Package Velox apps for distribution, with macOS bundle, signing, DMG, and notarization support.

## Overview

Velox can build a macOS `.app` bundle directly from `velox.json` and the CLI. Use the `bundle`
configuration to control packaging, optional code signing, DMG creation, and notarization.

## Quick Start

From your app directory (where `velox.json` lives):

```bash
velox build --bundle
```

Or set `bundle.active: true` in `velox.json` to enable bundling without the flag.

## Bundle Configuration (macOS)

Add a `bundle` section to `velox.json`:

```json
{
  "bundle": {
    "active": true,
    "targets": ["app", "dmg"],
    "icon": "icons/AppIcon.icns",
    "resources": ["extra-assets"],
    "macos": {
      "minimumSystemVersion": "13.0",
      "infoPlist": "Info.plist",
      "entitlements": "entitlements.plist",
      "signingIdentity": "Developer ID Application: Example (ABCDE12345)",
      "hardenedRuntime": true,
      "dmg": {
        "enabled": true,
        "name": "MyApp",
        "volumeName": "MyApp"
      },
      "notarization": {
        "keychainProfile": "AC_NOTARY",
        "wait": true,
        "staple": true
      }
    }
  }
}
```

### Field Notes

- `bundle.targets`: Use `app` for `.app` bundles and `dmg` for disk images.
- `bundle.icon`: On macOS, use an `.icns` file. The filename is stored in `CFBundleIconFile`.
- `bundle.resources`: Extra files or folders copied into `Contents/Resources`.
- `bundle.macos.infoPlist`: Merges into the generated Info.plist (values override defaults).
- `bundle.macos.entitlements`: Passed to `codesign --entitlements`.
- `bundle.macos.signingIdentity`: Enables code signing.
- `bundle.macos.hardenedRuntime`: Adds `--options runtime` to `codesign`.
- `bundle.macos.notarization`: Uses `xcrun notarytool` and optional stapling.

## Outputs

For a release build, bundles are created under:

```
.build/release/<Product>.app
.build/release/<Product>.dmg (optional)
```

## Makefile Helpers

From the repo root:

```bash
make bundle
```

For signed DMGs and notarization:

```bash
SIGNING_IDENTITY="Developer ID Application: Example (ABCDE12345)" \
NOTARY_KEYCHAIN_PROFILE="AC_NOTARY" \
make dmg
```

### Placeholders

- `SIGNING_IDENTITY`: Your Developer ID Application identity.
- `NOTARY_KEYCHAIN_PROFILE`: Keychain profile name for `notarytool`.
- `NOTARY_APPLE_ID` / `NOTARY_TEAM_ID` / `NOTARY_PASSWORD`: Alternative to `NOTARY_KEYCHAIN_PROFILE`.
- `ENTITLEMENTS`: Optional entitlements plist.
- `DMG_NAME` / `DMG_VOLUME_NAME`: Optional DMG naming overrides.

## Signing and Notarization

Velox uses standard Apple tooling:

- Code signing: `/usr/bin/codesign`
- Notarization: `/usr/bin/xcrun notarytool`
- Stapling: `/usr/bin/xcrun stapler`

If you use `notarization.keychainProfile`, run:

```bash
xcrun notarytool store-credentials AC_NOTARY --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PASSWORD
```

## Troubleshooting

If the Rust FFI library is missing during `velox build`:

- Make sure you are building from the project directory so the Rust build plugin runs.
- Ensure `cargo` is installed and available in `PATH`.

If the app fails to launch after signing, verify entitlements and re-run codesign with `--verbose`.
