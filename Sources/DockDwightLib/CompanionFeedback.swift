import AppKit
import AVFoundation
import Foundation

@MainActor
public final class CompanionFeedback {
    private let settings: CompanionSettings
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate = 44_100.0

    public init(settings: CompanionSettings) {
        self.settings = settings
        engine.attach(player)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    public func play(for state: DwightActivityState) {
        if settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(
                state == .focusWarning || state == .landing ? .levelChange : .alignment,
                performanceTime: .now
            )
        }
        guard settings.soundEnabled else { return }
        let notes: [Double]
        switch state {
        case .celebrating: notes = [523, 659, 784, 1_047]
        case .focusWarning: notes = [220, 165, 110]
        case .landing: notes = [150, 95]
        case .beetDrill: notes = [392, 523]
        case .inspecting, .observing: notes = [262, 330]
        default: notes = [330]
        }
        playChiptune(notes)
    }

    private func playChiptune(_ notes: [Double]) {
        let noteDuration = 0.055
        let frameCount = AVAudioFrameCount(sampleRate * noteDuration * Double(notes.count))
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let noteIndex = min(notes.count - 1, Int(time / noteDuration))
            let localTime = time - Double(noteIndex) * noteDuration
            let envelope = Float(max(0, 1 - localTime / noteDuration))
            let square: Float = sin(2 * .pi * notes[noteIndex] * localTime) >= 0 ? 1 : -1
            channel[frame] = square * envelope * 0.045
        }
        do {
            if !engine.isRunning { try engine.start() }
            player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            if !player.isPlaying { player.play() }
        } catch {
            // Visual feedback and haptics remain available if the audio route cannot start.
        }
    }
}
