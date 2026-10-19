import Foundation

private struct FaceSession {
    var counter = FaceMovementCounter()
    var time = 0.0
    var count = 0
    var countTimes: [Double] = []
    var interval = 0.05
    mutating func sample(_ y: Double?, height: Double? = 0.2, frames: Int = 12) {
        for _ in 0..<frames {
            time += interval
            if counter.update(y: y, height: height, time: time) { count += 1; countTimes.append(time) }
        }
    }
    mutating func prepare(height: Double = 0.2, centerY: Double = 0.6) {
        sample(centerY, height: height, frames: Int(WorkoutPreparation.duration / interval) + 3)
    }
    mutating func ramp(from start: Double, to end: Double, frames: Int = 10, height: Double = 0.2) {
        for frame in 1...frames { sample(start + (end - start) * Double(frame) / Double(frames), height: height, frames: 1) }
    }
}

@main enum FaceCounterChecks {
    static func main() {
        var checked = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message); checked += 1 }
        var s = FaceSession(); s.prepare()
        check(s.counter.phase == .resting && s.count == 0, "Preparation does not create a repetition")
        check(s.counter.imageHeight == 720 && s.counter.calibrationProgress == 1, "Display height and completed preparation are exposed")
        s.ramp(from: 0.6, to: 0.41); s.sample(0.41, frames: 10)
        check(s.counter.phase == .moved && !s.counter.challengeReached, "Minimum line can be cleared without the optional challenge")
        s.ramp(from: 0.41, to: 0.6); s.sample(0.6, frames: 10)
        check(s.count == 1, "Crossing the minimum and returning counts once")
        s.sample(0.6, frames: 60)
        check(s.count == 1, "Standing still cannot repeatedly count")
        for index in 0..<120 { s.sample(index.isMultiple(of: 2) ? 0.61 : 0.59, frames: 1) }
        s.sample(0.585, frames: 30); s.sample(0.6, frames: 30)
        check(s.count == 1, "Small jitter and held shifts cannot count")
        s.sample(0.3, frames: 1); s.sample(0.6, frames: 30)
        check(s.count == 1, "A one-frame jump cannot clear the minimum")
        s.sample(0.53, frames: 24); s.sample(0.6, frames: 24)
        check(s.count == 1 && s.counter.phase == .resting, "A shallow down-and-up stays uncounted")
        s.sample(0.75, frames: 24); s.sample(0.6, frames: 24)
        check(s.count == 1, "Movement above the standing position cannot count")
        s.sample(0.31, frames: 7); s.sample(0.6, frames: 16)
        check(s.count == 1, "A quick deep nod cannot manufacture a rep")
        s.sample(0.40, frames: 20); s.sample(nil, height: nil, frames: 2); s.sample(0.6, frames: 16)
        check(s.count == 2, "Short tracking gaps can recover a valid deep movement")
        s.sample(0.40, frames: 20); s.sample(nil, height: nil, frames: 20); s.sample(0.6, frames: 16)
        check(s.count == 2 && s.counter.phase == .calibrating, "Long loss discards a pending repetition")
        s.prepare(); s.sample(0.36, frames: 24)
        check(s.counter.challengeReached && s.counter.phase == .moved, "Optional challenge activates only beyond its deeper line")
        s.sample(0.6, frames: 16)
        check(s.count == 3 && !s.counter.challengeReached, "A challenge movement is still one rep and its highlight clears on return")
        s.sample(0.40, frames: 70)
        check(s.count == 3, "Holding a deep position cannot repeatedly count")
        s.sample(0.53, frames: 20)
        check(s.count == 3 && s.counter.phase == .moved, "Returning only halfway cannot finish a rep")
        s.sample(0.6, frames: 16)
        check(s.count == 4, "Returning to the standing zone finishes exactly one rep")
        s.counter.reset(); s.prepare(); s.sample(.nan, frames: 1); s.sample(0.6, frames: 20)
        check(s.count == 4, "Reset and invalid samples cannot count")
        var distant = FaceSession(); distant.prepare(height: 0.1)
        distant.sample(0.54, height: 0.1, frames: 24); distant.sample(0.6, height: 0.1, frames: 16)
        check(distant.count == 0, "A small face does not reduce the fixed on-screen minimum")
        distant.sample(0.41, height: 0.1, frames: 24); distant.sample(0.6, height: 0.1, frames: 16)
        check(distant.count == 1, "A small face clears the same fixed 120pt minimum")
        var veryDistant = FaceSession(); veryDistant.prepare(height: 0.021)
        veryDistant.sample(0.594, height: 0.021, frames: 24); veryDistant.sample(0.6, height: 0.021, frames: 24)
        check(veryDistant.count == 0, "A tiny face cannot turn small jitter into the fixed 120pt movement")
        s.counter.imageHeight = 360; s.counter.reset(); s.prepare()
        s.sample(0.41, frames: 24); s.sample(0.6, frames: 24)
        check(s.count == 4 && s.counter.imageHeight == 360, "Reset preserves display height and rejects movement shorter than 120pt")
        var repeated = FaceSession(); repeated.prepare()
        for _ in 0..<3 { repeated.sample(0.35, frames: 14); repeated.sample(0.6, frames: 12) }
        check(repeated.count == 3 && zip(repeated.countTimes, repeated.countTimes.dropFirst()).allSatisfy { $1 - $0 >= 1 }, "Complete cycles count at most once and respect the cooldown")
        for interval in [1.0 / 30.0, 1.0 / 15.0] {
            var rate = FaceSession(interval: interval); rate.prepare()
            let second = Int((1 / interval).rounded())
            rate.ramp(from: 0.6, to: 0.40, frames: second / 2); rate.sample(0.40, frames: second / 2)
            rate.ramp(from: 0.40, to: 0.6, frames: second / 2); rate.sample(0.6, frames: second / 2)
            check(rate.count == 1, "Valid downward motion counts at different frame rates")
        }
        let lines = FaceDepthLines(baseline: 0.6, imageHeight: 720)
        check(abs(lines.minimumY - (0.6 - 120.0 / 720)) < 0.00001 && abs(lines.challengeY - (0.6 - 160.0 / 720)) < 0.00001 && abs(lines.returnY - (0.6 - 40.0 / 720)) < 0.00001, "Displayed return, minimum and challenge use the exact counter thresholds")
        for imageHeight in [360.0, 560.0, 720.0, 1080.0] {
            let fixed = FaceDepthLines(baseline: 0.73, imageHeight: imageHeight)
            check(abs((fixed.baseline - fixed.returnY) * imageHeight - 40) < 0.00001 && abs((fixed.returnY - fixed.minimumY) * imageHeight - 80) < 0.00001 && abs((fixed.minimumY - fixed.challengeY) * imageHeight - 40) < 0.00001, "Every rendered image height keeps the 40/120/160pt offsets")
        }
        var between = FaceSession(); between.prepare()
        between.sample(0.385, frames: 30)
        check(between.counter.phase == .moved && !between.counter.challengeReached, "Clearing the old 150pt challenge but not 160pt no longer highlights yellow")
        between.sample(0.6, frames: 24)
        check(between.count == 1, "A minimum-only movement still counts exactly once")
        between.sample(0.37, frames: 30)
        check(between.counter.challengeReached, "The new deeper challenge highlights at the same position as its displayed line")
        between.sample(0.6, frames: 24)
        check(between.count == 2 && !between.counter.challengeReached, "The deeper challenge remains one rep and clears on return")
        var large = FaceSession(); large.prepare(height: 0.3)
        var small = FaceSession(); small.prepare(height: 0.08)
        check(large.counter.depthLines?.minimumY == small.counter.depthLines?.minimumY && large.counter.depthLines?.returnY == small.counter.depthLines?.returnY && large.counter.depthLines?.challengeY == small.counter.depthLines?.challengeY, "Face size never changes the established line positions")
        large.sample(0.50, height: 0.3, frames: 24); large.sample(0.6, height: 0.3, frames: 24)
        small.sample(0.50, height: 0.08, frames: 24); small.sample(0.6, height: 0.08, frames: 24)
        check(large.count == 0 && small.count == 0, "Both large and small faces reject the same sub-minimum movement")
        large.sample(0.41, height: 0.3, frames: 24); large.sample(0.6, height: 0.3, frames: 24)
        small.sample(0.41, height: 0.08, frames: 24); small.sample(0.6, height: 0.08, frames: 24)
        check(large.count == 1 && small.count == 1, "Both face sizes complete the same minimum-and-return cycle")
        var shifted = FaceSession(); shifted.prepare(centerY: 0.8)
        check(abs((shifted.counter.depthLines?.minimumY ?? 0) - (0.8 - 120.0 / 720)) < 0.00001, "The detected standing position anchors the same constant intervals")
        shifted.sample(0.60, frames: 24); shifted.sample(0.8, frames: 24)
        check(shifted.count == 1, "A different visible standing position uses the same counting motion")
        var compact = FaceSession(); compact.counter.imageHeight = 360; compact.prepare()
        compact.sample(0.41, frames: 24); compact.sample(0.6, frames: 24)
        check(compact.count == 0, "A smaller rendered image still requires 120pt rather than the old normalized movement")
        compact.sample(0.22, frames: 24); compact.sample(0.6, frames: 24)
        check(compact.count == 1, "Crossing the rendered 120pt minimum and 40pt return counts once")
        print("PASS: \(checked) face depth counter checks")
    }
}
