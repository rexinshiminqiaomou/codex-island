import AppKit
import Combine
import SwiftUI

@MainActor
final class IslandWindowController {
    let window: NSWindow
    let model: IslandModel
    private let host: IslandHostingView
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var trackingTimer: Timer?
    private var screenChangeObserver: NSObjectProtocol?
    private var occlusionObserver: NSObjectProtocol?
    private var sessionResignObserver: NSObjectProtocol?
    private var sessionActiveObserver: NSObjectProtocol?
    private var subs: Set<AnyCancellable> = []
    private var hasSeenMouseEvent = false
    private var isMouseInsideIsland = false
    private var cmdQMonitor: Any?
    private var optionGlobalMonitor: Any?
    private var overlayActionMonitor: Any?
    private var lastActiveApp: NSRunningApplication?
    private var capturesOverlayKeys = false
    private var lastOptionToggleAt: TimeInterval = 0

    static let windowSize = CGSize(width: 900, height: 360)

    init() {
        let notch = NotchInfo.detect(from: Self.targetScreen())
        self.model = IslandModel(notch: notch)

        window = BorderlessFloatingWindow(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isMovable = false

        host = IslandHostingView(
            rootView: IslandRootView(model: model),
            model: model
        )
        host.autoresizingMask = [.width, .height]
        window.contentView = host

        model.$state
            .map { $0 == .expanded }
            .removeDuplicates()
            .sink { [weak self] captures in
                self?.setCapturingOverlayKeys(captures)
            }
            .store(in: &subs)
        setCapturingOverlayKeys(false)
    }

    func show() {
        repositionForCurrentScreen()
        window.orderFrontRegardless()
        installMouseTracking()
        installInputHooks()
        observeScreenChanges()
        observeTargetChoice()
        observeOcclusion()
        observeSessionState()
    }

    deinit {
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = occlusionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = sessionResignObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        if let observer = sessionActiveObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m) }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m) }
        if let m = cmdQMonitor { NSEvent.removeMonitor(m) }
        if let m = overlayActionMonitor { NSEvent.removeMonitor(m) }
        if let m = optionGlobalMonitor { NSEvent.removeMonitor(m) }
        trackingTimer?.invalidate()
    }

    /// Click-through for everything outside the visible shape. We watch cursor
    /// position globally and flip ignoresMouseEvents accordingly so clicks
    /// outside the notch pill go straight to whatever's underneath.
    ///
    /// The hitTest override on IslandHostingView is necessary but not
    /// sufficient — without the global monitor, the window still steals focus
    /// on click even when hitTest returns nil.
    private func installMouseTracking() {
        window.ignoresMouseEvents = true

        let handler: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.hasSeenMouseEvent = true
                self.invalidateTrackingTimerIfReady()
                self.updateMouseEventsBasedOnCursor()
            }
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: handler)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
            handler(event)
            return event
        }

        // Polling safety net for the case where the cursor is already inside
        // the shape area at launch — no mouseMoved event would otherwise fire.
        // Self-invalidates once any real mouseMoved arrives, so steady-state
        // doesn't pay the 10Hz timer cost forever.
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateMouseEventsBasedOnCursor() }
        }
    }

    private func invalidateTrackingTimerIfReady() {
        guard hasSeenMouseEvent, let timer = trackingTimer else { return }
        timer.invalidate()
        trackingTimer = nil
    }

    private func updateMouseEventsBasedOnCursor() {
        let cursor = NSEvent.mouseLocation
        let win = window.frame
        let local = NSPoint(x: cursor.x - win.minX, y: cursor.y - win.minY)

        let size = model.size
        let rect = NSRect(
            x: win.width / 2 - size.width / 2,
            y: win.height - size.height,
            width: size.width,
            height: size.height
        )
        let inside = rect.contains(local)
        if window.ignoresMouseEvents == inside {
            window.ignoresMouseEvents = !inside
        }

        if inside {
            if !isMouseInsideIsland {
                isMouseInsideIsland = true
                cmdQMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.modifierFlags.contains(.command),
                       event.charactersIgnoringModifiers == "q" {
                        NSApp.terminate(nil)
                        return nil
                    }
                    return event
                }
            }
        } else if isMouseInsideIsland {
            if let m = cmdQMonitor { NSEvent.removeMonitor(m) }
            cmdQMonitor = nil
            isMouseInsideIsland = false
        }
    }

    private func installInputHooks() {
        if ProcessInfo.processInfo.environment["CODEX_ISLAND_INPUT_DEBUG"] == "1" {
            NSLog("[CodexIsland] Installing global Option monitor for focus-window mode.")
        }
        if installGlobalOptionMonitor() {
            if ProcessInfo.processInfo.environment["CODEX_ISLAND_INPUT_DEBUG"] == "1" {
                NSLog("[CodexIsland] Option monitor installed.")
            }
            return
        }
        NSLog("[CodexIsland] Failed to install global Option monitor.")
    }

    private func installGlobalOptionMonitor() -> Bool {
        guard optionGlobalMonitor == nil else { return true }

        let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            guard let self else { return }

            if ProcessInfo.processInfo.environment["CODEX_ISLAND_INPUT_DEBUG"] == "1" {
                NSLog(
                    "[CodexIsland][InputMonitor] type=%@ key=%d option=%d",
                    String(describing: event.type),
                    Int(event.keyCode),
                    event.modifierFlags.contains(.option) ? 1 : 0
                )
            }

            Task { @MainActor in
                self.handleGlobalOptionEvent(event)
            }
        }

        guard let monitor else {
            return false
        }

        optionGlobalMonitor = monitor
        return true
    }

    @MainActor
    private func handleGlobalOptionEvent(_ event: NSEvent) {
        if ProcessInfo.processInfo.environment["CODEX_ISLAND_INPUT_DEBUG"] == "1" {
            NSLog(
                "[CodexIsland][InputState] type=%@ key=%d optionBit=%d state=%@",
                String(describing: event.type),
                Int(event.keyCode),
                event.modifierFlags.contains(.option) ? 1 : 0,
                String(describing: model.state)
            )
        }

        guard event.type == .flagsChanged,
              isOptionKeyCode(event.keyCode),
              event.modifierFlags.contains(.option) else {
            return
        }
        triggerOptionToggleIfReady()
    }

    private func installOverlayActionMonitor() {
        guard overlayActionMonitor == nil else { return }

        overlayActionMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { [weak self] event in
            guard let self else { return event }
            let keyCode = event.keyCode

            guard self.capturesOverlayKeys,
                  self.model.state == .expanded else {
                return event
            }

            if event.type == .flagsChanged {
                guard self.isOptionKeyCode(keyCode) else { return event }
                let optionDown = event.modifierFlags.contains(.option)
                if optionDown {
                    Task { @MainActor in
                        self.triggerOptionToggleIfReady()
                    }
                }
                return nil
            }

            if event.type == .keyDown, event.isARepeat {
                if self.isOptionKeyCode(keyCode) || self.isOverlayActionKey(keyCode) {
                    return nil
                }
                return event
            }

            if self.isOptionKeyCode(keyCode) {
                if event.type == .keyUp {
                    return nil
                }

                if event.type == .keyDown {
                    Task { @MainActor in
                        self.triggerOptionToggleIfReady()
                    }
                }
                return nil
            } else if !self.isOverlayActionKey(keyCode) {
                return event
            }

            guard event.type == .keyDown else {
                return nil
            }

            Task { @MainActor in
                self.handleOverlayKeyDown(keyCode: keyCode)
            }
            return nil
        }

        if ProcessInfo.processInfo.environment["CODEX_ISLAND_INPUT_DEBUG"] == "1" {
            NSLog("[CodexIsland] Local overlay key monitor installed.")
        }
    }

    private func removeOverlayActionMonitor() {
        if let monitor = overlayActionMonitor {
            NSEvent.removeMonitor(monitor)
            overlayActionMonitor = nil
            if ProcessInfo.processInfo.environment["CODEX_ISLAND_INPUT_DEBUG"] == "1" {
                NSLog("[CodexIsland] Local overlay key monitor removed.")
            }
        }
    }

    private func isOptionKeyCode(_ keyCode: UInt16) -> Bool {
        keyCode == 58 || keyCode == 61
    }

    private func setCapturingOverlayKeys(_ enabled: Bool) {
        capturesOverlayKeys = enabled
        if enabled {
            installOverlayActionMonitor()
        } else {
            removeOverlayActionMonitor()
        }
    }

    @MainActor
    private func triggerOptionToggleIfReady() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastOptionToggleAt > 0.18 else { return }
        lastOptionToggleAt = now
        finishOptionGesture()
    }

    @MainActor
    private func finishOptionGesture() {
        let wasExpanded = model.state == .expanded
        if ProcessInfo.processInfo.environment["CODEX_ISLAND_INPUT_DEBUG"] == "1" {
            NSLog(
                "[CodexIsland][OptionToggle] state=%@",
                String(describing: model.state)
            )
            NSLog(
                "[CodexIsland][OptionToggle][StateDiag] before=%@ next=%@",
                String(describing: model.state),
                String(describing: wasExpanded ? IslandModel.State.compact : IslandModel.State.expanded)
            )
            debugWindowState("[CodexIsland][OptionToggle]")
        }

        if wasExpanded {
            restoreActiveApplicationIfNeeded()
            toggleExpansionWithCommand()
        } else {
            rememberActiveApplicationIfNeeded()
            toggleExpansionWithCommand()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                guard let self else { return }
                self.retryFocusIslandWindowForInput(remainingAttempts: 5)
            }
        }
        if ProcessInfo.processInfo.environment["CODEX_ISLAND_INPUT_DEBUG"] == "1" {
            NSLog(
                "[CodexIsland][OptionToggle][StateDiag] after=%@",
                String(describing: model.state)
            )
            debugWindowState("[CodexIsland][OptionToggle]")
        }
    }

    @MainActor
    private func focusIslandWindowForInput() {
        window.setIsVisible(true)
        window.alphaValue = 1
        // Ensure the host app is frontmost before making CodexIsland key. In
        // background states, AppKit can ignore focus transfers unless the app
        // is explicitly activated, which leads to missing overlay key capture.
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        window.makeKey()
        if let responder = window.contentView {
            let succeeded = window.makeFirstResponder(responder)
            if ProcessInfo.processInfo.environment["CODEX_ISLAND_INPUT_DEBUG"] == "1" {
                NSLog("[CodexIsland][Focus] makeFirstResponder=%d", succeeded ? 1 : 0)
            }
        }
        if ProcessInfo.processInfo.environment["CODEX_ISLAND_INPUT_DEBUG"] == "1" {
            debugWindowState("[CodexIsland][Focus]")
        }
    }

    @MainActor
    private func retryFocusIslandWindowForInput(remainingAttempts: Int) {
        guard remainingAttempts > 0, model.state == .expanded else { return }
        focusIslandWindowForInput()
        guard !window.isKeyWindow else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            self.retryFocusIslandWindowForInput(remainingAttempts: remainingAttempts - 1)
        }
    }

    private func rememberActiveApplicationIfNeeded() {
        guard model.state != .expanded else { return }
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }
        lastActiveApp = frontApp
    }

    private func restoreActiveApplicationIfNeeded() {
        guard let app = lastActiveApp else { return }
        if ProcessInfo.processInfo.environment["CODEX_ISLAND_INPUT_DEBUG"] == "1" {
            debugWindowState("[CodexIsland][Restore]")
        }
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        lastActiveApp = nil
    }

    private func debugWindowState(_ tag: String) {
        NSLog(
            "%@ state=%@ visible=%d key=%d main=%d frontmost=%d alpha=%.2f frame=%@",
            tag,
            String(describing: model.state),
            window.isVisible ? 1 : 0,
            window.isKeyWindow ? 1 : 0,
            window.isMainWindow ? 1 : 0,
            window.alphaValue,
            NSStringFromRect(window.frame)
        )
    }

    @MainActor
    private func handleOverlayKeyDown(keyCode: UInt16) {
        guard self.model.state == .expanded else { return }

        if ProcessInfo.processInfo.environment["CODEX_ISLAND_INPUT_DEBUG"] == "1" {
            NSLog("[CodexIsland][OverlayAction] key=%d state=%@", Int(keyCode), String(describing: self.model.state))
        }

        switch keyCode {
        case 123:
            self.model.rewindScreen()
        case 124:
            self.model.advanceScreen()
        case 49:
            switch ScreenPref.shared.screen {
            case .usage:
                UsageStore.shared.refresh()
            case .cost, .overview:
                CostStore.shared.refresh()
            }
        default:
            break
        }
    }

    private func isOverlayActionKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 49, 123, 124:
            return true
        default:
            return false
        }
    }

    @MainActor
    private func toggleExpansionWithCommand() {
        withAnimation(model.state == .expanded ? .closeMorph : .openMorph) {
            model.setState(model.state == .expanded ? .compact : .expanded)
        }
    }

    @MainActor
    private static func targetScreen() -> NSScreen? {
        DisplayInfo.currentTarget()?.screen
    }

    private func observeScreenChanges() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.repositionForCurrentScreen() }
        }
    }

    /// Pauses the LoadingSweep when the user can't see the island —
    /// fullscreen apps on a separate Space, the screen going to sleep,
    /// or anything else macOS reports as making the window invisible.
    /// The 30Hz TimelineView is the dominant idle-CPU cost; pausing it
    /// while occluded drops idle to ~0%.
    private func observeOcclusion() {
        // Seed the initial state — the notification doesn't fire on launch.
        WindowOcclusionStore.shared.update(
            isVisible: window.occlusionState.contains(.visible)
        )
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let visible = self.window.occlusionState.contains(.visible)
            Task { @MainActor in
                WindowOcclusionStore.shared.update(isVisible: visible)
            }
        }
    }

    /// Hides the island when the screen locks so it doesn't ride the
    /// lock-screen slide animation (which makes the notch appear to fall).
    /// DistributedNotificationCenter "com.apple.screenIsLocked" fires as soon
    /// as the lock is initiated, before the slide animation completes.
    private func observeSessionState() {
        let dc = DistributedNotificationCenter.default()
        sessionResignObserver = dc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.fadeOut() }
        }
        sessionActiveObserver = dc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.fadeIn() }
        }
    }

    private func fadeOut() {
        window.orderOut(nil)
    }

    private func fadeIn() {
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 1
        }
    }

    private func observeTargetChoice() {
        IslandTargetDisplayStore.shared.$choice
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.repositionForCurrentScreen() }
            }
            .store(in: &subs)
    }

    private func repositionForCurrentScreen() {
        guard let screen = Self.targetScreen() else { return }
        model.updateNotch(NotchInfo.detect(from: screen))
        let size = Self.windowSize
        let frame = screen.frame
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height
        window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}
