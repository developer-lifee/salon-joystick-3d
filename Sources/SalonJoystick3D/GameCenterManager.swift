import Foundation
import GameKit
import SwiftUI

@MainActor
extension UIApplication {
    static var topViewController: UIViewController? {
        let scenes = shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.first(where: { $0.activationState == .foregroundActive })?.windows.first(where: { $0.isKeyWindow })
            ?? scenes.first?.windows.first(where: { $0.isKeyWindow })
            ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

@MainActor
final class GameCenterManager: NSObject, ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var localPlayerAlias = "No autenticado"
    @Published private(set) var isInMatch = false
    @Published private(set) var connectedPlayerNames: [String] = []
    @Published var lastError: String?
    @Published var showsMatchmakerSheet = false
    @Published var achievements: [GameAchievement] = GameCenterManager.defaultAchievements

    private(set) var activeMatch: GKMatch?

    var onPacketReceived: ((LocalMatchPacket) -> Void)?
    var onMatchStarted: (() -> Void)?
    var onAchievementUnlocked: ((GameAchievement) -> Void)?

    static let defaultAchievements: [GameAchievement] = [
        GameAchievement(
            id: "achievement_mirror_kill",
            title: "Reflejo Mortal",
            description: "Elimina a un enemigo devolviéndole su propio rayo con el Escudo Espejo.",
            icon: "shield.righthalf.filled",
            points: 15
        ),
        GameAchievement(
            id: "achievement_coop_revive",
            title: "Paramédico de Combate",
            description: "Revive a un compañero caído inflando su plasta con la Bomba de Aire.",
            icon: "wind",
            points: 20
        ),
        GameAchievement(
            id: "achievement_water_slide",
            title: "Acrobacia Acuática",
            description: "Lánzate a toda velocidad por el gran tobogán de 5.6m y cae de lleno a la piscina.",
            icon: "figure.pool.swim",
            points: 10
        ),
        GameAchievement(
            id: "achievement_mirror_world",
            title: "Al Otro Lado del Espejo",
            description: "Alcanza 3,000 puntos y cruza el portal líquido hacia el Gran Salón Arcoíris.",
            icon: "sparkles",
            points: 25
        ),
        GameAchievement(
            id: "achievement_colossus_defeat",
            title: "Cazador de Sombras",
            description: "Sobrevive a las oleadas y destruye al Gólem Colosal de Vantablack.",
            icon: "crown.fill",
            points: 30
        ),
        GameAchievement(
            id: "achievement_deep_dive",
            title: "Explorador Abisal",
            description: "Bucea en la fosa profunda de la piscina (-11 m) y alcanza el reino sumergido.",
            icon: "arrow.down.to.line.compact",
            points: 15
        ),
        GameAchievement(
            id: "achievement_efficient_battery",
            title: "Batería Eficiente",
            description: "Consigue una racha de 3 bajas con el láser antes de que la batería se agote.",
            icon: "bolt.batteryblock.fill",
            points: 20
        ),
        GameAchievement(
            id: "achievement_lumina_rescued",
            title: "Salvador de Lumina",
            description: "Supera la Oleada 15, rescata a Lumina y completa la campaña al 100%.",
            icon: "crown.fill",
            points: 100
        ),
        GameAchievement(
            id: "achievement_quantum_puzzle",
            title: "Maestro de la Refracción",
            description: "Alinea un haz continuo de fotones entre espejos para activar el receptor del Chrono-Core.",
            icon: "clock.arrow.circlepath",
            points: 35
        ),
        GameAchievement(
            id: "achievement_drone_deflection",
            title: "Desvío Estratosférico",
            description: "Inclina el Escudo Espejo hacia el cielo y pulveriza a un Drone Centinela con su propio láser aéreo.",
            icon: "airplane.departure",
            points: 25
        ),
        GameAchievement(
            id: "achievement_photonic_overcharge",
            title: "Saturación Fotónica Suprema",
            description: "Mantén activas las 4 luminarias del santuario al 100% durante una oleada avanzada (Oleada 10+).",
            icon: "lightbulb.max.fill",
            points: 30
        )
    ]

    override init() {
        super.init()
        loadAchievements()
        configureAccessPoint()
        authenticateLocalPlayer()
    }

    func loadAchievements() {
        if let data = UserDefaults.standard.data(forKey: "saved_achievements"),
           let saved = try? JSONDecoder().decode([GameAchievement].self, from: data) {
            var merged = Self.defaultAchievements
            for i in merged.indices {
                if let found = saved.first(where: { $0.id == merged[i].id }), found.isUnlocked {
                    merged[i].isUnlocked = true
                    merged[i].unlockedDate = found.unlockedDate
                }
            }
            achievements = merged
        }
    }

    func saveAchievements() {
        if let data = try? JSONEncoder().encode(achievements) {
            UserDefaults.standard.set(data, forKey: "saved_achievements")
        }
    }

    func unlockAchievement(_ id: String) {
        guard let index = achievements.firstIndex(where: { $0.id == id }), !achievements[index].isUnlocked else { return }
        achievements[index].isUnlocked = true
        achievements[index].unlockedDate = Date()
        saveAchievements()
        let unlockedItem = achievements[index]
        onAchievementUnlocked?(unlockedItem)

        if GKLocalPlayer.local.isAuthenticated {
            let gk = GKAchievement(identifier: id)
            gk.percentComplete = 100.0
            gk.showsCompletionBanner = true
            GKAchievement.report([gk]) { _ in }
        }
    }

    func reportProgress(id: String, percent: Double) {
        let clamped = min(100.0, max(0.0, percent))
        if GKLocalPlayer.local.isAuthenticated {
            let gk = GKAchievement(identifier: id)
            gk.percentComplete = clamped
            gk.showsCompletionBanner = (clamped >= 100.0)
            GKAchievement.report([gk]) { _ in }
        }
        if clamped >= 100.0 {
            unlockAchievement(id)
        }
    }

    func configureAccessPoint() {
        GKAccessPoint.shared.location = .topLeading
        GKAccessPoint.shared.showHighlights = false
        GKAccessPoint.shared.isActive = false
    }

    func triggerGameCenterLogin() {
        configureAccessPoint()
        let localPlayer = GKLocalPlayer.local
        if localPlayer.isAuthenticated {
            self.isAuthenticated = true
            self.localPlayerAlias = localPlayer.alias
            GKAccessPoint.shared.trigger(state: .localPlayerProfile, handler: {})
        } else {
            authenticateLocalPlayer()
            GKAccessPoint.shared.trigger(state: .dashboard, handler: {})
        }
    }

    func authenticateLocalPlayer() {
        let localPlayer = GKLocalPlayer.local
        if localPlayer.isAuthenticated {
            self.isAuthenticated = true
            self.localPlayerAlias = localPlayer.alias
            self.lastError = nil
            GKAccessPoint.shared.isActive = false
            return
        }
        localPlayer.authenticateHandler = { [weak self] vc, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let vc {
                    // Present Apple's native Game Center Sign-In banner/dialog on top-most view controller
                    if let topVC = UIApplication.topViewController {
                        topVC.present(vc, animated: true)
                    }
                } else if localPlayer.isAuthenticated {
                    self.isAuthenticated = true
                    self.localPlayerAlias = localPlayer.alias
                    self.lastError = nil
                    GKAccessPoint.shared.isActive = false
                } else {
                    self.isAuthenticated = false
                    if let error {
                        self.lastError = error.localizedDescription
                    } else {
                        self.lastError = "Para jugar por Internet, activa Game Center en los Ajustes de tu iPhone/iPad."
                    }
                }
            }
        }
    }

