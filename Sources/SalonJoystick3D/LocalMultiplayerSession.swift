import Foundation
import MultipeerConnectivity
import UIKit

enum LocalMatchMode: String, Codable, CaseIterable, Identifiable {
    case cooperative
    case versus
    case lightBattle

    var id: Self { self }
    var label: String {
        switch self {
        case .cooperative: "Cooperativo"
        case .versus: "Versus 1v1"
        case .lightBattle: "Duelo de Luces"
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
        case enemySync
        case enemyHit
        case botDamage
        case scoreAward
        case lightSync
        case reviveTeammate
        case teamDefeat
        case teamRestart
        case slowMotion
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
    var isSlowMotion: Bool?

    // Sincronización autoritativa de enemigos (Host -> Cliente)
    var enemyPositions: [SIMD3<Float>]?
    var enemyHealths: [Float]?
    var wave: Int?
    var botsRemaining: Int?
    var totalBots: Int?
    var isIntermission: Bool?
    var intermissionTime: Float?
    var botLaserStarts: [SIMD3<Float>]?
    var botLaserEnds: [SIMD3<Float>]?

    // Daño colaborativo a enemigos (Cliente -> Host)
    var hitEnemyIndex: Int?
    var hitDamage: Float?

    // Cámara de Recuperación Cooperativa
    var isRecovering: Bool?
    var recoveryProgress: Float?

    // Marcador y rondas para Modo Versus
    var versusRound: Int?
    var versusLocalWins: Int?
    var versusRemoteWins: Int?

    // Capa de Escudo / Poción estilo Fortnite / Hongos Free Fire
    var shield: Float?

    // Contador de bajas / muertes en cooperativo
    var coopDeaths: Int?

    // Sincronización de luces en tiempo real
    var lightStates: GameLightStates?

    // Duelo de Luces (Luz vs Oscuridad / Captura de Bandera)
    var lightScore: Int?
    var shadowScore: Int?
    var hasCore: Bool?
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
    @Published private(set) var isSearching = false
    @Published private(set) var isConnected = false
    @Published private(set) var peers: [MCPeerID] = []
    @Published private(set) var discoveredPeers: [MCPeerID] = []
    @Published private(set) var statusMessage: String = "Listo para enlazar"
    @Published var mode: LocalMatchMode = .cooperative
    @Published var role: LocalDeviceRole = .full3DRender
    @Published private(set) var lastError: String?

    var onPacketReceived: ((LocalMatchPacket) -> Void)?
    var onConnected: (() -> Void)?

    private let serviceType = "salon-laser"
    let localPeer: MCPeerID
    private var session: MCSession
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    override init() {
        // Generar nombre único por modelo de iPhone + tag corto (en iOS 16+ UIDevice.current.name siempre devuelve "iPhone")
        let tagKey = "salon_mp_unique_tag"
        let savedTag = UserDefaults.standard.string(forKey: tagKey)
        let tag: String
        if let savedTag, !savedTag.isEmpty {
            tag = savedTag
        } else {
            let newTag = String(UUID().uuidString.prefix(4)).uppercased()
            UserDefaults.standard.set(newTag, forKey: tagKey)
            tag = newTag
        }

        let modelName = Self.detectDeviceModelName()
        let uniqueDisplay = "\(modelName) #\(tag)"
        self.localPeer = MCPeerID(displayName: String(uniqueDisplay.prefix(32)))
        self.session = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .none)
        super.init()
        self.session.delegate = self
    }

    static func detectDeviceModelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { id, element in
            guard let value = element.value as? Int8, value != 0 else { return id }
            return id + String(UnicodeScalar(UInt8(value)))
        }
        switch identifier {
        case "iPhone16,2": return "iPhone 15 Pro Max"
        case "iPhone16,1": return "iPhone 15 Pro"
        case "iPhone15,2": return "iPhone 14 Pro"
        case "iPhone15,3": return "iPhone 14 Pro Max"
        case "iPhone17,1": return "iPhone 16 Pro"
        case "iPhone17,2": return "iPhone 16 Pro Max"
        default:
            if identifier.hasPrefix("iPad") { return "iPad" }
            return "iPhone"
        }
    }

