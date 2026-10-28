PREFIX ?= /Applications
APP = Hyperlayer.app
BUNDLE_ID = com.royxue.hyperlayer
BIN ?= .build/release/Hyperlayer

.PHONY: build universal app zip icon install uninstall clean

# Regenerate Resources/AppIcon.icns after changing Resources/mark-source.png.
icon:
	@mkdir -p .build
	swiftc -O scripts/make-icon.swift -o .build/make-icon
	.build/make-icon

build:
	swift build -c release

# Build each architecture separately and merge. Passing both --arch flags at once goes
# through the Xcode build system, which fails on older Xcode versions in CI.
universal:
	swift build -c release --arch arm64
	swift build -c release --arch x86_64
	@mkdir -p .build/universal
	lipo -create -output .build/universal/Hyperlayer \
		.build/arm64-apple-macosx/release/Hyperlayer .build/x86_64-apple-macosx/release/Hyperlayer

# Bundles $(BIN) into $(APP). Set VERSION to stamp Info.plist (used by the release workflow).
app: $(if $(filter .build/release/Hyperlayer,$(BIN)),build)
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@cp $(BIN) $(APP)/Contents/MacOS/Hyperlayer
	@cp Info.plist $(APP)/Contents/
	@cp Resources/AppIcon.icns Resources/MenuBarIcon*.png $(APP)/Contents/Resources/
	@if [ -n "$(VERSION)" ]; then \
		/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" \
			-c "Set :CFBundleVersion $(VERSION)" $(APP)/Contents/Info.plist; fi
	@codesign -f -s - --identifier $(BUNDLE_ID) $(APP)
	@echo "Built $(APP)"

zip: app
	@rm -f Hyperlayer.zip
	@ditto -c -k --keepParent $(APP) Hyperlayer.zip
	@echo "Built Hyperlayer.zip"

# Each ad-hoc build has a new code hash, so the old Accessibility grant no longer
# matches. Reset it so macOS prompts again instead of showing a stale "on" toggle.
install: app
	@pkill -x Hyperlayer 2>/dev/null; sleep 0.5; true
	@tccutil reset Accessibility $(BUNDLE_ID) >/dev/null 2>&1 || true
	@rm -rf "$(PREFIX)/$(APP)"
	@cp -R $(APP) "$(PREFIX)/$(APP)"
	@rm -rf $(APP)
	@open "$(PREFIX)/$(APP)"
	@echo "Installed and launched $(PREFIX)/$(APP)"

uninstall:
	@pkill -x Hyperlayer 2>/dev/null; sleep 0.5; true
	@rm -rf "$(PREFIX)/$(APP)"
	@tccutil reset Accessibility $(BUNDLE_ID) >/dev/null 2>&1 || true
	@echo "Uninstalled"

clean:
	swift package clean
	@rm -rf $(APP)
