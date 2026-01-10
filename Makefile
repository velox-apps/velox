ROOT_DIR := $(CURDIR)
VELOX_BIN := $(ROOT_DIR)/.build/debug/velox
HELLOWORLD_DIR := $(ROOT_DIR)/Examples/HelloWorld
HELLOWORLD_TARGET := HelloWorld

# Placeholders for make dmg:
# SIGNING_IDENTITY="Developer ID Application: Example (ABCDE12345)"
# NOTARY_KEYCHAIN_PROFILE="AC_NOTARY" (or use NOTARY_APPLE_ID/NOTARY_TEAM_ID/NOTARY_PASSWORD)
# ENTITLEMENTS="entitlements.plist" (optional)
# HARDENED_RUNTIME="true" (optional)
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
	./scripts/bundle_helloworld.sh bundle

dmg: build-velox
	./scripts/bundle_helloworld.sh dmg
