//
//  HUDLinkReceiver.swift
//  StarkHUD — advertises on the local network and receives telemetry
//  frames from the iPhone companion over Multipeer Connectivity.
//

import Foundation
import MultipeerConnectivity
import UIKit

final class HUDLinkReceiver: NSObject {

    private let store: MetricStore
    private let peerID: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!

    @MainActor
    init(store: MetricStore) {
        self.store = store
        self.peerID = MCPeerID(displayName: UIDevice.current.name)
        super.init()
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        advertiser = MCNearbyServiceAdvertiser(peer: peerID,
                                               discoveryInfo: nil,
                                               serviceType: StarkLink.serviceType)
        advertiser.delegate = self
    }

    func start() {
        advertiser.startAdvertisingPeer()
    }

    func stop() {
        advertiser.stopAdvertisingPeer()
        session.disconnect()
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension HUDLinkReceiver: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Any nearby companion is welcome in the workshop.
        invitationHandler(true, session)
    }
}

// MARK: - MCSessionDelegate

extension HUDLinkReceiver: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let store = self.store
        let name = peerID.displayName
        Task { @MainActor in
            switch state {
            case .connected:
                store.setLinkState(.connected(name))
            case .notConnected:
                store.setLinkState(.searching)
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let payload = try? TelemetryPayload.decode(data) else { return }
        let store = self.store
        Task { @MainActor in
            store.applyLive(payload)
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream,
                 withName streamName: String, fromPeer peerID: MCPeerID) {}

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {}

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
