import AppKit

/// Beginner-friendly variant of the input panel.
/// Light visuals, larger fonts, conversational tone, and clickable
/// suggestion buttons (either starter prompts or AI-supplied via the
/// `suggest_actions` tool).
final class EasyPanelWindow: NSPanel {
    private let greetingLabel = NSTextField()
    private let resultScrollView = NSScrollView()
    private let resultView = NSTextView()
    private let suggestionStack = NSStackView()
    private let inputField = NSTextField()
    private let sendButton = NSButton()
    private let statusLabel = NSTextField()
    private let closeButton = NSButton()
    private let providerControl = NSSegmentedControl(
        labels: ProviderType.allCases.map(\.rawValue),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )

    private var currentSuggestions: [SuggestedAction] = []
    private var dismissTimer: DispatchWorkItem?
    private var idleTimer: DispatchWorkItem?
    private var isProcessing = false
    private var historyCursor: Int?
    private var draftBeforeHistory = ""
    private var isCompletingInput = false
    private var suppressInputChange = false

    static let minWidth: CGFloat  = 520
    static let minHeight: CGFloat = 380
    private static let cornerRadius: CGFloat = 14
    private static let idleTimeout: TimeInterval = 180
    private static let unfocusedAlpha: CGFloat = 0.55

    // MARK: Color tokens (local to easy mode)

    private static let bg          = NSColor(white: 0.98, alpha: 0.90)
    private static let fg          = NSColor(white: 0.13, alpha: 1.0)
    private static let fgDim       = NSColor(white: 0.13, alpha: 0.55)
    private static let borderColor = NSColor(white: 0.80, alpha: 1.0)

    /// Initial suggestions when there's no conversation yet.
    private static let starterActions: [SuggestedAction] = [
        SuggestedAction(label: "📧 メールを書く",       prompt: "メールを書きたいです。Gmail を開いてください"),
        SuggestedAction(label: "📅 今日の予定を見る",   prompt: "今日の予定を Google カレンダーで確認したい"),
        SuggestedAction(label: "🔉 音量を変える",       prompt: "音量を変えたいです。今の音量を聞いてから少し上げて"),
        SuggestedAction(label: "📁 最近のファイル",     prompt: "最近ダウンロードしたファイルを教えて"),
        SuggestedAction(label: "🌐 ネットで調べる",     prompt: "ネットで何かを調べたいです。何について調べますか？と聞き返して"),
    ]

    private var selectedProvider: ProviderType {
        ProviderType.allCases[providerControl.selectedSegment]
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.minWidth, height: Self.minHeight),
            styleMask: [.titled, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = "AI Window — 簡単モード"
        isFloatingPanel = true
        level = .floating
        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = false
        minSize = NSSize(width: Self.minWidth, height: Self.minHeight)
        appearance = NSAppearance(named: .aqua)
        isOpaque = false
        backgroundColor = .clear
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        hasShadow = true
        for buttonType: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(buttonType)?.isHidden = true
        }

        setupUI()
        restoreProviderSelection()
        updateProviderStatus()
        showStarter()

        NotificationCenter.default.addObserver(self, selector: #selector(windowBecameKey),
                                               name: NSWindow.didBecomeKeyNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(windowResignedKey),
                                               name: NSWindow.didResignKeyNotification, object: self)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override var canBecomeKey: Bool { true }

    // MARK: - Layout

