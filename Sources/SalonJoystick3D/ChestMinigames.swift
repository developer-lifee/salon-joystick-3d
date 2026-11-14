import SwiftUI
import AVFoundation
import UIKit

// MARK: - 🎁 6 Minijuegos de Cofre (uno por cofre, de más fácil a más difícil)
// Todos comparten la misma arena horizontal y el mismo contrato: `isUnlocked` + `onSolved`.

let chestArenaSize = CGSize(width: 420, height: 220)

private func chestHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
    UIImpactFeedbackGenerator(style: style).impactOccurred()
}

private func chestErrorHaptic() {
    UINotificationFeedbackGenerator().notificationOccurred(.error)
}

private struct ChestArenaFrame<Content: View>: View {
    let accent: Color
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.65), lineWidth: 2))
            content
        }
        .frame(width: chestArenaSize.width, height: chestArenaSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct ChestProgressDots: View {
    let done: Int
    let total: Int
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i < done ? color : Color.white.opacity(0.18))
                    .frame(width: 9, height: 9)
            }
        }
    }
}

// MARK: - 🎵 Tonos para el Simón (Do mayor, la tonalidad del salón principal)

final class ChestTonePlayer {
    static let shared = ChestTonePlayer()
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private var buffers: [AVAudioPCMBuffer] = []
    private var errorBuffer: AVAudioPCMBuffer?
    private var started = false

    // C5, E5, G5, C6: el acorde de tónica, así cualquier combinación suena bien
    private let notes: [Double] = [523.25, 659.25, 783.99, 1046.50]

    private init() {}

    private func start() {
        guard !started else { return }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        buffers = notes.map { makeTone(frequency: $0, duration: 0.38) }.compactMap { $0 }
        errorBuffer = makeTone(frequency: 155.56, duration: 0.45) // Mi♭3 grave para el error
        do {
            try engine.start()
            node.play()
            started = true
        } catch {
            started = false
        }
    }

    private func makeTone(frequency: Double, duration: Double) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(format.sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let ch = buffer.floatChannelData else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Double(i) / format.sampleRate
            let env = min(1.0, t * 90.0) * exp(-t * 6.5)
            let s = (sin(2 * .pi * frequency * t) + sin(2 * .pi * frequency * 2 * t) * 0.18) * env * 0.16
            ch[0][i] = Float(s)
            ch[1][i] = Float(s)
        }
        return buffer
    }

    func play(note index: Int) {
        start()
        guard started, buffers.indices.contains(index) else { return }
        node.scheduleBuffer(buffers[index], at: nil, options: .interrupts)
    }

    func playError() {
        start()
        guard started, let errorBuffer else { return }
        node.scheduleBuffer(errorBuffer, at: nil, options: .interrupts)
    }
}

// MARK: - 1. 🎵 Simón de Neones (secuencia de 3 a 6 luces)

struct NeonSimonPuzzleView: View {
    let isUnlocked: Bool
    let onSolved: () -> Void

    private let colors: [Color] = [.red, .green, .cyan, .purple]
    private let maxLength = 6

    @State private var sequence: [Int] = (0..<6).map { _ in Int.random(in: 0..<4) }
    @State private var roundLength = 3
    @State private var inputIndex = 0
    @State private var litPad: Int? = nil
    @State private var isShowing = false
    @State private var flashError = false
    @State private var playbackID = 0

