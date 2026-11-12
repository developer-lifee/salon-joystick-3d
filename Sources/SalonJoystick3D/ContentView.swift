import SwiftUI
import AVFoundation
import Metal
import StoreKit
import Combine
import GameController
import GameKit

enum GameCameraMode: Int {
    case thirdPerson
    case firstPerson
}

enum GameHeldTool: Int, CaseIterable, Identifiable {
    case none
    case flashlight
    case laser
    case mirror

    var id: Self { self }

    var icon: String {
        switch self {
        case .none: "hand.raised.fill"
        case .flashlight: "flashlight.on.fill"
        case .laser: "bolt.fill"
        case .mirror: "shield.fill"
        }
    }

    var label: String {
        switch self {
        case .none: "Guardar herramienta"
        case .flashlight: "Linterna"
        case .laser: "Láser"
        case .mirror: "Espejo defensivo"
        }
    }
}

struct GameToolStatus: Equatable {
    var activeRemaining: Float = 0
    var cooldownRemaining: Float = 0
    var label: String = ""
}

enum GameLightFixture: Int, CaseIterable, Identifiable {
    case post
    case piscinaNeon
    case sheeritNeon
    case poolStrips

    var id: Self { self }

    var label: String {
        switch self {
        case .post: "Poste"
        case .piscinaNeon: "Neón PISCINA"
        case .sheeritNeon: "Neón SHEERIT"
        case .poolStrips: "Borde de piscina"
        }
    }
}

struct GameAppVersion {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.1"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "141"
    }
    static let commitHash = "b141firstpersonmirrorandflashlight"
    static var formatted: String {
        "v\(version) • Build \(build)"
    }
}

extension UIDevice {
    /// Detecta si el dispositivo es un iPhone Duo o tiene soporte de pantalla doble
    static var isDuoSupported: Bool {
        #if canImport(UIKit)
        // 1. Identificador de máquina / modelo de hardware (ej. futuros identificadores Duo/Fold)
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in
                String(validatingUTF8: ptr) ?? ""
            }
        }
        if machine.localizedCaseInsensitiveContains("Duo") || machine.localizedCaseInsensitiveContains("Fold") {
            return true
        }

        // 2. Nombre del dispositivo personalizado (ej. "iPhone Duo", "Duo de Esteban")
        let devName = UIDevice.current.name
        if devName.localizedCaseInsensitiveContains("Duo") || devName.localizedCaseInsensitiveContains("Fold") {
            return true
        }

        // 3. Segunda pantalla externa física activa (AirPlay / DisplayPort USB-C)
        if UIScreen.screens.count > 1 {
            return true
        }

        return false
        #else
        return false
        #endif
    }
}

struct GameLightStates: Codable, Equatable {
    var post = false
    var piscinaNeon = false
    var sheeritNeon = false
    var poolStrips = false
    var postIntensity: Float = 1.0
    var piscinaNeonIntensity: Float = 1.0
    var sheeritNeonIntensity: Float = 1.0
    var poolStripsIntensity: Float = 1.0

    var areAllLightsOff: Bool {
        !post && !piscinaNeon && !sheeritNeon && !poolStrips
    }

    mutating func turnOffAllLights() {
        post = false
        piscinaNeon = false
        sheeritNeon = false
        poolStrips = false
    }

    mutating func turnOnAllLights() {
        post = true
        piscinaNeon = true
        sheeritNeon = true
        poolStrips = true
        if postIntensity <= 0.01 { postIntensity = 1.0 }
        if piscinaNeonIntensity <= 0.01 { piscinaNeonIntensity = 1.0 }
        if sheeritNeonIntensity <= 0.01 { sheeritNeonIntensity = 1.0 }
        if poolStripsIntensity <= 0.01 { poolStripsIntensity = 1.0 }
    }

    mutating func toggleAllLights() {
        if areAllLightsOff {
            turnOnAllLights()
        } else {
            turnOffAllLights()
        }
    }

    func isEnabled(_ fixture: GameLightFixture) -> Bool {
        switch fixture {
        case .post: post
        case .piscinaNeon: piscinaNeon
        case .sheeritNeon: sheeritNeon
        case .poolStrips: poolStrips
        }
    }

    mutating func toggle(_ fixture: GameLightFixture) {
        switch fixture {
        case .post:
            post.toggle()
            if post && postIntensity <= 0.01 { postIntensity = 1.0 }
        case .piscinaNeon:
            piscinaNeon.toggle()
            if piscinaNeon && piscinaNeonIntensity <= 0.01 { piscinaNeonIntensity = 1.0 }
        case .sheeritNeon:
            sheeritNeon.toggle()
            if sheeritNeon && sheeritNeonIntensity <= 0.01 { sheeritNeonIntensity = 1.0 }
        case .poolStrips:
            poolStrips.toggle()
            if poolStrips && poolStripsIntensity <= 0.01 { poolStripsIntensity = 1.0 }
        }
    }

    func intensity(_ fixture: GameLightFixture) -> Float {
        switch fixture {
        case .post: (postIntensity <= 0.01) ? 1.0 : postIntensity
        case .piscinaNeon: (piscinaNeonIntensity <= 0.01) ? 1.0 : piscinaNeonIntensity
        case .sheeritNeon: (sheeritNeonIntensity <= 0.01) ? 1.0 : sheeritNeonIntensity
        case .poolStrips: (poolStripsIntensity <= 0.01) ? 1.0 : poolStripsIntensity
        }
    }

    func effectiveIntensity(_ fixture: GameLightFixture) -> Float {
        isEnabled(fixture) ? intensity(fixture) : 0
    }

    mutating func setIntensity(_ value: Float, for fixture: GameLightFixture) {
        let clamped = min(1, max(0.1, value))
        switch fixture {
        case .post:
            post = true
            postIntensity = clamped
        case .piscinaNeon:
            piscinaNeon = true
            piscinaNeonIntensity = clamped
        case .sheeritNeon:
            sheeritNeon = true
            sheeritNeonIntensity = clamped
        case .poolStrips:
            poolStrips = true
            poolStripsIntensity = clamped
        }
    }
}

enum GameRenderResolution: String, CaseIterable, Identifiable {
    case ultraLight
    case light
    case balanced
    case high
    case ultra4K

    var id: Self { self }

    var scale: CGFloat {
        switch self {
        case .ultraLight: 0.55
        case .light: 0.75
        case .balanced: 1.0
        case .high: 1.5
        case .ultra4K: 2.2
        }
    }

    var label: String {
        switch self {
        case .ultraLight: "Ultra Ahorro (0,55x)"
        case .light: "Ligera (0,75x)"
        case .balanced: "Equilibrada (1x)"
        case .high: "Retina Pro (1,5x)"
        case .ultra4K: "Cine 4K TV / Máxima (2,2x)"
        }
    }
}

struct ContentView: View {
    @StateObject private var model = GameModel()
    @State private var dimmerFixture: GameLightFixture?
    @State private var isHUDBarMinimized: Bool = false

    var body: some View {
        if model.multiplayer.isConnected && model.multiplayer.role == .remoteController {
            TacticalRemoteControllerView(model: model)
        } else if model.duoScreenMode == .tacticalButtons && model.gameState == .playing {
            // 📱📱 MODO IPHONE DUO (OPCIÓN 1): Mitad Izquierda/Superior = Vista 3D Ray-Traced 100% Limpia | Mitad Derecha/Inferior = Panel de Mando Táctico
            GeometryReader { geo in
                let isHorizontalSplit = geo.size.width >= geo.size.height
                if isHorizontalSplit {
                    HStack(spacing: 0) {
                        ZStack {
                            MetalGameView(model: model)
                                .ignoresSafeArea(.all)
                                .allowsHitTesting(!model.isEditingHUDLayout)
                            if model.heldTool == .laser && model.laserBattery > 0.01 {
                                Circle()
                                    .stroke(Color.red.opacity(0.85), lineWidth: 1.5)
                                    .frame(width: 24, height: 24)
                                    .overlay(Circle().fill(Color.cyan).frame(width: 4, height: 4))
                            }
                        }
                        .frame(width: geo.size.width * 0.56)

                        Rectangle()
                            .fill(LinearGradient(colors: [.cyan, .purple], startPoint: .top, endPoint: .bottom))
                            .frame(width: 3)

                        DuoTacticalControllerDeckView(model: model)
                            .frame(width: max(1, geo.size.width * 0.44 - 3))
                    }
                    .ignoresSafeArea(.all)
                } else {
                    VStack(spacing: 0) {
                        ZStack {
                            MetalGameView(model: model)
                                .ignoresSafeArea(.all)
                                .allowsHitTesting(!model.isEditingHUDLayout)
                            if model.heldTool == .laser && model.laserBattery > 0.01 {
                                Circle()
                                    .stroke(Color.red.opacity(0.85), lineWidth: 1.5)
                                    .frame(width: 24, height: 24)
                                    .overlay(Circle().fill(Color.cyan).frame(width: 4, height: 4))
                            }
                        }
                        .frame(height: geo.size.height * 0.54)

                        Rectangle()
                            .fill(LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing))
                            .frame(height: 3)

                        DuoTacticalControllerDeckView(model: model)
                            .frame(height: max(1, geo.size.height * 0.46 - 3))
                    }
                    .ignoresSafeArea(.all)
                }
            }
            .sheet(isPresented: $model.showsMultiplayerSheet) {
                MultiplayerSettingsSheet(model: model)
            }
            .sheet(isPresented: $model.showsSettingsSheet) {
                GameOptionsSheet(model: model)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $model.showsAchievementsSheet) {
                NavigationStack {
                    AchievementsView(model: model)
                }
            }
            .fullScreenCover(isPresented: $model.showsPrologueScreen) {
                CinematicPrologueView(model: model)
            }
            .fullScreenCover(isPresented: $model.showsQuantumFuseBox) {
                QuantumFuseBoxView(model: model)
            }
        } else {
            ZStack(alignment: .bottomLeading) {
                MetalGameView(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(.all)
                    .allowsHitTesting(!model.isEditingHUDLayout)
                    .overlay {
                        if model.isDefeated {
                            DefeatOverlayView(
                                isTeamDefeat: model.isTeamDefeated,
                                isVersus: model.isAnyMultiplayerConnected && model.multiplayer.mode == .versus,
                                versusRound: model.versusRound,
                                localWins: model.versusLocalWins,
                                remoteWins: model.versusRemoteWins,
                                remotePlayerName: model.remotePlayerName,
                                coopDeaths: model.coopDeaths,
                                slang: model.slang,
                                onRespawn: {
                                    if model.isAnyMultiplayerConnected && model.multiplayer.mode == .versus {
                                        model.startNextVersusRound(fromNetwork: false)
                                    } else if model.isTeamDefeated {
                                        model.restartCooperativeMatch()
                                    } else {
                                        model.respawnPlayer()
                                    }
                                }
                            )
                            .transition(.opacity)
                        } else if model.isRecoveringInChamber {
                            RecoveryChamberOverlayView(model: model)
                                .transition(.opacity)
                        } else if model.isAnyMultiplayerConnected && model.multiplayer.mode == .versus && model.remotePlayerHealth <= 0 {
                            VStack(spacing: 12) {
                                Image(systemName: "trophy.fill")
                                    .font(.system(size: 46))
                                    .foregroundStyle(
                                        LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                                    )
                                    .shadow(color: .orange.opacity(0.8), radius: 10)

                                Text("¡VICTORIA EN RONDA \(model.versusRound)!")
                                    .font(.system(size: 28, weight: .black, design: .rounded))
                                    .foregroundStyle(
                                        LinearGradient(colors: [.white, .yellow], startPoint: .top, endPoint: .bottom)
                                    )
                                    .shadow(color: .yellow.opacity(0.8), radius: 10)

                                Text("DERROTASTE A \(model.remotePlayerName.isEmpty ? "TU RIVAL" : model.remotePlayerName)")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.9))

                                HStack(spacing: 18) {
                                    VStack(spacing: 2) {
                                        Text("TÚ")
                                            .font(.system(size: 11, weight: .black, design: .monospaced))
                                            .foregroundStyle(.cyan)
                                        Text("\(model.versusLocalWins)")
                                            .font(.system(size: 26, weight: .black, design: .rounded))
                                            .foregroundStyle(.white)
                                    }
                                    Text("—")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.4))
                                    VStack(spacing: 2) {
                                        Text(model.remotePlayerName.isEmpty ? "RIVAL" : model.remotePlayerName.uppercased())
                                            .font(.system(size: 11, weight: .black, design: .monospaced))
                                            .foregroundStyle(.red)
                                        Text("\(model.versusRemoteWins)")
                                            .font(.system(size: 26, weight: .black, design: .rounded))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .padding(.horizontal, 22)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))

                                Button(action: {
                                    model.startNextVersusRound(fromNetwork: false)
                                }) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "arrow.right.circle.fill")
                                            .font(.system(size: 16, weight: .bold))
                                        Text("SIGUIENTE RONDA")
                                            .font(.system(size: 14, weight: .black, design: .monospaced))
                                    }
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 28)
                                    .padding(.vertical, 12)
                                    .background(Capsule().fill(Color.yellow))
                                    .shadow(color: .yellow.opacity(0.6), radius: 8)
                                }
                                .padding(.top, 6)
                            }
                            .padding(.horizontal, 36)
                            .padding(.vertical, 24)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(LinearGradient(colors: [.yellow.opacity(0.8), .orange.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
                            )
                            .shadow(color: .black.opacity(0.5), radius: 20)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }

                if model.showsCampaignVictoryModal {
                    CampaignVictoryModalView(model: model)
                        .transition(.opacity)
                        .zIndex(100)
                }

                if model.gameState == .mainMenu {
                    MainMenuView(model: model)
                } else {

            // GTA-Style Aim Crosshair Overlay (Estética Neón Cyan & Pink)
            if model.heldTool == .laser && model.laserBattery > 0.01 {
                ZStack {
                    Circle()
                        .stroke(Color.pink.opacity(0.85), lineWidth: 1.5)
                        .frame(width: 28, height: 28)
                        .shadow(color: Color.pink.opacity(0.8), radius: 5)

                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 4.5, height: 4.5)
                        .shadow(color: Color.cyan.opacity(0.9), radius: 4)

                    Rectangle()
                        .fill(Color.pink.opacity(0.75))
                        .frame(width: 8, height: 1.5)
                        .offset(x: -18)

                    Rectangle()
                        .fill(Color.pink.opacity(0.75))
                        .frame(width: 8, height: 1.5)
                        .offset(x: 18)

                    Rectangle()
                        .fill(Color.pink.opacity(0.75))
                        .frame(width: 1.5, height: 8)
                        .offset(y: -18)

                    Rectangle()
                        .fill(Color.pink.opacity(0.75))
                        .frame(width: 1.5, height: 8)
                        .offset(y: 18)
                }
                .allowsHitTesting(false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            if model.isSlowMotionActive {
                RadialGradient(
                    colors: [.clear, Color.pink.opacity(0.12), .black.opacity(0.55)],
                    center: .center,
                    startRadius: 80,
                    endRadius: 480
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            // 🛡️❤️ Barra de Vida, Escudo y Puntos (Anclada al centro inferior, configurable en el editor de HUD)
            if (!model.isDefeated && !model.isRecoveringInChamber) || model.isEditingHUDLayout {
                HStack(spacing: 12) {
                    // Escudo
                    HStack(spacing: 5) {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.cyan)
                        ProgressView(value: Double(model.playerShield), total: 100.0)
                            .tint(.cyan)
                            .frame(width: 65)
                        Text("\(Int(model.playerShield))")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }

                    Divider()
                        .frame(height: 14)
                        .overlay(Color.white.opacity(0.3))

                    // Salud
                    HStack(spacing: 5) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.pink)
                        ProgressView(value: Double(model.playerHealth), total: Double(model.maxPlayerHealth))
                            .tint(model.playerHealth > 25 ? Color.pink : Color.red)
                            .frame(width: 65)
                        Text("\(Int(model.playerHealth))")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.pink)
                    }

                    Divider()
                        .frame(height: 14)
                        .overlay(Color.white.opacity(0.3))

                    // Puntos
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.cyan)
                        Text("\(model.playerScore)")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .background(Color.black.opacity(0.45), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.75), Color.pink.opacity(0.75)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)
                .opacity(model.hudHealthOpacity)
                .modifier(HUDDraggableModifier(
                    isEditing: model.isEditingHUDLayout,
                    isSelected: model.selectedHUDGroup == 10,
                    label: "❤️ SALUD / ESCUDO",
                    offsetX: $model.hudHealthX,
                    offsetY: $model.hudHealthY,
                    scale: model.hudHealthScale,
                    onSelect: { model.selectedHUDGroup = 10 }
                ))
                .padding(.bottom, 14)
                .padding(.leading, 185)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }

                // 🧟 Call of Duty Zombies-Style Wave / Round HUD Banner o Duelo Versus / Equipos
                VStack(spacing: 4) {
                    if model.showsFlashlightGuideBanner {
                        HStack(spacing: 8) {
                            Image(systemName: "flashlight.on.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.yellow)
                                .shadow(color: .yellow.opacity(0.8), radius: 6)

                            Text("🔦 LINTERNA ENCENDIDA • La sala está a oscuras. Ilumina tu camino y activa los interruptores.")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .background(Color.black.opacity(0.7), in: Capsule())
                        .overlay(Capsule().stroke(Color.yellow.opacity(0.85), lineWidth: 1.5))
                        .shadow(color: Color.yellow.opacity(0.4), radius: 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if model.showsChronoLockBanner {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(.cyan)
                            Text("🔒 CHRONO-CORE DORMIDO: Conecta los fusibles cuánticos para activar el Modo Slow-Mo y +50 HP.")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                            Button {
                                model.showsQuantumFuseBox = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "wrench.and.screwdriver.fill")
                                    Text("REPARAR FUSIBLES")
                                }
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.yellow, in: Capsule())
                                .shadow(color: Color.yellow.opacity(0.6), radius: 5)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .background(Color.black.opacity(0.65), in: Capsule())
                        .overlay(Capsule().stroke(Color.cyan.opacity(0.8), lineWidth: 1))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if model.isNearFuseTerminal && !model.isSlowMotionUnlocked {
                        Button {
                            model.showsQuantumFuseBox = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "bolt.badge.automatic.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.yellow)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("⚡ CAJA DE FUSIBLES CUÁNTICA")
                                        .font(.system(size: 11, weight: .black, design: .monospaced))
                                        .foregroundStyle(.white)
                                    Text("Toca para reconectar cables y activar Slow-Mo")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                                Image(systemName: "chevron.right.circle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.yellow)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .background(Color.black.opacity(0.7), in: Capsule())
                            .overlay(Capsule().stroke(Color.yellow.opacity(0.85), lineWidth: 1.5))
                            .shadow(color: Color.yellow.opacity(0.5), radius: 8)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }

                    if model.showsChronoCoreUnlockedBanner {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("✨ ¡CHRONO-CORE ACTIVADO!")
                                    .font(.system(size: 12, weight: .black, design: .rounded))
                                    .foregroundStyle(.yellow)
                                Text("Refracción cuántica completada • Modo Slow-Motion disponible • +50 HP Permanente (150 Salud Máxima)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.yellow.opacity(0.9), lineWidth: 1.5))
                        .shadow(color: Color.yellow.opacity(0.4), radius: 10)
                        .transition(.scale.combined(with: .opacity))
                    }

                if model.isAnyMultiplayerConnected && model.multiplayer.mode == .lightBattle {
                    let isTeamLight = model.isLocalTeamAlpha
                    let onCount = [model.lightStates.post, model.lightStates.piscinaNeon, model.lightStates.sheeritNeon, model.lightStates.poolStrips].filter { $0 }.count
                    let offCount = 4 - onCount
                    let myLightsReady = isTeamLight ? (onCount == 4) : (offCount == 4)
                    let rivalLightsReady = isTeamLight ? (offCount == 4) : (onCount == 4)
                    let distToCore = Int(round(simd_distance(model.localPlayerPosition, model.energyCorePosition)))
                    let myBasePos = isTeamLight ? SIMD3<Float>(-7.55, 0.2, 12.65) : SIMD3<Float>(-7.0, 0.2, -15.5)
                    let distToBase = Int(round(simd_distance(model.localPlayerPosition, myBasePos)))

                    VStack(spacing: 5) {
                        // 1. Rol del Jugador + Marcador de Capturas (Primero a 3 gana)
                        HStack(spacing: 10) {
                            HStack(spacing: 4) {
                                Image(systemName: isTeamLight ? "sun.max.fill" : "moon.stars.fill")
                                    .foregroundStyle(isTeamLight ? .yellow : .purple)
                                Text(isTeamLight ? "ERES EQUIPO LUZ (PRENDER)" : "ERES EQUIPO SOMBRA (APAGAR)")
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .foregroundStyle(isTeamLight ? .yellow : .purple)
                            }

                            Divider().frame(height: 14).background(Color.white.opacity(0.4))

                            Text("☀️ \(model.lightTeamScore)/3")
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .foregroundStyle(.yellow)

                            Text("vs")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.5))

                            Text("🌑 \(model.shadowTeamScore)/3")
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .foregroundStyle(.purple)
                        }

                        // 2. Estado de las 4 Luces en Vivo
                        HStack(spacing: 6) {
                            ForEach(GameLightFixture.allCases) { fixture in
                                let isOn = model.lightStates.isEnabled(fixture)
                                HStack(spacing: 3) {
                                    Image(systemName: isOn ? "lightbulb.fill" : "lightbulb.slash.fill")
                                        .font(.system(size: 9, weight: .bold))
                                    Text(fixture.label)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                }
                                .foregroundStyle(isOn ? .black : .white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(isOn ? Color.yellow : Color.purple.opacity(0.65))
                                )
                            }
                        }

                        // 3. Instrucción Paso a Paso en Tiempo Real ("¿Qué toca hacer ahora?")
                        Group {
                            if let winner = model.lightBattleWinner {
                                Text(winner)
                                    .foregroundStyle(.yellow)
                            } else if model.hasEnergyCore {
                                Text(isTeamLight
                                     ? "🏁 PASO 3: ¡LLEVA EL NÚCLEO AL FAROL DEL PATIO (TU BASE A \(distToBase)m)!"
                                     : "🏁 PASO 3: ¡LLEVA EL NÚCLEO AL NEÓN PISCINA (TU BASE A \(distToBase)m)!")
                                    .foregroundStyle(.green)
                            } else if model.remoteHasEnergyCore {
                                Text("🚨 ¡EL RIVAL LLEVA EL NÚCLEO! DISPÁRALE CON EL LÁSER O CAMBIA UNA LUZ")
                                    .foregroundStyle(.red)
                            } else if myLightsReady {
                                Text("⚡ PASO 2: ¡4/4 LUCES LISTAS! RECOGE EL NÚCLEO EN EL GRAN SALÓN ARCOÍRIS (A \(distToCore)m)")
                                    .foregroundStyle(.cyan)
                            } else if rivalLightsReady {
                                Text(isTeamLight
                                     ? "🚨 ¡EL RIVAL APAGÓ TODO! PRENDE UNA LUZ YA PARA BLOQUEARLE EL NÚCLEO"
                                     : "🚨 ¡EL RIVAL PRENDIÓ TODO! APAGA UNA LUZ YA PARA BLOQUEARLE EL NÚCLEO")
                                    .foregroundStyle(.orange)
                            } else {
                                Text(isTeamLight
                                     ? "💡 PASO 1: PRENDE LAS 4 LUCES PARA DESBLOQUEAR EL NÚCLEO (\(onCount)/4 ENCENDIDAS)"
                                     : "🌑 PASO 1: APAGA LAS 4 LUCES PARA DESBLOQUEAR EL NÚCLEO (\(offCount)/4 APAGADAS)")
                                    .foregroundStyle(.white)
                            }
                        }
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(
                            LinearGradient(colors: [.yellow.opacity(0.85), .purple.opacity(0.85)], startPoint: .leading, endPoint: .trailing),
                            lineWidth: 1.5
                        )
                    )
                    .shadow(color: .black.opacity(0.45), radius: 8)
                } else if model.isAnyMultiplayerConnected && model.multiplayer.mode == .versus {
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "swords")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.yellow)

                            Text("RONDA \(model.versusRound)")
                                .font(.system(size: 13, weight: .black, design: .monospaced))
                                .foregroundStyle(
                                    LinearGradient(colors: [.white, .yellow], startPoint: .top, endPoint: .bottom)
                                )
                        }

                        Divider()
                            .frame(height: 18)
                            .background(Color.white.opacity(0.4))

                        HStack(spacing: 8) {
                            Text("TÚ: \(model.versusLocalWins)")
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .foregroundStyle(.cyan)

                            Text("—")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.5))

                            Text("RIVAL: \(model.versusRemoteWins)")
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .foregroundStyle(.red)
                        }

                        Divider()
                            .frame(height: 18)
                            .background(Color.white.opacity(0.4))

                        HStack(spacing: 6) {
                            Text("HP: \(Int(max(0, model.remotePlayerHealth)))% • ESC: \(Int(max(0, model.remotePlayerShield)))%")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundStyle(model.remotePlayerHealth > 30 ? Color.green : Color.red)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(LinearGradient(colors: [.yellow.opacity(0.85), .orange.opacity(0.60)], startPoint: .leading, endPoint: .trailing), lineWidth: 1.5)
                    )
                    .shadow(color: .orange.opacity(0.35), radius: 8, x: 0, y: 4)
                } else if model.isWaveIntermission {
                    VStack(spacing: 4) {
                        Text("¡OLEADA COMPLETADA!")
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: .orange.opacity(0.8), radius: 6)

                        Text("DESCANSO: \(Int(ceil(model.waveIntermissionTime)))s")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)

                        if model.isAnyMultiplayerConnected && model.multiplayer.mode == .cooperative && model.remotePlayerIsRecovering {
                            Button {
                                model.pumpTeammateAir(fromIntermission: true)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "wind")
                                        .font(.system(size: 14, weight: .black))
                                    Text("💨 BOMBEAR A \(model.remotePlayerName.isEmpty ? "COMPAÑERO" : model.remotePlayerName.uppercased()) (\(model.teammateRevivePumps)/5)")
                                        .font(.system(size: 12, weight: .black, design: .rounded))
                                }
                                .foregroundStyle(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule()
                                        .fill(LinearGradient(colors: [.yellow, .green], startPoint: .leading, endPoint: .trailing))
                                )
                                .shadow(color: .green.opacity(0.8), radius: 8)
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isPumpingTeammateStroke)
                            .padding(.top, 2)
                        } else {
                            Text("+25 HP REGENERADOS")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(LinearGradient(colors: [.yellow.opacity(0.8), .orange.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 5)
                } else {
                    HStack(spacing: 10) {
                        HStack(spacing: 4) {
                            Text("OLEADA")
                                .font(.system(size: 13, weight: .black, design: .monospaced))
                                .foregroundStyle(.red)

                            Text("\(model.currentWave)")
                                .font(.system(size: 26, weight: .black, design: .monospaced))
                                .foregroundStyle(.red)
                                .shadow(color: .red.opacity(0.9), radius: 8)
                        }

                        Divider()
                            .frame(height: 20)
                            .background(Color.white.opacity(0.4))

                        HStack(spacing: 4) {
                            Image(systemName: "ladybug.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.red.opacity(0.8))

                            Text("RESTANTES: \(model.botsRemainingInWave) / \(model.totalBotsInWave)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }

                        if model.isAnyMultiplayerConnected && model.multiplayer.mode == .cooperative {
                            Divider()
                                .frame(height: 20)
                                .background(Color.white.opacity(0.4))

                            HStack(spacing: 4) {
                                Image(systemName: "skull.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.purple)

                                Text("BAJAS: \(model.coopDeaths)")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.purple)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(LinearGradient(colors: [.white.opacity(0.85), .red.opacity(0.50)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
                    )
                    .shadow(color: .black.opacity(0.20), radius: 8, x: 0, y: 4)
                }

                // Barra de Jefe / Enemigo Colosal (Solo aparece cuando hay un TITÁN o HEAVY activo)
                if !(model.isAnyMultiplayerConnected && (model.multiplayer.mode == .versus || model.multiplayer.mode == .lightBattle)) {
                    let titanHp = 4 < model.npcHealths.count ? model.npcHealths[4] : 0.0
                    let heavyHp = 3 < model.npcHealths.count ? model.npcHealths[3] : 0.0

                    if titanHp > 0 {
                        let titanMax = 4 < model.npcMaxHealths.count ? model.npcMaxHealths[4] : 320.0
                        let frac = max(0, min(1.0, titanHp / titanMax))
                        HStack(spacing: 6) {
                            Text("👾 TITÁN COLOSAL")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundStyle(Color.purple)

                            ProgressView(value: Double(frac), total: 1.0)
                                .tint(Color.purple)
                                .frame(width: 110)

                            Text("\(Int(titanHp)) HP")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .background(Color.black.opacity(0.6), in: Capsule())
                        .overlay(Capsule().stroke(Color.purple.opacity(0.8), lineWidth: 1.2))
                        .shadow(color: Color.purple.opacity(0.4), radius: 6)
                        .padding(.top, 2)
                    } else if heavyHp > 0 && model.currentWave >= 3 {
                        let heavyMax = 3 < model.npcMaxHealths.count ? model.npcMaxHealths[3] : 200.0
                        let frac = max(0, min(1.0, heavyHp / heavyMax))
                        HStack(spacing: 6) {
                            Text("🛡️ HEAVY BOT")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundStyle(Color.red)

                            ProgressView(value: Double(frac), total: 1.0)
                                .tint(Color.red)
                                .frame(width: 90)

                            Text("\(Int(heavyHp)) HP")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .background(Color.black.opacity(0.6), in: Capsule())
                        .overlay(Capsule().stroke(Color.red.opacity(0.8), lineWidth: 1.2))
                        .padding(.top, 2)
                    }

                    if model.currentWave >= 5 && (0..<min(2, model.npcHealths.count)).contains(where: { model.npcHealths[$0] > 0 }) {
                        HStack(spacing: 6) {
                            Text("🛸 AMENAZA AÉREA")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundStyle(Color.cyan)

                            Text("DRONE LÁSER EN VUELO")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .background(Color.black.opacity(0.6), in: Capsule())
                        .overlay(Capsule().stroke(Color.cyan.opacity(0.85), lineWidth: 1.2))
                        .shadow(color: Color.cyan.opacity(0.4), radius: 6)
                        .padding(.top, 2)
                    }
                }

                if let achievement = model.recentlyUnlockedAchievement {
                    Button {
                        model.showsAchievementsSheet = true
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 36, height: 36)
                                Image(systemName: achievement.icon)
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(.black)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("¡LOGRO DESBLOQUEADO!")
                                        .font(.system(size: 9, weight: .black, design: .rounded))
                                        .foregroundStyle(.yellow)
                                    Spacer()
                                    Text("+\(achievement.points) PTS")
                                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.85))
                                }
                                Text(achievement.title)
                                    .font(.system(size: 13, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                Text(achievement.description)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .frame(maxWidth: 360)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    LinearGradient(colors: [.yellow, .orange.opacity(0.8), .yellow.opacity(0.3)], startPoint: .leading, endPoint: .trailing),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: .orange.opacity(0.6), radius: 10, y: 3)
                    }
                    .buttonStyle(.plain)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if model.showsRainbowGateNotice {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.yellow)
                        Text("✨ ¡ESPEJO PORTAL ACTIVADO! PASO LIBRE AL HIPERESPACIO")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule().stroke(
                            LinearGradient(colors: [.yellow, .orange, .pink, .purple, .cyan], startPoint: .leading, endPoint: .trailing),
                            lineWidth: 1.5
                        )
                    )
                    .shadow(color: .yellow.opacity(0.8), radius: 8)
                } else if model.isNearRainbowGate && !model.isRainbowGateUnlocked {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.yellow)
                        Text("🔒 ESPEJO PORTAL BLOQUEADO (\(model.playerScore) / \(model.rainbowGateScoreNeeded) PTS)")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.yellow)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.75), in: Capsule())
                    .overlay(Capsule().stroke(Color.yellow.opacity(0.85), lineWidth: 1.5))
                    .shadow(color: .yellow.opacity(0.4), radius: 6)
                } else if model.isNearRainbowGate && model.isRainbowGateUnlocked {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.cyan)
                        Text("✨ ¡PORTAL ABIERTO (3,000 PTS)! CRUZA AL OTRO MUNDO")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule().stroke(
                            LinearGradient(colors: [.cyan, .yellow, .purple, .pink], startPoint: .leading, endPoint: .trailing),
                            lineWidth: 1.5
                        )
                    )
                    .shadow(color: .cyan.opacity(0.6), radius: 6)
                }

                if model.heldTool == .mirror && model.toolStatus.activeRemaining > 0 {
                    HStack(spacing: 12) {
                        Label("ESCENARIO", systemImage: "camera.viewfinder")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                        Text("|")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(.cyan)
                        Label("REFLEJO DEL ESPEJO (APUNTA AL RIVAL)", systemImage: "scope")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.75), in: Capsule())
                    .overlay(Capsule().stroke(Color.cyan.opacity(0.85), lineWidth: 1.5))
                    .shadow(color: .cyan.opacity(0.45), radius: 6)
                    .padding(.top, 3)
                } else if model.duoScreenMode == .squadCamera {
                    Button {
                        model.cycleSquadCameraMember()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack(spacing: 10) {
                            Label("TU CÁMARA", systemImage: "person.fill.viewfinder")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundStyle(.white)
                            Text("|")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundStyle(.cyan)
                            Label("CÁMARA ESCUADRA: \(model.selectedSquadCameraAgent.peerID.uppercased()) (TOCA PARA CAMBIAR)", systemImage: "video.fill")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundStyle(.cyan)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.78), in: Capsule())
                        .overlay(Capsule().stroke(Color.cyan.opacity(0.85), lineWidth: 1.5))
                        .shadow(color: .cyan.opacity(0.45), radius: 6)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 3)
                }

                if model.isAnyMultiplayerConnected && model.multiplayer.mode == .cooperative && model.remotePlayerIsRecovering {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.yellow)
                        Text("¡COMPAÑERO EN CÁMARA MÉDICA! (\(Int(ceil(model.remotePlayerRecoveryTime)))s)")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.yellow.opacity(0.85), lineWidth: 1.5))
                    .shadow(color: .yellow.opacity(0.4), radius: 8)
                    .padding(.top, 3)
                }
            }
            .padding(.top, 46)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if (!model.isDefeated && !model.isRecoveringInChamber) || model.isEditingHUDLayout {
                VStack(alignment: .leading, spacing: 10) {
                    JoystickView(onChanged: { vector in
                        guard !model.isDefeated, model.gameState == .playing else {
                            model.joystick = .zero
                            return
                        }
                        model.joystick = vector
                    }, isLiquidGlass: model.isLiquidGlassUIEnabled)
                    .frame(width: 156, height: 156)
                    .opacity(model.hudJoystickOpacity)
                    .disabled(model.isDefeated || model.gameState != .playing)
                    .modifier(HUDDraggableModifier(
                        isEditing: model.isEditingHUDLayout,
                        isSelected: model.selectedHUDGroup == 0,
                        label: "🕹️ JOYSTICK",
                        offsetX: $model.hudJoystickX,
                        offsetY: $model.hudJoystickY,
                        scale: model.hudJoystickScale,
                        onSelect: { model.selectedHUDGroup = 0 }
                    ))
                }
                .padding(.leading, 18)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }

            // 🧭 Radar Minimapa Táctico (Anclado con posición fija independiente, configurable en editor de HUD)
            if ((model.showsMinimap && !model.isMinimalHUDEnabled && !model.isDefeated && !model.isRecoveringInChamber) || model.isEditingHUDLayout) {
                TacticalMinimapView(model: model)
                    .opacity(model.hudMinimapOpacity)
                    .modifier(HUDDraggableModifier(
                        isEditing: model.isEditingHUDLayout,
                        isSelected: model.selectedHUDGroup == 8,
                        label: "🗺️ RADAR",
                        offsetX: $model.hudMinimapX,
                        offsetY: $model.hudMinimapY,
                        scale: model.hudMinimapScale,
                        onSelect: { model.selectedHUDGroup = 8 }
                    ))
                    .padding(.trailing, 12)
                    .padding(.bottom, 126)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .transition(.scale.combined(with: .opacity))
            }

            if (!model.isDefeated && !model.isRecoveringInChamber) || model.isEditingHUDLayout {
                VStack(alignment: .trailing, spacing: 8) {
                    // Aviso crítico de herramienta (solo si es advertencia de batería o sobrecalentamiento)
                    if !model.toolStatus.label.isEmpty && (model.toolStatus.label.contains("⚠️") || model.toolStatus.label.contains("🔥")) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 7, height: 7)
                                .shadow(color: Color.red.opacity(0.8), radius: 3)

                            Text(model.toolStatus.label)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .background(Color.black.opacity(0.75), in: Capsule())
                        .overlay(Capsule().stroke(Color.red.opacity(0.85), lineWidth: 1.2))
                        .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 2)
                        .transition(.scale.combined(with: .opacity))
                    }

                    // Bar 1: Action & Skill Buttons (Acción Contextual, Slow-Mo, Warp) - Estilo Circular Neón
                    HStack(spacing: 8) {
                        ContextualActionCircleButton(model: model, dimmerFixture: $dimmerFixture)
                            .opacity(model.hudActionOpacity)
                            .disabled(model.isDefeated || model.gameState != .playing)
                            .modifier(HUDDraggableModifier(
                                isEditing: model.isEditingHUDLayout,
                                isSelected: model.selectedHUDGroup == 5,
                                label: "🎯 ACCIÓN",
                                offsetX: $model.hudActionX,
                                offsetY: $model.hudActionY,
                                scale: model.hudActionScale,
                                onSelect: { model.selectedHUDGroup = 5 }
                            ))

                        SlowMoCircleButton(model: model)
                            .opacity(model.hudSlowMoOpacity)
                            .disabled(model.isDefeated || model.gameState != .playing)
                            .modifier(HUDDraggableModifier(
                                isEditing: model.isEditingHUDLayout,
                                isSelected: model.selectedHUDGroup == 6,
                                label: "⏳ SLOW-MO",
                                offsetX: $model.hudSlowMoX,
                                offsetY: $model.hudSlowMoY,
                                scale: model.hudSlowMoScale,
                                onSelect: { model.selectedHUDGroup = 6 }
                            ))

                        WarpCircleButton(model: model)
                            .opacity(model.hudWarpOpacity)
                            .disabled(model.isDefeated || model.gameState != .playing)
                            .modifier(HUDDraggableModifier(
                                isEditing: model.isEditingHUDLayout,
                                isSelected: model.selectedHUDGroup == 7,
                                label: "⚡ WARP",
                                offsetX: $model.hudWarpX,
                                offsetY: $model.hudWarpY,
                                scale: model.hudWarpScale,
                                onSelect: { model.selectedHUDGroup = 7 }
                            ))

                        if model.isGameControllerConnected && !model.isMinimalHUDEnabled {
                            HStack(spacing: 5) {
                                Image(systemName: "gamecontroller.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Color.cyan)
                                Text(model.gameControllerName)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.cyan.opacity(0.6), lineWidth: 1))
                        }

                        if model.isNearRecoveryConsole && model.remotePlayerIsRecovering {
                            Button {
                                model.pumpTeammateAir()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "gauge.with.needle.fill")
                                        .font(.system(size: 18, weight: .black))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("💨 BOMBEAR A \(model.remotePlayerName.isEmpty ? "COMPAÑERO" : model.remotePlayerName.uppercased())")
                                            .font(.system(size: 13, weight: .black, design: .rounded))
                                        Text("BOMBEO: \(model.teammateRevivePumps)/5 (Mínimo 5s)")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    }
                                }
                                .foregroundStyle(.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom),
                                    in: Capsule()
                                )
                                .overlay(Capsule().stroke(Color.white, lineWidth: 1.5))
                                .shadow(color: .orange.opacity(0.8), radius: 8)
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isPumpingTeammateStroke)
                            .accessibilityLabel("Bombear Aire a Compañero con Bomba Neumática")
                        }
                    }
                    .disabled(model.isDefeated || model.gameState != .playing)

                    // Bar 2: Independent Weapon Buttons + Jump Button (Cada arma independiente)
                    HStack(alignment: .center, spacing: 8) {
                        FlashlightButton(model: model)
                            .opacity(model.hudFlashlightOpacity)
                            .disabled(model.isDefeated || model.gameState != .playing)
                            .modifier(HUDDraggableModifier(
                                isEditing: model.isEditingHUDLayout,
                                isSelected: model.selectedHUDGroup == 1,
                                label: "🔦 LINTERNA",
                                offsetX: $model.hudFlashlightX,
                                offsetY: $model.hudFlashlightY,
                                scale: model.hudFlashlightScale,
                                onSelect: { model.selectedHUDGroup = 1 }
                            ))

                        LaserButton(model: model)
                            .opacity(model.hudLaserOpacity)
                            .disabled(model.isDefeated || model.gameState != .playing)
                            .modifier(HUDDraggableModifier(
                                isEditing: model.isEditingHUDLayout,
                                isSelected: model.selectedHUDGroup == 2,
                                label: "⚡ LÁSER",
                                offsetX: $model.hudLaserX,
                                offsetY: $model.hudLaserY,
                                scale: model.hudLaserScale,
                                onSelect: { model.selectedHUDGroup = 2 }
                            ))

                        MirrorShieldJoystickButton(model: model)
                            .opacity(model.hudShieldOpacity)
                            .disabled(model.isDefeated || model.gameState != .playing)
                            .modifier(HUDDraggableModifier(
                                isEditing: model.isEditingHUDLayout,
                                isSelected: model.selectedHUDGroup == 3,
                                label: "🛡️ ESCUDO",
                                offsetX: $model.hudShieldX,
                                offsetY: $model.hudShieldY,
                                scale: model.hudShieldScale,
                                onSelect: { model.selectedHUDGroup = 3 }
                            ))

                        JumpButton(model: model)
                            .opacity(model.hudJumpOpacity)
                            .disabled(model.isDefeated || model.gameState != .playing)
                            .modifier(HUDDraggableModifier(
                                isEditing: model.isEditingHUDLayout,
                                isSelected: model.selectedHUDGroup == 4,
                                label: "⬆️ SALTAR",
                                offsetX: $model.hudJumpX,
                                offsetY: $model.hudJumpY,
                                scale: model.hudJumpScale,
                                onSelect: { model.selectedHUDGroup = 4 }
                            ))
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 12)
            .padding(.bottom, 16)
        }

            VStack(alignment: .trailing, spacing: 8) {
                // ⚙️ Botón de Ajustes (Cyan & Pink Liquid Glass)
                Button {
                    model.showsSettingsSheet = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color.cyan)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .background(Color.black.opacity(0.40), in: Circle())
                        .overlay(
                            Circle().stroke(
                                LinearGradient(
                                    colors: [Color.cyan.opacity(0.85), Color.pink.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                        )
                        .shadow(color: Color.cyan.opacity(0.35), radius: 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ajustes y Opciones")

                // 🔊 Botón de Audio (Cyan cuando activo, Pink cuando silenciado)
                Button {
                    let audioOn = model.footstepsEnabled
                    model.footstepsEnabled = !audioOn
                    model.waterSoundEnabled = !audioOn
                    model.musicEnabled = !audioOn
                } label: {
                    Image(systemName: model.footstepsEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(model.footstepsEnabled ? Color.cyan : Color.pink)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .background(Color.black.opacity(0.40), in: Circle())
                        .overlay(
                            Circle().stroke(
                                model.footstepsEnabled ? Color.cyan.opacity(0.85) : Color.pink.opacity(0.85),
                                lineWidth: 1.5
                            )
                        )
                        .shadow(color: (model.footstepsEnabled ? Color.cyan : Color.pink).opacity(0.35), radius: 6)
                }
                .accessibilityLabel("Controles de audio")

                // ⏸️ Botón de Pausa (Estética Liquid Glass Neón)
                Button {
                    model.togglePause()
                } label: {
                    Image(systemName: model.gameState == .paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(model.gameState == .paused ? Color.pink : .white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .background(Color.black.opacity(0.40), in: Circle())
                        .overlay(
                            Circle().stroke(
                                LinearGradient(
                                    colors: [Color.pink.opacity(0.85), Color.cyan.opacity(0.85)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                        )
                        .shadow(color: Color.pink.opacity(0.35), radius: 6)
                }
                .accessibilityLabel("Pausa")

                if model.showsFPS {
                    Text("\(Int(model.framesPerSecond.rounded())) FPS")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(Color.cyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .background(Color.black.opacity(0.50), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.cyan.opacity(0.6), lineWidth: 1.0)
                        )
                }
            }
            .opacity(model.hudMenuOpacity)
            .modifier(HUDDraggableModifier(
                isEditing: model.isEditingHUDLayout,
                isSelected: model.selectedHUDGroup == 9,
                label: "⚙️ MENÚ / PAUSA",
                offsetX: $model.hudMenuX,
                offsetY: $model.hudMenuY,
                scale: model.hudMenuScale,
                onSelect: { model.selectedHUDGroup = 9 }
            ))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .safeAreaPadding(.top, 8)
            .padding(.trailing, 12)

            if model.showConnectedToast {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("¡ENLAZADO CON \(model.activePeerDisplayName.uppercased())!")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.black.opacity(0.80), in: Capsule())
                .overlay(Capsule().stroke(Color.green.opacity(0.8), lineWidth: 1.2))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .safeAreaPadding(.top, 56)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if model.gameState == .paused {
                PauseMenuView(model: model)
            }

            if model.showsLightRadialMenu {
                ZStack {
                    Color.black.opacity(0.72)
                        .ignoresSafeArea()
                        .onTapGesture { model.showsLightRadialMenu = false }

                    VStack(spacing: 18) {
                        VStack(spacing: 4) {
                            Text("⚡️ MINATO FLASH WARP")
                                .font(.title3.bold())
                                .foregroundStyle(.yellow)
                                .shadow(color: .yellow.opacity(0.8), radius: 8)
                            Text("Toca un Beacon de Luz activo para teletransportarte")
                                .font(.caption.bold())
                                .foregroundStyle(.white.opacity(0.8))
                        }

                        ZStack {
                            Circle()
                                .stroke(Color.yellow.opacity(0.4), lineWidth: 2)
                                .frame(width: 230, height: 230)

                            // ⚡ Centro: Indicador de Beacons
                            VStack(spacing: 2) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(.yellow)
                                Text("BEACONS")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            .frame(width: 60, height: 60)
                            .background(Color.black.opacity(0.55), in: Circle())
                            .overlay(Circle().stroke(Color.yellow.opacity(0.5), lineWidth: 1))

                            ForEach(Array(GameLightFixture.allCases.enumerated()), id: \.element) { index, fixture in
                                let angle: Double = Double(index) * (.pi / 2.0) - (.pi / 2.0)
                                let isEnabled = model.lightStates.isEnabled(fixture)

                                Button {
                                    model.showsLightRadialMenu = false
                                    if isEnabled {
                                        model.warpToLightFixture(fixture)
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: isEnabled ? "bolt.shield.fill" : "lightbulb.slash")
                                            .font(.system(size: 22, weight: .bold))
                                        Text(fixture.label)
                                            .font(.system(size: 10, weight: .bold))
                                            .multilineTextAlignment(.center)
                                    }
                                    .foregroundStyle(isEnabled ? .black : .white.opacity(0.4))
                                    .frame(width: 76, height: 76)
                                    .background(
                                        isEnabled ? AnyShapeStyle(Color.yellow) : AnyShapeStyle(Color.gray.opacity(0.35)),
                                        in: Circle()
                                    )
                                    .shadow(color: isEnabled ? .yellow.opacity(0.7) : .clear, radius: 10)
                                }
                                .offset(x: cos(angle) * 92, y: sin(angle) * 92)
                            }
                        }
                    }
                }
            }

            if model.isEditingHUDLayout {
                VStack {
                    if isHUDBarMinimized {
                        HStack(spacing: 10) {
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isHUDBarMinimized = false
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.down.circle.fill")
                                        .foregroundStyle(.cyan)
                                    Text("EXPANDIR EDITOR HUD")
                                        .font(.system(size: 11, weight: .black, design: .rounded))
                                        .foregroundStyle(.white)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                                .background(Color.black.opacity(0.75), in: Capsule())
                                .overlay(Capsule().stroke(Color.cyan.opacity(0.85), lineWidth: 1.5))
                            }

                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    model.isEditingHUDLayout = false
                                }
                            } label: {
                                Label("Guardar", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.cyan, in: Capsule())
                            }
                        }
                        .padding(.top, 10)
                        .shadow(color: .black.opacity(0.55), radius: 8)
                    } else {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "slider.horizontal.below.square.and.square.filled")
                                    .foregroundStyle(.cyan)
                                Text("EDITOR DE BOTONES HUD")
                                    .font(.system(size: 12, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)

                                Spacer()

                                Button {
                                    model.centerSelectedHUDElement(index: model.selectedHUDGroup)
                                } label: {
                                    Label("Centrar", systemImage: "scope")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(.yellow)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.yellow.opacity(0.18), in: Capsule())
                                }

                                Button {
                                    model.resetHUDLayout()
                                } label: {
                                    Label("Restaurar Todo", systemImage: "arrow.counterclockwise")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(.orange)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.orange.opacity(0.18), in: Capsule())
                                }

                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        isHUDBarMinimized = true
                                    }
                                } label: {
                                    Image(systemName: "chevron.up.circle.fill")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.85))
                                }

                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        model.isEditingHUDLayout = false
                                    }
                                } label: {
                                    Label("Guardar", systemImage: "checkmark.circle.fill")
                                        .font(.system(size: 11, weight: .black, design: .rounded))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.cyan, in: Capsule())
                                }
                            }

                            let groupNames = [
                                "🕹️ Joystick",
                                "🔦 Linterna",
                                "⚡ Láser",
                                "🛡️ Escudo",
                                "⬆️ Saltar",
                                "🎯 Acción",
                                "⏳ Slow-Mo",
                                "⚡ Warp",
                                "🗺️ Radar",
                                "⚙️ Menú",
                                "❤️ Salud"
                            ]

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(0..<groupNames.count, id: \.self) { idx in
                                        Button {
                                            model.selectedHUDGroup = idx
                                        } label: {
                                            Text(groupNames[idx])
                                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                                .foregroundStyle(model.selectedHUDGroup == idx ? .black : .white)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(
                                                    model.selectedHUDGroup == idx ? Color.cyan : Color.white.opacity(0.14),
                                                    in: Capsule()
                                                )
                                        }
                                    }
                                }
                            }

                            HStack(spacing: 12) {
                                Text("Ajustando: \(groupNames[min(max(model.selectedHUDGroup, 0), groupNames.count - 1)])")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.cyan)

                                Spacer()

                                let currentScaleBinding = Binding<Double>(
                                    get: {
                                        switch model.selectedHUDGroup {
                                        case 0: return model.hudJoystickScale
                                        case 1: return model.hudFlashlightScale
                                        case 2: return model.hudLaserScale
                                        case 3: return model.hudShieldScale
                                        case 4: return model.hudJumpScale
                                        case 5: return model.hudActionScale
                                        case 6: return model.hudSlowMoScale
                                        case 7: return model.hudWarpScale
                                        case 8: return model.hudMinimapScale
                                        case 9: return model.hudMenuScale
                                        default: return model.hudHealthScale
                                        }
                                    },
                                    set: { newVal in
                                        switch model.selectedHUDGroup {
                                        case 0: model.hudJoystickScale = newVal
                                        case 1: model.hudFlashlightScale = newVal
                                        case 2: model.hudLaserScale = newVal
                                        case 3: model.hudShieldScale = newVal
                                        case 4: model.hudJumpScale = newVal
                                        case 5: model.hudActionScale = newVal
                                        case 6: model.hudSlowMoScale = newVal
                                        case 7: model.hudWarpScale = newVal
                                        case 8: model.hudMinimapScale = newVal
                                        case 9: model.hudMenuScale = newVal
                                        default: model.hudHealthScale = newVal
                                        }
                                    }
                                )

                                let currentOpacityBinding = Binding<Double>(
                                    get: {
                                        switch model.selectedHUDGroup {
                                        case 0: return model.hudJoystickOpacity
                                        case 1: return model.hudFlashlightOpacity
                                        case 2: return model.hudLaserOpacity
                                        case 3: return model.hudShieldOpacity
                                        case 4: return model.hudJumpOpacity
                                        case 5: return model.hudActionOpacity
                                        case 6: return model.hudSlowMoOpacity
                                        case 7: return model.hudWarpOpacity
                                        case 8: return model.hudMinimapOpacity
                                        case 9: return model.hudMenuOpacity
                                        default: return model.hudHealthOpacity
                                        }
                                    },
                                    set: { newVal in
                                        switch model.selectedHUDGroup {
                                        case 0: model.hudJoystickOpacity = newVal
                                        case 1: model.hudFlashlightOpacity = newVal
                                        case 2: model.hudLaserOpacity = newVal
                                        case 3: model.hudShieldOpacity = newVal
                                        case 4: model.hudJumpOpacity = newVal
                                        case 5: model.hudActionOpacity = newVal
                                        case 6: model.hudSlowMoOpacity = newVal
                                        case 7: model.hudWarpOpacity = newVal
                                        case 8: model.hudMinimapOpacity = newVal
                                        case 9: model.hudMenuOpacity = newVal
                                        default: model.hudHealthOpacity = newVal
                                        }
                                    }
                                )

                                Text("Tamaño: \(Int(currentScaleBinding.wrappedValue * 100))%")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                                Slider(value: currentScaleBinding, in: 0.60...1.50, step: 0.05)
                                    .tint(.cyan)
                                    .frame(width: 110)

                                Text("Opacidad: \(Int(currentOpacityBinding.wrappedValue * 100))%")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                                Slider(value: currentOpacityBinding, in: 0.15...1.0, step: 0.05)
                                    .tint(.yellow)
                                    .frame(width: 85)
                            }
                        }
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .background(Color.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.cyan.opacity(0.75), lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.55), radius: 14, y: 6)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    }

                    Spacer()
                }
                .zIndex(999)
            }
            }
            }
            .background(Color.black)
            .sheet(isPresented: $model.showsMultiplayerSheet) {
                MultiplayerSettingsSheet(model: model)
            }
            .sheet(isPresented: $model.showsSettingsSheet) {
                GameOptionsSheet(model: model)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $model.showsAchievementsSheet) {
                NavigationStack {
                    AchievementsView(model: model)
                }
            }
            .fullScreenCover(isPresented: $model.showsPrologueScreen) {
                CinematicPrologueView(model: model)
            }
            .fullScreenCover(isPresented: $model.showsQuantumFuseBox) {
                QuantumFuseBoxView(model: model)
            }
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
            }
        }
    }
}

enum GameState: String {
    case mainMenu
    case playing
    case paused
}

@MainActor
final class GameModel: ObservableObject {
    let audio = ChiptuneAudioEngine()
    @Published var multiplayer = LocalMultiplayerSession()
    @Published var gameCenter = GameCenterManager()
    func updateAudioPauseState() {
        let shouldPause = (gameState != .playing) || showsSettingsSheet || showsMultiplayerSheet || isEditingHUDLayout || showsPrologueScreen
        audio.setPaused(shouldPause)
    }

    @Published var gameState: GameState = .mainMenu {
        didSet {
            updateAudioPauseState()
        }
    }
    @Published var showsSettingsSheet = false {
        didSet {
            updateAudioPauseState()
        }
    }
    @Published var showsMultiplayerSheet = false {
        didSet {
            updateAudioPauseState()
        }
    }

    @Published var cameraMode = GameCameraMode.firstPerson {
        didSet {
            if cameraMode != .firstPerson {
                cameraMode = .firstPerson
            }
        }
    }
    @Published var renderResolution = GameRenderResolution.balanced
    @Published var heldTool = GameHeldTool.flashlight {
        didSet {
            if heldTool != .laser {
                consecutiveLaserKills = 0
            }
            broadcastLocalState()
        }
    }
    private var isApplyingRemoteLightUpdate = false

    @Published var lightStates = GameLightStates() {
        didSet {
            guard !isApplyingRemoteLightUpdate else { return }
            broadcastLightStates()
        }
    }
    @Published private(set) var nearbyLight: GameLightFixture?
    @Published var showsFPS = false
    @Published var invertsCameraY = false
    @AppStorage("isLiquidGlassUIEnabled") var isLiquidGlassUIEnabled: Bool = true
    @Published var musicEnabled = true {
        didSet { audio.setMusicEnabled(musicEnabled) }
    }
    @Published var footstepsEnabled = true {
        didSet { audio.setEffectsEnabled(footstepsEnabled) }
    }
    @Published var waterSoundEnabled = true {
        didSet { audio.setWaterEnabled(waterSoundEnabled) }
    }
    @Published private(set) var framesPerSecond: Double = 0
    @Published var joystick = CGVector(dx: 0, dy: 0)
    @Published var shieldAngleOffset = CGVector(dx: 0, dy: 0)
    @Published private(set) var jumpRequestID = 0
    @Published private(set) var toolStatus = GameToolStatus()
    @Published var playerScore = 0
    @Published var isSlowMotionUnlocked: Bool = UserDefaults.standard.bool(forKey: "isSlowMotionUnlocked") {
        didSet { UserDefaults.standard.set(isSlowMotionUnlocked, forKey: "isSlowMotionUnlocked") }
    }
    @Published var isCampaignCompleted: Bool = UserDefaults.standard.bool(forKey: "isCampaignCompleted") {
        didSet { UserDefaults.standard.set(isCampaignCompleted, forKey: "isCampaignCompleted") }
    }
    var maxPlayerHealth: Float {
        isSlowMotionUnlocked ? 150.0 : 100.0
    }
    @Published var showsChronoLockBanner: Bool = false
    @Published var showsChronoCoreUnlockedBanner: Bool = false
    @Published var showsFlashlightGuideBanner: Bool = false
    @Published var showsCampaignVictoryModal: Bool = false
    @Published var showsQuantumFuseBox: Bool = false {
        didSet { updateAudioPauseState() }
    }
    @Published var isNearFuseTerminal: Bool = false
    @Published var playerHealth: Float = UserDefaults.standard.bool(forKey: "isSlowMotionUnlocked") ? 150.0 : 100.0
    @Published var playerShield: Float = 100.0
    private var lastDamageTime: TimeInterval = 0
    @Published var currentWave = 1
    @Published var botsRemainingInWave = 2
    @Published var totalBotsInWave = 2
    @Published var isWaveIntermission = false
    @Published var waveIntermissionTime: Float = 0
    @Published var isSlowMotionActive = false
    @Published var isCoverActive = false
    @Published private(set) var isNearCoverRock = false
    // Puerta Holográfica de Seguridad Arcoíris (Requiere 3,000 pts)
    @Published var isRainbowGateUnlocked: Bool = false
    @Published var isNearRainbowGate: Bool = false
    @Published var rainbowGateScoreNeeded: Int = 3000
    @Published var showsRainbowGateNotice: Bool = false
    @Published var recentlyUnlockedAchievement: GameAchievement? = nil
    @Published var showsAchievementsSheet: Bool = false
    var consecutiveLaserKills: Int = 0
    @Published var isDefeated = false
    @Published var isRecoveringInChamber = false
    @Published var inflationPumpsCount: Int = 0
    @Published var teammateRevivePumps: Int = 0
    @Published var isPumpingTeammateStroke: Bool = false
    private var lastPumpStrokeTime: TimeInterval = 0
    @Published var recoveryTimeRemaining: Float = 0
    @Published var isTeammateBoostingRecovery = false
    @Published var remotePlayerIsRecovering = false
    @Published var remotePlayerRecoveryTime: Float = 0
    @Published var isNearRecoveryConsole = false
    @Published var isTeamDefeated = false
    @Published var npcMaxHealths: [Float] = [80, 120, 180, 250, 350]
    @Published var npcHealths: [Float] = [80, 120, 180, 250, 350]
    @Published private(set) var respawnRequestID = 0
    @Published var showsLightRadialMenu = false

    // Marcador y rondas para Modo Versus 1v1
    @Published var versusLocalWins: Int = 0
    @Published var versusRemoteWins: Int = 0
    @Published var versusRound: Int = 1
    @Published var hasRecordedVersusRoundResult: Bool = false
    @Published var coopDeaths: Int = 0

    // Batería de linterna y láser, calor de espejo, gráficos y editor interactivo de HUD
    @Published var flashlightBattery: Float = 1.0
    @AppStorage("gameLanguagePreference") var selectedLanguagePreference: String = "auto"

    var effectiveLanguageCode: String {
        if selectedLanguagePreference != "auto" {
            return selectedLanguagePreference
        }
        for preferred in Locale.preferredLanguages {
            let code = String(preferred.prefix(2)).lowercased()
            if ["es", "en", "pt", "fr", "ja", "de", "hi", "it", "zh", "ko"].contains(code) {
                return code
            }
        }
        return "es"
    }

    var slang: GameSlang {
        GameSlang(languageCode: effectiveLanguageCode)
    }

    @Published var laserBattery: Float = 1.0
    @Published var mirrorHeat: Float = 0.0
    @Published var mirrorOverheated: Bool = false
    @Published var isMinimalHUDEnabled: Bool = false
    @AppStorage("touchControlsOpacity") var touchControlsOpacity: Double = 0.85
    @AppStorage("advancedReflectionsEnabled") var advancedReflectionsEnabled: Bool = true
    @AppStorage("targetFPS") var targetFPS: Int = 60
    @AppStorage("cameraSensitivity") var cameraSensitivity: Double = 1.0
    @Published var isEditingHUDLayout: Bool = false {
        didSet {
            updateAudioPauseState()
        }
    }
    @Published var selectedHUDGroup: Int = 0
    @AppStorage("hudJoystickX") var hudJoystickX: Double = 0
    @AppStorage("hudJoystickY") var hudJoystickY: Double = 0
    @AppStorage("hudJoystickScale") var hudJoystickScale: Double = 1.0
    @AppStorage("hudJoystickOpacity") var hudJoystickOpacity: Double = 0.85
    @AppStorage("hudFlashlightX") var hudFlashlightX: Double = 0
    @AppStorage("hudFlashlightY") var hudFlashlightY: Double = 0
    @AppStorage("hudFlashlightScale") var hudFlashlightScale: Double = 1.0
    @AppStorage("hudFlashlightOpacity") var hudFlashlightOpacity: Double = 0.85
    @AppStorage("hudLaserX") var hudLaserX: Double = 0
    @AppStorage("hudLaserY") var hudLaserY: Double = 0
    @AppStorage("hudLaserScale") var hudLaserScale: Double = 1.0
    @AppStorage("hudLaserOpacity") var hudLaserOpacity: Double = 0.85
    @AppStorage("hudShieldX") var hudShieldX: Double = 0
    @AppStorage("hudShieldY") var hudShieldY: Double = 0
    @AppStorage("hudShieldScale") var hudShieldScale: Double = 1.0
    @AppStorage("hudShieldOpacity") var hudShieldOpacity: Double = 0.85
    @AppStorage("hudActionX") var hudActionX: Double = 0
    @AppStorage("hudActionY") var hudActionY: Double = 0
    @AppStorage("hudActionScale") var hudActionScale: Double = 1.0
    @AppStorage("hudActionOpacity") var hudActionOpacity: Double = 0.85
    @AppStorage("hudWeaponsX") var hudWeaponsX: Double = 0
    @AppStorage("hudWeaponsY") var hudWeaponsY: Double = 0
    @AppStorage("hudWeaponsScale") var hudWeaponsScale: Double = 1.0
    @AppStorage("hudWeaponsOpacity") var hudWeaponsOpacity: Double = 0.85
    @AppStorage("hudJumpX") var hudJumpX: Double = 0
    @AppStorage("hudJumpY") var hudJumpY: Double = 0
    @AppStorage("hudJumpScale") var hudJumpScale: Double = 1.0
    @AppStorage("hudJumpOpacity") var hudJumpOpacity: Double = 0.85
    @AppStorage("hudSkillsX") var hudSkillsX: Double = 0
    @AppStorage("hudSkillsY") var hudSkillsY: Double = 0
    @AppStorage("hudSkillsScale") var hudSkillsScale: Double = 1.0
    @AppStorage("hudSkillsOpacity") var hudSkillsOpacity: Double = 0.85
    @AppStorage("hudSlowMoX") var hudSlowMoX: Double = 0
    @AppStorage("hudSlowMoY") var hudSlowMoY: Double = 0
    @AppStorage("hudSlowMoScale") var hudSlowMoScale: Double = 1.0
    @AppStorage("hudSlowMoOpacity") var hudSlowMoOpacity: Double = 0.85
    @AppStorage("hudWarpX") var hudWarpX: Double = 0
    @AppStorage("hudWarpY") var hudWarpY: Double = 0
    @AppStorage("hudWarpScale") var hudWarpScale: Double = 1.0
    @AppStorage("hudWarpOpacity") var hudWarpOpacity: Double = 0.85
    @AppStorage("hudMinimapX") var hudMinimapX: Double = 0
    @AppStorage("hudMinimapY") var hudMinimapY: Double = 0
    @AppStorage("hudMinimapScale") var hudMinimapScale: Double = 1.0
    @AppStorage("hudMinimapOpacity") var hudMinimapOpacity: Double = 0.90
    @AppStorage("hudMenuX") var hudMenuX: Double = 0
    @AppStorage("hudMenuY") var hudMenuY: Double = 0
    @AppStorage("hudMenuScale") var hudMenuScale: Double = 1.0
    @AppStorage("hudMenuOpacity") var hudMenuOpacity: Double = 0.90
    @AppStorage("hudHealthX") var hudHealthX: Double = 0
    @AppStorage("hudHealthY") var hudHealthY: Double = 0
    @AppStorage("hudHealthScale") var hudHealthScale: Double = 1.0
    @AppStorage("hudHealthOpacity") var hudHealthOpacity: Double = 0.90
    @AppStorage("hasSeenIntroPrologue") var hasSeenIntroPrologue: Bool = false
    @Published var showsPrologueScreen: Bool = false
    @Published var isGameControllerConnected: Bool = false
    @Published var gameControllerName: String = ""
    @AppStorage("duoScreenModeRaw") var duoScreenModeRaw: Int = 0
    @Published var selectedSquadMemberIndex: Int = 0
    @Published var remoteAgentsDict: [String: RemoteAgentState] = [:]

    var isDuoDevice: Bool {
        UIDevice.isDuoSupported
    }

    var duoScreenMode: DuoScreenMode {
        get { DuoScreenMode(rawValue: duoScreenModeRaw) ?? .off }
        set {
            duoScreenModeRaw = newValue.rawValue
            objectWillChange.send()
        }
    }

    var localPlayerDisplayName: String {
        if gameCenter.isInMatch {
            return gameCenter.localPlayerAlias
        }
        return multiplayer.localPeer.displayName
    }

    var allParticipantIDsSorted: [String] {
        var names = Set<String>([localPlayerDisplayName])
        for p in multiplayer.peers { names.insert(p.displayName) }
        for g in gameCenter.connectedPlayerNames { names.insert(g) }
        for k in remoteAgentsDict.keys { names.insert(k) }
        return names.sorted()
    }

    var localParticipantIndex: Int {
        allParticipantIDsSorted.firstIndex(of: localPlayerDisplayName) ?? 0
    }

    var isLocalTeamAlpha: Bool {
        if multiplayer.mode == .cooperative { return true }
        return localParticipantIndex % 2 == 0
    }

    func isPeerOnSameTeam(_ peerID: String) -> Bool {
        if multiplayer.mode == .cooperative { return true }
        let idx = allParticipantIDsSorted.firstIndex(of: peerID) ?? 1
        return (idx % 2 == 0) == isLocalTeamAlpha
    }

    private static let arenaTeamSpawns: [(SIMD3<Float>, Float)] = [
        (SIMD3<Float>( 3.8, 0,  3.8), Float.pi * 1.25),
        (SIMD3<Float>(-3.8, 0, -3.8), Float.pi * 0.25),
        (SIMD3<Float>( 6.4, 0,  5.2), Float.pi * 1.20),
        (SIMD3<Float>(-6.4, 0, -5.2), Float.pi * 0.20),
        (SIMD3<Float>(-8.2, 0, 26.0), Float.pi * 0.00),
        (SIMD3<Float>( 8.2, 0, 26.0), Float.pi * 0.00),
        (SIMD3<Float>(-8.2, 0, 52.0), Float.pi * 1.00),
        (SIMD3<Float>( 8.2, 0, 52.0), Float.pi * 1.00)
    ]

    var localSpawnPosition: SIMD3<Float> {
        let slot = localParticipantIndex % Self.arenaTeamSpawns.count
        return Self.arenaTeamSpawns[slot].0
    }

    var localSpawnYaw: Float {
        let slot = localParticipantIndex % Self.arenaTeamSpawns.count
        return Self.arenaTeamSpawns[slot].1
    }

    var sortedRemoteAgents: [RemoteAgentState] {
        let list = remoteAgentsDict.values.sorted { $0.peerID < $1.peerID }
        return list.map { agent in
            var copy = agent
            copy.isSameTeam = isPeerOnSameTeam(agent.peerID)
            return copy
        }
    }

    var squadMateCandidates: [RemoteAgentState] {
        let all = sortedRemoteAgents
        let sameTeam = all.filter { $0.isSameTeam }
        if !sameTeam.isEmpty { return sameTeam }
        if !all.isEmpty { return all }
        return [
            RemoteAgentState(
                peerID: "Escolta Táctico Alfa",
                position: localPlayerPosition + SIMD3<Float>(2.6, 0, -2.6),
                yaw: localPlayerYaw,
                isSameTeam: true
            )
        ]
    }

    var selectedSquadCameraAgent: RemoteAgentState {
        let candidates = squadMateCandidates
        let idx = max(0, min(candidates.count - 1, selectedSquadMemberIndex))
        return candidates[idx]
    }

    func cycleSquadCameraMember() {
        let count = max(1, squadMateCandidates.count)
        selectedSquadMemberIndex = (selectedSquadMemberIndex + 1) % count
    }

    func resetHUDLayout() {
        hudJoystickX = 0; hudJoystickY = 0; hudJoystickScale = 1.0; hudJoystickOpacity = 0.85
        hudFlashlightX = 0; hudFlashlightY = 0; hudFlashlightScale = 1.0; hudFlashlightOpacity = 0.85
        hudLaserX = 0; hudLaserY = 0; hudLaserScale = 1.0; hudLaserOpacity = 0.85
        hudShieldX = 0; hudShieldY = 0; hudShieldScale = 1.0; hudShieldOpacity = 0.85
        hudJumpX = 0; hudJumpY = 0; hudJumpScale = 1.0; hudJumpOpacity = 0.85
        hudActionX = 0; hudActionY = 0; hudActionScale = 1.0; hudActionOpacity = 0.85
        hudSlowMoX = 0; hudSlowMoY = 0; hudSlowMoScale = 1.0; hudSlowMoOpacity = 0.85
        hudWarpX = 0; hudWarpY = 0; hudWarpScale = 1.0; hudWarpOpacity = 0.85
        hudMinimapX = 0; hudMinimapY = 0; hudMinimapScale = 1.0; hudMinimapOpacity = 0.90
        hudMenuX = 0; hudMenuY = 0; hudMenuScale = 1.0; hudMenuOpacity = 0.90
        hudHealthX = 0; hudHealthY = 0; hudHealthScale = 1.0; hudHealthOpacity = 0.90
        hudWeaponsX = 0; hudWeaponsY = 0; hudWeaponsScale = 1.0; hudWeaponsOpacity = 0.85
        hudSkillsX = 0; hudSkillsY = 0; hudSkillsScale = 1.0; hudSkillsOpacity = 0.85
        touchControlsOpacity = 0.85
    }

    func centerSelectedHUDElement(index: Int) {
        switch index {
        case 0: hudJoystickX = 0; hudJoystickY = 0
        case 1: hudFlashlightX = 0; hudFlashlightY = 0
        case 2: hudLaserX = 0; hudLaserY = 0
        case 3: hudShieldX = 0; hudShieldY = 0
        case 4: hudJumpX = 0; hudJumpY = 0
        case 5: hudActionX = 0; hudActionY = 0
        case 6: hudSlowMoX = 0; hudSlowMoY = 0
        case 7: hudWarpX = 0; hudWarpY = 0
        case 8: hudMinimapX = 0; hudMinimapY = 0
        case 9: hudMenuX = 0; hudMenuY = 0
        default: hudHealthX = 0; hudHealthY = 0
        }
    }

    // Duelo de Luces (Luz vs Sombra / Captura del Núcleo en el Gran Salón Arcoíris)
    @Published var lightTeamScore: Int = 0
    @Published var shadowTeamScore: Int = 0
    @Published var hasEnergyCore: Bool = false
    @Published var remoteHasEnergyCore: Bool = false
    @Published var energyCorePosition: SIMD3<Float> = SIMD3<Float>(0, 0.85, 32.0)
    @Published var lightBattleRound: Int = 1
    @Published var lightBattleWinner: String? = nil

    func updateNPCHealths(_ healths: [Float]) {
        self.npcHealths = healths
    }
    @Published private(set) var warpRequestID = 0
    @Published private(set) var requestedWarpPosition = SIMD3<Float>.zero

    func updateWaveStatus(wave: Int, remaining: Int, total: Int, intermission: Bool, intermissionTime: Float) {
        let justEnteredIntermission = !self.isWaveIntermission && intermission
        let justEndedIntermission = self.isWaveIntermission && !intermission
        self.currentWave = wave
        self.botsRemainingInWave = remaining
        self.totalBotsInWave = total
        self.isWaveIntermission = intermission
        self.waveIntermissionTime = intermissionTime

        // 🏆 Progreso de Campaña en Game Center (1 al 15 = 100%)
        let progress = min(100.0, (Double(wave) / 15.0) * 100.0)
        gameCenter.reportProgress(id: "achievement_lumina_rescued", percent: progress)
        checkPhotonicOvercharge()

        // Si el jugador local estaba en la cámara de recuperación y la oleada se completó, auto-reanimar para el descanso
        if (justEnteredIntermission || justEndedIntermission || intermission) && isRecoveringInChamber {
            completeRecovery(wasRevivedByTeammate: true)
        }
    }

    func onQuantumPuzzleSolved() {
        guard !isSlowMotionUnlocked else { return }
        isSlowMotionUnlocked = true
        playerHealth = maxPlayerHealth
        audio.playLaserIgnition()
        audio.playLanding(intensity: 1.0)
        let notif = UINotificationFeedbackGenerator()
        notif.notificationOccurred(.success)
        gameCenter.unlockAchievement("achievement_quantum_puzzle")
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            showsChronoCoreUnlockedBanner = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            withAnimation {
                self?.showsChronoCoreUnlockedBanner = false
            }
        }
    }

    func onCampaignVictory() {
        isCampaignCompleted = true
        showsCampaignVictoryModal = true
        audio.playLaserReflectionSound()
        gameCenter.unlockAchievement("achievement_lumina_rescued")
        gameCenter.reportProgress(id: "achievement_lumina_rescued", percent: 100.0)
    }

    func checkPhotonicOvercharge() {
        guard currentWave >= 10, !isDefeated else { return }
        if lightStates.post && lightStates.piscinaNeon && lightStates.sheeritNeon && lightStates.poolStrips &&
           lightStates.postIntensity >= 0.95 && lightStates.piscinaNeonIntensity >= 0.95 &&
           lightStates.sheeritNeonIntensity >= 0.95 && lightStates.poolStripsIntensity >= 0.95 {
            gameCenter.unlockAchievement("achievement_photonic_overcharge")
        }
    }

    func toggleSlowMotion(fromNetwork: Bool = false) {
        if !fromNetwork && !isSlowMotionUnlocked {
            showsChronoLockBanner = true
            let notif = UINotificationFeedbackGenerator()
            notif.notificationOccurred(.warning)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
                withAnimation {
                    self?.showsChronoLockBanner = false
                }
            }
            return
        }

        isSlowMotionActive.toggle()
        audio.setSlowMotion(isSlowMotionActive)
        let impact = UIImpactFeedbackGenerator(style: isSlowMotionActive ? .heavy : .medium)
        impact.impactOccurred()

        if !fromNetwork && isAnyMultiplayerConnected {
            let pkt = LocalMatchPacket(
                kind: .slowMotion,
                peerID: multiplayer.localPeer.displayName,
                mode: multiplayer.mode,
                timestamp: Date().timeIntervalSince1970,
                isSlowMotion: isSlowMotionActive
            )
            if multiplayer.isConnected { multiplayer.send(pkt) }
            if gameCenter.isInMatch { gameCenter.sendPacket(pkt) }
        }
    }

    func toggleCover() {
        isCoverActive.toggle()
        audio.playLaserIgnition()
    }

    @Published var isUnderwater = false {
        didSet {
            audio.setUnderwaterZone(isUnderwater: isUnderwater)
        }
    }
    @Published private(set) var diveRequestID = 0

    func requestDive() {
        diveRequestID &+= 1
        audio.playSwimStrokeSound(intensity: 0.95)
    }

    func updateCoverStatus(isNear: Bool) {
        self.isNearCoverRock = isNear
        if !isNear && isCoverActive {
            isCoverActive = false
        }
    }

    func updateRainbowGateStatus(unlocked: Bool, current: Int, target: Int) {
        let wasUnlocked = isRainbowGateUnlocked
        isRainbowGateUnlocked = unlocked
        rainbowGateScoreNeeded = target
        let isNear = (current >= 0)
        isNearRainbowGate = isNear
        if !wasUnlocked && unlocked {
            showsRainbowGateNotice = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                self?.showsRainbowGateNotice = false
            }
        }
    }

    func warpToLightFixture(_ fixture: GameLightFixture) {
        let pos: SIMD3<Float> = switch fixture {
        case .post: SIMD3<Float>(-7.55, 0.2, 11.2)
        case .piscinaNeon: SIMD3<Float>(-7.70, 0.2, -15.8)
        case .sheeritNeon: SIMD3<Float>(6.20, 0.2, 15.8)
        case .poolStrips: SIMD3<Float>(-1.5, 0.2, -1.5)
        }
        warpRequestID += 1
        requestedWarpPosition = pos
        audio.playLaserIgnition()
    }

    @Published private(set) var resetRequestID = 0
    @Published var remotePlayerName: String = ""
    @Published var remotePlayerHealth: Float = 100.0
    @Published var remotePlayerShield: Float = 100.0
    @Published var remotePlayerScore: Int = 0
    @Published var remotePlayerPosition = SIMD3<Float>(-3.8, 0, 3.8)
    @Published var remotePlayerYaw: Float = .pi
    @Published var remotePlayerHeldTool: GameHeldTool = .laser
    @Published var remotePlayerIsFiringLaser: Bool = false
    @Published var showConnectedToast: Bool = false
    @Published private(set) var localPlayerPosition = SIMD3<Float>(3.8, 0, 3.8)
    @Published private(set) var localPlayerYaw: Float = .pi
    @Published var npcPositions: [SIMD3<Float>] = []
    @AppStorage("showsMinimap") var showsMinimap: Bool = true
    private var cancellables = Set<AnyCancellable>()

    var isAnyMultiplayerConnected: Bool {
        multiplayer.isConnected || gameCenter.isInMatch
    }

    var isHost: Bool {
        return localParticipantIndex == 0
    }

    var onRemoteNPCSyncReceived: (([SIMD3<Float>], [Float], Int, Int, Int, Bool, Float, [SIMD3<Float>]?, [SIMD3<Float>]?) -> Void)?
    var onRemoteNPCHitReceived: ((Int, Float) -> Void)?

    func broadcastEnemySync(
        positions: [SIMD3<Float>],
        healths: [Float],
        wave: Int,
        remaining: Int,
        total: Int,
        isIntermission: Bool,
        intermissionTime: Float,
        laserStarts: [SIMD3<Float>]? = nil,
        laserEnds: [SIMD3<Float>]? = nil
    ) {
        guard isAnyMultiplayerConnected && isHost else { return }
        let packet = LocalMatchPacket(
            kind: .enemySync,
            peerID: multiplayer.localPeer.displayName,
            timestamp: Date().timeIntervalSince1970,
            enemyPositions: positions,
            enemyHealths: healths,
            wave: wave,
            botsRemaining: remaining,
            totalBots: total,
            isIntermission: isIntermission,
            intermissionTime: intermissionTime,
            botLaserStarts: laserStarts,
            botLaserEnds: laserEnds
        )
        if multiplayer.isConnected {
            multiplayer.send(packet)
        }
        if gameCenter.isInMatch {
            gameCenter.sendPacket(packet)
        }
    }

    func sendBotDamageToClient(_ damage: Float) {
        guard isAnyMultiplayerConnected && isHost else { return }
        let packet = LocalMatchPacket(
            kind: .botDamage,
            peerID: multiplayer.localPeer.displayName,
            timestamp: Date().timeIntervalSince1970,
            hitDamage: damage
        )
        if multiplayer.isConnected {
            multiplayer.send(packet)
        }
        if gameCenter.isInMatch {
            gameCenter.sendPacket(packet)
        }
    }

    func sendScoreAwardToClient(_ points: Int) {
        guard isAnyMultiplayerConnected && isHost else { return }
        let packet = LocalMatchPacket(
            kind: .scoreAward,
            peerID: multiplayer.localPeer.displayName,
            timestamp: Date().timeIntervalSince1970,
            score: points
        )
        if multiplayer.isConnected {
            multiplayer.send(packet)
        }
        if gameCenter.isInMatch {
            gameCenter.sendPacket(packet)
        }
    }

    func sendEnemyHit(index: Int, damage: Float) {
        guard isAnyMultiplayerConnected && !isHost else { return }
        let packet = LocalMatchPacket(
            kind: .enemyHit,
            peerID: multiplayer.localPeer.displayName,
            timestamp: Date().timeIntervalSince1970,
            hitEnemyIndex: index,
            hitDamage: damage
        )
        if multiplayer.isConnected {
            multiplayer.send(packet)
        }
        if gameCenter.isInMatch {
            gameCenter.sendPacket(packet)
        }
    }

    func sendHitToRemotePlayer(damage: Float, targetPeerID: String? = nil) {
        guard isAnyMultiplayerConnected else { return }
        let packet = LocalMatchPacket(
            kind: .hit,
            peerID: localPlayerDisplayName,
            mode: multiplayer.mode,
            timestamp: Date().timeIntervalSince1970,
            health: playerHealth,
            score: playerScore,
            hitDamage: damage,
            targetPeerID: targetPeerID
        )
        if multiplayer.isConnected {
            multiplayer.send(packet)
        }
        if gameCenter.isInMatch {
            gameCenter.sendPacket(packet)
        }
    }

    var connectedPlayersCount: Int {
        max(1, allParticipantIDsSorted.count)
    }

    var activePeerDisplayName: String {
        let count = connectedPlayersCount
        if count > 2 {
            return "\(count) Jugadores (\(multiplayer.teamSize.shortLabel))"
        }
        if multiplayer.isConnected, let localPeer = multiplayer.peers.first?.displayName {
            return localPeer
        }
        if gameCenter.isInMatch, let gcPeer = gameCenter.connectedPlayerNames.first {
            return gcPeer
        }
        return remotePlayerName.isEmpty ? "Jugador 2" : remotePlayerName
    }

    init() {
        if !UIDevice.isDuoSupported {
            duoScreenModeRaw = 0 // Si no es un iPhone Duo, se asegura pantalla estándar normal
        }
        audio.start()
        updateAudioPauseState()

        gameCenter.onAchievementUnlocked = { [weak self] achievement in
            guard let self else { return }
            self.recentlyUnlockedAchievement = achievement
            self.audio.playLaserReflectionSound()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    if self?.recentlyUnlockedAchievement?.id == achievement.id {
                        self?.recentlyUnlockedAchievement = nil
                    }
                }
            }
        }

        // 🌟 Los reflejos Ray Tracing y el Vidrio Líquido son la identidad visual esencial del juego: siempre activos
        advancedReflectionsEnabled = true
        isLiquidGlassUIEnabled = true

        // Reenviar cambios de multiplayer y gameCenter a las vistas SwiftUI
        multiplayer.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        gameCenter.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        multiplayer.onConnected = { [weak self] in
            guard let self else { return }
            self.remotePlayerName = self.multiplayer.peers.first?.displayName ?? "Jugador 2"
            self.audio.playLaserIgnition()
            self.showConnectedToast = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                withAnimation(.easeOut(duration: 0.35)) {
                    self?.showConnectedToast = false
                }
            }
        }

        multiplayer.onPacketReceived = { [weak self] packet in
            self?.handleMultiplayerPacket(packet)
        }

        multiplayer.onPeerDisconnected = { [weak self] peerID in
            guard let self else { return }
            self.remoteAgentsDict.removeValue(forKey: peerID.displayName)
            if self.remotePlayerName == peerID.displayName {
                self.remotePlayerIsFiringLaser = false
                self.remotePlayerHeldTool = .flashlight
                if let nextPeer = self.multiplayer.peers.first?.displayName {
                    self.remotePlayerName = nextPeer
                } else {
                    self.remotePlayerName = ""
                }
            }
        }

        gameCenter.onPacketReceived = { [weak self] packet in
            self?.handleMultiplayerPacket(packet)
        }

        gameCenter.onMatchStarted = { [weak self] in
            guard let self else { return }
            self.remotePlayerName = self.gameCenter.connectedPlayerNames.first ?? "Jugador Game Center"
            self.audio.playLaserIgnition()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            self.startGame(fromNetwork: false)
        }

        setupGameControllers()
    }

    // MARK: - Game Controller Support (Mando Inalámbrico MFi / Xbox / PlayStation / Switch)
    func setupGameControllers() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let controller = notification.object as? GCController {
                self?.configureController(controller)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkConnectedControllers()
        }

        checkConnectedControllers()
    }

    private func checkConnectedControllers() {
        if let first = GCController.controllers().first {
            configureController(first)
        } else {
            isGameControllerConnected = false
            gameControllerName = ""
        }
    }

    private func configureController(_ controller: GCController) {
        isGameControllerConnected = true
        gameControllerName = controller.vendorName ?? "Mando Inalámbrico"

        if let gamepad = controller.extendedGamepad {
            gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
                DispatchQueue.main.async {
                    self?.joystick = CGVector(dx: CGFloat(x), dy: CGFloat(y))
                }
            }

            gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed {
                    DispatchQueue.main.async { self?.requestJump() }
                }
            }

            gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed {
                    DispatchQueue.main.async { self?.heldTool = (self?.heldTool == .laser ? .none : .laser) }
                }
            }

            gamepad.buttonY.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed {
                    DispatchQueue.main.async { self?.heldTool = (self?.heldTool == .flashlight ? .none : .flashlight) }
                }
            }

            gamepad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed {
                    DispatchQueue.main.async { self?.heldTool = (self?.heldTool == .mirror ? .none : .mirror) }
                }
            }

            gamepad.rightTrigger.valueChangedHandler = { [weak self] _, val, pressed in
                if pressed && val > 0.4 {
                    DispatchQueue.main.async {
                        if self?.heldTool != .laser { self?.heldTool = .laser }
                    }
                }
            }

            gamepad.leftTrigger.valueChangedHandler = { [weak self] _, val, pressed in
                if pressed && val > 0.4 {
                    DispatchQueue.main.async {
                        self?.heldTool = (self?.heldTool == .flashlight ? .none : .flashlight)
                    }
                }
            }

            gamepad.leftShoulder.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed {
                    DispatchQueue.main.async { self?.heldTool = (self?.heldTool == .mirror ? .none : .mirror) }
                }
            }

            gamepad.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed {
                    DispatchQueue.main.async { self?.toggleNearbyLight() }
                }
            }

            gamepad.rightThumbstickButton?.pressedChangedHandler = { [weak self] _, _, pressed in
                if pressed {
                    DispatchQueue.main.async { self?.toggleSlowMotion() }
                }
            }
        }
    }

    func broadcastLightStates() {
        guard isAnyMultiplayerConnected else { return }
        let packet = LocalMatchPacket(
            kind: .lightSync,
            peerID: multiplayer.localPeer.displayName,
            timestamp: Date().timeIntervalSince1970,
            lightStates: lightStates
        )
        if multiplayer.isConnected { multiplayer.send(packet) }
        if gameCenter.isInMatch { gameCenter.sendPacket(packet) }
    }

    private var lastLightScoreTick: TimeInterval = 0

    func updateLocalTransform(position: SIMD3<Float>, yaw: Float) {
        self.localPlayerPosition = position
        self.localPlayerYaw = yaw

        // 🍄 Capa de Escudo / Regeneración gradual (estilo Hongos Free Fire / Poción Fortnite)
        let now = Date().timeIntervalSince1970
        if now - lastDamageTime > 4.5 && playerShield < 100.0 && playerHealth > 0 && !isDefeated && !isRecoveringInChamber {
            playerShield = min(100.0, playerShield + 0.15)
        }

        // ☀️🌑 Mecánicas del Duelo de Luces (3 Pasos: 1. Prender/Apagar 4 Luces -> 2. Recoger Núcleo en Salón Arcoíris -> 3. Llevar a tu Base)
        if multiplayer.mode == .lightBattle && gameState == .playing && lightBattleWinner == nil {
            let isTeamLight = isLocalTeamAlpha
            let onCount = [lightStates.post, lightStates.piscinaNeon, lightStates.sheeritNeon, lightStates.poolStrips].filter { $0 }.count
            let offCount = 4 - onCount
            let myLightsReady = isTeamLight ? (onCount == 4) : (offCount == 4)

            // Si llevas el núcleo pero el rival saboteó una luz (ya no están las 4 de tu equipo), el núcleo regresa al centro
            if hasEnergyCore && !myLightsReady {
                hasEnergyCore = false
                audio.playLaserPlayerHitSound()
            }

            // Paso 2: Recoger el Núcleo en el centro de la piscina (0, 0.45, 0) SOLO cuando las 4 luces de tu equipo están listas
            let distToCore = simd_distance(position, energyCorePosition)
            if myLightsReady && distToCore < 2.4 && !hasEnergyCore && !remoteHasEnergyCore {
                hasEnergyCore = true
                audio.playLaserReflectionSound()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }

            // Paso 3: Llevar el Núcleo a tu Base para anotar 1 Captura (de 3 para ganar)
            if hasEnergyCore {
                let basePos = isTeamLight ? SIMD3<Float>(-7.55, 0.2, 12.65) : SIMD3<Float>(-7.0, 0.2, -15.5)
                if simd_distance(position, basePos) < 3.0 {
                    hasEnergyCore = false
                    audio.playLaserIgnition()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    if isTeamLight {
                        lightTeamScore += 1
                    } else {
                        shadowTeamScore += 1
                    }
                    // Reiniciar luces 2 encendidas / 2 apagadas para la siguiente ronda de captura
                    lightStates.post = true
                    lightStates.piscinaNeon = false
                    lightStates.sheeritNeon = true
                    lightStates.poolStrips = false

                    if lightTeamScore >= 3 && lightBattleWinner == nil {
                        lightBattleWinner = "☀️ ¡EQUIPO LUZ GANÓ EL DUELO (3/3 CAPTURAS)!"
                        audio.playLaserReflectionSound()
                    } else if shadowTeamScore >= 3 && lightBattleWinner == nil {
                        lightBattleWinner = "🌑 ¡EQUIPO SOMBRA GANÓ EL DUELO (3/3 CAPTURAS)!"
                        audio.playLaserReflectionSound()
                    }
                }
            }
        }
        broadcastLocalState()
    }

    func startSinglePlayerOrPrologue() {
        if !hasSeenIntroPrologue {
            showsPrologueScreen = true
        } else {
            startGame()
        }
    }

    func startGame(fromNetwork: Bool = false) {
        playerHealth = maxPlayerHealth
        playerShield = 100.0
        playerScore = 0
        remotePlayerHealth = 100.0
        remotePlayerShield = 100.0
        remotePlayerScore = 0
        currentWave = 1
        botsRemainingInWave = 2
        totalBotsInWave = 2
        isWaveIntermission = false
        heldTool = .flashlight
        remotePlayerHeldTool = .flashlight
        isSlowMotionActive = false
        audio.setSlowMotion(false)
        showsMultiplayerSheet = false
        isRecoveringInChamber = false
        recoveryTimeRemaining = 0
        heldTool = .flashlight
        isTeammateBoostingRecovery = false
        remotePlayerIsRecovering = false
        remotePlayerRecoveryTime = 0
        isTeamDefeated = false
        isDefeated = false

        if !fromNetwork && gameState == .mainMenu {
            versusLocalWins = 0
            versusRemoteWins = 0
            versusRound = 1
            coopDeaths = 0
            lightTeamScore = 0
            shadowTeamScore = 0
            hasEnergyCore = false
            remoteHasEnergyCore = false
            lightBattleWinner = nil
        }
        if isAnyMultiplayerConnected && multiplayer.mode == .lightBattle {
            // Iniciar Duelo de Luces con 2 luces encendidas y 2 apagadas (50/50 justo para ambos equipos)
            isApplyingRemoteLightUpdate = fromNetwork
            lightStates.post = true
            lightStates.piscinaNeon = false
            lightStates.sheeritNeon = true
            lightStates.poolStrips = false
            isApplyingRemoteLightUpdate = false
        } else {
            // Empezar con todas las luces apagadas para ir encendiendo progresivamente el Salón de la Piscina y el Mundo Arcoíris
            isApplyingRemoteLightUpdate = fromNetwork
            lightStates.turnOffAllLights()
            isApplyingRemoteLightUpdate = false
        }
        hasRecordedVersusRoundResult = false

        // Spawns distribuidos por escuadra en el Salón de la Piscina y Gran Salón Arcoíris
        let spawnPos = localSpawnPosition
        let spawnYaw = localSpawnYaw
        self.localPlayerPosition = spawnPos
        self.localPlayerYaw = spawnYaw
        self.remotePlayerPosition = isHost ? SIMD3<Float>(-3.8, 0, -3.8) : SIMD3<Float>(3.8, 0, 3.8)
        self.remotePlayerYaw = isHost ? Float.pi * 0.25 : Float.pi * 1.25

        resetRequestID += 1
        gameState = .playing
        triggerFlashlightGuideBanner()

        if !fromNetwork {
            let startPacket = LocalMatchPacket(
                kind: .start,
                peerID: localPlayerDisplayName,
                mode: multiplayer.mode,
                position: localPlayerPosition,
                yaw: localPlayerYaw,
                timestamp: Date().timeIntervalSince1970,
                health: playerHealth,
                score: playerScore,
                targetPeerID: nil,
                teamSizeRaw: multiplayer.teamSize.rawValue,
                versusRound: versusRound,
                versusLocalWins: versusLocalWins,
                versusRemoteWins: versusRemoteWins,
                shield: playerShield,
                coopDeaths: coopDeaths
            )
            if multiplayer.isConnected {
                remotePlayerName = multiplayer.peers.first?.displayName ?? "Jugador 2"
                multiplayer.send(startPacket)
            }
            if gameCenter.isInMatch {
                remotePlayerName = gameCenter.connectedPlayerNames.first ?? "Jugador Game Center"
                gameCenter.sendPacket(startPacket)
            }
        }
    }

    func startNextVersusRound(fromNetwork: Bool = false) {
        if !fromNetwork {
            versusRound += 1
        }
        hasRecordedVersusRoundResult = false
        playerHealth = maxPlayerHealth
        playerShield = 100.0
        remotePlayerHealth = 100.0
        remotePlayerShield = 100.0
        isDefeated = false
        isTeamDefeated = false
        heldTool = .flashlight
        remotePlayerHeldTool = .flashlight
        isSlowMotionActive = false
        audio.setSlowMotion(false)
        lightStates.turnOffAllLights()
        broadcastLocalState()

        let spawnPos = isHost ? SIMD3<Float>(3.8, 0, 3.8) : SIMD3<Float>(-3.8, 0, -3.8)
        let spawnYaw = isHost ? Float.pi * 1.25 : Float.pi * 0.25
        self.localPlayerPosition = spawnPos
        self.localPlayerYaw = spawnYaw
        self.remotePlayerPosition = isHost ? SIMD3<Float>(-3.8, 0, -3.8) : SIMD3<Float>(3.8, 0, 3.8)
        self.remotePlayerYaw = isHost ? Float.pi * 0.25 : Float.pi * 1.25

        resetRequestID += 1
        gameState = .playing
        triggerFlashlightGuideBanner()

        if !fromNetwork {
            let startPacket = LocalMatchPacket(
                kind: .start,
                peerID: multiplayer.localPeer.displayName,
                mode: multiplayer.mode,
                position: localPlayerPosition,
                yaw: localPlayerYaw,
                timestamp: Date().timeIntervalSince1970,
                health: playerHealth,
                score: playerScore,
                versusRound: versusRound,
                versusLocalWins: versusLocalWins,
                versusRemoteWins: versusRemoteWins,
                shield: playerShield,
                coopDeaths: coopDeaths
            )
            if multiplayer.isConnected {
                remotePlayerName = multiplayer.peers.first?.displayName ?? "Jugador 2"
                multiplayer.send(startPacket)
            }
            if gameCenter.isInMatch {
                remotePlayerName = gameCenter.connectedPlayerNames.first ?? "Jugador Game Center"
                gameCenter.sendPacket(startPacket)
            }
        }
    }

    func broadcastVersusRoundUpdate() {
        guard isAnyMultiplayerConnected else { return }
        let packet = LocalMatchPacket(
            kind: .state,
            peerID: multiplayer.localPeer.displayName,
            mode: multiplayer.mode,
            timestamp: Date().timeIntervalSince1970,
            health: playerHealth,
            score: playerScore,
            versusRound: versusRound,
            versusLocalWins: versusLocalWins,
            versusRemoteWins: versusRemoteWins,
            shield: playerShield,
            coopDeaths: coopDeaths,
            lightStates: nil,
            lightScore: lightTeamScore,
            shadowScore: shadowTeamScore,
            hasCore: hasEnergyCore
        )
        if multiplayer.isConnected { multiplayer.send(packet) }
        if gameCenter.isInMatch { gameCenter.sendPacket(packet) }
    }

    func handleMultiplayerPacket(_ packet: LocalMatchPacket) {
        if !packet.peerID.isEmpty && packet.peerID != localPlayerDisplayName {
            remotePlayerName = packet.peerID
            var entry = remoteAgentsDict[packet.peerID] ?? RemoteAgentState(
                peerID: packet.peerID,
                position: packet.position ?? SIMD3<Float>(-3.8, 0, 3.8),
                yaw: packet.yaw ?? .pi
            )
            if let pos = packet.position { entry.position = pos }
            if let y = packet.yaw { entry.yaw = y }
            if let t = packet.tool { entry.heldToolRaw = t }
            if let h = packet.health { entry.health = h }
            if let s = packet.shield { entry.shield = s }
            if let sc = packet.score { entry.score = sc }
            if let isRec = packet.isRecovering { entry.isRecovering = isRec }
            if let prog = packet.recoveryProgress { entry.recoveryProgress = prog }
            if let hasC = packet.hasCore { entry.hasCore = hasC }
            if let isFiring = packet.isFiringLaser {
                entry.isFiringLaser = isFiring
                self.remotePlayerIsFiringLaser = isFiring
            } else {
                entry.isFiringLaser = false
                self.remotePlayerIsFiringLaser = false
            }
            entry.isSameTeam = isPeerOnSameTeam(packet.peerID)
            remoteAgentsDict[packet.peerID] = entry
        }
        if let tsRaw = packet.teamSizeRaw, let ts = MatchTeamSize(rawValue: tsRaw) {
            multiplayer.teamSize = ts
        }
        switch packet.kind {
        case .start:
            if let m = packet.mode {
                multiplayer.mode = m
            }
            if let pos = packet.position {
                remotePlayerPosition = pos
            }
            if let y = packet.yaw {
                remotePlayerYaw = y
            }
            if let vr = packet.versusRound {
                self.versusRound = vr
            }
            if let vlw = packet.versusLocalWins, let vrw = packet.versusRemoteWins {
                self.versusRemoteWins = vlw
                self.versusLocalWins = vrw
            }
            if let s = packet.shield {
                self.remotePlayerShield = s
            }
            if let cd = packet.coopDeaths {
                self.coopDeaths = max(self.coopDeaths, cd)
            }
            if multiplayer.mode == .versus {
                startNextVersusRound(fromNetwork: true)
            } else {
                startGame(fromNetwork: true)
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)

        case .controllerInput:
            if let jx = packet.joystickX, let jy = packet.joystickY {
                self.joystick = CGVector(dx: CGFloat(jx), dy: CGFloat(jy))
            }
            if packet.jumpPressed == true {
                self.requestJump()
            }
            if let toolIndex = packet.tool, let newTool = GameHeldTool(rawValue: toolIndex) {
                self.heldTool = newTool
            }

        case .state:
            if let vr = packet.versusRound {
                self.versusRound = vr
            }
            if let vlw = packet.versusLocalWins, let vrw = packet.versusRemoteWins {
                self.versusRemoteWins = vlw
                self.versusLocalWins = vrw
            }
            if let s = packet.shield {
                self.remotePlayerShield = s
            }
            if let cd = packet.coopDeaths {
                self.coopDeaths = max(self.coopDeaths, cd)
            }
            if let ls = packet.lightStates, ls != self.lightStates {
                isApplyingRemoteLightUpdate = true
                self.lightStates = ls
                isApplyingRemoteLightUpdate = false
            }
            if let lScore = packet.lightScore {
                self.lightTeamScore = max(self.lightTeamScore, lScore)
                if self.lightTeamScore >= 3 && self.lightBattleWinner == nil {
                    self.lightBattleWinner = "☀️ ¡EQUIPO LUZ GANÓ EL DUELO (3/3 CAPTURAS)!"
                }
            }
            if let sScore = packet.shadowScore {
                self.shadowTeamScore = max(self.shadowTeamScore, sScore)
                if self.shadowTeamScore >= 3 && self.lightBattleWinner == nil {
                    self.lightBattleWinner = "🌑 ¡EQUIPO SOMBRA GANÓ EL DUELO (3/3 CAPTURAS)!"
                }
            }
            if let hasC = packet.hasCore {
                self.remoteHasEnergyCore = hasC
            }
            if let h = packet.health {
                self.remotePlayerHealth = h
                if (multiplayer.mode == .versus || multiplayer.mode == .lightBattle) && h <= 0 && !hasRecordedVersusRoundResult {
                    hasRecordedVersusRoundResult = true
                    self.versusLocalWins += 1
                }
            }
            if let s = packet.score {
                self.remotePlayerScore = s
            }
            if let pos = packet.position {
                self.remotePlayerPosition = pos
            }
            if let y = packet.yaw {
                self.remotePlayerYaw = y
            }
            if let t = packet.tool, let remoteTool = GameHeldTool(rawValue: t) {
                self.remotePlayerHeldTool = remoteTool
            }
            if let sm = packet.isSlowMotion, self.isSlowMotionActive != sm {
                self.isSlowMotionActive = sm
                self.audio.setSlowMotion(sm)
            }
            if let isRec = packet.isRecovering {
                self.remotePlayerIsRecovering = isRec
                if let prog = packet.recoveryProgress {
                    self.remotePlayerRecoveryTime = max(0, 5.0 * (1.0 - prog))
                }
                if isRec && self.isRecoveringInChamber {
                    self.triggerTeamDefeat()
                }
            }

        case .reviveProgress:
            if self.isRecoveringInChamber {
                let progress = packet.recoveryProgress ?? 0.0
                self.recoveryTimeRemaining = max(0.0, 5.0 * (1.0 - progress))
                self.isTeammateBoostingRecovery = true
                self.inflationPumpsCount = Int((progress * 5.0).rounded())
                self.audio.playAirPumpStrokeSound()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }

        case .reviveTeammate:
            if self.isRecoveringInChamber {
                self.completeRecovery(wasRevivedByTeammate: true)
            }

        case .teamDefeat:
            self.triggerTeamDefeat(fromNetwork: true)

        case .teamRestart:
            self.restartCooperativeMatch(fromNetwork: true)

        case .slowMotion:
            if let sm = packet.isSlowMotion, self.isSlowMotionActive != sm {
                self.isSlowMotionActive = sm
                self.audio.setSlowMotion(sm)
                let impact = UIImpactFeedbackGenerator(style: sm ? .heavy : .medium)
                impact.impactOccurred()
            }

        case .hit, .laser:
            // Si el disparo iba dirigido a un jugador específico en una sala de 4v4 y no somos nosotros, ignorar
            if let targetID = packet.targetPeerID, !targetID.isEmpty, targetID != localPlayerDisplayName {
                return
            }
            if multiplayer.mode == .versus || multiplayer.mode == .lightBattle {
                if hasEnergyCore {
                    hasEnergyCore = false // Suelta el núcleo al recibir un impacto de láser
                    audio.playLaserReflectionSound()
                }
                if heldTool == .mirror {
                    // Escudo Espejo bloquea el ataque y lo refleja de vuelta al rival que nos disparó
                    audio.playLaserReflectionSound()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    sendHitToRemotePlayer(damage: 25.0, targetPeerID: packet.peerID)
                } else {
                    let dmg = packet.hitDamage ?? 15.0
                    takeDamage(dmg, broadcast: true)
                    audio.playLaserPlayerHitSound()
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                }
            } else {
                // En modo Cooperativo: fuego amigo desactivado (sin daño, sin curación infinita ni puntos anómalos)
            }

        case .lightSync:
            if let ls = packet.lightStates, ls != self.lightStates {
                isApplyingRemoteLightUpdate = true
                self.lightStates = ls
                isApplyingRemoteLightUpdate = false
            }

        case .enemySync:
            if !isHost {
                if let positions = packet.enemyPositions,
                   let healths = packet.enemyHealths,
                   let wave = packet.wave,
                   let remaining = packet.botsRemaining,
                   let total = packet.totalBots {
                    let intermission = packet.isIntermission ?? false
                    let intermissionTime = packet.intermissionTime ?? 0
                    self.npcPositions = positions
                    self.npcHealths = healths
                    self.currentWave = wave
                    self.botsRemainingInWave = remaining
                    self.totalBotsInWave = total
                    self.isWaveIntermission = intermission
                    self.waveIntermissionTime = intermissionTime
                    onRemoteNPCSyncReceived?(positions, healths, wave, remaining, total, intermission, intermissionTime, packet.botLaserStarts, packet.botLaserEnds)
                }
            }

        case .botDamage:
            if !isHost {
                let dmg = packet.hitDamage ?? 15.0
                takeDamage(dmg, broadcast: true)
                audio.playLaserPlayerHitSound()
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }

        case .scoreAward:
            if !isHost {
                let pts = packet.score ?? 250
                addScore(pts)
                audio.playLaserReflectionSound()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }

        case .enemyHit:
            if isHost {
                if let botIndex = packet.hitEnemyIndex, let damage = packet.hitDamage {
                    onRemoteNPCHitReceived?(botIndex, damage)
                }
            }

        case .hello:
            broadcastLocalState()
            broadcastLightStates()
        }
    }

    func broadcastLocalState() {
        guard isAnyMultiplayerConnected else { return }
        let pkt = LocalMatchPacket(
            kind: .state,
            peerID: multiplayer.localPeer.displayName,
            mode: multiplayer.mode,
            position: localPlayerPosition,
            yaw: localPlayerYaw,
            tool: heldTool.rawValue,
            timestamp: Date().timeIntervalSince1970,
            health: playerHealth,
            score: playerScore,
            isSlowMotion: isSlowMotionActive,
            isFiringLaser: (heldTool == .laser && toolStatus.activeRemaining > 0),
            isRecovering: isRecoveringInChamber,
            recoveryProgress: isRecoveringInChamber ? max(0, min(1.0, 1.0 - recoveryTimeRemaining / 5.0)) : 1.0,
            versusRound: versusRound,
            versusLocalWins: versusLocalWins,
            versusRemoteWins: versusRemoteWins,
            shield: playerShield,
            coopDeaths: coopDeaths,
            lightStates: nil,
            lightScore: lightTeamScore,
            shadowScore: shadowTeamScore,
            hasCore: hasEnergyCore
        )
        if multiplayer.isConnected {
            multiplayer.send(pkt)
        }
        if gameCenter.isInMatch {
            gameCenter.sendPacket(pkt)
        }
    }

    func returnToMainMenu() {
        playerHealth = maxPlayerHealth
        playerScore = 0
        currentWave = 1
        botsRemainingInWave = 2
        totalBotsInWave = 2
        isWaveIntermission = false
        heldTool = .flashlight
        isSlowMotionActive = false
        audio.setSlowMotion(false)
        resetRequestID += 1
        gameState = .mainMenu
    }

    func togglePause() {
        if gameState == .playing {
            gameState = .paused
        } else if gameState == .paused {
            gameState = .playing
        }
    }

    func addScore(_ points: Int) {
        playerScore += points
        broadcastLocalState()
        if points >= 250 && heldTool == .laser && laserBattery > 0.05 {
            consecutiveLaserKills += 1
            if consecutiveLaserKills >= 3 {
                gameCenter.unlockAchievement("achievement_efficient_battery")
            }
        }
    }

    func takeDamage(_ damage: Float, broadcast: Bool = true) {
        lastDamageTime = Date().timeIntervalSince1970
        if damage < 0 {
            // Curación: primero vida hasta maxPlayerHealth, luego recarga el escudo
            let healAmount = -damage
            let missingHealth = maxPlayerHealth - playerHealth
            if healAmount <= missingHealth {
                playerHealth += healAmount
            } else {
                playerHealth = maxPlayerHealth
                playerShield = min(100.0, playerShield + (healAmount - missingHealth))
            }
        } else {
            // Daño: absorbe primero el escudo azul (estilo Free Fire / Fortnite)
            if playerShield > 0 {
                if playerShield >= damage {
                    playerShield -= damage
                } else {
                    let remainder = damage - playerShield
                    playerShield = 0
                    playerHealth = max(0, playerHealth - remainder)
                }
            } else {
                playerHealth = max(0, playerHealth - damage)
            }
        }
        if broadcast {
            broadcastLocalState()
        }
        if playerHealth <= 0 && !isDefeated && !isRecoveringInChamber {
            isSlowMotionActive = false
            audio.setSlowMotion(false)
            if isAnyMultiplayerConnected && multiplayer.mode == .cooperative {
                coopDeaths += 1
                broadcastLocalState()
                if remotePlayerIsRecovering {
                    triggerTeamDefeat(fromNetwork: false)
                } else {
                    enterRecoveryChamber()
                }
            } else if isAnyMultiplayerConnected && multiplayer.mode == .versus {
                isDefeated = true
                isTeamDefeated = false
                heldTool = .none
                joystick = .zero
                nearbyLight = nil
                audio.stopAllNonMusicEffects()
                audio.playSlimeDeflateSound()
                if !hasRecordedVersusRoundResult {
                    hasRecordedVersusRoundResult = true
                    versusRemoteWins += 1
                    broadcastVersusRoundUpdate()
                }
            } else {
                // Modo Solitario: ¡Derrota Directa / Game Over! Sin auto-revivir para mantener el reto
                isDefeated = true
                isTeamDefeated = false
                heldTool = .none
                joystick = .zero
                nearbyLight = nil
                audio.stopAllNonMusicEffects()
                audio.playSlimeDeflateSound()
                audio.playRobloxOofDefeatSound()
            }
        }
    }

    func enterRecoveryChamber() {
        guard !isRecoveringInChamber else { return }
        isSlowMotionActive = false
        audio.setSlowMotion(false)
        isRecoveringInChamber = true
        inflationPumpsCount = 0
        teammateRevivePumps = 0
        recoveryTimeRemaining = 5.0
        playerHealth = 0
        playerShield = 0
        heldTool = .none
        audio.playSlimeDeflateSound()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

        // 🌟 CERO TELETRANSPORTACIÓN: El jugador se queda exactamente donde cayó en el suelo
        broadcastLocalState()
    }

    func performAirPumpStroke() {
        // En cooperativo, únicamente el compañero vivo bombea aire para revivirte
    }

    func updateRecoveryProgress(remaining: Float, isBoosting: Bool) {
        self.recoveryTimeRemaining = remaining
        self.isTeammateBoostingRecovery = isBoosting
    }

    func completeRecovery(wasRevivedByTeammate: Bool = false) {
        guard isRecoveringInChamber else { return }
        isRecoveringInChamber = false
        inflationPumpsCount = 0
        teammateRevivePumps = 0
        playerHealth = maxPlayerHealth
        playerShield = 100.0
        recoveryTimeRemaining = 0
        heldTool = .flashlight
        isTeammateBoostingRecovery = false
        audio.playBalloonBouncePopSound()
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // El jugador se levanta en su misma posición con salto elástico
        localPlayerPosition.y = max(localPlayerPosition.y, 0.45)
        broadcastLocalState()
    }

    func pumpTeammateAir(fromIntermission: Bool = false) {
        guard isAnyMultiplayerConnected, remotePlayerIsRecovering else { return }
        if !fromIntermission {
            guard isNearRecoveryConsole else { return }
        }
        let now = Date().timeIntervalSince1970
        guard now - lastPumpStrokeTime >= 0.95 else { return } // Mínimo 1s por bombeo -> 5 segundos total
        lastPumpStrokeTime = now

        isPumpingTeammateStroke = true
        teammateRevivePumps += 1
        audio.playAirPumpStrokeSound()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        let progress = Float(teammateRevivePumps) / 5.0
        let pkt = LocalMatchPacket(
            kind: .reviveProgress,
            peerID: multiplayer.localPeer.displayName,
            mode: multiplayer.mode,
            timestamp: now,
            recoveryProgress: progress
        )
        if multiplayer.isConnected { multiplayer.send(pkt) }
        if gameCenter.isInMatch { gameCenter.sendPacket(pkt) }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.isPumpingTeammateStroke = false
        }

        if teammateRevivePumps >= 5 {
            teammateRevivePumps = 0
            playerScore += 200
            gameCenter.unlockAchievement("achievement_coop_revive")
            let finishPkt = LocalMatchPacket(
                kind: .reviveTeammate,
                peerID: multiplayer.localPeer.displayName,
                mode: multiplayer.mode,
                timestamp: now
            )
            if multiplayer.isConnected { multiplayer.send(finishPkt) }
            if gameCenter.isInMatch { gameCenter.sendPacket(finishPkt) }
            remotePlayerIsRecovering = false
            remotePlayerRecoveryTime = 0
            remotePlayerHealth = 100.0
            remotePlayerShield = 100.0
            audio.playBalloonBouncePopSound()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    func reviveTeammate(fromIntermission: Bool = false) {
        pumpTeammateAir(fromIntermission: fromIntermission)
    }

    func triggerTeamDefeat(fromNetwork: Bool = false) {
        guard !isDefeated else { return }
        isDefeated = true
        isTeamDefeated = true
        isRecoveringInChamber = false
        remotePlayerIsRecovering = false
        heldTool = .none
        isSlowMotionActive = false
        audio.setSlowMotion(false)
        audio.playRobloxOofDefeatSound()

        if !fromNetwork && isAnyMultiplayerConnected {
            let packet = LocalMatchPacket(
                kind: .teamDefeat,
                peerID: multiplayer.localPeer.displayName,
                mode: multiplayer.mode,
                timestamp: Date().timeIntervalSince1970
            )
            if multiplayer.isConnected { multiplayer.send(packet) }
            if gameCenter.isInMatch { gameCenter.sendPacket(packet) }
        }
    }

    func restartCooperativeMatch(fromNetwork: Bool = false) {
        playerHealth = maxPlayerHealth
        playerShield = 100.0
        playerScore = 0
        remotePlayerHealth = 100.0
        remotePlayerShield = 100.0
        remotePlayerScore = 0
        isDefeated = false
        isTeamDefeated = false
        isRecoveringInChamber = false
        remotePlayerIsRecovering = false
        recoveryTimeRemaining = 0
        currentWave = 1
        botsRemainingInWave = 2
        totalBotsInWave = 2
        isWaveIntermission = false
        heldTool = .flashlight
        remotePlayerHeldTool = .flashlight
        joystick = .zero
        isSlowMotionActive = false
        audio.setSlowMotion(false)
        lightStates.turnOffAllLights()
        broadcastLocalState()
        resetRequestID &+= 1
        respawnRequestID &+= 1
        updateAudioPauseState()

        if !fromNetwork && isAnyMultiplayerConnected {
            let packet = LocalMatchPacket(
                kind: .teamRestart,
                peerID: multiplayer.localPeer.displayName,
                mode: multiplayer.mode,
                timestamp: Date().timeIntervalSince1970
            )
            if multiplayer.isConnected { multiplayer.send(packet) }
            if gameCenter.isInMatch { gameCenter.sendPacket(packet) }
        }
    }

    func respawnPlayer() {
        playerHealth = maxPlayerHealth
        playerShield = 100.0
        playerScore = 0
        isDefeated = false
        isTeamDefeated = false
        isRecoveringInChamber = false
        remotePlayerIsRecovering = false
        recoveryTimeRemaining = 0
        heldTool = .flashlight
        joystick = .zero
        currentWave = 1
        botsRemainingInWave = 2
        totalBotsInWave = 2
        isWaveIntermission = false
        isSlowMotionActive = false
        audio.setSlowMotion(false)
        lightStates.turnOffAllLights()
        broadcastLocalState()
        resetRequestID &+= 1
        respawnRequestID &+= 1
        updateAudioPauseState()
        triggerFlashlightGuideBanner()
    }

    func triggerFlashlightGuideBanner() {
        showsFlashlightGuideBanner = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        audio.playLaserIgnition()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
            withAnimation {
                self?.showsFlashlightGuideBanner = false
            }
        }
    }

    func requestJump() {
        jumpRequestID &+= 1
    }

    func cycleHeldTool() {
        let tools: [GameHeldTool] = [.none, .flashlight, .laser, .mirror]
        let currentIndex = tools.firstIndex(of: heldTool) ?? 0
        heldTool = tools[(currentIndex + 1) % tools.count]
    }

    func toggleNearbyLight() {
        guard let nearbyLight else { return }
        lightStates.toggle(nearbyLight)
        checkPhotonicOvercharge()
        broadcastLocalState()
    }

    func toggleAllLights() {
        lightStates.toggleAllLights()
        checkPhotonicOvercharge()
        broadcastLocalState()
    }

    func setLightIntensity(_ value: Float, for fixture: GameLightFixture) {
        lightStates.setIntensity(value, for: fixture)
        checkPhotonicOvercharge()
    }

    func reportNearbyLight(_ fixture: GameLightFixture?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.isDefeated || self.isRecoveringInChamber {
                if self.nearbyLight != nil {
                    self.nearbyLight = nil
                }
                return
            }
            guard self.nearbyLight != fixture else { return }
            self.nearbyLight = fixture
        }
    }

    func reportFPS(_ value: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.framesPerSecond = value
        }
    }

    func reportToolStatus(_ status: GameToolStatus) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.toolStatus != status {
                self.toolStatus = status
                if self.heldTool == .mirror && status.activeRemaining <= 0 && status.cooldownRemaining > 0 {
                    self.heldTool = .none
                }
            }
        }
    }
}

struct LightDimmerPopover: View {
    let fixture: GameLightFixture
    @ObservedObject var model: GameModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(Color.cyan)
                Text(fixture.label)
                    .font(.headline)
                Spacer()
                Text("\(Int((model.lightStates.intensity(fixture) * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.cyan)
            }
            Slider(
                value: Binding(
                    get: { Double(model.lightStates.intensity(fixture)) },
                    set: { model.setLightIntensity(Float($0), for: fixture) }
                ),
                in: 0.1...1
            )
            .tint(.cyan)
        }
        .padding(14)
        .frame(width: 260)
        .presentationCompactAdaptation(.popover)
    }
}



#if LEGACY_SCENEKIT_RENDERER
struct GameSceneView: UIViewRepresentable {
    @ObservedObject var model: GameModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = UIColor(red: 0.015, green: 0.02, blue: 0.035, alpha: 1)
        view.isOpaque = true
        view.scene = context.coordinator.scene
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = false
        view.isPlaying = true
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 60
        view.contentScaleFactor = model.renderResolution.scale
        view.antialiasingMode = .multisampling2X
        view.pointOfView = context.coordinator.camera

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleCameraPan(_:))
        )
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = false
        view.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleSceneTap(_:))
        )
        tap.cancelsTouchesInView = false
        tap.require(toFail: pan)
        view.addGestureRecognizer(tap)

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.resetCamera)
        )
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        tap.require(toFail: doubleTap)
        view.addGestureRecognizer(doubleTap)

        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.contentScaleFactor = model.renderResolution.scale
        context.coordinator.advancedReflectionsEnabled = model.advancedReflectionsEnabled
        context.coordinator.setCameraMode(model.cameraMode)
        context.coordinator.setEquipment(
            heldTool: model.heldTool,
            lightStates: model.lightStates
        )
        context.coordinator.joystick = model.joystick
        context.coordinator.receiveJumpRequest(model.jumpRequestID)
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        private enum PhysicsCategory {
            static let player = 1 << 0
            static let world = 1 << 1
            static let cameraBlocker = 1 << 2
        }

        private enum RenderCategory {
            static let mirrorFixture = 1 << 10
        }

        let scene = SCNScene()
        let camera = SCNNode()

        weak var renderer: SCNView?
        var advancedReflectionsEnabled = false
        var joystick = CGVector(dx: 0, dy: 0)

        private let player = SCNNode()
        private let playerVisual = SCNNode()
        private let water = WaterSurface()
        private let audio: ChiptuneAudioEngine
        private var mirrorMaterial: SCNMaterial?
        private var mirrorNode: SCNNode?
        private var mirrorFrameMaterial: SCNMaterial?
        private var poolCopingMaterial: SCNMaterial?
        private var stoneMaterials: [SCNMaterial] = []
        private var sceneMaterials: [SCNMaterial] = []
        private var lampLight: SCNLight?
        private var ambientLight: SCNLight?
        private var fixedLightMaterials: [(material: SCNMaterial, onColor: UIColor, fixture: GameLightFixture)] = []
        private var neonLights: [(light: SCNLight, fixture: GameLightFixture)] = []
        private var mirrorBounceLight: SCNLight?
        private var flashlightLight: SCNLight?
        private let laserBeamNode = SCNNode()
        private let laserDotNode = SCNNode()
        private let mirrorCamera = SCNNode()
        private var mirrorRenderer: SCNRenderer?
        private var mirrorCommandQueue: MTLCommandQueue?
        private var mirrorColorTexture: MTLTexture?
        private var mirrorDepthTexture: MTLTexture?
        private var lastMirrorRenderTime: TimeInterval = 0
        private var lastUpdate: TimeInterval = 0
        private var lastWaterUpdate: TimeInterval = 0
        private var footstepCountdown: Float = 0
        private var waterStepCountdown: Float = 0
        private var appliedReflectionMode: Bool?
        private var cameraYaw: Float = 0
        private var cameraPitch: Float = 0.38
        private var firstPersonPitch: Float = 0
        private var cameraMode = GameCameraMode.thirdPerson
        private var heldTool = GameHeldTool.flashlight
        private var lightStates = GameLightStates()
        private var lastNearbyLight: GameLightFixture?
        private var hasReportedNearbyLight = false
        private var smoothedCameraTarget = SCNVector3Zero
        private var hasSmoothedCameraTarget = false
        private var playerFacingYaw: Float = .pi
        private var handledJumpRequestID = 0
        private var jumpQueued = false
        private var fpsFrameCount = 0
        private var fpsStartTime: TimeInterval = 0
        private var onFPSUpdate: ((Double) -> Void)?
        private var onNearbyLightUpdate: ((GameLightFixture?) -> Void)?

        init(model: GameModel) {
            audio = model.audio
            super.init()
            advancedReflectionsEnabled = model.advancedReflectionsEnabled
            onFPSUpdate = { [weak model] framesPerSecond in
                guard model?.showsFPS == true else { return }
                model?.reportFPS(framesPerSecond)
            }
            onNearbyLightUpdate = { [weak model] fixture in
                model?.reportNearbyLight(fixture)
            }
            buildScene()
        }

        func attach(to view: SCNView) {
            renderer = view
            view.delegate = self
            configureMirrorRenderer(for: view)
            applyReflectionMode(enabled: advancedReflectionsEnabled)
        }

        @objc func handleCameraPan(_ gesture: UIPanGestureRecognizer) {
            guard let view = renderer else { return }
            let translation = gesture.translation(in: view)
            cameraYaw += Float(translation.x) * 0.0075
            if cameraMode == .firstPerson {
                firstPersonPitch = max(-1.35, min(1.35, firstPersonPitch - Float(translation.y) * 0.0045))
            } else {
                cameraPitch = max(-1.10, min(1.25, cameraPitch - Float(translation.y) * 0.0045))
            }
            gesture.setTranslation(.zero, in: view)
        }

        @objc func handleSceneTap(_ gesture: UITapGestureRecognizer) {
            guard let view = renderer else { return }
            let point = gesture.location(in: view)
            guard let hit = view.hitTest(point, options: nil).first(where: { water.owns($0.node) }) else {
                return
            }
            water.disturb(atWorldPosition: hit.worldCoordinates, strength: 0.2)
        }

        @objc func resetCamera() {
            cameraYaw = playerFacingYaw + .pi
            if cameraMode == .firstPerson {
                firstPersonPitch = 0
            } else {
                cameraPitch = 0.38
            }
            hasSmoothedCameraTarget = false
        }

        func setCameraMode(_ mode: GameCameraMode) {
            guard cameraMode != mode else { return }
            cameraMode = mode
            cameraYaw = playerFacingYaw + .pi
            firstPersonPitch = 0
            cameraPitch = 0.38
            hasSmoothedCameraTarget = false
            camera.camera?.fieldOfView = mode == .firstPerson ? 72 : 58
            updateCamera(dt: 0, snap: true)
        }

        func receiveJumpRequest(_ requestID: Int) {
            guard requestID != handledJumpRequestID else { return }
            handledJumpRequestID = requestID
            jumpQueued = true
        }

        func setEquipment(heldTool: GameHeldTool, lightStates: GameLightStates) {
            self.heldTool = heldTool
            self.lightStates = lightStates
            let postLevel = lightStates.effectiveIntensity(.post)
            lampLight?.intensity = CGFloat(postLevel) * 580
            for fixedLight in fixedLightMaterials {
                let level = lightStates.effectiveIntensity(fixedLight.fixture)
                fixedLight.material.diffuse.contents = fixedLight.onColor
                fixedLight.material.diffuse.intensity = CGFloat(max(0.025, level))
                fixedLight.material.emission.contents = fixedLight.onColor
                fixedLight.material.emission.intensity = CGFloat(level)
            }
            for neonLight in neonLights {
                let level = lightStates.effectiveIntensity(neonLight.fixture)
                neonLight.light.intensity = CGFloat(level) * 650
            }
            ambientLight?.intensity = 105
            scene.lightingEnvironment.intensity = advancedReflectionsEnabled ? 0.88 : 0.7
            flashlightLight?.intensity = heldTool == .flashlight ? 920 : 0
        }

        private func buildScene() {
            scene.background.contents = UIColor(red: 0.01, green: 0.015, blue: 0.03, alpha: 1)
            scene.fogColor = UIColor(red: 0.018, green: 0.025, blue: 0.045, alpha: 1)
            scene.fogStartDistance = 14
            scene.fogEndDistance = 27
            scene.lightingEnvironment.contents = UIColor(red: 0.08, green: 0.10, blue: 0.15, alpha: 1)
            scene.lightingEnvironment.intensity = 0.7
            scene.physicsWorld.gravity = SCNVector3(0, -9.8, 0)

            buildCourtyard()
            buildPool()
            buildMirror()
            buildNeonSign()
            buildRiverStones()
            buildCharacters()
            buildLamp()
            buildCamera()
        }

        private func buildCourtyard() {
            let deckMaterial = makeMaterial(
                color: UIColor(red: 0.16, green: 0.18, blue: 0.19, alpha: 1),
                roughness: 0.9
            )
            let wallMaterial = makeMaterial(
                color: UIColor(red: 0.075, green: 0.085, blue: 0.10, alpha: 1),
                roughness: 0.95
            )

            // Four deck slabs leave a real opening for the recessed pool.
            addBox(size: SCNVector3(20, 0.2, 5.6), position: SCNVector3(0, -0.1, -7.2), material: deckMaterial)
            addBox(size: SCNVector3(20, 0.2, 8.6), position: SCNVector3(0, -0.1, 5.7), material: deckMaterial)
            addBox(size: SCNVector3(4.5, 0.2, 5.8), position: SCNVector3(-7.75, -0.1, -1.5), material: deckMaterial)
            addBox(size: SCNVector3(7.5, 0.2, 5.8), position: SCNVector3(6.25, -0.1, -1.5), material: deckMaterial)

            let mirrorWall = addBox(
                size: SCNVector3(20, 5, 0.35),
                position: SCNVector3(0, 2.5, -9.82),
                material: wallMaterial,
                blocksCamera: true
            )
            mirrorWall.categoryBitMask = RenderCategory.mirrorFixture
            addBox(
                size: SCNVector3(20, 5, 0.35),
                position: SCNVector3(0, 2.5, 9.82),
                material: wallMaterial,
                blocksCamera: true
            )
            addBox(
                size: SCNVector3(0.35, 5, 20),
                position: SCNVector3(-9.82, 2.5, 0),
                material: wallMaterial,
                blocksCamera: true
            )
            addBox(
                size: SCNVector3(0.35, 5, 20),
                position: SCNVector3(9.82, 2.5, 0),
                material: wallMaterial,
                blocksCamera: true
            )

            let ambient = SCNLight()
            ambient.type = .ambient
            ambient.color = UIColor(red: 0.30, green: 0.36, blue: 0.52, alpha: 1)
            ambient.intensity = 105
            let ambientNode = SCNNode()
            ambientNode.light = ambient
            scene.rootNode.addChildNode(ambientNode)
            ambientLight = ambient
        }

        private func buildPool() {
            let basinMaterial = makeMaterial(
                color: UIColor(red: 0.16, green: 0.23, blue: 0.22, alpha: 1),
                roughness: 0.72
            )
            let copingMaterial = makeMaterial(
                color: UIColor(red: 0.24, green: 0.25, blue: 0.24, alpha: 1),
                roughness: 0.82
            )
            poolCopingMaterial = copingMaterial

            addBox(size: SCNVector3(7.55, 0.14, 5.3), position: SCNVector3(-1.5, -0.72, -1.5), material: basinMaterial)
            addBox(size: SCNVector3(7.55, 0.64, 0.16), position: SCNVector3(-1.5, -0.35, -4.15), material: basinMaterial)
            addBox(size: SCNVector3(7.55, 0.64, 0.16), position: SCNVector3(-1.5, -0.35, 1.15), material: basinMaterial)
            addBox(size: SCNVector3(0.16, 0.64, 5.3), position: SCNVector3(-5.28, -0.35, -1.5), material: basinMaterial)
            addBox(size: SCNVector3(0.16, 0.64, 5.3), position: SCNVector3(2.28, -0.35, -1.5), material: basinMaterial)

            addBox(size: SCNVector3(8, 0.28, 0.34), position: SCNVector3(-1.5, 0.14, -4.4), material: copingMaterial)
            addBox(size: SCNVector3(8, 0.28, 0.34), position: SCNVector3(-1.5, 0.14, 1.4), material: copingMaterial)
            addBox(size: SCNVector3(0.34, 0.28, 5.46), position: SCNVector3(-5.5, 0.14, -1.5), material: copingMaterial)
            addBox(size: SCNVector3(0.34, 0.28, 5.46), position: SCNVector3(2.5, 0.14, -1.5), material: copingMaterial)

            water.configure(
                in: scene.rootNode,
                center: SCNVector3(-1.5, -0.08, -1.5),
                width: 7.45,
                length: 5.1
            )

            let floatMaterial = makeMaterial(
                color: UIColor(red: 0.95, green: 0.22, blue: 0.06, alpha: 1),
                roughness: 0.22
            )
            let floatGeometry = SCNTorus(ringRadius: 0.48, pipeRadius: 0.12)
            floatGeometry.ringSegmentCount = 28
            floatGeometry.pipeSegmentCount = 12
            floatGeometry.firstMaterial = floatMaterial
            let floatNode = SCNNode(geometry: floatGeometry)
            floatNode.name = "poolFloat"
            floatNode.position = SCNVector3(-2.6, -0.015, -2.0)
            scene.rootNode.addChildNode(floatNode)
            installStaticPhysics(on: floatNode)

            let warmYellow = UIColor(red: 1.0, green: 0.72, blue: 0.20, alpha: 1)
            addStrip(center: SCNVector3(-1.5, 0.292, -4.22), size: SCNVector3(7.5, 0.035, 0.07), color: warmYellow)
            addStrip(center: SCNVector3(-1.5, 0.292, 1.22), size: SCNVector3(7.5, 0.035, 0.07), color: warmYellow)
            addStrip(center: SCNVector3(-5.32, 0.292, -1.5), size: SCNVector3(0.07, 0.035, 5.1), color: warmYellow)
            addStrip(center: SCNVector3(2.32, 0.292, -1.5), size: SCNVector3(0.07, 0.035, 5.1), color: warmYellow)
        }

        private func buildMirror() {
            let frameMaterial = makeMaterial(
                color: UIColor(red: 0.62, green: 0.65, blue: 0.68, alpha: 1),
                roughness: 0.3,
                metalness: 0.72
            )
            mirrorFrameMaterial = frameMaterial
            let center = SCNVector3(3.5, 2.05, -9.58)
            let width: Float = 4.3
            let height: Float = 2.65

            let backing = SCNBox(width: CGFloat(width + 0.34), height: CGFloat(height + 0.34), length: 0.14, chamferRadius: 0.04)
            backing.firstMaterial = frameMaterial
            let backingNode = SCNNode(geometry: backing)
            backingNode.position = center
            backingNode.categoryBitMask = RenderCategory.mirrorFixture
            scene.rootNode.addChildNode(backingNode)

            let glass = SCNPlane(width: CGFloat(width), height: CGFloat(height))
            let glassMaterial = SCNMaterial()
            glassMaterial.name = "mirrorGlass"
            glassMaterial.isDoubleSided = true
            glassMaterial.lightingModel = .blinn
            glassMaterial.diffuse.contents = UIColor(red: 0.28, green: 0.34, blue: 0.4, alpha: 1)
            glassMaterial.specular.contents = UIColor(white: 0.55, alpha: 1)
            glassMaterial.shininess = 70
            glass.firstMaterial = glassMaterial
            mirrorMaterial = glassMaterial

            let glassNode = SCNNode(geometry: glass)
            glassNode.name = "framedMirror"
            glassNode.position = SCNVector3(center.x, center.y, center.z + 0.13)
            glassNode.categoryBitMask = RenderCategory.mirrorFixture
            scene.rootNode.addChildNode(glassNode)
            mirrorNode = glassNode

            let frameDepth: Float = 0.18
            let frameThickness: Float = 0.15
            let topFrame = addDecorativeBox(
                size: SCNVector3(width + 0.32, frameThickness, frameDepth),
                position: SCNVector3(center.x, center.y + height / 2 + 0.09, center.z + 0.14),
                material: frameMaterial
            )
            let bottomFrame = addDecorativeBox(
                size: SCNVector3(width + 0.32, frameThickness, frameDepth),
                position: SCNVector3(center.x, center.y - height / 2 - 0.09, center.z + 0.14),
                material: frameMaterial
            )
            let leftFrame = addDecorativeBox(
                size: SCNVector3(frameThickness, height + 0.32, frameDepth),
                position: SCNVector3(center.x - width / 2 - 0.09, center.y, center.z + 0.14),
                material: frameMaterial
            )
            let rightFrame = addDecorativeBox(
                size: SCNVector3(frameThickness, height + 0.32, frameDepth),
                position: SCNVector3(center.x + width / 2 + 0.09, center.y, center.z + 0.14),
                material: frameMaterial
            )

            for node in [topFrame, bottomFrame, leftFrame, rightFrame] {
                node.categoryBitMask = RenderCategory.mirrorFixture
            }
        }

        private func buildNeonSign() {
            addNeonText(
                "PISCINA",
                color: UIColor(red: 1.0, green: 0.015, blue: 0.01, alpha: 1),
                position: SCNVector3(-5.25, 3.45, -9.62),
                lightPosition: SCNVector3(-5.25, 3.2, -9.30),
                yaw: 0,
                mirrored: false,
                fixture: .piscinaNeon
            )
            addNeonText(
                "SHEERIT",
                color: UIColor(red: 0.01, green: 0.20, blue: 1.0, alpha: 1),
                position: SCNVector3(5.45, 3.45, 9.62),
                lightPosition: SCNVector3(5.45, 3.2, 9.30),
                yaw: .pi,
                mirrored: true,
                fixture: .sheeritNeon
            )
        }

        private func addNeonText(
            _ value: String,
            color: UIColor,
            position: SCNVector3,
            lightPosition: SCNVector3,
            yaw: Float,
            mirrored: Bool,
            fixture: GameLightFixture
        ) {
            let text = SCNText(string: value, extrusionDepth: 0.018)
            text.font = UIFont.systemFont(ofSize: 1, weight: .heavy)
            text.flatness = 0.12
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = color
            material.emission.contents = color
            fixedLightMaterials.append((material, color, fixture))
            text.materials = [material]

            let node = SCNNode(geometry: text)
            let bounds = node.boundingBox
            node.pivot = SCNMatrix4MakeTranslation(
                (bounds.min.x + bounds.max.x) * 0.5,
                (bounds.min.y + bounds.max.y) * 0.5,
                0
            )
            node.scale = SCNVector3(mirrored ? -0.82 : 0.82, 0.82, 0.82)
            node.position = position
            node.eulerAngles.y = yaw
            scene.rootNode.addChildNode(node)

            let glow = SCNLight()
            glow.type = .omni
            glow.color = color
            glow.intensity = 560
            glow.attenuationStartDistance = 0.4
            glow.attenuationEndDistance = 7.5
            glow.attenuationFalloffExponent = 2
            glow.castsShadow = false
            let glowNode = SCNNode()
            glowNode.light = glow
            glowNode.position = lightPosition
            scene.rootNode.addChildNode(glowNode)
            neonLights.append((glow, fixture))
        }

        private func buildRiverStones() {
            let stonePositions: [(SCNVector3, SCNVector3, UIColor)] = [
                (SCNVector3(-7.2, 0.24, -3.7), SCNVector3(1.25, 0.55, 0.9), UIColor(white: 0.28, alpha: 1)),
                (SCNVector3(-6.5, 0.18, -4.5), SCNVector3(0.8, 0.42, 1.1), UIColor(white: 0.36, alpha: 1)),
                (SCNVector3(-7.8, 0.16, -2.7), SCNVector3(0.72, 0.36, 0.84), UIColor(white: 0.22, alpha: 1)),
                (SCNVector3(-6.6, 0.13, 0.5), SCNVector3(0.62, 0.3, 0.76), UIColor(white: 0.40, alpha: 1)),
                (SCNVector3(-7.4, 0.2, 1.2), SCNVector3(0.95, 0.45, 0.7), UIColor(white: 0.31, alpha: 1)),
                (SCNVector3(-6.4, 0.17, 2.0), SCNVector3(0.76, 0.38, 0.9), UIColor(white: 0.25, alpha: 1)),
                (SCNVector3(4.0, 0.2, -4.9), SCNVector3(1.0, 0.46, 0.75), UIColor(white: 0.35, alpha: 1)),
                (SCNVector3(4.9, 0.15, -4.4), SCNVector3(0.65, 0.34, 0.88), UIColor(white: 0.24, alpha: 1)),
                (SCNVector3(5.6, 0.18, -3.7), SCNVector3(0.82, 0.4, 0.7), UIColor(white: 0.42, alpha: 1)),
                (SCNVector3(-2.5, 0.12, 3.0), SCNVector3(0.64, 0.3, 0.78), UIColor(white: 0.29, alpha: 1)),
                (SCNVector3(-1.5, 0.15, 3.2), SCNVector3(0.82, 0.34, 0.62), UIColor(white: 0.38, alpha: 1)),
                (SCNVector3(-0.5, 0.13, 3.0), SCNVector3(0.7, 0.3, 0.82), UIColor(white: 0.26, alpha: 1))
            ]

            for (index, stoneDefinition) in stonePositions.enumerated() {
                let (position, scale, color) = stoneDefinition
                let geometry = makeRiverStoneGeometry(
                    radii: SCNVector3(scale.x * 0.48, scale.y * 0.48, scale.z * 0.48),
                    seed: Float(index) + 0.7
                )
                let stoneMaterial = makeMaterial(color: color, roughness: 0.88)
                geometry.firstMaterial = stoneMaterial
                stoneMaterials.append(stoneMaterial)
                let stone = SCNNode(geometry: geometry)
                stone.position = position
                stone.eulerAngles = SCNVector3(0.08, position.x * 0.19, 0.04)
                scene.rootNode.addChildNode(stone)
                installStaticPhysics(on: stone, blocksCamera: true)
            }
        }

        private func makeRiverStoneGeometry(radii: SCNVector3, seed: Float) -> SCNGeometry {
            let segments = 18
            let rings = 9
            var vertices: [SCNVector3] = []
            var normals: [SCNVector3] = []
            var indices: [UInt32] = []

            for ring in 0...rings {
                let latitude = -Float.pi / 2 + Float.pi * Float(ring) / Float(rings)
                let latitudeCosine = cos(latitude)
                for segment in 0..<segments {
                    let longitude = 2 * Float.pi * Float(segment) / Float(segments)
                    let noise = 1
                        + sin(longitude * 3 + seed * 1.7) * 0.075
                        + cos(longitude * 5 - latitude * 2 + seed) * 0.045
                        + sin(latitude * 4 + seed * 2.3) * 0.035
                    let lowerFlattening: Float = latitude < 0 ? 0.82 : 1
                    let vertex = SCNVector3(
                        latitudeCosine * cos(longitude) * radii.x * noise,
                        sin(latitude) * radii.y * lowerFlattening,
                        latitudeCosine * sin(longitude) * radii.z * noise
                    )
                    vertices.append(vertex)
                    var normal = SCNVector3(
                        vertex.x / max(0.001, radii.x * radii.x),
                        vertex.y / max(0.001, radii.y * radii.y),
                        vertex.z / max(0.001, radii.z * radii.z)
                    )
                    let normalLength = max(0.001, sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z))
                    normal.x /= normalLength
                    normal.y /= normalLength
                    normal.z /= normalLength
                    normals.append(normal)
                }
            }

            for ring in 0..<rings {
                for segment in 0..<segments {
                    let next = (segment + 1) % segments
                    let a = UInt32(ring * segments + segment)
                    let b = UInt32(ring * segments + next)
                    let c = UInt32((ring + 1) * segments + segment)
                    let d = UInt32((ring + 1) * segments + next)
                    indices.append(contentsOf: [a, c, b, b, c, d])
                }
            }

            return SCNGeometry(
                sources: [
                    SCNGeometrySource(vertices: vertices),
                    SCNGeometrySource(normals: normals)
                ],
                elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
            )
        }

        private func buildCharacters() {
            player.addChildNode(playerVisual)
            buildCharacterVisual(on: playerVisual, color: .systemTeal, hasEyes: true)
            buildHeldToolVisual(on: playerVisual)
            playerVisual.eulerAngles.y = playerFacingYaw
            player.name = "player"
            player.position = SCNVector3(3.8, 0.86, 3.8)

            let playerShapeGeometry = SCNCapsule(capRadius: 0.3, height: 1.7)
            let playerShape = SCNPhysicsShape(geometry: playerShapeGeometry, options: nil)
            let playerBody = SCNPhysicsBody(type: .dynamic, shape: playerShape)
            playerBody.mass = 1.0
            playerBody.friction = 0.85
            playerBody.restitution = 0
            playerBody.damping = 0.2
            playerBody.angularDamping = 1.0
            playerBody.angularVelocityFactor = SCNVector3Zero
            playerBody.categoryBitMask = PhysicsCategory.player
            playerBody.collisionBitMask = PhysicsCategory.world
            playerBody.contactTestBitMask = PhysicsCategory.world
            playerBody.isAffectedByGravity = true
            playerBody.allowsResting = true
            player.physicsBody = playerBody
            scene.rootNode.addChildNode(player)
            playerBody.resetTransform()

            let guests: [(SCNVector3, UIColor, Float)] = [
                (SCNVector3(6.4, 0.86, 1.0), .systemPink, -.pi * 0.72),
                (SCNVector3(7.2, 0.86, -1.0), .systemOrange, -.pi * 0.62),
                (SCNVector3(-7.8, 0.86, 4.5), .systemPurple, .pi * 0.2)
            ]

            for (position, color, yaw) in guests {
                let guest = SCNNode()
                buildCharacterVisual(on: guest, color: color, hasEyes: true)
                guest.position = position
                guest.eulerAngles.y = yaw
                scene.rootNode.addChildNode(guest)

                let shapeGeometry = SCNCapsule(capRadius: 0.3, height: 1.7)
                let shape = SCNPhysicsShape(geometry: shapeGeometry, options: nil)
                let body = SCNPhysicsBody(type: .static, shape: shape)
                body.categoryBitMask = PhysicsCategory.world
                body.collisionBitMask = PhysicsCategory.player
                body.friction = 0.8
                guest.physicsBody = body
            }
        }

        private func buildCharacterVisual(on root: SCNNode, color: UIColor, hasEyes: Bool) {
            let characterMaterial = makeMatteMaterial(color: color)
            let bodyGeometry = SCNCapsule(capRadius: 0.25, height: 0.82)
            bodyGeometry.firstMaterial = characterMaterial
            let body = SCNNode(geometry: bodyGeometry)
            body.position.y = -0.12
            root.addChildNode(body)

            let headGeometry = SCNSphere(radius: 0.29)
            headGeometry.segmentCount = 20
            headGeometry.firstMaterial = characterMaterial
            let head = SCNNode(geometry: headGeometry)
            head.position.y = 0.52
            root.addChildNode(head)

            for side: Float in [-1, 1] {
                let legGeometry = SCNCapsule(capRadius: 0.075, height: 0.4)
                legGeometry.firstMaterial = characterMaterial
                let leg = SCNNode(geometry: legGeometry)
                leg.position = SCNVector3(side * 0.12, -0.62, 0)
                root.addChildNode(leg)

                let armGeometry = SCNCapsule(capRadius: 0.065, height: 0.42)
                armGeometry.firstMaterial = characterMaterial
                let arm = SCNNode(geometry: armGeometry)
                arm.position = SCNVector3(side * 0.31, -0.1, 0)
                arm.eulerAngles.z = side * 0.12
                root.addChildNode(arm)
            }

            guard hasEyes else { return }
            let eyeGeometry = SCNSphere(radius: 0.045)
            eyeGeometry.segmentCount = 12
            eyeGeometry.firstMaterial = makeMatteMaterial(color: .black)
            for side: Float in [-1, 1] {
                let eye = SCNNode(geometry: eyeGeometry.copy() as? SCNGeometry)
                eye.position = SCNVector3(side * 0.095, 0.055, 0.255)
                head.addChildNode(eye)
            }
        }

        private func buildHeldToolVisual(on root: SCNNode) {
            let geometry = SCNBox(width: 0.13, height: 0.15, length: 0.38, chamferRadius: 0.025)
            geometry.firstMaterial = makeMaterial(
                color: UIColor(red: 0.055, green: 0.06, blue: 0.065, alpha: 1),
                roughness: 0.34
            )
            let tool = SCNNode(geometry: geometry)
            tool.position = SCNVector3(0.38, -0.20, 0.20)
            root.addChildNode(tool)
        }

        private func buildLamp() {
            let metal = makeMaterial(
                color: UIColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1),
                roughness: 0.4,
                metalness: 0.75
            )
            let warmYellow = UIColor(red: 1.0, green: 0.72, blue: 0.20, alpha: 1)

            let base = SCNCylinder(radius: 0.3, height: 0.12)
            base.firstMaterial = metal
            let baseNode = SCNNode(geometry: base)
            baseNode.position = SCNVector3(-7.55, 0.06, 6.65)
            scene.rootNode.addChildNode(baseNode)
            installStaticPhysics(on: baseNode)

            let post = SCNCylinder(radius: 0.075, height: 2.7)
            post.firstMaterial = metal
            let postNode = SCNNode(geometry: post)
            postNode.position = SCNVector3(-7.55, 1.4, 6.65)
            scene.rootNode.addChildNode(postNode)
            installStaticPhysics(on: postNode, blocksCamera: true)

            let lantern = SCNBox(width: 0.34, height: 0.42, length: 0.34, chamferRadius: 0.04)
            let lanternMaterial = SCNMaterial()
            lanternMaterial.lightingModel = .constant
            lanternMaterial.diffuse.contents = warmYellow
            lanternMaterial.emission.contents = warmYellow
            fixedLightMaterials.append((lanternMaterial, warmYellow, .post))
            lantern.firstMaterial = lanternMaterial
            let lanternNode = SCNNode(geometry: lantern)
            lanternNode.position = SCNVector3(-7.55, 2.72, 6.65)
            scene.rootNode.addChildNode(lanternNode)

            let hood = SCNBox(width: 0.54, height: 0.08, length: 0.54, chamferRadius: 0.025)
            hood.firstMaterial = metal
            let hoodNode = SCNNode(geometry: hood)
            hoodNode.position = SCNVector3(-7.55, 2.99, 6.65)
            scene.rootNode.addChildNode(hoodNode)

            let light = SCNLight()
            light.type = .omni
            light.color = warmYellow
            light.intensity = 580
            light.attenuationStartDistance = 0.35
            light.attenuationEndDistance = 7.5
            light.attenuationFalloffExponent = 2
            light.castsShadow = true
            light.shadowMode = .deferred
            light.shadowMapSize = CGSize(width: 1024, height: 1024)
            light.shadowSampleCount = 8
            light.shadowRadius = 4
            light.shadowBias = 0.008
            let lightNode = SCNNode()
            lightNode.light = light
            lightNode.position = SCNVector3(-7.55, 2.72, 6.65)
            scene.rootNode.addChildNode(lightNode)
            lampLight = light

            // Approximate the first light bounce from the lamp across the mirror plane.
            let bounce = SCNLight()
            bounce.type = .spot
            bounce.color = warmYellow
            bounce.intensity = 0
            bounce.attenuationStartDistance = 1.0
            bounce.attenuationEndDistance = 15
            bounce.attenuationFalloffExponent = 2
            bounce.spotInnerAngle = 38
            bounce.spotOuterAngle = 74
            bounce.castsShadow = false

            let bounceNode = SCNNode()
            bounceNode.light = bounce
            bounceNode.position = SCNVector3(3.5, 2.05, -9.38)
            bounceNode.look(at: SCNVector3(1.6, 1.28, -2.93))
            scene.rootNode.addChildNode(bounceNode)
            mirrorBounceLight = bounce
        }

        private func buildCamera() {
            let cameraDefinition = SCNCamera()
            cameraDefinition.fieldOfView = 58
            cameraDefinition.zNear = 0.05
            cameraDefinition.zFar = 40
            cameraDefinition.wantsHDR = false
            cameraDefinition.bloomIntensity = 0
            cameraDefinition.screenSpaceAmbientOcclusionIntensity = 0
            cameraDefinition.categoryBitMask = Int.max
            camera.camera = cameraDefinition
            camera.position = SCNVector3(3.8, 3.0, 8.8)
            scene.rootNode.addChildNode(camera)

            let flashlight = SCNLight()
            flashlight.type = .spot
            flashlight.color = UIColor(red: 1.0, green: 0.88, blue: 0.68, alpha: 1)
            flashlight.intensity = 920
            flashlight.attenuationStartDistance = 0.25
            flashlight.attenuationEndDistance = 18
            flashlight.attenuationFalloffExponent = 1.7
            flashlight.spotInnerAngle = 18
            flashlight.spotOuterAngle = 42
            flashlight.castsShadow = true
            flashlight.shadowMode = .deferred
            flashlight.shadowMapSize = CGSize(width: 1024, height: 1024)
            flashlight.shadowSampleCount = 8
            flashlight.shadowRadius = 3
            flashlight.shadowBias = 0.008
            let flashlightNode = SCNNode()
            flashlightNode.light = flashlight
            flashlightNode.position = SCNVector3(0.18, -0.16, -0.10)
            camera.addChildNode(flashlightNode)
            flashlightLight = flashlight

            let laserMaterial = SCNMaterial()
            laserMaterial.lightingModel = .constant
            laserMaterial.diffuse.contents = UIColor(red: 1.0, green: 0.01, blue: 0.004, alpha: 1)
            laserMaterial.emission.contents = UIColor(red: 1.0, green: 0.005, blue: 0.002, alpha: 1)
            let beam = SCNCylinder(radius: 0.012, height: 1)
            beam.radialSegmentCount = 8
            beam.firstMaterial = laserMaterial
            laserBeamNode.geometry = beam
            laserBeamNode.isHidden = true
            scene.rootNode.addChildNode(laserBeamNode)

            let dot = SCNSphere(radius: 0.065)
            dot.segmentCount = 10
            dot.firstMaterial = laserMaterial
            laserDotNode.geometry = dot
            laserDotNode.isHidden = true
            scene.rootNode.addChildNode(laserDotNode)

            let mirrorCameraDefinition = SCNCamera()
            mirrorCameraDefinition.fieldOfView = 38
            mirrorCameraDefinition.zNear = 0.08
            mirrorCameraDefinition.zFar = 60
            mirrorCameraDefinition.wantsHDR = false
            mirrorCameraDefinition.categoryBitMask = Int.max & ~RenderCategory.mirrorFixture
            mirrorCamera.camera = mirrorCameraDefinition
            scene.rootNode.addChildNode(mirrorCamera)
            updateCamera(dt: 0, snap: true)
        }

        private func configureMirrorRenderer(for view: SCNView) {
            guard mirrorRenderer == nil,
                  let device = view.device ?? MTLCreateSystemDefaultDevice(),
                  let commandQueue = device.makeCommandQueue(),
                  let mirrorMaterial else {
                return
            }

            let width = 512
            let height = 316
            let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            colorDescriptor.storageMode = .private
            colorDescriptor.usage = [.renderTarget, .shaderRead]

            let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .depth32Float,
                width: width,
                height: height,
                mipmapped: false
            )
            depthDescriptor.storageMode = .private
            depthDescriptor.usage = .renderTarget

            guard let colorTexture = device.makeTexture(descriptor: colorDescriptor),
                  let depthTexture = device.makeTexture(descriptor: depthDescriptor) else {
                return
            }

            let sceneRenderer = SCNRenderer(device: device, options: nil)
            sceneRenderer.scene = scene
            sceneRenderer.pointOfView = mirrorCamera
            sceneRenderer.autoenablesDefaultLighting = false

            mirrorRenderer = sceneRenderer
            mirrorCommandQueue = commandQueue
            mirrorColorTexture = colorTexture
            mirrorDepthTexture = depthTexture

            mirrorMaterial.lightingModel = .constant
            mirrorMaterial.diffuse.contents = colorTexture
            mirrorMaterial.diffuse.magnificationFilter = .linear
            mirrorMaterial.diffuse.minificationFilter = .linear
            mirrorMaterial.diffuse.wrapS = .clamp
            mirrorMaterial.diffuse.wrapT = .clamp
        }

        private func renderMirror(atTime time: TimeInterval) {
            let frameInterval = advancedReflectionsEnabled ? 1.0 / 24.0 : 1.0 / 12.0
            guard lastMirrorRenderTime == 0 || time - lastMirrorRenderTime >= frameInterval,
                  let mirrorRenderer,
                  let mirrorCommandQueue,
                  let mirrorColorTexture,
                  let mirrorDepthTexture,
                  let mirrorNode,
                  let commandBuffer = mirrorCommandQueue.makeCommandBuffer() else {
                return
            }
            lastMirrorRenderTime = time

            let mirrorCenter = mirrorNode.presentation.worldPosition
            let sourcePosition = camera.presentation.worldPosition
            let reflectedPosition = SCNVector3(
                sourcePosition.x,
                sourcePosition.y,
                2 * mirrorCenter.z - sourcePosition.z
            )
            mirrorCamera.position = reflectedPosition
            mirrorCamera.look(
                at: mirrorCenter,
                up: SCNVector3(0, 1, 0),
                localFront: SCNVector3(0, 0, -1)
            )

            let dx = mirrorCenter.x - reflectedPosition.x
            let dy = mirrorCenter.y - reflectedPosition.y
            let dz = mirrorCenter.z - reflectedPosition.z
            let distance = max(1, sqrt(dx * dx + dy * dy + dz * dz))
            let verticalFieldOfView = 2 * atan(1.42 / distance) * 180 / Float.pi
            mirrorCamera.camera?.fieldOfView = CGFloat(max(8, min(58, verticalFieldOfView)))

            let passDescriptor = MTLRenderPassDescriptor()
            passDescriptor.colorAttachments[0].texture = mirrorColorTexture
            passDescriptor.colorAttachments[0].loadAction = .clear
            passDescriptor.colorAttachments[0].storeAction = .store
            passDescriptor.colorAttachments[0].clearColor = MTLClearColor(
                red: 0.01,
                green: 0.015,
                blue: 0.025,
                alpha: 1
            )
            passDescriptor.depthAttachment.texture = mirrorDepthTexture
            passDescriptor.depthAttachment.loadAction = .clear
            passDescriptor.depthAttachment.storeAction = .dontCare
            passDescriptor.depthAttachment.clearDepth = 1

            let viewport = CGRect(
                x: 0,
                y: 0,
                width: mirrorColorTexture.width,
                height: mirrorColorTexture.height
            )
            mirrorRenderer.render(
                atTime: time,
                viewport: viewport,
                commandBuffer: commandBuffer,
                passDescriptor: passDescriptor
            )
            commandBuffer.commit()
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let dt = lastUpdate == 0 ? 0 : min(1.0 / 30.0, time - lastUpdate)
            lastUpdate = time

            if fpsStartTime == 0 { fpsStartTime = time }
            fpsFrameCount += 1
            let fpsDuration = time - fpsStartTime
            if fpsDuration >= 0.5 {
                onFPSUpdate?(Double(fpsFrameCount) / fpsDuration)
                fpsFrameCount = 0
                fpsStartTime = time
            }

            updatePlayer(dt: Float(dt))
            reportNearbyLightIfNeeded()
            updateCamera(dt: Float(dt), snap: false)
            updateEquipmentVisuals()

            if lastWaterUpdate == 0 || time - lastWaterUpdate >= 1.0 / 30.0 {
                let waterDT = lastWaterUpdate == 0 ? Float(1.0 / 30.0) : Float(min(1.0 / 20.0, time - lastWaterUpdate))
                lastWaterUpdate = time
                water.update(dt: waterDT, time: Float(time))
            }

            if appliedReflectionMode != advancedReflectionsEnabled {
                applyReflectionMode(enabled: advancedReflectionsEnabled)
            }

            renderMirror(atTime: time)

            if player.position.y < -2 {
                resetPlayer()
            }
        }

        private func updatePlayer(dt: Float) {
            guard let body = player.physicsBody else { return }

            if jumpQueued {
                jumpQueued = false
                if isPlayerGrounded(body) {
                    var jumpVelocity = body.velocity
                    jumpVelocity.y = 5.2
                    body.velocity = jumpVelocity
                }
            }

            let inputX = Float(joystick.dx)
            let inputForward = -Float(joystick.dy)
            let magnitude = min(1, hypot(inputX, inputForward))

            let cameraForwardX = -sin(cameraYaw)
            let cameraForwardZ = -cos(cameraYaw)
            let cameraRightX = cos(cameraYaw)
            let cameraRightZ = -sin(cameraYaw)

            var moveX = cameraRightX * inputX + cameraForwardX * inputForward
            var moveZ = cameraRightZ * inputX + cameraForwardZ * inputForward
            let moveLength = hypot(moveX, moveZ)
            if moveLength > 0.001 {
                moveX /= moveLength
                moveZ /= moveLength
            }

            let speed: Float = magnitude > 0.08 ? 3.6 * magnitude : 0
            var velocity = body.velocity
            let currentHorizontalSpeed = hypot(velocity.x, velocity.z)
            if speed > 0 {
                let response = min(1, dt * 13)
                velocity.x += (moveX * speed - velocity.x) * response
                velocity.z += (moveZ * speed - velocity.z) * response
                body.velocity = velocity
            } else if currentHorizontalSpeed > 0.025 {
                let response = min(1, dt * 18)
                velocity.x += -velocity.x * response
                velocity.z += -velocity.z * response
                body.velocity = velocity
            } else if velocity.x != 0 || velocity.z != 0 {
                velocity.x = 0
                velocity.z = 0
                body.velocity = velocity
            }

            if cameraMode == .firstPerson {
                let targetYaw = cameraYaw + .pi
                let yawDelta = atan2(sin(targetYaw - playerFacingYaw), cos(targetYaw - playerFacingYaw))
                playerFacingYaw += yawDelta * min(1, dt * 18)
                playerVisual.eulerAngles.y = playerFacingYaw
            } else if speed > 0.08 {
                let targetYaw = atan2(moveX, moveZ)
                let yawDelta = atan2(sin(targetYaw - playerFacingYaw), cos(targetYaw - playerFacingYaw))
                playerFacingYaw += yawDelta * min(1, dt * 11)
                playerVisual.eulerAngles.y = playerFacingYaw
            }

            let horizontalSpeed = hypot(velocity.x, velocity.z)
            let grounded = isPlayerGrounded(body)
            let playerPosition = player.presentation.position
            let isInPool = playerPosition.y <= 0.05 && playerPosition.x > -5.28 && playerPosition.x < 2.28 &&
                playerPosition.z > -4.08 && playerPosition.z < 1.08
            if isInPool && grounded && horizontalSpeed > 0.25 {
                waterStepCountdown -= dt
                if waterStepCountdown <= 0 {
                    water.disturb(atWorldPosition: playerPosition, strength: 0.34)
                    audio.playWaterStep(intensity: min(1, horizontalSpeed / 1.85))
                    waterStepCountdown = 0.42
                }
                footstepCountdown = 0
            } else if grounded && horizontalSpeed > 0.45 {
                footstepCountdown -= dt
                if footstepCountdown <= 0 {
                    audio.playFootstep(intensity: min(1, horizontalSpeed / 3.6))
                    footstepCountdown = 0.36 - min(0.08, horizontalSpeed * 0.018)
                }
                waterStepCountdown = 0
            } else {
                footstepCountdown = 0
                if !isInPool { waterStepCountdown = 0 }
            }
        }

        private func isPlayerGrounded(_ body: SCNPhysicsBody) -> Bool {
            guard body.velocity.y < 0.8 else { return false }
            let position = player.presentation.position
            let floorProbe = SCNVector3(position.x, position.y - 1.02, position.z)
            let hits = scene.physicsWorld.rayTestWithSegment(
                from: position,
                to: floorProbe,
                options: [
                    .collisionBitMask: PhysicsCategory.world,
                    .searchMode: SCNPhysicsWorld.TestSearchMode.closest
                ]
            )
            return !hits.isEmpty
        }

        private func reportNearbyLightIfNeeded() {
            let position = player.presentation.position
            let point = SIMD2<Float>(position.x, position.z)
            var candidates: [(GameLightFixture, Float)] = []

            let postDistance = simd_distance(point, SIMD2<Float>(-7.55, 6.65))
            if postDistance < 3.4 {
                candidates.append((.post, postDistance))
            }
            let piscinaDistance = simd_distance(point, SIMD2<Float>(-5.25, -9.15))
            if piscinaDistance < 3.4 {
                candidates.append((.piscinaNeon, piscinaDistance))
            }
            let sheeritDistance = simd_distance(point, SIMD2<Float>(5.45, 9.15))
            if sheeritDistance < 3.4 {
                candidates.append((.sheeritNeon, sheeritDistance))
            }

            let poolStripsCenterDistance = simd_distance(point, SIMD2<Float>(-1.5, -1.5))
            let clampedPoolPoint = SIMD2<Float>(
                min(2.55, max(-5.55, point.x)),
                min(1.40, max(-4.40, point.y))
            )
            let poolEdgeDistance = simd_distance(point, clampedPoolPoint)
            if poolEdgeDistance < 2.8 || poolStripsCenterDistance < 3.4 {
                candidates.append((.poolStrips, min(poolEdgeDistance, poolStripsCenterDistance)))
            }

            let nearby = candidates.min(by: { $0.1 < $1.1 })?.0
            guard !hasReportedNearbyLight || nearby != lastNearbyLight else { return }
            hasReportedNearbyLight = true
            lastNearbyLight = nearby
            onNearbyLightUpdate?(nearby)
        }

        private func updateCamera(dt: Float, snap: Bool) {
            let playerPosition = player.presentation.position
            let targetHeight: Float = cameraMode == .firstPerson ? 0.56 : 0.28
            let rawTarget = SCNVector3(playerPosition.x, playerPosition.y + targetHeight, playerPosition.z)
            if snap || !hasSmoothedCameraTarget || dt == 0 {
                smoothedCameraTarget = rawTarget
                hasSmoothedCameraTarget = true
            } else {
                let targetFollow = min(1, dt * (cameraMode == .firstPerson ? 22 : 14))
                smoothedCameraTarget = SCNVector3(
                    smoothedCameraTarget.x + (rawTarget.x - smoothedCameraTarget.x) * targetFollow,
                    smoothedCameraTarget.y + (rawTarget.y - smoothedCameraTarget.y) * targetFollow,
                    smoothedCameraTarget.z + (rawTarget.z - smoothedCameraTarget.z) * targetFollow
                )
            }

            if cameraMode == .firstPerson {
                let forwardX = -sin(cameraYaw)
                let forwardZ = -cos(cameraYaw)
                let horizontalPitch = cos(firstPersonPitch)
                let cameraPosition = SCNVector3(
                    smoothedCameraTarget.x + forwardX * 0.34,
                    smoothedCameraTarget.y,
                    smoothedCameraTarget.z + forwardZ * 0.34
                )
                camera.position = cameraPosition
                camera.look(at: SCNVector3(
                    cameraPosition.x + forwardX * horizontalPitch * 5,
                    cameraPosition.y + sin(firstPersonPitch) * 5,
                    cameraPosition.z + forwardZ * horizontalPitch * 5
                ))
                return
            }

            let target = smoothedCameraTarget
            let distance: Float = 5.6
            let horizontalDistance = cos(cameraPitch) * distance
            let desired = SCNVector3(
                target.x + sin(cameraYaw) * horizontalDistance,
                target.y + sin(cameraPitch) * distance,
                target.z + cos(cameraYaw) * horizontalDistance
            )

            let hits = scene.physicsWorld.rayTestWithSegment(
                from: target,
                to: desired,
                options: [
                    .collisionBitMask: PhysicsCategory.cameraBlocker,
                    .searchMode: SCNPhysicsWorld.TestSearchMode.closest
                ]
            )

            var corrected = desired
            var obstructed = false
            if let hit = hits.first {
                obstructed = true
                corrected = SCNVector3(
                    hit.worldCoordinates.x + hit.worldNormal.x * 0.28,
                    hit.worldCoordinates.y + hit.worldNormal.y * 0.28,
                    hit.worldCoordinates.z + hit.worldNormal.z * 0.28
                )
            }

            if snap || dt == 0 {
                camera.position = corrected
            } else {
                let follow = min(1, dt * (obstructed ? 18 : 10))
                camera.position = SCNVector3(
                    camera.position.x + (corrected.x - camera.position.x) * follow,
                    camera.position.y + (corrected.y - camera.position.y) * follow,
                    camera.position.z + (corrected.z - camera.position.z) * follow
                )
            }
            camera.look(at: target)
        }

        private func updateEquipmentVisuals() {
            let laserEnabled = heldTool == .laser
            laserBeamNode.isHidden = !laserEnabled
            laserDotNode.isHidden = !laserEnabled
            guard laserEnabled else { return }

            let cameraPosition = camera.presentation.worldPosition
            let cameraForward = camera.presentation.worldFront
            let target = SCNVector3(
                cameraPosition.x + cameraForward.x * 25,
                cameraPosition.y + cameraForward.y * 25,
                cameraPosition.z + cameraForward.z * 25
            )
            let playerPosition = player.presentation.worldPosition
            let origin = cameraMode == .firstPerson
                ? SCNVector3(
                    cameraPosition.x + cameraForward.x * 0.12,
                    cameraPosition.y - 0.14,
                    cameraPosition.z + cameraForward.z * 0.12
                )
                : SCNVector3(playerPosition.x, playerPosition.y + 0.42, playerPosition.z)
            var direction = SCNVector3(
                target.x - origin.x,
                target.y - origin.y,
                target.z - origin.z
            )
            let directionLength = max(0.001, sqrt(
                direction.x * direction.x +
                direction.y * direction.y +
                direction.z * direction.z
            ))
            direction.x /= directionLength
            direction.y /= directionLength
            direction.z /= directionLength

            let maximumEnd = SCNVector3(
                origin.x + direction.x * 30,
                origin.y + direction.y * 30,
                origin.z + direction.z * 30
            )
            let hits = scene.physicsWorld.rayTestWithSegment(
                from: origin,
                to: maximumEnd,
                options: [
                    .collisionBitMask: PhysicsCategory.world,
                    .searchMode: SCNPhysicsWorld.TestSearchMode.closest
                ]
            )
            let end = hits.first?.worldCoordinates ?? maximumEnd
            let beamLength = max(0.001, sqrt(
                pow(end.x - origin.x, 2) +
                pow(end.y - origin.y, 2) +
                pow(end.z - origin.z, 2)
            ))
            let upVector = abs(direction.y) > 0.95 ? SCNVector3(1, 0, 0) : SCNVector3(0, 1, 0)
            laserBeamNode.position = SCNVector3(
                (origin.x + end.x) * 0.5,
                (origin.y + end.y) * 0.5,
                (origin.z + end.z) * 0.5
            )
            laserBeamNode.scale = SCNVector3(1, beamLength, 1)
            laserBeamNode.look(
                at: end,
                up: upVector,
                localFront: SCNVector3(0, 1, 0)
            )
            laserDotNode.position = end
        }

        private func resetPlayer() {
            player.physicsBody?.clearAllForces()
            player.physicsBody?.velocity = SCNVector3Zero
            player.position = SCNVector3(3.8, 0.9, 3.8)
            player.physicsBody?.resetTransform()
            playerFacingYaw = .pi
            player.eulerAngles = SCNVector3Zero
            playerVisual.eulerAngles = SCNVector3(0, playerFacingYaw, 0)
            footstepCountdown = 0
            jumpQueued = false
            resetCamera()
            updateCamera(dt: 0, snap: true)
        }

        private func applyReflectionMode(enabled: Bool) {
            guard appliedReflectionMode != enabled else { return }
            appliedReflectionMode = enabled

            renderer?.antialiasingMode = enabled ? .multisampling4X : .multisampling2X
            scene.lightingEnvironment.intensity = enabled ? 0.88 : 0.7
            camera.camera?.wantsHDR = false
            camera.camera?.bloomIntensity = 0
            camera.camera?.screenSpaceAmbientOcclusionIntensity = 0
            lampLight?.castsShadow = true
            let postLevel = lightStates.effectiveIntensity(.post)
            lampLight?.intensity = CGFloat(postLevel) * 580
            mirrorBounceLight?.intensity = enabled ? 145 : 0

            for material in sceneMaterials {
                material.lightingModel = enabled ? .physicallyBased : .blinn
                material.specular.contents = enabled
                    ? UIColor(white: 0.52, alpha: 1)
                    : UIColor(white: 0.14, alpha: 1)
                material.shininess = enabled ? 75 : 20
            }

            if let poolCopingMaterial {
                poolCopingMaterial.roughness.contents = enabled ? 0.24 : 0.82
                poolCopingMaterial.metalness.contents = enabled ? 0.12 : 0.0
            }

            if let mirrorFrameMaterial {
                mirrorFrameMaterial.roughness.contents = enabled ? 0.12 : 0.46
                mirrorFrameMaterial.metalness.contents = enabled ? 0.82 : 0.16
            }

            for material in stoneMaterials {
                material.roughness.contents = enabled ? 0.3 : 0.88
                material.metalness.contents = 0.0
                material.specular.contents = enabled
                    ? UIColor(white: 0.72, alpha: 1)
                    : UIColor(white: 0.12, alpha: 1)
            }

            if let mirrorMaterial {
                if let mirrorColorTexture {
                    mirrorMaterial.lightingModel = .constant
                    mirrorMaterial.diffuse.contents = mirrorColorTexture
                    mirrorMaterial.multiply.contents = enabled
                        ? UIColor.white
                        : UIColor(white: 0.82, alpha: 1)
                    mirrorMaterial.emission.contents = UIColor.black
                    mirrorMaterial.reflective.contents = UIColor.black
                    mirrorMaterial.specular.contents = UIColor.black
                } else {
                    mirrorMaterial.lightingModel = .blinn
                    mirrorMaterial.diffuse.contents = UIColor(red: 0.24, green: 0.30, blue: 0.36, alpha: 1)
                    mirrorMaterial.metalness.contents = 0.0
                    mirrorMaterial.roughness.contents = 0.2
                    mirrorMaterial.reflective.contents = UIColor.black
                    mirrorMaterial.specular.contents = UIColor(white: 0.78, alpha: 1)
                    mirrorMaterial.emission.contents = UIColor.black
                }
            }

            water.setAdvancedReflections(enabled)
        }

        private func makeMaterial(color: UIColor, roughness: CGFloat, metalness: CGFloat = 0) -> SCNMaterial {
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = color
            material.roughness.contents = roughness
            material.metalness.contents = metalness
            sceneMaterials.append(material)
            return material
        }

        private func makeMatteMaterial(color: UIColor) -> SCNMaterial {
            let material = SCNMaterial()
            material.lightingModel = .physicallyBased
            material.diffuse.contents = color
            material.roughness.contents = 0.92
            material.metalness.contents = 0.0
            material.specular.contents = UIColor(white: 0.04, alpha: 1)
            return material
        }

        @discardableResult
        private func addBox(
            size: SCNVector3,
            position: SCNVector3,
            material: SCNMaterial,
            blocksCamera: Bool = false
        ) -> SCNNode {
            let geometry = SCNBox(
                width: CGFloat(size.x),
                height: CGFloat(size.y),
                length: CGFloat(size.z),
                chamferRadius: 0.025
            )
            geometry.firstMaterial = material
            let node = SCNNode(geometry: geometry)
            node.position = position
            scene.rootNode.addChildNode(node)
            installStaticPhysics(on: node, blocksCamera: blocksCamera)
            return node
        }

        @discardableResult
        private func addDecorativeBox(size: SCNVector3, position: SCNVector3, material: SCNMaterial) -> SCNNode {
            let geometry = SCNBox(
                width: CGFloat(size.x),
                height: CGFloat(size.y),
                length: CGFloat(size.z),
                chamferRadius: 0.02
            )
            geometry.firstMaterial = material
            let node = SCNNode(geometry: geometry)
            node.position = position
            scene.rootNode.addChildNode(node)
            return node
        }

        private func addStrip(center: SCNVector3, size: SCNVector3, color: UIColor) {
            let geometry = SCNBox(
                width: CGFloat(size.x),
                height: CGFloat(size.y),
                length: CGFloat(size.z),
                chamferRadius: 0.01
            )
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = color
            material.emission.contents = color
            fixedLightMaterials.append((material, color, .poolStrips))
            geometry.firstMaterial = material
            let node = SCNNode(geometry: geometry)
            node.position = center
            scene.rootNode.addChildNode(node)
        }

        private func installStaticPhysics(on node: SCNNode, blocksCamera: Bool = false) {
            guard let geometry = node.geometry else { return }
            let shape = SCNPhysicsShape(geometry: geometry, options: nil)
            let body = SCNPhysicsBody(type: .static, shape: shape)
            body.categoryBitMask = PhysicsCategory.world | (blocksCamera ? PhysicsCategory.cameraBlocker : 0)
            body.collisionBitMask = PhysicsCategory.player
            body.contactTestBitMask = PhysicsCategory.player
            body.friction = 0.9
            node.physicsBody = body
        }
    }
}

final class WaterSurface {
    private let columns = 28
    private let rows = 20
    private let damping: Float = 0.978
    private let stiffness: Float = 31
    private let propagation: Float = 0.68

    private let node = SCNNode()
    private let material = SCNMaterial()
    private var width: Float = 1
    private var length: Float = 1
    private var heights: [Float] = []
    private var velocities: [Float] = []
    private var positions: [SCNVector3] = []
    private var normals: [SCNVector3] = []
    private var indices: [UInt32] = []
    private var lastAmbientRipple: Float = 0

    func configure(in parent: SCNNode, center: SCNVector3, width: Float, length: Float) {
        self.width = width
        self.length = length
        node.name = "waterSurface"
        node.position = center
        node.renderingOrder = 3
        configureMaterial()
        buildMesh()
        parent.addChildNode(node)
    }

    func owns(_ candidate: SCNNode) -> Bool {
        var current: SCNNode? = candidate
        while let examined = current {
            if examined === node { return true }
            current = examined.parent
        }
        return false
    }

    func disturb(atWorldPosition worldPosition: SCNVector3, strength: Float) {
        let local = node.convertPosition(worldPosition, from: nil)
        disturb(localX: local.x, localZ: local.z, strength: strength, radius: 0.72)
    }

    func setAdvancedReflections(_ enabled: Bool) {
        if enabled {
            material.lightingModel = .physicallyBased
            material.diffuse.contents = UIColor(red: 0.035, green: 0.075, blue: 0.08, alpha: 0.50)
            material.metalness.contents = 0.0
            material.roughness.contents = 0.045
            material.specular.contents = UIColor.white
            material.reflective.contents = UIColor.black
            material.emission.contents = UIColor(red: 0.005, green: 0.015, blue: 0.018, alpha: 1)
            material.transparency = 0.62
        } else {
            material.lightingModel = .blinn
            material.diffuse.contents = UIColor(red: 0.025, green: 0.065, blue: 0.07, alpha: 0.72)
            material.metalness.contents = 0.0
            material.roughness.contents = 0.42
            material.specular.contents = UIColor(white: 0.4, alpha: 1)
            material.reflective.contents = UIColor.black
            material.emission.contents = UIColor(red: 0.004, green: 0.012, blue: 0.014, alpha: 1)
            material.transparency = 0.76
        }
    }

    func update(dt: Float, time: Float) {
        guard !heights.isEmpty else { return }

        if time - lastAmbientRipple > 3.1 {
            lastAmbientRipple = time
            disturb(
                localX: sin(time * 0.63) * width * 0.28,
                localZ: cos(time * 0.47) * length * 0.25,
                strength: 0.15,
                radius: 0.62
            )
        }

        for z in 1..<(rows - 1) {
            for x in 1..<(columns - 1) {
                let i = index(x, z)
                let neighbors = heights[index(x - 1, z)]
                    + heights[index(x + 1, z)]
                    + heights[index(x, z - 1)]
                    + heights[index(x, z + 1)]
                let laplacian = neighbors * 0.25 - heights[i]
                velocities[i] += (laplacian * propagation - heights[i] * 0.35) * stiffness * dt
                velocities[i] *= damping
            }
        }

        for i in heights.indices {
            heights[i] += velocities[i] * dt
        }

        rebuildGeometry()
    }

    private func configureMaterial() {
        material.isDoubleSided = true
        material.blendMode = .alpha
        material.writesToDepthBuffer = true
        setAdvancedReflections(false)
    }

    private func buildMesh() {
        let count = columns * rows
        heights = Array(repeating: 0, count: count)
        velocities = Array(repeating: 0, count: count)
        positions = Array(repeating: SCNVector3Zero, count: count)
        normals = Array(repeating: SCNVector3(0, 1, 0), count: count)
        indices.removeAll(keepingCapacity: true)

        for z in 0..<rows {
            for x in 0..<columns {
                let fx = (Float(x) / Float(columns - 1) - 0.5) * width
                let fz = (Float(z) / Float(rows - 1) - 0.5) * length
                positions[index(x, z)] = SCNVector3(fx, 0, fz)
            }
        }

        for z in 0..<(rows - 1) {
            for x in 0..<(columns - 1) {
                let a = UInt32(index(x, z))
                let b = UInt32(index(x + 1, z))
                let c = UInt32(index(x, z + 1))
                let d = UInt32(index(x + 1, z + 1))
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }

        rebuildGeometry()
    }

    private func rebuildGeometry() {
        let cellX = width / Float(columns - 1)
        let cellZ = length / Float(rows - 1)

        for z in 0..<rows {
            for x in 0..<columns {
                let i = index(x, z)
                let fx = (Float(x) / Float(columns - 1) - 0.5) * width
                let fz = (Float(z) / Float(rows - 1) - 0.5) * length
                positions[i] = SCNVector3(fx, heights[i], fz)
            }
        }

        for z in 1..<(rows - 1) {
            for x in 1..<(columns - 1) {
                let left = heights[index(x - 1, z)]
                let right = heights[index(x + 1, z)]
                let up = heights[index(x, z - 1)]
                let down = heights[index(x, z + 1)]
                var normal = SCNVector3((left - right) / cellX, 1, (up - down) / cellZ)
                let length = max(0.001, sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z))
                normal.x /= length
                normal.y /= length
                normal.z /= length
                normals[index(x, z)] = normal
            }
        }

        let vertexSource = SCNGeometrySource(vertices: positions)
        let normalSource = SCNGeometrySource(normals: normals)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
        geometry.materials = [material]
        node.geometry = geometry
    }

    private func disturb(localX: Float, localZ: Float, strength: Float, radius: Float) {
        for z in 1..<(rows - 1) {
            for x in 1..<(columns - 1) {
                let px = (Float(x) / Float(columns - 1) - 0.5) * width
                let pz = (Float(z) / Float(rows - 1) - 0.5) * length
                let distance = hypot(px - localX, pz - localZ)
                guard distance < radius else { continue }
                let falloff = 1 - distance / radius
                velocities[index(x, z)] -= strength * falloff * falloff
            }
        }
    }

    private func index(_ x: Int, _ z: Int) -> Int {
        z * columns + x
    }
}

#endif

final class ChiptuneAudioEngine {
    private let engine = AVAudioEngine()
    private let musicNode = AVAudioPlayerNode()
    private let glideNode = AVAudioPlayerNode()
    private let effectsNode = AVAudioPlayerNode()
    private let waterNode = AVAudioPlayerNode()
    private let splashNode = AVAudioPlayerNode()
    private let landingNode = AVAudioPlayerNode()
    private let masterMixer = AVAudioMixerNode()
    private let underwaterEQ = AVAudioUnitEQ(numberOfBands: 1)
    private let slowMoTimePitch = AVAudioUnitTimePitch()
    private let slowMoFXNode = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private let audioQueue = DispatchQueue(label: "com.codex.salonjoystick3d.audio", qos: .userInitiated)
    private var musicBuffer: AVAudioPCMBuffer?
    private var rainbowMusicBuffer: AVAudioPCMBuffer?
    private var underwaterMusicBuffer: AVAudioPCMBuffer?
    private var isInRainbowHallZone = false
    private var isInUnderwaterZone = false
    private var waterBuffer: AVAudioPCMBuffer?
    private var glideBuffer: AVAudioPCMBuffer?
    private var splashBuffers: [AVAudioPCMBuffer] = []
    private var landingBuffers: [AVAudioPCMBuffer] = []
    private var laserIgnitionBuffer: AVAudioPCMBuffer?
    private var laserPlayerHitBuffer: AVAudioPCMBuffer?
    private var laserReflectionBuffer: AVAudioPCMBuffer?
    private var robloxOofBuffer: AVAudioPCMBuffer?
    private var lightsaberDefeatBuffer: AVAudioPCMBuffer?
    private var slowMoActivationBuffer: AVAudioPCMBuffer?
    private var slowMoDeactivationBuffer: AVAudioPCMBuffer?
    private var subterraneanPortalBuffer: AVAudioPCMBuffer?
    private var swimStrokeBuffer: AVAudioPCMBuffer?
    private var recoveryChamberEnterBuffer: AVAudioPCMBuffer?
    private var recoveryCompleteBuffer: AVAudioPCMBuffer?
    private var teammateRevivePulseBuffer: AVAudioPCMBuffer?
    private var slimeDeflateBuffer: AVAudioPCMBuffer?
    private var airPumpStrokeBuffer: AVAudioPCMBuffer?
    private var balloonBouncePopBuffer: AVAudioPCMBuffer?
    private var nextSplash = 0
    private var nextLanding = 0
    private var nodesAttached = false
    private var started = false
    private var isPaused = false
    private var musicEnabled = true
    private var effectsEnabled = true
    private var waterEnabled = true
    private var glideIntensity: Float = 0
    private var waterMovementIntensity: Float = 0

    func start() {
        audioQueue.async { [weak self] in
            self?.startEngine()
        }
    }

    func setPaused(_ paused: Bool) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.isPaused = paused
            if paused {
                self.musicNode.pause()
                self.glideNode.volume = 0
                self.glideNode.pause()
                self.waterNode.volume = 0
                self.waterNode.pause()
                self.effectsNode.stop()
                self.splashNode.stop()
                self.landingNode.stop()
                self.slowMoFXNode.stop()
            } else {
                guard self.started else { return }
                if self.musicEnabled {
                    self.musicNode.play()
                }
                self.glideNode.play()
                self.waterNode.play()
                self.updateGlideVolume()
                self.updateWaterMovementVolume()
            }
        }
    }

    func stopAllNonMusicEffects() {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.glideIntensity = 0
            self.waterMovementIntensity = 0
            self.glideNode.volume = 0
            self.waterNode.volume = 0
            self.effectsNode.stop()
            self.splashNode.stop()
            self.landingNode.stop()
            self.slowMoFXNode.stop()
        }
    }

    func setMusicEnabled(_ enabled: Bool) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.musicEnabled = enabled
            let vol: Float = self.isInUnderwaterZone ? 0.42 : (self.isInRainbowHallZone ? 0.35 : 0.28)
            self.musicNode.volume = enabled ? vol : 0
        }
    }

    func setAudioZone(isUnderwater: Bool, isRainbowHall: Bool) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            if self.isInUnderwaterZone == isUnderwater && self.isInRainbowHallZone == isRainbowHall {
                return
            }
            self.isInUnderwaterZone = isUnderwater
            self.isInRainbowHallZone = isRainbowHall
            self.underwaterEQ.bands[0].bypass = !isUnderwater
            guard self.started else { return }

            self.musicNode.stop()
            let activeBuffer: AVAudioPCMBuffer?
            let targetVol: Float

            if isUnderwater {
                activeBuffer = self.underwaterMusicBuffer ?? self.musicBuffer
                targetVol = self.musicEnabled ? 0.42 : 0
                // La música subacuática ya tiene arreglo y ecualización abisal de alta definición;
                // bypass en el low-pass para evitar resonancias o amortiguación innecesaria.
                self.underwaterEQ.bands[0].bypass = true
            } else if isRainbowHall {
                activeBuffer = self.rainbowMusicBuffer ?? self.musicBuffer
                targetVol = self.musicEnabled ? 0.35 : 0
                self.underwaterEQ.bands[0].bypass = true
            } else {
                activeBuffer = self.musicBuffer
                targetVol = self.musicEnabled ? 0.28 : 0
                self.underwaterEQ.bands[0].bypass = true
            }

            if let activeBuffer {
                self.musicNode.volume = targetVol
                self.musicNode.scheduleBuffer(activeBuffer, at: nil, options: .loops)
                self.musicNode.play()
            }
        }
    }

    func setArenaZone(isRainbowHall: Bool) {
        setAudioZone(isUnderwater: isInUnderwaterZone, isRainbowHall: isRainbowHall)
    }

    func setUnderwaterZone(isUnderwater: Bool) {
        setAudioZone(isUnderwater: isUnderwater, isRainbowHall: isInRainbowHallZone)
    }

    func setEffectsEnabled(_ enabled: Bool) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.effectsEnabled = enabled
            self.updateGlideVolume()
            self.landingNode.volume = enabled ? 1 : 0
            if !enabled {
                self.effectsNode.stop()
            }
        }
    }

    func setWaterEnabled(_ enabled: Bool) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.waterEnabled = enabled
            self.updateWaterMovementVolume()
            self.splashNode.volume = enabled ? 0.58 : 0
        }
    }

    private func startEngine() {
        guard !started else { return }

        do {
            if musicBuffer == nil {
                musicBuffer = makeMusicBuffer()
                rainbowMusicBuffer = makeRainbowMusicBuffer()
                underwaterMusicBuffer = makeUnderwaterMusicBuffer()
                waterBuffer = makeWaterBuffer()
                glideBuffer = makeGlideBuffer()
                splashBuffers = [
                    makeSplashBuffer(variant: 0),
                    makeSplashBuffer(variant: 1),
                    makeSplashBuffer(variant: 2)
                ].compactMap { $0 }
                landingBuffers = [makeLandingBuffer(variant: 0), makeLandingBuffer(variant: 1)].compactMap { $0 }
                laserIgnitionBuffer = makeLaserIgnitionBuffer()
                laserPlayerHitBuffer = makeLaserPlayerHitBuffer()
                laserReflectionBuffer = makeLaserReflectionBuffer()
                robloxOofBuffer = makeRobloxOofBuffer()
                lightsaberDefeatBuffer = makeLightsaberDefeatBuffer()
                slowMoActivationBuffer = makeSlowMotionActivationBuffer()
                slowMoDeactivationBuffer = makeSlowMotionDeactivationBuffer()
                subterraneanPortalBuffer = makeSubterraneanPortalBuffer()
                swimStrokeBuffer = makeSwimStrokeBuffer()
                recoveryChamberEnterBuffer = makeRecoveryChamberEnterBuffer()
                recoveryCompleteBuffer = makeRecoveryCompleteBuffer()
                teammateRevivePulseBuffer = makeTeammateRevivePulseBuffer()
                slimeDeflateBuffer = makeSlimeDeflateBuffer()
                airPumpStrokeBuffer = makeAirPumpStrokeBuffer()
                balloonBouncePopBuffer = makeBalloonBouncePopBuffer()
            }

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)

            underwaterEQ.bands[0].filterType = .lowPass
            underwaterEQ.bands[0].frequency = 1850.0
            underwaterEQ.bands[0].bandwidth = 0.85
            underwaterEQ.bands[0].bypass = true

            if !nodesAttached {
                engine.attach(musicNode)
                engine.attach(glideNode)
                engine.attach(effectsNode)
                engine.attach(waterNode)
                engine.attach(splashNode)
                engine.attach(landingNode)
                engine.attach(masterMixer)
                engine.attach(underwaterEQ)
                engine.attach(slowMoTimePitch)
                engine.attach(slowMoFXNode)

                engine.connect(musicNode, to: masterMixer, format: format)
                engine.connect(glideNode, to: masterMixer, format: format)
                engine.connect(effectsNode, to: masterMixer, format: format)
                engine.connect(waterNode, to: masterMixer, format: format)
                engine.connect(splashNode, to: masterMixer, format: format)
                engine.connect(landingNode, to: masterMixer, format: format)

                engine.connect(masterMixer, to: underwaterEQ, format: format)
                engine.connect(underwaterEQ, to: slowMoTimePitch, format: format)
                engine.connect(slowMoTimePitch, to: engine.mainMixerNode, format: format)
                engine.connect(slowMoFXNode, to: engine.mainMixerNode, format: format)
                nodesAttached = true
            }

            engine.prepare()
            try engine.start()
            started = true

            musicNode.volume = musicEnabled ? 0.28 : 0
            updateGlideVolume()
            updateWaterMovementVolume()
            splashNode.volume = waterEnabled ? 0.58 : 0
            landingNode.volume = effectsEnabled ? 1 : 0
            if let musicBuffer {
                musicNode.scheduleBuffer(musicBuffer, at: nil, options: .loops)
                musicNode.play()
            }
            if let waterBuffer {
                waterNode.scheduleBuffer(waterBuffer, at: nil, options: .loops)
                waterNode.play()
            }
            if let glideBuffer {
                glideNode.scheduleBuffer(glideBuffer, at: nil, options: .loops)
                glideNode.play()
            }
        } catch {
            print("Audio engine could not start: \(error.localizedDescription)")
        }
    }

    func setGlideIntensity(_ intensity: Float) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.glideIntensity = max(0, min(1, intensity))
            self.updateGlideVolume()
        }
    }

    func setWaterMovementIntensity(_ intensity: Float) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.waterMovementIntensity = max(0, min(1, intensity))
            self.updateWaterMovementVolume()
        }
    }

    func playWaterDisturbance(intensity: Float) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            guard self.started, self.waterEnabled, !self.isPaused, !self.splashBuffers.isEmpty else { return }
            let index = self.nextSplash % self.splashBuffers.count
            self.nextSplash += 1
            self.splashNode.volume = 0.26 + max(0, min(1, intensity)) * 0.14
            self.splashNode.rate = 1.0
            self.splashNode.scheduleBuffer(self.splashBuffers[index])
            if !self.splashNode.isPlaying {
                self.splashNode.play()
            }
        }
    }

    func playUnderwaterGlug(intensity: Float) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            guard self.started, self.waterEnabled, !self.isPaused, !self.splashBuffers.isEmpty else { return }
            let index = self.nextSplash % self.splashBuffers.count
            self.nextSplash += 1
            self.splashNode.volume = 0.22 + max(0, min(1, intensity)) * 0.14
            self.splashNode.rate = 0.62 // Submerged low-frequency bubble resonance!
            self.splashNode.scheduleBuffer(self.splashBuffers[index])
            if !self.splashNode.isPlaying {
                self.splashNode.play()
            }
        }
    }

    func playLaserPlayerHitSound() {
        audioQueue.async { [weak self] in
            guard let self, self.started, self.effectsEnabled, !self.isPaused else { return }
            if let laserPlayerHitBuffer = self.laserPlayerHitBuffer {
                self.effectsNode.volume = 0.65
                self.effectsNode.scheduleBuffer(laserPlayerHitBuffer)
                if !self.effectsNode.isPlaying {
                    self.effectsNode.play()
                }
            }
        }
    }

    func playLaserReflectionSound() {
        audioQueue.async { [weak self] in
            guard let self, self.started, self.effectsEnabled, !self.isPaused else { return }
            if let laserReflectionBuffer = self.laserReflectionBuffer {
                self.effectsNode.volume = 0.60
                self.effectsNode.scheduleBuffer(laserReflectionBuffer)
                if !self.effectsNode.isPlaying {
                    self.effectsNode.play()
                }
            }
        }
    }

    func playRobloxOofDefeatSound() {
        audioQueue.async { [weak self] in
            guard let self, self.started, self.effectsEnabled else { return }
            if let robloxOofBuffer = self.robloxOofBuffer {
                self.effectsNode.stop()
                self.effectsNode.volume = 0.72
                self.effectsNode.scheduleBuffer(robloxOofBuffer)
                self.effectsNode.play()
            }
        }
    }

    func playLightsaberDefeatSound() {
        audioQueue.async { [weak self] in
            guard let self, self.started, self.effectsEnabled else { return }
            if let buffer = self.lightsaberDefeatBuffer {
                self.effectsNode.stop()
                self.effectsNode.volume = 0.78
                self.effectsNode.scheduleBuffer(buffer)
                self.effectsNode.play()
            }
        }
    }

    func playRecoveryChamberEnterSound() {
        audioQueue.async { [weak self] in
            guard let self, self.started, self.effectsEnabled, !self.isPaused, let buffer = self.recoveryChamberEnterBuffer else { return }
            self.effectsNode.volume = 0.52
            self.effectsNode.scheduleBuffer(buffer)
            if !self.effectsNode.isPlaying {
                self.effectsNode.play()
            }
        }
    }

    func playRecoveryCompleteSound() {
        audioQueue.async { [weak self] in
            guard let self, self.started, self.effectsEnabled, !self.isPaused, let buffer = self.recoveryCompleteBuffer else { return }
            self.effectsNode.volume = 0.65
            self.effectsNode.scheduleBuffer(buffer)
            if !self.effectsNode.isPlaying {
                self.effectsNode.play()
            }
        }
    }

    func playTeammateRevivePulseSound() {
        audioQueue.async { [weak self] in
            guard let self, self.started, self.effectsEnabled, !self.isPaused, let buffer = self.teammateRevivePulseBuffer else { return }
            self.effectsNode.volume = 0.60
            self.effectsNode.scheduleBuffer(buffer)
            if !self.effectsNode.isPlaying {
                self.effectsNode.play()
            }
        }
    }

    func playSlimeDeflateSound() {
        audioQueue.async { [weak self] in
            guard let self, self.started, self.effectsEnabled, let buffer = self.slimeDeflateBuffer else { return }
            self.effectsNode.stop()
            self.effectsNode.volume = 0.52
            self.effectsNode.scheduleBuffer(buffer)
            self.effectsNode.play()
        }
    }

    func playAirPumpStrokeSound() {
        audioQueue.async { [weak self] in
            guard let self, self.started, self.effectsEnabled, !self.isPaused, let buffer = self.airPumpStrokeBuffer else { return }
            self.effectsNode.volume = 0.48
            self.effectsNode.scheduleBuffer(buffer)
            if !self.effectsNode.isPlaying {
                self.effectsNode.play()
            }
        }
    }

    func playBalloonBouncePopSound() {
        audioQueue.async { [weak self] in
            guard let self, self.started, self.effectsEnabled, !self.isPaused, let buffer = self.balloonBouncePopBuffer else { return }
            self.effectsNode.volume = 0.58
            self.effectsNode.scheduleBuffer(buffer)
            if !self.effectsNode.isPlaying {
                self.effectsNode.play()
            }
        }
    }

    func setSlowMotion(_ active: Bool) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            if active {
                // Pitch down master audio by -900 cents (9 semitones deeper, heavy cinematic bass)
                self.slowMoTimePitch.pitch = -900
                self.slowMoTimePitch.rate = 0.50
                self.playSlowMoActivationSound()
            } else {
                self.slowMoTimePitch.pitch = 0
                self.slowMoTimePitch.rate = 1.0
                self.playSlowMoDeactivationSound()
            }
        }
    }

    private func playSlowMoActivationSound() {
        guard started, effectsEnabled, let buffer = slowMoActivationBuffer else { return }
        slowMoFXNode.stop()
        slowMoFXNode.volume = 0.78
        slowMoFXNode.scheduleBuffer(buffer, at: nil)
        slowMoFXNode.play()
    }

    private func playSlowMoDeactivationSound() {
        guard started, effectsEnabled, let buffer = slowMoDeactivationBuffer else { return }
        slowMoFXNode.stop()
        slowMoFXNode.volume = 0.68
        slowMoFXNode.scheduleBuffer(buffer, at: nil)
        slowMoFXNode.play()
    }

    func playSubterraneanPortalPlungeSound() {
        audioQueue.async { [weak self] in
            guard let self, self.started, self.effectsEnabled, !self.isPaused else { return }
            if let buffer = self.subterraneanPortalBuffer {
                self.slowMoFXNode.stop()
                self.slowMoFXNode.volume = 0.75
                self.slowMoFXNode.scheduleBuffer(buffer, at: nil)
                self.slowMoFXNode.play()
            }
        }
    }

    func playSwimStrokeSound(intensity: Float = 0.80) {
        audioQueue.async { [weak self] in
            guard let self, self.started, self.waterEnabled, !self.isPaused else { return }
            if let buffer = self.swimStrokeBuffer {
                self.splashNode.stop()
                // Estándar de audio para videojuegos: Foley de movimiento a -10 dB de la música (0.18 - 0.28)
                self.splashNode.volume = 0.18 + max(0, min(1, intensity)) * 0.10
                self.splashNode.scheduleBuffer(buffer, at: nil)
                self.splashNode.play()
            }
        }
    }

    func playLanding(intensity: Float) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            guard self.started, self.effectsEnabled, !self.isPaused, !self.landingBuffers.isEmpty else { return }
            let index = self.nextLanding % self.landingBuffers.count
            self.nextLanding += 1
            // Foley de impacto de aterrizaje balanceado (-10 dB de BGM)
            self.landingNode.volume = 0.22 + max(0, min(1, intensity)) * 0.12
            self.landingNode.scheduleBuffer(self.landingBuffers[index])
            if !self.landingNode.isPlaying {
                self.landingNode.play()
            }
        }
    }

    func playLaserIgnition() {
        audioQueue.async { [weak self] in
            guard let self else { return }
            guard self.started, self.effectsEnabled, !self.isPaused else { return }
            if let laserIgnitionBuffer = self.laserIgnitionBuffer {
                self.effectsNode.volume = 0.55
                self.effectsNode.scheduleBuffer(laserIgnitionBuffer)
                if !self.effectsNode.isPlaying {
                    self.effectsNode.play()
                }
            }
        }
    }

    private func makeLaserIgnitionBuffer() -> AVAudioPCMBuffer? {
        let duration = 0.42
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / format.sampleRate
            let progress = time / duration
            let pitchEnv = 1.0 + exp(-progress * 9.0) * 1.8
            let baseFreq = (420.0 + sin(time * 65.0) * 45.0) * pitchEnv
            let phase = 2.0 * Double.pi * baseFreq * time
            let envelope = sin(progress * Double.pi) * exp(-progress * 2.2)
            let synth = sin(phase) * 0.55 + (sin(phase * 2.0) * 0.28)
            let sample = Float(synth * envelope * 0.70)
            channels[0][frame] = sample
            if format.channelCount > 1 {
                channels[1][frame] = sample * 0.95
            }
        }
        return buffer
    }

    private func makeLaserPlayerHitBuffer() -> AVAudioPCMBuffer? {
        let duration = 0.35
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / format.sampleRate
            let progress = t / duration
            let freq = (650.0 - progress * 540.0) + sin(t * 180.0) * 60.0
            let phase = 2.0 * Double.pi * freq * t
            let envelope = sin(progress * Double.pi) * exp(-progress * 2.5)
            let synth = (sin(phase) + 0.45 * sin(phase * 1.5) + 0.25 * sin(phase * 3.0)) * envelope
            let sample = Float(synth * 0.80)
            channels[0][frame] = sample
            if format.channelCount > 1 {
                channels[1][frame] = sample * 0.94
            }
        }
        return buffer
    }

    // 🛡️ Desenfundar Escudo Metálico (Captain America / Vibranium Round Shield Unsheath & Resonant Plate Ring)
    private func makeLaserReflectionBuffer() -> AVAudioPCMBuffer? {
        let duration = 0.44
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount

        // Modos resonantes de disco metálico circular (Chladni plate modes: frecuencias fijas sin modulación)
        let modes: [(Double, Double, Double)] = [
            (1046.5, 0.45, 6.5),   // C6 fundamental
            (2180.0, 0.35, 8.5),   // modo (1,1)
            (3520.0, 0.22, 11.0),  // modo (2,1)
            (5210.0, 0.15, 14.0),  // modo (0,2)
            (7400.0, 0.08, 18.0)   // brillo superior
        ]

        // Filtro pasabanda resonante de 2 polos centrado en 3800 Hz (fricción de metal puro)
        var bpX1 = 0.0
        var bpX2 = 0.0
        var bpY1 = 0.0
        var bpY2 = 0.0

        let fCenter = 3800.0
        let bw = 850.0
        let omega = 2.0 * Double.pi * fCenter / format.sampleRate
        let alpha = sin(omega) * sinh(log(2.0) / 2.0 * bw * omega / sin(omega))
        let a0 = 1.0 + alpha
        let b0 = alpha / a0
        let b1 = 0.0
        let b2 = -alpha / a0
        let a1 = (-2.0 * cos(omega)) / a0
        let a2 = (1.0 - alpha) / a0

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / format.sampleRate
            let progress = t / duration

            // 1. Fricción metálica de desenfunde (ruido blanco filtrado en 3800Hz, transitorio de 0 a 65ms)
            let noiseIn = Double.random(in: -1.0...1.0)
            let noiseBP = b0 * noiseIn + b1 * bpX1 + b2 * bpX2 - a1 * bpY1 - a2 * bpY2
            bpX2 = bpX1
            bpX1 = noiseIn
            bpY2 = bpY1
            bpY1 = noiseBP

            let scrapeEnv = min(1.0, t * 160.0) * exp(-t * 36.0)
            let scrape = noiseBP * scrapeEnv * 0.95

            // 2. Clic mecánico de enganche en el antebrazo (latch snap a t = 12ms)
            let clickT = t - 0.012
            var click = 0.0
            if clickT >= 0 {
                let clickEnv = exp(-clickT * 85.0)
                click = (sin(2.0 * .pi * 1850.0 * clickT) * 0.5 + sin(2.0 * .pi * 3200.0 * clickT) * 0.5) * clickEnv * 0.65
            }

            // 3. Resonancia pura de campana/placa de vibranio (frecuencias 100% fijas, CERO vibrato, CERO efecto resorte)
            var ringL = 0.0
            var ringR = 0.0
            let strikeT = t - 0.008
            if strikeT >= 0 {
                for (idx, mode) in modes.enumerated() {
                    let (freq, amp, decay) = mode
                    let env = min(1.0, strikeT * 220.0) * exp(-strikeT * decay)
                    let phaseL = 2.0 * .pi * freq * strikeT
                    let phaseR = phaseL + 0.35 * Double(idx + 1)
                    ringL += sin(phaseL) * amp * env
                    ringR += sin(phaseR) * amp * env
                }
            }

            // Cuerpo metálico grave (135 Hz con caída rápida en 35ms)
            let thump = sin(2.0 * .pi * 135.0 * t) * min(1.0, t * 250.0) * exp(-t * 55.0) * 0.40

            let fadeOut = min(1.0, (1.0 - progress) * 6.0)
            let outL = tanh((scrape + click + ringL + thump) * 1.25) * fadeOut * 0.90
            let outR = tanh((scrape + click + ringR + thump) * 1.25) * fadeOut * 0.90

            channels[0][frame] = Float(outL)
            channels[1][frame] = Float(outR)
        }
        return buffer
    }

    private func makeRobloxOofBuffer() -> AVAudioPCMBuffer? {
        let duration = 0.28
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / format.sampleRate
            let progress = t / duration
            let freq = 240.0 * exp(-progress * 1.6)
            let phase = 2.0 * Double.pi * freq * t
            let envelope = sin(progress * Double.pi) * exp(-progress * 1.8)
            let wave = (sin(phase) + 0.35 * sin(phase * 2.0) + 0.15 * sin(phase * 3.0)) * envelope
            let sample = Float(wave * 0.85)
            channels[0][frame] = sample
            if format.channelCount > 1 {
                channels[1][frame] = sample * 0.94
            }
        }
        return buffer
    }

    private func makeLightsaberDefeatBuffer() -> AVAudioPCMBuffer? {
        let duration = 0.46
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / format.sampleRate
            let progress = t / duration

            // Envolvente con ataque agresivo y disipación de plasma
            let attack = min(1.0, progress * 45.0)
            let decay = exp(-progress * 4.2)
            let envelope = attack * decay

            // Frecuencia descendente de sable con zumbido resonante de 110Hz
            let baseFreq = 580.0 * exp(-progress * 1.8) + sin(t * 110.0 * 2.0 * .pi) * 45.0
            let phase = 2.0 * Double.pi * baseFreq * t

            // Armónicos densos característicos de hoja de plasma
            let wave = sin(phase) 
                     + 0.50 * sin(phase * 2.0) 
                     + 0.30 * sin(phase * 3.0) 
                     + 0.15 * sin(phase * 5.0)

            // Chisporroteo de desintegración
            let sparkNoise = Double.random(in: -1.0...1.0) * exp(-progress * 5.5) * 0.40

            // Saturación suave para el grosor de sable
            let combined = tanh((wave + sparkNoise) * 1.5) * envelope
            let val = Float(combined * 0.90)
            channels[0][frame] = val
            if format.channelCount > 1 {
                channels[1][frame] = val * 0.96
            }
        }
        return buffer
    }

    // ⚡ Modo Furia / Dead Eye / Black Ops Slow-Mo Activation Sound
    private func makeSlowMotionActivationBuffer() -> AVAudioPCMBuffer? {
        let duration = 1.35
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / format.sampleRate

            // 1. Sub-Bass Drop ("BWWOOOMMMM") - 165Hz sweeping down to 34Hz
            let bassFreq = 34.0 + 131.0 * exp(-t * 3.4)
            let bassPhase = 2.0 * .pi * bassFreq * t
            let bassEnv = min(1.0, t * 80.0) * exp(-t * 2.2)
            let subBass = tanh((sin(bassPhase) + 0.40 * sin(bassPhase * 2.0)) * 2.2) * bassEnv

            // 2. Vacuum Inhalation / Temporal Distortion Whoosh (t: 0.0 -> 0.38s)
            var whoosh: Double = 0
            if t < 0.38 {
                let wProgress = t / 0.38
                let wNoise = Double.random(in: -1.0...1.0)
                let wFreq = 180.0 + 950.0 * pow(wProgress, 2.0)
                let resonance = sin(2.0 * .pi * wFreq * t)
                whoosh = (wNoise * 0.4 + resonance * 0.6) * pow(wProgress, 2.8) * 0.70
            }

            // 3. Ethereal "Dead Eye" Resonant Bell / Chime (432Hz & 864Hz harmonic ring)
            var bellL: Double = 0
            var bellR: Double = 0
            if t >= 0.08 {
                let bt = t - 0.08
                let bEnv = min(1.0, bt * 120.0) * exp(-bt * 3.0)
                let bPhase1 = 2.0 * .pi * 432.0 * bt
                let bPhase2 = 2.0 * .pi * 864.0 * bt
                let bPhaseDetune = 2.0 * .pi * 435.5 * bt
                bellL = (sin(bPhase1) * 0.60 + sin(bPhase2) * 0.25) * bEnv
                bellR = (sin(bPhaseDetune) * 0.60 + sin(bPhase2) * 0.25) * bEnv
            }

            // 4. Visceral Adrenaline Heartbeat Pulses (Thump 1 at 0.38s, Thump 2 at 0.78s)
            var heart: Double = 0
            for thumpTime in [0.38, 0.78] {
                if t >= thumpTime && t < thumpTime + 0.25 {
                    let ht = t - thumpTime
                    let hFreq = 58.0 * exp(-ht * 8.0)
                    let hEnv = sin(ht / 0.25 * .pi)
                    heart += sin(2.0 * .pi * hFreq * ht) * hEnv * 0.85
                }
            }

            let left = tanh(subBass * 0.90 + whoosh * 0.50 + bellL * 0.55 + heart * 0.80)
            let right = tanh(subBass * 0.90 + whoosh * 0.50 + bellR * 0.55 + heart * 0.80)

            channels[0][frame] = Float(left * 0.95)
            channels[1][frame] = Float(right * 0.95)
        }
        return buffer
    }

    private func makeSlowMotionDeactivationBuffer() -> AVAudioPCMBuffer? {
        let duration = 0.38
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / format.sampleRate
            let progress = t / duration

            // Rising snap back to normal time: 45Hz sweeping to 320Hz
            let freq = 45.0 + 275.0 * pow(progress, 2.2)
            let phase = 2.0 * .pi * freq * t
            let env = sin(progress * .pi)
            let whoosh = sin(phase) * env
            let snap = progress > 0.85 ? Double.random(in: -0.6...0.6) * (1.0 - progress) * 6.0 : 0

            let val = Float(tanh((whoosh + snap) * 1.4) * 0.85)
            channels[0][frame] = val
            channels[1][frame] = val
        }
        return buffer
    }

    // 🎨🌊 Entrada al Easter Egg estilo Super Mario 64: "Painting Water Ripple" + Plop Cavitación + Arpegio Mágico de Campanas
    private func makeSubterraneanPortalBuffer() -> AVAudioPCMBuffer? {
        let duration = 1.35
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount

        // Notas del arpegio ascendente mágico (Super Mario 64 style pentatónico brillante: C5, E5, G5, B5, D6, G6)
        let chimeFreqs: [Double] = [523.25, 659.25, 783.99, 987.77, 1174.66, 1567.98]
        let noteSpacing = 0.046 // 46ms entre notas del arpegio rápido ascendente

        var lpNoise = 0.0
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / format.sampleRate
            let progress = t / duration

            // 1. "Bloop / Plop" de inmersión en el lienzo líquido (Frecuencia cayendo 740Hz -> 140Hz)
            let plungeFreq = 140.0 + 600.0 * exp(-t * 22.0)
            let plungeEnv = min(1.0, t * 80.0) * exp(-t * 8.5)
            let plungeBody = sin(2.0 * .pi * plungeFreq * t) * plungeEnv * 0.75

            // 2. Ondulación / Vibrato acuático del lienzo de la pintura (18Hz ripple modulation)
            let ripplePhase = sin(2.0 * .pi * 18.0 * t) * exp(-t * 2.8) * 0.35

            // 3. Arpegio Mágico Crystalline Chimes (Nintendo 64 Water Portal Harps / Shimmer)
            var chimeLeft = 0.0
            var chimeRight = 0.0
            for (idx, baseFreq) in chimeFreqs.enumerated() {
                let noteStart = Double(idx) * noteSpacing
                if t >= noteStart {
                    let noteT = t - noteStart
                    let noteEnv = min(1.0, noteT * 90.0) * exp(-noteT * 4.2)
                    // Frecuencia con ligera modulación de onda de agua
                    let modFreq = baseFreq * (1.0 + ripplePhase * 0.04)
                    // Tono fundamental cristalino + 2do y 3er armónicos suaves
                    let tone = (sin(2.0 * .pi * modFreq * noteT) +
                                sin(2.0 * .pi * modFreq * 2.0 * noteT) * 0.32 +
                                sin(2.0 * .pi * modFreq * 3.0 * noteT) * 0.12) * noteEnv

                    // Panning estéreo progresivo (viaja de izquierda a derecha al ascender)
                    let pan = Double(idx) / Double(chimeFreqs.count - 1)
                    chimeLeft += tone * (1.0 - pan * 0.65)
                    chimeRight += tone * (0.35 + pan * 0.65)
                }
            }

            // 4. Salpicadura suave y efervescencia de gotas al cruzar el portal
            let rawNoise = Double.random(in: -1.0...1.0)
            lpNoise = lpNoise * 0.82 + rawNoise * 0.18
            let sparkleDrop = lpNoise * exp(-t * 6.0) * 0.22

            let fadeOut = min(1.0, (1.0 - progress) * 7.5)
            let sampleL = Float(tanh((plungeBody * 0.80 + chimeLeft * 0.55 + sparkleDrop) * 1.3) * fadeOut * 0.92)
            let sampleR = Float(tanh((plungeBody * 0.80 + chimeRight * 0.55 + sparkleDrop) * 1.3) * fadeOut * 0.92)

            channels[0][frame] = sampleL
            channels[1][frame] = sampleR
        }
        return buffer
    }

    // 🏊‍♂️ Brazada Acuática Mario 64: Impulso fluido, suave y gratificante (Foley balanceado a -10 dB de la música)
    private func makeSwimStrokeBuffer() -> AVAudioPCMBuffer? {
        let duration = 0.36
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount

        var lowPass = 0.0
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / format.sampleRate
            let progress = t / duration
            let env = sin(progress * .pi) * exp(-progress * 2.2)
            let raw = Double.random(in: -1.0...1.0)
            lowPass = lowPass * 0.82 + raw * 0.18

            // Desplazamiento de agua suave (barrido de 120Hz a 240Hz sin graves saturados)
            let sweepFreq = 120.0 + 120.0 * sin(progress * .pi * 0.80)
            let body = sin(2.0 * .pi * sweepFreq * t) * 0.38
            let bubble = sin(2.0 * .pi * (340.0 + 90.0 * sin(t * 32.0)) * t) * exp(-t * 8.0) * 0.14
            let sample = Float(tanh((lowPass * 0.45 + body + bubble) * env) * 0.48)

            channels[0][frame] = sample
            if format.channelCount > 1 {
                channels[1][frame] = sample * 0.92
            }
        }
        return buffer
    }

    private func makeRecoveryChamberEnterBuffer() -> AVAudioPCMBuffer? {
        let duration = 0.60
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount

        var lpNoise: Double = 0
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / format.sampleRate
            let attack = min(1.0, t * 35.0)
            let decay = exp(-t * 3.2)
            let env = attack * decay

            // Tono profundo de activación de escudo stasis (D3 + A3 sin sweeps)
            let toneD3 = sin(2.0 * .pi * 146.83 * t)
            let toneA3 = sin(2.0 * .pi * 220.00 * t) * 0.65
            let subBass = sin(2.0 * .pi * 73.41 * t) * 0.45

            let rawNoise = Double.random(in: -1.0...1.0)
            lpNoise = lpNoise * 0.80 + rawNoise * 0.20
            let fieldSnap = lpNoise * exp(-t * 22.0) * 0.35

            let wave = (toneD3 + toneA3 + subBass + fieldSnap) * env
            let sample = Float(tanh(wave * 1.3) * 0.88)
            channels[0][frame] = sample
            if format.channelCount > 1 {
                channels[1][frame] = sample * 0.95
            }
        }
        return buffer
    }

    private func makeRecoveryCompleteBuffer() -> AVAudioPCMBuffer? {
        let duration = 0.90
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount

        let chimeNotes: [Double] = [523.25, 659.25, 783.99, 1046.50]
        let noteSpacing = 0.055

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / format.sampleRate
            var leftAcc = 0.0
            var rightAcc = 0.0

            for (idx, freq) in chimeNotes.enumerated() {
                let noteStart = Double(idx) * noteSpacing
                if t >= noteStart {
                    let noteT = t - noteStart
                    let noteEnv = min(1.0, noteT * 80.0) * exp(-noteT * 3.6)
                    let tone = (sin(2.0 * .pi * freq * noteT) +
                                sin(2.0 * .pi * freq * 2.0 * noteT) * 0.22) * noteEnv
                    let pan = Double(idx) / Double(chimeNotes.count - 1)
                    leftAcc += tone * (1.0 - pan * 0.6)
                    rightAcc += tone * (0.4 + pan * 0.6)
                }
            }

            let fadeOut = min(1.0, (duration - t) * 6.0)
            let sampleL = Float(tanh(leftAcc * 1.2) * fadeOut * 0.90)
            let sampleR = Float(tanh(rightAcc * 1.2) * fadeOut * 0.90)

            channels[0][frame] = sampleL
            if format.channelCount > 1 {
                channels[1][frame] = sampleR
            }
        }
        return buffer
    }

    private func makeTeammateRevivePulseBuffer() -> AVAudioPCMBuffer? {
        let duration = 0.40
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / format.sampleRate
            let attack = min(1.0, t * 50.0)
            let decay = exp(-t * 6.5)
            let env = attack * decay

            // Pulso de energía médica de alta velocidad (A5 + A6)
            let pulse = (sin(2.0 * .pi * 880.0 * t) +
                         sin(2.0 * .pi * 1760.0 * t) * 0.45) * env
            let sample = Float(tanh(pulse * 1.4) * 0.92)
            channels[0][frame] = sample
            if format.channelCount > 1 {
                channels[1][frame] = sample
            }
        }
        return buffer
    }

    private func makeSlimeDeflateBuffer() -> AVAudioPCMBuffer? {
        let duration = 0.75
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frameCount

        var lpNoise: Double = 0
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / format.sampleRate
            let attack = min(1.0, t * 60.0)
            let decay = exp(-t * 2.8)
            let env = attack * decay

            // Tono descendente cómico de globo pinchado perdiendo aire (520Hz bajando a 75Hz)
            let freq = 520.0 * exp(-t * 3.4) + 75.0
            let flutter = sin(2.0 * .pi * (42.0 - t * 28.0) * t) * 0.45
            let tone = sin(2.0 * .pi * freq * t) * (1.0 + flutter)

            let rawNoise = Double.random(in: -1.0...1.0)
            lpNoise = lpNoise * 0.82 + rawNoise * 0.18
            let airHiss = lpNoise * 0.42

            let sample = Float(tanh((tone * 0.65 + airHiss) * env * 1.35) * 0.88)
            channels[0][frame] = sample
            if format.channelCount > 1 {
                channels[1][frame] = sample * 0.95
            }
        }
        return buffer
    }

    private func makeAirPumpStrokeBuffer() -> AVAudioPCMBuffer? {
        let duration = 0.32
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frameCount

        var lpNoise: Double = 0
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / format.sampleRate
            // Golpe rápido de pistón mecánico al inicio (15ms)
            let pistonClick = sin(2.0 * .pi * 180.0 * t) * exp(-t * 85.0) * 0.55

            // Ráfaga de aire comprimido saliendo por la boquilla (fshhh!)
            let airAttack = min(1.0, t * 110.0)
            let airDecay = exp(-t * 9.5)
            let airEnv = airAttack * airDecay

            let rawNoise = Double.random(in: -1.0...1.0)
            lpNoise = lpNoise * 0.76 + rawNoise * 0.24
            let airRush = lpNoise * airEnv * 0.95

            let sample = Float(tanh((pistonClick + airRush) * 1.4) * 0.92)
            channels[0][frame] = sample
            if format.channelCount > 1 {
                channels[1][frame] = sample * 0.94
            }
        }
        return buffer
    }

    private func makeBalloonBouncePopBuffer() -> AVAudioPCMBuffer? {
        let duration = 0.55
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = frameCount

        let chimes: [Double] = [523.25, 659.25, 783.99, 1046.50] // C5, E5, G5, C6
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / format.sampleRate

            // Boing elástico de goma ascendente (120Hz a 480Hz en 60ms)
            let pitchSweep = min(480.0, 120.0 + t * 4500.0)
            let boing = sin(2.0 * .pi * pitchSweep * t) * exp(-t * 8.0) * 0.70

            // Pop brillante y alegre
            var chimeSum = 0.0
            if t > 0.04 {
                let ct = t - 0.04
                for freq in chimes {
                    chimeSum += sin(2.0 * .pi * freq * ct) * exp(-ct * 7.5) * 0.25
                }
            }

            let sample = Float(tanh((boing + chimeSum) * 1.35) * 0.90)
            channels[0][frame] = sample
            if format.channelCount > 1 {
                channels[1][frame] = sample * 0.96
            }
        }
        return buffer
    }

    private func makeMusicBuffer() -> AVAudioPCMBuffer? {
        let duration = 8.0
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount

        let melody: [Double] = [
            261.63, 329.63, 392.00, 523.25,
            392.00, 329.63, 293.66, 349.23,
            220.00, 293.66, 349.23, 440.00,
            349.23, 293.66, 246.94, 329.63
        ]
        let bass: [Double] = [130.81, 110.00, 87.31, 98.00]

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / format.sampleRate
            let section = min(3, Int(time / 2.0))
            let noteIndex = min(melody.count - 1, Int(time / 0.5))
            let noteTime = time.truncatingRemainder(dividingBy: 0.5)
            let attack = min(1.0, noteTime / 0.012)
            let decay = exp(-noteTime * 4.6)
            let envelope = attack * decay
            let leadPhase = 2 * Double.pi * melody[noteIndex] * time
            let lead = (sin(leadPhase) + sin(leadPhase * 2) * 0.12) * 0.038 * envelope
            let pad = sin(2 * Double.pi * bass[section] * time) * 0.010
            let shimmer = sin(2 * Double.pi * melody[noteIndex] * 0.5 * time) * 0.004
            let sample = Float(lead + pad + shimmer)

            channels[0][frame] = sample * 0.96
            channels[1][frame] = sample
        }

        return buffer
    }

    // 🌈 Banda Ambiental Synthwave / Parkour Cósmico para el Gran Salón Arcoíris
    private func makeRainbowMusicBuffer() -> AVAudioPCMBuffer? {
        let duration = 8.0
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount

        // Arpegio prismático rápido de 32 notas (F# menor / D mayor / A mayor / E mayor)
        let arpNotes: [Double] = [
            369.99, 440.00, 554.37, 739.99, 659.25, 554.37, 440.00, 554.37,
            293.66, 369.99, 440.00, 587.33, 659.25, 587.33, 440.00, 369.99,
            329.63, 440.00, 554.37, 659.25, 880.00, 659.25, 554.37, 440.00,
            329.63, 392.00, 493.88, 659.25, 739.99, 659.25, 493.88, 392.00
        ]
        let bassRoots: [Double] = [92.50, 73.42, 110.00, 82.41]

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / format.sampleRate
            let section = min(3, Int(time / 2.0))
            let stepDur = 0.50
            let noteIndex = min(arpNotes.count - 1, Int(time / stepDur))
            let noteTime = time.truncatingRemainder(dividingBy: stepDur)
            let attack = min(1.0, noteTime / 0.045)
            let decay = exp(-noteTime * 2.6)
            let env = attack * decay

            let freq = arpNotes[noteIndex]
            let leadL = (sin(2 * .pi * freq * time) + sin(2 * .pi * (freq * 2.0) * time) * 0.12) * 0.032 * env
            let leadR = (sin(2 * .pi * (freq * 1.002) * time) + sin(2 * .pi * (freq * 1.5) * time) * 0.10) * 0.032 * env

            // Bajo synth melódico cálido puro sin distorsión tanh ni golpe percusivo
            let bassFreq = bassRoots[section]
            let subBass = (sin(2 * .pi * bassFreq * time) * 0.018 + sin(2 * .pi * bassFreq * 0.5 * time) * 0.008)

            // Pad aéreo brillante arcoíris con paneo estéreo envolvente
            let shimmerL = sin(2 * .pi * (freq * 0.5) * time + sin(time * 0.8)) * 0.008
            let shimmerR = cos(2 * .pi * (freq * 0.5) * time + cos(time * 0.8)) * 0.008

            channels[0][frame] = Float(leadL + subBass + shimmerL)
            if format.channelCount > 1 {
                channels[1][frame] = Float(leadR + subBass + shimmerR)
            }
        }
        return buffer
    }

    // 🌊 🐋 Banda Sonora Acuática Abisal Submarina (Subterranean Ocean / Mystic Water Realm)
    // Atmósfera inmersiva profundamente emotiva inspirada en Donkey Kong Country (Aquatic Ambiance)
    // y Super Mario 64 (Dire Dire Docks): acordes etéreos suspendidos, Rhodes cristalino,
    // arpegios de arpa marina líquida y bajo subacuático envolvente.
    private func makeUnderwaterMusicBuffer() -> AVAudioPCMBuffer? {
        let duration = 24.0
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount

        // 4 Progresiones armónicas de 6 segundos de pura emoción cósmica (Ebmaj9 -> Cm9 -> Abmaj9#11 -> Bbsus4):
        let chords: [[Double]] = [
            [77.78, 116.54, 155.56, 196.00, 293.66, 349.23, 392.00], // Ebmaj9: Eb2, Bb2, Eb3, G3, D4, F4, G4
            [65.41, 98.00,  155.56, 196.00, 233.08, 293.66, 392.00], // Cm9: C2, G2, Eb3, G3, Bb3, D4, G4
            [51.91, 77.78,  130.81, 196.00, 261.63, 293.66, 392.00], // Abmaj9#11: Ab1, Eb2, C3, G3, C4, D4, G4
            [58.27, 87.31,  116.54, 155.56, 174.61, 233.08, 293.66]  // Bbsus4: Bb1, F2, Bb2, Eb3, F3, Bb3, D4
        ]
        let subBassFrequencies: [Double] = [38.89, 32.70, 51.91, 58.27] // Eb1, C1, Ab1, Bb1

        // Melodía principal poética y flotante estilo Rhodes acuático (16 notas de 1.5s cada una):
        let melodyNotes: [Double] = [
            392.00, 349.23, 293.66, 233.08, // G4, F4, D4, Bb3 (Inmersión en la profundidad)
            261.63, 311.13, 392.00, 466.16, // C4, Eb4, G4, Bb4 (Anhelo ascendente en el abismo)
            523.25, 466.16, 392.00, 293.66, // C5, Bb4, G4, D4 (Misterio majestuoso de Lumina)
            311.13, 349.23, 293.66, 311.13  // Eb4, F4, D4, Eb4 (Resolución cálida y pacífica)
        ]

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / format.sampleRate
            let section = min(3, Int(time / 6.0))
            let chord = chords[section]

            // 1. Acordes etéreos flotantes (Lush Stereo Chorus Pad con swell oceánico y fase estable sin distorsión):
            var padL = 0.0
            var padR = 0.0
            let oceanSwell = 0.75 + 0.25 * sin(2 * Double.pi * 0.12 * time)
            for (idx, noteFreq) in chord.enumerated() {
                let pPhase = 2 * Double.pi * noteFreq * time
                let vibPhase = sin(2 * Double.pi * 3.2 * time + Double(idx)) * 0.24
                let detunePhase = 2 * Double.pi * (noteFreq * (1.0 + Double(idx) * 0.0012)) * time
                let wave1 = sin(pPhase + vibPhase)
                let wave2 = sin(detunePhase - vibPhase + 0.5) * 0.45
                let voiceAmp = 0.022 / Double(idx + 1) * 1.8
                padL += (wave1 + wave2) * voiceAmp
                padR += (wave2 + wave1) * voiceAmp
            }
            padL *= oceanSwell
            padR *= oceanSwell

            // 2. Melodía Rhodes cristalina (fase independiente de time para evitar modulación explosiva o distorsión):
            let stepDuration = 1.50
            let noteIdx = min(melodyNotes.count - 1, Int(time / stepDuration))
            let noteTime = time.truncatingRemainder(dividingBy: stepDuration)
            let mAttack = min(1.0, noteTime / 0.04)
            let mDecay = exp(-noteTime * 1.8)
            let mEnv = mAttack * mDecay
            let mFreq = melodyNotes[noteIdx]
            let vibOffset = (noteTime > 0.35 ? sin(2 * Double.pi * 4.5 * (noteTime - 0.35)) * 0.22 : 0.0)
            let mPhase = 2 * Double.pi * mFreq * time + vibOffset
            // Timbre de piano eléctrico acuático (fundamental puro + armónicos sutiles cálidos):
            let rhodesL = (sin(mPhase) + sin(mPhase * 2.0) * 0.18 + sin(mPhase * 3.0) * 0.04) * mEnv * 0.052
            let rhodesR = (sin(mPhase + 0.15) + sin((mPhase + 0.15) * 2.0) * 0.18 + sin((mPhase + 0.15) * 3.0) * 0.04) * mEnv * 0.052

            // 3. Arpegio de arpa líquida cristalina (ripples que caen y suben cada 0.25s):
            let arpStep = 0.25
            let arpIdx = Int(time / arpStep) % chord.count
            let arpTime = time.truncatingRemainder(dividingBy: arpStep)
            let arpEnv = min(1.0, arpTime / 0.02) * exp(-arpTime * 6.5)
            let arpHarpFreq = chord[arpIdx] * 2.0
            let arpHarpPhase = 2 * Double.pi * arpHarpFreq * time
            let arpPan = Double(arpIdx) / Double(chord.count - 1)
            let arpHarp = sin(arpHarpPhase) * arpEnv * 0.016
            let harpL = arpHarp * (1.0 - arpPan * 0.6)
            let harpR = arpHarp * (0.4 + arpPan * 0.6)

            // 4. Bajo oceánico profundo abisal (32 - 58 Hz con calidez táctil):
            let bassFreq = subBassFrequencies[section]
            let subBass = (sin(2 * Double.pi * bassFreq * time) * 0.038 + sin(2 * Double.pi * bassFreq * 2.0 * time) * 0.012) * oceanSwell

            // 5. Mezcla estéreo inmersiva con limitador suave y margen dinámico (headroom):
            let mixL = padL * 0.78 + rhodesL * 1.15 + harpL * 0.85 + subBass
            let mixR = padR * 0.78 + rhodesR * 1.15 + harpR * 0.85 + subBass

            // 6. Crossfade transparente en bordes del loop para ciclo infinito continuo:
            let loopFade = min(1.0, min(time, duration - time) / 0.18)
            let finalL = Float(tanh(mixL * 1.05) * loopFade * 0.88)
            let finalR = Float(tanh(mixR * 1.05) * loopFade * 0.88)

            channels[0][frame] = finalL
            if format.channelCount > 1 {
                channels[1][frame] = finalR
            }
        }
        return buffer
    }

    // 🌊 Sonido Acuático Fluido:
    // Textura envolvente de agua líquida y burbujas procedurales orgánicas sin acordes tonales fijos
    // para armonizar a la perfección con la banda sonora sin provocar disonancias.
    private func makeWaterBuffer() -> AVAudioPCMBuffer? {
        let duration = 10.0
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount

        var seed = UInt32(0x72A4_91C3)
        var middleNoise = 0.0
        var lowNoise = 0.0

        for frame in 0..<Int(frameCount) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Double(seed & 0xFFFF) / 32_767.5 - 1.0
            middleNoise = middleNoise * 0.88 + noise * 0.12
            lowNoise = lowNoise * 0.985 + noise * 0.015

            let time = Double(frame) / format.sampleRate
            let edgeFade = min(1.0, min(time, duration - time) / 0.12)

            // 1. Oleaje de agua cristalina envolvente (Flujo líquido puro sin acordes tonales fijos)
            let surge = 0.85 +
                sin(2 * Double.pi * 0.35 * time) * 0.12 +
                sin(2 * Double.pi * 0.58 * time + 1.2) * 0.08
            let flowingWater = (middleNoise - lowNoise) * 0.18 + lowNoise * 0.28

            // 2. Burbujas saltarinas rítmicas orgánicas ("blup... gloop... blup-blup")
            let bPeriod1 = time.truncatingRemainder(dividingBy: 0.95)
            let bubble1 = (bPeriod1 < 0.08) ? (sin(2.0 * .pi * (320.0 + bPeriod1 * 950.0) * bPeriod1) * exp(-bPeriod1 * 55.0) * 0.024) : 0.0

            let bPeriod2 = (time + 0.45).truncatingRemainder(dividingBy: 1.35)
            let bubble2 = (bPeriod2 < 0.07) ? (sin(2.0 * .pi * (280.0 + bPeriod2 * 820.0) * bPeriod2) * exp(-bPeriod2 * 60.0) * 0.020) : 0.0

            let bPeriod3 = (time + 0.80).truncatingRemainder(dividingBy: 1.80)
            let bubble3 = (bPeriod3 < 0.06) ? (sin(2.0 * .pi * (410.0 + bPeriod3 * 1100.0) * bPeriod3) * exp(-bPeriod3 * 65.0) * 0.018) : 0.0

            let bubbleGurgles = bubble1 + bubble2 + bubble3

            // 3. Muestra final estéreo de textura acuática
            let sampleL = Float((flowingWater * surge + bubbleGurgles) * edgeFade)
            let sampleR = Float((flowingWater * surge * 0.95 - bubble1 * 0.4 + bubble2 * 0.7 + bubble3 * 0.5) * edgeFade)

            channels[0][frame] = sampleL
            if format.channelCount > 1 {
                channels[1][frame] = sampleR
            }
        }
        return buffer
    }

    // 💦 Chapuzón Estilo Mario 64: Entrada alegre al agua ("KER-SPLASH / BLOOP-WOOSH!")
    // Transitorio acústico nítido de ruptura de superficie + cavitación efervescente que rebota hacia arriba
    private func makeSplashBuffer(variant: Int) -> AVAudioPCMBuffer? {
        let duration = 0.52
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount

        var seed = UInt32(0x94D0_49BB) &+ UInt32(variant * 1049)
        var lowPass = 0.0
        var midBand = 0.0

        let baseCavityFreq = variant == 0 ? 190.0 : 240.0

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / format.sampleRate
            let progress = t / duration

            seed = seed &* 1_664_525 &+ 1_013_904_223
            let rawNoise = Double(seed & 0xFFFF) / 32_767.5 - 1.0

            // 1. Slap inicial de superficie (el "plup" brillante de Mario entrando a la alberca)
            let slapAttack = min(1.0, t / 0.0025)
            let slapDecay = exp(-t * 68.0)
            let slap = rawNoise * slapAttack * slapDecay * 0.58

            // 2. Cavitación flotante ascendente ("WWOO-OOP" - elevación de tono que transmite alegría y emoción)
            let pitchSweep = baseCavityFreq * (1.15 - 0.35 * exp(-t * 18.0) + 0.45 * sin(t * 24.0))
            let cavityEnv = min(1.0, t * 140.0) * exp(-t * 8.5)
            let cavityTone = sin(2.0 * .pi * pitchSweep * t) * cavityEnv * 0.72

            // 3. Efervescencia acuosa Mario 64 (resplandor de gotas y rocío)
            lowPass = lowPass * 0.82 + rawNoise * 0.18
            midBand = midBand * 0.65 + (rawNoise - lowPass) * 0.35
            let washEnv = min(1.0, t * 50.0) * exp(-t * 5.8)
            let waterWash = (lowPass * 0.50 + midBand * 0.32) * washEnv

            // 4. Clúster de burbujas sonoras que explotan al sumergirse
            let b1 = sin(2.0 * .pi * (480.0 + 180.0 * sin(t * 42.0)) * t) * exp(-t * 10.0) * 0.18
            let b2 = sin(2.0 * .pi * (720.0 + 220.0 * cos(t * 36.0)) * t) * exp(-t * 12.0) * 0.14

            let combined = (slap + cavityTone + waterWash + b1 + b2)
            let fadeOut = min(1.0, (1.0 - progress) * 6.5)
            let sample = Float(tanh(combined * 1.40) * fadeOut * 0.95)

            channels[0][frame] = sample
            channels[1][frame] = sample * (variant == 1 ? 0.88 : 0.95)
        }
        return buffer
    }

    private func makeGlideBuffer() -> AVAudioPCMBuffer? {
        let duration = 4.0
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / format.sampleRate
            let lift = 0.82 + sin(2 * Double.pi * 0.5 * time) * 0.14
            let hum = sin(2 * Double.pi * 92.5 * time) * 0.13
            let air = sin(2 * Double.pi * 185.0 * time + sin(2 * Double.pi * 0.5 * time) * 0.55) * 0.052
            let shimmer = sin(2 * Double.pi * 370.5 * time) * 0.022
            channels[0][frame] = Float((hum + air + shimmer) * lift)
            channels[1][frame] = Float((hum + air * 0.82 - shimmer * 0.72) * lift)
        }
        return buffer
    }

    private func makeLandingBuffer(variant: Int) -> AVAudioPCMBuffer? {
        let duration = 0.20
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount

        var seed = UInt32(0x5A17_2E91) &+ UInt32(variant * 7919)
        var dryNoise = 0.0
        for frame in 0..<Int(frameCount) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Double(seed & 0xFFFF) / 32_767.5 - 1.0
            dryNoise = dryNoise * 0.42 + noise * 0.58
            let time = Double(frame) / format.sampleRate
            let progress = time / duration
            let bodyFrequency = 112.0 + Double(variant) * 7.0 - progress * 48.0
            let body = sin(2 * Double.pi * bodyFrequency * time) * exp(-time * 19.0) * 0.38
            let contact = dryNoise * exp(-time * 42.0) * 0.34
            let sample = Float(body + contact)
            channels[0][frame] = sample
            channels[1][frame] = sample * 0.92
        }
        return buffer
    }

    private func updateGlideVolume() {
        glideNode.volume = effectsEnabled && glideIntensity > 0.01 && !isPaused
            ? 0.14 + glideIntensity * 0.36
            : 0
    }

    private func updateWaterMovementVolume() {
        waterNode.volume = waterEnabled && waterMovementIntensity > 0.01 && !isPaused
            ? 0.12 + waterMovementIntensity * 0.36
            : 0
    }

    private func triangle(frequency: Double, time: Double) -> Double {
        2.0 / Double.pi * asin(sin(2.0 * Double.pi * frequency * time))
    }

}

struct JoystickView: View {
    var onChanged: (CGVector) -> Void
    var isLiquidGlass: Bool = true
    @State private var knob = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size / 2
            let knobRadius = size * 0.27

            ZStack {
                if isLiquidGlass {
                    //  Apple Liquid Glass Translucent Outer Ring with Real Backdrop Blur
                    Circle()
                        .fill(.ultraThinMaterial)
                        .background(Color.white.opacity(0.12), in: Circle())
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.95), .cyan.opacity(0.70), .white.opacity(0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2.0
                        )
                        .shadow(color: .cyan.opacity(0.40), radius: 6)
                    // Liquid Glass Knob
                    Circle()
                        .fill(.ultraThinMaterial)
                        .background(Color.white.opacity(0.88), in: Circle())
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .shadow(color: .white.opacity(0.60), radius: 10)
                        .frame(width: knobRadius * 2, height: knobRadius * 2)
                        .offset(knob)
                } else {
                    Circle()
                        .fill(.black.opacity(0.42))
                    Circle()
                        .stroke(.white.opacity(0.3), lineWidth: 2)
                    Circle()
                        .fill(.white.opacity(0.92))
                        .frame(width: knobRadius * 2, height: knobRadius * 2)
                        .offset(knob)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dx = value.location.x - radius
                        let dy = value.location.y - radius
                        let maxDistance = radius - knobRadius
                        let vector = CGVector(dx: dx, dy: dy)
                        let distance = hypot(vector.dx, vector.dy)
                        let scale = distance > maxDistance ? maxDistance / distance : 1
                        knob = CGSize(width: vector.dx * scale, height: vector.dy * scale)
                        onChanged(CGVector(dx: knob.width / maxDistance, dy: knob.height / maxDistance))
                    }
                    .onEnded { _ in
                        knob = .zero
                        onChanged(.zero)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Joystick de movimiento")
            .accessibilityIdentifier("movementJoystick")
            .accessibilityAddTraits(.allowsDirectInteraction)
        }
    }
}

// 🧭 Minimapa Radar Táctico 3D estilo Apple Liquid Glass
struct TacticalMinimapView: View {
    @ObservedObject var model: GameModel
    @State private var isFullView: Bool = false

    var body: some View {
        let size: CGFloat = isFullView ? 155 : 98
        let radius: CGFloat = size / 2
        let worldRadius: Float = isFullView ? 46.0 : 23.0
        let pxPerMeter = radius / CGFloat(worldRadius)
        let playerPos = model.localPlayerPosition
        let playerYaw = model.localPlayerYaw

        ZStack {
            // Fondo de Cristal Líquido Translúcido
            Circle()
                .fill(Color.black.opacity(0.65))
                .background(.ultraThinMaterial, in: Circle())

            // Rejilla Concéntrica de Radar Táctico
            Circle()
                .stroke(Color.cyan.opacity(0.20), lineWidth: 1)
                .frame(width: size * 0.52, height: size * 0.52)
            Circle()
                .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
                .frame(width: size * 0.94, height: size * 0.94)

            // Ejes de Cruz Radar
            Path { path in
                path.move(to: CGPoint(x: radius, y: 5))
                path.addLine(to: CGPoint(x: radius, y: size - 5))
                path.move(to: CGPoint(x: 5, y: radius))
                path.addLine(to: CGPoint(x: size - 5, y: radius))
            }
            .stroke(Color.cyan.opacity(0.18), lineWidth: 1)

            // Contenido del Mapa proyectado relativo al jugador
            Group {
                // 1. Salón Arcoíris (Z = 17.8 a 72.0, X = -27.0 a 27.0)
                let rainbowW = CGFloat(54.0) * pxPerMeter
                let rainbowH = CGFloat(72.0 - 17.8) * pxPerMeter
                let rainbowCenterX = radius + CGFloat(0.0 - playerPos.x) * pxPerMeter
                let rainbowCenterY = radius + CGFloat(44.9 - playerPos.z) * pxPerMeter
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.red.opacity(0.15), .yellow.opacity(0.12), .green.opacity(0.12), .blue.opacity(0.15), .purple.opacity(0.15)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(Rectangle().stroke(Color.purple.opacity(0.35), lineWidth: 1))
                    .frame(width: rainbowW, height: rainbowH)
                    .position(x: rainbowCenterX, y: rainbowCenterY)

                // 2. Muros Perimetrales del Patio Piscina (Z = -17.8 a 17.8, X = -17.8 a 17.8)
                let arenaW = CGFloat(35.6) * pxPerMeter
                let arenaH = CGFloat(35.6) * pxPerMeter
                let arenaCenterX = radius + CGFloat(0.0 - playerPos.x) * pxPerMeter
                let arenaCenterY = radius + CGFloat(0.0 - playerPos.z) * pxPerMeter
                Rectangle()
                    .stroke(Color.white.opacity(0.35), lineWidth: 1.2)
                    .frame(width: arenaW, height: arenaH)
                    .position(x: arenaCenterX, y: arenaCenterY)

                // 3. Piscina Central (Agua): [-5.35, 2.35] en X, [-4.2, 1.2] en Z
                let poolW = CGFloat(2.35 - (-5.35)) * pxPerMeter
                let poolH = CGFloat(1.20 - (-4.20)) * pxPerMeter
                let poolCenterX = radius + CGFloat(-1.50 - playerPos.x) * pxPerMeter
                let poolCenterY = radius + CGFloat(-1.50 - playerPos.z) * pxPerMeter
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.cyan.opacity(0.28))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.cyan.opacity(0.65), lineWidth: 1))
                    .frame(width: poolW, height: poolH)
                    .position(x: poolCenterX, y: poolCenterY)

                // 4. Muro Divisorio Sur (Z = 17.8) con Gran Pórtico Abierto en el Centro
                let wallY = radius + CGFloat(17.8 - playerPos.z) * pxPerMeter
                let portalX = radius + CGFloat(0.0 - playerPos.x) * pxPerMeter
                Path { p in
                    let leftX1 = radius + CGFloat(-17.8 - playerPos.x) * pxPerMeter
                    let leftX2 = radius + CGFloat(-5.2 - playerPos.x) * pxPerMeter
                    p.move(to: CGPoint(x: leftX1, y: wallY))
                    p.addLine(to: CGPoint(x: leftX2, y: wallY))

                    let rightX1 = radius + CGFloat(5.2 - playerPos.x) * pxPerMeter
                    let rightX2 = radius + CGFloat(17.8 - playerPos.x) * pxPerMeter
                    p.move(to: CGPoint(x: rightX1, y: wallY))
                    p.addLine(to: CGPoint(x: rightX2, y: wallY))
                }
                .stroke(Color.white.opacity(0.65), lineWidth: 2)

                // Portal Arcoíris en (0, 17.8)
                Image(systemName: "sparkles")
                    .font(.system(size: isFullView ? 11 : 8, weight: .bold))
                    .foregroundStyle(model.playerScore >= 3000 ? Color.yellow : Color.cyan)
                    .position(x: portalX, y: wallY)
            }
            .clipShape(Circle()) // Recorta cualquier geometría que se salga del círculo

            // 💡 Puntos de Luminarias de la Arena (Poste, Neón Piscina, Neón Sheerit, Borde Piscina)
            let lightPoints: [(fixture: GameLightFixture, x: Float, z: Float, isOn: Bool, color: Color)] = [
                (.post, -7.55, 12.65, model.lightStates.post, .yellow),
                (.piscinaNeon, -7.70, -16.80, model.lightStates.piscinaNeon, .cyan),
                (.sheeritNeon, 6.20, 16.80, model.lightStates.sheeritNeon, .orange),
                (.poolStrips, -1.50, -1.50, model.lightStates.poolStrips, .teal)
            ]

            ForEach(lightPoints, id: \.fixture.rawValue) { pt in
                let lx = radius + CGFloat(pt.x - playerPos.x) * pxPerMeter
                let lz = radius + CGFloat(pt.z - playerPos.z) * pxPerMeter
                let dx = lx - radius
                let dz = lz - radius
                let dist = sqrt(dx * dx + dz * dz)
                let maxRadarR = radius - 8
                let isClamped = dist > maxRadarR
                let finalX = isClamped ? (radius + (dx / dist) * maxRadarR) : lx
                let finalY = isClamped ? (radius + (dz / dist) * maxRadarR) : lz

                ZStack {
                    if pt.isOn {
                        Circle()
                            .fill(pt.color.opacity(0.40))
                            .frame(width: isFullView ? 14 : 10, height: isFullView ? 14 : 10)
                            .blur(radius: 2)
                    }
                    Circle()
                        .fill(pt.isOn ? pt.color : Color.gray.opacity(0.45))
                        .frame(width: isFullView ? 8 : 6, height: isFullView ? 8 : 6)
                        .overlay(Circle().stroke(Color.black, lineWidth: 1))
                    Image(systemName: pt.isOn ? "lightbulb.fill" : "lightbulb")
                        .font(.system(size: isFullView ? 6 : 4.5, weight: .bold))
                        .foregroundStyle(pt.isOn ? .black : .white.opacity(0.8))
                }
                .position(x: finalX, y: finalY)
            }

            // 5. Enemigos / Bots (Puntos Rojos Tácticos con Alerta de Perímetro)
            ForEach(Array(model.npcPositions.enumerated()), id: \.offset) { index, botPos in
                let health = (index < model.npcHealths.count) ? model.npcHealths[index] : 0
                if health > 0 && botPos.y > -5.0 {
                    let dx = CGFloat(botPos.x - playerPos.x) * pxPerMeter
                    let dz = CGFloat(botPos.z - playerPos.z) * pxPerMeter
                    let dist = sqrt(dx * dx + dz * dz)
                    let maxRadarR = radius - 7
                    let isClamped = dist > maxRadarR
                    let finalDx = isClamped ? (dx / dist) * maxRadarR : dx
                    let finalDz = isClamped ? (dz / dist) * maxRadarR : dz

                    Circle()
                        .fill(Color.red)
                        .frame(width: isClamped ? 5 : 7, height: isClamped ? 5 : 7)
                        .shadow(color: .red.opacity(0.9), radius: 3)
                        .position(x: radius + finalDx, y: radius + finalDz)
                }
            }

            // 6. Compañero de Equipo Multijugador (Punto Verde)
            if model.isAnyMultiplayerConnected {
                let dx = CGFloat(model.remotePlayerPosition.x - playerPos.x) * pxPerMeter
                let dz = CGFloat(model.remotePlayerPosition.z - playerPos.z) * pxPerMeter
                let dist = sqrt(dx * dx + dz * dz)
                let maxRadarR = radius - 7
                let isClamped = dist > maxRadarR
                let finalDx = isClamped ? (dx / dist) * maxRadarR : dx
                let finalDz = isClamped ? (dz / dist) * maxRadarR : dz

                Circle()
                    .fill(Color.green)
                    .frame(width: isClamped ? 5 : 7, height: isClamped ? 5 : 7)
                    .shadow(color: .green.opacity(0.9), radius: 3)
                    .position(x: radius + finalDx, y: radius + finalDz)
            }

            // 7. Jugador Local en el Centro con Flecha Direccional de Vista
            ZStack {
                Image(systemName: "location.north.fill")
                    .font(.system(size: isFullView ? 14 : 11, weight: .black))
                    .foregroundStyle(.cyan)
                    .rotationEffect(Angle(radians: Double(atan2(sin(playerYaw), -cos(playerYaw)))))
                    .shadow(color: .cyan.opacity(0.9), radius: 4)

                Circle()
                    .fill(Color.white)
                    .frame(width: 3.5, height: 3.5)
            }
            .position(x: radius, y: radius)

            // 8. Letras Cardinales (N, S, O, E)
            VStack {
                Text("N")
                    .font(.system(size: 6.5, weight: .black))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text("S")
                    .font(.system(size: 6.5, weight: .black))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.vertical, 2)

            HStack {
                Text("O")
                    .font(.system(size: 6.5, weight: .black))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text("E")
                    .font(.system(size: 6.5, weight: .black))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 2)

            // 9. Borde Exterior Estilo Apple Liquid Glass
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [.cyan.opacity(0.85), .white.opacity(0.4), .cyan.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                isFullView.toggle()
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

struct TacticalRemoteControllerView: View {
    @ObservedObject var model: GameModel
    @State private var feedback = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("CONTROL REMOTO TÁCTICO P2")
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                        }
                        Text("Conectado a la Arena 3D")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                            Text("\(Int(model.playerHealth)) HP")
                                .font(.headline.monospacedDigit().bold())
                                .foregroundStyle(.white)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                            Text("Puntos: \(model.playerScore)")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Spacer()

                HStack(alignment: .bottom, spacing: 30) {
                    VStack(spacing: 12) {
                        Text("MOVIMIENTO 360°")
                            .font(.caption2.bold())
                            .foregroundStyle(.white.opacity(0.6))
                        JoystickView { vector in
                            model.joystick = vector
                            sendInput(joystick: vector)
                        }
                        .frame(width: 175, height: 175)
                    }

                    Spacer()

                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            Button {
                                feedback.impactOccurred()
                                model.heldTool = (model.heldTool == .mirror ? .none : .mirror)
                                sendInput(tool: model.heldTool.rawValue)
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "shield.fill")
                                        .font(.system(size: 26, weight: .bold))
                                    Text("ESPEJO")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .foregroundStyle(model.heldTool == .mirror ? .white : .cyan)
                                .frame(width: 78, height: 78)
                                .background(
                                    model.heldTool == .mirror
                                        ? AnyShapeStyle(Color.cyan)
                                        : AnyShapeStyle(Color.cyan.opacity(0.20)),
                                    in: Circle()
                                )
                                .overlay {
                                    Circle()
                                        .stroke(Color.cyan, lineWidth: 2.5)
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                feedback.impactOccurred()
                                model.heldTool = (model.heldTool == .laser ? .none : .laser)
                                sendInput(tool: model.heldTool.rawValue)
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 26, weight: .bold))
                                    Text("LÁSER")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .foregroundStyle(model.heldTool == .laser ? .white : .red)
                                .frame(width: 78, height: 78)
                                .background(
                                    model.heldTool == .laser
                                        ? AnyShapeStyle(Color.red)
                                        : AnyShapeStyle(Color.red.opacity(0.20)),
                                    in: Circle()
                                )
                                .overlay {
                                    Circle()
                                        .stroke(Color.red, lineWidth: 2.5)
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            feedback.impactOccurred()
                            model.requestJump()
                            sendInput(jump: true)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 20, weight: .bold))
                                Text("SALTAR")
                                    .font(.headline.bold())
                            }
                            .foregroundStyle(.white)
                            .frame(width: 172, height: 48)
                            .background(Color.green.opacity(0.85), in: RoundedRectangle(cornerRadius: 24))
                            .overlay {
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }

    private func sendInput(joystick: CGVector? = nil, jump: Bool? = nil, tool: Int? = nil) {
        let packet = LocalMatchPacket(
            kind: .controllerInput,
            peerID: "",
            timestamp: Date().timeIntervalSince1970,
            joystickX: Float(joystick?.dx ?? model.joystick.dx),
            joystickY: Float(joystick?.dy ?? model.joystick.dy),
            jumpPressed: jump,
            role: LocalDeviceRole.remoteController.rawValue
        )
        model.multiplayer.send(packet)
    }
}

struct DuoTacticalControllerDeckView: View {
    @ObservedObject var model: GameModel
    @State private var feedback = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.05, blue: 0.09).ignoresSafeArea()

            VStack(spacing: 10) {
                // Barra superior de telemetría y acciones rápidas
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: "rectangle.split.2x1.fill")
                                .foregroundStyle(.cyan)
                                .font(.caption.bold())
                            Text("MANDO TÁCTICO DUO")
                                .font(.system(size: 11, weight: .black, design: .rounded))
                                .foregroundStyle(.cyan)
                        }
                        HStack(spacing: 8) {
                            Text("❤️ \(Int(model.playerHealth))")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundStyle(.green)
                            Text("🛡️ \(Int(model.playerShield))")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundStyle(.cyan)
                            Text("⭐ \(model.playerScore)")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundStyle(.yellow)
                        }
                    }

                    Spacer()

                    Button {
                        model.duoScreenMode = .squadCamera
                    } label: {
                        Label("Cámara Escuadra", systemImage: "video.badge.Viewfinder")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.purple.opacity(0.28), in: Capsule())
                            .overlay(Capsule().stroke(Color.purple, lineWidth: 1))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.showsSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.duoScreenMode = .off
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.yellow)
                            .frame(width: 32, height: 32)
                            .background(Color.yellow.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)

                // Habilidades Rápidas (Slow-Mo, Luz Cercana, Cobertura)
                HStack(spacing: 8) {
                    Button {
                        feedback.impactOccurred()
                        model.toggleSlowMotion()
                    } label: {
                        Label(
                            model.isSlowMotionUnlocked ? "Slow-Mo" : "🔒 Chrono",
                            systemImage: model.isSlowMotionUnlocked ? "hourglass" : "lock.fill"
                        )
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(model.isSlowMotionActive ? .black : (model.isSlowMotionUnlocked ? .yellow : .cyan))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(model.isSlowMotionActive ? Color.yellow : Color.white.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    if let near = model.nearbyLight {
                        Button {
                            feedback.impactOccurred()
                            model.toggleNearbyLight()
                        } label: {
                            Label(near.label, systemImage: "lightbulb.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.yellow, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    if model.isNearCoverRock || model.isCoverActive {
                        Button {
                            feedback.impactOccurred()
                            model.toggleCover()
                        } label: {
                            Label(model.isCoverActive ? "Salir" : "Cubrirse", systemImage: "shield.lefthalf.filled")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(model.isCoverActive ? .black : .green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(model.isCoverActive ? Color.green : Color.white.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 4)

                // Controles Principales: Joystick 360° + Armas y Salto
                HStack(alignment: .center, spacing: 16) {
                    JoystickView(onChanged: { vec in
                        model.joystick = vec
                    }, isLiquidGlass: true)
                    .frame(width: 145, height: 145)

                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            Button {
                                feedback.impactOccurred()
                                model.heldTool = (model.heldTool == .flashlight ? .none : .flashlight)
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: "flashlight.on.fill")
                                        .font(.system(size: 18, weight: .bold))
                                    Text("\(Int(model.flashlightBattery * 100))%")
                                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                }
                                .foregroundStyle(model.heldTool == .flashlight ? .black : .yellow)
                                .frame(width: 54, height: 54)
                                .background(model.heldTool == .flashlight ? Color.yellow : Color.yellow.opacity(0.18), in: Circle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                feedback.impactOccurred()
                                model.heldTool = (model.heldTool == .laser ? .none : .laser)
                            } label: {
                                VStack(spacing: 2) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 18, weight: .bold))
                                    Text("LÁSER")
                                        .font(.system(size: 9, weight: .heavy))
                                }
                                .foregroundStyle(.white)
                                .frame(width: 54, height: 54)
                                .background(model.heldTool == .laser ? Color.red : Color.red.opacity(0.22), in: Circle())
                            }
                            .buttonStyle(.plain)

                            MirrorShieldJoystickButton(model: model)
                        }

                        Button {
                            feedback.impactOccurred()
                            model.requestJump()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 18, weight: .black))
                                Text("SALTAR / PARKOUR")
                                    .font(.system(size: 12, weight: .black, design: .rounded))
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white, in: Capsule())
                            .overlay(Capsule().stroke(Color.yellow, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
    }
}



struct PauseMenuView: View {
    @ObservedObject var model: GameModel

    var body: some View {
        ZStack {
            // Ultra-subtle liquid glass tint (crystal clear background so 3D scene stays visible!)
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                //  iOS 18 Liquid Glass Title Header (Cyan & Pink)
                HStack(spacing: 10) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(colors: [Color.cyan, Color.pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )

                    Text("PAUSA")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(
                            LinearGradient(colors: [Color.cyan, Color.pink], startPoint: .leading, endPoint: .trailing)
                        )
                        .shadow(color: Color.pink.opacity(0.7), radius: 12)
                }

                if model.isAnyMultiplayerConnected {
                    HStack(spacing: 8) {
                        Circle().fill(Color.cyan).frame(width: 8, height: 8)
                        Text("ENLAZADO: \(model.activePeerDisplayName.uppercased())")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(Color.cyan)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .overlay(Capsule().stroke(Color.cyan.opacity(0.5), lineWidth: 1.0))
                }

                VStack(spacing: 14) {
                    // Continuar - Primary Liquid Glass Focus Button (Gradient Cyan -> Pink)
                    Button {
                        model.gameState = .playing
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("CONTINUAR")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .tracking(1.5)
                        }
                        .foregroundStyle(.white)
                        .frame(width: 250, height: 50)
                        .background(
                            ZStack {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(red: 0.12, green: 0.86, blue: 1.0), Color(red: 1.0, green: 0.28, blue: 0.65)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                Capsule()
                                    .stroke(Color.white.opacity(0.90), lineWidth: 1.5)
                            }
                        )
                        .shadow(color: Color(red: 1.0, green: 0.28, blue: 0.65).opacity(0.55), radius: 12)
                    }
                    .buttonStyle(.plain)

                    // Reiniciar Partida - Crystalline Liquid Glass Pill Button
                    Button {
                        model.startGame()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 16, weight: .bold))
                            Text("REINICIAR PARTIDA")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .tracking(1.5)
                        }
                        .foregroundStyle(.white)
                        .frame(width: 250, height: 50)
                        .background(
                            ZStack {
                                Capsule()
                                    .fill(Color.white.opacity(0.18))
                                    .background(Color.black.opacity(0.35), in: Capsule())

                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.cyan.opacity(0.85), Color.pink.opacity(0.85)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.2
                                    )
                            }
                        )
                        .shadow(color: Color.cyan.opacity(0.20), radius: 8)
                    }
                    .buttonStyle(.plain)

                    // Menú Principal - Neon Pink Liquid Glass Pill Button
                    Button {
                        model.returnToMainMenu()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "house.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("MENÚ PRINCIPAL")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .tracking(1.5)
                        }
                        .foregroundStyle(Color.pink)
                        .frame(width: 250, height: 50)
                        .background(
                            ZStack {
                                Capsule()
                                    .fill(Color.pink.opacity(0.16))
                                    .background(Color.black.opacity(0.35), in: Capsule())

                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.pink.opacity(0.85), Color.cyan.opacity(0.60)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.2
                                    )
                            }
                        )
                        .shadow(color: Color.pink.opacity(0.30), radius: 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 30)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color.white.opacity(0.16))
                        .background(Color.black.opacity(0.40), in: RoundedRectangle(cornerRadius: 28))

                    RoundedRectangle(cornerRadius: 28)
                        .stroke(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.90), Color.pink.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
            )
            .shadow(color: Color.black.opacity(0.40), radius: 20, x: 0, y: 8)
            .shadow(color: Color.pink.opacity(0.25), radius: 12, x: 0, y: 0)
        }
    }
}

struct MultiplayerSettingsSheet: View {
    @ObservedObject var model: GameModel
    @ObservedObject var multiplayer: LocalMultiplayerSession
    @Environment(\.dismiss) private var dismiss

    init(model: GameModel) {
        self.model = model
        self.multiplayer = model.multiplayer
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tu Dispositivo") {
                    HStack {
                        Label(multiplayer.localPeer.displayName, systemImage: "iphone.radiowaves.left.and.right")
                            .font(.subheadline.bold())
                            .foregroundStyle(.cyan)
                        Spacer()
                        Text(multiplayer.isConnected ? "ENLAZADO" : "LISTO")
                            .font(.caption2.bold())
                            .foregroundStyle(multiplayer.isConnected ? .green : .secondary)
                    }
                }

                Section("Modo de Juego y Tamaño de Sala") {
                    Picker("Modo", selection: $multiplayer.mode) {
                        ForEach(LocalMatchMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Capacidad Máxima (Equipo)", selection: $multiplayer.teamSize) {
                        ForEach(MatchTeamSize.allCases) { size in
                            Text(size.label).tag(size)
                        }
                    }

                    Text("💡 No es obligatorio llenar el grupo: si eliges 4 vs 4 (hasta 8) y solo hay 3 o 5 amigos conectados, puedes iniciar la partida en cualquier momento.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if model.isDuoDevice {
                    Section("📱📱 Modo Doble Pantalla (iPhone Duo)") {
                        Picker("Pantalla iPhone Duo", selection: Binding(
                            get: { model.duoScreenMode },
                            set: { model.duoScreenMode = $0 }
                        )) {
                            ForEach(DuoScreenMode.allCases) { dMode in
                                Text(dMode.label).tag(dMode)
                            }
                        }
                    }
                }

                Section("Rol de este Dispositivo") {
                    Picker("Rol", selection: $multiplayer.role) {
                        ForEach(LocalDeviceRole.allCases) { role in
                            Text(role.label).tag(role)
                        }
                    }
                }

                Section("Conexión Local Wi-Fi / Bluetooth") {
                    // Estado en vivo
                    HStack(spacing: 10) {
                        Image(systemName: multiplayer.isConnected ? "checkmark.seal.fill" : (multiplayer.isHosting || multiplayer.isSearching ? "dot.radiowaves.left.and.right" : "wifi"))
                            .foregroundStyle(multiplayer.isConnected ? .green : .cyan)
                        Text(multiplayer.statusMessage)
                            .font(.caption.bold())
                            .foregroundStyle(multiplayer.isConnected ? .green : .primary)
                    }

                    Button {
                        multiplayer.host()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        HStack {
                            Label("1. Crear sala (Host 3D)", systemImage: "antenna.radiowaves.left.and.right")
                                .font(.subheadline.bold())
                            Spacer()
                            if multiplayer.isHosting && !multiplayer.isConnected {
                                ProgressView()
                            } else if multiplayer.isHosting {
                                Text("Activa")
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                            }
                        }
                    }

                    Button {
                        multiplayer.join()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } label: {
                        HStack {
                            Label("2. Unirse a sala cercana", systemImage: "person.2.wave.2.fill")
                                .font(.subheadline.bold())
                            Spacer()
                            if multiplayer.isSearching && !multiplayer.isConnected {
                                ProgressView()
                            }
                        }
                    }

                    if !multiplayer.discoveredPeers.isEmpty && !multiplayer.isConnected {
                        ForEach(multiplayer.discoveredPeers, id: \.displayName) { peer in
                            Button {
                                multiplayer.invitePeer(peer)
                            } label: {
                                HStack {
                                    Image(systemName: "iphone")
                                        .foregroundStyle(.green)
                                    Text("Conectar con \(peer.displayName)")
                                        .font(.caption.bold())
                                    Spacer()
                                    Text("Enlazar")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.2), in: Capsule())
                                }
                            }
                        }
                    }

                    if multiplayer.isConnected {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Sala activa: \(multiplayer.peers.count + 1)/\(multiplayer.teamSize.maxPlayers) jugadores conectados")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.green)
                            }
                            ForEach(multiplayer.peers, id: \.displayName) { peer in
                                Label(peer.displayName, systemImage: "iphone.gen3")
                                    .font(.caption.bold())
                            }

                            Button {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    model.startGame(fromNetwork: false)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("INICIAR PARTIDA AHORA (\(multiplayer.peers.count + 1) JUGADORES)")
                                        .font(.subheadline.bold())
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.green, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.black)
                            }
                            .buttonStyle(.plain)

                            Button("Desconectar sala", role: .destructive) {
                                multiplayer.stop()
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }

                    if let error = multiplayer.lastError {
                        Text("Aviso: \(error)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("🌐 Partida por Internet (Apple Game Center)") {
                    HStack {
                        Image(systemName: model.gameCenter.isAuthenticated ? "checkmark.seal.fill" : "person.crop.circle.badge.exclamationmark")
                            .foregroundStyle(model.gameCenter.isAuthenticated ? .green : .orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.gameCenter.isAuthenticated ? "Game Center Autenticado" : "Game Center Desconectado")
                                .font(.subheadline.bold())
                            Text(model.gameCenter.localPlayerAlias)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !model.gameCenter.isAuthenticated {
                        Button {
                            model.gameCenter.authenticateLocalPlayer()
                        } label: {
                            Label("Iniciar sesión en Game Center", systemImage: "person.crop.circle.badge.plus")
                        }
                    } else {
                        Button {
                            model.gameCenter.presentMatchmaker(maxPlayers: multiplayer.teamSize.maxPlayers)
                        } label: {
                            HStack {
                                Label("Invitar Amigos / Matchmaking (\(multiplayer.teamSize.shortLabel))", systemImage: "gamecontroller.fill")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if model.gameCenter.isInMatch {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "globe.americas.fill")
                                    .foregroundStyle(.green)
                                Text("Sala Game Center: \(model.gameCenter.connectedPlayerNames.count + 1)/\(multiplayer.teamSize.maxPlayers) jugadores (listo para iniciar)")
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                            }
                            ForEach(model.gameCenter.connectedPlayerNames, id: \.self) { peer in
                                Label(peer, systemImage: "person.fill")
                                    .font(.caption.bold())
                            }
                            Button {
                                model.gameCenter.startMatchNowWithConnectedPlayers()
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    model.startGame(fromNetwork: false)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("INICIAR CON LOS \(model.gameCenter.connectedPlayerNames.count + 1) CONECTADOS AHORA")
                                        .font(.subheadline.bold())
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.green, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.black)
                            }
                            .buttonStyle(.plain)

                            Button("Abandonar partida de Game Center", role: .destructive) {
                                model.gameCenter.leaveMatch()
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }

                    if let error = model.gameCenter.lastError {
                        Text("Error de Game Center: \(error)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Multijugador (Local & Internet)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct GameSlang {
    let languageCode: String

    // 💀 Pantalla de Derrota (Slangs de Infancia / Gamer)
    var defeatTitle: String {
        switch languageCode {
        case "en": return "YOU DED 💀"
        case "pt": return "FOI DE BASE 💀"
        case "fr": return "T'ES MORT D'UN COUP :v"
        case "ja": return "オワタ＼(^o^)／"
        case "de": return "LOST GEGANGEN 💀"
        case "hi": return "KHATAM TATA BYE BYE 💀"
        case "it": return "SEI MORTO MALISSIMO 💀"
        case "zh": return "芭比Q了 💀"
        case "ko": return "망했다 💀"
        default:   return "MORIDO :v"
        }
    }

    var defeatVersusTitle: String {
        switch languageCode {
        case "en": return "WASTED IN COMBAT"
        case "pt": return "DEITOU NA BRÈXA :v"
        case "fr": return "MIS AU TAPIS!"
        case "ja": return "しぼう :v"
        case "de": return "WEGGEKLATSCHT!"
        case "hi": return "DHOBI PACHAD HO GAYA!"
        case "it": return "TI HANNO ARRIFATTO :v"
        case "zh": return "直接被干碎了!"
        case "ko": return "컷! 당해버렸쥬?"
        default:   return "CAÍSTE EN COMBATE"
        }
    }

    var defeatTeamTitle: String {
        switch languageCode {
        case "en": return "SQUAD WIPED OUT"
        case "pt": return "BONDE DERRUBADO"
        case "fr": return "MISSION ÉCHOUÉE"
        case "ja": return "ぜんめつ..."
        case "de": return "TEAM GEWIPED"
        case "hi": return "SQUAD KHATAM BHAI!"
        case "it": return "SQUADRA DISTRUTTA!"
        case "zh": return "团灭了兄弟们..."
        case "ko": return "올킬 당함..."
        default:   return "MISIÓN FALLIDA"
        }
    }

    var defeatSubtitleReset: String {
        switch languageCode {
        case "en": return "A MIMIR UN RATO • BACK TO WAVE 1"
        case "pt": return "VACILOU, MORREU • ONDA 1 DE NOVO"
        case "fr": return "RETOUR À LA CASE DÉPART • VAGUE 1"
        case "ja": return "ゲームオーバー • ウェーブ1へもどる"
        case "de": return "DIGGA WAS WAR DAS • WELLE 1"
        case "hi": return "KHEL KHATAM BHAI • WAPAS WAVE 1 PE"
        case "it": return "VACCI PIANO • SI RIPARTE DA ONDATA 1"
        case "zh": return "重开一把 • 从第一波重新开始"
        case "ko": return "멘탈 잡고 1웨이브부터 다시"
        default:   return "OLEADA RESTABLECIDA A OLEADA 1"
        }
    }

    var retryButton: String {
        switch languageCode {
        case "en": return "RESPAWN ME PLZ (RETRY)"
        case "pt": return "RESSUSCITA AÍ (TENTAR DE NOVO)"
        case "fr": return "REZ-MOI STP (RÉESSAYER)"
        case "ja": return "もういっかい！ (RETRY)"
        case "de": return "NOCHMAL REINDA! (RETRY)"
        case "hi": return "FIR SE KHELENGE! (RESPAWN)"
        case "it": return "SPAWNAMI PLS! (RIGIOCA)"
        case "zh": return "再来一把! (RETRY)"
        case "ko": return "한 판 더! (RETRY)"
        default:   return "DAME VIDA (REINTENTAR)"
        }
    }

    var nextRoundButton: String {
        switch languageCode {
        case "en": return "RUN IT BACK (NEXT ROUND)"
        case "pt": return "PRÓXIMO ROUND"
        case "fr": return "MANCHE SUIVANTE"
        case "ja": return "つぎのラウンド"
        case "de": return "NÄCHSTE RUNDE"
        case "hi": return "AGLA ROUND CHALO!"
        case "it": return "PROSSIMO ROUND"
        case "zh": return "下一轮冲冲冲!"
        case "ko": return "다음 라운드 가자!"
        default:   return "SIGUIENTE RONDA"
        }
    }

    // 🎬 Lore y Prólogo
    var loreButtonTitle: String {
        switch languageCode {
        case "en": return "THE LORE THO: SECRET OF LUMINA"
        case "pt": return "HISTÓRIA DAS ANTIGAS: O SEGREDO DE LUMINA"
        case "fr": return "L'HISTOIRE DU DARON: LE SECRET DE LUMINA"
        case "ja": return "むかしばなし: ルミナのひみつ"
        case "de": return "DEEP LORE: DAS GEHEIMNIS VON LUMINA"
        case "hi": return "ASLI KAHANI: SECRET OF LUMINA"
        case "it": return "IL LORE SEGRETO: DI LUMINA"
        case "zh": return "故事背景大揭秘: 卢米娜的秘密"
        case "ko": return "비하인드 스토리: 루미나의 비밀"
        default:   return "LORE & CUENTO: EL SECRETO DE LUMINA"
        }
    }

    // 👑 Victoria
    var victoryTitle: String {
        switch languageCode {
        case "en": return "POGGERS! EZ CLAP! 👑"
        case "pt": return "MITOU DEMAIS! 👑"
        case "fr": return "MASTERCLASS! 👑"
        case "ja": return "カチカク！やったー！ 👑"
        case "de": return "ABSOLUTER EHRENMANN! 👑"
        case "hi": return "BOOYAH! OP BHAI OP! 👑"
        case "it": return "LEGGENDA ASSOLUTA! GG! 👑"
        case "zh": return "秀麻了! 绝杀! 👑"
        case "ko": return "개이득! 레전드 찍었다! 👑"
        default:   return "¡CORONAMOS! 👑"
        }
    }

    // ⚡ Menú principal y botones
    var playButton: String {
        switch languageCode {
        case "en": return "LET'S COOK! (PLAY)"
        case "pt": return "BORA JOGAR! (PLAY)"
        case "fr": return "C'EST PARTI! (JOUER)"
        case "ja": return "あそぶ！(PLAY)"
        case "de": return "LOS GEHT'S! (SPIELEN)"
        case "hi": return "CHALO SHURU KAREIN! (PLAY)"
        case "it": return "ANDIAMO A VINCERE! (GIOCA)"
        case "zh": return "开整! (PLAY)"
        case "ko": return "드가자! (PLAY)"
        default:   return "¡A DARLE! (JUGAR)"
        }
    }

    var optionsButton: String {
        switch languageCode {
        case "en": return "OPTIONS & SETTINGS"
        case "pt": return "OPÇÕES E AJUSTES"
        case "fr": return "OPTIONS ET PARAMÈTRES"
        case "ja": return "せってい (SETTINGS)"
        case "de": return "EINSTELLUNGEN"
        case "hi": return "SETTINGS & OPTIONS"
        case "it": return "OPZIONI E IMPOSTAZIONI"
        case "zh": return "系统设置 (SETTINGS)"
        case "ko": return "환경설정 (SETTINGS)"
        default:   return "OPCIONES Y AJUSTES"
        }
    }

    var multiplayerButton: String {
        switch languageCode {
        case "en": return "ONLINE / LOCAL MULTIPLAYER"
        case "pt": return "MULTIJOGADOR ONLINE / LOCAL"
        case "fr": return "MULTIJOUEUR EN LIGNE / LOCAL"
        case "ja": return "マルチプレイ (ONLINE / LOCAL)"
        case "de": return "MEHRSPIELER ONLINE / LOKAL"
        case "hi": return "DOST KE SAATH (MULTIPLAYER)"
        case "it": return "MULTIGIOCA ONLINE / LOCALE"
        case "zh": return "联机对战 (MULTIPLAYER)"
        case "ko": return "멀티플레이 (MULTIPLAYER)"
        default:   return "MULTIJUGADOR ONLINE / LOCAL"
        }
    }

    var speed2XTitle: String {
        switch languageCode {
        case "en": return "⚡ 2X ZOOMIN'"
        case "pt": return "⚡ 2X TURBINADO"
        case "fr": return "⚡ 2X VITESSE ÉCLAIR"
        case "ja": return "⚡ 2X ばくそく"
        case "de": return "⚡ 2X TURBO SPEED"
        case "hi": return "⚡ 2X FULL SPEED JALDI"
        case "it": return "⚡ 2X CORSA PAZZA"
        case "zh": return "⚡ 2X 起飞倍速"
        case "ko": return "⚡ 2X 초고속 모드"
        default:   return "⚡ 2X CINE VOLAO"
        }
    }
}

enum GameOptionsTab: String, CaseIterable, Identifiable {
    case controls = "Controles"
    case graphics = "Gráficos"
    case audio = "Sonido"
    case language = "Idioma / Slang"
    case achievements = "Logros"
    case system = "Sistema"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .controls: "gamecontroller.fill"
        case .graphics: "display"
        case .audio: "speaker.wave.2.fill"
        case .language: "globe.americas.fill"
        case .achievements: "trophy.fill"
        case .system: "info.circle.fill"
        }
    }
}

struct GameOptionsSheet: View {
    @ObservedObject var model: GameModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: GameOptionsTab = .controls

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                //  Barra de Pestañas Horizontales ("Pestañas de para el lado")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(GameOptionsTab.allCases) { tab in
                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    selectedTab = tab
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 12, weight: .bold))
                                    Text(tab.rawValue)
                                        .font(.system(size: 13, weight: .bold))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .foregroundStyle(selectedTab == tab ? .white : .secondary)
                                .background(
                                    selectedTab == tab
                                        ? AnyShapeStyle(LinearGradient(colors: [Color.cyan.opacity(0.85), Color.pink.opacity(0.85)], startPoint: .leading, endPoint: .trailing))
                                        : AnyShapeStyle(Color.white.opacity(0.08)),
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            selectedTab == tab
                                                ? LinearGradient(colors: [Color.cyan, Color.pink], startPoint: .leading, endPoint: .trailing)
                                                : LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)], startPoint: .leading, endPoint: .trailing),
                                            lineWidth: 1.2
                                        )
                                )
                                .shadow(color: selectedTab == tab ? Color.pink.opacity(0.40) : .clear, radius: 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .background(.ultraThinMaterial)
                .overlay(Divider(), alignment: .bottom)

                Form {
                    switch selectedTab {
                    case .controls:
                        Section("🎮 Mando Inalámbrico") {
                            HStack {
                                Label(
                                    model.isGameControllerConnected ? "Mando Conectado" : "Mando Inalámbrico",
                                    systemImage: model.isGameControllerConnected ? "gamecontroller.fill" : "gamecontroller"
                                )
                                .foregroundStyle(model.isGameControllerConnected ? Color.cyan : Color.secondary)

                                Spacer()

                                Text(model.isGameControllerConnected ? model.gameControllerName : "Ninguno detectado")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            if model.isGameControllerConnected {
                                DisclosureGroup("Mapeo de Botones (Xbox / PS / Switch)") {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("• **Stick Izquierdo**: Movimiento de personaje").font(.caption)
                                        Text("• **Stick Derecho**: Cámara / Apuntar").font(.caption)
                                        Text("• **Botón A / ✕**: Saltar").font(.caption)
                                        Text("• **Botón B / ◯ / RT / R2**: Disparar Láser").font(.caption)
                                        Text("• **Botón Y / △ / LT / L2**: Linterna (Prender/Apagar)").font(.caption)
                                        Text("• **Botón X / ▢ / LB / L1**: Escudo Espejo").font(.caption)
                                        Text("• **D-Pad Arriba**: Conmutar Luz de arena").font(.caption)
                                        Text("• **R3 (Pulsar Stick Der.)**: Cámara Lenta").font(.caption)
                                    }
                                    .padding(.vertical, 4)
                                }
                            } else {
                                Text("Compatible con mandos inalámbricos Bluetooth de Xbox, PlayStation o Nintendo Switch.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Section("📱 Controles Táctiles y Cámara") {
                            Button {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    if model.gameState != .playing {
                                        model.gameState = .playing
                                    }
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        model.isEditingHUDLayout = true
                                    }
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "slider.horizontal.below.square.and.square.filled")
                                        .font(.title3)
                                        .foregroundStyle(.cyan)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Personalizar Posición y Tamaño de Botones HUD")
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)
                                        Text("Mueve el joystick, armas, salto y habilidades táctiles")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Sensibilidad de Cámara")
                                    Spacer()
                                    Text(String(format: "%.1fx", model.cameraSensitivity))
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: $model.cameraSensitivity, in: 0.4...2.0, step: 0.1)
                                    .tint(.cyan)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Opacidad General de Botones")
                                    Spacer()
                                    Text("\(Int(model.touchControlsOpacity * 100))%")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: Binding<Double>(
                                    get: { model.touchControlsOpacity },
                                    set: { newVal in
                                        model.touchControlsOpacity = newVal
                                        model.hudJoystickOpacity = newVal
                                        model.hudFlashlightOpacity = newVal
                                        model.hudLaserOpacity = newVal
                                        model.hudShieldOpacity = newVal
                                        model.hudJumpOpacity = newVal
                                        model.hudActionOpacity = newVal
                                        model.hudSlowMoOpacity = newVal
                                        model.hudWarpOpacity = newVal
                                        model.hudWeaponsOpacity = newVal
                                        model.hudSkillsOpacity = newVal
                                    }
                                ), in: 0.2...1.0, step: 0.05)
                                .tint(.pink)
                            }

                            Toggle("Invertir eje Y (Cámara)", isOn: $model.invertsCameraY)

                            HStack {
                                Label("Perspectiva de Cámara", systemImage: "eye.fill")
                                Spacer()
                                Text("1ª Persona FPS")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.cyan)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.cyan.opacity(0.18)))
                            }
                            Text("Modo FPS activo con armas y manos 3D. La 3ª persona queda preservada en el motor para el futuro.")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))

                            if model.isDuoDevice {
                                Picker("Modo Doble Pantalla (iPhone Duo)", selection: Binding(
                                    get: { model.duoScreenMode },
                                    set: { model.duoScreenMode = $0 }
                                )) {
                                    ForEach(DuoScreenMode.allCases) { dMode in
                                        Text(dMode.label).tag(dMode)
                                    }
                                }

                                if model.duoScreenMode == .squadCamera {
                                    Button {
                                        model.cycleSquadCameraMember()
                                    } label: {
                                        HStack {
                                            Label("Compañero en 2ª Pantalla", systemImage: "person.2.crop.square.stack.fill")
                                            Spacer()
                                            Text(model.selectedSquadCameraAgent.peerID)
                                                .font(.caption.bold())
                                                .foregroundStyle(.cyan)
                                        }
                                    }
                                }
                            }
                        }

                    case .graphics:
                        Section("⚡ Perfiles Rápidos de Rendimiento") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Elige según nivel de batería o fidelidad visual")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 6) {
                                    Button {
                                        model.targetFPS = 30
                                        model.renderResolution = .light
                                        model.advancedReflectionsEnabled = true
                                        model.isLiquidGlassUIEnabled = true
                                    } label: {
                                        VStack(spacing: 3) {
                                            Image(systemName: "snowflake")
                                            Text("Batería Fría")
                                                .font(.caption2.bold())
                                            Text("30 FPS • Frío")
                                                .font(.system(size: 8, weight: .semibold))
                                                .opacity(0.85)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.teal.opacity(0.85))

                                    Button {
                                        model.targetFPS = 60
                                        model.renderResolution = .balanced
                                        model.advancedReflectionsEnabled = true
                                        model.isLiquidGlassUIEnabled = true
                                    } label: {
                                        VStack(spacing: 3) {
                                            Image(systemName: "dial.medium.fill")
                                            Text("Equilibrado")
                                                .font(.caption2.bold())
                                            Text("60 FPS • 1.0x")
                                                .font(.system(size: 8, weight: .semibold))
                                                .opacity(0.85)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.blue.opacity(0.8))

                                    Button {
                                        model.targetFPS = 60
                                        model.renderResolution = .high
                                        model.advancedReflectionsEnabled = true
                                        model.isLiquidGlassUIEnabled = true
                                    } label: {
                                        VStack(spacing: 3) {
                                            Image(systemName: "sparkles")
                                            Text("Retina Pro")
                                                .font(.caption2.bold())
                                            Text("60 FPS • 1.5x")
                                                .font(.system(size: 8, weight: .semibold))
                                                .opacity(0.85)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.purple.opacity(0.85))

                                    Button {
                                        model.targetFPS = 60
                                        model.renderResolution = .ultra4K
                                        model.advancedReflectionsEnabled = true
                                        model.isLiquidGlassUIEnabled = true
                                    } label: {
                                        VStack(spacing: 3) {
                                            Image(systemName: "tv.fill")
                                            Text("Ultra Cool")
                                                .font(.caption2.bold())
                                            Text("4K TV • 2.2x")
                                                .font(.system(size: 8, weight: .semibold))
                                                .opacity(0.85)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.orange.opacity(0.9))
                                }

                                Text("✨ Los reflejos Ray Tracing y el tema Vidrio Líquido se mantienen activos en todos los perfiles.")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                            .padding(.vertical, 4)
                        }

                        Section("🖥️ Calidad Visual y Tasa de Cuadros") {
                            Picker("Límite de Fotogramas (FPS)", selection: $model.targetFPS) {
                                Text("30 FPS (Ahorra Batería y Calor)").tag(30)
                                Text("60 FPS (Fluidez Máxima)").tag(60)
                            }

                            Picker("Resolución interna 3D", selection: $model.renderResolution) {
                                ForEach(GameRenderResolution.allCases) { resolution in
                                    Text(resolution.label).tag(resolution)
                                }
                            }

                            Toggle("Reflejos Ray Tracing (Agua, Piso y Espejos)", isOn: $model.advancedReflectionsEnabled)
                            Toggle("Tema Vidrio Líquido (Apple Liquid Glass)", isOn: $model.isLiquidGlassUIEnabled)
                            Toggle("Mostrar Radar Minimapa Táctico", isOn: $model.showsMinimap)
                            Toggle("Mostrar contador de FPS", isOn: $model.showsFPS)
                        }

                    case .audio:
                        Section("🎵 Música y Efectos de Sonido") {
                            Toggle("Música de fondo", isOn: $model.musicEnabled)
                            Toggle("Efectos de sonido y pasos", isOn: $model.footstepsEnabled)
                            Toggle("Sonido de agua", isOn: $model.waterSoundEnabled)
                        }

                    case .language:
                        Section("🌐 Detección Automática de Idioma") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Por defecto, el juego detecta de manera 100% automática el idioma de tu iPhone y de la App Store en cualquier país del mundo.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Text("Idioma actual de iOS:")
                                        .font(.caption.bold())
                                    Spacer()
                                    Text("\(Locale.current.identifier) • \(model.effectiveLanguageCode.uppercased())")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.cyan)
                                }
                            }

                            Picker("Seleccionar Idioma / Cultura", selection: $model.selectedLanguagePreference) {
                                Text("🌐 Automático (Detectar de iOS)").tag("auto")
                                Text("🇲🇽/🇪🇸 Español (Morido :v / Coronamos)").tag("es")
                                Text("🇺🇸/🇬🇧 English (You Ded 💀 / Poggers)").tag("en")
                                Text("🇧🇷/🇵🇹 Português (Foi de Base 💀 / Mitou)").tag("pt")
                                Text("🇫🇷 Français (T'es Mort :v / Masterclass)").tag("fr")
                                Text("🇩🇪 Deutsch (Lost Gegangen 💀 / Ehrenmann / 🇨🇭)").tag("de")
                                Text("🇮🇹 Italiano (Morto Malissimo 💀 / GG / 🇨🇭)").tag("it")
                                Text("🇮🇳 Hindi / Hinglish (Khatam Tata Bye Bye 💀 / OP Bhai)").tag("hi")
                                Text("🇯🇵 日本語 (オワタ＼(^o^)／ / カチカク)").tag("ja")
                                Text("🇨🇳 中文 (芭比Q了 💀 / 秀麻了)").tag("zh")
                                Text("🇰🇷 한국어 (망했다 💀 / 드가자)").tag("ko")
                            }
                        }

                        Section("🎮 Slangs de Infancia & Cultura Gamer Activa") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("¡Cero traducciones corporativas aburridas! Cada idioma tiene modismos nostálgicos de videojuegos de la infancia y cultura de internet.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HStack {
                                    Text("Al perder:")
                                    Spacer()
                                    Text(model.slang.defeatTitle)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.red)
                                }

                                HStack {
                                    Text("Botón revivir:")
                                    Spacer()
                                    Text(model.slang.retryButton)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.cyan)
                                }

                                HStack {
                                    Text("Victoria:")
                                    Spacer()
                                    Text(model.slang.victoryTitle)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.yellow)
                                }

                                HStack {
                                    Text("Botón de jugar:")
                                    Spacer()
                                    Text(model.slang.playButton)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.green)
                                }

                                HStack {
                                    Text("Modo 2X Cine:")
                                    Spacer()
                                    Text(model.slang.speed2XTitle)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                    case .achievements:
                        Section("🏆 Game Center") {
                            NavigationLink {
                                AchievementsView(model: model)
                            } label: {
                                HStack {
                                    Label("Ver Lista de Logros", systemImage: "trophy.fill")
                                        .foregroundStyle(Color.pink)
                                    Spacer()
                                    let unlocked = model.gameCenter.achievements.filter { $0.isUnlocked }.count
                                    Text("\(unlocked) / \(model.gameCenter.achievements.count)")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(Color.cyan)
                                }
                            }
                        }

                    case .system:
                        Section("🎬 Historia y Lore del Juego") {
                            Button {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    model.showsPrologueScreen = true
                                }
                            } label: {
                                HStack {
                                    Label("Ver Prólogo: El Secreto de Lumina", systemImage: "film.stack.fill")
                                        .font(.subheadline.bold())
                                        .foregroundStyle(Color.yellow)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        Section("ℹ️ Información del Sistema") {
                            HStack {
                                Text("Versión")
                                Spacer()
                                Text(GameAppVersion.formatted)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Text("Motor Gráfico")
                                Spacer()
                                Text("Metal Hardware Ray Tracing")
                                    .font(.caption.bold())
                                    .foregroundStyle(.cyan)
                            }

                            HStack {
                                Text("Dispositivo")
                                Spacer()
                                Text("Apple Silicon GPU (A-Series)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Text("Multijugador")
                                Spacer()
                                Text("Multipeer + Game Center")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Ajustes y Opciones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .foregroundStyle(Color.cyan)
                }
            }
        }
    }
}

struct AchievementsView: View {
    @ObservedObject var model: GameModel
    @Environment(\.dismiss) private var dismiss

    var totalPoints: Int {
        model.gameCenter.achievements.reduce(0) { $0 + $1.points }
    }

    var earnedPoints: Int {
        model.gameCenter.achievements.filter { $0.isUnlocked }.reduce(0) { $0 + $1.points }
    }

    var unlockedCount: Int {
        model.gameCenter.achievements.filter { $0.isUnlocked }.count
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    HStack(spacing: 18) {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.12), lineWidth: 8)
                                .frame(width: 72, height: 72)
                            Circle()
                                .trim(from: 0, to: CGFloat(unlockedCount) / CGFloat(max(1, model.gameCenter.achievements.count)))
                                .stroke(
                                    LinearGradient(colors: [.yellow, .orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .frame(width: 72, height: 72)

                            VStack(spacing: 0) {
                                Text("\(Int((Double(unlockedCount) / Double(max(1, model.gameCenter.achievements.count))) * 100))%")
                                    .font(.system(size: 15, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Progreso de Logros")
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                            Text("\(unlockedCount) de \(model.gameCenter.achievements.count) completados")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(earnedPoints) / \(totalPoints) Puntos de Game Center")
                                .font(.caption.bold())
                                .foregroundStyle(.yellow)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.white.opacity(0.04))
            }

            Section("Desafíos Disponibles") {
                ForEach(model.gameCenter.achievements) { ach in
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(ach.isUnlocked ? AnyShapeStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color.white.opacity(0.08)))
                                .frame(width: 44, height: 44)
                            Image(systemName: ach.icon)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(ach.isUnlocked ? .black : .secondary)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(ach.title)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(ach.isUnlocked ? .white : .secondary)
                                Spacer()
                                Text("+\(ach.points) pts")
                                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                    .foregroundStyle(ach.isUnlocked ? .yellow : .secondary)
                            }

                            Text(ach.description)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(ach.isUnlocked ? .white.opacity(0.85) : .secondary.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)

                            if ach.isUnlocked, let date = ach.unlockedDate {
                                Text("Desbloqueado: \(date.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.cyan.opacity(0.85))
                                    .padding(.top, 1)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(ach.isUnlocked ? Color.yellow.opacity(0.06) : Color.white.opacity(0.02))
                }
            }
        }
        .navigationTitle("Logros")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Listo") {
                    dismiss()
                }
            }
        }
    }
}

struct HUDDraggableModifier: ViewModifier {
    let isEditing: Bool
    let isSelected: Bool
    let label: String
    @Binding var offsetX: Double
    @Binding var offsetY: Double
    let scale: Double
    let onSelect: () -> Void

    @GestureState private var dragTranslation: CGSize = .zero

    func body(content: Content) -> some View {
        let currentX = offsetX + Double(dragTranslation.width)
        let currentY = offsetY + Double(dragTranslation.height)

        content
            .allowsHitTesting(!isEditing)
            .scaleEffect(CGFloat(scale))
            .overlay {
                if isEditing {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isSelected ? Color.cyan.opacity(0.24) : Color.black.opacity(0.28))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(
                                    isSelected ? Color.cyan : Color.white.opacity(0.70),
                                    style: StrokeStyle(lineWidth: isSelected ? 2.5 : 1.5, dash: [5, 4])
                                )
                        )
                        .overlay(alignment: .top) {
                            Text("\(label) • \(Int(scale * 100))%")
                                .font(.system(size: 9, weight: .black, design: .rounded))
                                .foregroundStyle(isSelected ? .black : .white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(isSelected ? Color.cyan : Color.black.opacity(0.85), in: Capsule())
                                .offset(y: -11)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onSelect()
                        }
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .updating($dragTranslation) { value, state, _ in
                                    state = value.translation
                                }
                                .onEnded { value in
                                    onSelect()
                                    offsetX = min(max(offsetX + Double(value.translation.width), -420), 420)
                                    offsetY = min(max(offsetY + Double(value.translation.height), -280), 280)
                                }
                        )
                }
            }
            .offset(x: CGFloat(currentX), y: CGFloat(currentY))
    }
}

struct FlashlightButton: View {
    @ObservedObject var model: GameModel

    var body: some View {
        Button {
            guard model.flashlightBattery > 0.02 else { return }
            model.heldTool = (model.heldTool == .flashlight ? .none : .flashlight)
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: CGFloat(model.flashlightBattery))
                    .stroke(
                        model.flashlightBattery > 0.35 ? Color.yellow : (model.flashlightBattery > 0.15 ? Color.orange : Color.red),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 1) {
                    Image(systemName: model.flashlightBattery <= 0.02 ? "battery.0percent" : "flashlight.on.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text("\(Int((model.flashlightBattery * 100).rounded()))%")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                }
                .foregroundStyle(model.heldTool == .flashlight ? .black : (model.flashlightBattery > 0.20 ? .yellow : .orange))
            }
            .frame(width: 48, height: 48)
            .background(
                model.heldTool == .flashlight
                    ? AnyShapeStyle(model.flashlightBattery > 0.20 ? Color.yellow : Color.orange)
                    : AnyShapeStyle(Color.black.opacity(0.65)),
                in: Circle()
            )
            .overlay(Circle().stroke(Color.yellow.opacity(model.heldTool == .flashlight ? 0.90 : 0.40), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Linterna")
    }
}

struct LaserButton: View {
    @ObservedObject var model: GameModel

    var body: some View {
        Button {
            guard model.laserBattery > 0.02 else { return }
            model.heldTool = (model.heldTool == .laser ? .none : .laser)
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: CGFloat(model.laserBattery))
                    .stroke(
                        model.laserBattery > 0.35 ? Color.cyan : (model.laserBattery > 0.15 ? Color.orange : Color.red),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 1) {
                    Image(systemName: model.laserBattery <= 0.02 ? "bolt.slash.fill" : "bolt.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text("\(Int((model.laserBattery * 100).rounded()))%")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                }
                .foregroundStyle(model.heldTool == .laser ? .white : (model.laserBattery > 0.20 ? .cyan : .red))
            }
            .frame(width: 48, height: 48)
            .background(
                model.heldTool == .laser
                    ? AnyShapeStyle(model.laserBattery > 0.02 ? Color.red : Color.gray.opacity(0.6))
                    : AnyShapeStyle(Color.black.opacity(0.65)),
                in: Circle()
            )
            .overlay(Circle().stroke(Color.cyan.opacity(model.heldTool == .laser ? 0.90 : 0.40), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Láser")
    }
}

struct JumpButton: View {
    @ObservedObject var model: GameModel

    var body: some View {
        Button {
            guard !model.isDefeated, model.gameState == .playing else { return }
            model.requestJump()
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(.black)
                .frame(width: 50, height: 50)
                .background(.white.opacity(0.95), in: Circle())
                .overlay(Circle().stroke(Color.yellow, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.35), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel("Saltar")
        .accessibilityIdentifier("jumpButton")
    }
}

struct SlowMoCircleButton: View {
    @ObservedObject var model: GameModel

    var body: some View {
        Button {
            model.toggleSlowMotion()
        } label: {
            VStack(spacing: 1) {
                Image(systemName: model.isSlowMotionUnlocked ? "hourglass" : "lock.fill")
                    .font(.system(size: 15, weight: .bold))
                Text(model.isSlowMotionUnlocked ? "SLOW" : "CHRONO")
                    .font(.system(size: 7, weight: .black, design: .monospaced))
            }
            .foregroundStyle(
                model.isSlowMotionActive ? .black : (model.isSlowMotionUnlocked ? Color.pink : Color.cyan.opacity(0.85))
            )
            .frame(width: 48, height: 48)
            .background(
                model.isSlowMotionActive
                    ? AnyShapeStyle(Color.pink)
                    : (model.isSlowMotionUnlocked ? AnyShapeStyle(Color.black.opacity(0.65)) : AnyShapeStyle(Color.blue.opacity(0.30))),
                in: Circle()
            )
            .overlay(
                Circle().stroke(
                    model.isSlowMotionActive ? Color.pink.opacity(0.95) : (model.isSlowMotionUnlocked ? Color.pink.opacity(0.60) : Color.cyan.opacity(0.55)),
                    lineWidth: 1.5
                )
            )
            .shadow(color: (model.isSlowMotionUnlocked ? Color.pink : Color.cyan).opacity(model.isSlowMotionActive ? 0.6 : 0.20), radius: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.isSlowMotionUnlocked ? "Cámara Lenta Slow Motion" : "Chrono-Core Bloqueado")
    }
}

struct WarpCircleButton: View {
    @ObservedObject var model: GameModel

    var body: some View {
        Button {
            model.showsLightRadialMenu.toggle()
        } label: {
            VStack(spacing: 1) {
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 16, weight: .bold))
                Text("WARP")
                    .font(.system(size: 7, weight: .black, design: .monospaced))
            }
            .foregroundStyle(model.showsLightRadialMenu ? .black : Color.cyan)
            .frame(width: 48, height: 48)
            .background(
                model.showsLightRadialMenu
                    ? AnyShapeStyle(Color.cyan)
                    : AnyShapeStyle(Color.black.opacity(0.65)),
                in: Circle()
            )
            .overlay(Circle().stroke(Color.cyan.opacity(model.showsLightRadialMenu ? 0.95 : 0.60), lineWidth: 1.5))
            .shadow(color: Color.cyan.opacity(model.showsLightRadialMenu ? 0.6 : 0.15), radius: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Menú Radial de Teletransporte")
    }
}

struct ContextualActionCircleButton: View {
    @ObservedObject var model: GameModel
    @Binding var dimmerFixture: GameLightFixture?

    var body: some View {
        let hasCover = model.isNearCoverRock || model.isCoverActive
        let hasLight = model.nearbyLight != nil && !model.isDefeated && !model.isRecoveringInChamber

        if model.isEditingHUDLayout || hasCover || hasLight {
            Button {
                if hasCover {
                    model.toggleCover()
                } else if hasLight {
                    model.toggleNearbyLight()
                }
            } label: {
                ZStack {
                    if hasCover {
                        VStack(spacing: 1) {
                            Image(systemName: model.isCoverActive ? "shield.fill" : "shield")
                                .font(.system(size: 16, weight: .bold))
                            Text(model.isCoverActive ? "CUBIERTO" : "CUBRIR")
                                .font(.system(size: 6.5, weight: .black, design: .monospaced))
                        }
                        .foregroundStyle(model.isCoverActive ? .black : Color.green)
                    } else if let light = model.nearbyLight {
                        let isOn = model.lightStates.isEnabled(light)
                        VStack(spacing: 1) {
                            Image(systemName: isOn ? "lightbulb.fill" : "lightbulb.slash.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text(isOn ? "ON" : "OFF")
                                .font(.system(size: 7, weight: .black, design: .monospaced))
                        }
                        .foregroundStyle(isOn ? (light == .sheeritNeon ? .orange : (light == .piscinaNeon ? .cyan : .yellow)) : .white.opacity(0.85))
                    } else {
                        VStack(spacing: 1) {
                            Image(systemName: "hand.tap.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("ACCIÓN")
                                .font(.system(size: 6.5, weight: .black, design: .monospaced))
                        }
                        .foregroundStyle(.white)
                    }
                }
                .frame(width: 48, height: 48)
                .background(
                    (model.isCoverActive ? Color.green : Color.black.opacity(0.65)),
                    in: Circle()
                )
                .overlay(
                    Circle().stroke(
                        hasCover ? (model.isCoverActive ? Color.green : Color.green.opacity(0.60)) :
                        (hasLight ? Color.cyan.opacity(0.80) : Color.white.opacity(0.40)),
                        lineWidth: 1.5
                    )
                )
                .shadow(color: (model.isCoverActive ? Color.green : Color.cyan).opacity(0.35), radius: 6)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    if let light = model.nearbyLight {
                        dimmerFixture = light
                    }
                }
            )
            .popover(
                isPresented: Binding(
                    get: { dimmerFixture != nil },
                    set: { if !$0 { dimmerFixture = nil } }
                ),
                arrowEdge: .bottom
            ) {
                if let fixture = dimmerFixture {
                    LightDimmerPopover(fixture: fixture, model: model)
                }
            }
        }
    }
}

struct MirrorShieldJoystickButton: View {
    @ObservedObject var model: GameModel
    @State private var dragOffset: CGSize = .zero
    @State private var initialToolWasMirror: Bool = false
    @State private var didMoveSignificantly: Bool = false

    private var heatColor: Color {
        if model.mirrorOverheated {
            return Color.red
        } else if model.mirrorHeat > 0.70 {
            return Color.orange
        } else if model.mirrorHeat > 0.35 {
            return Color.yellow
        } else {
            return Color.cyan
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.04, model.mirrorHeat)))
                .stroke(
                    heatColor,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Circle()
                .fill(
                    model.heldTool == .mirror
                        ? (model.mirrorOverheated ? Color.red.opacity(0.75) : Color.cyan)
                        : (model.mirrorOverheated ? Color.red.opacity(0.35) : Color.black.opacity(0.65))
                )
                .frame(width: 48, height: 48)

            VStack(spacing: 1) {
                Image(systemName: model.mirrorOverheated ? "flame.fill" : "shield.fill")
                    .font(.system(size: 15, weight: .bold))
                Text(model.mirrorOverheated ? "¡HOT!" : "\(Int((model.mirrorHeat * 100).rounded()))%")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
            }
            .foregroundStyle(model.heldTool == .mirror ? .black : heatColor)
            .offset(dragOffset)
        }
        .frame(width: 48, height: 48)
        .overlay(Circle().stroke(heatColor.opacity(0.8), lineWidth: 1.5))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !model.mirrorOverheated else { return }
                    let distance = hypot(value.translation.width, value.translation.height)
                    if dragOffset == .zero && !didMoveSignificantly {
                        initialToolWasMirror = (model.heldTool == .mirror)
                    }
                    if distance > 6 {
                        didMoveSignificantly = true
                    }
                    if model.heldTool != .mirror {
                        model.heldTool = .mirror
                    } else if model.toolStatus.activeRemaining <= 0.01 && model.toolStatus.cooldownRemaining <= 0.01 {
                        // Re-activar inmediatamente el espejo si ya terminó la recarga sin obligar a cambiar de herramienta
                        model.heldTool = .none
                        model.heldTool = .mirror
                    }
                    let maxRadius: CGFloat = 28.0
                    let dx = max(-maxRadius, min(maxRadius, value.translation.width))
                    let dy = max(-maxRadius, min(maxRadius, value.translation.height))
                    dragOffset = CGSize(width: dx, height: dy)
                    model.shieldAngleOffset = CGVector(dx: -(dx / maxRadius) * 1.25, dy: -(dy / maxRadius) * 1.25)
                }
                .onEnded { value in
                    let distance = hypot(value.translation.width, value.translation.height)
                    if !didMoveSignificantly && distance < 8 && initialToolWasMirror {
                        // Tapped while mirror was already equipped -> toggle off!
                        model.heldTool = .none
                    }
                    dragOffset = .zero
                    model.shieldAngleOffset = .zero
                    didMoveSignificantly = false
                    initialToolWasMirror = false
                }
        )
        .accessibilityLabel("Espejo Defensivo")
    }
}

struct StoryChapter: Identifiable {
    let id: Int
    let title: String
    let subtitle: String
    let badge: String
    let scriptES: String
    let scriptEN: String
    let scriptPT: String
    let scriptFR: String

    func script(for lang: String) -> String {
        switch lang {
        case "en": return scriptEN
        case "pt": return scriptPT
        case "fr": return scriptFR
        default: return scriptES
        }
    }
}

final class StoryPrologueManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published var currentChapterIndex: Int = 0
    @Published var isSpeaking: Bool = false
    @Published var isMuted: Bool = false
    @Published var selectedLanguage: String = "es"
    @Published var displayedChars: Int = 0
    @Published var isStoryCompleted: Bool = false
    @Published var playbackSpeed: Float = 1.0 // 1.0x, 1.5x, 2.0x
    @Published var isSpeedingUp: Bool = false // Gesto TikTok estilo press-and-hold
    @Published var autoAdvance: Bool = true
    @Published var showsSubtitles: Bool = true

    var onPrologueCompleted: (() -> Void)? = nil
    private var autoAdvanceWorkItem: DispatchWorkItem? = nil

    private let synthesizer = AVSpeechSynthesizer()
    private var audioPlayer: AVAudioPlayer?
    private var backgroundMusicPlayer: AVAudioPlayer?
    private var typewriterTimer: Timer?
    private var isStoppingIntentionally = false

    static let chapters: [StoryChapter] = [
        StoryChapter(
            id: 0,
            title: "Capítulo I • El Reino de Lumina",
            subtitle: "La armonía de los Slimes y el secreto cuántico de la luz",
            badge: "ORIGEN ANCESTRAL",
            scriptES: "Registro de emergencia cuántica cero siete. Si recibes esta frecuencia... el Gran Salón de Lumina ha caído. No siempre fuimos soldados. Éramos una pacífica civilización de slimes de gelatina bioluminiscente, guardianes del secreto cósmico de la luz pura.",
            scriptEN: "Quantum emergency log zero seven. If you are receiving this frequency... the Great Hall of Lumina has fallen. We were never soldiers. We were a peaceful civilization of bioluminescent jelly slimes, guardians of the cosmic secret of pure light.",
            scriptPT: "Registro de emergência quântica zero sete. Se você está recebendo esta frequência... o Grande Salão de Lumina caiu. Nunca fomos soldados. Éramos uma civilização pacífica de slimes de gelatina bioluminescente, guardiões do segredo cósmico da luz pura.",
            scriptFR: "Rapport d'urgence quantique zéro sept. Si vous recevez cette fréquence... la Grande Salle de Lumina est tombée. Nous n'avons jamais été des soldats. Nous étions une paisible civilisation de slimes bioluminescents, gardiens du secret cosmique de la lumière pure."
        ),
        StoryChapter(
            id: 1,
            title: "Capítulo II • La Invasión Fotófaga",
            subtitle: "Autómatas biomecánicos descendiendo del vacío estelar",
            badge: "AMENAZA CÓSMICA",
            scriptES: "Pero en la noche del Eclipse Eterno, ellos descendieron de las estrellas... Los Fotófagos. Autómatas biomecánicos colosales devoradores de energía, decididos a saquear nuestra tecnología de iluminación para saciar el frío vacío de sus mundos muertos.",
            scriptEN: "Until the night of the Eternal Eclipse, when they descended from the stars... The Photophages. Colossal biomechanical automatons seeking our illumination technology to feed the cold void of their dying worlds.",
            scriptPT: "Mas na noite do Eclipse Eterno, eles desceram das estrelas... Os Fotófagos. Autômatos biomecânicos colossais devoradores de energia, determinados a saquear nossa tecnologia de iluminação para saciar o vazio frio de seus mundos mortos.",
            scriptFR: "Mais dans la nuit de l'Éclipse Éternelle, ils sont descendus des étoiles... Les Photophages. Des automates biomécaniques colossaux dévoreurs d'énergie, déterminés à piller notre technologie d'éclairage pour combler le vide glacial de leurs mondes mourants."
        ),
        StoryChapter(
            id: 2,
            title: "Capítulo III • La Arena y las Armas de Luz",
            subtitle: "Blaster Láser, Escudo Espejo y las 4 luminarias maestras",
            badge: "OBJETIVO TÁCTICO",
            scriptES: "Nos confinaron en esta arena de pruebas holográfica. Drenaron el cien por ciento de las luces para debilitarnos. Tu misión es sagrada: empuña el Blaster Fotónico y el Escudo Espejo, y reactiva las cuatro luminarias maestras. Cada luz devuelve la energía al sistema.",
            scriptEN: "They locked us inside this holographic test arena, draining one hundred percent of the lights to weaken us. Your mission is sacred: wield the Photonic Blaster and Mirror Shield, and reactivate the four master light beacons. Every light restores power to the system.",
            scriptPT: "Eles nos confinaram nesta arena de testes holográfica. Drenaram cem por cento das luzes para nos enfraquecer. Sua missão é sagrada: empunhe o Blaster Fotônico e o Escudo Espelho, e reative as quatro luminárias mestras. Cada luz devolve a energia ao sistema.",
            scriptFR: "Ils nous ont enfermés dans cette arène d'entraînement holographique, drainant cent pour cent des lumières pour nous affaiblir. Votre mission est sacrée : maniez le Blaster Photonique et le Bouclier Miroir, et réactivez les quatre balises maîtresses. Chaque lumière restaure l'énergie du système."
        ),
        StoryChapter(
            id: 3,
            title: "Capítulo IV • La Refracción y el Salón Arcoíris",
            subtitle: "Espejos, fluidos cuánticos y el tobogán subterráneo",
            badge: "MECÁNICA FOTÓNICA",
            scriptES: "La piscina no es agua ordinaria: es un condensador cuántico de refracción. Usa tu linterna y tu láser reflectante para doblar los haces contra los espejos. Cuando alcances la saturación total de luz, el tobogán abrirá el portal subterráneo hacia el legendario Gran Salón Arcoíris.",
            scriptEN: "The pool is no ordinary water: it is a quantum refraction capacitor. Use your flashlight and reflective laser against mirrors to bend beams. When total light saturation is reached, the water slide unlocks the subterranean portal into the legendary Rainbow Hall.",
            scriptPT: "A piscina não é água comum: é um condensador quântico de refração. Use sua lanterna e laser refletivo para dobrar feixes contra os espelhos. Quando alcançar a saturação total de luz, o toboágua abrirá o portal subterrâneo para o lendário Grande Salão Arco-Íris.",
            scriptFR: "La piscine n'est pas de l'eau ordinaire : c'est un condensateur quantique de réfraction. Utilisez votre lampe torche et votre laser réfléchissant pour dévier les faisceaux contre les miroirs. Quand la saturation lumineuse totale sera atteinte, le toboggan débloquera le portail souterrain vers la légendaire Grande Salle Arc-en-ciel."
        ),
        StoryChapter(
            id: 4,
            title: "Capítulo V • La Revelación Final",
            subtitle: "El secreto que cambiará el destino del cosmos para siempre",
            badge: "GIRO DE GUIÓN // SPOILER",
            scriptES: "Pero escucha la verdad oculta que nadie te dijo... Los invasores contra los que luchas no son monstruos de otra galaxia. Son NUESTROS PROPIOS HERMANOS. Son los slimes del futuro lejano, que renunciaron a su cuerpo orgánico y se transformaron en titanio para no morir de frío. No vienen a destruirnos... vienen desesperados a buscar la luz que perdieron al deshumanizarse. ¡No luches con odio! Enciende las luces, alcanza el cien por ciento... ¡y devuélveles la vida a través del Arcoíris!",
            scriptEN: "Now listen to the ultimate truth... The invaders you are fighting are not alien monsters. They are OUR OWN KIND. Slimes from a distant future who surrendered their organic souls, turning into titanium to escape the cosmic cold. They did not come to destroy us... they are desperate to reclaim the light they lost when they cast away their humanity. Do not fight with hatred! Ignite the lights, reach one hundred percent... and restore their souls through the Rainbow!",
            scriptPT: "Mas ouça a verdade oculta... Os invasores contra os quais você luta não são monstros alienígenas. São NOSSOS PRÓPRIOS IRMÃOS. São os slimes do futuro distante que renunciaram à sua alma orgânica e viraram titânio para fugir do frio estelar. Eles não vieram nos destruir... vieram desesperados recuperar a luz que perderam ao se desumanizar. Não lute com ódio! Acenda as luzes, atinja cem por cento... e devolva a vida a eles através do Arco-Íris!",
            scriptFR: "Écoutez maintenant l'ultime vérité... Les envahisseurs que vous combattez ne sont pas des monstres extraterrestres. Ce sont NOS PROPRES FRÈRES. Des slimes d'un futur lointain qui ont abandonné leur âme organique pour devenir du titane face au froid stellaire. Ils ne viennent pas pour nous anéantir... ils cherchent désespérément à retrouver la lumière perdue en perdant leur humanité. Ne combattez pas avec haine ! Allumez les lumières, atteignez cent pour cent... et rendez-leur la vie à travers l'Arc-en-ciel !"
        )
    ]

    override init() {
        super.init()
        synthesizer.delegate = self
        let preferred = Locale.current.language.languageCode?.identifier ?? "es"
        if ["es", "en", "pt", "fr"].contains(preferred) {
            selectedLanguage = preferred
        } else {
            selectedLanguage = "es"
        }
    }

    var effectiveRate: Float {
        let base: Float = 0.54
        if isSpeedingUp || playbackSpeed >= 2.0 {
            return min(0.70, base * 1.35)
        } else if playbackSpeed >= 1.5 {
            return min(0.62, base * 1.18)
        } else {
            return base
        }
    }

    func cyclePlaybackSpeed() {
        if playbackSpeed < 1.4 {
            playbackSpeed = 1.5
        } else if playbackSpeed < 1.9 {
            playbackSpeed = 2.0
        } else {
            playbackSpeed = 1.0
        }
        if let player = audioPlayer {
            player.rate = playbackSpeed
        } else {
            playCurrentChapter(resumeChars: displayedChars)
        }
    }

    var is2XActive: Bool {
        isSpeedingUp || playbackSpeed >= 2.0
    }

    func toggle2X() {
        if is2XActive {
            playbackSpeed = 1.0
            isSpeedingUp = false
        } else {
            playbackSpeed = 2.0
        }
        if let player = audioPlayer {
            player.rate = isSpeedingUp ? 2.0 : playbackSpeed
        } else {
            playCurrentChapter(resumeChars: displayedChars)
        }
    }

    func setSpeedingUp(_ speeding: Bool) {
        guard isSpeedingUp != speeding else { return }
        isSpeedingUp = speeding
        if let player = audioPlayer {
            player.rate = speeding ? 2.0 : playbackSpeed
        } else {
            playCurrentChapter(resumeChars: displayedChars)
        }
    }

    func cancelAutoAdvance() {
        autoAdvanceWorkItem?.cancel()
        autoAdvanceWorkItem = nil
    }

    func triggerAutoAdvanceIfNeeded() {
        guard autoAdvance else { return }
        guard currentChapterIndex < Self.chapters.count else { return }
        let chapter = Self.chapters[currentChapterIndex]
        let fullText = chapter.script(for: selectedLanguage)

        // 1. El texto mecanografiado debe haber terminado por completo
        guard displayedChars >= fullText.count else { return }

        // 2. Si el audio está activo, esperar a que termine la narración
        if !isMuted {
            if isSpeaking || (audioPlayer?.isPlaying == true) {
                return
            }
        }

        // Cancelar cualquier auto-avance previo pendiente
        cancelAutoAdvance()

        let delay: TimeInterval = is2XActive ? 0.6 : 1.2
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, self.autoAdvance else { return }
            if self.currentChapterIndex + 1 < Self.chapters.count {
                self.nextChapter()
            } else {
                self.isStoryCompleted = true
                self.onPrologueCompleted?()
            }
        }
        self.autoAdvanceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func startPrologue() {
        currentChapterIndex = 0
        isStoryCompleted = false
        playBackgroundMusic()
        playCurrentChapter()
    }

    func playBackgroundMusic() {
        guard backgroundMusicPlayer == nil else { return }
        if let asset = NSDataAsset(name: "PrologueTheme") {
            do {
                let player = try AVAudioPlayer(data: asset.data)
                player.numberOfLoops = -1
                player.volume = isMuted ? 0.0 : 0.28
                player.prepareToPlay()
                player.play()
                self.backgroundMusicPlayer = player
            } catch {
                print("Failed to initialize PrologueTheme: \(error)")
            }
        }
    }

    func playCurrentChapter(resumeChars: Int = 0) {
        cancelAutoAdvance()
        isStoppingIntentionally = true
        stopTypewriter()
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil
        isStoppingIntentionally = false

        guard currentChapterIndex < Self.chapters.count else {
            isStoryCompleted = true
            isSpeaking = false
            return
        }

        let chapter = Self.chapters[currentChapterIndex]
        let fullText = chapter.script(for: selectedLanguage)

        if resumeChars > 0 && resumeChars < fullText.count {
            displayedChars = resumeChars
        } else {
            displayedChars = 0
        }

        let charDelay: TimeInterval = (isSpeedingUp || playbackSpeed >= 2.0) ? 0.015 : ((playbackSpeed >= 1.5) ? 0.022 : 0.030)
        typewriterTimer = Timer.scheduledTimer(withTimeInterval: charDelay, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if self.displayedChars < fullText.count {
                self.displayedChars += 1
            } else {
                timer.invalidate()
                self.triggerAutoAdvanceIfNeeded()
            }
        }

        if !isMuted {
            let spokenText: String
            if resumeChars > 0 && resumeChars < fullText.count {
                let startIdx = fullText.index(fullText.startIndex, offsetBy: resumeChars)
                spokenText = String(fullText[startIdx...])
            } else {
                spokenText = fullText
            }

            guard !spokenText.isEmpty else { return }

            // 🎙️ 1. Audio Neuronal de Estudio Ultra-Natural (edge-tts / 0 ms latencia)
            let assetName = "PrologueAudio\(currentChapterIndex)_\(selectedLanguage)"
            if let dataAsset = NSDataAsset(name: assetName),
               let player = try? AVAudioPlayer(data: dataAsset.data) {
                player.delegate = self
                player.enableRate = true
                player.rate = (isSpeedingUp || playbackSpeed >= 2.0) ? 2.0 : (playbackSpeed >= 1.5 ? 1.5 : 1.0)
                if resumeChars > 0 && fullText.count > 0 {
                    let progress = Double(resumeChars) / Double(fullText.count)
                    player.currentTime = player.duration * progress
                }
                player.play()
                self.audioPlayer = player
                self.isSpeaking = true
            } else {
                // Fallback: Sintetizador nativo
                let utterance = AVSpeechUtterance(string: spokenText)
                let voiceCode: String
                switch selectedLanguage {
                case "en": voiceCode = "en-US"
                case "pt": voiceCode = "pt-BR"
                case "fr": voiceCode = "fr-FR"
                default: voiceCode = "es-ES"
                }
                utterance.voice = AVSpeechSynthesisVoice(language: voiceCode) ?? AVSpeechSynthesisVoice(language: "en-US")
                utterance.rate = effectiveRate
                utterance.pitchMultiplier = 0.92
                utterance.volume = 1.0
                isSpeaking = true
                synthesizer.speak(utterance)
            }
        } else {
            isSpeaking = false
        }
    }

    func nextChapter() {
        cancelAutoAdvance()
        if currentChapterIndex + 1 < Self.chapters.count {
            currentChapterIndex += 1
            playCurrentChapter()
        } else {
            isStoryCompleted = true
            stopAll()
            onPrologueCompleted?()
        }
    }

    func previousChapter() {
        cancelAutoAdvance()
        if currentChapterIndex > 0 {
            currentChapterIndex -= 1
            playCurrentChapter()
        }
    }

    func toggleMute() {
        isMuted.toggle()
        backgroundMusicPlayer?.volume = isMuted ? 0.0 : 0.28
        if isMuted {
            isStoppingIntentionally = true
            synthesizer.stopSpeaking(at: .immediate)
            audioPlayer?.stop()
            audioPlayer = nil
            isStoppingIntentionally = false
            isSpeaking = false
            triggerAutoAdvanceIfNeeded()
        } else {
            playCurrentChapter()
        }
    }

    func changeLanguage(_ lang: String) {
        cancelAutoAdvance()
        selectedLanguage = lang
        playCurrentChapter()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard !isStoppingIntentionally else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isSpeaking = false
            self.triggerAutoAdvanceIfNeeded()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard !isStoppingIntentionally else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isSpeaking = false
            self.triggerAutoAdvanceIfNeeded()
        }
    }

    private func stopTypewriter() {
        typewriterTimer?.invalidate()
        typewriterTimer = nil
    }

    func stopAll() {
        cancelAutoAdvance()
        isStoppingIntentionally = true
        stopTypewriter()
        synthesizer.stopSpeaking(at: .immediate)
        audioPlayer?.stop()
        audioPlayer = nil
        backgroundMusicPlayer?.stop()
        backgroundMusicPlayer = nil
        isStoppingIntentionally = false
        isSpeaking = false
    }
}

// MARK: - ⚡ Minijuego: Caja de Fusibles Cuántica (Estilo Wiring de Among Us)
struct QuantumFuseWire: Identifiable, Equatable {
    let id: Int
    let color: Color
    let glowColor: Color
    let name: String
    var isConnected: Bool = false
}

struct QuantumFuseBoxView: View {
    @ObservedObject var model: GameModel
    @Environment(\.dismiss) private var dismiss

    @State private var wires: [QuantumFuseWire] = [
        QuantumFuseWire(id: 0, color: Color(red: 1.0, green: 0.18, blue: 0.35), glowColor: .red, name: "RUBÍ"),
        QuantumFuseWire(id: 1, color: Color(red: 0.0, green: 0.95, blue: 1.0), glowColor: .cyan, name: "CIAN"),
        QuantumFuseWire(id: 2, color: Color(red: 1.0, green: 0.82, blue: 0.20), glowColor: .yellow, name: "ÁMBAR"),
        QuantumFuseWire(id: 3, color: Color(red: 0.78, green: 0.25, blue: 1.0), glowColor: .purple, name: "PLASMA")
    ]

    @State private var rightOrder: [Int] = [2, 0, 3, 1]
    @State private var activeDragWireId: Int? = nil
    @State private var currentDragPoint: CGPoint = .zero
    @State private var leftAnchors: [CGPoint] = Array(repeating: .zero, count: 4)
    @State private var rightAnchors: [CGPoint] = Array(repeating: .zero, count: 4)
    @State private var isCompleted: Bool = false
    @State private var powerPercentage: Int = 0

    private var allConnected: Bool {
        wires.allSatisfy { $0.isConnected }
    }

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.10).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header Caja de Fusibles
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(isCompleted ? .green : .yellow)
                        Text("CIRCUITO CHRONO-CORE // CAJA DE FUSIBLES")
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        Text("POTENCIA:")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                        Text("\(powerPercentage)%")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .foregroundStyle(isCompleted ? .green : (powerPercentage > 50 ? .yellow : .cyan))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.5), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))

                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                            Text("SALIR")
                        }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 6)

                // Franja de Advertencia
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.yellow, .black, .yellow, .black, .yellow],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 3)
                    .opacity(0.8)

                Text(isCompleted ? "✨ ¡CIRCUITO RESTAURADO CON ÉXITO!" : "Conecta cada cable láser a la terminal de su mismo color")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(isCompleted ? Color.green : Color.white.opacity(0.75))
                    .padding(.vertical, 4)

                // Panel de Cableado
                GeometryReader { boardGeo in
                    ZStack {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(red: 0.10, green: 0.12, blue: 0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(Color.cyan.opacity(0.35), lineWidth: 1.5)
                            )
                            .shadow(color: .black.opacity(0.6), radius: 12)

                        // Cables Conectados
                        ForEach(wires) { wire in
                            if wire.isConnected, let targetSlot = rightOrder.firstIndex(of: wire.id) {
                                let start = leftAnchors[wire.id]
                                let end = rightAnchors[targetSlot]
                                if start != .zero && end != .zero {
                                    Path { p in
                                        p.move(to: start)
                                        let midX = (start.x + end.x) * 0.5
                                        p.addCurve(to: end, control1: CGPoint(x: midX, y: start.y), control2: CGPoint(x: midX, y: end.y))
                                    }
                                    .stroke(
                                        wire.color,
                                        style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round)
                                    )
                                    .shadow(color: wire.glowColor.opacity(0.9), radius: 8)

                                    Path { p in
                                        p.move(to: start)
                                        let midX = (start.x + end.x) * 0.5
                                        p.addCurve(to: end, control1: CGPoint(x: midX, y: start.y), control2: CGPoint(x: midX, y: end.y))
                                    }
                                    .stroke(
                                        Color.white.opacity(0.85),
                                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                                    )
                                }
                            }
                        }

                        // Cable en Arrastre Activo
                        if let dragId = activeDragWireId, dragId < wires.count {
                            let wire = wires[dragId]
                            let start = leftAnchors[dragId]
                            Path { p in
                                p.move(to: start)
                                let midX = (start.x + currentDragPoint.x) * 0.5
                                p.addCurve(to: currentDragPoint, control1: CGPoint(x: midX, y: start.y), control2: CGPoint(x: midX, y: currentDragPoint.y))
                            }
                            .stroke(
                                wire.color,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                            )
                            .shadow(color: wire.glowColor.opacity(0.9), radius: 10)

                            Circle()
                                .fill(Color.white)
                                .frame(width: 14, height: 14)
                                .shadow(color: wire.glowColor, radius: 8)
                                .position(currentDragPoint)
                        }

                        // Columnas Izquierda y Derecha
                        HStack {
                            // Izquierda
                            VStack(spacing: 20) {
                                ForEach(0..<4, id: \.self) { idx in
                                    let wire = wires[idx]
                                    HStack(spacing: 8) {
                                        ZStack {
                                            Circle()
                                                .fill(Color(red: 0.16, green: 0.18, blue: 0.22))
                                                .frame(width: 38, height: 38)
                                                .overlay(Circle().stroke(wire.color, lineWidth: 2.5))
                                                .shadow(color: wire.glowColor.opacity(0.6), radius: 6)

                                            Circle()
                                                .fill(wire.color)
                                                .frame(width: 18, height: 18)

                                            if wire.isConnected {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(.black)
                                            }
                                        }
                                        .background(
                                            GeometryReader { cGeo in
                                                Color.clear.onAppear {
                                                    let frame = cGeo.frame(in: .named("fuse_board"))
                                                    leftAnchors[idx] = CGPoint(x: frame.maxX, y: frame.midY)
                                                }
                                                .onChange(of: cGeo.frame(in: .named("fuse_board"))) { newFrame in
                                                    leftAnchors[idx] = CGPoint(x: newFrame.maxX, y: newFrame.midY)
                                                }
                                            }
                                        )

                                        Text(wire.name)
                                            .font(.system(size: 11, weight: .black, design: .monospaced))
                                            .foregroundStyle(wire.color)

                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0, coordinateSpace: .named("fuse_board"))
                                            .onChanged { val in
                                                guard !wire.isConnected && !isCompleted else { return }
                                                if activeDragWireId == nil {
                                                    activeDragWireId = idx
                                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                                }
                                                currentDragPoint = val.location
                                            }
                                            .onEnded { val in
                                                guard activeDragWireId == idx else { return }
                                                handleDrop(for: idx, at: val.location)
                                                activeDragWireId = nil
                                            }
                                    )
                                }
                            }
                            .frame(width: 140)
                            .padding(.leading, 24)

                            Spacer()

                            // Derecha
                            VStack(spacing: 20) {
                                ForEach(0..<4, id: \.self) { slotIdx in
                                    let targetColorId = rightOrder[slotIdx]
                                    let targetWire = wires[targetColorId]
                                    let isPlugged = targetWire.isConnected

                                    HStack(spacing: 8) {
                                        Spacer()

                                        Text(targetWire.name)
                                            .font(.system(size: 11, weight: .black, design: .monospaced))
                                            .foregroundStyle(targetWire.color)

                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(red: 0.16, green: 0.18, blue: 0.22))
                                                .frame(width: 38, height: 38)
                                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(targetWire.color, lineWidth: 2.5))
                                                .shadow(color: targetWire.glowColor.opacity(isPlugged ? 0.9 : 0.3), radius: isPlugged ? 10 : 3)

                                            if isPlugged {
                                                Circle()
                                                    .fill(Color.green)
                                                    .frame(width: 14, height: 14)
                                                    .shadow(color: .green, radius: 6)
                                            } else {
                                                Circle()
                                                    .stroke(targetWire.color.opacity(0.6), lineWidth: 2)
                                                    .frame(width: 12, height: 12)
                                            }
                                        }
                                        .background(
                                            GeometryReader { cGeo in
                                                Color.clear.onAppear {
                                                    let frame = cGeo.frame(in: .named("fuse_board"))
                                                    rightAnchors[slotIdx] = CGPoint(x: frame.minX, y: frame.midY)
                                                }
                                                .onChange(of: cGeo.frame(in: .named("fuse_board"))) { newFrame in
                                                    rightAnchors[slotIdx] = CGPoint(x: newFrame.minX, y: newFrame.midY)
                                                }
                                            }
                                        )
                                    }
                                }
                            }
                            .frame(width: 140)
                            .padding(.trailing, 24)
                        }
                    }
                    .coordinateSpace(name: "fuse_board")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

                if isCompleted {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("¡SOBRECARGA ACTIVADA // CHRONO-CORE DESPIERTO!")
                                .font(.system(size: 11.5, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            Text("+50 SALUD • MODO SLOW-MOTION DESBLOQUEADO • LINTERNA AL 100%")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.yellow)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.green.opacity(0.8), lineWidth: 1.5))
                    .padding(.bottom, 10)
                }
            }
        }
        .onAppear {
            setupBoard()
        }
    }

    private func setupBoard() {
        rightOrder.shuffle()
        powerPercentage = 0
    }

    private func handleDrop(for wireId: Int, at point: CGPoint) {
        for slotIdx in 0..<4 {
            let target = rightAnchors[slotIdx]
            let dist = hypot(point.x - target.x, point.y - target.y)
            if dist < 42.0 {
                let targetColorId = rightOrder[slotIdx]
                if targetColorId == wireId {
                    wires[wireId].isConnected = true
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    model.audio.playLaserReflectionSound()
                    powerPercentage = min(100, wires.filter { $0.isConnected }.count * 25)

                    if allConnected {
                        triggerVictory()
                    }
                    return
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    return
                }
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func triggerVictory() {
        isCompleted = true
        powerPercentage = 100
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        model.audio.playLaserIgnition()
        model.audio.playLanding(intensity: 1.0)
        
        model.onQuantumPuzzleSolved()
        model.playerHealth = min(model.maxPlayerHealth, model.playerHealth + 50)
        model.flashlightBattery = 1.0

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                dismiss()
            }
        }
    }
}

// MARK: - 🎬 Prólogo Cinematográfico con Viñetas Separadas y Audio Natural
struct CinematicPrologueView: View {
    @ObservedObject var model: GameModel
    @StateObject private var prologue = StoryPrologueManager()
    @Environment(\.dismiss) private var dismiss
    @State private var kenBurnsScale: CGFloat = 1.02
    @State private var pressStartTime: Date? = nil
    @State private var isImmersionMode: Bool = false
    @State private var showsImmersionToast: Bool = false

    private func panelImageName(for index: Int) -> String {
        switch index {
        case 0: return "ProloguePanel1"
        case 1: return "ProloguePanel2"
        case 2: return "ProloguePanel3"
        case 3: return "ProloguePanel4"
        default: return "ProloguePanel5"
        }
    }

    // Comprueba si debemos estar en modo pantalla completa 100% limpia sin interfaz
    private var isZeroUIMode: Bool {
        prologue.is2XActive || prologue.isSpeedingUp || isImmersionMode
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // 🌌 1. Ilustración Inmersiva a Pantalla Completa
            let imgName = panelImageName(for: prologue.currentChapterIndex)
            GeometryReader { fullGeo in
                if let uiImg = UIImage(named: imgName) ?? UIImage(named: "PrologueCover") {
                    ZStack {
                        // Halo atmosférico difuminado para rellenar los bordes de la pantalla
                        Image(uiImage: uiImg)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: fullGeo.size.width, height: fullGeo.size.height)
                            .blur(radius: 28)
                            .opacity(0.42)

                        // Cómic / Viñeta nítida centrada ocupando toda la pantalla
                        Image(uiImage: uiImg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: fullGeo.size.width, height: fullGeo.size.height)
                            .scaleEffect(kenBurnsScale)
                            .id("prologue_full_panel_\(prologue.currentChapterIndex)")
                    }
                    .frame(width: fullGeo.size.width, height: fullGeo.size.height)
                    .clipped()
                }
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                // Toque en cualquier lugar de la pantalla: alterna modo inmersión limpia
                withAnimation(.easeInOut(duration: 0.28)) {
                    if prologue.is2XActive {
                        prologue.toggle2X()
                        isImmersionMode = false
                    } else {
                        isImmersionMode.toggle()
                        if isImmersionMode {
                            showsImmersionToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation(.easeOut(duration: 0.4)) {
                                    showsImmersionToast = false
                                }
                            }
                        }
                    }
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            .gesture(
                // Presión prolongada (Long Press): activa 2X mientras mantengas presionado (estilo TikTok/YouTube)
                LongPressGesture(minimumDuration: 0.35)
                    .onEnded { _ in
                        prologue.setSpeedingUp(true)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
            )
            .animation(.easeInOut(duration: 0.35), value: prologue.currentChapterIndex)

            // 🎬 2. Degradado Inferior Suave Cinematográfico (sin cajas oscuras)
            if !isZeroUIMode {
                VStack {
                    Spacer()
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.0),
                            Color.black.opacity(0.35),
                            Color.black.opacity(0.72)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 120)
                    .allowsHitTesting(false)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }

            // 💎 3. Interfaz Flotante Limpia (Se oculta 100% en 2X o Modo Inmersión)
            if !isZeroUIMode {
                VStack(spacing: 0) {
                    // Barra Superior Flotante Minimalista
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                                .shadow(color: .red, radius: 4)
                            Text("LUMINA // REGISTRO 0-7")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .background(Color.black.opacity(0.35), in: Capsule())
                        .overlay(Capsule().stroke(Color.red.opacity(0.65), lineWidth: 1))

                        Spacer()

                        // Selector de Idiomas
                        HStack(spacing: 2) {
                            ForEach(["es", "en", "pt", "fr"], id: \.self) { lang in
                                Button {
                                    prologue.changeLanguage(lang)
                                } label: {
                                    Text(flagForLang(lang))
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(prologue.selectedLanguage == lang ? .white : .white.opacity(0.55))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(
                                            prologue.selectedLanguage == lang ? Color.cyan.opacity(0.45) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 6)
                                        )
                                }
                            }
                        }
                        .padding(3)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.15), lineWidth: 1))

                        // Botón de Velocidad
                        Button {
                            prologue.cyclePlaybackSpeed()
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text(String(format: "%.1fx", prologue.playbackSpeed))
                                    .font(.system(size: 11, weight: .black, design: .monospaced))
                            }
                            .foregroundStyle(prologue.playbackSpeed > 1.0 ? Color.yellow : Color.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .background(Color.black.opacity(0.35), in: Capsule())
                            .overlay(Capsule().stroke(prologue.playbackSpeed > 1.0 ? Color.yellow.opacity(0.8) : Color.white.opacity(0.25), lineWidth: 1))
                        }

                        // Botón de Silencio
                        Button {
                            prologue.toggleMute()
                        } label: {
                            Image(systemName: prologue.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(prologue.isMuted ? Color.pink : Color.cyan)
                                .frame(width: 30, height: 30)
                                .background(.ultraThinMaterial, in: Circle())
                                .background(Color.black.opacity(0.35), in: Circle())
                                .overlay(Circle().stroke((prologue.isMuted ? Color.pink : Color.cyan).opacity(0.6), lineWidth: 1))
                        }

                        // Botón Ocultar HUD (Modo Cine Limpio)
                        Button {
                            withAnimation(.easeInOut(duration: 0.28)) {
                                isImmersionMode = true
                                showsImmersionToast = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation(.easeOut(duration: 0.4)) {
                                    showsImmersionToast = false
                                }
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 30, height: 30)
                                .background(.ultraThinMaterial, in: Circle())
                                .background(Color.black.opacity(0.35), in: Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.20), lineWidth: 1))
                        }

                        // Botón JUGAR / Omitir en la barra superior (despeja totalmente el centro)
                        Button {
                            completeAndClose()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text("JUGAR")
                                    .font(.system(size: 10.5, weight: .black, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                LinearGradient(colors: [Color.cyan, Color.pink], startPoint: .leading, endPoint: .trailing),
                                in: Capsule()
                            )
                            .overlay(Capsule().stroke(Color.white.opacity(0.75), lineWidth: 1))
                            .shadow(color: Color.pink.opacity(0.4), radius: 4)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 14)
                    .transition(.opacity)

                    Spacer()

                    // 💬 Subtítulos Cinematográficos Flotantes (Sin caja oscura que tape la pantalla)
                    let currentChapter = StoryPrologueManager.chapters[min(prologue.currentChapterIndex, StoryPrologueManager.chapters.count - 1)]
                    let fullScript = currentChapter.script(for: prologue.selectedLanguage)
                    let visibleText = String(fullScript.prefix(prologue.displayedChars))

                    VStack(spacing: 6) {
                        // Cabecera compacta flotante: Badge + Título + Progreso
                        HStack(spacing: 8) {
                            Text(currentChapter.badge)
                                .font(.system(size: 8.5, weight: .black, design: .monospaced))
                                .foregroundStyle(.yellow)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.yellow.opacity(0.25), in: Capsule())
                                .overlay(Capsule().stroke(Color.yellow.opacity(0.8), lineWidth: 1))

                            Text(currentChapter.title)
                                .font(.system(size: 12.5, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                                .shadow(color: .black, radius: 3)

                            Spacer()

                            // Barra de Progreso de Capítulos
                            HStack(spacing: 4) {
                                ForEach(0..<StoryPrologueManager.chapters.count, id: \.self) { idx in
                                    Capsule()
                                        .fill(idx <= prologue.currentChapterIndex ? Color.cyan : Color.white.opacity(0.30))
                                        .frame(width: idx == prologue.currentChapterIndex ? 18 : 8, height: 3.5)
                                        .shadow(color: idx == prologue.currentChapterIndex ? Color.cyan : Color.clear, radius: 3)
                                }
                            }

                            Text("PARTE \(prologue.currentChapterIndex + 1)/\(StoryPrologueManager.chapters.count)")
                                .font(.system(size: 9.5, weight: .black, design: .monospaced))
                                .foregroundStyle(Color.cyan)
                                .shadow(color: .black, radius: 2)
                        }
                        .frame(maxWidth: 820)
                        .padding(.horizontal, 16)

                        // Texto de subtítulo flotante con alta legibilidad
                        Text(visibleText)
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .lineSpacing(2.5)
                            .lineLimit(3)
                            .shadow(color: .black, radius: 3, x: 0, y: 1.5)
                            .shadow(color: .black.opacity(0.9), radius: 8, x: 0, y: 2)
                            .frame(maxWidth: 820, alignment: .leading)
                            .padding(.horizontal, 16)
                            .frame(height: 44)

                        // Barra de micro-controles flotantes en la base
                        HStack(spacing: 12) {
                            Button {
                                prologue.previousChapter()
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(prologue.currentChapterIndex > 0 ? .white : .white.opacity(0.25))
                                    .frame(width: 28, height: 28)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .background(Color.black.opacity(0.4), in: Circle())
                            }
                            .disabled(prologue.currentChapterIndex == 0)

                            Button {
                                prologue.playCurrentChapter()
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .background(Color.black.opacity(0.4), in: Circle())
                            }

                            // ⚡ Botón de Velocidad 2X (Inmersión Total Automática)
                            Button {
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    prologue.toggle2X()
                                    if prologue.is2XActive {
                                        isImmersionMode = true
                                    }
                                }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 9, weight: .bold))
                                    Text(prologue.is2XActive ? "2X ON" : "2X CINE")
                                        .font(.system(size: 10, weight: .black, design: .monospaced))
                                }
                                .foregroundStyle(prologue.is2XActive ? Color.black : Color.yellow)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(prologue.is2XActive ? Color.yellow : Color.black.opacity(0.45), in: Capsule())
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(Capsule().stroke(Color.yellow.opacity(0.8), lineWidth: 1.0))
                                .shadow(color: Color.yellow.opacity(0.4), radius: 4)
                            }

                            Spacer()

                            // Botón Siguiente
                            Button {
                                if prologue.currentChapterIndex < StoryPrologueManager.chapters.count - 1 {
                                    prologue.nextChapter()
                                } else {
                                    completeAndClose()
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                HStack(spacing: 4) {
                                    Text(prologue.currentChapterIndex < StoryPrologueManager.chapters.count - 1 ? "SIGUIENTE" : "FINALIZAR")
                                        .font(.system(size: 10, weight: .black, design: .rounded))
                                    Image(systemName: prologue.currentChapterIndex < StoryPrologueManager.chapters.count - 1 ? "forward.fill" : "checkmark.circle.fill")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .foregroundStyle(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(prologue.currentChapterIndex < StoryPrologueManager.chapters.count - 1 ? Color.cyan : Color.green, in: Capsule())
                                .shadow(color: (prologue.currentChapterIndex < StoryPrologueManager.chapters.count - 1 ? Color.cyan : Color.green).opacity(0.6), radius: 4)
                            }
                        }
                        .frame(maxWidth: 820)
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.35), value: isZeroUIMode)
            }

            // 🌟 Toast de Notificación Modo Inmersión
            if showsImmersionToast {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "film")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.cyan)
                        Text("Modo Cine Inmersivo Activo • Toca la pantalla para ver controles")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .background(Color.black.opacity(0.65), in: Capsule())
                    .overlay(Capsule().stroke(Color.cyan.opacity(0.6), lineWidth: 1))
                    .shadow(color: .cyan.opacity(0.4), radius: 8)
                    .padding(.top, 40)
                    Spacer()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                .allowsHitTesting(false)
            }

            // Indicador TikTok 2X mientras se mantiene pulsado
            if prologue.isSpeedingUp {
                VStack {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.yellow)
                        Text("2X VELOCIDAD ACTIVA")
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .background(Color.black.opacity(0.65), in: Capsule())
                    .overlay(Capsule().stroke(Color.yellow, lineWidth: 1.5))
                    .shadow(color: .yellow.opacity(0.6), radius: 10)
                    .padding(.top, 50)
                    Spacer()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            GKAccessPoint.shared.isActive = false
            prologue.onPrologueCompleted = {
                completeAndClose()
            }
            prologue.startPrologue()
        }
        .onDisappear {
            prologue.stopAll()
        }
    }

    private func flagForLang(_ lang: String) -> String {
        switch lang {
        case "en": return "🇺🇸 EN"
        case "pt": return "🇧🇷 PT"
        case "fr": return "🇫🇷 FR"
        default: return "🇪🇸 ES"
        }
    }

    private func completeAndClose() {
        model.hasSeenIntroPrologue = true
        model.showsPrologueScreen = false
        prologue.stopAll()
        dismiss()
        if model.gameState != .playing {
            model.startGame()
        }
    }
}

struct CampaignVictoryModalView: View {
    @ObservedObject var model: GameModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.80)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Shiny Crown Icon
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color.yellow.opacity(0.35), Color.clear], center: .center, startRadius: 10, endRadius: 65))
                        .frame(width: 96, height: 96)
                    Image(systemName: "crown.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .yellow.opacity(0.85), radius: 14)
                }

                Text("¡LUMINA RESCATADA AL 100%!")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white, .yellow], startPoint: .top, endPoint: .bottom))
                    .multilineTextAlignment(.center)

                Text("CAMPAÑA PRINCIPAL SUPERADA")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.cyan)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.18), in: Capsule())
                    .overlay(Capsule().stroke(Color.cyan.opacity(0.7), lineWidth: 1))

                Text("¡Has vencido a las 15 oleadas invasoras de Vantablack! Las 4 luminarias resplandecen y el santuario de los Slimes está purificado.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)

                VStack(spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: "infinity")
                            .foregroundStyle(.pink)
                            .font(.system(size: 15, weight: .bold))
                        Text("DESBLOQUEADO: MODO SUPERVIVENCIA INFINITA")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.white)
                    }
                    Text("A partir de ahora, Oleada 16+ sin interrupciones del lore. Pura destreza, reflejos con el espejo y récords.")
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.70))
                        .multilineTextAlignment(.center)
                }
                .padding(10)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                Button {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    model.showsCampaignVictoryModal = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "flame.fill")
                        Text("CONTINUAR A LA OLEADA 16 (SUPERVIVENCIA)")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        LinearGradient(colors: [Color.yellow, Color.orange], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .shadow(color: Color.yellow.opacity(0.5), radius: 8)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
            }
            .padding(20)
            .frame(maxWidth: 420)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.yellow.opacity(0.7), lineWidth: 1.5))
            .shadow(color: Color.black.opacity(0.85), radius: 24)
            .padding(.horizontal, 20)
        }
    }
}

struct MainMenuView: View {
    @ObservedObject var model: GameModel

    var body: some View {
        ZStack {
            // Ultra-subtle liquid glass background (3D raytraced patio shining through!)
            Color.black.opacity(0.40)
                .ignoresSafeArea()

            GeometryReader { proxy in
                let isCompactLandscape = proxy.size.height < 520
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: isCompactLandscape ? 10 : 32)

                        //  iOS 18 Liquid Glass Title Card
                        VStack(spacing: isCompactLandscape ? 4 : 8) {
                            Text("LASER TRACER 3D")
                                .font(.system(size: isCompactLandscape ? 28 : 42, weight: .black, design: .rounded))
                                .minimumScaleFactor(0.55)
                                .lineLimit(1)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.white, .cyan, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .shadow(color: .cyan.opacity(0.9), radius: isCompactLandscape ? 10 : 18)

                            Text("METAL RAY TRACING COMBAT & DEFENSIVE SHIELD")
                                .font(.system(size: isCompactLandscape ? 9 : 11, weight: .bold, design: .monospaced))
                                .minimumScaleFactor(0.55)
                                .lineLimit(1)
                                .foregroundStyle(.white.opacity(0.90))
                                .tracking(isCompactLandscape ? 1.5 : 2.5)

                            if model.isCampaignCompleted {
                                HStack(spacing: 5) {
                                    Image(systemName: "crown.fill")
                                        .foregroundStyle(.yellow)
                                    Text("🏆 CAMPAÑA COMPLETADA AL 100% • MODO SUPERVIVENCIA ACTIVO")
                                        .font(.system(size: 8.5, weight: .black, design: .rounded))
                                        .foregroundStyle(.yellow)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.yellow.opacity(0.18), in: Capsule())
                                .overlay(Capsule().stroke(Color.yellow.opacity(0.7), lineWidth: 1))
                            }
                        }
                        .padding(.horizontal, isCompactLandscape ? 20 : 28)
                        .padding(.vertical, isCompactLandscape ? 10 : 20)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: isCompactLandscape ? 18 : 26)
                                    .fill(Color.white.opacity(0.18))
                                    .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: isCompactLandscape ? 18 : 26))

                                RoundedRectangle(cornerRadius: isCompactLandscape ? 18 : 26)
                                    .stroke(
                                        LinearGradient(
                                            colors: [.white.opacity(0.90), .cyan.opacity(0.60), .white.opacity(0.30)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            }
                        )
                        .shadow(color: .cyan.opacity(0.30), radius: isCompactLandscape ? 10 : 16)
                        .padding(.horizontal, 24)

                        Spacer(minLength: isCompactLandscape ? 10 : 40)

                        //  iOS 18 Control Center Liquid Glass Action Tiles (Paleta Unificada Cyan & Pink)
                        VStack(spacing: isCompactLandscape ? 9 : 14) {
                            Button {
                                if model.isAnyMultiplayerConnected {
                                    model.startGame()
                                } else {
                                    model.startSinglePlayerOrPrologue()
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: model.isAnyMultiplayerConnected ? "bolt.horizontal.circle.fill" : "play.fill")
                                        .font(isCompactLandscape ? .subheadline.bold() : .title3.bold())
                                    Text(
                                        model.isAnyMultiplayerConnected
                                            ? "INICIAR MULTIJUGADOR (\(model.activePeerDisplayName))"
                                            : model.slang.playButton
                                    )
                                    .font(isCompactLandscape ? .subheadline.bold() : .headline.bold())
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.80)
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: isCompactLandscape ? 360 : 390, minHeight: isCompactLandscape ? 46 : 56)
                                .background(
                                    ZStack {
                                        RoundedRectangle(cornerRadius: isCompactLandscape ? 16 : 22)
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color(red: 0.12, green: 0.86, blue: 1.0), Color(red: 1.0, green: 0.28, blue: 0.65)],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                        RoundedRectangle(cornerRadius: isCompactLandscape ? 16 : 22)
                                            .stroke(Color.white.opacity(0.85), lineWidth: 1.5)
                                    }
                                )
                                .shadow(color: Color(red: 1.0, green: 0.28, blue: 0.65).opacity(0.55), radius: 12)
                            }
                            .buttonStyle(.plain)

                            // 🎬 Lore & Prólogo Cinematográfico (Narrado con IA y Concept Art)
                            Button {
                                model.showsPrologueScreen = true
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "film.stack.fill")
                                        .font(isCompactLandscape ? .subheadline.bold() : .title3.bold())
                                        .foregroundStyle(Color.yellow)
                                    Text(model.slang.loreButtonTitle)
                                        .font(isCompactLandscape ? .subheadline.bold() : .headline.bold())
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.80)
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: isCompactLandscape ? 360 : 390, minHeight: isCompactLandscape ? 44 : 52)
                                .background(
                                    ZStack {
                                        RoundedRectangle(cornerRadius: isCompactLandscape ? 16 : 22)
                                            .fill(Color.white.opacity(0.14))
                                            .background(Color.black.opacity(0.40), in: RoundedRectangle(cornerRadius: isCompactLandscape ? 16 : 22))
                                        RoundedRectangle(cornerRadius: isCompactLandscape ? 16 : 22)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [Color.yellow.opacity(0.85), Color.orange.opacity(0.85)],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                ),
                                                lineWidth: 1.4
                                            )
                                    }
                                )
                                .shadow(color: Color.yellow.opacity(0.35), radius: 8)
                            }
                            .buttonStyle(.plain)

                            Button {
                                model.showsMultiplayerSheet = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: model.isAnyMultiplayerConnected ? "checkmark.seal.fill" : "person.2.fill")
                                        .font(isCompactLandscape ? .subheadline.bold() : .title3.bold())
                                        .foregroundStyle(model.isAnyMultiplayerConnected ? Color.cyan : Color(red: 1.0, green: 0.35, blue: 0.70))
                                    Text(
                                        model.isAnyMultiplayerConnected
                                            ? "SALA ACTIVA (\(model.activePeerDisplayName))"
                                            : model.slang.multiplayerButton
                                    )
                                    .font(isCompactLandscape ? .subheadline.bold() : .headline.bold())
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.80)
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: isCompactLandscape ? 360 : 390, minHeight: isCompactLandscape ? 46 : 56)
                                .background(
                                    ZStack {
                                        RoundedRectangle(cornerRadius: isCompactLandscape ? 16 : 22)
                                            .fill(Color.white.opacity(0.16))
                                            .background(Color.black.opacity(0.40), in: RoundedRectangle(cornerRadius: isCompactLandscape ? 16 : 22))

                                        RoundedRectangle(cornerRadius: isCompactLandscape ? 16 : 22)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [Color.cyan.opacity(0.85), Color.pink.opacity(0.85)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1.4
                                            )
                                    }
                                )
                                .shadow(color: Color.cyan.opacity(0.25), radius: 8)
                            }
                            .buttonStyle(.plain)

                            Button {
                                model.showsSettingsSheet = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "gearshape.fill")
                                        .font(isCompactLandscape ? .subheadline.bold() : .title3.bold())
                                        .foregroundStyle(Color.cyan)
                                    Text(model.slang.optionsButton)
                                        .font(isCompactLandscape ? .subheadline.bold() : .headline.bold())
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: isCompactLandscape ? 360 : 390, minHeight: isCompactLandscape ? 46 : 56)
                                .background(
                                    ZStack {
                                        RoundedRectangle(cornerRadius: isCompactLandscape ? 16 : 22)
                                            .fill(Color.white.opacity(0.14))
                                            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: isCompactLandscape ? 16 : 22))

                                        RoundedRectangle(cornerRadius: isCompactLandscape ? 16 : 22)
                                            .stroke(
                                                LinearGradient(
                                                    colors: [Color.pink.opacity(0.75), Color.cyan.opacity(0.75)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1.2
                                            )
                                    }
                                )
                                .shadow(color: Color.pink.opacity(0.20), radius: 8)
                            }
                            .buttonStyle(.plain)

                            // 🏷️ Version and Commit Tracking Badge
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                    .shadow(color: .green.opacity(0.8), radius: 4)
                                Text(GameAppVersion.formatted)
                                    .font(.system(size: isCompactLandscape ? 9 : 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.70))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.40))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                            )
                            .padding(.top, isCompactLandscape ? 4 : 8)
                        }

                        Spacer(minLength: isCompactLandscape ? 12 : 32)
                    }
                    .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
                    .padding(.bottom, isCompactLandscape ? 16 : 24)
                }
            }
        }
    }
}

struct DefeatOverlayView: View {
    var isTeamDefeat: Bool = false
    var isVersus: Bool = false
    var versusRound: Int = 1
    var localWins: Int = 0
    var remoteWins: Int = 0
    var remotePlayerName: String = "Rival"
    var coopDeaths: Int = 0
    var slang: GameSlang = GameSlang(languageCode: "es")
    var onRespawn: () -> Void

    @State private var animateIn = false

    var body: some View {
        ZStack {
            // Ultra-subtle liquid glass tint (100% crystal clear background so 3D scene shines through!)
            Color.black.opacity(0.28)
                .ignoresSafeArea(.all)

            VStack {
                Spacer()

                //  iOS 18 Focus Pill Liquid Glass Floating Banner Card
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: isVersus ? "skull.fill" : (isTeamDefeat ? "cross.fill" : "moon.fill"))
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(colors: isVersus ? [.white, .red] : (isTeamDefeat ? [.white, .red, .orange] : [.white, .cyan, .orange]), startPoint: .topLeading, endPoint: .bottomTrailing)
                            )

                        Text(isVersus ? slang.defeatVersusTitle : (isTeamDefeat ? slang.defeatTeamTitle : slang.defeatTitle))
                            .font(.system(size: isVersus ? 28 : (isTeamDefeat ? 30 : 38), weight: .black, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(
                                LinearGradient(colors: [.white, Color(red: 1.0, green: 0.38, blue: 0.38), .orange], startPoint: .top, endPoint: .bottom)
                            )
                            .shadow(color: .red.opacity(0.8), radius: 12)
                    }

                    if isVersus {
                        Text("RONDA \(versusRound) • PUNTO PARA \(remotePlayerName.isEmpty ? "RIVAL" : remotePlayerName.uppercased())")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.92))
                            .shadow(color: .black.opacity(0.7), radius: 3)

                        HStack(spacing: 16) {
                            Text("TÚ: \(localWins)")
                                .font(.system(size: 13, weight: .black, design: .monospaced))
                                .foregroundStyle(.cyan)
                            Text("—")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.4))
                            Text("\(remotePlayerName.isEmpty ? "RIVAL" : remotePlayerName.uppercased()): \(remoteWins)")
                                .font(.system(size: 13, weight: .black, design: .monospaced))
                                .foregroundStyle(.red)
                        }
                        .padding(.top, 2)
                    } else if isTeamDefeat {
                        Text("AMBOS AGENTES HAN CAÍDO • BAJAS TOTALES: \(coopDeaths)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundStyle(.white.opacity(0.92))
                            .shadow(color: .black.opacity(0.7), radius: 3)
                    } else {
                        Text(slang.defeatSubtitleReset)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(2.0)
                            .foregroundStyle(.white.opacity(0.92))
                            .shadow(color: .black.opacity(0.7), radius: 3)
                    }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 18)
                .background(
                    ZStack {
                        // Frosted liquid glass backdrop fill
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                            .background(.ultraThinMaterial, in: Capsule())

                        // Inner Specular Glint & Highlights
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.92),
                                        Color.white.opacity(0.20),
                                        Color.cyan.opacity(0.80),
                                        Color.white.opacity(0.60)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
                )
                .shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 6)
                .shadow(color: Color.white.opacity(0.20), radius: 10, x: 0, y: 0)
                .scaleEffect(animateIn ? 1.0 : 0.82)

                Spacer().frame(height: 24)

                //  iOS 18 Focus Pill Liquid Glass Action Button (Identical to Lock Screen Focus Pill in Image 3!)
                Button(action: onRespawn) {
                    HStack(spacing: 8) {
                        Image(systemName: isVersus ? "arrow.right.circle.fill" : "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)

                        Text(isVersus ? slang.nextRoundButton : slang.retryButton)
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        ZStack {
                            Capsule()
                                .fill(Color.white.opacity(0.22))
                                .background(Color.black.opacity(0.40), in: Capsule())

                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: [.white.opacity(0.95), .white.opacity(0.30), .orange.opacity(0.70)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.2
                                )
                        }
                    )
                    .shadow(color: .white.opacity(0.25), radius: 10, x: 0, y: 0)
                    .shadow(color: .black.opacity(0.30), radius: 10, x: 0, y: 4)
                }
                .scaleEffect(animateIn ? 1.0 : 0.88)

                Spacer()
            }
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.all)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.70)) {
                animateIn = true
            }
        }
    }
}

struct RecoveryChamberOverlayView: View {
    @ObservedObject var model: GameModel

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "wind")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(Color.yellow)

                    Text("¡DESINFLADO COMO SLIME!")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(
                            LinearGradient(colors: [.white, .yellow, .green], startPoint: .leading, endPoint: .trailing)
                        )
                }

                if model.isTeammateBoostingRecovery {
                    HStack(spacing: 6) {
                        Image(systemName: "wind")
                            .foregroundStyle(.yellow)
                        Text("💨 ¡COMPAÑERO BOMBEÁNDOTE AIRE! (\(model.inflationPumpsCount)/5)")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(.yellow)
                    }
                } else {
                    Text("ESPERA A QUE TU COMPAÑERO SE ACERQUE A BOMBEARTE AIRE...")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }

                let progress = min(1.0, max(0.0, Float(model.inflationPumpsCount) / 5.0))
                VStack(spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.black.opacity(0.55))

                            Capsule()
                                .fill(
                                    LinearGradient(colors: [.yellow, .green, .cyan], startPoint: .leading, endPoint: .trailing)
                                )
                                .frame(width: max(6, geo.size.width * CGFloat(progress)))
                        }
                    }
                    .frame(height: 12)

                    HStack {
                        Text("PRESIÓN NEUMÁTICA: \(Int(progress * 100))%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.92))

                        Spacer()

                        Text("\(max(0, 5 - model.inflationPumpsCount))s")
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundStyle(.yellow)
                    }
                }
                .frame(width: 290)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(
                ZStack {
                    Capsule()
                        .fill(Color.black.opacity(0.60))
                        .background(.ultraThinMaterial, in: Capsule())

                    Capsule()
                        .stroke(
                            LinearGradient(colors: [.yellow.opacity(0.85), .green.opacity(0.60)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1.5
                        )
                }
            )
            .shadow(color: .yellow.opacity(0.35), radius: 16, x: 0, y: 6)
            .padding(.bottom, 24)
        }
    }
}
