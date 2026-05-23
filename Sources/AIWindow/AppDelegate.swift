import AppKit
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: RightClickDragMonitor?
    private var overlayWindow: SelectionOverlayWindow?
    private var inputPanel: InputPanelWindow?
    private var statusItem: NSStatusItem?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusBar()
        startIfPermitted()

        NotificationCenter.default.addObserver(
            forName: LearnedRulesStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.updateMenu() }

        // Warm the installed-app inventory in the background so the first
        // open_app call doesn't pay the directory-scan latency.
        DispatchQueue.global(qos: .utility).async { _ = AppInventory.names() }
    }

    // MARK: - Status bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "AI Window")
        updateMenu()
    }

    private func updateMenu() {
        let trusted = AXIsProcessTrusted()
        let menu = NSMenu()

        if trusted {
            let ok = NSMenuItem(title: "✓ 右クリックドラッグで起動", action: nil, keyEquivalent: "")
            ok.isEnabled = false
            menu.addItem(ok)
        } else {
            let warn = NSMenuItem(title: "⚠ Accessibility 権限が必要です", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)

            let grant = NSMenuItem(title: "  アクセシビリティを許可する...", action: #selector(requestAccessibility), keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)

            let recheck = NSMenuItem(title: "  権限を再チェック", action: #selector(recheckPermission), keyEquivalent: "")
            recheck.target = self
            menu.addItem(recheck)

            let openSettings = NSMenuItem(title: "  システム設定を開く...", action: #selector(openAccessibilitySettings), keyEquivalent: "")
            openSettings.target = self
            menu.addItem(openSettings)
        }

        menu.addItem(.separator())

        let rules = LearnedRulesStore.shared.rules
        let learnedHeader = NSMenuItem(title: "学習済みルール: \(rules.count) 件", action: nil, keyEquivalent: "")
        learnedHeader.isEnabled = false
        menu.addItem(learnedHeader)

        if !rules.isEmpty {
            let submenu = NSMenu()
            for rule in rules.suffix(15) {
                let item = NSMenuItem(title: rule.text, action: nil, keyEquivalent: "")
                item.isEnabled = false
                submenu.addItem(item)
            }
            submenu.addItem(.separator())
            let clear = NSMenuItem(title: "すべて削除...", action: #selector(clearLearnedRules), keyEquivalent: "")
            clear.target = self
            submenu.addItem(clear)

            let learnedItem = NSMenuItem(title: "  ルール一覧 / クリア", action: nil, keyEquivalent: "")
            learnedItem.submenu = submenu
            menu.addItem(learnedItem)
        }

        menu.addItem(.separator())

        let restart = NSMenuItem(title: "アプリを再起動", action: #selector(restartApp), keyEquivalent: "r")
        restart.target = self
        menu.addItem(restart)

        menu.addItem(NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        startPermissionPolling()
    }

    @objc private func recheckPermission() {
        if AXIsProcessTrusted() {
            permissionTimer?.invalidate()
            permissionTimer = nil
            updateMenu()
            startMonitoring()
        } else {
            startPermissionPolling()
        }
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startPermissionPolling()
    }

    @objc private func clearLearnedRules() {
        let alert = NSAlert()
        alert.messageText = "学習済みルールをすべて削除しますか？"
        alert.informativeText = "この操作は取り消せません。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "削除")
        alert.addButton(withTitle: "キャンセル")
        if alert.runModal() == .alertFirstButtonReturn {
            LearnedRulesStore.shared.clear()
            updateMenu()
        }
    }

    @objc private func restartApp() {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    /// Idempotently start a 1 Hz timer that flips the app into the running
    /// state the moment the user grants Accessibility in System Settings.
    private func startPermissionPolling() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            if AXIsProcessTrusted() {
                timer.invalidate()
                self.permissionTimer = nil
                self.updateMenu()
                self.startMonitoring()
                print("[AIWindow] Accessibility 許可を検知 — 監視開始")
            }
        }
    }

    // MARK: - Startup

    private func startIfPermitted() {
        if AXIsProcessTrusted() {
            startMonitoring()
        } else {
            print("[AIWindow] Accessibility 未許可 — 権限ポーリング開始")
            startPermissionPolling()
        }
    }

    private func startMonitoring() {
        guard monitor == nil else { return }

        let m = RightClickDragMonitor()
        self.monitor = m

        m.onDragStart = { [weak self] in
            DispatchQueue.main.async { self?.showOverlay() }
        }
        m.onDragUpdate = { [weak self] start, current in
            DispatchQueue.main.async { self?.overlayWindow?.update(start: start, current: current) }
        }
        m.onSelectionMade = { [weak self] rect in
            DispatchQueue.main.async {
                self?.overlayWindow?.clear()
                self?.overlayWindow?.orderOut(nil)
                self?.showInputPanel(near: rect)
            }
        }
        m.onDragCancelled = { [weak self] in
            DispatchQueue.main.async {
                self?.overlayWindow?.clear()
                self?.overlayWindow?.orderOut(nil)
            }
        }

        m.start()
        updateMenu()
    }

    // MARK: - Windows

    private func showOverlay() {
        if overlayWindow == nil { overlayWindow = SelectionOverlayWindow() }
        overlayWindow?.orderFrontRegardless()
    }

    private func showInputPanel(near rect: CGRect) {
        if inputPanel == nil { inputPanel = InputPanelWindow() }
        inputPanel?.showNear(selectionRect: rect)
    }
}
