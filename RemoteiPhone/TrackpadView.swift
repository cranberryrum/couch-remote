import RemoteKit
import SwiftUI
import UIKit

struct TrackpadView: UIViewRepresentable {
    let client: RemoteClient
    var night = false

    func makeUIView(context: Context) -> TrackpadUIView {
        let view = TrackpadUIView()
        view.send = { [client] message in client.send(message) }
        view.backgroundColor = Theme(night: night).surfaceUIColor
        return view
    }

    func updateUIView(_ uiView: TrackpadUIView, context: Context) {
        uiView.backgroundColor = Theme(night: night).surfaceUIColor
    }
}

/// Raw multi-touch surface. A "session" runs from first finger down to last finger up.
///
/// - 1 finger drags the cursor (deltas coalesced and sent once per display frame).
/// - 2 fingers scroll (with synthesized momentum); a quick still 2-finger touch is a right click.
/// - A quick still 1-finger touch is a left click; repeated taps escalate the click count.
/// - Tap, then touch down again quickly and move: a drag (button held until lift-off).
/// - Two fingers moving apart / together: pinch, which zooms the page (⌘= / ⌘-) a step at a time.
/// - 3+ fingers are ignored.
final class TrackpadUIView: UIView {
    var send: (Message) -> Void = { _ in }

    private enum Mode {
        case idle
        case pointer
        case scroll
        case pinch
        case spent // gesture finished (or unsupported); ignore until every finger lifts
    }

    private struct Momentum {
        var velocity: CGVector
        var hasBegun = false
    }

    private var mode = Mode.idle
    private var touchStarts: [UITouch: CGPoint] = [:]
    private var sessionStart: TimeInterval = 0
    private var maxTouches = 0
    private var maxTravel: CGFloat = 0

    // Pointer
    private var pointerEngaged = false
    private var heldBackPointer = CGVector.zero
    private var pendingMove = CGVector.zero
    private var lastPointerTimestamp: TimeInterval = 0

    // Scroll
    private var scrollCentroid: CGPoint?
    private var scrollBegan = false
    private var heldBackScroll = CGVector.zero
    private var pendingScroll = CGVector.zero
    private var nextScrollPhase = ScrollPhase.began
    private var scrollSamples: [(time: TimeInterval, delta: CGVector)] = []
    private var momentum: Momentum?

    // Taps
    private var lastTap: (time: TimeInterval, count: Int)?

    // Pinch (two-finger zoom). The classifier decides scroll vs. pinch before a scroll begins.
    private var classifier: TwoFingerClassifier?
    private var pinchSteps = StepAccumulator(stepSize: Double(Tuning.pinchStepDistance))
    private var pinchLastSpread: CGFloat = 0
    private let selectionHaptic = UISelectionFeedbackGenerator()

    // Drag (tap-then-hold-and-move)
    private var dragCandidate = false
    private var isDragging = false

    private var displayLink: CADisplayLink?
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = UIColor(white: 0.09, alpha: 1)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Display link

