PREFIX ?= /Applications
APP = Hyperlayer.app
BUNDLE_ID = com.royxue.hyperlayer

.PHONY: build app install uninstall clean

build:
	swift build -c release

app: build
	@rm -rf $(APP)
	@mkdir -p $(APP)/Contents/MacOS
	@cp .build/release/Hyperlayer $(APP)/Contents/MacOS/
	@cp Info.plist $(APP)/Contents/
	@codesign -f -s - --identifier $(BUNDLE_ID) $(APP)
	@echo "Built $(APP)"

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
