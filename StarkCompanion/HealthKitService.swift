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

        // Workout history for the combat log.
        readTypes.insert(HKObjectType.workoutType())
        readTypes.insert(HKQuantityType(.distanceCycling))

        // Phone-native gait metrics for chassis diagnostics.
        readTypes.insert(HKQuantityType(.appleWalkingSteadiness))
        readTypes.insert(HKQuantityType(.walkingAsymmetryPercentage))
        readTypes.insert(HKQuantityType(.walkingDoubleSupportPercentage))
        readTypes.insert(HKQuantityType(.walkingStepLength))
        readTypes.insert(HKQuantityType(.stairAscentSpeed))
        readTypes.insert(HKQuantityType(.stairDescentSpeed))
        readTypes.insert(HKQuantityType(.sixMinuteWalkTestDistance))

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
        if let mindful = await mindfulMinutesToday(from: startOfDay) {
            samples.append(MetricSample(kind: .mindfulMinutes, value: mindful, date: now))
        }

        let report = await sleepReport()
        if let night = report?.lastNight {
            samples.append(MetricSample(kind: .sleepHours, value: night.totalHours, date: now))
        }

        let series = await recentHeartRateSeries()
        let workouts = await recentWorkouts()
        let mobility = await mobilityReport()

        return TelemetryPayload(samples: samples,
                                heartRateSeries: series,
                                sourceName: sourceName,
                                sentAt: now,
                                sleep: report,
                                workouts: workouts.isEmpty ? nil : workouts,
                                mobility: mobility.hasAnyData ? mobility : nil)
    }

    // MARK: Workout history

    private func kind(for type: HKWorkoutActivityType) -> WorkoutKind {
        switch type {
        case .running: return .running
        case .walking: return .walking
        case .hiking: return .hiking
        case .cycling: return .cycling
        case .swimming: return .swimming
        case .traditionalStrengthTraining, .functionalStrengthTraining: return .strength
        case .highIntensityIntervalTraining: return .hiit
        case .yoga, .mindAndBody: return .yoga
        case .elliptical: return .elliptical
        case .rowing: return .rowing
        default: return .other
        }
    }

    /// Last two weeks of workouts (any app that logs to HealthKit),
    /// newest first, with energy, distance, and average heart rate.
    private func recentWorkouts() async -> [WorkoutEntry] {
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let start = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
            let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(),
                                      predicate: predicate,
                                      limit: 8,
                                      sortDescriptors: [sort]) { _, results, _ in
                continuation.resume(returning: (results as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }

        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        var entries: [WorkoutEntry] = []
        for w in workouts {
            let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie())
            let km = w.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                .sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo))
                ?? w.statistics(for: HKQuantityType(.distanceCycling))?
                .sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo))
            let avgHR = await windowStatistic(.heartRate, unit: bpmUnit,
                                              options: .discreteAverage,
                                              start: w.startDate, end: w.endDate)
            entries.append(WorkoutEntry(kind: kind(for: w.workoutActivityType),
                                        start: w.startDate,
                                        minutes: w.duration / 60,
                                        kcal: kcal,
                                        km: km,
                                        avgHeartRate: avgHR))
        }
        return entries
    }

    // MARK: Mobility / gait

    private func mobilityReport() async -> MobilityReport {
        func percentLatest(_ id: HKQuantityTypeIdentifier) async -> Double? {
            await latestValue(type: HKQuantityType(id), unit: .percent()).map { $0 * 100 }
        }
        let speedUnit = HKUnit(from: "m/s")
        return MobilityReport(
            steadiness: await percentLatest(.appleWalkingSteadiness),
            asymmetry: await percentLatest(.walkingAsymmetryPercentage),
            doubleSupport: await percentLatest(.walkingDoubleSupportPercentage),
            stepLengthMeters: await latestValue(type: HKQuantityType(.walkingStepLength), unit: .meter()),
            stairAscentSpeed: await latestValue(type: HKQuantityType(.stairAscentSpeed), unit: speedUnit),
            stairDescentSpeed: await latestValue(type: HKQuantityType(.stairDescentSpeed), unit: speedUnit),
            sixMinuteWalkMeters: await latestValue(type: HKQuantityType(.sixMinuteWalkTestDistance), unit: .meter())
        )
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

    // MARK: Sleep report

    /// Full stage-level sleep analysis: last night's hypnogram, stage totals,
    /// efficiency, overnight vitals, and a 7-night trend. Works with any
    /// source that writes sleepAnalysis stages (Oura, Apple Watch, …).
    func sleepReport() async -> SleepReport? {
        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        guard let windowStart = cal.date(byAdding: .day, value: -8, to: startOfToday),
              let nightStart = cal.date(byAdding: .hour, value: -6, to: startOfToday) else {
            return nil
        }

        let all = await sleepSamples(from: windowStart)
        guard !all.isEmpty else { return nil }

        let lastNight = await buildNight(from: all.filter { $0.endDate > nightStart })
        let totals = nightlyTotals(from: all, calendar: cal, now: now)
        return SleepReport(lastNight: lastNight, recentTotals: totals)
    }

    private func sleepSamples(from start: Date) async -> [HKCategorySample] {
        await withCheckedContinuation { continuation in
            let type = HKCategoryType(.sleepAnalysis)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: type,
                                      predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [sort]) { _, results, _ in
                continuation.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
    }

    private func stage(forHKValue value: Int) -> SleepStage? {
        switch value {
        case HKCategoryValueSleepAnalysis.awake.rawValue:
            return .awake
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            return .rem
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
            return .deep
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
             HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
            return .light
        default:
            return nil // inBed handled separately
        }
    }

    private func buildNight(from samples: [HKCategorySample]) async -> SleepNight? {
        var stageIntervals: [SleepStage: [(Date, Date)]] = [:]
        var asleepIntervals: [(Date, Date)] = []
        var inBedIntervals: [(Date, Date)] = []
        var segments: [SleepStageSegment] = []

        for s in samples {
            if s.value == HKCategoryValueSleepAnalysis.inBed.rawValue {
                inBedIntervals.append((s.startDate, s.endDate))
                continue
            }
            guard let st = stage(forHKValue: s.value) else { continue }
            stageIntervals[st, default: []].append((s.startDate, s.endDate))
            if st != .awake { asleepIntervals.append((s.startDate, s.endDate)) }
            segments.append(SleepStageSegment(stage: st, start: s.startDate, end: s.endDate))
        }
        guard !asleepIntervals.isEmpty else { return nil }

        let allTracked = samples.map { ($0.startDate, $0.endDate) }
        let bedtime = allTracked.map(\.0).min()!
        let wakeTime = asleepIntervals.map(\.1).max()!

        var stageHours: [SleepStage: Double] = [:]
        for (st, intervals) in stageIntervals {
            stageHours[st] = unionHours(intervals)
        }
        let totalHours = unionHours(asleepIntervals)
        let inBedHours = inBedIntervals.isEmpty
            ? wakeTime.timeIntervalSince(bedtime) / 3600
            : unionHours(inBedIntervals)
        let efficiency = min(totalHours / max(inBedHours, 0.01), 1)

        segments.sort { $0.start < $1.start }
        if segments.count > 250 { segments = Array(segments.suffix(250)) }

        // Overnight vitals across the sleep window (Oura writes both).
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let lowestHR = await windowStatistic(.heartRate, unit: bpmUnit,
                                             options: .discreteMin,
                                             start: bedtime, end: wakeTime)
        let avgRR = await windowStatistic(.respiratoryRate, unit: bpmUnit,
                                          options: .discreteAverage,
                                          start: bedtime, end: wakeTime)

        return SleepNight(bedtime: bedtime,
                          wakeTime: wakeTime,
                          totalHours: totalHours,
                          stageHours: stageHours,
                          inBedHours: inBedHours,
                          efficiency: efficiency,
                          segments: segments,
                          lowestHeartRate: lowestHR,
                          averageRespiratoryRate: avgRR)
    }

    /// Sum of intervals with overlaps merged, in hours — so two sources
    /// logging the same night can never double-count.
    private func unionHours(_ intervals: [(Date, Date)]) -> Double {
        guard !intervals.isEmpty else { return 0 }
        let sorted = intervals.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var currentStart = sorted[0].0
        var currentEnd = sorted[0].1
        for (start, end) in sorted.dropFirst() {
            if start <= currentEnd {
                currentEnd = max(currentEnd, end)
            } else {
                total += currentEnd.timeIntervalSince(currentStart)
                currentStart = start
                currentEnd = end
            }
        }
        total += currentEnd.timeIntervalSince(currentStart)
        return total / 3600
    }

    /// Buckets asleep samples into nights (a sample belongs to the day you
    /// woke up) and returns the last 7 nights of totals, oldest first.
    private func nightlyTotals(from samples: [HKCategorySample],
                               calendar cal: Calendar, now: Date) -> [Double] {
        var buckets: [Date: [(Date, Date)]] = [:]
        for s in samples {
            guard let st = stage(forHKValue: s.value), st != .awake else { continue }
            // Shifting by +9h maps anything ending overnight or in the morning
            // onto the wake day.
            let key = cal.startOfDay(for: s.endDate.addingTimeInterval(9 * 3600))
            buckets[key, default: []].append((s.startDate, s.endDate))
        }
        let todayKey = cal.startOfDay(for: now.addingTimeInterval(9 * 3600))
        return (0..<7).reversed().map { daysAgo in
            guard let day = cal.date(byAdding: .day, value: -daysAgo, to: todayKey),
                  let intervals = buckets[day] else { return 0 }
            return unionHours(intervals)
        }
    }

    private func windowStatistic(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                                 options: HKStatisticsOptions,
                                 start: Date, end: Date) async -> Double? {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
            let query = HKStatisticsQuery(quantityType: HKQuantityType(id),
                                          quantitySamplePredicate: predicate,
                                          options: options) { _, stats, _ in
                let value: Double?
                if options.contains(.discreteMin) {
                    value = stats?.minimumQuantity()?.doubleValue(for: unit)
                } else if options.contains(.discreteAverage) {
                    value = stats?.averageQuantity()?.doubleValue(for: unit)
                } else {
                    value = nil
                }
                continuation.resume(returning: value)
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
