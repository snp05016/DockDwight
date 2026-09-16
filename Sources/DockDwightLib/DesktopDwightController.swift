import AppKit
import CoreFoundation
import SwiftUI

@MainActor
public final class DesktopDwightController: NSObject {
    public static let panelSize = CGSize(width: 300, height: 210)

    private let model = DwightViewModel()
    private let settings = CompanionSettings.shared
    private let activityLog = ActivityLogStore()
    private lazy var feedback = CompanionFeedback(settings: settings)
    private lazy var contextMonitor = ContextMonitor(settings: settings)
    private lazy var settingsWindow = CompanionSettingsWindowController(
        settings: settings,
        log: activityLog,
        actions: .init(
            speak: { [weak self] in self?.speakNow() },
            beetDrill: { [weak self] in self?.startBeetDrill() },
            resetPlacement: { [weak self] in self?.resetToAutomaticPlacement() },
            showVisitor: { [weak self] in self?.showVisitor() },
            startFocus: { [weak self] in self?.startFocusSession() },
            hide: { [weak self] in self?.hide() }
        )
    )
    private var panel: NSPanel?
    private var movementTimer: Timer?
    private var quoteWorkItem: DispatchWorkItem?
    private var quoteHideWorkItem: DispatchWorkItem?
    private var stateResetWorkItem: DispatchWorkItem?
    private var visitorWorkItem: DispatchWorkItem?
    private var dockAuditWorkItem: DispatchWorkItem?
    private var beetWorkItem: DispatchWorkItem?
    private var patrol = PatrolState(x: 0)
    private var lastTick = Date()
    private var frameAccumulator: TimeInterval = 0
    private var quoteIndex = Int.random(in: 0..<DwightQuoteBook.quotes.count)
    private var pauseUntil = Date.distantPast
    private var activeDisplayID: NSNumber?
    private var usesManualPlacement = false
    private var manualY: CGFloat = 0
    private var manualLaneCenterX: CGFloat = 0
    private var gestureStartPointer = CGPoint.zero
    private var gestureStartOrigin = CGPoint.zero
    private var gestureStartScale: CGFloat = 1
    private var isInteracting = false
    private var lastReactionSource: String?
    private var lastReactionDate = Date.distantPast
    private var focusSessionEnd: Date?
    private var lastObstacleCheck = Date.distantPast
    private var lastObstacleName: String?
    private(set) public var isVisible = true

    public override init() { super.init() }

    public func start() {
        let panel = makePanel()
        self.panel = panel
        restoreOrPlaceAtPatrolStart(panel)
        panel.orderFrontRegardless()
        model.accessory = settings.accessory
        model.statusText = DwightActivityState.walking.label
        startMovement()
        scheduleNextQuote(initial: true)
        configureContextMonitor()
        contextMonitor.start()
        scheduleVisitor(initial: true)
        scheduleDockAudit(initial: true)
    }

    public func toggleVisibility() {
        isVisible ? hide() : show()
    }

    public func showSettings() {
        settingsWindow.show()
    }

    public func hide() {
        isVisible = false
        panel?.orderOut(nil)
        UserDefaults.standard.set(true, forKey: "dwightHidden")
    }

    public func show() {
        isVisible = true
        UserDefaults.standard.set(false, forKey: "dwightHidden")
        panel?.orderFrontRegardless()
        speakNow()
    }

