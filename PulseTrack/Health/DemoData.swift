import Foundation

/// Realistic sample data so the app can be explored in the Simulator or before granting Health access.
enum DemoData {
    struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = (seed &* 0x9E37_79B9_7F4A_7C15) | 1 }
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }

    static func night(for day: Date) -> SleepNight {
        let wake = Calendar.current.startOfDay(for: day)
        var rng = SeededRNG(seed: UInt64(max(0, Int(wake.timeIntervalSince1970 / 86400))))
        var t = wake.addingTimeInterval(-3600 + Double.random(in: 0...2700, using: &rng)) // 23:00–23:45
        var segments: [StageSegment] = []

        func add(_ stage: SleepStage, _ minutes: Double) {
            let end = t.addingTimeInterval(max(minutes, 1) * 60)
            segments.append(StageSegment(stage: stage, start: t, end: end))
            t = end
        }

        add(.awake, Double.random(in: 4...12, using: &rng))
        let cycles = Int.random(in: 4...6, using: &rng)
        for c in 0..<cycles {
            let f = Double(c) / Double(max(cycles - 1, 1))
            add(.core, Double.random(in: 15...25, using: &rng))
            add(.deep, 35 - 28 * f + Double.random(in: -5...5, using: &rng))
            add(.core, Double.random(in: 15...30, using: &rng))
            add(.rem, 10 + 22 * f + Double.random(in: -4...6, using: &rng))
            if Double.random(in: 0...1, using: &rng) < 0.45 {
                add(.awake, Double.random(in: 2...9, using: &rng))
            }
        }
        add(.awake, Double.random(in: 2...8, using: &rng))

        var night = SleepNight(wakeDay: wake, segments: segments)
        night.vitals = SleepVitals(
            heartRate: Double.random(in: 50...57, using: &rng),
            hrv: Double.random(in: 48...66, using: &rng),
            respiratoryRate: Double.random(in: 13.8...15.6, using: &rng),
            oxygen: Double.random(in: 95...98, using: &rng))
        return night
    }

    private struct Spec {
        let name: String, symbol: String, hoursAgo: Double, minutes: Double
        let distance: Double?, avgHR: Double, maxHR: Double, kcal: Double
    }

    static func workouts(restingHR: Double, maxHR: Double) -> [WorkoutSummary] {
        let specs = [
            Spec(name: "Run", symbol: "figure.run", hoursAgo: 14, minutes: 48, distance: 8_400, avgHR: 158, maxHR: 181, kcal: 610),
            Spec(name: "Strength Training", symbol: "figure.strengthtraining.traditional", hoursAgo: 38, minutes: 55, distance: nil, avgHR: 122, maxHR: 151, kcal: 340),
            Spec(name: "Cycling", symbol: "figure.outdoor.cycle", hoursAgo: 62, minutes: 75, distance: 31_200, avgHR: 141, maxHR: 172, kcal: 720),
            Spec(name: "HIIT", symbol: "figure.highintensity.intervaltraining", hoursAgo: 90, minutes: 28, distance: nil, avgHR: 162, maxHR: 186, kcal: 330),
            Spec(name: "Swim", symbol: "figure.pool.swim", hoursAgo: 114, minutes: 40, distance: 1_800, avgHR: 134, maxHR: 160, kcal: 410),
            Spec(name: "Walk", symbol: "figure.walk", hoursAgo: 140, minutes: 52, distance: 4_600, avgHR: 102, maxHR: 121, kcal: 210)
        ]
        let now = Date()
        return specs.map { s in
            let end = now.addingTimeInterval(-s.hoursAgo * 3600)
            let start = end.addingTimeInterval(-s.minutes * 60)
            let load = RecoveryCalculator.trainingLoad(duration: s.minutes * 60, avgHR: s.avgHR,
                                                       restingHR: restingHR, maxHR: maxHR, energy: s.kcal)
            return WorkoutSummary(id: UUID(), name: s.name, symbol: s.symbol, start: start, end: end,
                                  energy: s.kcal, distance: s.distance, avgHR: s.avgHR, maxHR: s.maxHR, load: load)
        }
    }

    /// Synthetic heart-rate trace (every 30s) with warm-up, intervals and cool-down.
    static func heartRateSeries(for w: WorkoutSummary) -> [(date: Date, bpm: Double)] {
        let avg = w.avgHR ?? 130
        let peak = w.maxHR ?? avg + 20
        let steps = Int(w.duration / 30)
        return (0..<max(steps, 1)).map { i in
            let p = Double(i) / Double(max(steps - 1, 1))
            let ramp = min(p / 0.12, 1) * min((1 - p) / 0.08, 1)
            let wave = sin(p * .pi * 10) * (peak - avg) * 0.6
            let bpm = 95 + (avg + wave - 95) * ramp
            return (date: w.start.addingTimeInterval(Double(i) * 30), bpm: min(bpm, peak))
        }
    }
}
