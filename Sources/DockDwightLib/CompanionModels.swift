import AppKit
import Foundation

public enum DwightActivityState: String, CaseIterable, Sendable {
    case walking
    case idle
    case talking
    case observing
    case focusWarning
    case inspecting
    case celebrating
    case sleeping
    case carried
    case landing
    case beetDrill

    public var label: String {
        switch self {
        case .walking: return "ON PATROL"
        case .idle: return "STANDING BY"
        case .talking: return "DECLARATION"
        case .observing: return "SURVEILLANCE"
        case .focusWarning: return "FOCUS BREACH"
        case .inspecting: return "INSPECTION"
        case .celebrating: return "APPROVED"
        case .sleeping: return "NIGHT WATCH"
        case .carried: return "AIRBORNE"
        case .landing: return "TACTICAL LANDING"
        case .beetDrill: return "BEET DRILL"
        }
    }
}

public enum DwightAccessory: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case classic
    case sheriff
    case beetFarmer
    case nightWatch
    case seasonal

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .classic: return "Classic"
        case .sheriff: return "Volunteer Sheriff"
        case .beetFarmer: return "Beet Farmer"
        case .nightWatch: return "Night Watch"
        case .seasonal: return "Seasonal"
        }
    }
}

public enum VisitorKind: String, CaseIterable, Sendable {
    case prankster
    case cousin
    case cat

    public var label: String {
        switch self {
        case .prankster: return "JIM ALERT"
        case .cousin: return "MOSE PASSING"
        case .cat: return "ANGELA'S CAT"
        }
    }
}

public enum WeatherMood: String, Sendable {
    case clear
    case cloudy
    case rain
    case snow
    case storm
    case unknown

    public static func classify(code: Int) -> WeatherMood {
        switch code {
        case 0, 1: return .clear
        case 2, 3, 45, 48: return .cloudy
        case 51...67, 80...82: return .rain
        case 71...77, 85, 86: return .snow
        case 95...99: return .storm
        default: return .unknown
        }
    }
}

public struct CompanionReaction: Equatable, Sendable {
    public let state: DwightActivityState
    public let message: String
    public let source: String
    public let duration: TimeInterval

    public init(state: DwightActivityState, message: String, source: String, duration: TimeInterval = 4.2) {
        self.state = state
        self.message = message
        self.source = source
        self.duration = duration
    }
}

public enum ContextualReactionEngine {
    public static func reaction(
        bundleIdentifier: String?,
        appName: String,
        focusMode: Bool,
        distractingApps: [String]
    ) -> CompanionReaction? {
        let bundle = (bundleIdentifier ?? "").lowercased()
        let name = appName.lowercased()
        if focusMode, distractingApps.contains(where: { token in
            let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !normalized.isEmpty && (name.contains(normalized) || bundle.contains(normalized))
        }) {
            return CompanionReaction(
                state: .focusWarning,
                message: "FOCUS BREACH: \(appName.uppercased()) IS NOT MISSION-CRITICAL.",
                source: appName,
                duration: 5.4
            )
        }

        if bundle.contains("xcode") || name.contains("xcode") {
            return .init(state: .inspecting, message: "I AM INSPECTING THE BUILD PIPELINE.", source: appName)
        }
        if bundle.contains("terminal") || bundle.contains("iterm") || name.contains("terminal") {
            return .init(state: .observing, message: "COMMAND-LINE AUTHORITY RECOGNIZED.", source: appName)
        }
        if bundle.contains("slack") || name.contains("slack") {
            return .init(state: .observing, message: "COMMUNICATION CHANNEL UNDER SURVEILLANCE.", source: appName)
        }
        if bundle.contains("music") || bundle.contains("spotify") || name.contains("spotify") {
            return .init(state: .celebrating, message: "ACCEPTABLE MORALE SOUNDTRACK.", source: appName)
        }
        if bundle.contains("calendar") || name.contains("calendar") {
            return .init(state: .inspecting, message: "YOUR SCHEDULE REQUIRES GREATER DISCIPLINE.", source: appName)
        }
        if bundle.contains("mail") || name == "mail" {
            return .init(state: .inspecting, message: "CORRESPONDENCE REQUIRES IMMEDIATE SORTING.", source: appName)
        }
        return nil
    }
}

public struct ActivityLogEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let source: String
    public let message: String

    public init(id: UUID = UUID(), date: Date = Date(), source: String, message: String) {
        self.id = id
        self.date = date
        self.source = source
        self.message = message
    }
}

@MainActor
public final class ActivityLogStore: ObservableObject {
    @Published public private(set) var entries: [ActivityLogEntry] = []

    public init() {}

    public func record(source: String, message: String) {
        entries.insert(.init(source: source, message: message), at: 0)
        if entries.count > 60 { entries.removeLast(entries.count - 60) }
    }

