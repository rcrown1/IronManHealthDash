//
//  DemoDataEngine.swift
//  StarkHUD — generates plausible, coherent vitals whenever no iPhone
//  uplink is active, so the workshop display is never dark.
//

import Foundation

@MainActor
final class DemoDataEngine {

    private let store: MetricStore
    private var task: Task<Void, Never>?

    // Simulated physiological state.
    private var heartRate: Double = 64
    private var hrTarget: Double = 64
    private var burstSecondsRemaining: Int = 0
    private var secondsUntilNextBurst: Int = 45
    private var hrv: Double = 52
    private var spo2: Double = 98
    private var respiratory: Double = 14.5
    private var steps: Double
    private var activeEnergy: Double
    private var exerciseMinutes: Double
    private var flights: Double
    private var walkingSpeed: Double = 4.6
    private var hrSeries: [Double] = []
    private let demoSleep: SleepReport = DemoDataEngine.makeDemoSleep()
    private let demoWorkouts: [WorkoutEntry] = DemoDataEngine.makeDemoWorkouts()
    private let demoMobility = MobilityReport(steadiness: 81,
                                              asymmetry: 2.7,
                                              doubleSupport: 27.4,
                                              stepLengthMeters: 0.74,
                                              stairAscentSpeed: 0.63,
                                              stairDescentSpeed: 0.74,
                                              sixMinuteWalkMeters: 545)

