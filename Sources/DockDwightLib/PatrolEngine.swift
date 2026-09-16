import CoreGraphics
import Foundation

public enum PatrolDirection: Int, Sendable {
    case left = -1
    case right = 1
}

public struct PatrolState: Equatable, Sendable {
    public var x: CGFloat
    public var direction: PatrolDirection

    public init(x: CGFloat, direction: PatrolDirection = .right) {
        self.x = x
        self.direction = direction
    }
}

public enum PatrolEngine {
    public static func step(
        state: PatrolState,
        deltaTime: TimeInterval,
        speed: CGFloat,
        bounds: ClosedRange<CGFloat>
    ) -> PatrolState {
        guard bounds.lowerBound < bounds.upperBound else {
            return PatrolState(x: bounds.lowerBound, direction: state.direction)
        }
        var direction = state.direction
        var next = state.x + CGFloat(direction.rawValue) * speed * deltaTime
        if next >= bounds.upperBound {
            next = bounds.upperBound
            direction = .left
        } else if next <= bounds.lowerBound {
            next = bounds.lowerBound
            direction = .right
        }
        return PatrolState(x: next, direction: direction)
    }
}

public enum DwightQuoteBook {
    public static let quotes = [
        "Identity theft is not a joke, Jim!",
        "Question: What kind of bear is best?",
        "Fact: I am faster than 80% of all snakes.",
        "Before I do anything, I ask: would an idiot do that?",
        "Nothing stresses me out. Except having to seek approval.",
        "I am ready to face any challenge foolish enough to face me.",
        "Security level: Assistant Regional Manager.",
        "The Schrutes have their own traditions.",
        "False. This workstation is now secure.",
        "Bears. Beets. Battlestar Galactica."
    ]

    public static func quote(at index: Int, excluding previous: String? = nil) -> String {
        guard !quotes.isEmpty else { return "Fact." }
        var selected = quotes[((index % quotes.count) + quotes.count) % quotes.count]
        if quotes.count > 1, selected == previous {
            selected = quotes[(index + 1) % quotes.count]
        }
        return selected
    }
}

