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
    private var link: CompanionLink?
    private var syncTask: Task<Void, Never>?

    private(set) var authState: AuthState = .unknown
    private(set) var connectedTV: String?
    private(set) var lastPayload: TelemetryPayload?
    private(set) var lastSentAt: Date?
    private(set) var framesSent = 0

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
        let payload = await health.snapshot(sourceName: sourceName)
        lastPayload = payload
        if let link, link.isConnected {
            link.send(payload)
            framesSent += 1
            lastSentAt = Date()
        }
    }
}
