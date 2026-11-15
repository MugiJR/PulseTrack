import Foundation
import HealthKit
import Observation

@MainActor
@Observable
final class HealthManager {
    enum Phase: Equatable { case idle, loading, ready, failed(String) }

    var phase: Phase = .idle
    var isDemo = false

    var selectedDay: Date = Calendar.current.startOfDay(for: .now)
    var night: SleepNight?
    var sleepScore: SleepScore?
    var history: [NightScore] = []

    var workouts: [WorkoutSummary] = []
    var selectedWorkoutID: UUID?
    var zones: [HRZone] = []

    var recovery: RecoveryStatus?
    private(set) var recoveryModifier = 1.0

    var maxHR: Double = 190
    var restingHR: Double = 60

    private let service = HealthService()
    @ObservationIgnored private var lastBaselines = Baselines()

    private struct Baselines {
        var hrvToday: Double?, hrvBase: Double?, rhrToday: Double?, rhrBase: Double?
    }

    var hasConnected: Bool = UserDefaults.standard.bool(forKey: "hasConnectedHealth") {
        didSet { UserDefaults.standard.set(hasConnected, forKey: "hasConnectedHealth") }
    }

    var needsOnboarding: Bool { !hasConnected && !isDemo }

    var selectedWorkout: WorkoutSummary? {
        workouts.first { $0.id == selectedWorkoutID } ?? workouts.first
    }

    var isToday: Bool { Calendar.current.isDateInToday(selectedDay) }

    var errorMessage: String? {
        if case .failed(let msg) = phase { return msg }
        return nil
    }

    func recoveryHours(for workout: WorkoutSummary) -> Double {
        RecoveryCalculator.baseHours(load: workout.load) * recoveryModifier
    }

    // MARK: - Lifecycle

    func start() async {
        if hasConnected { await refresh() }
    }

