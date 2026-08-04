import Foundation
import MultipeerConnectivity

enum LocalMatchMode: String, Codable, CaseIterable, Identifiable {
    case cooperative
    case versus

    var id: Self { self }
    var label: String {
        switch self {
        case .cooperative: "Cooperativo"
        case .versus: "Versus"
        }
    }
}

struct LocalMatchPacket: Codable {
    enum Kind: String, Codable {
        case hello
        case state
        case laser
        case hit
        case start
        case controllerInput
    }

    var kind: Kind
    var peerID: String
    var mode: LocalMatchMode?
    var position: SIMD3<Float>?
    var yaw: Float?
    var pitch: Float?
    var tool: Int?
    var timestamp: TimeInterval
    var joystickX: Float?
    var joystickY: Float?
    var jumpPressed: Bool?
    var role: String?
    var health: Float?
    var score: Int?
}

enum LocalDeviceRole: String, Codable, CaseIterable, Identifiable {
    case full3DRender = "3DRender"
    case remoteController = "RemoteController"

    var id: Self { self }
    var label: String {
        switch self {
        case .full3DRender: "Renderizado 3D Completo"
        case .remoteController: "Control Remoto Táctico (Segunda Pantalla)"
        }
    }
}

@MainActor
final class LocalMultiplayerSession: NSObject, ObservableObject {
    @Published private(set) var isHosting = false
    @Published private(set) var isConnected = false
    @Published private(set) var peers: [MCPeerID] = []
    @Published var mode: LocalMatchMode = .versus
    @Published var role: LocalDeviceRole = .full3DRender
    @Published private(set) var lastError: String?

    private let serviceType = "salon-laser"
    private let localPeer: MCPeerID
    private let session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    override init() {
        let name = UIDevice.current.name.isEmpty ? "Jugador" : UIDevice.current.name
        localPeer = MCPeerID(displayName: String(name.prefix(32)))
        session = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    func host() {
        stopDiscovery()
        isHosting = true
        advertiser = MCNearbyServiceAdvertiser(
            peer: localPeer,
            discoveryInfo: ["mode": mode.rawValue],
            serviceType: serviceType
        )
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
    }

    func join() {
        stopDiscovery()
        isHosting = false
        browser = MCNearbyServiceBrowser(peer: localPeer, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }

    func stop() {
        stopDiscovery()
        session.disconnect()
        peers = []
        isConnected = false
    }

    func send(_ packet: LocalMatchPacket) {
        guard !session.connectedPeers.isEmpty,
              let data = try? JSONEncoder().encode(packet) else { return }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func stopDiscovery() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        advertiser = nil
        browser = nil
    }
}

extension LocalMultiplayerSession: MCSessionDelegate {
    nonisolated func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        Task { @MainActor in
            self.peers = session.connectedPeers
            self.isConnected = !session.connectedPeers.isEmpty
        }
    }

    nonisolated func session(
        _ session: MCSession,
        didReceive data: Data,
        fromPeer peerID: MCPeerID
    ) {
        // Gameplay packets will be routed into GameModel in the next step.
        _ = data
        _ = peerID
    }

    nonisolated func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {}
}

extension LocalMultiplayerSession: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        invitationHandler(true, session)
    }

    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        Task { @MainActor in self.lastError = error.localizedDescription }
    }
}

extension LocalMultiplayerSession: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
    }

    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        lostPeer peerID: MCPeerID
    ) {}

    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error
    ) {
        Task { @MainActor in self.lastError = error.localizedDescription }
    }
}
