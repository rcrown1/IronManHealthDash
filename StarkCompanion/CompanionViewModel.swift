//
//  CompanionViewModel.swift
//  StarkCompanion — drives authorization, the sync loop, and UI state.
//

import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class CompanionViewModel {

    enum AuthState {
        case unknown, unavailable, requesting, granted, denied
    }

    private let health = HealthKitService()
    private let watchLink = WatchLinkReceiver()
    private var link: CompanionLink?
    private var syncTask: Task<Void, Never>?

    private(set) var authState: AuthState = .unknown
    private(set) var connectedTV: String?
    private(set) var lastPayload: TelemetryPayload?
    private(set) var lastSentAt: Date?
    private(set) var framesSent = 0

    // Live heart rate streamed from the Stark Sensor watch app.
    private(set) var watchHeartRate: Double?
    private(set) var watchHRAt: Date?
    private var watchSeries: [Double] = []
    private var lastMiniSendAt = Date.distantPast

    var watchIsLive: Bool {
        guard let at = watchHRAt else { return false }
        return Date().timeIntervalSince(at) < 20
    }

    var sourceName: String {
        UIDevice.current.name
    }

    func start() {
        guard syncTask == nil else { return }

        let link = CompanionLink()
        link.onStateChange = { [weak self] peerName in
            Task { @MainActor in
                self?.connectedTV = peerName
            }
        }
        link.start()
        self.link = link

        watchLink.onHeartRate = { [weak self] bpm in
            Task { @MainActor in
                self?.ingestWatchHeartRate(bpm)
            }
        }
        watchLink.activate()

        syncTask = Task { [weak self] in
            await self?.authorize()
            while !Task.isCancelled {
                await self?.syncOnce()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func authorize() async {
        guard health.isAvailable else {
            authState = .unavailable
            return
        }
        authState = .requesting
        do {
            try await health.requestAuthorization()
            authState = .granted
        } catch {
            authState = .denied
        }
    }

    private func syncOnce() async {
        guard authState == .granted else { return }
        var payload = await health.snapshot(sourceName: sourceName)

        // Watch readings are fresher than anything HealthKit has committed —
        // they win whenever the stream is live.
        if watchIsLive, let bpm = watchHeartRate, let at = watchHRAt {
            payload.samples.removeAll { $0.kind == .heartRate }
            payload.samples.append(MetricSample(kind: .heartRate, value: bpm, date: at))
            payload.heartRateSeries = watchSeries
        }

        lastPayload = payload
        if let link, link.isConnected {
            link.send(payload)
            framesSent += 1
            lastSentAt = Date()
        }
    }

    /// Each watch reading updates local state immediately and, at most every
    /// 2 seconds, pushes a heart-rate-only frame so the reactor pulse and
    /// EKG on the TV track the wearer beat-to-beat.
    private func ingestWatchHeartRate(_ bpm: Double) {
        watchHeartRate = bpm
        watchHRAt = Date()
        watchSeries.append(bpm)
        if watchSeries.count > 120 { watchSeries.removeFirst(watchSeries.count - 120) }

        let now = Date()
        guard let link, link.isConnected,
              now.timeIntervalSince(lastMiniSendAt) >= 2 else { return }
        lastMiniSendAt = now

        let mini = TelemetryPayload(
            samples: [MetricSample(kind: .heartRate, value: bpm, date: now)],
            heartRateSeries: watchSeries,
            sourceName: sourceName,
            sentAt: now)
        link.send(mini)
        framesSent += 1
        lastSentAt = now
    }
}
