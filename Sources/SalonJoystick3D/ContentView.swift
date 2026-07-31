import SwiftUI
import AVFoundation
import Metal
import StoreKit

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
        case .none: "power"
        case .flashlight: "flashlight.on.fill"
        case .laser: "scope"
        case .mirror: "rectangle.portrait.fill"
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

struct GameLightStates: Equatable {
    var post = true
    var piscinaNeon = true
    var sheeritNeon = true
    var poolStrips = true
    var postIntensity: Float = 1
    var piscinaNeonIntensity: Float = 1
    var sheeritNeonIntensity: Float = 1
    var poolStripsIntensity: Float = 1

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
        case .post: post.toggle()
        case .piscinaNeon: piscinaNeon.toggle()
        case .sheeritNeon: sheeritNeon.toggle()
        case .poolStrips: poolStrips.toggle()
        }
    }

    func intensity(_ fixture: GameLightFixture) -> Float {
        switch fixture {
        case .post: postIntensity
        case .piscinaNeon: piscinaNeonIntensity
        case .sheeritNeon: sheeritNeonIntensity
        case .poolStrips: poolStripsIntensity
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
    case light
    case balanced
    case high

    var id: Self { self }

    var scale: CGFloat {
        switch self {
        case .light: 0.75
        case .balanced: 1.0
        case .high: 1.5
        }
    }

    var label: String {
        switch self {
        case .light: "Ligera (0,75x)"
        case .balanced: "Equilibrada (1x)"
        case .high: "Alta (1,5x)"
        }
    }
}

struct ContentView: View {
    @StateObject private var model = GameModel()
    @State private var dimmerFixture: GameLightFixture?
    @State private var showsCoffeeStore = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            MetalGameView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                Text("Patio nocturno")
                    .font(.headline)
                    .foregroundStyle(.white)

                Picker("Cámara", selection: $model.cameraMode) {
                    Label("3ª", systemImage: "person.fill")
                        .tag(GameCameraMode.thirdPerson)
                    Label("1ª", systemImage: "eye.fill")
                        .tag(GameCameraMode.firstPerson)
                }
                .pickerStyle(.segmented)
                .frame(width: 190)
                .accessibilityLabel("Modo de cámara")

                JoystickView { vector in
                    model.joystick = vector
                }
                .frame(width: 168, height: 168)
            }
            .padding(14)
            .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
            .padding(.leading, 14)
            .padding(.bottom, 22)

            VStack(alignment: .trailing, spacing: 12) {
                if let nearbyLight = model.nearbyLight {
                    ContextualLightButton(
                        isOn: model.lightStates.isEnabled(nearbyLight),
                        label: nearbyLight.label,
                        onTap: model.toggleNearbyLight,
                        onLongPress: { dimmerFixture = nearbyLight }
                    )
                    .popover(
                        isPresented: Binding(
                            get: { dimmerFixture != nil },
                            set: { if !$0 { dimmerFixture = nil } }
                        ),
                        arrowEdge: .trailing
                    ) {
                        if let fixture = dimmerFixture {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "lightbulb.fill")
                                        .foregroundStyle(.yellow)
                                    Text(fixture.label)
                                        .font(.headline)
                                    Spacer()
                                    Text("\(Int((model.lightStates.intensity(fixture) * 100).rounded()))%")
                                        .font(.caption.monospacedDigit())
                                }
                                Slider(
                                    value: Binding(
                                        get: { Double(model.lightStates.intensity(fixture)) },
                                        set: { model.setLightIntensity(Float($0), for: fixture) }
                                    ),
                                    in: 0.1...1
                                )
                                .tint(.yellow)
                            }
                            .padding(14)
                            .frame(width: 260)
                            .presentationCompactAdaptation(.popover)
                        }
                    }
                }

                Button {
                    model.cycleHeldTool()
                } label: {
                    Image(systemName: model.heldTool.icon)
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(model.heldTool == .none ? .white.opacity(0.72) : .black)
                        .frame(width: 62, height: 62)
                        .background(
                            model.heldTool == .none ? .black.opacity(0.64) : .white.opacity(0.94),
                            in: Circle()
                        )
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(model.heldTool == .none ? 0.22 : 0.72), lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .accessibilityLabel("Herramienta: \(model.heldTool.label)")
                .accessibilityHint("Toca para cambiar de herramienta")
                .accessibilityIdentifier("toolButton")

                if !model.toolStatus.label.isEmpty {
                    Text(model.toolStatus.label)
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 6))
                }

                Button {
                    model.requestJump()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 76, height: 76)
                        .background(.white.opacity(0.94), in: Circle())
                        .overlay {
                            Circle()
                                .stroke(.yellow.opacity(0.85), lineWidth: 3)
                        }
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
                .accessibilityLabel("Saltar")
                .accessibilityIdentifier("jumpButton")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 28)
            .padding(.bottom, 48)

            VStack(alignment: .trailing, spacing: 8) {
                Menu {
                    Toggle(isOn: $model.showsFPS) {
                        Label("Mostrar FPS", systemImage: "speedometer")
                    }

                    Picker("Resolución interna", selection: $model.renderResolution) {
                        ForEach(GameRenderResolution.allCases) { resolution in
                            Text(resolution.label)
                                .tag(resolution)
                        }
                    }

                    Section("Controles") {
                        Toggle(isOn: $model.invertsCameraY) {
                            Label("Invertir cámara", systemImage: "arrow.up.and.down")
                        }
                    }

                    Section("Audio") {
                        Toggle(isOn: $model.musicEnabled) {
                            Label("Música", systemImage: "music.note")
                        }
                        Toggle(isOn: $model.footstepsEnabled) {
                            Label("Movimiento", systemImage: "wind")
                        }
                        Toggle(isOn: $model.waterSoundEnabled) {
                            Label("Agua", systemImage: "water.waves")
                        }
                    }

                    Section("Partida local") {
                        Picker("Modo", selection: $model.multiplayer.mode) {
                            ForEach(LocalMatchMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        Button {
                            model.multiplayer.host()
                        } label: {
                            Label("Crear sala", systemImage: "wifi")
                        }
                        Button {
                            model.multiplayer.join()
                        } label: {
                            Label("Buscar jugador", systemImage: "person.2")
                        }
                        if model.multiplayer.isConnected {
                            Label("Jugador conectado", systemImage: "checkmark.circle.fill")
                            Button("Desconectar", role: .destructive) {
                                model.multiplayer.stop()
                            }
                        }
                    }

                    Button {
                        showsCoffeeStore = true
                    } label: {
                        Label("Invitarme un café", systemImage: "cup.and.saucer.fill")
                    }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.58), in: Circle())
                }
                .accessibilityLabel("Ajustes de renderizado")

                if model.showsFPS {
                    Text("\(Int(model.framesPerSecond.rounded())) FPS")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .safeAreaPadding(.top, 8)
            .padding(.trailing, 14)
        }
        .background(Color.black)
        .sheet(isPresented: $showsCoffeeStore) {
            CoffeeTipView()
        }
    }
}

