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
                s(.sleepHours, 7.3),
                s(.mindfulMinutes, 12),
                s(.bodyMass, 84.1),
                s(.walkingSpeed, walkingSpeed),
            ],
            heartRateSeries: hrSeries,
            sourceName: "SIMULATION CORE",
            sentAt: now
        )
    }
}
