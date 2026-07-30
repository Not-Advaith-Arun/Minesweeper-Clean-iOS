.PHONY: generate test test-extended test-ios validate open clean

SIMULATOR ?= platform=iOS Simulator,name=iPhone 16 Pro

generate:
	@command -v xcodegen >/dev/null || { echo "Install XcodeGen: brew install xcodegen"; exit 1; }
	xcodegen generate

test:
	swift test

test-extended:
	MINESWEEPER_EXTENDED_TESTS=1 swift test -c release

test-ios: generate
	@command -v xcodebuild >/dev/null || { echo "Xcode and the iOS Simulator are required (macOS only)."; exit 1; }
	xcodebuild -project Minesweeper.xcodeproj -scheme Minesweeper -destination '$(SIMULATOR)' test

validate: test
	swiftc -frontend -parse MinesweeperApp/*.swift MinesweeperUITests/*.swift

open: generate
	open Minesweeper.xcodeproj

clean:
	rm -rf .build DerivedData build