    private var activeCoordinator: GameCenterMatchmakerCoordinator?

    func presentMatchmaker(maxPlayers: Int = 8) {
        let localPlayer = GKLocalPlayer.local
        guard localPlayer.isAuthenticated else {
            self.isAuthenticated = false
            self.lastError = "Debes iniciar sesión en Game Center (Ajustes de iOS -> Game Center)."
            triggerGameCenterLogin()
            return
        }

        let clampedMax = max(2, min(16, maxPlayers))
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = clampedMax
        request.defaultNumberOfPlayers = clampedMax
        request.inviteMessage = "¡Únete a mi escuadrón en Laser Tracer 3D (hasta \(clampedMax) jugadores)!"

        guard let vc = GKMatchmakerViewController(matchRequest: request) else { return }
        let coordinator = GameCenterMatchmakerCoordinator(gameCenter: self)
        vc.matchmakerDelegate = coordinator
        self.activeCoordinator = coordinator

        if let topVC = UIApplication.topViewController {
            topVC.present(vc, animated: true)
        }
    }

    func startMatchNowWithConnectedPlayers() {
        guard let activeMatch, !activeMatch.players.isEmpty else { return }
        GKMatchmaker.shared().finishMatchmaking(for: activeMatch)
        onMatchStarted?()
    }