    var body: some View {
        VStack(spacing: 8) {
            ChestArenaFrame(accent: .purple) {
                HStack(spacing: 14) {
                    ForEach(0..<4, id: \.self) { pad in
                        RoundedRectangle(cornerRadius: 16)
                            .fill(colors[pad].opacity(litPad == pad ? 1.0 : 0.28))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(colors[pad], lineWidth: 2))
                            .shadow(color: colors[pad].opacity(litPad == pad ? 0.95 : 0.0), radius: 18)
                            .frame(width: 82, height: 120)
                            .scaleEffect(litPad == pad ? 1.06 : 1.0)
                            .animation(.easeOut(duration: 0.12), value: litPad)
                            .onTapGesture { tap(pad) }
                    }
                }
                if flashError {
                    Color.red.opacity(0.25).allowsHitTesting(false)
                }
            }
            HStack {
                Text(isShowing ? "👀 MIRA LA SECUENCIA…" : "🎵 REPÍTELA (\(inputIndex)/\(roundLength))")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                ChestProgressDots(done: isUnlocked ? maxLength : roundLength - 1, total: maxLength, color: .purple)
            }
            .frame(width: chestArenaSize.width)
        }
        .onAppear { playSequence(after: 0.6) }
    }

    private func playSequence(after delay: Double) {
        playbackID += 1
        let id = playbackID
        isShowing = true
        inputIndex = 0
        let step = 0.55
        for i in 0..<roundLength {
            let start = delay + Double(i) * step
            DispatchQueue.main.asyncAfter(deadline: .now() + start) {
                guard id == playbackID else { return }
                light(sequence[i])
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + Double(roundLength) * step) {
            guard id == playbackID else { return }
            isShowing = false
        }
    }

    private func light(_ pad: Int) {
        litPad = pad
        ChestTonePlayer.shared.play(note: pad)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            if litPad == pad { litPad = nil }
        }
    }

    private func tap(_ pad: Int) {
        guard !isUnlocked, !isShowing else { return }
        light(pad)
        chestHaptic()
        if pad == sequence[inputIndex] {
            inputIndex += 1
            if inputIndex == roundLength {
                if roundLength == maxLength {
                    onSolved()
                } else {
                    roundLength += 1
                    playSequence(after: 0.8)
                }
            }
        } else {
            ChestTonePlayer.shared.playError()
            chestErrorHaptic()
            flashError = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { flashError = false }
            playSequence(after: 0.9)
        }
    }
}

// MARK: - 2. 🎨 Mezclador Arcoíris (mezcla aditiva RGB)

struct RainbowMixerPuzzleView: View {
    let isUnlocked: Bool
    let onSolved: () -> Void

    private static let palette: [(name: String, rgb: SIMD3<Double>)] = [
        ("MAGENTA", SIMD3(1, 0, 1)), ("AMARILLO", SIMD3(1, 1, 0)), ("CIAN", SIMD3(0, 1, 1)),
        ("NARANJA", SIMD3(1, 0.5, 0)), ("VIOLETA", SIMD3(0.5, 0, 1)), ("LIMA", SIMD3(0.5, 1, 0)),
        ("ROSA", SIMD3(1, 0, 0.5)), ("TURQUESA", SIMD3(0, 1, 0.5))
    ]

    @State private var targets: [(name: String, rgb: SIMD3<Double>)] = Array(palette.shuffled().prefix(3))
    @State private var round = 0
    @State private var r: Double = 0.2
    @State private var g: Double = 0.2
    @State private var b: Double = 0.2
    @State private var matchedFlash = false

    private var target: SIMD3<Double> { targets[min(round, targets.count - 1)].rgb }
    private var mix: SIMD3<Double> { SIMD3(r, g, b) }
    private var distance: Double { simd_length(mix - target) }

    var body: some View {
        VStack(spacing: 6) {
            ChestArenaFrame(accent: .pink) {
                HStack(spacing: 30) {
                    VStack(spacing: 6) {
                        Text("OBJETIVO: \(targets[min(round, 2)].name)")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                        Circle()
                            .fill(color(target))
                            .frame(width: 92, height: 92)
                            .shadow(color: color(target).opacity(0.8), radius: 14)
                    }
                    // Tres focos que se solapan: la zona central es la mezcla real
                    ZStack {
                        Circle().fill(Color(red: r, green: 0, blue: 0)).frame(width: 78).offset(x: -20, y: -14)
                            .blendMode(.plusLighter)
                        Circle().fill(Color(red: 0, green: g, blue: 0)).frame(width: 78).offset(x: 20, y: -14)
                            .blendMode(.plusLighter)
                        Circle().fill(Color(red: 0, green: 0, blue: b)).frame(width: 78).offset(x: 0, y: 20)
                            .blendMode(.plusLighter)
                    }
                    .compositingGroup()
                    .frame(width: 130, height: 130)
                    VStack(spacing: 6) {
                        Text("TU MEZCLA")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                        Circle()
                            .fill(color(mix))
                            .frame(width: 92, height: 92)
                            .overlay(Circle().stroke(matchedFlash ? Color.white : Color.clear, lineWidth: 3))
                    }
                }
            }
            HStack(spacing: 10) {
                mixerSlider("R", value: $r, tint: .red)
                mixerSlider("G", value: $g, tint: .green)
                mixerSlider("B", value: $b, tint: .blue)
                ChestProgressDots(done: isUnlocked ? 3 : round, total: 3, color: .pink)
            }
            .frame(width: chestArenaSize.width)
        }
    }

