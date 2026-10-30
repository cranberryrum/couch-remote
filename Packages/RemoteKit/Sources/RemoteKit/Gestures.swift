import Foundation

/// Turns a continuous value (e.g. change in the distance between two fingers) into whole steps,
/// carrying the remainder so slow, jittery pinches still add up and nothing is lost between events.
public struct StepAccumulator: Sendable, Equatable {
    public let stepSize: Double
    private var accumulated = 0.0

    public init(stepSize: Double) {
        precondition(stepSize > 0, "stepSize must be positive")
        self.stepSize = stepSize
    }

    /// Adds `delta` and returns the number of whole steps crossed: positive, negative, or 0.
    public mutating func add(_ delta: Double) -> Int {
        accumulated += delta
        let steps = Int((accumulated / stepSize).rounded(.towardZero))
        accumulated -= Double(steps) * stepSize
        return steps
    }

    public mutating func reset() {
        accumulated = 0
    }
}

/// Decides whether two fingers that just started moving mean "scroll" (they travel together) or
/// "pinch" (the distance between them changes). It decides once and sticks with that: a scroll
/// that drifts apart mid-way stays a scroll, and a pinch that drifts sideways stays a pinch.
public struct TwoFingerClassifier: Sendable {
    public enum Intent: Equatable, Sendable {
        case undecided
        case scroll
        case pinch
    }

    public private(set) var intent = Intent.undecided

    private let startDistance: Double
    private let startX: Double
    private let startY: Double
    private let slop: Double
    private let pinchBias: Double

    /// - Parameters:
    ///   - slop: how far (points) the fingers must move before it decides.
    ///   - pinchBias: it's a pinch when the change in finger spread exceeds this multiple of how far
    ///     the midpoint travelled. One finger moving alone gives a ratio of 2, parallel fingers ~0.
    public init(startDistance: Double, startX: Double, startY: Double, slop: Double, pinchBias: Double) {
        self.startDistance = startDistance
        self.startX = startX
        self.startY = startY
        self.slop = slop
        self.pinchBias = pinchBias
    }

    public mutating func update(distance: Double, centroidX: Double, centroidY: Double) -> Intent {
        guard intent == .undecided else { return intent }
        let spread = abs(distance - startDistance)
        let travel = hypot(centroidX - startX, centroidY - startY)
        guard max(spread, travel) > slop else { return .undecided }
        intent = spread > travel * pinchBias ? .pinch : .scroll
        return intent
    }
}
