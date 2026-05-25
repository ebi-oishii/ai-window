import AppKit

class InputPanelWindow: NSPanel {
    private let inputField = NSTextField()
    private let sendButton = NSButton()
    private let resultScrollView = NSScrollView()
    private let resultView = NSTextView()
    private let providerControl = NSSegmentedControl(
        labels: ProviderType.allCases.map(\.rawValue),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let statusLabel = NSTextField()
    private let shortcutScrollView = NSScrollView()
    private let shortcutStack = NSStackView()
    private let screenshotButton = NSButton()
    private let helpButton = NSButton()
    private let closeButton = NSButton()
    private var shortcutButtons: [NSButton] = []
    private var toggledShortcutIDs: Set<String> = []
    private var dismissTimer: DispatchWorkItem?
    private var idleTimer: DispatchWorkItem?
    private var isProcessing = false

    /// Auto-dismiss the panel after this many seconds of no interaction.
    private static let idleTimeout: TimeInterval = 90
    /// Alpha applied to the panel when it loses key focus.
    private static let unfocusedAlpha: CGFloat = 0.45

    static let minWidth: CGFloat  = 460
    static let minHeight: CGFloat = 160
    private static let cornerRadius: CGFloat = 14
    private static let toggledKey = "AIWindow.ToggledShortcutIDs"

    private var selectedProvider: ProviderType {
        ProviderType.allCases[providerControl.selectedSegment]
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.minWidth, height: Self.minHeight),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        title = "AI Window"
        isFloatingPanel = true
        level = .floating
        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = false
        minSize = NSSize(width: Self.minWidth, height: Self.minHeight)

        // Detroit-style chrome: transparent window, no title, no traffic lights
        appearance = NSAppearance(named: .darkAqua)
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
        restoreToggledShortcuts()
        rebuildShortcutBar()
        updateProviderStatus()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutsDidChange),
            name: ShortcutRegistry.didChangeNotification,
            object: nil
        )

        // Fade when another window takes focus, restore on key-back.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowBecameKey),
            name: NSWindow.didBecomeKeyNotification,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowResignedKey),
            name: NSWindow.didResignKeyNotification,
            object: self
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupUI() {
        let content = PanelBackgroundView()
        contentView = content
        content.wantsLayer = true
        content.layer?.cornerRadius = Self.cornerRadius
        content.layer?.masksToBounds = true
        content.layer?.borderWidth = 1
        content.layer?.borderColor = Theme.accentDim.cgColor

        // Blur layer (bottom of z-order)
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = Self.cornerRadius
        blur.layer?.masksToBounds = true
        blur.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(blur, positioned: .below, relativeTo: nil)

        // Accent tint over the blur
        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = Theme.backgroundOverlay.cgColor
        tint.layer?.cornerRadius = Self.cornerRadius
        tint.layer?.masksToBounds = true
        tint.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(tint, positioned: .above, relativeTo: blur)

        // Close button (top-right, inside the cyan accent strip)
        closeButton.isBordered = false
        closeButton.wantsLayer = true
        closeButton.attributedTitle = NSAttributedString(
            string: "✕",
            attributes: [
                .foregroundColor: Theme.accentDim,
                .font: Theme.hud(13, weight: .medium),
            ]
        )
        closeButton.target = self
        closeButton.action = #selector(didPressClose)
        closeButton.toolTip = "閉じる (Esc)"
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(closeButton)

        // Row 1 — input field + send button
        inputField.placeholderAttributedString = NSAttributedString(
            string: "COMMAND ▸  例: Gmail を開く、音量を少し上げる",
            attributes: [
                .foregroundColor: Theme.foregroundDim,
                .font: Theme.body(13, weight: .light),
                .kern: 0.4,
            ]
        )
        inputField.delegate = self
        inputField.isBordered = false
        inputField.drawsBackground = false
        inputField.focusRingType = .none
        inputField.textColor = Theme.foreground
        inputField.font = Theme.body(15, weight: .light)
        inputField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(inputField)

        // Thin cyan underline beneath the input — focus indicator look
        let inputUnderline = NSView()
        inputUnderline.wantsLayer = true
        inputUnderline.layer?.backgroundColor = Theme.accentDim.cgColor
        inputUnderline.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(inputUnderline)

        sendButton.attributedTitle = NSAttributedString(
            string: "▸ EXECUTE",
            attributes: [
                .foregroundColor: Theme.accent,
                .font: Theme.hud(11, weight: .semibold),
                .kern: 1.8,
            ]
        )
        sendButton.isBordered = false
        sendButton.wantsLayer = true
        sendButton.layer?.borderColor = Theme.accent.cgColor
        sendButton.layer?.borderWidth = 1
        sendButton.layer?.cornerRadius = 11
        sendButton.layer?.backgroundColor = Theme.accentGlow.cgColor
        sendButton.target = self
        sendButton.action = #selector(didPressSend)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sendButton)

        // Row 1.5 — help button + screenshot toggle (fixed, left) + shortcut chip bar (scrollable)
        Self.styleChip(helpButton, title: "/help", on: false)
        helpButton.target = self
        helpButton.action = #selector(didPressHelp)
        helpButton.toolTip = "AI Window で何ができるかを AI に説明させる"
        helpButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(helpButton)

        screenshotButton.setButtonType(.pushOnPushOff)
        Self.styleChip(screenshotButton, title: "📷 SCREEN", on: false)
        screenshotButton.toolTip = "オンにすると送信時に画面全体のスクリーンショットを AI に同送します"
        screenshotButton.target = self
        screenshotButton.action = #selector(screenshotToggled)
        screenshotButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(screenshotButton)

        shortcutStack.orientation = .horizontal
        shortcutStack.spacing = 6
        shortcutStack.alignment = .centerY
        shortcutStack.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
        shortcutStack.translatesAutoresizingMaskIntoConstraints = false

        shortcutScrollView.borderType = .noBorder
        shortcutScrollView.drawsBackground = false
        shortcutScrollView.hasHorizontalScroller = false
        shortcutScrollView.hasVerticalScroller = false
        shortcutScrollView.autohidesScrollers = true
        shortcutScrollView.horizontalScrollElasticity = .allowed
        shortcutScrollView.verticalScrollElasticity = .none
        shortcutScrollView.documentView = shortcutStack
        shortcutScrollView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(shortcutScrollView)

        // Row 2 — scrollable result (fills remaining height)
        resultView.isEditable = false
        resultView.isSelectable = true
        resultView.drawsBackground = false
        resultView.font = Theme.body(13, weight: .light)
        resultView.textColor = Theme.foreground
        resultView.insertionPointColor = Theme.accent
        resultView.selectedTextAttributes = [
            .backgroundColor: Theme.accent.withAlphaComponent(0.28),
            .foregroundColor: Theme.foreground,
        ]
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

        // Row 3 — provider picker + status
        providerControl.segmentStyle = .smallSquare
        providerControl.target = self
        providerControl.action = #selector(providerChanged)
        for i in 0..<providerControl.segmentCount {
            providerControl.setWidth(72, forSegment: i)
        }
        providerControl.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(providerControl)

        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.drawsBackground = false
        statusLabel.textColor = Theme.accentDim
        statusLabel.font = Theme.hud(10, weight: .medium)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(statusLabel)

        // --- Layout for the new background / tint / underline pieces ---
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: content.topAnchor),
            blur.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            tint.topAnchor.constraint(equalTo: blur.topAnchor),
            tint.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            tint.bottomAnchor.constraint(equalTo: blur.bottomAnchor),

            inputUnderline.leadingAnchor.constraint(equalTo: inputField.leadingAnchor),
            inputUnderline.trailingAnchor.constraint(equalTo: inputField.trailingAnchor),
            inputUnderline.topAnchor.constraint(equalTo: inputField.bottomAnchor, constant: 2),
            inputUnderline.heightAnchor.constraint(equalToConstant: 1),
        ])

        NSLayoutConstraint.activate([
            // Close button — top-right, in the accent strip
            closeButton.topAnchor.constraint(equalTo: content.topAnchor, constant: 4),
            closeButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 18),

            // Row 1
            inputField.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            inputField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            inputField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),

            sendButton.centerYAnchor.constraint(equalTo: inputField.centerYAnchor),
            sendButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            sendButton.widthAnchor.constraint(equalToConstant: 92),

            // Row 1.5 — help + screenshot toggle (fixed left) + chip bar (scrollable, right)
            helpButton.topAnchor.constraint(equalTo: inputField.bottomAnchor, constant: 6),
            helpButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            helpButton.heightAnchor.constraint(equalToConstant: 22),

            screenshotButton.centerYAnchor.constraint(equalTo: helpButton.centerYAnchor),
            screenshotButton.leadingAnchor.constraint(equalTo: helpButton.trailingAnchor, constant: 6),
            screenshotButton.heightAnchor.constraint(equalToConstant: 22),

            shortcutScrollView.centerYAnchor.constraint(equalTo: helpButton.centerYAnchor),
            shortcutScrollView.leadingAnchor.constraint(equalTo: screenshotButton.trailingAnchor, constant: 6),
            shortcutScrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            shortcutScrollView.heightAnchor.constraint(equalToConstant: 26),

            shortcutStack.leadingAnchor.constraint(equalTo: shortcutScrollView.contentView.leadingAnchor),
            shortcutStack.topAnchor.constraint(equalTo: shortcutScrollView.contentView.topAnchor),
            shortcutStack.bottomAnchor.constraint(equalTo: shortcutScrollView.contentView.bottomAnchor),

            // Row 2 — fills available vertical space
            resultScrollView.topAnchor.constraint(equalTo: helpButton.bottomAnchor, constant: 6),
            resultScrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            resultScrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            resultScrollView.bottomAnchor.constraint(equalTo: providerControl.topAnchor, constant: -4),

            // Row 3
            providerControl.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            providerControl.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),

            statusLabel.centerYAnchor.constraint(equalTo: providerControl.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: providerControl.trailingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
        ])
    }

    // MARK: - Provider

    private func restoreProviderSelection() {
        let saved = UserDefaults.standard.integer(forKey: ProviderType.defaultsKey)
        providerControl.selectedSegment = min(saved, ProviderType.allCases.count - 1)
    }

    @objc private func providerChanged() {
        UserDefaults.standard.set(providerControl.selectedSegment, forKey: ProviderType.defaultsKey)
        if !isProcessing { updateProviderStatus() }
    }

    private func updateProviderStatus() {
        let ok = selectedProvider.isConfigured
        inputField.isEditable = ok
        sendButton.isEnabled = ok
        if !isProcessing {
            statusLabel.stringValue = ok ? "▸ READY" : "⚠ \(selectedProvider.envKey) NOT SET"
            statusLabel.textColor = ok ? Theme.accentDim : Theme.danger
        }
        refreshSendButton()
    }

    // MARK: - Close / focus / idle

    @objc private func didPressClose() {
        dismiss()
    }

    @objc private func windowBecameKey() {
        cancelIdleTimer()
        scheduleIdleTimer()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            self.animator().alphaValue = 1.0
        }
    }

    @objc private func windowResignedKey() {
        // Keep the idle timer running — losing focus shouldn't reset it.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            self.animator().alphaValue = Self.unfocusedAlpha
        }
    }

    /// Reschedule the auto-dismiss for `idleTimeout` from now.
    /// Called whenever the user shows signs of life: typing, toggling, etc.
    private func scheduleIdleTimer() {
        cancelIdleTimer()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Don't yank a panel that's mid-flight or just finished
            // (`dismissTimer` handles the short post-success countdown).
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

    // MARK: - Chip styling

    /// Apply Detroit-inspired chip look. Used for shortcut chips, the help
    /// trigger, and the screenshot toggle so they all share one visual rule.
    static func styleChip(_ button: NSButton, title: String, on: Bool) {
        button.isBordered = false
        button.bezelStyle = .recessed
        button.wantsLayer = true
        button.layer?.cornerRadius = 10
        button.layer?.borderWidth = 1
        button.layer?.backgroundColor = (on ? Theme.accentGlow : .clear).cgColor
        button.layer?.borderColor = (on ? Theme.accent : Theme.accentDim).cgColor
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: on ? Theme.accent : Theme.foregroundDim,
            .font: Theme.hud(10.5, weight: .medium),
            .kern: 0.5,
        ])
    }

    @objc private func screenshotToggled() {
        Self.styleChip(screenshotButton, title: "📷 SCREEN", on: screenshotButton.state == .on)
        scheduleIdleTimer()
    }

    private func refreshSendButton() {
        let enabled = sendButton.isEnabled
        sendButton.attributedTitle = NSAttributedString(
            string: "▸ EXECUTE",
            attributes: [
                .foregroundColor: enabled ? Theme.accent : Theme.accentDim,
                .font: Theme.hud(11, weight: .semibold),
                .kern: 1.8,
            ]
        )
        sendButton.layer?.backgroundColor = (enabled ? Theme.accentGlow : .clear).cgColor
        sendButton.layer?.borderColor = (enabled ? Theme.accent : Theme.accentDim).cgColor
    }

    // MARK: - Shortcut chips

    private func restoreToggledShortcuts() {
        let saved = UserDefaults.standard.stringArray(forKey: Self.toggledKey) ?? []
        toggledShortcutIDs = Set(saved.map { $0.lowercased() })
    }

    private func persistToggledShortcuts() {
        UserDefaults.standard.set(Array(toggledShortcutIDs), forKey: Self.toggledKey)
    }

    @objc private func shortcutsDidChange() {
        DispatchQueue.main.async { [weak self] in self?.rebuildShortcutBar() }
    }

    private func rebuildShortcutBar() {
        for view in shortcutStack.arrangedSubviews {
            shortcutStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        shortcutButtons.removeAll()

        // Drop stale toggled IDs that no longer exist in the registry.
        let validIDs = Set(ShortcutRegistry.shared.commands.map { $0.id.lowercased() })
        toggledShortcutIDs = toggledShortcutIDs.intersection(validIDs)

        for command in ShortcutRegistry.shared.ordered {
            let button = NSButton(title: "/\(command.id)", target: self, action: #selector(didToggleShortcut(_:)))
            button.setButtonType(.pushOnPushOff)
            button.identifier = NSUserInterfaceItemIdentifier(rawValue: command.id)
            let on = toggledShortcutIDs.contains(command.id.lowercased())
            button.state = on ? .on : .off
            Self.styleChip(button, title: "/\(command.id)", on: on)
            button.toolTip = command.isBuiltIn
                ? "オンで「/\(command.id)」を先頭に付けたのと等価 — \(command.title)"
                : "学習されたショートカット — \(command.title)"
            shortcutStack.addArrangedSubview(button)
            shortcutButtons.append(button)
        }
    }

    @objc private func didToggleShortcut(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue.lowercased() else { return }
        if sender.state == .on {
            toggledShortcutIDs.insert(id)
        } else {
            toggledShortcutIDs.remove(id)
        }
        Self.styleChip(sender, title: sender.title, on: sender.state == .on)
        persistToggledShortcuts()
        scheduleIdleTimer()
    }

    // MARK: - Show / dismiss

    /// Position and size the panel to match the selection rect.
    /// selectionRect is in CGEvent coordinates (y = 0 at screen top).
    func showNear(selectionRect: CGRect) {
        // Cancel any pending auto-dismiss from a previous use
        dismissTimer?.cancel()
        dismissTimer = nil

        guard let screen = NSScreen.main else { return }
        let sh = screen.frame.height
        let sw = screen.frame.width

        // Size: match selection with floor constraints
        let width  = max(Self.minWidth,  min(sw - 40, selectionRect.width))
        let height = max(Self.minHeight, min(sh - 80, selectionRect.height))

        // Convert CGEvent top-left to NSWindow bottom-left
        var x = selectionRect.minX
        var y = sh - selectionRect.maxY

        // Clamp to screen
        x = max(8, min(x, sw - width  - 8))
        y = max(8, min(y, sh - height - 8))

        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)

        // .nonactivatingPanel lets us become key without NSApp.activate(), which
        // would trigger kCGEventTapDisabledByUserInput and kill the CGEventTap.
        alphaValue = 1.0
        orderFrontRegardless()
        makeKey()
        makeFirstResponder(inputField)
        inputField.selectText(nil)
        scheduleIdleTimer()
    }

    override var canBecomeKey: Bool { true }

    func dismiss() {
        dismissTimer?.cancel()
        dismissTimer = nil
        cancelIdleTimer()
        orderOut(nil)
        inputField.stringValue = ""
        resultView.string = ""
        resultView.textColor = Theme.foreground
        isProcessing = false
        screenshotButton.state = .off
        screenshotToggled()
        updateProviderStatus()
        statusLabel.textColor = Theme.accentDim
    }

    // MARK: - Send

    @objc private func didPressHelp() {
        guard !isProcessing else { return }
        // Have the AI introspect from the tools it's been handed this turn.
        // Anchoring on "tools you have right now" keeps the answer accurate
        // even as we add new tools later.
        inputField.stringValue = """
        あなたは AI Window という macOS バックグラウンドアシスタントです。
        現在あなたに渡されているツール一覧と system prompt を踏まえ、初心者向けに
        「AI Window で実際にできること」を日本語で説明してください。

        要件:
        - 5〜8 個の具体的な指示例を箇条書きで（例:「Gmail で田中さんからのメールを検索」）
        - 学習機能・前面アプリ把握・スクリーンショット同送 などの隠れた機能にも軽く触れる
        - ツール名そのもの（open_app, search_files など）は出さなくて良い。ユーザーは指示文だけ理解できればよい
        - 最後に「右下のチップで /gmail などをトグルするとそれを前提に話せる」とだけ補足
        """
        didPressSend()
    }

    @objc private func didPressSend() {
        guard !isProcessing else { return }
        let provider = selectedProvider
        guard provider.isConfigured else { return }
        let text = inputField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let expansion = ShortcutExpander.expand(input: text, toggledIDs: Array(toggledShortcutIDs))
        let knownShortcutsBefore = Set(ShortcutRegistry.shared.commands.map { $0.id.lowercased() })

        let forceScreen = screenshotButton.state == .on

        dismissTimer?.cancel()
        isProcessing = true
        sendButton.isEnabled = false
        inputField.isEditable = false
        resultView.string = ""
        resultView.textColor = Theme.foreground
        let visualNote = forceScreen ? " 📷" : " AUTO"
        statusLabel.stringValue = expansion.activeIDs.isEmpty
            ? "▸ PROCESSING...\(visualNote)"
            : "▸ PROCESSING... /\(expansion.activeIDs.joined(separator: " /"))\(visualNote)"
        statusLabel.textColor = Theme.accent
        refreshSendButton()

        Task { @MainActor in
            do {
                let forcedImageBase64 = forceScreen ? await self.captureScreenForAI() : nil
                let result = try await ActionDispatcher().dispatch(
                    userInput: expansion.prompt,
                    provider: provider,
                    imageBase64: forcedImageBase64,
                    autoScreen: !forceScreen,
                    captureScreen: { [weak self] in await self?.captureScreenForAI() }
                )
                ShortcutRegistry.shared.recordUsage(ids: expansion.activeIDs)
                let display = result.text.isEmpty ? "（応答なし）" : result.text
                resultView.string = display
                resultView.scrollToBeginningOfDocument(nil)

                let learnedNow = ShortcutRegistry.shared.commands
                    .filter { !knownShortcutsBefore.contains($0.id.lowercased()) }
                if let learned = learnedNow.first {
                    statusLabel.stringValue = result.usedScreen
                        ? "✓ DONE 📷 — LEARNED /\(learned.id)"
                        : "✓ DONE — LEARNED /\(learned.id)"
                } else {
                    statusLabel.stringValue = result.usedScreen ? "✓ DONE 📷" : "✓ DONE"
                }
                statusLabel.textColor = Theme.success
                inputField.stringValue = ""
                isProcessing = false
                updateProviderStatus()

                let item = DispatchWorkItem { [weak self] in self?.dismiss() }
                dismissTimer = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: item)

            } catch {
                resultView.string = error.localizedDescription
                resultView.textColor = Theme.danger
                statusLabel.stringValue = "✗ ERROR"
                statusLabel.textColor = Theme.danger
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
}

extension InputPanelWindow: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(insertNewline(_:)):
            didPressSend()
            return true
        case #selector(cancelOperation(_:)):
            dismiss()
            return true
        default:
            return false
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        scheduleIdleTimer()
    }
}

/// Custom content view. Border + corner radius are handled by the layer so
/// they follow the rounded shape automatically. We still hand-draw the top
/// accent stripe — it gets clipped by `masksToBounds` to the rounded top.
final class PanelBackgroundView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 2px accent stripe at the very top — clipped to the rounded corners
        // by the parent layer's masksToBounds.
        let accent = NSRect(x: 0, y: bounds.maxY - 2, width: bounds.width, height: 2)
        Theme.accent.setFill()
        accent.fill()
    }
}