private struct CoffeeTipView: View {
    static let productID = "com.estebanavila.RtPruebas.tip.coffee"

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ProductView(id: Self.productID, prefersPromotionalIcon: false)
                .productViewStyle(.compact)
                .padding(20)
                .navigationTitle("Invitarme un café")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Cerrar")
                    }
                }
        }
        .presentationDetents([.medium])
    }
}

final class GameModel: ObservableObject {
    let audio = ChiptuneAudioEngine()
    let multiplayer = LocalMultiplayerSession()

    @Published var cameraMode = GameCameraMode.thirdPerson {
        didSet { }
    }
    @Published var renderResolution = GameRenderResolution.balanced
    @Published var heldTool = GameHeldTool.flashlight
    @Published var lightStates = GameLightStates()
    @Published private(set) var nearbyLight: GameLightFixture?
    @Published var showsFPS = false
    @Published var invertsCameraY = false
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
    @Published private(set) var jumpRequestID = 0
    @Published private(set) var toolStatus = GameToolStatus()

    init() {
        audio.start()
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
    }

    func setLightIntensity(_ value: Float, for fixture: GameLightFixture) {
        lightStates.setIntensity(value, for: fixture)
    }

    func reportNearbyLight(_ fixture: GameLightFixture?) {
        DispatchQueue.main.async { [weak self] in
            guard self?.nearbyLight != fixture else { return }
            self?.nearbyLight = fixture
        }
    }

    func reportFPS(_ value: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.framesPerSecond = value
        }
    }

    func reportToolStatus(_ status: GameToolStatus) {
        DispatchQueue.main.async { [weak self] in
            guard self?.toolStatus != status else { return }
            self?.toolStatus = status
        }
    }
}

