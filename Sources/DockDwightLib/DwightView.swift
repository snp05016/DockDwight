import AppKit
import SwiftUI

@MainActor
public final class DwightViewModel: ObservableObject {
    @Published public var frameIndex = 0
    @Published public var direction: PatrolDirection = .right
    @Published public var quote: String?
    @Published public var isPaused = false
    @Published public var dockHeight: CGFloat = 56
    @Published public var userScale: CGFloat = 1

    public init() {}
}

final class DwightAssetLoader: @unchecked Sendable {
    static let shared = DwightAssetLoader()
    private var cache: [String: NSImage] = [:]

    func image(named name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        #if SWIFT_PACKAGE
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let sourceImage = NSImage(contentsOf: url) else { return nil }
        #else
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let sourceImage = NSImage(contentsOf: url) else { return nil }
        #endif
        let image = Self.croppedToVisiblePixels(sourceImage) ?? sourceImage
        cache[name] = image
        return image
    }

    private static func croppedToVisiblePixels(_ image: NSImage) -> NSImage? {
        var proposed = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * bytesPerRow + x * 4 + 3] > 20 {
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let crop = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let cropped = cgImage.cropping(to: crop) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: crop.width, height: crop.height))
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
    var onReset: (() -> Void)?
    var onGestureBegan: ((Bool, CGPoint) -> Void)?
    var onGestureChanged: ((Bool, CGPoint) -> Void)?
    var onGestureEnded: ((Bool, CGPoint) -> Void)?
    var onScroll: ((CGFloat) -> Void)?
    private var isDragging = false
    private var isResizing = false
    private var hasBegunGesture = false
    private var startPoint = CGPoint.zero

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onReset?()
            return
        }
        startPoint = NSEvent.mouseLocation
        isDragging = false
        hasBegunGesture = false
        isResizing = event.modifierFlags.contains(.shift)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        if hypot(point.x - startPoint.x, point.y - startPoint.y) > 2 { isDragging = true }
        if isDragging {
            if !hasBegunGesture {
                hasBegunGesture = true
                onGestureBegan?(isResizing, startPoint)
            }
            onGestureChanged?(isResizing, point)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            onGestureEnded?(isResizing, NSEvent.mouseLocation)
        } else if event.clickCount < 2 {
            onLeftClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) { onRightClick?() }
    override func scrollWheel(with event: NSEvent) { onScroll?(event.scrollingDeltaY) }
}

private struct ClickCapture: NSViewRepresentable {
    let onLeftClick: () -> Void
    let onRightClick: () -> Void
    let onReset: () -> Void
    let onGestureBegan: (Bool, CGPoint) -> Void
    let onGestureChanged: (Bool, CGPoint) -> Void
    let onGestureEnded: (Bool, CGPoint) -> Void
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ClickCaptureView {
        let view = ClickCaptureView()
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        view.onReset = onReset
        view.onGestureBegan = onGestureBegan
        view.onGestureChanged = onGestureChanged
        view.onGestureEnded = onGestureEnded
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ClickCaptureView, context: Context) {
        nsView.onLeftClick = onLeftClick
        nsView.onRightClick = onRightClick
        nsView.onReset = onReset
        nsView.onGestureBegan = onGestureBegan
        nsView.onGestureChanged = onGestureChanged
        nsView.onGestureEnded = onGestureEnded
        nsView.onScroll = onScroll
    }
}

public struct DwightView: View {
    @ObservedObject var model: DwightViewModel
    let onSpeak: () -> Void
    let onHide: () -> Void
    let onReset: () -> Void
    let onGestureBegan: (Bool, CGPoint) -> Void
    let onGestureChanged: (Bool, CGPoint) -> Void
    let onGestureEnded: (Bool, CGPoint) -> Void
    let onScroll: (CGFloat) -> Void

    public init(
        model: DwightViewModel,
        onSpeak: @escaping () -> Void,
        onHide: @escaping () -> Void,
        onReset: @escaping () -> Void,
        onGestureBegan: @escaping (Bool, CGPoint) -> Void,
        onGestureChanged: @escaping (Bool, CGPoint) -> Void,
        onGestureEnded: @escaping (Bool, CGPoint) -> Void,
        onScroll: @escaping (CGFloat) -> Void
    ) {
        self.model = model
        self.onSpeak = onSpeak
        self.onHide = onHide
        self.onReset = onReset
        self.onGestureBegan = onGestureBegan
        self.onGestureChanged = onGestureChanged
        self.onGestureEnded = onGestureEnded
        self.onScroll = onScroll
    }

    private var spriteName: String {
        if model.isPaused { return "dwight_standing" }
        return model.frameIndex == 0 ? "dwight_walk_1" : "dwight_walk_2"
    }

    public var body: some View {
        let characterHeight = model.dockHeight * model.userScale
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
                .frame(width: characterHeight * 0.68, height: characterHeight)
                .offset(y: model.isPaused ? 0 : (model.frameIndex == 0 ? 1 : -1))
            }
            ClickCapture(
                onLeftClick: onSpeak,
                onRightClick: onHide,
                onReset: onReset,
                onGestureBegan: onGestureBegan,
                onGestureChanged: onGestureChanged,
                onGestureEnded: onGestureEnded,
                onScroll: onScroll
            )
            .frame(width: max(48, characterHeight * 0.82), height: max(48, characterHeight + 8))
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
