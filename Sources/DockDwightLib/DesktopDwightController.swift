import AppKit
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
    private(set) public var isVisible = true

    public init() {}

    public func start() {
        let panel = makePanel()
        self.panel = panel
        placeAtPatrolStart(panel)
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
        panel.contentView = NSHostingView(rootView: DwightView(model: model, onSpeak: { [weak self] in self?.speakNow() }, onHide: { [weak self] in self?.hide() }))
        panel.setContentSize(Self.panelSize)
        return panel
    }

    private func placeAtPatrolStart(_ panel: NSPanel) {
        guard let frame = NSScreen.main?.visibleFrame else { return }
        let bounds = patrolBounds(in: frame)
        patrol = PatrolState(x: bounds.lowerBound, direction: .right)
        panel.setFrameOrigin(CGPoint(x: patrol.x, y: frame.minY - 38))
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
        guard let panel, let screen = NSScreen.main else { return }
        let now = Date()
        let delta = min(0.1, now.timeIntervalSince(lastTick))
        lastTick = now
        guard isVisible, now >= pauseUntil else { return }

        let next = PatrolEngine.step(state: patrol, deltaTime: delta, speed: 31, bounds: patrolBounds(in: screen.visibleFrame))
        patrol = next
        model.direction = next.direction
        frameAccumulator += delta
        if frameAccumulator >= 0.24 {
            frameAccumulator = 0
            model.frameIndex = (model.frameIndex + 1) % 2
        }
        panel.setFrameOrigin(CGPoint(x: next.x, y: screen.visibleFrame.minY - 38))
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
