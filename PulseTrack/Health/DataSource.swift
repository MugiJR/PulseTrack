import Foundation

/// Plain data types shared by every data source (HealthKit or Shortcuts import).
enum Metric: String, CaseIterable {
    case heartRate = "HR"
    case restingHR = "RHR"
    case hrv = "HRV"
    case respiratory = "RR"
    case oxygen = "O2"
}

struct SleepRecord {
    let stage: SleepStage?   // nil = "In Bed"
    let start: Date
    let end: Date
    var fromWatch = true
}

struct Reading {
    let date: Date
    let value: Double
}

struct WorkoutRecord {
    let id: UUID
    let name: String
    let symbol: String
    let start: Date
    let end: Date
    var energy: Double?
    var distance: Double?
    var avgHR: Double?
    var maxHR: Double?
}

protocol HealthDataSource {
    func sleep(from start: Date, to end: Date) async throws -> [SleepRecord]
    func readings(_ metric: Metric, from start: Date, to end: Date) async throws -> [Reading]
    func workouts(since: Date, limit: Int) async throws -> [WorkoutRecord]
    func age() -> Int?
}

extension HealthDataSource {
    func average(_ metric: Metric, from start: Date, to end: Date) async throws -> Double? {
        let r = try await readings(metric, from: start, to: end)
        guard !r.isEmpty else { return nil }
        return r.map(\.value).reduce(0, +) / Double(r.count)
    }
}

// MARK: - Shortcuts-imported data

struct ImportedSource: HealthDataSource {
    var restingHR: Double
    var maxHR: Double
    private let store = ImportStore.shared

    func sleep(from start: Date, to end: Date) async throws -> [SleepRecord] {
        store.lines()
            .filter { $0.kind == "S" && $0.start >= start && $0.start < end }
            .map { SleepRecord(stage: Self.stage($0.value), start: $0.start, end: $0.end) }
            .filter { $0.stage != nil }
    }

    func readings(_ metric: Metric, from start: Date, to end: Date) async throws -> [Reading] {
        store.lines()
            .filter { $0.kind == metric.rawValue && $0.start >= start && $0.start <= end }
            .compactMap { line in
                guard var v = ImportStore.number(line.value) else { return nil }
                if metric == .oxygen && v <= 1 { v *= 100 }
                return Reading(date: line.start, value: v)
            }
    }

    func workouts(since: Date, limit: Int) async throws -> [WorkoutRecord] {
        let hr = try await readings(.heartRate, from: since, to: .now)
        var records: [WorkoutRecord] = store.lines()
            .filter { $0.kind == "W" && $0.start >= since && $0.end > $0.start }
            .map { line in
                let style = Self.workoutStyle(line.value)
                let inside = hr.filter { $0.date >= line.start && $0.date <= line.end }.map(\.value)
                return WorkoutRecord(
                    id: UUID(), name: style.name, symbol: style.symbol, start: line.start, end: line.end,
                    avgHR: inside.isEmpty ? nil : inside.reduce(0, +) / Double(inside.count),
                    maxHR: inside.max())
            }
        if records.isEmpty {
            records = WorkoutDetector.detect(hr, restingHR: restingHR, maxHR: maxHR)
        }
        return Array(records.sorted { $0.end > $1.end }.prefix(limit))
    }

    func age() -> Int? { nil }

    // MARK: Mapping helpers

    static func stage(_ raw: String) -> SleepStage? {
        let s = raw.lowercased()
        if let code = Int(s.trimmingCharacters(in: .whitespaces)) {
            switch code {
            case 2: return .awake
            case 3, 1: return .core
            case 4: return .deep
            case 5: return .rem
            default: return nil
            }
        }
        if s.contains("deep") { return .deep }
        if s.contains("rem") { return .rem }
        if s.contains("core") { return .core }
        if s.contains("awake") { return .awake }
        if s.contains("bed") { return nil }
        if s.contains("asleep") || s.contains("unspecified") { return .core }
        return nil
    }

    static func workoutStyle(_ raw: String) -> (name: String, symbol: String) {
        let s = raw.lowercased()
        let table: [([String], String, String)] = [
            (["hiit", "interval"], "HIIT", "figure.highintensity.intervaltraining"),
            (["functional"], "Functional Strength", "figure.strengthtraining.functional"),
            (["strength", "weight"], "Strength Training", "figure.strengthtraining.traditional"),
            (["run"], "Run", "figure.run"),
            (["walk"], "Walk", "figure.walk"),
            (["cycl", "bike", "biking"], "Cycling", "figure.outdoor.cycle"),
            (["swim"], "Swim", "figure.pool.swim"),
            (["hik"], "Hike", "figure.hiking"),
            (["yoga"], "Yoga", "figure.yoga"),
            (["pilates"], "Pilates", "figure.pilates"),
            (["rowing", "rower"], "Rowing", "figure.rower"),
            (["ellip"], "Elliptical", "figure.elliptical"),
            (["stair"], "Stair Stepper", "figure.stair.stepper"),
            (["core"], "Core Training", "figure.core.training"),
            (["dance"], "Dance", "figure.dance"),
            (["tennis"], "Tennis", "figure.tennis"),
            (["soccer", "football"], "Football", "figure.soccer"),
            (["basketball"], "Basketball", "figure.basketball"),
            (["cooldown"], "Cooldown", "figure.cooldown")
        ]
        for (keys, name, symbol) in table where keys.contains(where: { s.contains($0) }) {
            return (name, symbol)
        }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let isNumber = Double(trimmed.replacingOccurrences(of: ",", with: ".")) != nil
        return (trimmed.isEmpty || isNumber ? "Workout" : trimmed.capitalized, "figure.mixed.cardio")
    }
}

/// Finds workouts in heart-rate data when the shortcut doesn't send workout samples.
enum WorkoutDetector {
    static func detect(_ hr: [Reading], restingHR: Double, maxHR: Double) -> [WorkoutRecord] {
        let threshold = restingHR + 0.45 * (maxHR - restingHR)
        var result: [WorkoutRecord] = []
        var current: [Reading] = []

        func flush() {
            defer { current = [] }
            guard let first = current.first, let last = current.last,
                  last.date.timeIntervalSince(first.date) >= 10 * 60 else { return }
            let values = current.map(\.value)
            result.append(WorkoutRecord(
                id: UUID(), name: "Detected activity", symbol: "figure.mixed.cardio",
                start: first.date, end: last.date,
                avgHR: values.reduce(0, +) / Double(values.count), maxHR: values.max()))
        }

        for r in hr.sorted(by: { $0.date < $1.date }) {
            if let last = current.last, r.date.timeIntervalSince(last.date) > 180 { flush() }
            if r.value >= threshold { current.append(r) }
        }
        flush()
        return result
    }
}
