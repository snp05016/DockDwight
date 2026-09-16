import AppKit
import CoreGraphics
import Foundation
import IOKit.ps

@MainActor
public final class ContextMonitor {
    public var onReaction: ((CompanionReaction) -> Void)?
    public var onIdleChanged: ((Bool) -> Void)?
    public var onWeather: ((WeatherMood, Int?) -> Void)?

    private let settings: CompanionSettings
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var weatherTimer: Timer?
    private var wasIdle = false
    private var lastBatteryWarning = Date.distantPast
    private var lastBundleIdentifier: String?

    public init(settings: CompanionSettings) {
        self.settings = settings
    }

    public func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated { self?.handleApplication(note) }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            let name = (note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)?.lastPathComponent ?? "External drive"
            MainActor.assumeIsolated {
                self?.onReaction?(.init(state: .inspecting, message: "NEW STORAGE DEVICE: \(name.uppercased()). INSPECTION REQUIRED.", source: "Drive"))
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] note in
            let name = (note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL)?.lastPathComponent ?? "External drive"
            MainActor.assumeIsolated {
                self?.onReaction?(.init(state: .celebrating, message: "\(name.uppercased()) DEPARTED SAFELY.", source: "Drive"))
            }
        })
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.saumya.DeviceArrivalHUD.event"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            let name = note.userInfo?["name"] as? String ?? "DEVICE"
            let connected = note.userInfo?["connected"] as? Bool ?? true
            let battery = note.userInfo?["battery"] as? Int
            let suffix = battery.map { " BATTERY \($0)%." } ?? ""
            let message = connected
                ? "\(name.uppercased()) CONNECTED. SECURITY CLEARED.\(suffix)"
                : "\(name.uppercased()) HAS LEFT THE PERIMETER."
            MainActor.assumeIsolated {
                self?.onReaction?(.init(state: connected ? .celebrating : .observing, message: message, source: "Device"))
            }
        })

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollSystemContext() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        refreshWeather()
        let weatherTimer = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshWeather() }
        }
        self.weatherTimer = weatherTimer
        RunLoop.main.add(weatherTimer, forMode: .common)
    }

    public func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll()
        timer?.invalidate()
        weatherTimer?.invalidate()
    }

    private func handleApplication(_ note: Notification) {
        guard settings.reactionsEnabled,
              let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let name = app.localizedName ?? "Application"
        if app.bundleIdentifier == lastBundleIdentifier { return }
        lastBundleIdentifier = app.bundleIdentifier
        if let reaction = ContextualReactionEngine.reaction(
            bundleIdentifier: app.bundleIdentifier,
            appName: name,
            focusMode: settings.focusMode,
            distractingApps: settings.distractingApps
        ) {
            onReaction?(reaction)
        }
        RoutineTracker.record(appName: name)
    }

    private func pollSystemContext() {
        let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
        let threshold = max(60, settings.sleepAfterMinutes * 60)
        let idle = settings.autoSleepEnabled && idleSeconds >= threshold
        if idle != wasIdle {
            wasIdle = idle
            onIdleChanged?(idle)
        }

        if let battery = Self.batteryPercentage(), battery <= 15,
           Date().timeIntervalSince(lastBatteryWarning) > 30 * 60 {
            lastBatteryWarning = Date()
            onReaction?(.init(state: .focusWarning, message: "BATTERY AT \(battery)%. CONNECT POWER IMMEDIATELY.", source: "Power", duration: 6))
        }
    }

    private func refreshWeather() {
        guard settings.weatherEnabled else {
            onWeather?(.unknown, nil)
            return
        }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            .init(name: "latitude", value: String(settings.latitude)),
            .init(name: "longitude", value: String(settings.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code"),
            .init(name: "timezone", value: "auto")
        ]
        guard let url = components?.url else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = object["current"] as? [String: Any],
                  let code = current["weather_code"] as? Int else { return }
            let temperature = (current["temperature_2m"] as? Double).map { Int($0.rounded()) }
            Task { @MainActor in self?.onWeather?(WeatherMood.classify(code: code), temperature) }
        }.resume()
    }

    private static func batteryPercentage() -> Int? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0 else { continue }
            return Int((Double(current) / Double(maximum) * 100).rounded())
        }
        return nil
    }
}

private enum RoutineTracker {
    static func record(appName: String, defaults: UserDefaults = .standard) {
        let hour = Calendar.current.component(.hour, from: Date())
        let key = "routine.hour.\(hour)"
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
        defaults.set(appName, forKey: "routine.lastApp")
    }
}
