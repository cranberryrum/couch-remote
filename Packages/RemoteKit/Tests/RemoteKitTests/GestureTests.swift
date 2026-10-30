import Testing
@testable import RemoteKit

@Suite struct StepAccumulatorTests {
    @Test func belowOneStepProducesNothingButIsRemembered() {
        var steps = StepAccumulator(stepSize: 40)
        #expect(steps.add(15) == 0)
        #expect(steps.add(15) == 0)
        #expect(steps.add(15) == 1) // 45 total: one step, 5 left over
        #expect(steps.add(34) == 0) // 39
        #expect(steps.add(2) == 1)  // 41
    }

    @Test func negativeDirectionCountsDownAndKeepsItsRemainder() {
        var steps = StepAccumulator(stepSize: 10)
        #expect(steps.add(-25) == -2)
        #expect(steps.add(-5) == -1) // -5 left over from before, so -10 in total
        #expect(steps.add(0) == 0)
    }

    @Test func aLargeJumpYieldsSeveralSteps() {
        var steps = StepAccumulator(stepSize: 40)
        #expect(steps.add(130) == 3)
        #expect(steps.add(-130) == -3)
    }

    @Test func reversingDirectionDoesNotOvershoot() {
        var steps = StepAccumulator(stepSize: 40)
        #expect(steps.add(30) == 0)
        #expect(steps.add(-30) == 0) // back where it started
        #expect(steps.add(-39) == 0)
        #expect(steps.add(-2) == -1)
    }

    @Test func resetDiscardsTheRemainder() {
        var steps = StepAccumulator(stepSize: 40)
        _ = steps.add(30)
        steps.reset()
        #expect(steps.add(30) == 0)
    }

    @Test func manySmallEventsAddUpExactly() {
        var steps = StepAccumulator(stepSize: 40)
        var total = 0
        for _ in 0..<400 { total += steps.add(1) }
        #expect(total == 10)
    }
}

@Suite struct TwoFingerClassifierTests {
    private func classifier() -> TwoFingerClassifier {
        TwoFingerClassifier(startDistance: 100, startX: 200, startY: 300, slop: 6, pinchBias: 1.6)
    }

    @Test func staysUndecidedInsideTheSlop() {
        var c = classifier()
        #expect(c.update(distance: 103, centroidX: 203, centroidY: 300) == .undecided)
    }

    @Test func fingersTravellingTogetherAreAScroll() {
        var c = classifier()
        #expect(c.update(distance: 100, centroidX: 200, centroidY: 316) == .scroll)
    }

    @Test func scrollWithSmallJitterInSpreadIsStillAScroll() {
        var c = classifier()
        #expect(c.update(distance: 103, centroidX: 204, centroidY: 314) == .scroll)
    }

    @Test func fingersMovingApartAreAPinch() {
        var c = classifier()
        // both fingers move 8 pt outwards: spread +16, midpoint stays put
        #expect(c.update(distance: 116, centroidX: 200, centroidY: 300) == .pinch)
    }

    @Test func fingersMovingTogetherAreAPinchIn() {
        var c = classifier()
        #expect(c.update(distance: 84, centroidX: 200, centroidY: 300) == .pinch)
    }

    @Test func onlyOneFingerMovingIsAPinch() {
        var c = classifier()
        // one finger moves 12 pt away from the other: spread +12, midpoint +6
        #expect(c.update(distance: 112, centroidX: 200, centroidY: 306.5) == .pinch)
    }

    @Test func theDecisionIsSticky() {
        var scroll = classifier()
        _ = scroll.update(distance: 100, centroidX: 200, centroidY: 320)
        #expect(scroll.update(distance: 160, centroidX: 200, centroidY: 320) == .scroll)

        var pinch = classifier()
        _ = pinch.update(distance: 120, centroidX: 200, centroidY: 300)
        #expect(pinch.update(distance: 120, centroidX: 200, centroidY: 400) == .pinch)
    }
}