    private func mixerSlider(_ label: String, value: Binding<Double>, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 11, weight: .black, design: .monospaced)).foregroundStyle(tint)
            Slider(value: value, in: 0...1, onEditingChanged: { editing in
                if !editing { check() }
            })
            .tint(tint)
        }
    }

    private func color(_ c: SIMD3<Double>) -> Color { Color(red: c.x, green: c.y, blue: c.z) }

    private func check() {
        guard !isUnlocked, distance < 0.16 else { return }
        chestHaptic(.medium)
        matchedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            matchedFlash = false
            if round >= 2 {
                onSolved()
            } else {
                round += 1
                r = 0.2; g = 0.2; b = 0.2
            }
        }
    }
}

// MARK: - 3. 🔒 Anillos de Cerradura (6 anillos, toca cuando el hueco esté arriba)

struct LockRingsPuzzleView: View {
    let isUnlocked: Bool
    let onSolved: () -> Void

    private let ringCount = 6
    @State private var angles: [Double] = (0..<6).map { _ in Double.random(in: 0..<360) }
    @State private var locked = 0
    @State private var flashError = false
    @State private var timer: Timer?

    private func speed(_ ring: Int) -> Double { 70 + Double(ring) * 28 } // °/s, cada anillo más rápido

    var body: some View {
        VStack(spacing: 8) {
            ChestArenaFrame(accent: .orange) {
                ZStack {
                    ForEach(0..<ringCount, id: \.self) { i in
                        let radius = 22.0 + Double(i) * 15.0
                        Circle()
                            .trim(from: 0.04, to: 0.96)
                            .stroke(ringColor(i), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: radius * 2, height: radius * 2)
                            .rotationEffect(.degrees(angles[i] - 90)) // el hueco queda en el ángulo actual
                            .shadow(color: ringColor(i).opacity(i == locked ? 0.8 : 0), radius: 8)
                    }
                    // Marca superior: el láser entra por aquí
                    Rectangle()
                        .fill(Color.cyan)
                        .frame(width: 3, height: 104)
                        .offset(y: -52)
                        .shadow(color: .cyan, radius: 6)
                    if flashError {
                        Color.red.opacity(0.25).allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { tap() }
            }
            HStack {
                Text("🔒 TOCA CUANDO EL HUECO DEL ANILLO BRILLANTE ESTÉ ARRIBA")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                ChestProgressDots(done: locked, total: ringCount, color: .orange)
            }
            .frame(width: chestArenaSize.width)
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
                guard !isUnlocked, locked < ringCount else { return }
                angles[locked] = (angles[locked] + speed(locked) / 60.0).truncatingRemainder(dividingBy: 360)
            }
        }
        .onDisappear { timer?.invalidate() }
    }

    private func ringColor(_ i: Int) -> Color {
        if i < locked { return .green }
        if i == locked { return .orange }
        return .white.opacity(0.25)
    }

    private func tap() {
        guard !isUnlocked, locked < ringCount else { return }
        // El hueco está centrado en `angle`; arriba = 0°
        let a = angles[locked]
        let offTop = min(a, 360 - a)
        if offTop < 16 {
            angles[locked] = 0
            locked += 1
            chestHaptic(.medium)
            if locked == ringCount { onSolved() }
        } else {
            chestErrorHaptic()
            flashError = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { flashError = false }
            if locked > 0 {
                locked -= 1
                angles[locked] = Double.random(in: 60..<300)
            }
        }
    }
}

// MARK: - 4. 💧 Tanque de Refracción (ley de Snell, agua n = 1.333)

struct RefractionTankPuzzleView: View {
    let isUnlocked: Bool
    let onSolved: () -> Void

