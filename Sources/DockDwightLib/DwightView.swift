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
    @Published public var activityState: DwightActivityState = .walking
    @Published public var statusText: String?
    @Published public var accessory: DwightAccessory = .automatic
    @Published public var weatherMood: WeatherMood = .unknown
    @Published public var temperature: Int?
    @Published public var visitor: VisitorKind?
    @Published public var effectPulse = 0
    @Published public var miniGameActive = false
    @Published public var beetScore = 0

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
    var onSettings: (() -> Void)?
    var onBeetTap: (() -> Void)?
    private var isDragging = false
    private var isResizing = false
    private var hasBegunGesture = false
    private var suppressClick = false
    private var startPoint = CGPoint.zero

    override func mouseDown(with event: NSEvent) {
        isDragging = false
        hasBegunGesture = false
        suppressClick = false
        if event.clickCount >= 3 {
            suppressClick = true
            onBeetTap?()
            return
        }
        if event.clickCount >= 2 {
            suppressClick = true
            onReset?()
            return
        }
        if event.modifierFlags.contains(.option) {
            suppressClick = true
            onSettings?()
            return
        }
        startPoint = NSEvent.mouseLocation
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
        } else if !suppressClick && event.clickCount < 2 {
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
    let onSettings: () -> Void
    let onBeetTap: () -> Void

    func makeNSView(context: Context) -> ClickCaptureView {
        let view = ClickCaptureView()
        view.onLeftClick = onLeftClick
        view.onRightClick = onRightClick
        view.onReset = onReset
        view.onGestureBegan = onGestureBegan
        view.onGestureChanged = onGestureChanged
        view.onGestureEnded = onGestureEnded
        view.onScroll = onScroll
        view.onSettings = onSettings
        view.onBeetTap = onBeetTap
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
        nsView.onSettings = onSettings
        nsView.onBeetTap = onBeetTap
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
    let onSettings: () -> Void
    let onBeetTap: () -> Void

    public init(
        model: DwightViewModel,
        onSpeak: @escaping () -> Void,
        onHide: @escaping () -> Void,
        onReset: @escaping () -> Void,
        onGestureBegan: @escaping (Bool, CGPoint) -> Void,
        onGestureChanged: @escaping (Bool, CGPoint) -> Void,
        onGestureEnded: @escaping (Bool, CGPoint) -> Void,
        onScroll: @escaping (CGFloat) -> Void,
        onSettings: @escaping () -> Void,
        onBeetTap: @escaping () -> Void
    ) {
        self.model = model
        self.onSpeak = onSpeak
        self.onHide = onHide
        self.onReset = onReset
        self.onGestureBegan = onGestureBegan
        self.onGestureChanged = onGestureChanged
        self.onGestureEnded = onGestureEnded
        self.onScroll = onScroll
        self.onSettings = onSettings
        self.onBeetTap = onBeetTap
    }

    private var spriteName: String {
        switch model.activityState {
        case .sleeping: return "dwight_sleeping"
        case .inspecting, .observing, .focusWarning: return "dwight_inspecting"
        case .celebrating: return "dwight_celebrating"
        default: break
        }
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
                    statusHeader
                        .frame(height: 64, alignment: .bottom)
                }

                ZStack(alignment: .bottom) {
                    if let visitor = model.visitor {
                        PixelVisitorView(kind: visitor)
                            .frame(width: characterHeight * 0.48, height: characterHeight * 0.72)
                            .offset(x: model.direction == .right ? -characterHeight * 0.48 : characterHeight * 0.48)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    SpriteView(
                        image: DwightAssetLoader.shared.image(named: spriteName),
                        flipped: model.direction == .left
                    )
                    .frame(width: characterHeight * 0.68, height: characterHeight)
                    .rotationEffect(.degrees(model.activityState == .carried ? Double(model.direction.rawValue) * 8 : 0))
                    .scaleEffect(x: model.activityState == .landing ? 1.10 : 1, y: model.activityState == .landing ? 0.88 : 1, anchor: .bottom)
                    .opacity(model.activityState == .sleeping ? 0.74 : 1)
                    .offset(y: spriteYOffset)

                    PixelAccessoryView(accessory: resolvedAccessory, weather: model.weatherMood)
                        .frame(width: characterHeight * 0.50, height: characterHeight * 0.45)
                        .offset(y: characterHeight * 0.54)

                    if model.activityState == .landing {
                        LandingDustView(pulse: model.effectPulse)
                            .frame(width: characterHeight * 1.2, height: 15)
                    }
                    if model.miniGameActive {
                        BeetDrillView(score: model.beetScore, pulse: model.effectPulse)
                            .frame(width: 132, height: 60)
                            .offset(y: 20)
                    }
                }
            }
            ClickCapture(
                onLeftClick: onSpeak,
                onRightClick: onHide,
                onReset: onReset,
                onGestureBegan: onGestureBegan,
                onGestureChanged: onGestureChanged,
                onGestureEnded: onGestureEnded,
                onScroll: onScroll,
                onSettings: onSettings,
                onBeetTap: onBeetTap
            )
            .frame(width: max(48, characterHeight * 0.82), height: max(48, characterHeight + 8))
        }
        .frame(width: 300, height: 210)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: model.quote)
        .animation(.spring(response: 0.28, dampingFraction: 0.66), value: model.activityState)
        .animation(.spring(response: 0.4, dampingFraction: 0.72), value: model.visitor)
    }

    private var spriteYOffset: CGFloat {
        switch model.activityState {
        case .carried: return 12
        case .celebrating: return model.effectPulse.isMultiple(of: 2) ? 5 : 0
        case .sleeping: return -2
        default: return model.isPaused ? 0 : (model.frameIndex == 0 ? 1 : -1)
        }
    }

    private var resolvedAccessory: DwightAccessory {
        guard model.accessory == .automatic else { return model.accessory }
        if model.weatherMood == .snow || model.weatherMood == .rain { return .seasonal }
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 22 || hour < 6 ? .nightWatch : .classic
    }

    @ViewBuilder
    private var statusHeader: some View {
        if let status = model.statusText {
            HStack(spacing: 5) {
                Circle()
                    .fill(model.activityState == .focusWarning ? Color.red : Color(red: 0.22, green: 0.91, blue: 0.78))
                    .frame(width: 6, height: 6)
                Text(status)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .lineLimit(1)
                if let temperature = model.temperature { Text("\(temperature)°").font(.system(size: 8, weight: .bold, design: .monospaced)) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.84))
            .overlay(Rectangle().stroke(model.activityState == .focusWarning ? Color.red : Color(red: 0.96, green: 0.67, blue: 0.08), lineWidth: 2))
        } else {
            Color.clear
        }
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

private struct PixelAccessoryView: View {
    let accessory: DwightAccessory
    let weather: WeatherMood

    var body: some View {
        ZStack {
            switch accessory {
            case .automatic, .classic:
                EmptyView()
            case .sheriff:
                Text("★").font(.system(size: 12, weight: .black)).foregroundStyle(Color.yellow)
                    .background(Rectangle().fill(.black).frame(width: 14, height: 14))
            case .beetFarmer:
                VStack(spacing: 0) {
                    Rectangle().fill(Color(red: 0.26, green: 0.14, blue: 0.07)).frame(width: 24, height: 4)
                    Rectangle().fill(Color(red: 0.36, green: 0.20, blue: 0.09)).frame(width: 15, height: 7)
                }
            case .nightWatch:
                Text("Z").font(.system(size: 12, weight: .black, design: .monospaced)).foregroundStyle(.cyan).offset(x: 14, y: -6)
            case .seasonal:
                Text(weather == .snow ? "❄" : weather == .rain ? "▱" : "◆")
                    .font(.system(size: 13, weight: .black)).foregroundStyle(weather == .snow ? .white : .cyan)
            }
        }
    }
}

private struct PixelVisitorView: View {
    let kind: VisitorKind

    var body: some View {
        VStack(spacing: 0) {
            if kind == .cat {
                HStack(spacing: 5) {
                    Rectangle().frame(width: 5, height: 7)
                    Rectangle().frame(width: 5, height: 7)
                }
                Rectangle().frame(width: 23, height: 14)
                HStack(spacing: 12) {
                    Rectangle().frame(width: 4, height: 9)
                    Rectangle().frame(width: 4, height: 9)
                }
            } else {
                Rectangle().fill(kind == .prankster ? Color(red: 0.87, green: 0.72, blue: 0.55) : Color(red: 0.65, green: 0.34, blue: 0.18)).frame(width: 18, height: 16)
                Rectangle().fill(kind == .prankster ? Color(red: 0.30, green: 0.42, blue: 0.56) : Color(red: 0.28, green: 0.38, blue: 0.16)).frame(width: 24, height: 24)
                HStack(spacing: 6) {
                    Rectangle().fill(Color(red: 0.16, green: 0.14, blue: 0.14)).frame(width: 7, height: 24)
                    Rectangle().fill(Color(red: 0.16, green: 0.14, blue: 0.14)).frame(width: 7, height: 24)
                }
            }
        }
        .foregroundStyle(Color(red: 0.45, green: 0.44, blue: 0.43))
        .overlay(alignment: .top) {
            Text(kind == .cat ? "CAT" : kind == .prankster ? "J" : "M")
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}

private struct LandingDustView: View {
    let pulse: Int
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { index in
                Rectangle()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: index.isMultiple(of: 2) ? 5 : 3, height: 3)
                    .offset(x: CGFloat(index - 2) * CGFloat(pulse % 3 + 1), y: CGFloat(abs(index - 2)) * -2)
            }
        }
    }
}

private struct BeetDrillView: View {
    let score: Int
    let pulse: Int
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                VStack(spacing: 0) {
                    Rectangle().fill(.green).frame(width: 3, height: 6).rotationEffect(.degrees(index == 1 ? 20 : -20))
                    Circle().fill(Color(red: 0.55, green: 0.06, blue: 0.20)).frame(width: 13, height: 13)
                }
                .offset(y: CGFloat((pulse + index) % 3) * -4)
            }
            Text("×\(score)").font(.system(size: 9, weight: .black, design: .monospaced)).foregroundStyle(.white)
        }
        .padding(5)
        .background(Color.black.opacity(0.76))
        .overlay(Rectangle().stroke(Color(red: 0.95, green: 0.68, blue: 0.08), lineWidth: 2))
    }
}
