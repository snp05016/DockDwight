import AppKit
import CoreFoundation
import SwiftUI

@MainActor
public final class DesktopDwightController {
    public static let panelSize = CGSize(width: 300, height: 210)

    private let model = DwightViewModel()
    private var panel: NSPanel?
    private var movementTimer: Timer?
    private var quoteWorkItem: DispatchWorkItem?
    private var quoteHideWorkItem: DispatchWorkItem?
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
    private(set) public var isVisible = true

    public init() {}

    public func start() {
        let panel = makePanel()
        self.panel = panel
        restoreOrPlaceAtPatrolStart(panel)
        panel.orderFrontRegardless()
        startMovement()
        scheduleNextQuote(initial: true)
    }

    public func toggleVisibility() {
        isVisible ? hide() : show()
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
        quoteIndex = (quoteIndex + Int.random(in: 1...DwightQuoteBook.quotes.count - 1)) % DwightQuoteBook.quotes.count
        let quote = DwightQuoteBook.quote(at: quoteIndex, excluding: model.quote)
        pauseUntil = Date().addingTimeInterval(5.8)
        model.isPaused = true
        model.quote = quote
        quoteHideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.model.quote = nil
            self.model.isPaused = false
        }
        quoteHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.8, execute: work)
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
            onHide: { [weak self] in self?.hide() },
            onReset: { [weak self] in self?.resetToAutomaticPlacement() },
            onGestureBegan: { [weak self] resize, point in self?.beginGesture(resize: resize, pointer: point) },
            onGestureChanged: { [weak self] resize, point in self?.updateGesture(resize: resize, pointer: point) },
            onGestureEnded: { [weak self] resize, point in self?.endGesture(resize: resize, pointer: point) },
            onScroll: { [weak self] delta in self?.resizeByScroll(delta) }
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
        let leftEdge = max(frame.midX + 40, rightEdge - 430)
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
        let delta = min(0.1, now.timeIntervalSince(lastTick))
        lastTick = now
        let displayID = displayID(for: screen)
        let displayChanged = displayID != activeDisplayID
        if displayChanged && !usesManualPlacement {
            activeDisplayID = displayID
            let bounds = patrolBounds(in: screen.frame)
            patrol.x = patrol.direction == .right ? bounds.lowerBound : bounds.upperBound
        }
        updateDockHeight(for: screen)
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
        let next = PatrolEngine.step(state: patrol, deltaTime: delta, speed: 31, bounds: bounds)
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
        speakNow()
    }

    private func scheduleNextQuote(initial: Bool = false) {
        quoteWorkItem?.cancel()
        let delay = initial ? 1.4 : Double.random(in: 28...52)
        let work = DispatchWorkItem { [weak self] in
            self?.speakNow()
            self?.scheduleNextQuote()
        }
        quoteWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

private extension Double {
    var nonzero: Double? { self == 0 ? nil : self }
}