    private struct Round { let angleDeg: Double; let targetX: CGFloat }
    @State private var rounds: [Round] = [
        // Rangos alcanzables según el ángulo (tanque vacío ↔ lleno), con margen
        Round(angleDeg: 48, targetX: CGFloat.random(in: 188...214)),
        Round(angleDeg: 58, targetX: CGFloat.random(in: 232...300)),
        Round(angleDeg: 64, targetX: CGFloat.random(in: 266...380))
    ]
    @State private var round = 0
    @State private var waterLevel: CGFloat = 0.15 // 0 = vacío, 1 = lleno
    @State private var hitFlash = false

    private let emitter = CGPoint(x: 30, y: 26)
    private let tankLeft: CGFloat = 70
    private let tankRight: CGFloat = 400
    private let tankTop: CGFloat = 70
    private let floorY: CGFloat = 205

    private var current: Round { rounds[min(round, rounds.count - 1)] }
    private var waterY: CGFloat { floorY - (floorY - tankTop) * waterLevel }

    /// Trayectoria del rayo: aire → superficie del agua → fondo del tanque
    private var beam: (surface: CGPoint, floor: CGPoint) {
        let theta = current.angleDeg * .pi / 180          // ángulo respecto a la vertical
        let dir = CGVector(dx: sin(theta), dy: cos(theta))
        let tSurface = (waterY - emitter.y) / dir.dy
        let surface = CGPoint(x: emitter.x + dir.dx * tSurface, y: waterY)
        let sin2 = sin(theta) / 1.333
        let theta2 = asin(sin2)
        let floorX = surface.x + tan(theta2) * (floorY - waterY)
        return (surface, CGPoint(x: floorX, y: floorY))
    }

    var body: some View {
        VStack(spacing: 6) {
            ChestArenaFrame(accent: .cyan) {
                Canvas { ctx, _ in
                    // Tanque
                    var tank = Path()
                    tank.move(to: CGPoint(x: tankLeft, y: tankTop))
                    tank.addLine(to: CGPoint(x: tankLeft, y: floorY))
                    tank.addLine(to: CGPoint(x: tankRight, y: floorY))
                    tank.addLine(to: CGPoint(x: tankRight, y: tankTop))
                    ctx.stroke(tank, with: .color(.white.opacity(0.5)), lineWidth: 2)
                    // Agua
                    let water = CGRect(x: tankLeft, y: waterY, width: tankRight - tankLeft, height: floorY - waterY)
                    ctx.fill(Path(water), with: .linearGradient(Gradient(colors: [.cyan.opacity(0.45), .blue.opacity(0.55)]),
                                                               startPoint: CGPoint(x: 0, y: waterY), endPoint: CGPoint(x: 0, y: floorY)))
                    // Diana en el fondo
                    let tRect = CGRect(x: current.targetX - 12, y: floorY - 5, width: 24, height: 8)
                    ctx.fill(Path(roundedRect: tRect, cornerRadius: 3), with: .color(hitFlash ? .green : .yellow))
                    // Emisor
                    ctx.fill(Path(ellipseIn: CGRect(x: emitter.x - 8, y: emitter.y - 8, width: 16, height: 16)), with: .color(.red))
                    // Rayo
                    let b = beam
                    var ray = Path()
                    ray.move(to: emitter)
                    ray.addLine(to: b.surface)
                    ray.addLine(to: b.floor)
                    ctx.stroke(ray, with: .color(.red), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    ctx.stroke(ray, with: .color(.white.opacity(0.6)), lineWidth: 1)
                }
            }
            HStack(spacing: 10) {
                Text("💧 NIVEL")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.cyan)
                Slider(value: $waterLevel, in: 0...0.95, onEditingChanged: { editing in
                    if !editing { check() }
                })
                .tint(.cyan)
                ChestProgressDots(done: isUnlocked ? 3 : round, total: 3, color: .cyan)
            }
            .frame(width: chestArenaSize.width)
        }
    }

