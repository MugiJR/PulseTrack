import Foundation
import HealthKit
import SwiftUI

// MARK: - Sleep parsing

enum SleepAnalyzer {
    /// Window for the night that ends on `day`: 6 PM the previous evening → 2 PM on `day`.
    static func window(for day: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let d = calendar.startOfDay(for: day)
        return (d.addingTimeInterval(-6 * 3600), d.addingTimeInterval(14 * 3600))
    }

    /// Converts HealthKit samples into non-overlapping stage segments.
    /// Prefers Apple Watch samples (which have stages) over iPhone "in bed" data.
    static func segments(from records: [SleepRecord]) -> [StageSegment] {
        let watch = records.filter(\.fromWatch)
        let source = watch.isEmpty ? records : watch

        let raw: [StageSegment] = source.compactMap { record in
            guard let stage = record.stage else { return nil }
            return StageSegment(stage: stage, start: record.start, end: record.end)
        }
        .sorted { $0.start < $1.start }

        // Clip overlaps so nothing is double counted.
        var result: [StageSegment] = []
        var cursor = Date.distantPast
        for seg in raw {
            let start = max(seg.start, cursor)
            guard seg.end > start else { continue }
            result.append(StageSegment(stage: seg.stage, start: start, end: seg.end))
            cursor = max(cursor, seg.end)
        }
        return mainSleep(result)
    }

    /// Splits segments into blocks separated by 2h+ gaps and returns the longest (ignores naps).
    static func mainSleep(_ segments: [StageSegment]) -> [StageSegment] {
        guard !segments.isEmpty else { return [] }
        var blocks: [[StageSegment]] = [[segments[0]]]
        for seg in segments.dropFirst() {
            if let last = blocks[blocks.count - 1].last, seg.start.timeIntervalSince(last.end) > 2 * 3600 {
                blocks.append([seg])
            } else {
                blocks[blocks.count - 1].append(seg)
            }
        }
        func asleep(_ b: [StageSegment]) -> TimeInterval {
            b.filter { $0.stage != .awake }.reduce(0) { $0 + $1.duration }
        }
        return blocks.max { asleep($0) < asleep($1) } ?? []
    }

    static func stage(for value: HKCategoryValueSleepAnalysis) -> SleepStage? {
        switch value {
        case .awake: return .awake
        case .asleepREM: return .rem
        case .asleepDeep: return .deep
        case .asleepCore, .asleepUnspecified: return .core
        default: return nil // .inBed
        }
    }
}

// MARK: - Sleep score (0–100)

enum SleepScorer {
    /// Linear 0→1 between `zero` and `full` (works in either direction).
    static func ramp(_ x: Double, zero: Double, full: Double) -> Double {
        let t = (x - zero) / (full - zero)
        return min(max(t, 0), 1)
    }

    static func score(_ night: SleepNight, goalHours: Double = 8) -> SleepScore {
        let hours = night.asleep / 3600
        var durationPts = ramp(hours, zero: 4, full: goalHours - 0.5) * 40
        if hours > goalHours + 1.5 { durationPts -= min((hours - goalHours - 1.5) * 4, 8) }

        let deep = night.share(of: .deep)
        let rem = night.share(of: .rem)
        let eff = night.efficiency
        let awakeMin = night.awake / 60

        let components = [
            ScoreComponent(name: "Duration", points: durationPts, maxPoints: 40,
                           detail: "\(night.asleep.hm) asleep · goal \(Int(goalHours))h"),
            ScoreComponent(name: "Deep sleep", points: ramp(deep, zero: 0.05, full: 0.15) * 15, maxPoints: 15,
                           detail: "\(deep.percent) of sleep · ideal 13–23%"),
            ScoreComponent(name: "REM sleep", points: ramp(rem, zero: 0.08, full: 0.20) * 15, maxPoints: 15,
                           detail: "\(rem.percent) of sleep · ideal 20–25%"),
            ScoreComponent(name: "Efficiency", points: ramp(eff, zero: 0.70, full: 0.92) * 15, maxPoints: 15,
                           detail: "\(eff.percent) of time in bed asleep"),
            ScoreComponent(name: "Restfulness", points: ramp(awakeMin, zero: 75, full: 15) * 15, maxPoints: 15,
                           detail: "\(night.awake.hm) awake · \(night.awakenings) wake-ups")
        ]
        let total = Int(components.reduce(0) { $0 + $1.points }.rounded())
        return SleepScore(total: min(max(total, 0), 100), components: components)
    }
}

// MARK: - Heart-rate zones

enum ZoneCalculator {
    private static let bounds: [Double] = [0, 0.6, 0.7, 0.8, 0.9]
    private static let colors: [Color] = [
        Color(red: 0.55, green: 0.65, blue: 0.80),
        Color(red: 0.30, green: 0.65, blue: 1.00),
        Color(red: 0.30, green: 0.85, blue: 0.50),
        Color(red: 1.00, green: 0.65, blue: 0.20),
        Color(red: 1.00, green: 0.30, blue: 0.30)
    ]

