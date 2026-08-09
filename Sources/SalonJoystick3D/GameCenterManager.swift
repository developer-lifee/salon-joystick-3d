import Foundation
import GameKit
import SwiftUI

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
        authenticateLocalPlayer()
    }

    func authenticateLocalPlayer() {
        let localPlayer = GKLocalPlayer.local
        if localPlayer.isAuthenticated {
            self.isAuthenticated = true
            self.localPlayerAlias = localPlayer.alias
            self.lastError = nil
            return
        }
        localPlayer.authenticateHandler = { [weak self] vc, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let vc {
                    // Present Apple's native Game Center Sign-In banner/dialog
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
                        rootVC.present(vc, animated: true)
                    }
                } else if localPlayer.isAuthenticated {
                    self.isAuthenticated = true
                    self.localPlayerAlias = localPlayer.alias
                    self.lastError = nil
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

    func presentMatchmaker() {
        let localPlayer = GKLocalPlayer.local
        if localPlayer.isAuthenticated {
            self.isAuthenticated = true
            self.localPlayerAlias = localPlayer.alias
            self.showsMatchmakerSheet = true
        } else {
            self.isAuthenticated = false
            self.lastError = "Debes iniciar sesión en Game Center (Ajustes de iOS -> Game Center)."
            authenticateLocalPlayer()
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

struct GameCenterMatchmakerView: UIViewControllerRepresentable {
    @ObservedObject var gameCenter: GameCenterManager
    var mode: LocalMatchMode

    func makeUIViewController(context: Context) -> GKMatchmakerViewController {
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 4
        request.defaultNumberOfPlayers = 2

        guard GKLocalPlayer.local.isAuthenticated,
              let vc = GKMatchmakerViewController(matchRequest: request) else {
            return GKMatchmakerViewController()
        }
        vc.matchmakerDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: GKMatchmakerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, GKMatchmakerViewControllerDelegate {
        var parent: GameCenterMatchmakerView

        init(_ parent: GameCenterMatchmakerView) {
            self.parent = parent
        }

        func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
            viewController.dismiss(animated: true)
            Task { @MainActor in
                self.parent.gameCenter.showsMatchmakerSheet = false
            }
        }

        func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
            viewController.dismiss(animated: true)
            Task { @MainActor in
                self.parent.gameCenter.showsMatchmakerSheet = false
                self.parent.gameCenter.lastError = error.localizedDescription
            }
        }

        func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
            viewController.dismiss(animated: true)
            Task { @MainActor in
                self.parent.gameCenter.startMatch(match)
            }
        }
    }
}