    func connect() async {
        do {
            try await service.requestAuthorization()
            hasConnected = true
            await refresh()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func setDemo(_ on: Bool) async {
        isDemo = on
        selectedDay = Calendar.current.startOfDay(for: .now)
        if !on && !hasConnected {
            night = nil; sleepScore = nil; history = []; workouts = []; zones = []; recovery = nil
            phase = .idle
            return
        }
        await refresh()
    }

    func refresh() async {
        phase = .loading
        if isDemo { loadDemo(); phase = .ready; return }
        do {
            if let age = service.age() { maxHR = 208 - 0.7 * Double(age) }
            lastBaselines = try await loadBaselines()
            restingHR = lastBaselines.rhrBase ?? lastBaselines.rhrToday ?? 60
            try await loadSleep()
            try await loadHistory()
            try await loadWorkouts()
            computeRecovery()
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func shiftDay(by days: Int) async {
        guard let day = Calendar.current.date(byAdding: .day, value: days, to: selectedDay),
              day <= Calendar.current.startOfDay(for: .now) else { return }
        selectedDay = day
        if isDemo {
            night = DemoData.night(for: day)
            sleepScore = night.map { SleepScorer.score($0) }
        } else {
            try? await loadSleep()
        }
    }

    func select(_ workout: WorkoutSummary) async {
        selectedWorkoutID = workout.id
        await loadZones(for: workout)
    }

    // MARK: - Loading

    private func loadBaselines() async throws -> Baselines {
        let hrv = try await dailyMeans(.heartRateVariabilitySDNN, unit: .ms, days: 30)
        let rhr = try await dailyMeans(.restingHeartRate, unit: .bpm, days: 30)
        let h = split(hrv), r = split(rhr)
        return Baselines(hrvToday: h.today, hrvBase: h.baseline, rhrToday: r.today, rhrBase: r.baseline)
    }

    private func dailyMeans(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async throws -> [Date: Double] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: .now))!
        let samples = try await service.quantitySamples(id, from: start, to: .now)
        let grouped = Dictionary(grouping: samples) { cal.startOfDay(for: $0.startDate) }
        return grouped.mapValues { arr in
            arr.map { $0.quantity.doubleValue(for: unit) }.reduce(0, +) / Double(arr.count)
        }
    }

    private func split(_ means: [Date: Double]) -> (today: Double?, baseline: Double?) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let current = means[today] ?? means[yesterday]
        let past = means.filter { $0.key < today }.map(\.value)
        return (current, past.isEmpty ? nil : past.reduce(0, +) / Double(past.count))
    }

    private func loadSleep() async throws {
        let window = SleepAnalyzer.window(for: selectedDay)
        let samples = try await service.sleepSamples(from: window.start, to: window.end)
        let segments = SleepAnalyzer.segments(from: samples)
        guard !segments.isEmpty else { night = nil; sleepScore = nil; return }
        var n = SleepNight(wakeDay: selectedDay, segments: segments)
        n.vitals = try await vitals(from: n.start, to: n.end)
        night = n
        sleepScore = SleepScorer.score(n)
    }

    private func vitals(from start: Date, to end: Date) async throws -> SleepVitals {
        let hr = try await service.average(.heartRate, unit: .bpm, from: start, to: end)
        let hrv = try await service.average(.heartRateVariabilitySDNN, unit: .ms, from: start, to: end)
        let resp = try await service.average(.respiratoryRate, unit: .bpm, from: start, to: end)
        let spo2 = try await service.average(.oxygenSaturation, unit: .percent(), from: start, to: end)
        return SleepVitals(heartRate: hr, hrv: hrv, respiratoryRate: resp, oxygen: spo2.map { $0 * 100 })
    }

    private func loadHistory() async throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }.reversed()
        guard let first = days.first else { return }
        let samples = try await service.sleepSamples(from: SleepAnalyzer.window(for: first).start,
                                                     to: SleepAnalyzer.window(for: today).end)
        history = days.compactMap { day in
            let w = SleepAnalyzer.window(for: day)
            let daySamples = samples.filter { $0.startDate >= w.start && $0.startDate < w.end }
            let segs = SleepAnalyzer.segments(from: daySamples)
            guard !segs.isEmpty else { return nil }
            return NightScore(date: day, score: SleepScorer.score(SleepNight(wakeDay: day, segments: segs)).total)
        }
    }

    private func loadWorkouts() async throws {
        let since = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
        let hk = try await service.workouts(since: since, limit: 25)
        workouts = hk.map(summary(for:))
        selectedWorkoutID = workouts.first?.id
        if let w = workouts.first { await loadZones(for: w) } else { zones = [] }
    }

    private func summary(for w: HKWorkout) -> WorkoutSummary {
        let hrStats = w.statistics(for: HKQuantityType(.heartRate))
        let avg = hrStats?.averageQuantity()?.doubleValue(for: .bpm)
        let mx = hrStats?.maximumQuantity()?.doubleValue(for: .bpm)
        let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        let distanceTypes: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
        let dist = distanceTypes.lazy
            .compactMap { w.statistics(for: HKQuantityType($0))?.sumQuantity()?.doubleValue(for: .meter()) }
            .first
        let load = RecoveryCalculator.trainingLoad(duration: w.duration, avgHR: avg, restingHR: restingHR, maxHR: maxHR, energy: kcal)
        return WorkoutSummary(id: w.uuid, name: w.workoutActivityType.displayName, symbol: w.workoutActivityType.symbol,
                              start: w.startDate, end: w.endDate, energy: kcal, distance: dist,
                              avgHR: avg, maxHR: mx, load: load)
    }

    private func loadZones(for w: WorkoutSummary) async {
        if isDemo {
            zones = ZoneCalculator.zones(samples: DemoData.heartRateSeries(for: w), end: w.end, maxHR: maxHR)
            return
        }
        let samples = (try? await service.quantitySamples(.heartRate, from: w.start, to: w.end)) ?? []
        zones = ZoneCalculator.zones(samples: samples.map { (date: $0.startDate, bpm: $0.quantity.doubleValue(for: .bpm)) },
                                     end: w.end, maxHR: maxHR)
    }

    private func computeRecovery() {
        // Recovery always uses the most recent night, regardless of which night is being browsed.
        let todayScore = history.last(where: { Calendar.current.isDateInToday($0.date) })?.score
            ?? (isToday ? sleepScore?.total : nil)
        let result = RecoveryCalculator.evaluate(.init(
            workouts: workouts,
            sleepScore: todayScore,
            hrvToday: lastBaselines.hrvToday, hrvBaseline: lastBaselines.hrvBase,
            rhrToday: lastBaselines.rhrToday, rhrBaseline: lastBaselines.rhrBase))
        recovery = result.status
        recoveryModifier = result.modifier
    }

    // MARK: - Demo

    private func loadDemo() {
        maxHR = 188
        restingHR = 54
        lastBaselines = Baselines(hrvToday: 54, hrvBase: 58, rhrToday: 55, rhrBase: 54)
        night = DemoData.night(for: selectedDay)
        sleepScore = night.map { SleepScorer.score($0) }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        history = (0..<7).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return NightScore(date: d, score: SleepScorer.score(DemoData.night(for: d)).total)
        }
        workouts = DemoData.workouts(restingHR: restingHR, maxHR: maxHR)
        selectedWorkoutID = workouts.first?.id
        if let w = workouts.first {
            zones = ZoneCalculator.zones(samples: DemoData.heartRateSeries(for: w), end: w.end, maxHR: maxHR)
        }
        computeRecovery()
    }
}
