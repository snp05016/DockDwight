import AppKit
import SwiftUI

@MainActor
public final class DwightViewModel: ObservableObject {
    @Published public var frameIndex = 0
    @Published public var direction: PatrolDirection = .right
    @Published public var quote: String?
    @Published public var isPaused = false

    public init() {}
}

final class DwightAssetLoader: @unchecked Sendable {
    static let shared = DwightAssetLoader()
    private var cache: [String: NSImage] = [:]

    func image(named name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        #if SWIFT_PACKAGE
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        #else
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        #endif
        cache[name] = image
        return image
    }
}

private final class NearestSpriteView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var flippedHorizontally = false { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        context.imageInterpolation = .none
        context.shouldAntialias = false
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: floor(image.size.width * scale), height: floor(image.size.height * scale))
        let rect = CGRect(x: floor((bounds.width - size.width) / 2), y: 0, width: size.width, height: size.height)
        if flippedHorizontally {
            let transform = NSAffineTransform()
            transform.translateX(by: bounds.width, yBy: 0)
            transform.scaleX(by: -1, yBy: 1)
            transform.concat()
        }
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
        context.restoreGraphicsState()
    }
}

private struct SpriteView: NSViewRepresentable {
    let image: NSImage?
    let flipped: Bool

    func makeNSView(context: Context) -> NearestSpriteView {
        let view = NearestSpriteView()
        view.wantsLayer = true
        view.layer?.magnificationFilter = .nearest
        view.layer?.minificationFilter = .nearest
        return view
    }

    func updateNSView(_ nsView: NearestSpriteView, context: Context) {
        nsView.image = image
        nsView.flippedHorizontally = flipped
    }
}

private final class ClickCaptureView: NSView {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onLeftClick?() }
    override func rightMouseDown(with event: NSEvent) { onRightClick?() }
}

private struct ClickCapture: NSViewRepresentable {
    let onLeftClick: () -> Void
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> ClickCaptureView {
        let view = ClickCaptureView()
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: ClickCaptureView, context: Context) {
        nsView.onLeftClick = onLeftClick
        nsView.onRightClick = onRightClick
    }
}

public struct DwightView: View {
    @ObservedObject var model: DwightViewModel
    let onSpeak: () -> Void
    let onHide: () -> Void

    public init(model: DwightViewModel, onSpeak: @escaping () -> Void, onHide: @escaping () -> Void) {
        self.model = model
        self.onSpeak = onSpeak
        self.onHide = onHide
    }

    private var spriteName: String {
        if model.isPaused { return "dwight_standing" }
        return model.frameIndex == 0 ? "dwight_walk_1" : "dwight_walk_2"
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            VStack(spacing: 0) {
                if let quote = model.quote {
                    speechBubble(quote)
                        .transition(.asymmetric(insertion: .scale(scale: 0.55, anchor: .bottom).combined(with: .opacity), removal: .opacity))
                } else {
                    Spacer().frame(height: 64)
                }

                SpriteView(
                    image: DwightAssetLoader.shared.image(named: spriteName),
                    flipped: model.direction == .left
                )
                .frame(width: 90, height: 132)
                .offset(y: model.isPaused ? 0 : (model.frameIndex == 0 ? 1 : -1))
            }
            ClickCapture(onLeftClick: onSpeak, onRightClick: onHide)
                .frame(width: 106, height: 144)
        }
        .frame(width: 300, height: 210)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: model.quote)
    }

    private func speechBubble(_ quote: String) -> some View {
        VStack(spacing: 0) {
            Text(quote.uppercased())
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(Color(red: 0.07, green: 0.08, blue: 0.07))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Color(red: 1.0, green: 0.82, blue: 0.22))
                .overlay(Rectangle().stroke(.black, lineWidth: 3))
                .shadow(color: .black.opacity(0.35), radius: 0, x: 5, y: 5)
            HStack(spacing: 0) {
                Rectangle().fill(.black).frame(width: 17, height: 5)
                Rectangle().fill(Color(red: 1.0, green: 0.82, blue: 0.22)).frame(width: 12, height: 9)
            }
            .frame(width: 34, alignment: .leading)
            .offset(x: 23)
        }
        .frame(width: 270)
    }
}
