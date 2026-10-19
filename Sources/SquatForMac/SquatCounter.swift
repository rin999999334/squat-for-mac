import Foundation

// A full repetition requires stable standing → crouching → standing.
// Loss of tracking invalidates the partial repetition.
struct SquatCounter {
    enum Phase { case calibrating, standing, down }
    private(set) var phase: Phase = .calibrating
    private(set) var calibrationProgress = 0.0
    private var preparationAngle: Double?
    private var candidate: Bool?
    private var candidateSince = 0.0
    private var lastCount = -Double.infinity
    private var lastSample: Double?
    private var side: String?

    mutating func reset() { self = SquatCounter() }
    mutating func update(angle: Double?, side newSide: String?, time: Double) -> Bool {
        guard time.isFinite else { return false }
        guard let angle, angle.isFinite, let newSide else { reset(); return false }
        if side != newSide || lastSample.map({ time - $0 > 0.6 || time < $0 }) == true {
            reset()
        }
        side = newSide
        lastSample = time
        let isStanding = angle >= 160
        let isDown = angle <= 110
        let condition: Bool?
        switch phase {
        case .calibrating, .down: condition = isStanding ? true : nil
        case .standing: condition = isDown ? false : nil
        }
        guard let condition else {
            candidate = nil
            if phase == .calibrating { calibrationProgress = 0; preparationAngle = nil }
            return false
        }
        if phase == .calibrating, let anchor = preparationAngle, abs(angle - anchor) > 10 { candidate = nil }
        if phase == .calibrating && candidate == nil { preparationAngle = angle; calibrationProgress = 0 }
        if candidate != condition { candidate = condition; candidateSince = time; return false }
        if phase == .calibrating { calibrationProgress = min(1, max(0, (time - candidateSince) / WorkoutPreparation.duration)) }
        guard time - candidateSince + 0.000001 >= (phase == .calibrating ? WorkoutPreparation.duration : 0.20) else { return false }
        candidate = nil
        switch phase {
        case .calibrating: phase = .standing; calibrationProgress = 1
        case .standing: phase = .down
        case .down:
            phase = .standing
            if time - lastCount >= 0.8 { lastCount = time; return true }
        }
        return false
    }
}
