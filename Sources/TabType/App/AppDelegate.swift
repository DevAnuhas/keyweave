import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import TabTypeKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let settings = AppSettings.shared
    private let llamaModels = LlamaModelManager.shared
    private lazy var engine = Engine(settings: settings)

    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()
    private(set) var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var accessibilityTimer: Timer?

    /// Permission requests are explicit UI actions. Startup only checks trust.
    struct StartupOperations {
        var accessibilityTrusted: () -> Bool
        var startEngine: () -> Bool
    }

    static func startEngineIfTrusted(operations: StartupOperations) -> AppSettings.InputMonitoringState {
        guard AppSafetyPolicy.inputMonitoringEnabled,
              operations.accessibilityTrusted() else { return .needsAccessibility }
        return operations.startEngine() ? .active : .failed
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        startSecureInputWatch()

        // Rebuild the menu whenever model state or enablement changes.
        settings.$isEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.rebuildMenu()
                // Visibly dim the menu-bar glyph while disabled — a silently-off
                // engine has repeatedly read as "the app is broken".
                self?.statusItem.button?.appearsDisabled = !enabled
            }
            .store(in: &cancellables)
        settings.$showMenuBarIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] show in self?.statusItem.isVisible = show }
            .store(in: &cancellables)
        settings.$inputMonitoringState
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)

        // Accessory button → open Settings.
        NotificationCenter.default.addObserver(
            forName: .tabTypeOpenSettings, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.openSettings() }
        }

        Log.shared.info("\(ProductIdentity.name) launched. model=\(llamaModels.selectedID) ax=\(AccessibilityBridge.isTrusted()) screen=\(ScreenContextProvider.shared.hasPermission()) emoji=\(EmojiMatcher.shared.all.count)")

        // Register bundled fonts so ghost text can match fields that use them.
        Log.shared.info("ghost fonts: \(BundledFonts.families.joined(separator: ", "))")

        // Only an already installed KeyWeave model loads at startup.
        llamaModels.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)
        // Autocorrect and the typo gate on suggestions both use it.
        SpellChecker.shared.loadIfNeeded(language: settings.autocorrectLanguage)

        llamaModels.start()
        refreshInputMonitoring()
        // A new bundle needs its own grant. Detect grants/revocations without
        // asking for permission repeatedly or requiring an app restart.
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshInputMonitoring() }
        }
        // Finder launches must visibly open the app, even with a hidden icon or
        // an unfinished model/permission setup.
        SettingsNavigator.shared.pendingSection = .setup
        openSettings()
    }

    private func refreshInputMonitoring() {
        let trusted = AccessibilityBridge.isTrusted()
        if !trusted {
            if engine.isRunning { engine.stop() }
            if settings.inputMonitoringState != .needsAccessibility {
                settings.inputMonitoringState = .needsAccessibility
            }
            return
        }
        guard !engine.isRunning else { return }
        let state = Self.startEngineIfTrusted(operations: .init(
            accessibilityTrusted: { trusted },
            startEngine: { self.engine.start() }))
        if state != settings.inputMonitoringState {
            settings.inputMonitoringState = state
            Log.shared.info("Input monitoring: \(state)")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    /// The model must be freed before exit: ggml aborts if Metal resources are
    /// still alive when the process tears down.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
        engine.stop()
        Task { @MainActor in
            await llamaModels.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = BrandAssets.menuBarIcon()
            button.setAccessibilityLabel(ProductIdentity.name)
        }
        statusItem.isVisible = settings.showMenuBarIcon
        statusMenu.delegate = self
        // Honor the isEnabled we set in item(...) — with auto-enable on, AppKit
        // grays out action-less items like the "Pause For…" submenu parent.
        statusMenu.autoenablesItems = false
        statusItem.menu = statusMenu
        rebuildMenu()
    }

    /// Rebuild right before the menu is shown, so a time-limited pause that expired
    /// while the menu was closed is reflected immediately.
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = statusMenu
        menu.removeAllItems()

        menu.addItem(item(statusLine(), icon: engineIconName(), enabled: false))
        if secureInputActive {
            menu.addItem(item(secureInputHolder.map { "Secure Input is held by \($0) — suggestions paused" }
                              ?? "Secure Input is on — suggestions paused",
                              icon: "lock.fill", enabled: false))
        }
        if let pause = engine.frontmostAppPause() {
            let mins = max(1, Int(pause.until.timeIntervalSinceNow / 60))
            menu.addItem(item("Paused in this app (\(mins)m left) — Resume",
                              icon: "pause.circle", action: #selector(resumeAppPause)))
        }
        menu.addItem(.separator())

        if engine.isPaused {
            let resumeTitle = settings.isEnabled ? "Resume \(ProductIdentity.name)" : "Enable \(ProductIdentity.name)"
            menu.addItem(item(resumeTitle, icon: "play.circle", action: #selector(resumeNow)))
        } else {
            let toggle = item(settings.isEnabled ? "Pause \(ProductIdentity.name)" : "Enable \(ProductIdentity.name)",
                              icon: settings.isEnabled ? "pause.circle" : "power",
                              action: #selector(toggleEnabled))
            menu.addItem(toggle)

            let pauseMenu = NSMenu()
            pauseMenu.autoenablesItems = false
            pauseMenu.addItem(item("For 15 Minutes", icon: "timer", action: #selector(pause15)))
            pauseMenu.addItem(item("For 1 Hour", icon: "timer", action: #selector(pause60)))
            pauseMenu.addItem(item("Until I Turn It Back On", icon: "moon.zzz", action: #selector(pauseIndefinitely)))
            if let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier,
               let name = app.localizedName {
                pauseMenu.addItem(.separator())
                pauseMenu.addItem(item("In \(name) for 1 Hour", icon: "app.badge", action: #selector(pauseAppHour)))
            }
            let pauseItem = item("Pause For…", icon: "pause.circle")
            pauseItem.submenu = pauseMenu
            menu.addItem(pauseItem)
        }

        menu.addItem(.separator())

        menu.addItem(item("Settings…", icon: "gearshape", action: #selector(openSettings), key: ","))
        menu.addItem(item("Statistics", icon: "chart.bar", action: #selector(openStatistics)))

        if AppSafetyPolicy.inputMonitoringEnabled && !AccessibilityBridge.isTrusted() {
            menu.addItem(item("Grant Accessibility Permission…", icon: "exclamationmark.triangle",
                              action: #selector(showOnboarding)))
        }

        menu.addItem(.separator())
        menu.addItem(item("Open Log", icon: "doc.text.magnifyingglass", action: #selector(openLog)))
        menu.addItem(item("About \(ProductIdentity.name)", icon: "info.circle", action: #selector(openAbout)))

        menu.addItem(.separator())
        menu.addItem(item("Quit \(ProductIdentity.name)", icon: "power", action: #selector(quit), key: "q"))
    }

    /// Build an `NSMenuItem` with an SF Symbol icon.
    private func item(_ title: String, icon: String, action: Selector? = nil,
                      key: String = "", enabled: Bool = true) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        if action != nil { menuItem.target = self }
        // Submenu parents legitimately have no action — don't disable them.
        menuItem.isEnabled = enabled
        return menuItem
    }

    private func engineIconName() -> String {
        switch llamaModels.status {
        case .ready: return "cpu"
        case .downloading: return "arrow.down.circle"
        case .loading: return "gearshape.2"
        case .failed: return "exclamationmark.triangle"
        case .noModel: return "circle.dashed"
        }
    }

    /// Another app holding macOS Secure Input silently blinds the keystroke tap —
    /// surface it instead of looking broken (Cotypist ships the same warning).
    private var secureInputActive = false
    /// The app holding Secure Input, when macOS reports it (often a password
    /// manager or a terminal with "Secure Keyboard Entry" on).
    private var secureInputHolder: String?

    /// Name of the process holding Secure Input, from the login session's
    /// `kCGSSessionSecureInputPID`.
    private static func secureInputHolderName() -> String? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              let pid = (session["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value, pid > 0 else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }
    private var secureInputTimer: Timer?

    func startSecureInputWatch() {
        secureInputTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let active = IsSecureEventInputEnabled()
                let holder = active ? Self.secureInputHolderName() : nil
                guard active != self.secureInputActive || holder != self.secureInputHolder else { return }
                self.secureInputActive = active
                self.secureInputHolder = holder
                self.statusItem.button?.toolTip = active
                    ? "\(holder ?? "Another app") has Secure Input on — \(ProductIdentity.name) can't see keystrokes until it releases it."
                    : nil
                self.rebuildMenu()
                if active {
                    Log.shared.info("Secure Input active (held by \(holder ?? "unknown app")) — keystroke tap is blind")
                }
            }
        }
    }

    private func statusLine() -> String {
        switch settings.inputMonitoringState {
        case .needsAccessibility: return "Finish setup — grant Accessibility in Settings"
        case .failed: return "Keyboard monitoring failed — check Privacy & Security"
        case .active: break
        }
        let name = { (id: String) in self.llamaModels.entry(id: id)?.name ?? id }
        switch llamaModels.status {
        case .noModel: return "No model yet — choose one in Settings ▸ Model"
        case .downloading(let id, let f): return "Downloading \(name(id))… \(Int(f * 100))%"
        case .loading(let id): return "Loading \(name(id))…"
        case .ready(let id): return "Model: \(name(id))"
        case .failed(_, let message): return message
        }
    }

    private func shortModelName(_ id: String) -> String {
        id.split(separator: "/").last.map(String.init) ?? id
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
        rebuildMenu()
    }

    @objc private func pause15() { engine.pause(minutes: 15); rebuildMenu() }
    @objc private func pause60() { engine.pause(minutes: 60); rebuildMenu() }
    @objc private func pauseIndefinitely() { engine.pause(minutes: nil); rebuildMenu() }
    @objc private func resumeNow() { engine.resume(); rebuildMenu() }
    @objc private func resumeAppPause() { engine.resumeFrontmostAppPause(); rebuildMenu() }
    @objc private func pauseAppHour() { engine.pauseFrontmostApp(minutes: 60); rebuildMenu() }

    @objc private func openStatistics() {
        SettingsNavigator.shared.pendingSection = .statistics
        openSettings()
    }

    @objc private func openAbout() {
        SettingsNavigator.shared.pendingSection = .about
        openSettings()
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView().environmentObject(settings).environmentObject(llamaModels)
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "\(ProductIdentity.name) Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: SettingsNavigator.shared.desiredContentWidth, height: 620))
            window.minSize = NSSize(width: 760, height: 460)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
            // SwiftUI can't drive an AppKit-hosted window's size, so the settings
            // content publishes the width each section wants and we animate to it.
            SettingsNavigator.shared.$desiredContentWidth
                .removeDuplicates()
                .sink { [weak self] width in self?.resizeSettings(toContentWidth: width) }
                .store(in: &cancellables)
        }
        // Give TabType a Dock icon + Cmd-Tab entry while Settings is open — as a
        // menu-bar-only (.accessory) app, clicking another app would otherwise send
        // this window behind it with no way back except reopening from the menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        // Honor the current section's width now that the window is visible (the
        // sink's initial value arrived while it was still hidden).
        resizeSettings(toContentWidth: SettingsNavigator.shared.desiredContentWidth)
    }

    /// Animate the settings window to a section's desired content width, keeping it
    /// on screen. Height is preserved (respects any manual vertical resize).
    private func resizeSettings(toContentWidth width: CGFloat) {
        guard let window = settingsWindow, window.isVisible else {
            Log.shared.debug("resizeSettings(\(width)) skipped — window not visible")
            return
        }
        let currentContent = window.contentRect(forFrameRect: window.frame).size
        Log.shared.debug("resizeSettings: \(currentContent.width) -> \(width)")
        guard abs(currentContent.width - width) > 1 else { return }
        var frame = window.frame
        let target = window.frameRect(forContentRect:
            NSRect(x: 0, y: 0, width: width, height: currentContent.height)).size
        // Grow/shrink around the current center, then nudge back on screen.
        frame.origin.x -= (target.width - frame.width) / 2
        frame.size.width = target.width
        if let vis = window.screen?.visibleFrame {
            frame.origin.x = min(max(frame.origin.x, vis.minX), vis.maxX - frame.width)
        }
        // `setFrame(_:display:animate:)` is the reliable AppKit API — `animator()`
        // outside an explicit animation context can silently no-op.
        window.setFrame(frame, display: true, animate: true)
    }

    @objc private func showOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView(
                onGrant: { AccessibilityBridge.requestTrust() },
                onGrantScreen: { _ = ScreenContextProvider.shared.requestPermission() },
                onDone: { [weak self] in self?.onboardingWindow?.close() }
            )
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Welcome to \(ProductIdentity.name)"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 480, height: 420))
            window.isReleasedWhenClosed = false
            window.center()
            onboardingWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(Log.fileURL)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === settingsWindow else { return }
        // Revert to menu-bar-only now that Settings is closed.
        NSApp.setActivationPolicy(.accessory)
    }

}
