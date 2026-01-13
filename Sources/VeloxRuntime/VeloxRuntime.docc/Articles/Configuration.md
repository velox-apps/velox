# Configuration

Configure your Velox application with velox.json.

## Overview

The `velox.json` file is the central configuration for your Velox application. It defines your app's identity, window settings, build configuration, and security policies.

## Basic Configuration

```json
{
    "productName": "MyApp",
    "version": "1.0.0",
    "identifier": "com.example.myapp",
    "app": {
        "windows": [{
            "label": "main",
            "title": "My Application",
            "width": 800,
            "height": 600,
            "url": "app://localhost/"
        }]
    }
}
```

## Configuration Reference

### Root Properties

| Property | Type | Description |
|----------|------|-------------|
| `productName` | String | Display name of your application |
| `version` | String | Semantic version (e.g., "1.0.0") |
| `identifier` | String | Reverse-domain bundle identifier |
| `app` | Object | Application configuration |
| `build` | Object | Build and development settings |
| `bundle` | Object | Bundle and distribution settings |
| `security` | Object | Security policies |

### App Configuration

```json
{
    "app": {
        "windows": [...],
        "macOS": {
            "activationPolicy": "regular"
        }
    }
}
```

#### Window Configuration

```json
{
    "windows": [{
        "label": "main",
        "title": "Window Title",
        "width": 800,
        "height": 600,
        "minWidth": 400,
        "minHeight": 300,
        "maxWidth": 1920,
        "maxHeight": 1080,
        "x": 100,
        "y": 100,
        "url": "app://localhost/",
        "visible": true,
        "resizable": true,
        "devtools": true,
        "fullscreen": false,
        "decorations": true,
        "transparent": false,
        "alwaysOnTop": false,
        "create": true
    }]
}
```

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `label` | String | Required | Unique identifier for the window |
| `title` | String | `productName` | Window title bar text |
| `width` | Number | 800 | Initial width in pixels |
| `height` | Number | 600 | Initial height in pixels |
| `minWidth` | Number | - | Minimum width constraint |
| `minHeight` | Number | - | Minimum height constraint |
| `maxWidth` | Number | - | Maximum width constraint |
| `maxHeight` | Number | - | Maximum height constraint |
| `x` | Number | Centered | Initial X position |
| `y` | Number | Centered | Initial Y position |
| `url` | String | `app://localhost/` | URL to load in the webview |
| `visible` | Boolean | `true` | Whether window starts visible |
| `resizable` | Boolean | `true` | Whether window can be resized |
| `devtools` | Boolean | Debug: `true`, Release: `false` | Enable WebView devtools (inspector) |
| `fullscreen` | Boolean | `false` | Whether to start in fullscreen |
| `decorations` | Boolean | `true` | Show window chrome (title bar, borders) |
| `transparent` | Boolean | `false` | Enable transparent background |
| `alwaysOnTop` | Boolean | `false` | Keep window above others |
| `create` | Boolean | `true` | Create window on app start |

On macOS, enabling devtools uses private WebKit APIs, so avoid setting `devtools: true` in release builds.

#### macOS Configuration

```json
{
    "macOS": {
        "activationPolicy": "regular"
    }
}
```

| Property | Type | Values | Description |
|----------|------|--------|-------------|
| `activationPolicy` | String | `regular`, `accessory`, `prohibited` | How app appears in Dock |

- `regular`: Normal app with Dock icon
- `accessory`: Background app, no Dock icon
- `prohibited`: Cannot be activated

### Build Configuration

```json
{
    "build": {
        "devUrl": "http://localhost:5173",
        "beforeDevCommand": "npm run dev",
        "beforeBuildCommand": "npm run build",
        "beforeBundleCommand": "npm run prepare",
        "frontendDist": "dist",
        "env": {
            "API_URL": "https://api.example.com"
        }
    }
}
```

| Property | Type | Description |
|----------|------|-------------|
| `devUrl` | String | Development server URL (enables proxy mode) |
| `beforeDevCommand` | String | Command to run before `velox dev` |
| `beforeBuildCommand` | String | Command to run before `velox build` |
| `beforeBundleCommand` | String | Command to run before bundling |
| `frontendDist` | String | Directory containing frontend assets |
| `env` | Object | Environment variables for builds |

### Bundle Configuration (macOS)

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