    public func clear() { entries.removeAll() }
}

@MainActor
public final class CompanionSettings: ObservableObject {
    public static let shared = CompanionSettings()

    private let defaults: UserDefaults

    @Published public var reactionsEnabled: Bool { didSet { save(reactionsEnabled, "reactionsEnabled") } }
    @Published public var soundEnabled: Bool { didSet { save(soundEnabled, "soundEnabled") } }
    @Published public var hapticsEnabled: Bool { didSet { save(hapticsEnabled, "hapticsEnabled") } }
    @Published public var focusMode: Bool { didSet { save(focusMode, "focusMode") } }
    @Published public var visitorsEnabled: Bool { didSet { save(visitorsEnabled, "visitorsEnabled") } }
    @Published public var weatherEnabled: Bool { didSet { save(weatherEnabled, "weatherEnabled") } }
    @Published public var autoSleepEnabled: Bool { didSet { save(autoSleepEnabled, "autoSleepEnabled") } }
    @Published public var personality: Double { didSet { save(personality, "personality") } }
    @Published public var walkingSpeed: Double { didSet { save(walkingSpeed, "walkingSpeed") } }
    @Published public var patrolWidth: Double { didSet { save(patrolWidth, "patrolWidth") } }
    @Published public var sleepAfterMinutes: Double { didSet { save(sleepAfterMinutes, "sleepAfterMinutes") } }
    @Published public var focusDurationMinutes: Double { didSet { save(focusDurationMinutes, "focusDurationMinutes") } }
    @Published public var accessory: DwightAccessory { didSet { save(accessory.rawValue, "accessory") } }
    @Published public var distractingAppsText: String { didSet { save(distractingAppsText, "distractingApps") } }
    @Published public var latitude: Double { didSet { save(latitude, "weatherLatitude") } }
    @Published public var longitude: Double { didSet { save(longitude, "weatherLongitude") } }

    public var distractingApps: [String] {
        distractingAppsText.split(separator: ",").map(String.init)
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "reactionsEnabled": true,
            "soundEnabled": false,
            "hapticsEnabled": true,
            "focusMode": false,
            "visitorsEnabled": true,
            "weatherEnabled": true,
            "autoSleepEnabled": true,
            "personality": 0.65,
            "walkingSpeed": 31.0,
            "patrolWidth": 430.0,
            "sleepAfterMinutes": 18.0,
            "focusDurationMinutes": 25.0,
            "accessory": DwightAccessory.automatic.rawValue,
            "distractingApps": "Chrome, Steam, Discord, TV",
            "weatherLatitude": 53.5461,
            "weatherLongitude": -113.4938
        ])
        reactionsEnabled = defaults.bool(forKey: "reactionsEnabled")
        soundEnabled = defaults.bool(forKey: "soundEnabled")
        hapticsEnabled = defaults.bool(forKey: "hapticsEnabled")
        focusMode = defaults.bool(forKey: "focusMode")
        visitorsEnabled = defaults.bool(forKey: "visitorsEnabled")
        weatherEnabled = defaults.bool(forKey: "weatherEnabled")
        autoSleepEnabled = defaults.bool(forKey: "autoSleepEnabled")
        personality = defaults.double(forKey: "personality")
        walkingSpeed = defaults.double(forKey: "walkingSpeed")
        patrolWidth = defaults.double(forKey: "patrolWidth")
        sleepAfterMinutes = defaults.double(forKey: "sleepAfterMinutes")
        focusDurationMinutes = defaults.double(forKey: "focusDurationMinutes")
        accessory = DwightAccessory(rawValue: defaults.string(forKey: "accessory") ?? "") ?? .automatic
        distractingAppsText = defaults.string(forKey: "distractingApps") ?? "Chrome, Steam, Discord, TV"
        latitude = defaults.double(forKey: "weatherLatitude")
        longitude = defaults.double(forKey: "weatherLongitude")
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
}

public extension DwightQuoteBook {
    static let contextual = [
        "Productivity is not optional.",
        "I have established a perimeter.",
        "Your desktop is now under Schrute protection.",
        "A minute wasted is a beet unharvested.",
        "This workstation has passed preliminary inspection.",
        "I do not need a break. Breaks need me."
    ]

    static func quote(seed: Int, intensity: Double, excluding previous: String? = nil) -> String {
        let pool = intensity >= 0.55 ? quotes + contextual : Array(quotes.prefix(6))
        guard !pool.isEmpty else { return "Fact." }
        var value = pool[((seed % pool.count) + pool.count) % pool.count]
        if pool.count > 1, value == previous { value = pool[(seed + 1) % pool.count] }
        return value
    }
}
