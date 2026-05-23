APP_NAME  = AIWindow
BUILD_DIR = .build/release

.PHONY: build bundle run debug clean

build:
	swift build -c release 2>&1

# バイナリが変わったときだけ再パッケージ＋再署名する。
# 変わっていなければスキップすることで Accessibility 権限が維持される。
bundle: build
	@mkdir -p $(APP_NAME).app/Contents/MacOS $(APP_NAME).app/Contents/Resources
	@if cmp -s $(BUILD_DIR)/$(APP_NAME) $(APP_NAME).app/Contents/MacOS/$(APP_NAME) 2>/dev/null; then \
		echo "✓ バイナリ変更なし — 再署名スキップ（Accessibility 権限を維持）"; \
	else \
		echo "→ バイナリ更新 — パッケージ化 + 署名"; \
		cp $(BUILD_DIR)/$(APP_NAME) $(APP_NAME).app/Contents/MacOS/; \
		cp Resources/Info.plist $(APP_NAME).app/Contents/; \
		codesign --force --sign - $(APP_NAME).app; \
		echo ""; \
		echo "  ！ バイナリが変わりました。"; \
		echo "    Accessibility を再許可する必要があります:"; \
		echo "    システム設定 → プライバシーとセキュリティ → アクセシビリティ"; \
		echo "    で AIWindow を一度削除して再追加してください。"; \
		echo ""; \
		echo "✓ $(APP_NAME).app 完了"; \
	fi

run: bundle
	@echo "→ AIWindow 起動（終了: Ctrl+C）"
	@[ -n "$$GEMINI_API_KEY" ]      && echo "  ✓ GEMINI_API_KEY 設定済み"      || echo "  - GEMINI_API_KEY 未設定"
	@[ -n "$$ANTHROPIC_API_KEY" ]   && echo "  ✓ ANTHROPIC_API_KEY 設定済み"   || echo "  - ANTHROPIC_API_KEY 未設定"
	@echo ""
	./$(APP_NAME).app/Contents/MacOS/$(APP_NAME)

debug:
	swift build 2>&1

clean:
	rm -rf .build $(APP_NAME).app
