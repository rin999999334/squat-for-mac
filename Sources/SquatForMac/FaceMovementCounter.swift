import Foundation

// Counts a face crossing a downward minimum line and returning, not squat form.
struct FaceMovementCounter {
    enum Phase { case calibrating, resting, moved }
    private(set) var phase: Phase = .calibrating
    var imageHeight = 720.0 // Rendered camera height in points, including aspect-fill crop.
    private(set) var baseline: Double?
    private(set) var calibrationProgress = 0.0
    private var referenceHeight = 0.0
    private var samples: [(Double, Double)] = []
    private var preparationElapsed = 0.0
    private var preparationAnchor: (y: Double, x: Double?, height: Double)?
    private var lastPreparationSample: Double?
    private var filteredY: Double?
    private var lastSeen: Double?
    private var candidateSince: Double?
    private var movementStarted: Double?
    private var returnStarted: Double?
    private var lastCount = -Double.infinity
    private(set) var displacement = 0.0
    private(set) var challengeReached = false
    var depthLines: FaceDepthLines? {
        guard let baseline, referenceHeight > 0 else { return nil }
        return FaceDepthLines(baseline: baseline, imageHeight: imageHeight)
    }

    // Time-based confirmation rejects frame jitter and quick nods while allowing
    // a relaxed full movement. The pixel-space floor matters for distant faces.
    private let outwardDwell = 0.24
    private let returnDwell = 0.20
    private let minimumCycle = 0.60
    private let countCooldown = 1.0
    private let smoothingTime = 0.12
    static let preparationDuration = WorkoutPreparation.duration

    mutating func reset() {
        let height = imageHeight
        self = FaceMovementCounter()
        imageHeight = height
    }
    mutating func update(y: Double?, height: Double?, time: Double, x: Double? = nil, aspect: Double = 4.0 / 3.0) -> Bool {
        guard time.isFinite else { return false }
        guard let y, let height, y.isFinite, height.isFinite, height > 0.02,
              x.map({ $0.isFinite }) ?? true else {
            candidateSince = nil
            // A brief missing frame pauses preparation; it never advances the countdown.
            lastPreparationSample = nil
            if let lastSeen, time - lastSeen > 0.6 { reset() }
            return false
        }
        if let lastSeen, time < lastSeen || time - lastSeen > 0.6 { reset() }
        let elapsed = lastSeen.map { max(0, time - $0) }
        lastSeen = time
        let alpha = elapsed.map { 1 - exp(-$0 / smoothingTime) } ?? 1
        let smoothed = filteredY.map { $0 + alpha * (y - $0) } ?? y
        filteredY = smoothed
        if phase == .calibrating {
            let tolerance = max(0.008, height * 0.20)
            if let anchor = preparationAnchor {
                let horizontalShift = x.flatMap { current in anchor.x.map { abs(current - $0) * max(0.1, aspect) } } ?? 0
                if abs(y - anchor.y) > tolerance || horizontalShift > tolerance || abs(height - anchor.height) > anchor.height * 0.25 {
                    preparationAnchor = nil; preparationElapsed = 0; lastPreparationSample = nil; samples = []
                }
            }
            if preparationAnchor == nil { preparationAnchor = (y, x, height) }
            if let previous = lastPreparationSample { preparationElapsed += max(0, time - previous) }
            lastPreparationSample = time
            samples.append((y, height))
            calibrationProgress = min(1, preparationElapsed / Self.preparationDuration)
            if preparationElapsed + 0.000001 >= Self.preparationDuration, samples.count >= 4 {
                baseline = samples.map { $0.0 }.sorted()[samples.count / 2]
                referenceHeight = samples.map { $0.1 }.sorted()[samples.count / 2]
                filteredY = baseline; calibrationProgress = 1
                phase = .resting; samples = []; preparationAnchor = nil
            }
            return false
        }
        guard let baseline, let lines = depthLines else { return false }
        displacement = max(0, (baseline - smoothed) / referenceHeight)
        challengeReached = smoothed <= lines.challengeY
        if phase == .moved {
            if y >= lines.returnY {
                if returnStarted == nil { returnStarted = time }
            } else { returnStarted = nil }
        }
        let reached = phase == .resting ? smoothed <= lines.minimumY : smoothed >= lines.returnY
        if !reached { candidateSince = nil; return false }
        if candidateSince == nil { candidateSince = time; return false }
        let dwell = phase == .resting ? outwardDwell : returnDwell
        guard time - (candidateSince ?? time) >= dwell else { return false }
        let confirmedSince = candidateSince ?? time
        candidateSince = nil
        if phase == .resting {
            phase = .moved
            movementStarted = confirmedSince
            returnStarted = nil
            return false
        }
        phase = .resting
        // Smoothing and return confirmation must not turn a short nod into a long movement.
        let cycleDuration = (returnStarted ?? time) - (movementStarted ?? time)
        movementStarted = nil; returnStarted = nil
        if cycleDuration + 0.000001 >= minimumCycle, time - lastCount >= countCooldown {
            lastCount = time
            return true
        }
        return false
    }
}