| Property | Type | Description |
|----------|------|-------------|
| `active` | Bool | Enable bundling without `--bundle` |
| `targets` | Array | Bundle targets (`app`, `dmg`) |
| `icon` | String/Array | Path(s) to icon files (macOS expects `.icns`) |
| `resources` | Array | Extra files or folders to copy into `Contents/Resources` |
| `macos.minimumSystemVersion` | String | `LSMinimumSystemVersion` override |
| `macos.infoPlist` | String | Path to a plist to merge into the generated Info.plist |
| `macos.entitlements` | String | Entitlements file for code signing |
| `macos.signingIdentity` | String | Code signing identity |
| `macos.hardenedRuntime` | Bool | Enable hardened runtime for code signing |
| `macos.dmg.enabled` | Bool | Create a DMG |
| `macos.dmg.name` | String | DMG filename (without extension) |
| `macos.dmg.volumeName` | String | DMG volume name |
| `macos.notarization.keychainProfile` | String | notarytool keychain profile |
| `macos.notarization.appleId` | String | notarytool Apple ID (if no keychain profile) |
| `macos.notarization.teamId` | String | notarytool team ID |
| `macos.notarization.password` | String | notarytool app-specific password |
| `macos.notarization.wait` | Bool | Wait for notarization to complete |
| `macos.notarization.staple` | Bool | Staple the notarization ticket |

See <doc:Bundling> for packaging, signing, DMG, and notarization steps.

### Security Configuration

```json
{
    "security": {
        "csp": {
            "default-src": "'self'",
            "script-src": "'self' 'unsafe-inline'",
            "style-src": "'self' 'unsafe-inline'",
            "img-src": "'self' data: https:"
        },
        "dangerousDisableAssetCspModification": false
    }
}
```

#### Content Security Policy (CSP)

Define CSP directives to control resource loading:

```json
{
    "csp": {
        "default-src": "'self'",
        "script-src": "'self'",
        "style-src": "'self' 'unsafe-inline'",
        "img-src": "'self' data: blob:",
        "font-src": "'self'",
        "connect-src": "'self' https://api.example.com"
    }
}
```

## Environment Variables

Velox loads environment variables from multiple sources:

1. `.env` — Base environment file
2. `.env.development` / `.env.production` — Mode-specific
3. `.env.local` — Local overrides (gitignored)
4. `velox.json build.env` — Configuration-defined

Priority (highest to lowest):
```
System environment
    ↓
velox.json build.env
    ↓
.env.local
    ↓
.env.development / .env.production
    ↓
.env
```

Example `.env` file:
```
API_URL=https://api.example.com
DEBUG=true
# Comments are supported
MULTILINE="line1\nline2"
```

## Platform Overrides

Create platform-specific configuration files:

- `velox.macos.json` — macOS overrides
- `velox.ios.json` — iOS overrides

These files use JSON Merge Patch (RFC 7396) to override the base `velox.json`:

```json
// velox.macos.json
{
    "app": {
        "windows": [{
            "label": "main",
            "width": 1024,
            "height": 768
        }]
    }
}
```

## Development Modes

### Local Asset Serving

For simple projects without a build step:

```json
{
    "build": {
        "frontendDist": "assets"
    }
}
```

Files are served directly from the `assets` directory.

### Dev Server Proxy

For modern frontend tooling (Vite, webpack):

```json
{
    "build": {
        "devUrl": "http://localhost:5173",
        "beforeDevCommand": "npm run dev",
        "frontendDist": "dist"
    }
}
```

The `app://` protocol proxies requests to your dev server, enabling HMR.

## Complete Example

```json
{
    "$schema": "https://velox.dev/schema/velox.schema.json",
    "productName": "My Velox App",
    "version": "1.0.0",
    "identifier": "com.example.myveloxapp",
    "app": {
        "windows": [
            {
                "label": "main",
                "title": "My Velox App",
                "width": 1024,
                "height": 768,
                "minWidth": 640,
                "minHeight": 480,
                "url": "app://localhost/",
                "resizable": true
            },
            {
                "label": "settings",
                "title": "Settings",
                "width": 400,
                "height": 500,
                "url": "app://localhost/settings.html",
                "resizable": false,
                "create": false
            }
        ],
        "macOS": {
            "activationPolicy": "regular"
        }
    },
    "build": {
        "devUrl": "http://localhost:5173",
        "beforeDevCommand": "npm run dev",
        "beforeBuildCommand": "npm run build",
        "frontendDist": "dist",
        "env": {
            "API_URL": "https://api.example.com"
        }
    },
    "security": {
        "csp": {
            "default-src": "'self'",
            "script-src": "'self'",
            "connect-src": "'self' https://api.example.com"
        }
    }
}
```

## See Also

- <doc:GettingStarted>
- <doc:VeloxArchitecture>