    init(store: MetricStore) {
        self.store = store
        // Seed cumulative metrics proportionally to how far into the day we are,
        // so the simulation looks like a real day in progress.
        let hour = Double(Calendar.current.component(.hour, from: Date()))
        let dayFraction = min(1, max(0.05, (hour - 6) / 16))
        steps = (8200 * dayFraction).rounded()
        activeEnergy = (540 * dayFraction).rounded()
        exerciseMinutes = (34 * dayFraction).rounded()
        flights = (9 * dayFraction).rounded()
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func tick() {
        advancePhysiology()
        store.applyDemo(makePayload())
    }

    private func advancePhysiology() {
        // Occasionally simulate a bout of activity — Tony pacing the workshop.
        if burstSecondsRemaining > 0 {
            burstSecondsRemaining -= 1
            if burstSecondsRemaining == 0 {
                hrTarget = Double.random(in: 60...70)
                secondsUntilNextBurst = Int.random(in: 60...150)
            }
        } else {
            secondsUntilNextBurst -= 1
            if secondsUntilNextBurst <= 0 {
                burstSecondsRemaining = Int.random(in: 25...70)
                hrTarget = Double.random(in: 95...132)
            }
        }

        // Heart rate chases its target with jitter.
        heartRate += (hrTarget - heartRate) * 0.08 + Double.random(in: -1.4...1.4)
        heartRate = min(max(heartRate, 48), 178)
        hrSeries.append(heartRate)
        if hrSeries.count > 90 { hrSeries.removeFirst(hrSeries.count - 90) }

        let active = burstSecondsRemaining > 0

        // Correlated vitals.
        hrv += Double.random(in: -1.2...1.2) - (active ? 0.35 : -0.15)
        hrv = min(max(hrv, 18), 96)
        spo2 += Double.random(in: -0.15...0.15)
        spo2 = min(max(spo2, 94.5), 100)
        respiratory += (active ? 0.12 : -0.05) + Double.random(in: -0.2...0.2)
        respiratory = min(max(respiratory, 11), 26)
        walkingSpeed += Double.random(in: -0.05...0.05)
        walkingSpeed = min(max(walkingSpeed, 3.8), 5.6)

        // Cumulative counters.
        steps += active ? Double(Int.random(in: 18...32)) : Double(Int.random(in: 0...2))
        activeEnergy += heartRate * 0.0011
        if active { exerciseMinutes += 1.0 / 60.0 }
        if active, Int.random(in: 0..<220) == 0 { flights += 1 }
    }

    private func makePayload() -> TelemetryPayload {
        let hour = Double(Calendar.current.component(.hour, from: Date()))
        let standHours = min(12, max(1, hour - 7))
        let now = Date()

        func s(_ kind: MetricKind, _ value: Double) -> MetricSample {
            MetricSample(kind: kind, value: value, date: now)
        }

        return TelemetryPayload(
            samples: [
                s(.heartRate, heartRate.rounded()),
                s(.restingHeartRate, 57),
                s(.heartRateVariability, hrv.rounded()),
                s(.bloodOxygen, spo2),
                s(.respiratoryRate, respiratory.rounded()),
                s(.vo2Max, 41.2),
                s(.steps, steps),
                s(.activeEnergy, activeEnergy.rounded()),
                s(.exerciseMinutes, exerciseMinutes.rounded(.down)),
                s(.standHours, standHours),
                s(.distanceWalkingRunning, steps * 0.00074),
                s(.flightsClimbed, flights),
                s(.sleepHours, demoSleep.lastNight?.totalHours ?? 7.3),
                s(.mindfulMinutes, 12),
                s(.bodyMass, 84.1),
                s(.walkingSpeed, walkingSpeed),
            ],
            heartRateSeries: hrSeries,
            sourceName: "SIMULATION CORE",
            sentAt: now,
            sleep: demoSleep,
            workouts: demoWorkouts,
            mobility: demoMobility
        )
    }

    private static func makeDemoWorkouts() -> [WorkoutEntry] {
        let today = Calendar.current.startOfDay(for: Date())
        func entry(_ daysAgo: Int, _ hour: Double, _ kind: WorkoutKind, _ minutes: Double,
                   _ kcal: Double, _ km: Double?, _ avgHR: Double) -> WorkoutEntry {
            WorkoutEntry(kind: kind,
                         start: today.addingTimeInterval(Double(-daysAgo) * 86400 + hour * 3600),
                         minutes: minutes, kcal: kcal, km: km, avgHeartRate: avgHR)
        }
        return [
            entry(0, 7.5, .strength, 42, 384, nil, 128),
            entry(1, 18.2, .running, 31, 348, 5.2, 152),
            entry(2, 7.4, .hiit, 24, 296, nil, 158),
            entry(3, 12.2, .walking, 48, 212, 3.9, 104),
            entry(5, 17.8, .cycling, 55, 502, 18.4, 141),
            entry(6, 8.1, .yoga, 30, 96, nil, 84),
        ]
    }

    // MARK: Simulated night

    /// A plausible night built from ~90-minute cycles: deep sleep front-loaded,
    /// REM stretching out toward morning, brief awakenings in between.
    private static func makeDemoSleep() -> SleepReport {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let bedtime = today.addingTimeInterval(-38 * 60) // 23:22 last night

        let pattern: [(SleepStage, Double)] = [
            (.light, 22), (.deep, 46), (.light, 14), (.rem, 16),
            (.awake, 3),
            (.light, 26), (.deep, 38), (.light, 16), (.rem, 24),
            (.light, 30), (.deep, 20), (.rem, 28),
            (.awake, 5),
            (.light, 34), (.rem, 36), (.light, 24),
        ]

        var segments: [SleepStageSegment] = []
        var cursor = bedtime
        for (stage, minutes) in pattern {
            let end = cursor.addingTimeInterval(minutes * 60)
            segments.append(SleepStageSegment(stage: stage, start: cursor, end: end))
            cursor = end
        }
        let wakeTime = cursor

        var stageHours: [SleepStage: Double] = [:]
        for seg in segments {
            stageHours[seg.stage, default: 0] += seg.hours
        }
        let totalHours = segments.filter { $0.stage != .awake }.reduce(0) { $0 + $1.hours }
        let inBedHours = wakeTime.timeIntervalSince(bedtime) / 3600

        let night = SleepNight(bedtime: bedtime,
                               wakeTime: wakeTime,
                               totalHours: totalHours,
                               stageHours: stageHours,
                               inBedHours: inBedHours,
                               efficiency: totalHours / inBedHours,
                               segments: segments,
                               lowestHeartRate: 49,
                               averageRespiratoryRate: 13.4)

        return SleepReport(lastNight: night,
                           recentTotals: [7.1, 6.4, 7.8, 6.9, 8.2, 7.0, totalHours])
    }
}