private struct ContextualLightButton: View {
    let isOn: Bool
    let label: String
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        Image(systemName: isOn ? "lightbulb.fill" : "lightbulb.slash.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(isOn ? .yellow : .white)
            .frame(width: 54, height: 54)
            .background(.black.opacity(0.64), in: Circle())
            .contentShape(Circle())
            .gesture(
                LongPressGesture(minimumDuration: 0.45)
                    .exclusively(before: TapGesture())
                    .onEnded { result in
                        switch result {
                        case .first:
                            onLongPress()
                        case .second:
                            onTap()
                        }
                    }
            )
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isOn ? "Apagar \(label)" : "Encender \(label)")
            .accessibilityAction(.default) {
                onTap()
            }
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
                firstPersonPitch = max(-0.82, min(0.82, firstPersonPitch - Float(translation.y) * 0.0045))
            } else {
                cameraPitch = max(0.24, min(0.72, cameraPitch - Float(translation.y) * 0.0045))
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
            let isInPool = playerPosition.x > -5.28 && playerPosition.x < 2.28 &&
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
            if postDistance < 2.15 {
                candidates.append((.post, postDistance))
            }
            let piscinaDistance = simd_distance(point, SIMD2<Float>(-5.25, -9.15))
            if piscinaDistance < 2.25 {
                candidates.append((.piscinaNeon, piscinaDistance))
            }
            let sheeritDistance = simd_distance(point, SIMD2<Float>(5.45, 9.15))
            if sheeritDistance < 2.25 {
                candidates.append((.sheeritNeon, sheeritDistance))
            }

            let clampedPoolPoint = SIMD2<Float>(
                min(2.55, max(-5.55, point.x)),
                min(1.40, max(-4.40, point.y))
            )
            let poolEdgeDistance = simd_distance(point, clampedPoolPoint)
            let outsidePoolOpening = point.x < -5.28 || point.x > 2.28 ||
                point.y < -4.08 || point.y > 1.08
            if outsidePoolOpening && poolEdgeDistance < 1.15 {
                candidates.append((.poolStrips, poolEdgeDistance + 0.2))
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
            laserBeamNode.position = SCNVector3(
                (origin.x + end.x) * 0.5,
                (origin.y + end.y) * 0.5,
                (origin.z + end.z) * 0.5
            )
            laserBeamNode.scale = SCNVector3(1, beamLength, 1)
            laserBeamNode.look(
                at: end,
                up: SCNVector3(0, 0, 1),
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
    private let effectsNode = AVAudioPlayerNode()
    private let waterNode = AVAudioPlayerNode()
    private let splashNode = AVAudioPlayerNode()
    private let landingNode = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private let audioQueue = DispatchQueue(label: "com.codex.salonjoystick3d.audio", qos: .userInitiated)
    private var musicBuffer: AVAudioPCMBuffer?
    private var waterBuffer: AVAudioPCMBuffer?
    private var glideBuffer: AVAudioPCMBuffer?
    private var splashBuffers: [AVAudioPCMBuffer] = []
    private var landingBuffers: [AVAudioPCMBuffer] = []
    private var nextSplash = 0
    private var nextLanding = 0
    private var nodesAttached = false
    private var started = false
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

    func setMusicEnabled(_ enabled: Bool) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.musicEnabled = enabled
            self.musicNode.volume = enabled ? 0.22 : 0
        }
    }

    func setEffectsEnabled(_ enabled: Bool) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            self.effectsEnabled = enabled
            self.updateGlideVolume()
            self.landingNode.volume = enabled ? 1 : 0
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
                waterBuffer = makeWaterBuffer()
                glideBuffer = makeGlideBuffer()
                splashBuffers = [
                    makeSplashBuffer(variant: 0),
                    makeSplashBuffer(variant: 1),
                    makeSplashBuffer(variant: 2)
                ].compactMap { $0 }
                landingBuffers = [makeLandingBuffer(variant: 0), makeLandingBuffer(variant: 1)].compactMap { $0 }
            }

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)

            if !nodesAttached {
                engine.attach(musicNode)
                engine.attach(effectsNode)
                engine.attach(waterNode)
                engine.attach(splashNode)
                engine.attach(landingNode)
                engine.connect(musicNode, to: engine.mainMixerNode, format: format)
                engine.connect(effectsNode, to: engine.mainMixerNode, format: format)
                engine.connect(waterNode, to: engine.mainMixerNode, format: format)
                engine.connect(splashNode, to: engine.mainMixerNode, format: format)
                engine.connect(landingNode, to: engine.mainMixerNode, format: format)
                nodesAttached = true
            }

            engine.prepare()
            try engine.start()
            started = true

            musicNode.volume = musicEnabled ? 0.22 : 0
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
                effectsNode.scheduleBuffer(glideBuffer, at: nil, options: .loops)
                effectsNode.play()
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
            guard self.started, self.waterEnabled, !self.splashBuffers.isEmpty else { return }
            let index = self.nextSplash % self.splashBuffers.count
            self.nextSplash += 1
            self.splashNode.volume = 0.42 + max(0, min(1, intensity)) * 0.38
            self.splashNode.scheduleBuffer(self.splashBuffers[index])
            if !self.splashNode.isPlaying {
                self.splashNode.play()
            }
        }
    }

    func playLanding(intensity: Float) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            guard self.started, self.effectsEnabled, !self.landingBuffers.isEmpty else { return }
            let index = self.nextLanding % self.landingBuffers.count
            self.nextLanding += 1
            self.landingNode.volume = 0.62 + max(0, min(1, intensity)) * 0.34
            self.landingNode.scheduleBuffer(self.landingBuffers[index])
            if !self.landingNode.isPlaying {
                self.landingNode.play()
            }
        }
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

    private func makeWaterBuffer() -> AVAudioPCMBuffer? {
        let duration = 8.0
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
            middleNoise = middleNoise * 0.86 + noise * 0.14
            lowNoise = lowNoise * 0.982 + noise * 0.018
            let time = Double(frame) / format.sampleRate
            let edgeFade = min(1.0, min(time, duration - time) / 0.08)
            let surge = 0.82 +
                sin(2 * Double.pi * 0.375 * time) * 0.11 +
                sin(2 * Double.pi * 0.625 * time + 0.8) * 0.07
            let flowingWater = (middleNoise - lowNoise) * 0.34 + lowNoise * 0.52
            let smallBubbles = sin(2 * Double.pi * 286.0 * time + lowNoise * 1.8) * 0.012
            let sample = Float((flowingWater * 0.52 * surge + smallBubbles) * edgeFade)
            channels[0][frame] = sample * 0.92
            channels[1][frame] = sample
        }
        return buffer
    }

    private func makeSplashBuffer(variant: Int) -> AVAudioPCMBuffer? {
        let duration = 0.32
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }
        buffer.frameLength = frameCount

        var seed = UInt32(0x94D0_49BB) &+ UInt32(variant * 1049)
        var lowPass = 0.0
        var bubblePhase = 0.0
        for frame in 0..<Int(frameCount) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Double(seed & 0xFFFF) / 32_767.5 - 1.0
            lowPass = lowPass * 0.72 + noise * 0.28
            let time = Double(frame) / format.sampleRate
            let progress = time / duration
            let attack = min(1.0, time / 0.007)
            let slapEnvelope = attack * exp(-time * (10.0 + Double(variant)))
            let trailEnvelope = attack * exp(-time * 5.5)
            let highPass = noise - lowPass
            let slap = highPass * 0.42 * slapEnvelope
            let body = lowPass * 0.31 * trailEnvelope
            let sample = Float(slap + body)
            channels[0][frame] = sample
            channels[1][frame] = sample * (variant == 1 ? 0.86 : 0.94)
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
        effectsNode.volume = effectsEnabled && glideIntensity > 0.01
            ? 0.14 + glideIntensity * 0.36
            : 0
    }

    private func updateWaterMovementVolume() {
        waterNode.volume = waterEnabled && waterMovementIntensity > 0.01
            ? 0.12 + waterMovementIntensity * 0.36
            : 0
    }

    private func triangle(frequency: Double, time: Double) -> Double {
        2.0 / Double.pi * asin(sin(2.0 * Double.pi * frequency * time))
    }

}

struct JoystickView: View {
    var onChanged: (CGVector) -> Void
    @State private var knob = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let radius = size / 2
            let knobRadius = size * 0.27

            ZStack {
                Circle()
                    .fill(.black.opacity(0.42))
                Circle()
                    .stroke(.white.opacity(0.3), lineWidth: 2)
                Circle()
                    .fill(.white.opacity(0.92))
                    .frame(width: knobRadius * 2, height: knobRadius * 2)
                    .offset(knob)
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
