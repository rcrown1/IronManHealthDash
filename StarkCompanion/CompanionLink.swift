//
//  CompanionLink.swift
//  StarkCompanion — finds the Apple TV on the local network and streams
//  telemetry frames to it over Multipeer Connectivity.
//

import Foundation
import MultipeerConnectivity
import UIKit

final class CompanionLink: NSObject {

    /// Called with the connected peer's display name, or nil when disconnected.
    var onStateChange: ((String?) -> Void)?

    private let peerID: MCPeerID
    private var session: MCSession!
    private var browser: MCNearbyServiceBrowser!

    @MainActor
    override init() {
        self.peerID = MCPeerID(displayName: UIDevice.current.name)
        super.init()
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: StarkLink.serviceType)
        browser.delegate = self
    }

    func start() {
        browser.startBrowsingForPeers()
    }

    func stop() {
        browser.stopBrowsingForPeers()
        session.disconnect()
    }

    var isConnected: Bool { !session.connectedPeers.isEmpty }

    func send(_ payload: TelemetryPayload) {
        guard !session.connectedPeers.isEmpty else { return }
        guard let data = try? payload.encoded() else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension CompanionLink: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}

// MARK: - MCSessionDelegate

extension CompanionLink: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            onStateChange?(peerID.displayName)
        case .notConnected:
            onStateChange?(nil)
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didReceive stream: InputStream,
                 withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {}

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