    private func setupUI() {
        let content = NSView()
        content.wantsLayer = true
        content.layer?.cornerRadius = Self.cornerRadius
        content.layer?.masksToBounds = true
        content.layer?.borderWidth = 1
        content.layer?.borderColor = Self.borderColor.cgColor
        contentView = content

        let blur = NSVisualEffectView()
        blur.material = .menu
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = Self.cornerRadius
        blur.layer?.masksToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(blur, positioned: .below, relativeTo: nil)

        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = Self.bg.cgColor
        tint.layer?.cornerRadius = Self.cornerRadius
        tint.layer?.masksToBounds = true
        tint.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(tint, positioned: .above, relativeTo: blur)

        // Close button
        closeButton.isBordered = false
        closeButton.wantsLayer = true
        closeButton.attributedTitle = NSAttributedString(
            string: "✕",
            attributes: [
                .foregroundColor: Self.fgDim,
                .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            ]
        )
        closeButton.target = self
        closeButton.action = #selector(didPressClose)
        closeButton.toolTip = "閉じる (Esc)"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(closeButton)

        // Greeting
        greetingLabel.stringValue = "何をお手伝いしましょうか？"
        greetingLabel.isBordered = false
        greetingLabel.drawsBackground = false
        greetingLabel.isEditable = false
        greetingLabel.isSelectable = false
        greetingLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        greetingLabel.textColor = Self.fg
        greetingLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(greetingLabel)

        // Result (centered conversational)
        resultView.isEditable = false
        resultView.isSelectable = true
        resultView.drawsBackground = false
        resultView.font = .systemFont(ofSize: 15, weight: .regular)
        resultView.textColor = Self.fg
        resultView.textContainerInset = NSSize(width: 4, height: 6)
        resultView.isVerticallyResizable = true
        resultView.isHorizontallyResizable = false
        resultView.autoresizingMask = [.width]
        resultView.textContainer?.widthTracksTextView = true

        resultScrollView.borderType = .noBorder
        resultScrollView.drawsBackground = false
        resultScrollView.hasVerticalScroller = true
        resultScrollView.autohidesScrollers = true
        resultScrollView.documentView = resultView
        resultScrollView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(resultScrollView)

        // Suggestion buttons row — wraps if too many fit
        suggestionStack.orientation = .horizontal
        suggestionStack.spacing = 8
        suggestionStack.alignment = .centerY
        suggestionStack.distribution = .equalSpacing
        suggestionStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(suggestionStack)

        // Input
        inputField.placeholderString = "ここに話しかけてください..."
        inputField.font = .systemFont(ofSize: 16, weight: .regular)
        inputField.textColor = Self.fg
        inputField.isBordered = true
        inputField.bezelStyle = .roundedBezel
        inputField.delegate = self
        inputField.focusRingType = .none
        inputField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(inputField)

        // Send button
        sendButton.title = "送信"
        sendButton.bezelStyle = .rounded
        sendButton.controlSize = .large
        sendButton.keyEquivalent = "\r"
        sendButton.target = self
        sendButton.action = #selector(didPressSend)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sendButton)

        // Status + provider
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.drawsBackground = false
        statusLabel.textColor = Self.fgDim
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(statusLabel)

        providerControl.segmentStyle = .smallSquare
        providerControl.target = self
        providerControl.action = #selector(providerChanged)
        providerControl.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(providerControl)

        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: content.topAnchor),
            blur.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            tint.topAnchor.constraint(equalTo: blur.topAnchor),
            tint.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            tint.bottomAnchor.constraint(equalTo: blur.bottomAnchor),

            closeButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),

            greetingLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            greetingLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            greetingLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),

            resultScrollView.topAnchor.constraint(equalTo: greetingLabel.bottomAnchor, constant: 10),
            resultScrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            resultScrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            resultScrollView.bottomAnchor.constraint(equalTo: suggestionStack.topAnchor, constant: -10),

            suggestionStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            suggestionStack.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -18),
            suggestionStack.bottomAnchor.constraint(equalTo: inputField.topAnchor, constant: -12),

            inputField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            inputField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),
            inputField.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -10),
            inputField.heightAnchor.constraint(equalToConstant: 30),

            sendButton.centerYAnchor.constraint(equalTo: inputField.centerYAnchor),
            sendButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            sendButton.widthAnchor.constraint(equalToConstant: 80),

            providerControl.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            providerControl.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),

            statusLabel.centerYAnchor.constraint(equalTo: providerControl.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: providerControl.trailingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
        ])
    }

    // MARK: - Suggestions UI

    private func renderSuggestions(_ actions: [SuggestedAction]) {
        currentSuggestions = actions
        for view in suggestionStack.arrangedSubviews {
            suggestionStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for (idx, action) in actions.enumerated() {
            let btn = NSButton(title: action.label, target: self, action: #selector(didTapSuggestion(_:)))
            btn.identifier = NSUserInterfaceItemIdentifier(rawValue: String(idx))
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 14
            btn.layer?.borderWidth = 1
            btn.layer?.borderColor = Theme.accent.withAlphaComponent(0.7).cgColor
            btn.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.10).cgColor
            btn.attributedTitle = NSAttributedString(
                string: action.label,
                attributes: [
                    .foregroundColor: Theme.accent.blended(withFraction: 0.4, of: .black) ?? Theme.accent,
                    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                ]
            )
            btn.toolTip = action.prompt
            suggestionStack.addArrangedSubview(btn)
        }
    }

    private func showStarter() {
        greetingLabel.stringValue = "何をお手伝いしましょうか？"
        resultView.string = ""
        renderSuggestions(Self.starterActions)
    }

    @objc private func didTapSuggestion(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let idx = Int(raw),
              idx < currentSuggestions.count else { return }
        let action = currentSuggestions[idx]
        inputField.stringValue = action.prompt
        didPressSend()
    }

    // MARK: - Provider

    private func restoreProviderSelection() {
        let saved = UserDefaults.standard.integer(forKey: ProviderType.defaultsKey)
        providerControl.selectedSegment = min(saved, ProviderType.allCases.count - 1)
    }

    @objc private func providerChanged() {
        UserDefaults.standard.set(providerControl.selectedSegment, forKey: ProviderType.defaultsKey)
        if selectedProvider == .ollama {
            OllamaWarmup.warmTextModelIfNeeded()
        }
        if !isProcessing { updateProviderStatus() }
    }

    private func updateProviderStatus() {
        let ok = selectedProvider.isConfigured
        inputField.isEditable = ok
        sendButton.isEnabled = ok
        if !isProcessing {
            statusLabel.stringValue = ok ? "" : "⚠ \(selectedProvider.envKey) が未設定（メニューバーから設定）"
            statusLabel.textColor = ok ? Self.fgDim : .systemOrange
        }
    }

    // MARK: - Show / dismiss / focus

    func showNear(selectionRect: CGRect) {
        dismissTimer?.cancel()
        dismissTimer = nil
        guard let screen = NSScreen.main else { return }
        let sh = screen.frame.height
        let sw = screen.frame.width
        let width  = max(Self.minWidth,  min(sw - 40, selectionRect.width))
        let height = max(Self.minHeight, min(sh - 80, selectionRect.height))
        var x = selectionRect.minX
        var y = sh - selectionRect.maxY
        x = max(8, min(x, sw - width  - 8))
        y = max(8, min(y, sh - height - 8))
        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        alphaValue = 1.0
        orderFrontRegardless()
        makeKey()
        makeFirstResponder(inputField)
        inputField.selectText(nil)
        if selectedProvider == .ollama {
            OllamaWarmup.keepTextModelWarm()
        }
        scheduleIdleTimer()
    }

    func dismiss() {
        dismissTimer?.cancel()
        dismissTimer = nil
        cancelIdleTimer()
        orderOut(nil)
        inputField.stringValue = ""
        resultView.string = ""
        statusLabel.stringValue = ""
        isProcessing = false
        updateProviderStatus()
        showStarter()
    }

    @objc private func didPressClose() { dismiss() }

    @objc private func windowBecameKey() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            self.animator().alphaValue = 1.0
        }
        scheduleIdleTimer()
    }

    @objc private func windowResignedKey() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            self.animator().alphaValue = Self.unfocusedAlpha
        }
    }

    private func scheduleIdleTimer() {
        cancelIdleTimer()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isProcessing { return }
            self.dismiss()
        }
        idleTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleTimeout, execute: item)
    }

    private func cancelIdleTimer() {
        idleTimer?.cancel()
        idleTimer = nil
    }

    // MARK: - Send

    @objc private func didPressSend() {
        guard !isProcessing else { return }
        let provider = selectedProvider
        guard provider.isConfigured else { return }
        let text = inputField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        InputHistoryStore.record(text)
        historyCursor = nil
        draftBeforeHistory = ""

        dismissTimer?.cancel()
        isProcessing = true
        sendButton.isEnabled = false
        inputField.isEditable = false
        resultView.string = ""
        statusLabel.stringValue = "考え中..."
        statusLabel.textColor = Self.fgDim
        // While processing, hide stale starter/suggestion buttons.
        renderSuggestions([])

        Task { @MainActor in
            do {
                let result = try await ActionDispatcher().dispatch(
                    userInput: text,
                    provider: provider,
                    autoScreen: true,
                    captureScreen: { [weak self] in await self?.captureScreenForAI() }
                )
                resultView.string = result.text.isEmpty ? "（応答なし）" : result.text
                resultView.scrollToBeginningOfDocument(nil)

                if result.suggestions.isEmpty {
                    renderSuggestions(Self.starterActions)
                } else {
                    renderSuggestions(result.suggestions)
                }

                statusLabel.stringValue = result.usedScreen ? "✓ 完了（画面を見ました）" : "✓ 完了"
                statusLabel.textColor = .systemGreen
                inputField.stringValue = ""
                isProcessing = false
                updateProviderStatus()
                scheduleIdleTimer()
            } catch {
                resultView.string = error.localizedDescription
                resultView.textColor = .systemRed
                statusLabel.stringValue = "✗ エラー"
                statusLabel.textColor = .systemRed
                isProcessing = false
                updateProviderStatus()
            }
        }
    }

    /// Temporarily fade the panel out before capture so the AI sees the user's
    /// workspace instead of AI Window's own controls.
    private func captureScreenForAI() async -> String? {
        let previousAlpha = alphaValue
        alphaValue = 0.0
        displayIfNeeded()
        try? await Task.sleep(nanoseconds: 120_000_000)
        let image = ScreenCapture.captureMainDisplayBase64()
        alphaValue = previousAlpha
        displayIfNeeded()
        return image
    }

    private func recallHistory(delta: Int, textView: NSTextView) {
        let history = InputHistoryStore.entries
        guard !history.isEmpty else { return }

        if historyCursor == nil {
            draftBeforeHistory = inputField.stringValue
            historyCursor = history.count
        }

        let current = historyCursor ?? history.count
        let next = max(0, min(history.count, current + delta))
        historyCursor = next

        let value = next == history.count ? draftBeforeHistory : history[next]
        suppressInputChange = true
        textView.string = value
        textView.setSelectedRange(NSRange(location: (value as NSString).length, length: 0))
        inputField.stringValue = value
        suppressInputChange = false
        scheduleIdleTimer()
    }

    private func completeInput(textView: NSTextView) {
        guard !isProcessing, !isCompletingInput else { return }
        let prefix = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty, selectedProvider.isConfigured else { return }

        isCompletingInput = true
        let previousStatus = statusLabel.stringValue
        statusLabel.stringValue = "考え中..."
        statusLabel.textColor = Self.fgDim

        Task { @MainActor in
            defer {
                self.isCompletingInput = false
                if !self.isProcessing {
                    self.statusLabel.stringValue = previousStatus
                    self.updateProviderStatus()
                }
            }

            do {
                let suggestion = try await ActionDispatcher().suggestInputCompletion(
                    prefix: prefix,
                    provider: self.selectedProvider
                )
                guard !suggestion.isEmpty else { return }
                self.suppressInputChange = true
                self.inputField.stringValue = suggestion
                textView.string = suggestion

                let nsSuggestion = suggestion as NSString
                let nsPrefix = prefix as NSString
                if suggestion.hasPrefix(prefix), nsSuggestion.length > nsPrefix.length {
                    textView.setSelectedRange(NSRange(
                        location: nsPrefix.length,
                        length: nsSuggestion.length - nsPrefix.length
                    ))
                } else {
                    textView.setSelectedRange(NSRange(location: nsSuggestion.length, length: 0))
                }
                self.suppressInputChange = false
                self.scheduleIdleTimer()
            } catch {
                self.statusLabel.stringValue = "✗ 補完エラー"
                self.statusLabel.textColor = .systemRed
            }
        }
    }
}

extension EasyPanelWindow: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(insertNewline(_:)):
            didPressSend()
            return true
        case #selector(moveUp(_:)):
            recallHistory(delta: -1, textView: textView)
            return true
        case #selector(moveDown(_:)):
            recallHistory(delta: 1, textView: textView)
            return true
        case #selector(insertTab(_:)):
            completeInput(textView: textView)
            return true
        case #selector(cancelOperation(_:)):
            dismiss()
            return true
        default:
            return false
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        if !suppressInputChange {
            historyCursor = nil
            draftBeforeHistory = ""
        }
        scheduleIdleTimer()
    }
}
