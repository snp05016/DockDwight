import AppKit
import SwiftUI

@MainActor
public final class CompanionSettingsWindowController {
    private var window: NSWindow?
    private let settings: CompanionSettings
    private let log: ActivityLogStore
    private let actions: CompanionSettingsActions

    public init(settings: CompanionSettings, log: ActivityLogStore, actions: CompanionSettingsActions) {
        self.settings = settings
        self.log = log
        self.actions = actions
    }

    public func show() {
        if window == nil { window = makeWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 590, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Schrute Command Center"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentView = NSHostingView(rootView: CompanionSettingsView(settings: settings, log: log, actions: actions))
        return window
    }
}

public struct CompanionSettingsActions {
    public let speak: () -> Void
    public let beetDrill: () -> Void
    public let resetPlacement: () -> Void
    public let showVisitor: () -> Void
    public let startFocus: () -> Void
    public let hide: () -> Void

    public init(
        speak: @escaping () -> Void,
        beetDrill: @escaping () -> Void,
        resetPlacement: @escaping () -> Void,
        showVisitor: @escaping () -> Void,
        startFocus: @escaping () -> Void,
        hide: @escaping () -> Void
    ) {
        self.speak = speak
        self.beetDrill = beetDrill
        self.resetPlacement = resetPlacement
        self.showVisitor = showVisitor
        self.startFocus = startFocus
        self.hide = hide
    }
}

private struct CompanionSettingsView: View {
    @ObservedObject var settings: CompanionSettings
    @ObservedObject var log: ActivityLogStore
    let actions: CompanionSettingsActions

    var body: some View {
        VStack(spacing: 0) {
            commandHeader
            TabView {
                behaviorTab
                    .tabItem { Label("Behavior", systemImage: "figure.walk") }
                appearanceTab
                    .tabItem { Label("Appearance", systemImage: "paintpalette") }
                focusTab
                    .tabItem { Label("Focus", systemImage: "scope") }
                logTab
                    .tabItem { Label("Schrute Log", systemImage: "list.clipboard") }
            }
            .padding(14)
        }
        .frame(minWidth: 590, minHeight: 540)
        .background(Color(red: 0.055, green: 0.07, blue: 0.10))
        .preferredColorScheme(.dark)
    }

    private var commandHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Rectangle().fill(Color(red: 1, green: 0.78, blue: 0.12)).frame(width: 42, height: 42)
                Text("D").font(.system(size: 24, weight: .black, design: .monospaced)).foregroundStyle(.black)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("SCHRUTE COMMAND CENTER")
                    .font(.system(size: 17, weight: .black, design: .monospaced))
                Text("DESKTOP SECURITY • COMPANION CONTROL")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.42, green: 0.88, blue: 0.86))
            }
            Spacer()
            Button("DECLARE") { actions.speak() }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.88, green: 0.55, blue: 0.08))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(red: 0.08, green: 0.10, blue: 0.15))
        .overlay(alignment: .bottom) { Rectangle().fill(Color(red: 1, green: 0.72, blue: 0.08)).frame(height: 2) }
    }

    private var behaviorTab: some View {
        Form {
            Section("AUTONOMY") {
                Toggle("Contextual app and device reactions", isOn: $settings.reactionsEnabled)
                Toggle("Visitor cameos", isOn: $settings.visitorsEnabled)
                Toggle("Sleep after inactivity", isOn: $settings.autoSleepEnabled)
                if settings.autoSleepEnabled {
                    LabeledContent("Sleep after") {
                        HStack {
                            Slider(value: $settings.sleepAfterMinutes, in: 2...90, step: 1)
                            Text("\(Int(settings.sleepAfterMinutes)) min").monospacedDigit().frame(width: 54)
                        }
                    }
                }
            }
            Section("PERSONALITY") {
                LabeledContent("Maximum Schrute") {
                    Slider(value: $settings.personality, in: 0...1)
                }
                LabeledContent("Walking speed") {
                    HStack {
                        Slider(value: $settings.walkingSpeed, in: 12...90, step: 1)
                        Text("\(Int(settings.walkingSpeed))").monospacedDigit().frame(width: 30)
                    }
                }
                LabeledContent("Patrol width") {
                    HStack {
                        Slider(value: $settings.patrolWidth, in: 120...900, step: 10)
                        Text("\(Int(settings.patrolWidth)) px").monospacedDigit().frame(width: 56)
                    }
                }
            }
            Section("FEEDBACK") {
                Toggle("Pixel sound effects", isOn: $settings.soundEnabled)
                Toggle("Trackpad haptics", isOn: $settings.hapticsEnabled)
            }
            HStack {
                Button("Start Beet Drill") { actions.beetDrill() }
                Button("Summon Visitor") { actions.showVisitor() }
                Spacer()
                Button("Hide Dwight") { actions.hide() }
            }
        }
        .formStyle(.grouped)
    }

    private var appearanceTab: some View {
        Form {
            Section("OUTFIT") {
                Picker("Accessory", selection: $settings.accessory) {
                    ForEach(DwightAccessory.allCases) { accessory in
                        Text(accessory.title).tag(accessory)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            Section("WEATHER AND TIME") {
                Toggle("Weather-aware accessories", isOn: $settings.weatherEnabled)
                LabeledContent("Latitude") { TextField("Latitude", value: $settings.latitude, format: .number).frame(width: 110) }
                LabeledContent("Longitude") { TextField("Longitude", value: $settings.longitude, format: .number).frame(width: 110) }
                Text("Defaults use Edmonton. Coordinates stay on this Mac and are sent only to Open-Meteo for current conditions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("PLACEMENT") {
                Button("Reset to Dock-sized automatic placement") { actions.resetPlacement() }
                Text("Drag to place • Shift-drag or scroll to resize • Double-click to reset")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var focusTab: some View {
        Form {
            Section("FOCUS SUPERVISOR") {
                Toggle("Enable focus supervision", isOn: $settings.focusMode)
                Text("When enabled, Dwight flags distracting foreground apps without reading window contents or recording what you type.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Distracting apps, comma separated", text: $settings.distractingAppsText, axis: .vertical)
                    .lineLimit(3...6)
                LabeledContent("Session length") {
                    HStack {
                        Slider(value: $settings.focusDurationMinutes, in: 5...90, step: 5)
                        Text("\(Int(settings.focusDurationMinutes)) min").monospacedDigit().frame(width: 58)
                    }
                }
                Button("Start timed focus patrol") { actions.startFocus() }
            }
            Section("LOCAL ROUTINE LEARNING") {
                Text("DockDwight stores only hourly activation counts and the last app name in local preferences. No documents, URLs, keystrokes, or screen contents are collected.")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
    }

    private var logTab: some View {
        VStack(spacing: 10) {
            HStack {
                Text("RECENT INCIDENTS").font(.system(size: 12, weight: .black, design: .monospaced))
                Spacer()
                Button("Clear") { log.clear() }
            }
            if log.entries.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "checkmark.shield").font(.system(size: 34)).foregroundStyle(.green)
                    Text("NO INCIDENTS").font(.system(size: 13, weight: .black, design: .monospaced))
                    Text("The perimeter is secure.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(log.entries) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Text(entry.date, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 62, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.source.uppercased()).font(.caption.bold())
                            Text(entry.message).font(.callout)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(10)
    }
}