    static func zones(samples: [(date: Date, bpm: Double)], end: Date, maxHR: Double) -> [HRZone] {
        var minutes = Array(repeating: 0.0, count: 5)
        let sorted = samples.sorted { $0.date < $1.date }
        for (i, s) in sorted.enumerated() {
            let next = i + 1 < sorted.count ? sorted[i + 1].date : end
            let dt = min(max(next.timeIntervalSince(s.date), 0), 60)
            let pct = s.bpm / maxHR
            let idx = bounds.lastIndex { pct >= $0 } ?? 0
            minutes[idx] += dt / 60
        }
        guard minutes.reduce(0, +) > 0 else { return [] }
        return (0..<5).map { i in
            let lo = Int(bounds[i] * maxHR)
            let range: String
            if i == 0 { range = "< \(Int(bounds[1] * maxHR)) bpm" }
            else if i == 4 { range = "\(lo)+ bpm" }
            else { range = "\(lo)–\(Int(bounds[i + 1] * maxHR)) bpm" }
            return HRZone(id: i + 1, name: "Zone \(i + 1)", range: range, minutes: minutes[i], color: colors[i])
        }
    }
}

// MARK: - Recovery

enum RecoveryCalculator {
    /// Banister TRIMP training load.
    static func trainingLoad(duration: TimeInterval, avgHR: Double?, restingHR: Double, maxHR: Double, energy: Double?) -> Double {
        let minutes = duration / 60
        if let hr = avgHR, maxHR > restingHR {
            let r = min(max((hr - restingHR) / (maxHR - restingHR), 0), 1)
            return minutes * r * 0.64 * exp(1.92 * r)
        }
        if let kcal = energy { return kcal / 5 }
        return minutes
    }

    /// Hours needed to recover from a given load, before personal modifiers.
    static func baseHours(load: Double) -> Double {
        min(max(4 + load * 0.33, 4), 72)
    }

    struct Inputs {
        var workouts: [WorkoutSummary]
        var sleepScore: Int?
        var hrvToday: Double?
        var hrvBaseline: Double?
        var rhrToday: Double?
        var rhrBaseline: Double?
        var now = Date()
    }

    static func evaluate(_ i: Inputs) -> (status: RecoveryStatus, modifier: Double) {
        var modifier = 1.0
        var factors: [RecoveryFactor] = []
        var parts: [(value: Double, weight: Double)] = []

        if let s = i.sleepScore {
            let m: Double = s >= 85 ? 0.9 : s >= 70 ? 1.0 : s >= 50 ? 1.15 : 1.3
            modifier *= m
            factors.append(RecoveryFactor(
                title: "Last night's sleep", value: "\(s)",
                detail: m < 1 ? "Great sleep is speeding up recovery" : m > 1 ? "Short or broken sleep is slowing recovery" : "Normal sleep",
                impact: m < 1 ? .positive : m > 1 ? .negative : .neutral))
            parts.append((value: Double(s), weight: 0.35))
        }

        if let t = i.hrvToday, let b = i.hrvBaseline, b > 0 {
            let ratio = t / b
            let m: Double = ratio >= 1.05 ? 0.9 : ratio >= 0.95 ? 1.0 : ratio >= 0.85 ? 1.1 : 1.25
            modifier *= m
            let diff = Int(((ratio - 1) * 100).rounded())
            factors.append(RecoveryFactor(
                title: "Heart rate variability", value: "\(Int(t)) ms",
                detail: "\(diff >= 0 ? "+" : "")\(diff)% vs your 30-day average (\(Int(b)) ms)",
                impact: m < 1 ? .positive : m > 1 ? .negative : .neutral))
            parts.append((value: SleepScorer.ramp(ratio, zero: 0.75, full: 1.10) * 100, weight: 0.35))
        }

        if let t = i.rhrToday, let b = i.rhrBaseline {
            let delta = t - b
            let m: Double = delta >= 5 ? 1.15 : delta >= 3 ? 1.05 : delta <= -2 ? 0.95 : 1.0
            modifier *= m
            let d = Int(delta.rounded())
            factors.append(RecoveryFactor(
                title: "Resting heart rate", value: "\(Int(t)) bpm",
                detail: "\(d >= 0 ? "+" : "")\(d) bpm vs your 30-day average (\(Int(b)) bpm)",
                impact: m < 1 ? .positive : m > 1 ? .negative : .neutral))
            parts.append((value: SleepScorer.ramp(delta, zero: 8, full: -2) * 100, weight: 0.15))
        }

        // Remaining fatigue from workouts in the last 5 days (latest dominates, older ones add residual).
        let recent = i.workouts.filter { i.now.timeIntervalSince($0.end) < 5 * 86400 }
        let remainings = recent
            .map { max(0, baseHours(load: $0.load) * modifier - i.now.timeIntervalSince($0.end) / 3600) }
            .sorted(by: >)
        let remaining = (remainings.first ?? 0) + remainings.dropFirst().reduce(0, +) * 0.3

        let latest = i.workouts.first
        var total = 0.0
        if let w = latest {
            let elapsed = i.now.timeIntervalSince(w.end) / 3600
            total = max(baseHours(load: w.load) * modifier, remaining + elapsed)
            factors.insert(RecoveryFactor(
                title: "Training load", value: "\(Int(w.load))",
                detail: "\(w.intensity) \(w.name.lowercased()) · \(w.end.formatted(.relative(presentation: .named)))",
                impact: w.load >= 100 ? .negative : .neutral), at: 0)
        }
        parts.append((value: SleepScorer.ramp(remaining, zero: 48, full: 0) * 100, weight: 0.15))

        let weight = parts.reduce(0) { $0 + $1.weight }
        let readiness = weight > 0 ? Int((parts.reduce(0) { $0 + $1.value * $1.weight } / weight).rounded()) : 0

        let status = RecoveryStatus(
            totalHours: total,
            remainingHours: remaining,
            readyAt: i.now.addingTimeInterval(remaining * 3600),
            readiness: readiness,
            factors: factors,
            lastWorkout: latest)
        return (status, modifier)
    }
}
