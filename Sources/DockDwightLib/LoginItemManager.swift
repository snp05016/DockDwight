import Foundation
import ServiceManagement

public final class LoginItemManager: @unchecked Sendable {
    public static let shared = LoginItemManager()
    public static let appName = "DockDwight"
    public static let appPath = "/Applications/DockDwight.app"

    public init() {}

    public var isEnabled: Bool {
        if #available(macOS 13.0, *), Bundle.main.bundleIdentifier == "com.saumya.DockDwight",
           SMAppService.mainApp.status == .enabled { return true }
        return appleScript("tell application \"System Events\" to return exists (login item \"\(Self.appName)\")")
    }

    @discardableResult
    public func enable() -> Bool {
        if #available(macOS 13.0, *), Bundle.main.bundleIdentifier == "com.saumya.DockDwight" {
            do {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
                if SMAppService.mainApp.status == .enabled { return true }
            } catch {}
        }
        return appleScript("""
        tell application "System Events"
            if exists (login item "\(Self.appName)") then delete login item "\(Self.appName)"
            make login item at end with properties {path:"\(Self.appPath)", hidden:true, name:"\(Self.appName)"}
            return exists (login item "\(Self.appName)")
        end tell
        """)
    }

    @discardableResult
    public func disable() -> Bool {
        if #available(macOS 13.0, *), Bundle.main.bundleIdentifier == "com.saumya.DockDwight" {
            try? SMAppService.mainApp.unregister()
        }
        return appleScript("""
        tell application "System Events"
            if exists (login item "\(Self.appName)") then delete login item "\(Self.appName)"
            return not (exists (login item "\(Self.appName)"))
        end tell
        """)
    }

    private func appleScript(_ source: String) -> Bool {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run(); process.waitUntilExit()
            let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            return process.terminationStatus == 0 && text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
        } catch { return false }
    }
}

