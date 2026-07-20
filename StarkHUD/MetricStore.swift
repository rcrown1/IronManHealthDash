//
//  MetricStore.swift
//  StarkHUD — single source of truth for everything the HUD renders.
//

import Foundation
import Observation

@MainActor
@Observable
final class MetricStore {

    enum LinkState: Equatable {
        case searching
        case connected(String)
    }

    enum Mode: Equatable {
        case simulation
        case live
    }

    private(set) var latest: [MetricKind: MetricSample] = [:]
    private(set) var history: [MetricKind: [Double]] = [:]
    private(set) var heartRateSeries: [Double] = []
    private(set) var linkState: LinkState = .searching
    private(set) var mode: Mode = .simulation
    private(set) var sourceName: String = "SIMULATION CORE"
    private(set) var lastLiveAt: Date?

    // Kept separately so simulated data is never presented as real data.
    private var liveSleepReport: SleepReport?
    private var demoSleepReport: SleepReport?
    private var liveWorkouts: [WorkoutEntry]?
    private var demoWorkouts: [WorkoutEntry]?
    private var liveMobility: MobilityReport?
    private var demoMobility: MobilityReport?

    var sleepReport: SleepReport? {
        mode == .live ? liveSleepReport : demoSleepReport
    }

    var workouts: [WorkoutEntry] {
        (mode == .live ? liveWorkouts : demoWorkouts) ?? []
    }

    var mobility: MobilityReport? {
        mode == .live ? liveMobility : demoMobility
    }

    /// Daily goals used by the power-systems rings.
    let energyGoal: Double = 600
    let exerciseGoal: Double = 30
    let standGoal: Double = 12

    var bpm: Double { latest[.heartRate]?.value ?? 0 }

    func sample(_ kind: MetricKind) -> MetricSample? { latest[kind] }

    func value(_ kind: MetricKind) -> Double { latest[kind]?.value ?? 0 }

    func sparkline(_ kind: MetricKind) -> [Double] { history[kind] ?? [] }

    // MARK: Ingest

    /// Telemetry from the phone always wins.
    func applyLive(_ payload: TelemetryPayload) {
        lastLiveAt = Date()
        mode = .live
        if let sleep = payload.sleep { liveSleepReport = sleep }
        if let workouts = payload.workouts { liveWorkouts = workouts }
        if let mobility = payload.mobility { liveMobility = mobility }
        apply(payload)
    }

    /// Simulation frames only land while no live uplink has spoken recently.
    func applyDemo(_ payload: TelemetryPayload) {
        if let t = lastLiveAt, Date().timeIntervalSince(t) < 30 { return }
        mode = .simulation
        if let sleep = payload.sleep { demoSleepReport = sleep }
        if let workouts = payload.workouts { demoWorkouts = workouts }
        if let mobility = payload.mobility { demoMobility = mobility }
        apply(payload)
    }

    func setLinkState(_ state: LinkState) {
        linkState = state
        if state == .searching, mode == .live {
            // Uplink dropped; simulation takes back over after the grace period.
        }
    }

    private func apply(_ payload: TelemetryPayload) {
        sourceName = payload.sourceName
        for s in payload.samples {
            latest[s.kind] = s
            var h = history[s.kind] ?? []
            h.append(s.value)
            if h.count > 60 { h.removeFirst(h.count - 60) }
            history[s.kind] = h
        }
        if !payload.heartRateSeries.isEmpty {
            heartRateSeries = payload.heartRateSeries
        }
    }
}
