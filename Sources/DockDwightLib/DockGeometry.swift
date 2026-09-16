import CoreGraphics
import Foundation

public enum DockGeometry {
    public static func characterHeight(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        configuredTileSize: CGFloat?
    ) -> CGFloat {
        if let configuredTileSize, configuredTileSize > 0 {
            return min(160, max(32, configuredTileSize))
        }

        let bottomInset = max(0, visibleFrame.minY - screenFrame.minY)
        let leftInset = max(0, visibleFrame.minX - screenFrame.minX)
        let rightInset = max(0, screenFrame.maxX - visibleFrame.maxX)
        let inferred = max(bottomInset, leftInset, rightInset) - 12
        return min(160, max(32, inferred > 8 ? inferred : 56))
    }
}

