.PHONY: run build clean bundle install run-app

APP_NAME = FansCtrl
APP_BUNDLE = $(APP_NAME).app

run: build
	@sudo "$$(swift build -c release --show-bin-path)/$(APP_NAME)"

build:
	@swift build -c release

clean:
	@swift package clean
	@rm -rf $(APP_BUNDLE)

bundle: build
	@rm -rf $(APP_BUNDLE)
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@cp "$$(swift build -c release --show-bin-path)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/"
	@cp Sources/Info.plist "$(APP_BUNDLE)/Contents/"
	@test -f AppIcon.icns && cp AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/" || true
	@echo "✅ $(APP_BUNDLE) 已生成"

install: bundle
	@rm -rf "/Applications/$(APP_BUNDLE)"
	@cp -R "$(APP_BUNDLE)" "/Applications/"
	@echo "✅ 已安装到 /Applications/$(APP_BUNDLE)"

run-app: bundle
	@open "$(APP_BUNDLE)"
