//
//  HealthKitService.swift
//  StarkCompanion — reads every metric the HUD understands from HealthKit.
//

import Foundation
import HealthKit

final class HealthKitService {

    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: Type mapping

    private func quantityType(for kind: MetricKind) -> HKQuantityType? {
        switch kind {
        case .heartRate: return HKQuantityType(.heartRate)
        case .restingHeartRate: return HKQuantityType(.restingHeartRate)
        case .heartRateVariability: return HKQuantityType(.heartRateVariabilitySDNN)
        case .bloodOxygen: return HKQuantityType(.oxygenSaturation)
        case .respiratoryRate: return HKQuantityType(.respiratoryRate)
        case .vo2Max: return HKQuantityType(.vo2Max)
        case .steps: return HKQuantityType(.stepCount)
        case .activeEnergy: return HKQuantityType(.activeEnergyBurned)
        case .exerciseMinutes: return HKQuantityType(.appleExerciseTime)
        case .distanceWalkingRunning: return HKQuantityType(.distanceWalkingRunning)
        case .flightsClimbed: return HKQuantityType(.flightsClimbed)
        case .bodyMass: return HKQuantityType(.bodyMass)
        case .walkingSpeed: return HKQuantityType(.walkingSpeed)
        case .standHours, .sleepHours, .mindfulMinutes: return nil // category-based
        }
    }

    private func unit(for kind: MetricKind) -> HKUnit {
        switch kind {
        case .heartRate, .restingHeartRate, .respiratoryRate:
            return HKUnit.count().unitDivided(by: .minute())
        case .heartRateVariability:
            return HKUnit.secondUnit(with: .milli)
        case .bloodOxygen:
            return HKUnit.percent()
        case .vo2Max:
            return HKUnit(from: "ml/kg*min")
        case .steps, .flightsClimbed:
            return HKUnit.count()
        case .activeEnergy:
            return HKUnit.kilocalorie()
        case .exerciseMinutes:
            return HKUnit.minute()
        case .distanceWalkingRunning:
            return HKUnit.meterUnit(with: .kilo)
        case .bodyMass:
            return HKUnit.gramUnit(with: .kilo)
        case .walkingSpeed:
            return HKUnit(from: "km/hr")
        case .standHours, .sleepHours, .mindfulMinutes:
            return HKUnit.count()
        }
    }

    // MARK: Authorization

    func requestAuthorization() async throws {
        var readTypes: Set<HKObjectType> = []
        for kind in MetricKind.allCases {
            if let qt = quantityType(for: kind) { readTypes.insert(qt) }
        }
        readTypes.insert(HKCategoryType(.appleStandHour))
        readTypes.insert(HKCategoryType(.sleepAnalysis))
        readTypes.insert(HKCategoryType(.mindfulSession))

        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: Snapshot

    /// Gathers one full telemetry frame: today's totals for cumulative
    /// metrics, most recent readings for point-in-time metrics, and a
    /// recent heart-rate series for the EKG trace.
    func snapshot(sourceName: String) async -> TelemetryPayload {
        var samples: [MetricSample] = []
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)

        for kind in MetricKind.allCases {
            guard let qt = quantityType(for: kind) else { continue }
            let value: Double?
            if kind.isCumulative {
                value = await todaysSum(type: qt, unit: unit(for: kind), from: startOfDay)
            } else {
                value = await latestValue(type: qt, unit: unit(for: kind))
            }
            if var v = value {
                if kind == .bloodOxygen { v *= 100 } // HK stores 0..1
                samples.append(MetricSample(kind: kind, value: v, date: now))
            }
        }

        if let stand = await standHoursToday(from: startOfDay) {
            samples.append(MetricSample(kind: .standHours, value: stand, date: now))
        }
        if let sleep = await sleepHoursLastNight() {
            samples.append(MetricSample(kind: .sleepHours, value: sleep, date: now))
        }
        if let mindful = await mindfulMinutesToday(from: startOfDay) {
            samples.append(MetricSample(kind: .mindfulMinutes, value: mindful, date: now))
        }

        let series = await recentHeartRateSeries()

        return TelemetryPayload(samples: samples,
                                heartRateSeries: series,
                                sourceName: sourceName,
                                sentAt: now)
    }

    // MARK: Query helpers

    private func todaysSum(type: HKQuantityType, unit: HKUnit, from start: Date) async -> Double? {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: type,
                                          quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func latestValue(type: HKQuantityType, unit: HKUnit) async -> Double? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: type,
                                      predicate: nil,
                                      limit: 1,
                                      sortDescriptors: [sort]) { _, results, _ in
                let quantitySample = results?.first as? HKQuantitySample
                continuation.resume(returning: quantitySample?.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func standHoursToday(from start: Date) async -> Double? {
        await withCheckedContinuation { continuation in
            let type = HKCategoryType(.appleStandHour)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)
            let query = HKSampleQuery(sampleType: type,
                                      predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, results, _ in
                guard let categories = results as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                let stood = categories.filter {
                    $0.value == HKCategoryValueAppleStandHour.stood.rawValue
                }.count
                continuation.resume(returning: Double(stood))
            }
            store.execute(query)
        }
    }

    private func sleepHoursLastNight() async -> Double? {
        await withCheckedContinuation { continuation in
            let type = HKCategoryType(.sleepAnalysis)
            // From 6 PM yesterday to now covers a normal night.
            let start = Calendar.current.date(byAdding: .hour, value: -6,
                                              to: Calendar.current.startOfDay(for: Date()))!
            let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: [])
            let query = HKSampleQuery(sampleType: type,
                                      predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, results, _ in
                guard let categories = results as? [HKCategorySample], !categories.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let asleepValues: Set<Int> = [
                    HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                    HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                ]
                let seconds = categories
                    .filter { asleepValues.contains($0.value) }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: seconds > 0 ? seconds / 3600 : nil)
            }
            store.execute(query)
        }
    }

    private func mindfulMinutesToday(from start: Date) async -> Double? {
        await withCheckedContinuation { continuation in
            let type = HKCategoryType(.mindfulSession)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: [])
            let query = HKSampleQuery(sampleType: type,
                                      predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: nil) { _, results, _ in
                guard let categories = results as? [HKCategorySample], !categories.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                let seconds = categories.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: seconds / 60)
            }
            store.execute(query)
        }
    }

    /// Heart-rate readings from the last 30 minutes, oldest first.
    private func recentHeartRateSeries() async -> [Double] {
        await withCheckedContinuation { continuation in
            let type = HKQuantityType(.heartRate)
            let start = Date().addingTimeInterval(-30 * 60)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let bpmUnit = HKUnit.count().unitDivided(by: .minute())
            let query = HKSampleQuery(sampleType: type,
                                      predicate: predicate,
                                      limit: 120,
                                      sortDescriptors: [sort]) { _, results, _ in
                let values = (results as? [HKQuantitySample])?.map {
                    $0.quantity.doubleValue(for: bpmUnit)
                } ?? []
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }
}