    func host() {
        stopDiscovery()
        lastError = nil
        isHosting = true
        isSearching = false
        statusMessage = "Sala creada por \(localPeer.displayName). Esperando jugador..."

        let adv = MCNearbyServiceAdvertiser(
            peer: localPeer,
            discoveryInfo: ["mode": mode.rawValue],
            serviceType: serviceType
        )
        adv.delegate = self
        adv.startAdvertisingPeer()
        self.advertiser = adv

        // También activar navegador en segundo plano para acelerar el descubrimiento mutuo
        let brw = MCNearbyServiceBrowser(peer: localPeer, serviceType: serviceType)
        brw.delegate = self
        brw.startBrowsingForPeers()
        self.browser = brw
    }

    func join() {
        stopDiscovery()
        lastError = nil
        isHosting = false
        isSearching = true
        discoveredPeers = []
        statusMessage = "Buscando salas cercanas de Laser Tracer..."

        let brw = MCNearbyServiceBrowser(peer: localPeer, serviceType: serviceType)
        brw.delegate = self
        brw.startBrowsingForPeers()
        self.browser = brw

        // También anunciar presencia para que el Host nos vea de inmediato
        let adv = MCNearbyServiceAdvertiser(
            peer: localPeer,
            discoveryInfo: ["mode": mode.rawValue],
            serviceType: serviceType
        )
        adv.delegate = self
        adv.startAdvertisingPeer()
        self.advertiser = adv
    }

    func invitePeer(_ peer: MCPeerID) {
        statusMessage = "Conectando con \(peer.displayName)..."
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 15)
    }

    func stop() {
        stopDiscovery()
        session.disconnect()
        peers = []
        discoveredPeers = []
        isConnected = false
        isHosting = false
        isSearching = false
        statusMessage = "Desconectado"
    }

    func send(_ packet: LocalMatchPacket) {
        guard !session.connectedPeers.isEmpty,
              let data = try? JSONEncoder().encode(packet) else { return }
        let mode: MCSessionSendDataMode = (packet.kind == .state || packet.kind == .controllerInput || packet.kind == .enemySync) ? .unreliable : .reliable
        do {
            try session.send(data, toPeers: session.connectedPeers, with: mode)
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
            let connectedNow = !session.connectedPeers.isEmpty
            let wasConnected = self.isConnected
            self.isConnected = connectedNow

            switch state {
            case .connected:
                self.statusMessage = "¡Enlazado con \(peerID.displayName)!"
                self.isHosting = false
                self.isSearching = false
                self.stopDiscovery()
                if !wasConnected && connectedNow {
                    self.onConnected?()
                }
            case .connecting:
                self.statusMessage = "Enlazando con \(peerID.displayName)..."
            case .notConnected:
                if session.connectedPeers.isEmpty {
                    self.statusMessage = "Jugador desconectado"
                }
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(
        _ session: MCSession,
        didReceive data: Data,
        fromPeer peerID: MCPeerID
    ) {
        guard let packet = try? JSONDecoder().decode(LocalMatchPacket.self, from: data) else { return }
        Task { @MainActor in
            self.onPacketReceived?(packet)
        }
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
        Task { @MainActor in
            self.statusMessage = "Aceptando invitación de \(peerID.displayName)..."
            invitationHandler(true, self.session)
        }
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
        Task { @MainActor in
            guard peerID.displayName != self.localPeer.displayName else { return }
            if !self.discoveredPeers.contains(peerID) {
                self.discoveredPeers.append(peerID)
            }
            self.statusMessage = "Sala encontrada: \(peerID.displayName). Enlazando..."
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 15)
        }
    }

    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        lostPeer peerID: MCPeerID
    ) {
        Task { @MainActor in
            self.discoveredPeers.removeAll { $0 == peerID }
        }
    }

    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error
    ) {
        Task { @MainActor in self.lastError = error.localizedDescription }
    }
}