    private func check() {
        guard !isUnlocked, abs(beam.floor.x - current.targetX) < 12 else { return }
        chestHaptic(.medium)
        hitFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            hitFlash = false
            if round >= 2 {
                onSolved()
            } else {
                round += 1
                waterLevel = 0.15
            }
        }
    }
}

// MARK: - 5. 🐇 Sombras Chinescas (gira la figura y acércala a la linterna)

struct ShadowPuppetPuzzleView: View {
    let isUnlocked: Bool
    let onSolved: () -> Void

    private struct Shape { let symbol: String; let targetAngle: Double; let targetScale: Double }
    @State private var shapes: [Shape] = [
        Shape(symbol: "hare.fill", targetAngle: Double.random(in: 40...140), targetScale: Double.random(in: 1.15...1.5)),
        Shape(symbol: "bird.fill", targetAngle: Double.random(in: 200...320), targetScale: Double.random(in: 0.8...1.1)),
        Shape(symbol: "tortoise.fill", targetAngle: Double.random(in: 100...260), targetScale: Double.random(in: 1.2...1.55))
    ]
    @State private var round = 0
    @State private var angle: Double = 0
    @State private var distance: Double = 0.5 // 0 = lejos de la linterna (sombra pequeña), 1 = cerca (grande)
    @State private var dragStartAngle: Double = 0
    @State private var isDragging = false
    @State private var matched = false

    private var current: Shape { shapes[min(round, shapes.count - 1)] }
    private var shadowScale: Double { 0.7 + distance * 1.0 }

    var body: some View {
        VStack(spacing: 6) {
            ChestArenaFrame(accent: .yellow) {
                HStack(spacing: 0) {
                    // Linterna + figura
                    ZStack {
                        Image(systemName: "flashlight.on.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.yellow)
                            .rotationEffect(.degrees(90))
                            .offset(x: -60)
                        Image(systemName: current.symbol)
                            .font(.system(size: 38))
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(angle))
                            .offset(x: -10 + distance * -30)
                    }
                    .frame(width: 160)
                    // Pared con silueta objetivo y la sombra proyectada
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(RadialGradient(colors: [Color(white: 0.85), Color(white: 0.55)], center: .center, startRadius: 10, endRadius: 140))
                        Image(systemName: current.symbol)
                            .font(.system(size: 64))
                            .foregroundStyle(Color.red.opacity(0.35))
                            .rotationEffect(.degrees(current.targetAngle))
                            .scaleEffect(current.targetScale)
                        Image(systemName: current.symbol)
                            .font(.system(size: 64))
                            .foregroundStyle(Color.black.opacity(matched ? 0.95 : 0.7))
                            .rotationEffect(.degrees(angle))
                            .scaleEffect(shadowScale)
                            .blur(radius: (1 - distance) * 2.5)
                    }
                    .frame(width: 240, height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { v in
                            if !isDragging { isDragging = true; dragStartAngle = angle }
                            angle = (dragStartAngle + Double(v.translation.width) * 0.9).truncatingRemainder(dividingBy: 360)
                            if angle < 0 { angle += 360 }
                        }
                        .onEnded { _ in
                            isDragging = false
                            check()
                        }
                )
            }
            HStack(spacing: 10) {
                Text("↔️ ARRASTRA PARA GIRAR · DISTANCIA")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(.yellow)
                Slider(value: $distance, in: 0...1, onEditingChanged: { editing in
                    if !editing { check() }
                })
                .tint(.yellow)
                ChestProgressDots(done: isUnlocked ? 3 : round, total: 3, color: .yellow)
            }
            .frame(width: chestArenaSize.width)
        }
    }

    private func check() {
        guard !isUnlocked else { return }
        let diff = abs(angle - current.targetAngle)
        let angleOK = min(diff, 360 - diff) < 12
        let scaleOK = abs(shadowScale - current.targetScale) < 0.1
        guard angleOK && scaleOK else { return }
        chestHaptic(.medium)
        matched = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            matched = false
            if round >= 2 {
                onSolved()
            } else {
                round += 1
                angle = 0
                distance = 0.5
                dragStartAngle = 0
            }
        }
    }
}