    override func didMoveToWindow() {
        super.didMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        guard window != nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        flushMove()
        flushScroll()
        stepMomentum(frameDuration: link.targetTimestamp - link.timestamp)

        if touchStarts.isEmpty && momentum == nil && pendingMove == .zero && pendingScroll == .zero {
            link.isPaused = true
        }
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        stopMomentum()
        displayLink?.isPaused = false

        if touchStarts.isEmpty {
            beginSession(at: touches.first?.timestamp ?? 0)
            haptic.prepare()
        }
        for touch in touches { touchStarts[touch] = touch.location(in: self) }
        maxTouches = max(maxTouches, touchStarts.count)

        switch touchStarts.count {
        case 1:
            lastPointerTimestamp = touches.first?.timestamp ?? 0
        case 2:
            if mode == .pointer {
                if isDragging {
                    // A second finger lands mid-drag: let go and ignore the rest of the gesture.
                    endDrag()
                    mode = .spent
                } else {
                    mode = .scroll
                    let c = centroid()
                    scrollCentroid = c
                    let spread = fingerSpread()
                    pinchLastSpread = spread
                    pinchSteps.reset()
                    classifier = TwoFingerClassifier(
                        startDistance: Double(spread), startX: Double(c.x), startY: Double(c.y),
                        slop: Double(Tuning.tapSlop), pinchBias: Double(Tuning.pinchBias)
                    )
                    selectionHaptic.prepare()
                }
            }
        default:
            endDragIfNeeded()
            if mode == .scroll { endScroll(at: touches.first?.timestamp ?? 0) }
            mode = .spent
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let start = touchStarts[touch] else { continue }
            let p = touch.location(in: self)
            maxTravel = max(maxTravel, hypot(p.x - start.x, p.y - start.y))
        }

        switch mode {
        case .pointer:
            guard let touch = touches.first, touchStarts[touch] != nil else { return }
            let p = touch.location(in: self)
            let q = touch.previousLocation(in: self)
            let delta = CGVector(dx: p.x - q.x, dy: p.y - q.y)
            let dt = touch.timestamp - lastPointerTimestamp
            lastPointerTimestamp = touch.timestamp

            if pointerEngaged {
                add(accelerated(delta, dt: dt), to: &pendingMove)
            } else {
                add(delta, to: &heldBackPointer)
                if maxTravel > Tuning.tapSlop {
                    pointerEngaged = true
                    if dragCandidate && maxTouches == 1 { beginDrag() }
                    add(accelerated(heldBackPointer, dt: dt), to: &pendingMove)
                    heldBackPointer = .zero
                }
            }
        case .scroll:
            guard touchStarts.count == 2, let previous = scrollCentroid else { return }
            let c = centroid()
            scrollCentroid = c
            if !scrollBegan, var classifier {
                let intent = classifier.update(distance: Double(fingerSpread()), centroidX: Double(c.x), centroidY: Double(c.y))
                self.classifier = classifier
                if intent == .pinch {
                    heldBackScroll = .zero
                    mode = .pinch
                    updatePinch()
                    return
                }
            }
            let delta = CGVector(
                dx: (c.x - previous.x) * Tuning.scrollGain,
                dy: (c.y - previous.y) * Tuning.scrollGain
            )
            if scrollBegan {
                add(delta, to: &pendingScroll)
                scrollSamples.append((touches.first?.timestamp ?? 0, delta))
                if scrollSamples.count > 30 { scrollSamples.removeFirst(scrollSamples.count - 30) }
            } else {
                add(delta, to: &heldBackScroll)
                // A scroll starts once the fingers have moved *and* the classifier says "scroll".
                if maxTravel > Tuning.tapSlop, classifier?.intent != .undecided {
                    scrollBegan = true
                    add(heldBackScroll, to: &pendingScroll)
                    heldBackScroll = .zero
                }
            }
        case .pinch:
            guard touchStarts.count == 2 else { return }
            updatePinch()
        case .idle, .spent:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        finish(touches, cancelled: true)
    }

    private func finish(_ touches: Set<UITouch>, cancelled: Bool) {
        let endTime = touches.map(\.timestamp).max() ?? sessionStart
        for touch in touches { touchStarts[touch] = nil }

        if mode == .scroll && touchStarts.count < 2 {
            endScroll(at: endTime)
            mode = .spent
        }
        if mode == .pinch && touchStarts.count < 2 {
            mode = .spent
        }
        if touchStarts.isEmpty {
            endDragIfNeeded()
            if !cancelled { evaluateTap(endTime: endTime) }
            mode = .idle
        }
    }

    // MARK: Session

    private func beginSession(at time: TimeInterval) {
        mode = .pointer
        sessionStart = time
        maxTouches = 0
        maxTravel = 0
        pointerEngaged = false
        heldBackPointer = .zero
        // Touching down again soon after a tap arms a drag (it fires once the finger moves).
        dragCandidate = lastTap.map { time - $0.time < Tuning.doubleTapInterval } ?? false
        isDragging = false
        scrollBegan = false
        heldBackScroll = .zero
        scrollCentroid = nil
        scrollSamples.removeAll()
        nextScrollPhase = .began
    }

    private func centroid() -> CGPoint {
        let points = touchStarts.keys.map { $0.location(in: self) }
        guard !points.isEmpty else { return .zero }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private func add(_ delta: CGVector, to total: inout CGVector) {
        total.dx += delta.dx
        total.dy += delta.dy
    }

    // MARK: Pinch

    /// Distance between the two fingers.
    private func fingerSpread() -> CGFloat {
        let points = touchStarts.keys.map { $0.location(in: self) }
        guard points.count == 2 else { return pinchLastSpread }
        return hypot(points[0].x - points[1].x, points[0].y - points[1].y)
    }

    /// Fingers apart zoom in (⌘=), together zoom out (⌘-), one step per `Tuning.pinchStepDistance`.
    private func updatePinch() {
        let spread = fingerSpread()
        let steps = pinchSteps.add(Double(spread - pinchLastSpread))
        pinchLastSpread = spread
        guard steps != 0 else { return }
        for _ in 0..<abs(steps) {
            send(.key(steps > 0 ? .equal : .minus, modifiers: .command))
        }
        selectionHaptic.selectionChanged()
    }

    // MARK: Pointer

    private func flushMove() {
        guard pendingMove != .zero else { return }
        send(.move(dx: Float(pendingMove.dx), dy: Float(pendingMove.dy)))
        pendingMove = .zero
    }

    private func beginDrag() {
        isDragging = true
        lastTap = nil // this touch is a drag, not the second half of a double-click
        send(.button(.left, .down))
        haptic.impactOccurred()
    }

    /// Releases the button after the last queued motion, so the drop lands where the finger was.
    private func endDrag() {
        flushMove()
        send(.button(.left, .up))
        isDragging = false
    }

    private func endDragIfNeeded() {
        if isDragging { endDrag() }
    }

    private func accelerated(_ delta: CGVector, dt: TimeInterval) -> CGVector {
        let seconds = max(dt, 1.0 / 240)
        let speed = hypot(delta.dx, delta.dy) / seconds
        let gain = min(Tuning.maxPointerGain, Tuning.pointerSensitivity * (1 + Tuning.pointerAcceleration * speed))
        return CGVector(dx: delta.dx * gain, dy: delta.dy * gain)
    }

    // MARK: Taps

    private func evaluateTap(endTime: TimeInterval) {
        let isTap = endTime - sessionStart < Tuning.tapMaxDuration
            && maxTravel <= Tuning.tapSlop
            && !scrollBegan
        guard isTap else { return }

        switch maxTouches {
        case 1:
            var count = 1
            if let last = lastTap, endTime - last.time < Tuning.doubleTapInterval {
                count = min(last.count + 1, 3)
            }
            lastTap = (endTime, count)
            send(.click(.left, count: UInt8(count)))
            haptic.impactOccurred()
        case 2:
            lastTap = nil
            send(.click(.right, count: 1))
            haptic.impactOccurred()
        default:
            break
        }
    }

    // MARK: Scroll + momentum

    private func flushScroll() {
        guard pendingScroll != .zero else { return }
        send(.scroll(dx: Float(pendingScroll.dx), dy: Float(pendingScroll.dy), phase: nextScrollPhase))
        nextScrollPhase = .changed
        pendingScroll = .zero
    }

    private func endScroll(at time: TimeInterval) {
        guard scrollBegan else { return }
        flushScroll()
        send(.scroll(dx: 0, dy: 0, phase: .ended))
        scrollBegan = false

        // Release velocity over the last 100 ms of finger motion.
        let window: TimeInterval = 0.1
        var sum = CGVector.zero
        for sample in scrollSamples where time - sample.time <= window { add(sample.delta, to: &sum) }
        scrollSamples.removeAll()
        let velocity = CGVector(dx: sum.dx / window, dy: sum.dy / window)
        if hypot(velocity.dx, velocity.dy) >= Tuning.momentumStartSpeed {
            momentum = Momentum(velocity: velocity)
            displayLink?.isPaused = false
        }
    }

    private func stepMomentum(frameDuration: TimeInterval) {
        guard var m = momentum else { return }
        let dt = max(frameDuration, 1.0 / 240)
        if hypot(m.velocity.dx, m.velocity.dy) < Tuning.momentumStopSpeed {
            send(.scroll(dx: 0, dy: 0, phase: .momentumEnded))
            momentum = nil
            return
        }
        send(.scroll(
            dx: Float(m.velocity.dx * dt),
            dy: Float(m.velocity.dy * dt),
            phase: m.hasBegun ? .momentumChanged : .momentumBegan
        ))
        m.hasBegun = true
        let decay = exp(-Tuning.momentumDecay * dt)
        m.velocity = CGVector(dx: m.velocity.dx * decay, dy: m.velocity.dy * decay)
        momentum = m
    }

    private func stopMomentum() {
        guard let m = momentum else { return }
        if m.hasBegun { send(.scroll(dx: 0, dy: 0, phase: .momentumEnded)) }
        momentum = nil
    }
}
