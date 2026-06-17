import Foundation

struct IslandHorizontalModuleSwipeEvent {
    var horizontalDelta: Double
    var verticalDelta: Double
    var phaseBegan: Bool = false
    var phaseEnded: Bool = false
    var isMomentum: Bool = false
}

enum IslandHorizontalModuleSwipeDecision: Equatable {
    case passThrough
    case consume
    case switchModule(offset: Int)
}

struct IslandHorizontalModuleSwipeGate {
    var postSwitchSuppressionDuration: TimeInterval = 0.62
    var postSwitchIdleResetDelay: TimeInterval = 0.7
    var idleResetDelay: TimeInterval = 0.42
    var minimumHorizontalDelta: Double = 1.5
    var horizontalIntentThreshold: Double = 12
    var switchThreshold: Double = 58
    var verticalIntentMultiplier: Double = 1.2

    private var accumulatedHorizontal: Double = 0
    private var accumulatedVertical: Double = 0
    private var lastSwitchAt: TimeInterval = -.greatestFiniteMagnitude
    private var lastScrollEventAt: TimeInterval = -.greatestFiniteMagnitude
    private var suppressWheelEventsUntil: TimeInterval = -.greatestFiniteMagnitude
    private var hasSwitchedDuringGesture = false

    mutating func handle(
        _ event: IslandHorizontalModuleSwipeEvent,
        at now: TimeInterval
    ) -> IslandHorizontalModuleSwipeDecision {
        guard now >= suppressWheelEventsUntil else {
            lastScrollEventAt = now
            return isVerticalIntent(event) ? .passThrough : .consume
        }

        if event.phaseBegan,
           hasSwitchedDuringGesture,
           now - lastSwitchAt <= postSwitchIdleResetDelay {
            lastScrollEventAt = now
            return isVerticalIntent(event) ? .passThrough : .consume
        }

        if event.phaseBegan {
            resetGestureState()
        }

        if event.isMomentum {
            return hasSwitchedDuringGesture && !isVerticalIntent(event) ? .consume : .passThrough
        }

        let resolvedIdleResetDelay = hasSwitchedDuringGesture ? postSwitchIdleResetDelay : idleResetDelay
        if now - lastScrollEventAt > resolvedIdleResetDelay {
            resetGestureState()
        }
        lastScrollEventAt = now

        if event.phaseEnded {
            resetAccumulation()
            return hasSwitchedDuringGesture ? .consume : .passThrough
        }

        guard abs(event.horizontalDelta) >= minimumHorizontalDelta else {
            return .passThrough
        }

        accumulatedHorizontal += event.horizontalDelta
        accumulatedVertical += event.verticalDelta

        let hasHorizontalIntent =
            abs(accumulatedHorizontal) > horizontalIntentThreshold
            && abs(accumulatedHorizontal) > abs(accumulatedVertical) * verticalIntentMultiplier

        guard hasHorizontalIntent else {
            return .passThrough
        }

        if hasSwitchedDuringGesture {
            return .consume
        }

        guard abs(accumulatedHorizontal) > switchThreshold,
              now - lastSwitchAt > postSwitchSuppressionDuration else {
            return .consume
        }

        return .switchModule(offset: accumulatedHorizontal > 0 ? 1 : -1)
    }

    mutating func recordSwitch(at now: TimeInterval) {
        lastSwitchAt = now
        suppressWheelEventsUntil = now + postSwitchSuppressionDuration
        hasSwitchedDuringGesture = true
        resetAccumulation()
    }

    mutating func suppressWheelMomentum(after now: TimeInterval) {
        suppressWheelEventsUntil = now + postSwitchSuppressionDuration
        resetAccumulation()
    }

    private func isVerticalIntent(_ event: IslandHorizontalModuleSwipeEvent) -> Bool {
        let horizontal = abs(event.horizontalDelta)
        let vertical = abs(event.verticalDelta)
        return vertical > minimumHorizontalDelta && vertical > horizontal * verticalIntentMultiplier
    }

    private mutating func resetAccumulation() {
        accumulatedHorizontal = 0
        accumulatedVertical = 0
    }

    private mutating func resetGestureState() {
        resetAccumulation()
        hasSwitchedDuringGesture = false
    }
}
