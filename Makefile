APP_NAME = PolinShield
BUNDLE_ID = dev.polinshield.app
VERSION = 1.0.0

BUILD_DIR = .build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
DMG = $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg

.PHONY: all build app dmg clean run install

all: app

build:
	@echo "→ Building Swift release..."
	swift build -c release --arch arm64 --arch x86_64 2>&1 | tail -20

app: build
	@echo "→ Assembling .app bundle..."
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources/scripts
	@cp .build/apple/Products/Release/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	@chmod +x $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp Resources/scripts/*.sh $(APP_BUNDLE)/Contents/Resources/scripts/
	@chmod +x $(APP_BUNDLE)/Contents/Resources/scripts/*.sh
	@cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist 2>/dev/null || $(MAKE) gen-plist
	@codesign --force --deep --sign - $(APP_BUNDLE) 2>&1 | grep -v "replacing existing" || true
	@echo "✓ Built: $(APP_BUNDLE)"
	@du -sh $(APP_BUNDLE)

gen-plist:
	@cat > $(APP_BUNDLE)/Contents/Info.plist <<EOF
	<?xml version="1.0" encoding="UTF-8"?>\
	<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\
	<plist version="1.0"><dict>\
	<key>CFBundleName</key><string>$(APP_NAME)</string>\
	<key>CFBundleIdentifier</key><string>$(BUNDLE_ID)</string>\
	<key>CFBundleVersion</key><string>$(VERSION)</string>\
	<key>CFBundleShortVersionString</key><string>$(VERSION)</string>\
	<key>CFBundleExecutable</key><string>$(APP_NAME)</string>\
	<key>CFBundlePackageType</key><string>APPL</string>\
	<key>LSMinimumSystemVersion</key><string>13.0</string>\
	<key>LSUIElement</key><true/>\
	<key>NSUserNotificationsUsageDescription</key><string>Show malware detection alerts.</string>\
	</dict></plist>\
	EOF

dmg: app
	@echo "→ Building DMG..."
	@rm -f $(DMG)
	@mkdir -p $(BUILD_DIR)/dmg-staging
	@cp -R $(APP_BUNDLE) $(BUILD_DIR)/dmg-staging/
	@ln -s /Applications $(BUILD_DIR)/dmg-staging/Applications
	@hdiutil create -volname "$(APP_NAME) $(VERSION)" -srcfolder $(BUILD_DIR)/dmg-staging -ov -format UDZO $(DMG) >/dev/null
	@rm -rf $(BUILD_DIR)/dmg-staging
	@echo "✓ Built: $(DMG)"
	@du -sh $(DMG)

install: app
	@echo "→ Installing to /Applications..."
	@rm -rf /Applications/$(APP_NAME).app
	@cp -R $(APP_BUNDLE) /Applications/
	@open /Applications/$(APP_NAME).app
	@echo "✓ Installed and launched"

run: app
	@open $(APP_BUNDLE)

clean:
	rm -rf $(BUILD_DIR) .swiftpm
	swift package clean
