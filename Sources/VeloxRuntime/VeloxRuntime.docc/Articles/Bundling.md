# Bundling

Package Velox apps for distribution on macOS and Linux.

## Overview

Velox can create platform-native packages directly from your project. On macOS, it produces `.app`
bundles with optional code signing, DMG creation, and notarization. On Linux, it produces `.deb`
packages with FreeDesktop integration (`.desktop` files and icon installation).

Run `velox bundle` from your project directory (where `velox.json` lives) to create a package
for the current platform:

```bash
velox bundle
```

You can also trigger bundling from the build command with `velox build --bundle`, or set
`bundle.active: true` in `velox.json` to always bundle after a release build.

## Bundle Configuration

The `bundle` section of `velox.json` controls packaging for all platforms. Platform-specific
settings live under `macos` and `linux` sub-objects.

### Common Settings

These fields apply on every platform:

| Field | Description |
|-------|-------------|
| `active` | Enable bundling automatically on every build |
| `targets` | Array of bundle formats to create (see below) |
| `publisher` | Author or organization name for package metadata |
| `icon` | Path(s) to icon files — string or array of strings |
| `resources` | Additional files or folders to include in the package |

### Bundle Targets

The `targets` array controls which package formats to produce:

| Target | Platform | Description |
|--------|----------|-------------|
| `app` | macOS | Standard `.app` bundle |
| `dmg` | macOS | Disk image containing the `.app` bundle |
| `deb` | Linux | Debian package (`.deb`) |
| `appimage` | Linux | AppImage portable executable (planned) |

If `targets` is omitted, Velox defaults to `app` on macOS and `deb` on Linux.

## macOS Bundling

### Configuration

```json
{
  "productName": "MyApp",
  "version": "1.0.0",
  "identifier": "com.example.myapp",
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

### macOS Settings Reference

| Field | Description |
|-------|-------------|
| `minimumSystemVersion` | Minimum macOS version (default: `"13.0"`) — sets `LSMinimumSystemVersion` |
| `infoPlist` | Path to a custom Info.plist to merge into the generated one |
| `entitlements` | Path to entitlements plist for code signing |
| `signingIdentity` | Code signing identity (e.g., `"Developer ID Application: ..."`) |
| `hardenedRuntime` | Enable hardened runtime (`codesign --options runtime`) |
| `dmg.enabled` | Create a DMG disk image |
| `dmg.name` | DMG filename (without `.dmg` extension) |
| `dmg.volumeName` | Volume name shown when the DMG is mounted |

### App Bundle Structure

Velox creates a standard macOS app bundle:

```
MyApp.app/
└── Contents/
    ├── Info.plist
    ├── MacOS/
    │   └── myapp              ← executable
    └── Resources/
        ├── velox.json
        ├── AppIcon.icns
        ├── [frontend dist]    ← if build.frontendDist is set
        └── [extra resources]
```

The `Info.plist` is generated from your `velox.json` configuration. If you provide a custom
plist via `macos.infoPlist`, its values are merged into the generated one (custom values win).

### Code Signing

When `signingIdentity` is set, Velox signs the bundle using `/usr/bin/codesign`:

```bash
codesign --force --sign "Developer ID Application: ..." \
  --options runtime \               # if hardenedRuntime is true
  --entitlements entitlements.plist \  # if entitlements is set
  --timestamp \
  MyApp.app
```

### Notarization

Velox uses Apple's `notarytool` for notarization. Configure credentials using either a
keychain profile (recommended) or direct credentials.

**Setting up a keychain profile** (one-time setup):

```bash
xcrun notarytool store-credentials AC_NOTARY \
  --apple-id you@example.com \
  --team-id TEAMID \
  --password APP_SPECIFIC_PASSWORD
```

Then reference it in `velox.json`:

```json
{
  "bundle": {
    "macos": {
      "notarization": {
        "keychainProfile": "AC_NOTARY"
      }
    }
  }
}
```

**Direct credentials** (useful for CI):

```json
{
  "bundle": {
    "macos": {
      "notarization": {
        "appleId": "you@example.com",
        "teamId": "TEAMID",
        "password": "$APP_SPECIFIC_PASSWORD"
      }
    }
  }
}
```

After notarization, Velox staples the ticket to the bundle so users can verify offline.

## Linux Bundling

### Configuration

```json
{
  "productName": "MyApp",
  "version": "1.0.0",
  "identifier": "com.example.myapp",
  "bundle": {
    "active": true,
    "targets": ["deb"],
    "publisher": "Your Name <you@example.com>",
    "icon": [
      "icons/32x32.png",
      "icons/128x128.png",
      "icons/256x256.png"
    ],
    "linux": {
      "shortDescription": "A desktop app built with Velox",
      "longDescription": "MyApp is a cross-platform desktop application\nbuilt using Swift and web technologies.",
      "section": "utils",
      "depends": ["libwebkit2gtk-4.1-0", "libgtk-3-0"],
      "categories": ["Utility"],
      "mimeTypes": ["text/plain"]
    }
  }
}
```

### Linux Settings Reference

| Field | Description |
|-------|-------------|
| `shortDescription` | One-line summary (used in Debian `Description` and `.desktop` `Comment`) |
| `longDescription` | Multi-line description (indented in Debian control file) |
| `section` | Debian archive section (e.g., `"utils"`, `"devel"`, `"net"`) |
| `priority` | Package priority (default: `"optional"`) |
| `depends` | List of Debian package dependencies |
| `categories` | FreeDesktop.org categories for the `.desktop` file |
| `desktopTemplate` | Path to a custom `.desktop` file template |
| `mimeTypes` | MIME types the application can open |

### Debian Package Structure

The `.deb` package installs files following standard Linux conventions:

```
/usr/
├── bin/
│   └── myapp                     ← executable
├── lib/myapp/
│   ├── velox.json
│   ├── [frontend dist]
│   └── [extra resources]
└── share/
    ├── applications/
    │   └── myapp.desktop         ← FreeDesktop desktop entry
    └── icons/hicolor/
        ├── 32x32/apps/myapp.png
        ├── 128x128/apps/myapp.png
        └── 256x256/apps/myapp.png
