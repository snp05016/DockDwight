import AppKit
import Carbon
import DockDwightLib
import Foundation

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let dwight = DesktopDwightController()
    private var hotKey: HotKeyController?
    private var settingsHotKey: HotKeyController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        dwight.start()
        let hotKey = HotKeyController { [weak self] in
            DispatchQueue.main.async { self?.dwight.toggleVisibility() }
        }
        self.hotKey = hotKey
        _ = hotKey.register()
        let settingsHotKey = HotKeyController(keyCode: UInt32(kVK_ANSI_Comma), id: 2) { [weak self] in
            DispatchQueue.main.async { self?.dwight.showSettings() }
        }
        self.settingsHotKey = settingsHotKey
        _ = settingsHotKey.register()
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--enable-login") {
    print(LoginItemManager.shared.enable() ? "enabled" : "failed")
    exit(LoginItemManager.shared.isEnabled ? 0 : 1)
}
if arguments.contains("--disable-login") {
    print(LoginItemManager.shared.disable() ? "disabled" : "failed")
    exit(LoginItemManager.shared.isEnabled ? 1 : 0)
}
if arguments.contains("--status-login") {
    print(LoginItemManager.shared.isEnabled ? "enabled" : "disabled")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
private let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