// MARK: - 6. 🔭 Periscopio Láser de 6 Rebotes (vista de binoculares)

struct PeriscopePuzzleView: View {
    let isUnlocked: Bool
    let onSolved: () -> Void

    // Recorrido de la solución: emisor → M0 → M1 → M2 → M3 → M4 → M5 → lámpara
    private let emitter = CGPoint(x: 18, y: 112)
    private let mirrorCenters: [CGPoint] = [
        CGPoint(x: 80, y: 112), CGPoint(x: 80, y: 36), CGPoint(x: 190, y: 36),
        CGPoint(x: 190, y: 186), CGPoint(x: 300, y: 186), CGPoint(x: 300, y: 36)
    ]
    private let lamp = CGPoint(x: 395, y: 131)
    private let mirrorHalfLength: CGFloat = 22
    private let lampRadius: CGFloat = 16

    @State private var mirrorAngles: [Double] = (0..<6).map { _ in Double(Int.random(in: 0..<36)) * 5 }
    @State private var selected = 0
    @State private var solvedFlash = false

    private struct Trace { var points: [CGPoint]; var mirrorsHit: Set<Int>; var hitLamp: Bool }

    private var trace: Trace {
        var points = [emitter]
        var origin = emitter
        var dir = CGVector(dx: 1, dy: 0)
        var hits = Set<Int>()
        var lastMirror = -1
        for _ in 0..<10 {
            var bestT = CGFloat.greatestFiniteMagnitude
            var bestMirror = -1
            for (i, c) in mirrorCenters.enumerated() where i != lastMirror {
                if let t = intersect(origin: origin, dir: dir, mirror: i, center: c), t < bestT {
                    bestT = t
                    bestMirror = i
                }
            }
            // ¿Toca la lámpara antes que otro espejo?
            if let tl = hitCircle(origin: origin, dir: dir, center: lamp, radius: lampRadius), tl < bestT {
                points.append(CGPoint(x: origin.x + dir.dx * tl, y: origin.y + dir.dy * tl))
                return Trace(points: points, mirrorsHit: hits, hitLamp: true)
            }
            guard bestMirror >= 0 else {
                points.append(CGPoint(x: origin.x + dir.dx * 600, y: origin.y + dir.dy * 600))
                return Trace(points: points, mirrorsHit: hits, hitLamp: false)
            }
            let hit = CGPoint(x: origin.x + dir.dx * bestT, y: origin.y + dir.dy * bestT)
            points.append(hit)
            hits.insert(bestMirror)
            let a = mirrorAngles[bestMirror] * .pi / 180
            let n = CGVector(dx: -sin(a), dy: cos(a))
            let d = dir.dx * n.dx + dir.dy * n.dy
            dir = CGVector(dx: dir.dx - 2 * d * n.dx, dy: dir.dy - 2 * d * n.dy)
            origin = hit
            lastMirror = bestMirror
        }
        return Trace(points: points, mirrorsHit: hits, hitLamp: false)
    }

