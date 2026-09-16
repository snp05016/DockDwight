import AppKit
import Foundation

@MainActor
public final class CompanionFeedback {
    private let settings: CompanionSettings

    public init(settings: CompanionSettings) {
        self.settings = settings
    }

    public func play(for state: DwightActivityState) {
        if settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(
                state == .focusWarning || state == .landing ? .levelChange : .alignment,
                performanceTime: .now
            )
        }
        guard settings.soundEnabled else { return }
        let soundName: NSSound.Name
        switch state {
        case .celebrating: soundName = .init("Glass")
        case .focusWarning: soundName = .init("Basso")
        case .landing: soundName = .init("Pop")
        case .beetDrill: soundName = .init("Tink")
        default: soundName = .init("Morse")
        }
        NSSound(named: soundName)?.play()
    }
}
