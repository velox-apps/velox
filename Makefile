all:
	(cd runtime-wry-ffi; cargo build)
	swift build

test: all
	swift test
	swift build -c release
