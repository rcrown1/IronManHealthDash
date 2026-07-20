//
//  HeartRateStreamer.swift
//  StarkSensor — runs a workout session so the Watch samples heart rate
//  continuously (~1/sec), and streams each reading to the iPhone.
//

import Foundation
import HealthKit
import Observation
import WatchConnectivity

@MainActor
@Observable
final class HeartRateStreamer: NSObject {

    enum State: Equatable {
        case idle, requesting, streaming, denied, failed(String)
    }

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private(set) var state: State = .idle
    private(set) var heartRate: Double = 0
    private(set) var phoneReachable = false
    private(set) var samplesSent = 0

    private var lastSendAt = Date.distantPast

    var isStreaming: Bool { state == .streaming }

    // MARK: Phone link

    func activatePhoneLink() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: Streaming control

    func start() async {
        state = .requesting
        do {
            // Sharing workoutType is required to drive a live workout builder;
            // heart rate is the only thing we read.
            try await healthStore.requestAuthorization(
                toShare: [HKObjectType.workoutType()],
                read: [HKQuantityType(.heartRate)])
        } catch {
            state = .denied
            return
        }

        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore,
                                                         workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            workoutSession = session
            self.builder = builder

            session.startActivity(with: Date())
            try await builder.beginCollection(at: Date())
            state = .streaming
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        workoutSession?.end()
        builder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            Task { @MainActor in
                // The session exists only to keep the sensor hot; nothing to save.
                self?.builder?.discardWorkout()
                self?.builder = nil
                self?.workoutSession = nil
            }
        }
        state = .idle
    }

    // MARK: Forwarding

    private func ingest(_ bpm: Double) {
        heartRate = bpm
        let now = Date()
        guard now.timeIntervalSince(lastSendAt) >= 1.0 else { return }
        lastSendAt = now

        let message: [String: Any] = ["hr": bpm, "t": now.timeIntervalSince1970]
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil)
            samplesSent += 1
        } else {
            // Best-effort fallback; delivered when the phone wakes.
            try? session.updateApplicationContext(message)
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension HeartRateStreamer: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: Error) {
        let text = error.localizedDescription
        Task { @MainActor in self.state = .failed(text) }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension HeartRateStreamer: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hrType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hrType),
              let stats = workoutBuilder.statistics(for: hrType),
              let quantity = stats.mostRecentQuantity() else { return }
        let bpm = quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        Task { @MainActor in self.ingest(bpm) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

// MARK: - WCSessionDelegate

extension HeartRateStreamer: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let reachable = session.isReachable
        Task { @MainActor in self.phoneReachable = reachable }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.phoneReachable = reachable }
    }
}
