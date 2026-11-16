import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class HealthManager {
    enum Phase: Equatable { case idle, loading, ready, failed(String) }

    /// Where data comes from: HealthKit directly, or a Shortcuts automation (works with free sideloading).
    enum Source: String { case healthKit, shortcut }

    var phase: Phase = .idle
    var isDemo = false
    var source: Source? = UserDefaults.standard.string(forKey: "dataSource").flatMap(Source.init(rawValue:)) {
        didSet { UserDefaults.standard.set(source?.rawValue, forKey: "dataSource") }
    }
    var lastImport: Date? = ImportStore.shared.lastImport
    var showShortcutGuide = false

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

    @ObservationIgnored private let healthKit = HealthService()
    @ObservationIgnored private var lastBaselines = Baselines()
    @ObservationIgnored private var observer: NSObjectProtocol?

    private struct Baselines {
        var hrvToday: Double?, hrvBase: Double?, rhrToday: Double?, rhrBase: Double?
    }

    init() {
        observer = NotificationCenter.default.addObserver(forName: ImportStore.didChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private var dataSource: HealthDataSource {
        if source == .shortcut {
            return ImportedSource(restingHR: restingHR, maxHR: maxHR)
        }
        return healthKit
    }

    var needsOnboarding: Bool { source == nil && !isDemo }
    var usesShortcut: Bool { source == .shortcut && !isDemo }
    var awaitingFirstImport: Bool { usesShortcut && lastImport == nil }

    var selectedWorkout: WorkoutSummary? {
        workouts.first { $0.id == selectedWorkoutID } ?? workouts.first
    }

    var isToday: Bool { Calendar.current.isDateInToday(selectedDay) }

    var errorMessage: String? {
        if case .failed(let msg) = phase { return msg }
        return nil
    }

    var isEntitlementError: Bool { errorMessage?.localizedCaseInsensitiveContains("entitlement") == true }

    func recoveryHours(for workout: WorkoutSummary) -> Double {
        RecoveryCalculator.baseHours(load: workout.load) * recoveryModifier
    }

    // MARK: - Lifecycle

    func start() async {
        if source != nil { await refresh() }
    }

    func connect() async {
        do {
            try await healthKit.requestAuthorization()
            source = .healthKit
            isDemo = false
            await refresh()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func useShortcut() async {
        source = .shortcut
        isDemo = false
        if lastImport == nil { showShortcutGuide = true }
        await refresh()
    }

    func useHealthKit() async {
        await connect()
    }

    func importFromClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            phase = .failed("The clipboard is empty. Run the PulseTrack Sync shortcut with \"Copy to Clipboard\" first.")
            return
        }
        do {
            try ImportStore.shared.ingest(text)
            if source == nil { source = .shortcut }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func setDemo(_ on: Bool) async {
        isDemo = on
        selectedDay = Calendar.current.startOfDay(for: .now)
        if !on && source == nil {
            night = nil; sleepScore = nil; history = []; workouts = []; zones = []; recovery = nil
            phase = .idle
            return
        }
        await refresh()
    }

    func refresh() async {
        lastImport = ImportStore.shared.lastImport
        phase = .loading
        if isDemo { loadDemo(); phase = .ready; return }
        do {
            if let age = dataSource.age() { maxHR = 208 - 0.7 * Double(age) }
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
        let hrv = try await dailyMeans(.hrv, days: 30)
        let rhr = try await dailyMeans(.restingHR, days: 30)
        let h = split(hrv), r = split(rhr)
        return Baselines(hrvToday: h.today, hrvBase: h.baseline, rhrToday: r.today, rhrBase: r.baseline)
    }

    private func dailyMeans(_ metric: Metric, days: Int) async throws -> [Date: Double] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: .now))!
        let readings = try await dataSource.readings(metric, from: start, to: .now)
        let grouped = Dictionary(grouping: readings) { cal.startOfDay(for: $0.date) }
        return grouped.mapValues { arr in arr.map(\.value).reduce(0, +) / Double(arr.count) }
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
        let records = try await dataSource.sleep(from: window.start, to: window.end)
        let segments = SleepAnalyzer.segments(from: records)
        guard !segments.isEmpty else { night = nil; sleepScore = nil; return }
        var n = SleepNight(wakeDay: selectedDay, segments: segments)
        n.vitals = try await vitals(from: n.start, to: n.end)
        night = n
        sleepScore = SleepScorer.score(n)
    }

    private func vitals(from start: Date, to end: Date) async throws -> SleepVitals {
        let source = dataSource
        let hr = try await source.average(.heartRate, from: start, to: end)
        let hrv = try await source.average(.hrv, from: start, to: end)
        let resp = try await source.average(.respiratory, from: start, to: end)
        let spo2 = try await source.average(.oxygen, from: start, to: end)
        return SleepVitals(heartRate: hr, hrv: hrv, respiratoryRate: resp, oxygen: spo2)
    }

    private func loadHistory() async throws {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }.reversed()
        guard let first = days.first else { return }
        let records = try await dataSource.sleep(from: SleepAnalyzer.window(for: first).start,
                                                 to: SleepAnalyzer.window(for: today).end)
        history = days.compactMap { day in
            let w = SleepAnalyzer.window(for: day)
            let segs = SleepAnalyzer.segments(from: records.filter { $0.start >= w.start && $0.start < w.end })
            guard !segs.isEmpty else { return nil }
            return NightScore(date: day, score: SleepScorer.score(SleepNight(wakeDay: day, segments: segs)).total)
        }
    }

    private func loadWorkouts() async throws {
        let since = Calendar.current.date(byAdding: .day, value: -30, to: .now)!
        let records = try await dataSource.workouts(since: since, limit: 25)
        workouts = records.map { r in
            WorkoutSummary(
                id: r.id, name: r.name, symbol: r.symbol, start: r.start, end: r.end,
                energy: r.energy, distance: r.distance, avgHR: r.avgHR, maxHR: r.maxHR,
                load: RecoveryCalculator.trainingLoad(duration: r.end.timeIntervalSince(r.start), avgHR: r.avgHR,
                                                      restingHR: restingHR, maxHR: maxHR, energy: r.energy))
        }
        selectedWorkoutID = workouts.first?.id
        if let w = workouts.first { await loadZones(for: w) } else { zones = [] }
    }

    private func loadZones(for w: WorkoutSummary) async {
        if isDemo {
            zones = ZoneCalculator.zones(samples: DemoData.heartRateSeries(for: w), end: w.end, maxHR: maxHR)
            return
        }
        let readings = (try? await dataSource.readings(.heartRate, from: w.start, to: w.end)) ?? []
        zones = ZoneCalculator.zones(samples: readings.map { (date: $0.date, bpm: $0.value) }, end: w.end, maxHR: maxHR)
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
