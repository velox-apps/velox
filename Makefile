ROOT_DIR := $(CURDIR)
VELOX_BIN := $(ROOT_DIR)/.build/debug/velox
HELLOWORLD_DIR := $(ROOT_DIR)/Examples/HelloWorld
HELLOWORLD_TARGET := HelloWorld

# Placeholders for make dmg:
# SIGNING_IDENTITY="Developer ID Application: Example (ABCDE12345)"
# NOTARY_KEYCHAIN_PROFILE="AC_NOTARY" (or use NOTARY_APPLE_ID/NOTARY_TEAM_ID/NOTARY_PASSWORD)
# ENTITLEMENTS="entitlements.plist" (optional)
# DMG_NAME="HelloWorld" (optional)
# DMG_VOLUME_NAME="HelloWorld" (optional)

all:
	(cd runtime-wry-ffi; cargo build)
	swift build

test: all
	swift test
	swift build -c release

.PHONY: bundle dmg build-velox

build-velox:
	swift build --product velox

bundle: build-velox
	cd $(HELLOWORLD_DIR) && $(VELOX_BIN) build $(HELLOWORLD_TARGET) --bundle

dmg: build-velox
	cd $(HELLOWORLD_DIR) && \
	  if [ -z "$$SIGNING_IDENTITY" ]; then \
	    echo "SIGNING_IDENTITY is required"; exit 1; \
	  fi; \
	  if [ -z "$$NOTARY_KEYCHAIN_PROFILE" ] && \
	     { [ -z "$$NOTARY_APPLE_ID" ] || [ -z "$$NOTARY_TEAM_ID" ] || [ -z "$$NOTARY_PASSWORD" ]; }; then \
	    echo "Set NOTARY_KEYCHAIN_PROFILE or NOTARY_APPLE_ID/NOTARY_TEAM_ID/NOTARY_PASSWORD"; exit 1; \
	  fi; \
	  entitlements_line=""; \
	  if [ -n "$$ENTITLEMENTS" ]; then \
	    entitlements_line="      \\\"entitlements\\\": \\\"$$ENTITLEMENTS\\\","; \
	  fi; \
	  if [ -n "$$NOTARY_KEYCHAIN_PROFILE" ]; then \
	    notarization_block="      \\\"notarization\\\": {\\\"keychainProfile\\\": \\\"$$NOTARY_KEYCHAIN_PROFILE\\\", \\\"wait\\\": true, \\\"staple\\\": true}"; \
	  else \
	    notarization_block="      \\\"notarization\\\": {\\\"appleId\\\": \\\"$$NOTARY_APPLE_ID\\\", \\\"teamId\\\": \\\"$$NOTARY_TEAM_ID\\\", \\\"password\\\": \\\"$$NOTARY_PASSWORD\\\", \\\"wait\\\": true, \\\"staple\\\": true}"; \
	  fi; \
	  trap 'rm -f velox.macos.json' EXIT; \
	  cat > velox.macos.json <<EOF
{
  "bundle": {
    "targets": ["app", "dmg"],
    "macos": {
      "signingIdentity": "$$SIGNING_IDENTITY",
      "hardenedRuntime": true,
$$entitlements_line
      "dmg": {
        "enabled": true,
        "name": "$${DMG_NAME:-HelloWorld}",
        "volumeName": "$${DMG_VOLUME_NAME:-HelloWorld}"
      },
$$notarization_block
    }
  }
}
EOF
	  $(VELOX_BIN) build $(HELLOWORLD_TARGET) --bundle