    var body: some View {
        let t = trace
        VStack(spacing: 6) {
            ChestArenaFrame(accent: .green) {
                ZStack {
                    Canvas { ctx, _ in
                        // Rayo
                        var path = Path()
                        path.addLines(t.points)
                        ctx.stroke(path, with: .color(.red.opacity(0.9)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        ctx.stroke(path, with: .color(.white.opacity(0.55)), lineWidth: 1)
                        // Espejos
                        for (i, c) in mirrorCenters.enumerated() {
                            let a = mirrorAngles[i] * .pi / 180
                            let dx = cos(a) * mirrorHalfLength, dy = sin(a) * mirrorHalfLength
                            var m = Path()
                            m.move(to: CGPoint(x: c.x - dx, y: c.y - dy))
                            m.addLine(to: CGPoint(x: c.x + dx, y: c.y + dy))
                            let color: Color = i == selected ? .yellow : (t.mirrorsHit.contains(i) ? .cyan : .white.opacity(0.7))
                            ctx.stroke(m, with: .color(color), style: StrokeStyle(lineWidth: i == selected ? 5 : 4, lineCap: .round))
                            ctx.draw(Text("\(i + 1)").font(.system(size: 9, weight: .black)).foregroundColor(.white.opacity(0.8)),
                                     at: CGPoint(x: c.x, y: c.y + (c.y < 110 ? -20 : 20)))
                        }
                        // Emisor y lámpara
                        ctx.fill(Path(ellipseIn: CGRect(x: emitter.x - 7, y: emitter.y - 7, width: 14, height: 14)), with: .color(.red))
                        ctx.fill(Path(ellipseIn: CGRect(x: lamp.x - lampRadius, y: lamp.y - lampRadius, width: lampRadius * 2, height: lampRadius * 2)),
                                 with: .color(t.hitLamp && t.mirrorsHit.count == 6 ? .yellow : .yellow.opacity(0.3)))
                    }
                    // Marco de binoculares
                    ZStack {
                        Rectangle().fill(Color.black.opacity(0.78))
                        BinocularHoles().fill(Color.black).blendMode(.destinationOut)
                    }
                    .compositingGroup()
                    .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { p in selectNearest(p) }
            }
            HStack(spacing: 8) {
                Text("ESPEJO \(selected + 1)")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .foregroundStyle(.yellow)
                Slider(value: Binding(
                    get: { mirrorAngles[selected] },
                    set: { mirrorAngles[selected] = ($0 / 2.5).rounded() * 2.5 }
                ), in: 0...180, onEditingChanged: { editing in
                    if !editing { check() }
                })
                .tint(.green)
                Text("REBOTES \(t.mirrorsHit.count)/6")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(t.mirrorsHit.count == 6 ? .green : .white.opacity(0.8))
            }
            .frame(width: chestArenaSize.width)
        }
    }

    private func selectNearest(_ p: CGPoint) {
        var best = selected
        var bestD = CGFloat.greatestFiniteMagnitude
        for (i, c) in mirrorCenters.enumerated() {
            let d = hypot(c.x - p.x, c.y - p.y)
            if d < bestD { bestD = d; best = i }
        }
        if bestD < 50 {
            selected = best
            chestHaptic()
        }
    }

    private func check() {
        guard !isUnlocked else { return }
        let t = trace
        guard t.hitLamp && t.mirrorsHit.count == 6 else { return }
        chestHaptic(.heavy)
        solvedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onSolved() }
    }

    /// Intersección rayo–segmento del espejo; devuelve la distancia o nil
    private func intersect(origin: CGPoint, dir: CGVector, mirror i: Int, center c: CGPoint) -> CGFloat? {
        let a = mirrorAngles[i] * .pi / 180
        let s = CGVector(dx: cos(a) * mirrorHalfLength * 2, dy: sin(a) * mirrorHalfLength * 2)
        let p0 = CGPoint(x: c.x - s.dx / 2, y: c.y - s.dy / 2)
        let denom = dir.dx * s.dy - dir.dy * s.dx
        guard abs(denom) > 1e-6 else { return nil }
        let qx = p0.x - origin.x, qy = p0.y - origin.y
        let t = (qx * s.dy - qy * s.dx) / denom
        let u = (qx * dir.dy - qy * dir.dx) / denom
        guard t > 0.5, u >= 0, u <= 1 else { return nil }
        return t
    }

    private func hitCircle(origin: CGPoint, dir: CGVector, center: CGPoint, radius: CGFloat) -> CGFloat? {
        let ox = origin.x - center.x, oy = origin.y - center.y
        let b = ox * dir.dx + oy * dir.dy
        let c = ox * ox + oy * oy - radius * radius
        let disc = b * b - c
        guard disc >= 0 else { return nil }
        let t = -b - sqrt(disc)
        return t > 0.5 ? t : nil
    }
}

/// Los dos huecos de los binoculares (se recortan del velo negro)
private struct BinocularHoles: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.height * 0.62
        p.addEllipse(in: CGRect(x: rect.midX - r * 1.45, y: rect.midY - r, width: r * 2, height: r * 2))
        p.addEllipse(in: CGRect(x: rect.midX - r * 0.55, y: rect.midY - r, width: r * 2, height: r * 2))
        return p
    }
}
