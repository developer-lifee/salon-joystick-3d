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

    private(set) var activeMatch: GKMatch?

    var onPacketReceived: ((LocalMatchPacket) -> Void)?

    override init() {
        super.init()
        configureAccessPoint()
        authenticateLocalPlayer()
    }

    func configureAccessPoint() {
        GKAccessPoint.shared.location = .topLeading
        GKAccessPoint.shared.showHighlights = true
        GKAccessPoint.shared.isActive = true
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
            GKAccessPoint.shared.isActive = true
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
                    GKAccessPoint.shared.isActive = true
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

    func presentMatchmaker() {
        let localPlayer = GKLocalPlayer.local
        guard localPlayer.isAuthenticated else {
            self.isAuthenticated = false
            self.lastError = "Debes iniciar sesión en Game Center (Ajustes de iOS -> Game Center)."
            triggerGameCenterLogin()
            return
        }

        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 4
        request.defaultNumberOfPlayers = 2
        request.inviteMessage = "¡Únete a mi partida en Salón Joystick 3D!"

        guard let vc = GKMatchmakerViewController(matchRequest: request) else { return }
        let coordinator = GameCenterMatchmakerCoordinator(gameCenter: self)
        vc.matchmakerDelegate = coordinator
        self.activeCoordinator = coordinator

        if let topVC = UIApplication.topViewController {
            topVC.present(vc, animated: true)
        }
    }

    func startMatch(_ match: GKMatch) {
        self.activeMatch = match
        self.isInMatch = true
        self.connectedPlayerNames = match.players.map { $0.alias }
        self.showsMatchmakerSheet = false
        match.delegate = self
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
        do {
            try activeMatch.sendData(toAllPlayers: data, with: .reliable)
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
            self.connectedPlayerNames = match.players.map { $0.alias }
            self.isInMatch = !match.players.isEmpty
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


