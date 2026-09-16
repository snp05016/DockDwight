import AppKit
import CoreGraphics
import Foundation

public enum WindowAwareness {
    public static func appKitRect(fromQuartzBounds bounds: CGRect, desktopTop: CGFloat) -> CGRect {
        CGRect(x: bounds.minX, y: desktopTop - bounds.maxY, width: bounds.width, height: bounds.height)
    }

    public static func blockingApplication(at point: CGPoint, excludingPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> String? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let desktopTop = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        for window in windows {
            let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  ownerPID != excludingPID,
                  let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let quartzRect = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { continue }
            let rect = appKitRect(fromQuartzBounds: quartzRect, desktopTop: desktopTop)
            guard rect.width > 180, rect.height > 120, rect.insetBy(dx: -8, dy: -8).contains(point) else { continue }
            return window[kCGWindowOwnerName as String] as? String ?? "WINDOW"
        }
        return nil
    }
}