    public func speakNow() {
        guard isVisible else { return }
        quoteIndex += Int.random(in: 1...9)
        let quote = DwightQuoteBook.quote(seed: quoteIndex, intensity: settings.personality, excluding: model.quote)
        present(message: quote, state: .talking, source: "Dwight", duration: 5.8)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: DwightView(
            model: model,
            onSpeak: { [weak self] in self?.speakNow() },
            onHide: { [weak self] in self?.showContextMenu() },
            onReset: { [weak self] in self?.resetToAutomaticPlacement() },
            onGestureBegan: { [weak self] resize, point in self?.beginGesture(resize: resize, pointer: point) },
            onGestureChanged: { [weak self] resize, point in self?.updateGesture(resize: resize, pointer: point) },
            onGestureEnded: { [weak self] resize, point in self?.endGesture(resize: resize, pointer: point) },
            onScroll: { [weak self] delta in self?.resizeByScroll(delta) },
            onSettings: { [weak self] in self?.settingsWindow.show() },
            onBeetTap: { [weak self] in self?.handleBeetTap() }
        ))
        panel.setContentSize(Self.panelSize)
        return panel
    }

    private func restoreOrPlaceAtPatrolStart(_ panel: NSPanel) {
        model.userScale = max(0.45, min(3, CGFloat(UserDefaults.standard.double(forKey: "dwightScale").nonzero ?? 1)))
        if UserDefaults.standard.bool(forKey: "dwightManualPlacement") {
            let x = CGFloat(UserDefaults.standard.double(forKey: "dwightX"))
            let y = CGFloat(UserDefaults.standard.double(forKey: "dwightY"))
            let point = CGPoint(x: x, y: y)
            if let screen = screen(containing: point) {
                usesManualPlacement = true
                activeDisplayID = displayID(for: screen)
                updateDockHeight(for: screen)
                manualY = y
                manualLaneCenterX = x
                patrol = PatrolState(x: x, direction: .right)
                panel.setFrameOrigin(point)
                restoreHiddenState(panel)
                return
            }
        }
        placeAtAutomaticStart(panel)
    }

    private func placeAtAutomaticStart(_ panel: NSPanel) {
        guard let screen = activeScreen() else { return }
        usesManualPlacement = false
        activeDisplayID = displayID(for: screen)
        updateDockHeight(for: screen)
        let bounds = patrolBounds(in: screen.frame)
        patrol = PatrolState(x: bounds.lowerBound, direction: .right)
        panel.setFrameOrigin(CGPoint(x: patrol.x, y: screen.frame.minY))
        restoreHiddenState(panel)
    }

    private func restoreHiddenState(_ panel: NSPanel) {
        if UserDefaults.standard.bool(forKey: "dwightHidden") {
            isVisible = false
            panel.orderOut(nil)
        }
    }

    private func patrolBounds(in frame: CGRect) -> ClosedRange<CGFloat> {
        let rightEdge = frame.maxX - Self.panelSize.width + 48
        let leftEdge = max(frame.minX, rightEdge - CGFloat(settings.patrolWidth))
        return leftEdge...max(leftEdge + 1, rightEdge)
    }

    private func startMovement() {
        lastTick = Date()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        movementTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        guard let panel else { return }
        let targetScreen: NSScreen?
        if usesManualPlacement {
            targetScreen = screen(containing: CGPoint(x: panel.frame.midX, y: panel.frame.midY)) ?? activeScreen()
        } else {
            targetScreen = activeScreen()
        }
        guard let screen = targetScreen else { return }
        let now = Date()
        updateFocusCountdown(now: now)
        let delta = min(0.1, now.timeIntervalSince(lastTick))
        lastTick = now
        let displayID = displayID(for: screen)
        let displayChanged = displayID != activeDisplayID
        if displayChanged && !usesManualPlacement {
            activeDisplayID = displayID
            let bounds = patrolBounds(in: screen.frame)
            patrol.x = patrol.direction == .right ? bounds.lowerBound : bounds.upperBound
            triggerDisplayTransfer()
        }
        updateDockHeight(for: screen)
        model.accessory = settings.accessory
        guard !isInteracting else { return }
        panel.setFrameOrigin(CGPoint(x: patrol.x, y: usesManualPlacement ? manualY : screen.frame.minY))
        guard isVisible, now >= pauseUntil else { return }

        let bounds: ClosedRange<CGFloat>
        if usesManualPlacement {
            let minimum = max(screen.frame.minX, manualLaneCenterX - 110)
            let maximum = min(screen.frame.maxX - Self.panelSize.width + 48, manualLaneCenterX + 110)
            bounds = min(minimum, maximum)...max(minimum + 1, maximum)
        } else {
            bounds = patrolBounds(in: screen.frame)
        }
        let next = PatrolEngine.step(state: patrol, deltaTime: delta, speed: CGFloat(settings.walkingSpeed), bounds: bounds)
        if now.timeIntervalSince(lastObstacleCheck) >= 0.55 {
            lastObstacleCheck = now
            let probe = CGPoint(
                x: next.x + Self.panelSize.width / 2,
                y: panel.frame.minY + model.dockHeight * model.userScale * 0.55
            )
            let obstacle = WindowAwareness.blockingApplication(at: probe)
            if let obstacle, obstacle != lastObstacleName {
                lastObstacleName = obstacle
                patrol.direction = patrol.direction == .right ? .left : .right
                model.direction = patrol.direction
                model.activityState = .observing
                model.statusText = "WINDOW EDGE • \(obstacle.uppercased())"
                model.effectPulse += 1
                scheduleStateReset(after: 1.4)
                return
            } else if obstacle == nil {
                lastObstacleName = nil
            }
        }
        patrol = next
        model.direction = next.direction
        frameAccumulator += delta
        if frameAccumulator >= 0.16 {
            frameAccumulator = 0
            model.frameIndex = (model.frameIndex + 1) % 2
        }
        panel.setFrameOrigin(CGPoint(x: next.x, y: usesManualPlacement ? manualY : screen.frame.minY))
    }

    private func activeScreen() -> NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
    }

    private func displayID(for screen: NSScreen) -> NSNumber? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    }

    private func updateDockHeight(for screen: NSScreen) {
        let stored = CFPreferencesCopyAppValue("tilesize" as CFString, "com.apple.dock" as CFString) as? NSNumber
        let height = DockGeometry.characterHeight(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            configuredTileSize: stored.map { CGFloat(truncating: $0) }
        )
        if abs(model.dockHeight - height) > 0.5 { model.dockHeight = height }
    }

    private func beginGesture(resize: Bool, pointer: CGPoint) {
        guard let panel else { return }
        isInteracting = true
        pauseUntil = .distantFuture
        model.isPaused = true
        gestureStartPointer = pointer
        gestureStartOrigin = panel.frame.origin
        gestureStartScale = model.userScale
        if !resize {
            model.activityState = .carried
            model.statusText = DwightActivityState.carried.label
            model.effectPulse += 1
            feedback.play(for: .carried)
        }
    }

    private func updateGesture(resize: Bool, pointer: CGPoint) {
        guard let panel else { return }
        if resize {
            let delta = (pointer.y - gestureStartPointer.y) / 85
            model.userScale = max(0.45, min(3, gestureStartScale + delta))
        } else {
            panel.setFrameOrigin(CGPoint(
                x: gestureStartOrigin.x + pointer.x - gestureStartPointer.x,
                y: gestureStartOrigin.y + pointer.y - gestureStartPointer.y
            ))
        }
    }

    private func endGesture(resize: Bool, pointer: CGPoint) {
        guard let panel else { return }
        if !resize {
            usesManualPlacement = true
            manualY = panel.frame.origin.y
            manualLaneCenterX = panel.frame.origin.x
            patrol.x = panel.frame.origin.x
            activeDisplayID = screen(containing: pointer).flatMap { displayID(for: $0) }
        }
        persistPlacement()
        isInteracting = false
        pauseUntil = Date().addingTimeInterval(0.7)
        model.isPaused = false
        if !resize {
            model.activityState = .landing
            model.statusText = DwightActivityState.landing.label
            model.effectPulse += 1
            feedback.play(for: .landing)
            scheduleStateReset(after: 0.75)
        }
    }

    private func resizeByScroll(_ delta: CGFloat) {
        model.userScale = max(0.45, min(3, model.userScale + delta * 0.018))
        persistPlacement()
    }

    private func persistPlacement() {
        UserDefaults.standard.set(Double(model.userScale), forKey: "dwightScale")
        UserDefaults.standard.set(usesManualPlacement, forKey: "dwightManualPlacement")
        if usesManualPlacement {
            UserDefaults.standard.set(Double(manualLaneCenterX), forKey: "dwightX")
            UserDefaults.standard.set(Double(manualY), forKey: "dwightY")
        }
    }

    private func resetToAutomaticPlacement() {
        guard let panel else { return }
        usesManualPlacement = false
        model.userScale = 1
        UserDefaults.standard.removeObject(forKey: "dwightManualPlacement")
        UserDefaults.standard.removeObject(forKey: "dwightX")
        UserDefaults.standard.removeObject(forKey: "dwightY")
        UserDefaults.standard.set(1.0, forKey: "dwightScale")
        placeAtAutomaticStart(panel)
        present(message: "AUTOMATIC PATROL PARAMETERS RESTORED.", state: .celebrating, source: "Placement", duration: 3.5)
    }

    private func scheduleNextQuote(initial: Bool = false) {
        quoteWorkItem?.cancel()
        let center = 52 - settings.personality * 30
        let delay = initial ? 1.4 : max(12, center + Double.random(in: -8...10))
        let work = DispatchWorkItem { [weak self] in
            self?.speakNow()
            self?.scheduleNextQuote()
        }
        quoteWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func configureContextMonitor() {
        contextMonitor.onReaction = { [weak self] reaction in self?.handle(reaction) }
        contextMonitor.onIdleChanged = { [weak self] idle in self?.handleIdleChange(idle) }
        contextMonitor.onWeather = { [weak self] mood, temperature in
            self?.model.weatherMood = mood
            self?.model.temperature = temperature
        }
    }

    private func handle(_ reaction: CompanionReaction) {
        guard settings.reactionsEnabled else { return }
        if reaction.source == lastReactionSource, Date().timeIntervalSince(lastReactionDate) < 12 { return }
        lastReactionSource = reaction.source
        lastReactionDate = Date()
        present(message: reaction.message, state: reaction.state, source: reaction.source, duration: reaction.duration)
    }

    private func present(message: String, state: DwightActivityState, source: String, duration: TimeInterval) {
        guard isVisible else { return }
        pauseUntil = Date().addingTimeInterval(duration)
        model.isPaused = state != .celebrating
        model.activityState = state
        model.statusText = state.label
        model.quote = message
        model.effectPulse += 1
        feedback.play(for: state)
        activityLog.record(source: source, message: message)
        quoteHideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.model.quote = nil
            self.model.isPaused = false
            if self.model.activityState != .sleeping && !self.model.miniGameActive {
                self.model.activityState = .walking
                self.model.statusText = DwightActivityState.walking.label
            }
        }
        quoteHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func handleIdleChange(_ idle: Bool) {
        if idle {
            quoteHideWorkItem?.cancel()
            model.quote = nil
            model.isPaused = true
            model.activityState = .sleeping
            model.statusText = DwightActivityState.sleeping.label
            pauseUntil = .distantFuture
            activityLog.record(source: "Idle", message: "Night watch initiated.")
        } else if model.activityState == .sleeping {
            pauseUntil = Date().addingTimeInterval(3.6)
            present(message: "YOU HAVE RETURNED. THE PERIMETER REMAINED SECURE.", state: .celebrating, source: "Idle", duration: 3.6)
        }
    }

    private func triggerDisplayTransfer() {
        guard !usesManualPlacement else { return }
        model.activityState = .observing
        model.statusText = "DISPLAY TRANSFER"
        model.effectPulse += 1
        scheduleStateReset(after: 0.8)
    }

    private func scheduleStateReset(after delay: TimeInterval) {
        stateResetWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.model.activityState != .sleeping, !self.model.miniGameActive else { return }
            self.model.activityState = .walking
            self.model.statusText = DwightActivityState.walking.label
            self.model.isPaused = false
        }
        stateResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startBeetDrill() {
        show()
        beetWorkItem?.cancel()
        pauseUntil = Date().addingTimeInterval(12)
        model.isPaused = true
        model.miniGameActive = true
        model.beetScore = 0
        model.activityState = .beetDrill
        model.statusText = "CLICK DWIGHT: HARVEST BEETS"
        model.effectPulse += 1
        feedback.play(for: .beetDrill)
        activityLog.record(source: "Beet Drill", message: "Twelve-second harvesting drill started.")
        let work = DispatchWorkItem { [weak self] in self?.finishBeetDrill() }
        beetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
    }

    private func handleBeetTap() {
        guard model.miniGameActive else {
            startBeetDrill()
            return
        }
        model.beetScore += 1
        model.effectPulse += 1
        feedback.play(for: .beetDrill)
        if model.beetScore >= 10 { finishBeetDrill() }
    }

    private func finishBeetDrill() {
        guard model.miniGameActive else { return }
        beetWorkItem?.cancel()
        model.miniGameActive = false
        let score = model.beetScore
        present(
            message: score >= 10 ? "BEET HARVEST COMPLETE. EXEMPLARY." : "BEET DRILL ENDED. SCORE: \(score).",
            state: score >= 10 ? .celebrating : .inspecting,
            source: "Beet Drill",
            duration: 4.2
        )
    }

    private func scheduleVisitor(initial: Bool = false) {
        visitorWorkItem?.cancel()
        let delay = initial ? 12 : Double.random(in: 90...220)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.settings.visitorsEnabled { self.showVisitor() }
            self.scheduleVisitor()
        }
        visitorWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func scheduleDockAudit(initial: Bool = false) {
        dockAuditWorkItem?.cancel()
        let delay = initial ? 48 : Double.random(in: 160...340)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.settings.reactionsEnabled,
               Double.random(in: 0...1) <= max(0.25, self.settings.personality),
               let app = self.dockApplicationNames().randomElement() {
                self.present(
                    message: "AUDITING THE \(app.uppercased()) DOCK STATION.",
                    state: .observing,
                    source: "Dock",
                    duration: 3.6
                )
            }
            self.scheduleDockAudit()
        }
        dockAuditWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func dockApplicationNames() -> [String] {
        guard let entries = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            let data = entry["tile-data"] as? [String: Any]
            return data?["file-label"] as? String
        }
    }

    private func showVisitor() {
        guard settings.visitorsEnabled else { return }
        let visitor = VisitorKind.allCases.randomElement() ?? .cat
        model.visitor = visitor
        model.effectPulse += 1
        activityLog.record(source: "Visitor", message: visitor.label)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.model.visitor = nil }
    }

    private func startFocusSession() {
        settings.focusMode = true
        focusSessionEnd = Date().addingTimeInterval(settings.focusDurationMinutes * 60)
        present(
            message: "TIMED FOCUS PATROL ENGAGED FOR \(Int(settings.focusDurationMinutes)) MINUTES.",
            state: .observing,
            source: "Focus",
            duration: 4
        )
    }

    private func updateFocusCountdown(now: Date) {
        guard let focusSessionEnd else { return }
        let remaining = focusSessionEnd.timeIntervalSince(now)
        if remaining <= 0 {
            self.focusSessionEnd = nil
            settings.focusMode = false
            present(message: "FOCUS PATROL COMPLETE. PRODUCTIVITY VERIFIED.", state: .celebrating, source: "Focus", duration: 4.5)
        } else if model.activityState == .walking {
            let minutes = Int(ceil(remaining / 60))
            model.statusText = "FOCUS PATROL • \(minutes) MIN"
        }
    }

    private func showContextMenu() {
        let menu = NSMenu(title: "DockDwight")
        menu.addItem(withTitle: "Schrute Command Center…", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(withTitle: "Make a Declaration", action: #selector(declare), keyEquivalent: "")
        menu.addItem(withTitle: "Start Beet Drill", action: #selector(beetDrillMenuAction), keyEquivalent: "")
        menu.addItem(withTitle: "Summon Visitor", action: #selector(visitorMenuAction), keyEquivalent: "")
        let focus = menu.addItem(withTitle: "Focus Supervisor", action: #selector(toggleFocus), keyEquivalent: "")
        focus.state = settings.focusMode ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "Reset Position & Size", action: #selector(resetMenuAction), keyEquivalent: "")
        menu.addItem(withTitle: "Hide Dwight", action: #selector(hideMenuAction), keyEquivalent: "")
        menu.addItem(withTitle: "Quit DockDwight", action: #selector(quitMenuAction), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func openSettings() { settingsWindow.show() }
    @objc private func declare() { speakNow() }
    @objc private func beetDrillMenuAction() { startBeetDrill() }
    @objc private func visitorMenuAction() { showVisitor() }
    @objc private func toggleFocus() {
        settings.focusMode.toggle()
        if !settings.focusMode { focusSessionEnd = nil }
        present(message: settings.focusMode ? "FOCUS SUPERVISOR ENGAGED." : "FOCUS SUPERVISOR STOOD DOWN.", state: .observing, source: "Focus", duration: 3.2)
    }
    @objc private func resetMenuAction() { resetToAutomaticPlacement() }
    @objc private func hideMenuAction() { hide() }
    @objc private func quitMenuAction() { NSApp.terminate(nil) }
}

private extension Double {
    var nonzero: Double? { self == 0 ? nil : self }
}
