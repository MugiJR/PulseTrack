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

/// Thin async wrapper around HealthKit. Read-only.
final class HealthService {
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

    func sleepSamples(from start: Date, to end: Date) async throws -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store)
    }

    func quantitySamples(_ id: HKQuantityTypeIdentifier, from start: Date, to end: Date) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store)
    }

    func average(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date, to end: Date) async throws -> Double? {
        let samples = try await quantitySamples(id, from: start, to: end)
        guard !samples.isEmpty else { return nil }
        return samples.map { $0.quantity.doubleValue(for: unit) }.reduce(0, +) / Double(samples.count)
    }

    func workouts(since: Date, limit: Int) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: limit
        )
        return try await descriptor.result(for: store)
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
