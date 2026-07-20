//
//  WatchLinkReceiver.swift
//  StarkCompanion — receives live heart-rate readings streamed from the
//  Stark Sensor watch app over WatchConnectivity.
//

import Foundation
import WatchConnectivity

final class WatchLinkReceiver: NSObject {

    /// Called with each live BPM reading from the watch.
    var onHeartRate: ((Double) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func handle(_ message: [String: Any]) {
        guard let bpm = message["hr"] as? Double else { return }
        onHeartRate?(bpm)
    }
}

extension WatchLinkReceiver: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(applicationContext)
    }
}
