import Foundation
@main enum CounterChecks {
    static func main() {
        var counter = SquatCounter()
        var t = 0.0
        var reps = 0
        func sample(_ angle: Double?, _ side: String? = "左", frames: Int = 5) {
            for _ in 0..<frames {
                t += 0.1
                if counter.update(angle: angle, side: side, time: t) { reps += 1 }
            }
        }
        sample(95); sample(175, frames: 60)
        precondition(reps == 0, "Starting crouched must not count")
        sample(95); sample(175, frames: 60)
        precondition(reps == 1, "A complete cycle counts once")
        sample(175, frames: 20)
        precondition(reps == 1, "Holding standing must not count again")
        sample(95, frames: 1); sample(175)
        precondition(reps == 1, "One noisy crouching frame must not count")
        sample(95); sample(nil, nil, frames: 1); sample(175, frames: 60)
        precondition(reps == 1, "Tracking loss invalidates a partial rep")
        sample(95); sample(175, "右", frames: 60)
        precondition(reps == 1, "Switching tracked legs invalidates a partial rep")
        sample(95, "右"); t += 1; sample(175, "右", frames: 60)
        precondition(reps == 1, "Long sample gaps invalidate a partial rep")
        sample(130, "右", frames: 10); sample(175, "右", frames: 60)
        precondition(reps == 1, "Shallow movement must not count")
        sample(95, "右"); sample(175, "右", frames: 60)
        precondition(reps == 2, "Valid tracking must recover")
        sample(.nan, "右"); sample(175, "右", frames: 60)
        precondition(reps == 2, "Nonfinite values must be ignored")
        counter.reset(); sample(95, "右"); sample(175, "右", frames: 60)
        precondition(reps == 2, "Reset clears the partial cycle")
        print("PASS: 10 squat counter checks")
    }
}
