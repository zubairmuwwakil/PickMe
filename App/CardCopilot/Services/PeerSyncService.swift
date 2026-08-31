import Foundation
@preconcurrency import MultipeerConnectivity
import Observation
import UIKit
import CardCopilotEngine
import CardCopilotStore

private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
}

/// Data payload exchanged between nearby devices via 100% offline Peer-to-Peer sync.
public struct PeerSyncPayload: Codable, Sendable {
    public let deviceName: String
    public let exportedAt: Date
    public let ownedCardIds: [String]
    public let customValuations: [String: ProgramValuation]
    public let merchantOverrides: [String: String]

    public init(
        deviceName: String,
        exportedAt: Date = Date(),
        ownedCardIds: [String],
        customValuations: [String: ProgramValuation] = [:],
        merchantOverrides: [String: String] = [:]
    ) {
        self.deviceName = deviceName
        self.exportedAt = exportedAt
        self.ownedCardIds = ownedCardIds
        self.customValuations = customValuations
        self.merchantOverrides = merchantOverrides
    }
}

/// A 100% offline, zero-cloud peer sync coordinator using Multipeer Connectivity / Wi-Fi Aware standards.
/// Allows two nearby Apple devices running PickMe to exchange wallet configurations without internet.
@Observable
@MainActor
public final class PeerSyncService: NSObject {
    public static let serviceType = "pickme-sync"

    public var isAdvertising = false
    public var isBrowsing = false
    public var discoveredPeers: [MCPeerID] = []
    public var connectedPeers: [MCPeerID] = []
    public var lastReceivedPayload: PeerSyncPayload?
    public var lastSyncDate: Date?
    public var statusMessage: String = "Offline P2P Ready"

    private let myPeerId: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    public override init() {
        let name = UIDevice.current.name
        self.myPeerId = MCPeerID(displayName: name)
        super.init()
    }

    public func start() {
        stop()

        let sess = MCSession(peer: myPeerId, securityIdentity: nil, encryptionPreference: .required)
        self.session = sess
        sess.delegate = self

        let adv = MCNearbyServiceAdvertiser(peer: myPeerId, discoveryInfo: nil, serviceType: Self.serviceType)
        self.advertiser = adv
        adv.delegate = self
        adv.startAdvertisingPeer()
        isAdvertising = true

        let brw = MCNearbyServiceBrowser(peer: myPeerId, serviceType: Self.serviceType)
        self.browser = brw
        brw.delegate = self
        brw.startBrowsingForPeers()
        isBrowsing = true

        statusMessage = "Discovering nearby PickMe devices..."
    }

    public func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        isAdvertising = false

        browser?.stopBrowsingForPeers()
        browser = nil
        isBrowsing = false

        session?.disconnect()
        session = nil
        connectedPeers.removeAll()
        discoveredPeers.removeAll()
        statusMessage = "Offline P2P Stopped"
    }

    public func invitePeer(_ peer: MCPeerID) {
        guard let browser, let session else { return }
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 30)
        statusMessage = "Connecting to \(peer.displayName)..."
    }

    public func exportCurrentPayload() -> PeerSyncPayload {
        let ownerStore = OwnerStateLocalStore()
        let wallet = ownerStore.loadUserWallet()
        let ownedIds = wallet?.ownedCardIds ?? []

        return PeerSyncPayload(
            deviceName: myPeerId.displayName,
            ownedCardIds: ownedIds,
            customValuations: wallet?.valuationsCad.programs ?? [:]
        )
    }

    public func sendCurrentWallet(to peer: MCPeerID) throws {
        guard let session else { return }
        let payload = exportCurrentPayload()
        let data = try JSONEncoder().encode(payload)
        try session.send(data, toPeers: [peer], with: .reliable)
        statusMessage = "Sent wallet data to \(peer.displayName)"
    }

    public func applyReceivedPayload(_ payload: PeerSyncPayload) {
        let ownerStore = OwnerStateLocalStore()
        guard var current = ownerStore.loadUserWallet() else {
            statusMessage = "Set up a wallet before receiving nearby cards"
            return
        }

        // Merge owned card IDs (union)
        var mergedCards = Set(current.ownedCardIds)
        for id in payload.ownedCardIds {
            mergedCards.insert(id)
        }
        current.ownedCardIds = Array(mergedCards)

        // Merge custom reward-program valuations
        for (programId, valuation) in payload.customValuations {
            current.valuationsCad.programs[programId] = valuation
        }

        try? ownerStore.save(current)
        lastReceivedPayload = payload
        lastSyncDate = Date()
        statusMessage = "Merged \(payload.ownedCardIds.count) cards from \(payload.deviceName)"
    }
}

// MARK: - MCSessionDelegate
extension PeerSyncService: MCSessionDelegate {
    public nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
                self.statusMessage = "Connected to \(peerID.displayName)"
                // Auto-send our current payload upon connection
                try? self.sendCurrentWallet(to: peerID)
            case .connecting:
                self.statusMessage = "Connecting to \(peerID.displayName)..."
            case .notConnected:
                self.connectedPeers.removeAll { $0 == peerID }
                self.statusMessage = "\(peerID.displayName) disconnected"
            @unknown default:
                break
            }
        }
    }

    public nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            if let payload = try? JSONDecoder().decode(PeerSyncPayload.self, from: data) {
                self.applyReceivedPayload(payload)
            }
        }
    }

    public nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension PeerSyncService: MCNearbyServiceAdvertiserDelegate {
    public nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let invitation = UncheckedSendableBox(value: invitationHandler)
        let peerName = peerID.displayName
        Task { @MainActor in
            // Auto-accept local PickMe sync invitations
            invitation.value(true, self.session)
            self.statusMessage = "Accepted invitation from \(peerName)"
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension PeerSyncService: MCNearbyServiceBrowserDelegate {
    public nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        Task { @MainActor in
            if peerID != self.myPeerId && !self.discoveredPeers.contains(peerID) {
                self.discoveredPeers.append(peerID)
            }
        }
    }

    public nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.discoveredPeers.removeAll { $0 == peerID }
        }
    }
}
