import Foundation
import HealthKit

enum HealthError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "Apple Health isn't available on this device. Run PulseTrack on an iPhone paired with your Apple Watch."
    }
}

extension HKUnit {
    static let bpm = HKUnit.count().unitDivided(by: .minute())
    static let ms = HKUnit.secondUnit(with: .milli)
}

/// Direct HealthKit access (needs the HealthKit entitlement, i.e. a paid developer account or Xcode signing).
final class HealthService: HealthDataSource {
    let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.distanceSwimming),
            HKObjectType.workoutType(),
            HKCharacteristicType(.dateOfBirth)
        ]
    }

    func requestAuthorization() async throws {
        guard Self.isAvailable else { throw HealthError.unavailable }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: HealthDataSource

    func sleep(from start: Date, to end: Date) async throws -> [SleepRecord] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await descriptor.result(for: store)
        return samples.map { s in
            SleepRecord(
                stage: HKCategoryValueSleepAnalysis(rawValue: s.value).flatMap(SleepAnalyzer.stage(for:)),
                start: s.startDate, end: s.endDate,
                fromWatch: s.sourceRevision.productType?.hasPrefix("Watch") == true)
        }
    }

    func readings(_ metric: Metric, from start: Date, to end: Date) async throws -> [Reading] {
        let (id, unit, scale): (HKQuantityTypeIdentifier, HKUnit, Double) = switch metric {
        case .heartRate: (.heartRate, .bpm, 1)
        case .restingHR: (.restingHeartRate, .bpm, 1)
        case .hrv: (.heartRateVariabilitySDNN, .ms, 1)
        case .respiratory: (.respiratoryRate, .bpm, 1)
        case .oxygen: (.oxygenSaturation, .percent(), 100)
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store).map {
            Reading(date: $0.startDate, value: $0.quantity.doubleValue(for: unit) * scale)
        }
    }

    func workouts(since: Date, limit: Int) async throws -> [WorkoutRecord] {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: limit
        )
        return try await descriptor.result(for: store).map { w in
            let hrStats = w.statistics(for: HKQuantityType(.heartRate))
            let distanceTypes: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
            return WorkoutRecord(
                id: w.uuid,
                name: w.workoutActivityType.displayName,
                symbol: w.workoutActivityType.symbol,
                start: w.startDate, end: w.endDate,
                energy: w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                distance: distanceTypes.lazy
                    .compactMap { w.statistics(for: HKQuantityType($0))?.sumQuantity()?.doubleValue(for: .meter()) }
                    .first,
                avgHR: hrStats?.averageQuantity()?.doubleValue(for: .bpm),
                maxHR: hrStats?.maximumQuantity()?.doubleValue(for: .bpm))
        }
    }

    func age() -> Int? {
        guard let dob = try? store.dateOfBirthComponents(), let birth = Calendar.current.date(from: dob) else { return nil }
        return Calendar.current.dateComponents([.year], from: birth, to: Date()).year
    }
}

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .running: "Run"
        case .walking: "Walk"
        case .cycling: "Cycling"
        case .swimming: "Swim"
        case .hiking: "Hike"
        case .traditionalStrengthTraining: "Strength Training"
        case .functionalStrengthTraining: "Functional Strength"
        case .highIntensityIntervalTraining: "HIIT"
        case .coreTraining: "Core Training"
        case .yoga: "Yoga"
        case .pilates: "Pilates"
        case .rowing: "Rowing"
        case .elliptical: "Elliptical"
        case .stairClimbing: "Stair Stepper"
        case .crossTraining: "Cross Training"
        case .mixedCardio: "Mixed Cardio"
        case .dance: "Dance"
        case .tennis: "Tennis"
        case .soccer: "Football"
        case .basketball: "Basketball"
        case .cooldown: "Cooldown"
        default: "Workout"
        }
    }

    var symbol: String {
        switch self {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .cycling: "figure.outdoor.cycle"
        case .swimming: "figure.pool.swim"
        case .hiking: "figure.hiking"
        case .traditionalStrengthTraining: "figure.strengthtraining.traditional"
        case .functionalStrengthTraining: "figure.strengthtraining.functional"
        case .highIntensityIntervalTraining: "figure.highintensity.intervaltraining"
        case .coreTraining: "figure.core.training"
        case .yoga: "figure.yoga"
        case .pilates: "figure.pilates"
        case .rowing: "figure.rower"
        case .elliptical: "figure.elliptical"
        case .stairClimbing: "figure.stair.stepper"
        case .crossTraining: "figure.cross.training"
        case .dance: "figure.dance"
        case .tennis: "figure.tennis"
        case .soccer: "figure.soccer"
        case .basketball: "figure.basketball"
        case .cooldown: "figure.cooldown"
        default: "figure.mixed.cardio"
        }
    }
}
