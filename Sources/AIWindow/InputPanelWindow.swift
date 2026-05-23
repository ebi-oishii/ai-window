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
    private var shortcutButtons: [NSButton] = []
    private var toggledShortcutIDs: Set<String> = []
    private var dismissTimer: DispatchWorkItem?
    private var isProcessing = false

    static let minWidth: CGFloat  = 460
    static let minHeight: CGFloat = 160
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
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupUI() {
        let content = NSView()
        contentView = content

        // Row 1 — input field + send button
        inputField.placeholderString = "何をしたいですか？（例: Gmail を開く、音量を少し上げる）"
        inputField.delegate = self
        inputField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(inputField)

        sendButton.title = "実行"
        sendButton.bezelStyle = .rounded
        sendButton.target = self
        sendButton.action = #selector(didPressSend)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(sendButton)

        // Row 1.5 — help button + screenshot toggle (fixed, left) + shortcut chip bar (scrollable)
        helpButton.title = "/help"
        helpButton.bezelStyle = .recessed
        helpButton.font = .systemFont(ofSize: 11, weight: .medium)
        helpButton.target = self
        helpButton.action = #selector(didPressHelp)
        helpButton.toolTip = "AI Window で何ができるかを AI に説明させる"
        helpButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(helpButton)

        screenshotButton.title = "📷 画面"
        screenshotButton.setButtonType(.pushOnPushOff)
        screenshotButton.bezelStyle = .recessed
        screenshotButton.font = .systemFont(ofSize: 11, weight: .medium)
        screenshotButton.toolTip = "オンにすると送信時に画面全体のスクリーンショットを AI に同送します"
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
        resultView.font = .systemFont(ofSize: 13)
        resultView.textColor = .labelColor
        resultView.textContainerInset = NSSize(width: 2, height: 4)
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
        providerControl.segmentStyle = .capsule
        providerControl.target = self
        providerControl.action = #selector(providerChanged)
        providerControl.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(providerControl)

        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.drawsBackground = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            // Row 1
            inputField.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            inputField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            inputField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -8),

            sendButton.centerYAnchor.constraint(equalTo: inputField.centerYAnchor),
            sendButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            sendButton.widthAnchor.constraint(equalToConstant: 64),

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
            statusLabel.stringValue = ok ? "" : "⚠ \(selectedProvider.envKey) が未設定"
            statusLabel.textColor = ok ? .secondaryLabelColor : .systemOrange
        }
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
            button.bezelStyle = .recessed
            button.font = .systemFont(ofSize: 11, weight: .medium)
            button.identifier = NSUserInterfaceItemIdentifier(rawValue: command.id)
            button.state = toggledShortcutIDs.contains(command.id.lowercased()) ? .on : .off
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
        persistToggledShortcuts()
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
        orderFrontRegardless()
        makeKey()
        makeFirstResponder(inputField)
        inputField.selectText(nil)
    }

    override var canBecomeKey: Bool { true }

    func dismiss() {
        dismissTimer?.cancel()
        dismissTimer = nil
        orderOut(nil)
        inputField.stringValue = ""
        resultView.string = ""
        isProcessing = false
        screenshotButton.state = .off
        updateProviderStatus()
        statusLabel.textColor = .secondaryLabelColor
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

        // Snapshot the screen synchronously while it's still in front. If we
        // wait until after the panel grabs focus we just capture ourselves.
        let imageBase64: String? = (screenshotButton.state == .on)
            ? ScreenCapture.captureMainDisplayBase64()
            : nil

        dismissTimer?.cancel()
        isProcessing = true
        sendButton.isEnabled = false
        inputField.isEditable = false
        resultView.string = ""
        let visualNote = imageBase64.map { _ in " 📷" } ?? ""
        statusLabel.stringValue = expansion.activeIDs.isEmpty
            ? "考え中...\(visualNote)"
            : "考え中... (/\(expansion.activeIDs.joined(separator: " /")))\(visualNote)"
        statusLabel.textColor = .secondaryLabelColor

        Task { @MainActor in
            do {
                let result = try await ActionDispatcher().dispatch(
                    userInput: expansion.prompt,
                    provider: provider,
                    imageBase64: imageBase64
                )
                ShortcutRegistry.shared.recordUsage(ids: expansion.activeIDs)
                let display = result.isEmpty ? "（応答なし）" : result
                resultView.string = display
                resultView.scrollToBeginningOfDocument(nil)

                let learnedNow = ShortcutRegistry.shared.commands
                    .filter { !knownShortcutsBefore.contains($0.id.lowercased()) }
                if let learned = learnedNow.first {
                    statusLabel.stringValue = "✓ 完了 — 🆕 /\(learned.id) を学習しました"
                } else {
                    statusLabel.stringValue = "✓ 完了"
                }
                statusLabel.textColor = .systemGreen
                inputField.stringValue = ""
                isProcessing = false
                updateProviderStatus()

                let item = DispatchWorkItem { [weak self] in self?.dismiss() }
                dismissTimer = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: item)

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
}