    func startMatch(_ match: GKMatch) {
        self.activeMatch = match
        self.isInMatch = true
        let names = match.players.map { $0.displayName.isEmpty ? $0.alias : $0.displayName }
        self.connectedPlayerNames = names.isEmpty ? ["Jugador Online"] : names
        self.showsMatchmakerSheet = false
        match.delegate = self

        let hello = LocalMatchPacket(
            kind: .hello,
            peerID: GKLocalPlayer.local.alias,
            timestamp: Date().timeIntervalSince1970
        )
        sendPacket(hello)

        if match.expectedPlayerCount == 0 {
            onMatchStarted?()
        }
    }

    func leaveMatch() {
        activeMatch?.disconnect()
        activeMatch = nil
        isInMatch = false
        connectedPlayerNames = []
    }

    func sendPacket(_ packet: LocalMatchPacket) {
        guard let activeMatch, isInMatch,
              let data = try? JSONEncoder().encode(packet) else { return }
        let mode: GKMatch.SendDataMode = (packet.kind == .state || packet.kind == .controllerInput || packet.kind == .enemySync) ? .unreliable : .reliable
        do {
            try activeMatch.sendData(toAllPlayers: data, with: mode)
        } catch {
            lastError = error.localizedDescription
        }
    }
}

extension GameCenterManager: GKMatchDelegate {
    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        guard let packet = try? JSONDecoder().decode(LocalMatchPacket.self, from: data) else { return }
        Task { @MainActor in
            self.onPacketReceived?(packet)
        }
    }

    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        Task { @MainActor in
            let names = match.players.map { $0.displayName.isEmpty ? $0.alias : $0.displayName }
            self.connectedPlayerNames = names.isEmpty ? [player.alias] : names
            if state == .connected {
                self.isInMatch = true
                let hello = LocalMatchPacket(
                    kind: .hello,
                    peerID: GKLocalPlayer.local.alias,
                    timestamp: Date().timeIntervalSince1970
                )
                self.sendPacket(hello)
                if match.expectedPlayerCount == 0 {
                    self.onMatchStarted?()
                }
            } else if state == .disconnected && match.players.isEmpty {
                self.isInMatch = false
            }
        }
    }

    nonisolated func match(_ match: GKMatch, didFailWithError error: Error?) {
        Task { @MainActor in
            self.lastError = error?.localizedDescription
            self.isInMatch = false
        }
    }
}

final class GameCenterMatchmakerCoordinator: NSObject, GKMatchmakerViewControllerDelegate {
    unowned let gameCenter: GameCenterManager

    init(gameCenter: GameCenterManager) {
        self.gameCenter = gameCenter
    }

    func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        viewController.dismiss(animated: true)
    }

    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        viewController.dismiss(animated: true)
        Task { @MainActor in
            self.gameCenter.lastError = error.localizedDescription
        }
    }

    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        viewController.dismiss(animated: true)
        Task { @MainActor in
            self.gameCenter.startMatch(match)
        }
    }
}

struct GameAchievement: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let description: String
    let icon: String
    let points: Int
    var isUnlocked: Bool = false
    var unlockedDate: Date? = nil
}


