import SwiftUI

// MARK: - Sleep

enum SleepStage: String, CaseIterable, Identifiable {
    case awake, rem, core, deep

    var id: String { rawValue }

    var label: String {
        switch self {
        case .awake: "Awake"
        case .rem: "REM"
        case .core: "Core"
        case .deep: "Deep"
        }
    }

    var color: Color {
        switch self {
        case .awake: Color(red: 1.00, green: 0.55, blue: 0.45)
        case .rem: Color(red: 0.35, green: 0.80, blue: 1.00)
        case .core: Color(red: 0.25, green: 0.50, blue: 1.00)
        case .deep: Color(red: 0.48, green: 0.32, blue: 0.95)
        }
    }

    /// Healthy share of total sleep, shown as guidance in the UI.
    var idealRange: String {
        switch self {
        case .awake: "< 10% of time in bed"
        case .rem: "20–25%"
        case .core: "45–55%"
        case .deep: "13–23%"
        }
    }
}

struct StageSegment: Identifiable {
    let id = UUID()
    let stage: SleepStage
    let start: Date
    let end: Date
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

struct SleepVitals {
    var heartRate: Double?        // bpm
    var hrv: Double?              // ms (SDNN)
    var respiratoryRate: Double?  // breaths/min
    var oxygen: Double?           // %
}

struct SleepNight {
    /// The calendar day the night ends on (the morning you woke up).
    let wakeDay: Date
    let segments: [StageSegment]
    var vitals = SleepVitals()

    var start: Date { segments.first?.start ?? wakeDay }
    var end: Date { segments.last?.end ?? wakeDay }
    var timeInBed: TimeInterval { end.timeIntervalSince(start) }

    func duration(of stage: SleepStage) -> TimeInterval {
        segments.filter { $0.stage == stage }.reduce(0) { $0 + $1.duration }
    }

    var asleep: TimeInterval { duration(of: .rem) + duration(of: .core) + duration(of: .deep) }
    /// Awake time including any untracked gaps between samples.
    var awake: TimeInterval { max(0, timeInBed - asleep) }
    var efficiency: Double { timeInBed > 0 ? asleep / timeInBed : 0 }

    /// Share of total sleep (or of time in bed, for Awake).
    func share(of stage: SleepStage) -> Double {
        if stage == .awake { return timeInBed > 0 ? awake / timeInBed : 0 }
        return asleep > 0 ? duration(of: stage) / asleep : 0
    }

    /// Wake-ups of 2+ minutes in the middle of the night.
    var awakenings: Int {
        guard segments.count > 2 else { return 0 }
        return segments.dropFirst().dropLast().filter { $0.stage == .awake && $0.duration >= 120 }.count
    }
}

struct ScoreComponent: Identifiable {
    let id = UUID()
    let name: String
    let points: Double
    let maxPoints: Double
    let detail: String
}

struct SleepScore {
    let total: Int
    let components: [ScoreComponent]

    var rating: String {
        switch total {
        case 85...: "Excellent"
        case 70..<85: "Good"
        case 50..<70: "Fair"
        default: "Poor"
        }
    }

    var color: Color { Theme.scoreColor(total) }
}

struct NightScore: Identifiable {
    var id: Date { date }
    let date: Date
    let score: Int
}

// MARK: - Workouts

struct WorkoutSummary: Identifiable {
    let id: UUID
    let name: String
    let symbol: String
    let start: Date
    let end: Date
    let energy: Double?     // kcal
    let distance: Double?   // meters
    let avgHR: Double?
    let maxHR: Double?
    let load: Double        // TRIMP

    var duration: TimeInterval { end.timeIntervalSince(start) }

    var intensity: String {
        switch load {
        case ..<50: "Light"
        case 50..<100: "Moderate"
        case 100..<180: "Hard"
        default: "Very hard"
        }
    }
}

struct HRZone: Identifiable {
    let id: Int
    let name: String
    let range: String
    let minutes: Double
    let color: Color
}

// MARK: - Recovery

enum Impact {
    case positive, neutral, negative

    var color: Color {
        switch self {
        case .positive: Theme.recovery
        case .neutral: .secondary
        case .negative: Color(red: 1.0, green: 0.45, blue: 0.4)
        }
    }

    var symbol: String {
        switch self {
        case .positive: "arrow.up.circle.fill"
        case .neutral: "minus.circle.fill"
        case .negative: "arrow.down.circle.fill"
        }
    }
}

struct RecoveryFactor: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
    let impact: Impact
}

struct RecoveryStatus {
    let totalHours: Double
    let remainingHours: Double
    let readyAt: Date
    let readiness: Int
    let factors: [RecoveryFactor]
    let lastWorkout: WorkoutSummary?

    var progress: Double {
        guard totalHours > 0 else { return 1 }
        return 1 - min(remainingHours / totalHours, 1)
    }

    var recommendation: String {
        if remainingHours < 1 && readiness >= 70 {
            return "You're fully recovered. Today is a good day for a hard or long session."
        } else if remainingHours < 1 {
            return "Your muscles have recovered, but your body signals are below normal. Keep it moderate today."
        } else if remainingHours < 12 {
            return "Nearly there. Light to moderate training is fine — save high intensity for when you're fully recovered."
        } else {
            return "Prioritise rest. Stick to mobility, walking or an easy Zone 1–2 session, and aim for a full night's sleep."
        }
    }
}