```

### Desktop Entry

Velox generates a `.desktop` file following the
[FreeDesktop Desktop Entry Specification](https://specifications.freedesktop.org/desktop-entry-spec/latest/).
The generated file looks like:

```ini
[Desktop Entry]
Type=Application
Name=MyApp
Exec=myapp
Icon=myapp
Terminal=false
StartupWMClass=myapp
Categories=Utility;
Comment=A desktop app built with Velox
```

To use a custom `.desktop` file instead, set `linux.desktopTemplate` to its path.

### Icons

Provide PNG icons at multiple sizes for sharp rendering across different display densities.
Velox reads the PNG dimensions automatically and installs each icon into the correct
`hicolor` theme directory:

```json
{
  "bundle": {
    "icon": [
      "icons/32x32.png",
      "icons/128x128.png",
      "icons/256x256.png"
    ]
  }
}
```

Icons are installed to `usr/share/icons/hicolor/<width>x<height>/apps/<package-name>.png`.

### Dependencies

Most Velox apps on Linux need WebKit2GTK and GTK. Declare these as package dependencies
so the package manager installs them automatically:

```json
{
  "bundle": {
    "linux": {
      "depends": [
        "libwebkit2gtk-4.1-0",
        "libgtk-3-0",
        "libayatana-appindicator3-1"
      ]
    }
  }
}
```

## CLI Reference

### Basic Usage

```bash
# Bundle for the current platform (release build)
velox bundle

# Bundle in debug mode
velox bundle --debug

# Skip building, use existing artifacts
velox bundle --no-build

# Verbose output
velox bundle --verbose
```

### macOS CLI Overrides

```bash
# Create a signed DMG
velox bundle --dmg \
  --signing-identity "Developer ID Application: Example (ABCDE12345)" \
  --hardened-runtime

# Notarize with a keychain profile
velox bundle --dmg \
  --signing-identity "Developer ID Application: Example (ABCDE12345)" \
  --notary-keychain-profile "AC_NOTARY"

# Notarize with direct credentials
velox bundle --dmg \
  --notary-apple-id you@example.com \
  --notary-team-id TEAMID \
  --notary-password "$APP_SPECIFIC_PASSWORD"

# Custom DMG naming
velox bundle --dmg --dmg-name "MyApp-Installer" --dmg-volume-name "MyApp"
```

### Environment Variable Overrides

These environment variables override `velox.json` settings:

| Variable | Overrides |
|----------|-----------|
| `SIGNING_IDENTITY` | `macos.signingIdentity` |
| `ENTITLEMENTS` | `macos.entitlements` |
| `HARDENED_RUNTIME` | `macos.hardenedRuntime` |
| `NOTARY_KEYCHAIN_PROFILE` | `macos.notarization.keychainProfile` |
| `NOTARY_APPLE_ID` | `macos.notarization.appleId` |
| `NOTARY_TEAM_ID` | `macos.notarization.teamId` |
| `NOTARY_PASSWORD` | `macos.notarization.password` |
| `DMG_ENABLED` | `macos.dmg.enabled` |
| `DMG_NAME` | `macos.dmg.name` |
| `DMG_VOLUME_NAME` | `macos.dmg.volumeName` |

## Output Locations

Bundles are created under the build directory:

```
# macOS
.build/release/MyApp.app
.build/release/MyApp.dmg

# Linux
.build/release/myapp_1.0.0_amd64.deb
```

## Build Hooks

Two hooks run during the bundle process if configured in `velox.json`:

```json
{
  "build": {
    "beforeBuildCommand": "npm run build",
    "beforeBundleCommand": "echo 'Bundling...'"
  }
}
```

- `beforeBuildCommand` runs before `swift build`
- `beforeBundleCommand` runs after the build but before packaging

## Troubleshooting

### Rust FFI library missing

If `velox build` fails to find the Rust FFI library:

- Build from the project directory so the Rust build plugin runs.
- Ensure `cargo` is installed and available in `PATH`.
- Set `VELOX_CARGO_ONLINE=1` if building for the first time (allows cargo to fetch dependencies).

### macOS: App fails to launch after signing

Verify your entitlements and re-run codesign with `--verbose`:

```bash
codesign --verify --verbose=4 MyApp.app
```

### Linux: dpkg-deb not found

Install `dpkg-dev`:

```bash
sudo apt-get install dpkg-dev
```

### Linux: Missing runtime libraries

If the app fails to launch on a target system, ensure the WebKit2GTK and GTK libraries
are installed. Add them to `linux.depends` so the package manager handles this automatically.
