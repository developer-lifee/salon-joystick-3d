import Foundation
import Metal
import MetalKit
import QuartzCore
import simd

struct RTTriangleData {
    var normalRoughness: SIMD4<Float>
    var albedoReflectivity: SIMD4<Float>
    var emissionKind: SIMD4<Float>
}

private struct RTUniforms {
    var viewport: SIMD4<Float>
    var cameraPosition: SIMD4<Float>
    var cameraRight: SIMD4<Float>
    var cameraUp: SIMD4<Float>
    var cameraForward: SIMD4<Float>
    var lightPosition: SIMD4<Float>
    var lightColor: SIMD4<Float>
    var waterSimulation: SIMD4<Float>
    var waterImpulse: SIMD4<Float>
    var toolOrigin: SIMD4<Float>
    var toolDirection: SIMD4<Float>
    var toolParameters: SIMD4<Float>
    var lightStates: SIMD4<Float>
    var secondaryCameraPosition: SIMD4<Float>
    var secondaryCameraForward: SIMD4<Float>
}

private struct RTLaserResult {
    var primaryStart: SIMD4<Float>
    var primaryEnd: SIMD4<Float>
    var reflectedEnd: SIMD4<Float>
    var bot0Start: SIMD4<Float>
    var bot0End: SIMD4<Float>
    var bot1Start: SIMD4<Float>
    var bot1End: SIMD4<Float>
    var bot2Start: SIMD4<Float>
    var bot2End: SIMD4<Float>
    var bot3Start: SIMD4<Float>
    var bot3End: SIMD4<Float>
    var bot4Start: SIMD4<Float>
    var bot4End: SIMD4<Float>
}

private struct RTMaterial {
    var color: SIMD3<Float>
    var roughness: Float
    var emission: SIMD3<Float> = .zero
    var reflectivity: Float = 0
    var kind: Float = 0
}

private struct RTRiverRock {
    let center: SIMD3<Float>
    let radii: SIMD3<Float>
    let color: SIMD3<Float>
}

private struct RTParkourBox {
    let center: SIMD3<Float>
    let size: SIMD3<Float>
    let color: SIMD3<Float>
    let emission: SIMD3<Float>
    let kind: Float
}

private let rtRiverRocks: [RTRiverRock] = [
    RTRiverRock(center: SIMD3<Float>(-7.3, 0.24, -3.4), radii: SIMD3<Float>(0.72, 0.24, 0.52), color: SIMD3<Float>(0.18, 0.20, 0.20)),
    RTRiverRock(center: SIMD3<Float>(-6.45, 0.18, -4.4), radii: SIMD3<Float>(0.50, 0.18, 0.64), color: SIMD3<Float>(0.30, 0.29, 0.27)),
    RTRiverRock(center: SIMD3<Float>(-7.75, 0.16, -2.35), radii: SIMD3<Float>(0.46, 0.16, 0.42), color: SIMD3<Float>(0.14, 0.16, 0.17)),
    RTRiverRock(center: SIMD3<Float>(-7.05, 0.20, 1.2), radii: SIMD3<Float>(0.62, 0.20, 0.46), color: SIMD3<Float>(0.35, 0.34, 0.31)),
    RTRiverRock(center: SIMD3<Float>(4.3, 0.19, -4.9), radii: SIMD3<Float>(0.68, 0.19, 0.48), color: SIMD3<Float>(0.25, 0.27, 0.27)),
    RTRiverRock(center: SIMD3<Float>(5.15, 0.15, -4.45), radii: SIMD3<Float>(0.48, 0.15, 0.58), color: SIMD3<Float>(0.19, 0.18, 0.17)),
    // 🪨 Zone 1: North-East High Rock Pillars (NE X: 10..14, Z: -10..-14)
    RTRiverRock(center: SIMD3<Float>(12.0, 1.2, -12.0), radii: SIMD3<Float>(1.5, 1.4, 1.5), color: SIMD3<Float>(0.28, 0.30, 0.32)),
    RTRiverRock(center: SIMD3<Float>(13.5, 0.9, -10.5), radii: SIMD3<Float>(1.2, 1.0, 1.2), color: SIMD3<Float>(0.22, 0.24, 0.26)),
    RTRiverRock(center: SIMD3<Float>(10.5, 1.0, -13.5), radii: SIMD3<Float>(1.3, 1.1, 1.3), color: SIMD3<Float>(0.34, 0.32, 0.30)),
    // 🏛️ Zone 2: South-West Obelisks & Rocks (SW X: -10..-14, Z: 10..14)
    RTRiverRock(center: SIMD3<Float>(-12.0, 1.4, 12.0), radii: SIMD3<Float>(1.6, 1.5, 1.6), color: SIMD3<Float>(0.16, 0.20, 0.24)),
    RTRiverRock(center: SIMD3<Float>(-13.5, 1.1, 10.2), radii: SIMD3<Float>(1.2, 1.2, 1.2), color: SIMD3<Float>(0.20, 0.22, 0.25)),
    // 🌿 Zone 3: North-West Garden Planter Boulders (NW X: -10..-14, Z: -10..-14)
    RTRiverRock(center: SIMD3<Float>(-12.0, 0.8, -12.0), radii: SIMD3<Float>(1.8, 0.9, 1.4), color: SIMD3<Float>(0.25, 0.28, 0.24)),
    RTRiverRock(center: SIMD3<Float>(-13.8, 0.7, -13.5), radii: SIMD3<Float>(1.4, 0.8, 1.6), color: SIMD3<Float>(0.30, 0.27, 0.23)),
    // 💡 Zone 4: South-East Neon Pillars & Cover (SE X: 10..14, Z: 10..14)
    RTRiverRock(center: SIMD3<Float>(12.0, 1.5, 12.0), radii: SIMD3<Float>(1.4, 1.6, 1.4), color: SIMD3<Float>(0.15, 0.30, 0.38)),
    RTRiverRock(center: SIMD3<Float>(13.8, 1.2, 13.8), radii: SIMD3<Float>(1.2, 1.3, 1.2), color: SIMD3<Float>(0.20, 0.25, 0.30)),
    // 🌈 Postes y Columnas de Cobertura Cuerpo Completo en el Gran Salón Arcoíris (Z: 23..65)
    RTRiverRock(center: SIMD3<Float>(-9.0, 1.8, 25.0), radii: SIMD3<Float>(1.05, 1.85, 1.05), color: SIMD3<Float>(0.35, 0.12, 0.14)),
    RTRiverRock(center: SIMD3<Float>( 9.0, 1.8, 25.0), radii: SIMD3<Float>(1.05, 1.85, 1.05), color: SIMD3<Float>(0.36, 0.22, 0.10)),
    RTRiverRock(center: SIMD3<Float>(-9.5, 1.8, 39.0), radii: SIMD3<Float>(1.05, 1.85, 1.05), color: SIMD3<Float>(0.34, 0.32, 0.10)),
    RTRiverRock(center: SIMD3<Float>( 9.5, 1.8, 39.0), radii: SIMD3<Float>(1.05, 1.85, 1.05), color: SIMD3<Float>(0.12, 0.35, 0.18)),
    RTRiverRock(center: SIMD3<Float>(-9.5, 1.8, 51.0), radii: SIMD3<Float>(1.05, 1.85, 1.05), color: SIMD3<Float>(0.10, 0.32, 0.36)),
    RTRiverRock(center: SIMD3<Float>( 9.5, 1.8, 51.0), radii: SIMD3<Float>(1.05, 1.85, 1.05), color: SIMD3<Float>(0.12, 0.18, 0.38)),
    RTRiverRock(center: SIMD3<Float>(-9.0, 1.8, 64.0), radii: SIMD3<Float>(1.05, 1.85, 1.05), color: SIMD3<Float>(0.28, 0.12, 0.38)),
    RTRiverRock(center: SIMD3<Float>( 9.0, 1.8, 64.0), radii: SIMD3<Float>(1.05, 1.85, 1.05), color: SIMD3<Float>(0.38, 0.12, 0.30)),
    RTRiverRock(center: SIMD3<Float>(-21.5, 1.8, 44.0), radii: SIMD3<Float>(1.15, 1.95, 1.15), color: SIMD3<Float>(0.14, 0.28, 0.34)),
    RTRiverRock(center: SIMD3<Float>( 21.5, 1.8, 44.0), radii: SIMD3<Float>(1.15, 1.95, 1.15), color: SIMD3<Float>(0.34, 0.16, 0.28))
]

// 🌈 Circuito de Parkour Multi-Altura + 4 Cabañas Arcoíris Transitables (Paredes Sólidas + Puerta Abierta + Escalones al Techo)
private let rtRainbowParkourBoxes: [RTParkourBox] = {
    var boxes: [RTParkourBox] = [
        // 1. Ruta Central de Parkour (Salto de Plataforma en Plataforma hacia la Cumbre Arcoíris a Y = 3.50m)
        RTParkourBox(center: SIMD3<Float>( 0.0, 0.35, 23.5), size: SIMD3<Float>(3.8, 0.70, 3.0), color: SIMD3<Float>(0.28, 0.06, 0.08), emission: SIMD3<Float>(4.2, 0.35, 0.18), kind: 4),
        RTParkourBox(center: SIMD3<Float>(-3.6, 0.70, 27.8), size: SIMD3<Float>(3.4, 1.40, 3.2), color: SIMD3<Float>(0.32, 0.14, 0.04), emission: SIMD3<Float>(4.5, 1.60, 0.15), kind: 4),
        RTParkourBox(center: SIMD3<Float>( 3.6, 0.70, 27.8), size: SIMD3<Float>(3.4, 1.40, 3.2), color: SIMD3<Float>(0.32, 0.28, 0.04), emission: SIMD3<Float>(4.2, 3.60, 0.20), kind: 6),
        RTParkourBox(center: SIMD3<Float>(-5.0, 1.05, 33.6), size: SIMD3<Float>(3.4, 2.10, 3.8), color: SIMD3<Float>(0.06, 0.28, 0.10), emission: SIMD3<Float>(0.35, 4.40, 0.85), kind: 6),
        RTParkourBox(center: SIMD3<Float>( 5.0, 1.05, 33.6), size: SIMD3<Float>(3.4, 2.10, 3.8), color: SIMD3<Float>(0.04, 0.28, 0.22), emission: SIMD3<Float>(0.20, 4.20, 2.60), kind: 6),
        RTParkourBox(center: SIMD3<Float>( 0.0, 1.40, 38.8), size: SIMD3<Float>(4.4, 2.80, 3.6), color: SIMD3<Float>(0.04, 0.22, 0.32), emission: SIMD3<Float>(0.25, 3.60, 4.80), kind: 7),
        // 🏆 Cumbre Central del Santuario Arcoíris (Y = 3.50m)
        RTParkourBox(center: SIMD3<Float>( 0.0, 1.75, 45.0), size: SIMD3<Float>(6.6, 3.50, 6.6), color: SIMD3<Float>(0.18, 0.10, 0.28), emission: SIMD3<Float>(3.80, 0.85, 4.80), kind: 5),
        RTParkourBox(center: SIMD3<Float>( 0.0, 1.40, 51.2), size: SIMD3<Float>(4.4, 2.80, 3.6), color: SIMD3<Float>(0.06, 0.12, 0.34), emission: SIMD3<Float>(0.55, 1.40, 4.80), kind: 7),
        RTParkourBox(center: SIMD3<Float>(-5.0, 1.05, 56.4), size: SIMD3<Float>(3.4, 2.10, 3.8), color: SIMD3<Float>(0.16, 0.06, 0.32), emission: SIMD3<Float>(2.20, 0.40, 4.60), kind: 7),
        RTParkourBox(center: SIMD3<Float>( 5.0, 1.05, 56.4), size: SIMD3<Float>(3.4, 2.10, 3.8), color: SIMD3<Float>(0.28, 0.06, 0.26), emission: SIMD3<Float>(4.40, 0.35, 3.60), kind: 5),
        RTParkourBox(center: SIMD3<Float>( 0.0, 0.70, 62.2), size: SIMD3<Float>(5.0, 1.40, 3.6), color: SIMD3<Float>(0.30, 0.08, 0.18), emission: SIMD3<Float>(4.50, 0.60, 2.20), kind: 5)
    ]

    // 2. Las 4 Cabañas Arcoíris (Refugios de Cuerpo Completo con Puerta Abierta + Techo Transitable + Escalones de Parkour)
    let cabinConfigs: [(SIMD3<Float>, Float, SIMD3<Float>, SIMD3<Float>, Float)] = [
        // (CentroXZ, DoorFacingSignX, ColorBase, ColorEmision, LightKind)
        (SIMD3<Float>(-16.5, 0, 32.0),  1.0, SIMD3<Float>(0.16, 0.05, 0.06), SIMD3<Float>(4.5, 0.8, 0.2), 4), // Cabaña Rubí-Ámbar (NW)
        (SIMD3<Float>( 16.5, 0, 32.0), -1.0, SIMD3<Float>(0.05, 0.16, 0.08), SIMD3<Float>(0.4, 4.5, 1.2), 6), // Cabaña Esmeralda (NE)
        (SIMD3<Float>(-16.5, 0, 56.0),  1.0, SIMD3<Float>(0.05, 0.14, 0.20), SIMD3<Float>(0.2, 3.4, 4.8), 7), // Cabaña Cian-Zafiro (SW)
        (SIMD3<Float>( 16.5, 0, 56.0), -1.0, SIMD3<Float>(0.18, 0.05, 0.20), SIMD3<Float>(4.2, 0.4, 4.6), 5)  // Cabaña Violeta-Magenta (SE)
    ]

    for (cPos, doorSignX, baseCol, emitCol, lKind) in cabinConfigs {
        let wallH: Float = 2.80
        let halfW: Float = 2.80
        let wallT: Float = 0.32
        // Pared Trasera (opuesta a la puerta)
        boxes.append(RTParkourBox(
            center: cPos + SIMD3<Float>(-doorSignX * halfW, wallH * 0.5, 0),
            size: SIMD3<Float>(wallT, wallH, halfW * 2.0),
            color: baseCol, emission: .zero, kind: 0
        ))
        // Pared Norte (-Z) y Pared Sur (+Z)
        boxes.append(RTParkourBox(
            center: cPos + SIMD3<Float>(0, wallH * 0.5, -halfW),
            size: SIMD3<Float>(halfW * 2.0, wallH, wallT),
            color: baseCol, emission: .zero, kind: 0
        ))
        boxes.append(RTParkourBox(
            center: cPos + SIMD3<Float>(0, wallH * 0.5,  halfW),
            size: SIMD3<Float>(halfW * 2.0, wallH, wallT),
            color: baseCol, emission: .zero, kind: 0
        ))
        // Pared Frontal con Puerta Abierta de 2.2m en el medio (2 jambas laterales de 1.7m cada una)
        boxes.append(RTParkourBox(
            center: cPos + SIMD3<Float>(doorSignX * halfW, wallH * 0.5, -1.95),
            size: SIMD3<Float>(wallT, wallH, 1.70),
            color: baseCol, emission: .zero, kind: 0
        ))
        boxes.append(RTParkourBox(
            center: cPos + SIMD3<Float>(doorSignX * halfW, wallH * 0.5,  1.95),
            size: SIMD3<Float>(wallT, wallH, 1.70),
            color: baseCol, emission: .zero, kind: 0
        ))
        // Techo Sólido Arcoíris Transitable (Y = 2.80 .. 3.04m)
        boxes.append(RTParkourBox(
            center: cPos + SIMD3<Float>(0, 2.92, 0),
            size: SIMD3<Float>(halfW * 2.12, 0.24, halfW * 2.12),
            color: baseCol * 1.4, emission: emitCol, kind: lKind
        ))
        // 3 Escalones Exteriores de Parkour para subir saltando al Techo de la Cabaña (Y = 0.75m, 1.50m, 2.25m)
        boxes.append(RTParkourBox(
            center: cPos + SIMD3<Float>(-doorSignX * 1.6, 0.375, halfW + 1.15),
            size: SIMD3<Float>(1.6, 0.75, 1.5),
            color: baseCol * 1.2, emission: emitCol * 0.65, kind: lKind
        ))
        boxes.append(RTParkourBox(
            center: cPos + SIMD3<Float>(0.0, 0.75, halfW + 1.15),
            size: SIMD3<Float>(1.6, 1.50, 1.5),
            color: baseCol * 1.3, emission: emitCol * 0.80, kind: lKind
        ))
        boxes.append(RTParkourBox(
            center: cPos + SIMD3<Float>(doorSignX * 1.6, 1.125, halfW + 1.15),
            size: SIMD3<Float>(1.6, 2.25, 1.5),
            color: baseCol * 1.4, emission: emitCol * 0.95, kind: lKind
        ))
    }

    return boxes
}()

private struct RTMeshBuilder {
    var vertices: [SIMD3<Float>] = []
    var triangles: [RTTriangleData] = []

    mutating func addTriangle(
        _ a: SIMD3<Float>,
        _ b: SIMD3<Float>,
        _ c: SIMD3<Float>,
        material: RTMaterial
    ) {
        let edgeA = b - a
        let edgeB = c - a
        let rawNormal = simd_cross(edgeA, edgeB)
        guard simd_length_squared(rawNormal) > 0.000_001 else { return }
        let normal = simd_normalize(rawNormal)
        vertices.append(contentsOf: [a, b, c])
        triangles.append(RTTriangleData(
            normalRoughness: SIMD4<Float>(normal, material.roughness),
            albedoReflectivity: SIMD4<Float>(material.color, material.reflectivity),
            emissionKind: SIMD4<Float>(material.emission, material.kind)
        ))
    }

    mutating func addQuad(
        _ a: SIMD3<Float>,
        _ b: SIMD3<Float>,
        _ c: SIMD3<Float>,
        _ d: SIMD3<Float>,
        material: RTMaterial
    ) {
        addTriangle(a, b, c, material: material)
        addTriangle(a, c, d, material: material)
    }

    mutating func addBox(center: SIMD3<Float>, size: SIMD3<Float>, material: RTMaterial, doubleSided: Bool = false) {
        let h = size * 0.5
        let p: [SIMD3<Float>] = [
            center + SIMD3<Float>(-h.x, -h.y, -h.z),
            center + SIMD3<Float>( h.x, -h.y, -h.z),
            center + SIMD3<Float>( h.x,  h.y, -h.z),
            center + SIMD3<Float>(-h.x,  h.y, -h.z),
            center + SIMD3<Float>(-h.x, -h.y,  h.z),
            center + SIMD3<Float>( h.x, -h.y,  h.z),
            center + SIMD3<Float>( h.x,  h.y,  h.z),
            center + SIMD3<Float>(-h.x,  h.y,  h.z)
        ]
        addQuad(p[4], p[5], p[6], p[7], material: material)
        addQuad(p[1], p[0], p[3], p[2], material: material)
        addQuad(p[0], p[4], p[7], p[3], material: material)
        addQuad(p[5], p[1], p[2], p[6], material: material)
        addQuad(p[3], p[7], p[6], p[2], material: material)
        addQuad(p[0], p[1], p[5], p[4], material: material)
        if doubleSided {
            addQuad(p[7], p[6], p[5], p[4], material: material)
            addQuad(p[2], p[3], p[0], p[1], material: material)
            addQuad(p[3], p[7], p[4], p[0], material: material)
            addQuad(p[6], p[2], p[1], p[5], material: material)
            addQuad(p[2], p[6], p[7], p[3], material: material)
            addQuad(p[4], p[5], p[1], p[0], material: material)
        }
    }

    /// 🔫 🔦 3D Modelado Articulado del Gadget/Arma en la mano del Slime (Blaster Láser Cuántico / Linterna Táctica)
    mutating func addHeldGadget(center: SIMD3<Float>) {
        let titaniumChassis = RTMaterial(color: SIMD3<Float>(0.84, 0.86, 0.90), roughness: 0.28, reflectivity: 0.35)
        let gunmetal = RTMaterial(color: SIMD3<Float>(0.16, 0.17, 0.20), roughness: 0.30, reflectivity: 0.45)
        let goldBezel = RTMaterial(color: SIMD3<Float>(0.95, 0.78, 0.24), roughness: 0.18, reflectivity: 0.65)
        let rubyCrystal = RTMaterial(color: SIMD3<Float>(0.98, 0.12, 0.22), roughness: 0.12, emission: SIMD3<Float>(4.8, 0.25, 0.35), reflectivity: 0.55, kind: 5.0)
        let cyanBattery = RTMaterial(color: SIMD3<Float>(0.05, 0.85, 0.98), roughness: 0.15, emission: SIMD3<Float>(0.2, 3.4, 4.8), reflectivity: 0.30, kind: 5.0)
        let laserTip = RTMaterial(color: SIMD3<Float>(1.0, 0.2, 0.25), roughness: 0.10, emission: SIMD3<Float>(5.8, 0.4, 0.5), reflectivity: 0.40, kind: 5.0)

        // 1. Empuñadura ergonómica / grip en la mano del slime
        addBox(center: center + SIMD3<Float>(0, -0.06, -0.04), size: SIMD3<Float>(0.08, 0.15, 0.09), material: gunmetal)
        // 2. Chasis superior / corredera de titanio blanco-plateado
        addBox(center: center + SIMD3<Float>(0, 0.03, 0.06), size: SIMD3<Float>(0.11, 0.12, 0.32), material: titaniumChassis)
        // 3. Cámara de Cristal de Rubí Cuántico expuesta (núcleo de energía que brilla en rojo)
        addSphere(center: center + SIMD3<Float>(0, 0.03, 0.04), radii: SIMD3<Float>(0.052, 0.052, 0.065), material: rubyCrystal, segments: 8, rings: 5)
        // 4. Cañón cilíndrico frontal cromado
        addBox(center: center + SIMD3<Float>(0, 0.04, 0.22), size: SIMD3<Float>(0.075, 0.075, 0.16), material: gunmetal)
        // 5. Boquilla / Anillo Emitter dorado y punta de láser brillante (donde nace el rayo)
        addBox(center: center + SIMD3<Float>(0, 0.04, 0.29), size: SIMD3<Float>(0.095, 0.095, 0.04), material: goldBezel)
        addSphere(center: center + SIMD3<Float>(0, 0.04, 0.31), radii: SIMD3<Float>(repeating: 0.032), material: laserTip, segments: 7, rings: 4)
        // 6. Indicador de Batería lateral Cian
        addBox(center: center + SIMD3<Float>(0.056, 0.04, 0.06), size: SIMD3<Float>(0.012, 0.035, 0.12), material: cyanBattery)
        addBox(center: center + SIMD3<Float>(-0.056, 0.04, 0.06), size: SIMD3<Float>(0.012, 0.035, 0.12), material: cyanBattery)
    }

    mutating func addSphere(
        center: SIMD3<Float>,
        radii: SIMD3<Float>,
        material: RTMaterial,
        segments: Int = 10,
        rings: Int = 6
    ) {
        func point(latitude: Float, longitude: Float) -> SIMD3<Float> {
            let latitudeCosine = cos(latitude)
            return center + SIMD3<Float>(
                latitudeCosine * cos(longitude) * radii.x,
                sin(latitude) * radii.y,
                latitudeCosine * sin(longitude) * radii.z
            )
        }

        let bottom = center + SIMD3<Float>(0, -radii.y, 0)
        let top = center + SIMD3<Float>(0, radii.y, 0)
        var latitudeRings: [[SIMD3<Float>]] = []
        for ring in 1..<rings {
            let latitude = -.pi / 2 + .pi * Float(ring) / Float(rings)
            latitudeRings.append((0..<segments).map { segment in
                point(latitude: latitude, longitude: 2 * .pi * Float(segment) / Float(segments))
            })
        }

        guard let firstRing = latitudeRings.first, let lastRing = latitudeRings.last else { return }
        for segment in 0..<segments {
            let next = (segment + 1) % segments
            addTriangle(bottom, firstRing[next], firstRing[segment], material: material)
            addTriangle(top, lastRing[segment], lastRing[next], material: material)
        }

        for ring in 0..<(latitudeRings.count - 1) {
            for segment in 0..<segments {
                let next = (segment + 1) % segments
                addQuad(
                    latitudeRings[ring][segment],
                    latitudeRings[ring][next],
                    latitudeRings[ring + 1][next],
                    latitudeRings[ring + 1][segment],
                    material: material
                )
            }
        }
    }

    mutating func addRiverRock(
        center: SIMD3<Float>,
        radii: SIMD3<Float>,
        seed: Float,
        material: RTMaterial,
        segments: Int = 18,
        rings: Int = 10
    ) {
        func point(ring: Int, segment: Int) -> SIMD3<Float> {
            let latitude = -.pi / 2 + .pi * Float(ring) / Float(rings)
            let longitude = 2 * .pi * Float(segment) / Float(segments)
            let latCos = cos(latitude)
            let latSin = sin(latitude)
            let lonCos = cos(longitude)
            let lonSin = sin(longitude)

            // Vector normal esférico base
            let n = SIMD3<Float>(latCos * lonCos, latSin, latCos * lonSin)

            // 1. Facetas cristalinas / fracturas planas (Voronoi cleavage planes)
            let plane1 = abs(n.x * 0.707 + n.z * 0.707)
            let plane2 = abs(n.x * -0.707 + n.z * 0.707)
            let plane3 = abs(n.x * 0.894 + n.y * 0.447)
            let facetPlateau = max(plane1, max(plane2, plane3))

            // 2. Ruido orgánico asimétrico de crag y hendiduras
            let crag1 = sin(longitude * 3.0 + seed * 2.1) * 0.16
            let crag2 = cos(longitude * 5.0 - latitude * 3.0 + seed * 1.3) * 0.10
            let crag3 = sin(latitude * 4.0 + longitude * 2.0 + seed * 0.7) * 0.08

            // 3. Estratos sedimentarios escalonados
            let strata = sin(latitude * 8.0 + seed * 1.5) * 0.06

            // Factor de desplazamiento geológico modulado por latCos
            // CRÍTICO: En los polos (latitude = +/- pi/2), latCos == 0, por lo que todo el ruido de longitud
            // se desvanece a 0. Esto garantiza que todos los segmentos converjan al MISMO punto exacto
            // en la cumbre y en la base, sellando la roca 100% estanca sin fisuras ni huecos por donde ver el interior.
            let poleBlend = max(0.0, latCos)
            let geoDisp = 1.0 + (crag1 + crag2 + crag3 + strata - (facetPlateau * 0.12)) * poleBlend

            // 4. Base geológica plana firmemente anclada al suelo (Y <= 0.0)
            var yCoord = center.y + latSin * radii.y * geoDisp
            if latitude < -0.15 {
                let t = max(0.0, min(1.0, (-latitude - 0.15) / 1.1))
                let groundContactY: Float = -0.04
                yCoord = yCoord * (1.0 - t) + min(yCoord, groundContactY) * t
            }

            return SIMD3<Float>(
                center.x + latCos * lonCos * radii.x * geoDisp,
                yCoord,
                center.z + latCos * lonSin * radii.z * geoDisp
            )
        }

        for ring in 0..<rings {
            for segment in 0..<segments {
                let nextSegment = (segment + 1) % segments
                addQuad(
                    point(ring: ring, segment: segment),
                    point(ring: ring + 1, segment: segment),
                    point(ring: ring + 1, segment: nextSegment),
                    point(ring: ring, segment: nextSegment),
                    material: material
                )
            }
        }
    }

    mutating func addTorus(
        center: SIMD3<Float>,
        majorRadius: Float,
        minorRadius: Float,
        material: RTMaterial,
        majorSegments: Int = 18,
        minorSegments: Int = 8
    ) {
        func point(_ major: Int, _ minor: Int) -> SIMD3<Float> {
            let a = 2 * Float.pi * Float(major) / Float(majorSegments)
            let b = 2 * Float.pi * Float(minor) / Float(minorSegments)
            let radial = majorRadius + minorRadius * cos(b)
            return center + SIMD3<Float>(radial * cos(a), minorRadius * sin(b), radial * sin(a))
        }

        for major in 0..<majorSegments {
            for minor in 0..<minorSegments {
                let nextMajor = (major + 1) % majorSegments
                let nextMinor = (minor + 1) % minorSegments
                addQuad(
                    point(major, minor),
                    point(nextMajor, minor),
                    point(nextMajor, nextMinor),
                    point(major, nextMinor),
                    material: material
                )
            }
        }
    }

    mutating func addPuddle(
        center: SIMD2<Float>,
        scale: SIMD2<Float>,
        rotation: Float,
        material: RTMaterial
    ) {
        let cosine = cos(rotation)
        let sine = sin(rotation)
        let pointCount = 20
        let points = (0..<pointCount).map { index -> SIMD3<Float> in
            let angle = 2 * Float.pi * Float(index) / Float(pointCount)
            let irregularity = 1
                + sin(Float(index) * 2.17 + center.x * 0.31) * 0.13
                + cos(Float(index) * 1.41 + center.y * 0.27) * 0.07
            let point = SIMD2<Float>(cos(angle), sin(angle)) * irregularity
            let scaled = point * scale
            let rotated = SIMD2<Float>(
                scaled.x * cosine - scaled.y * sine,
                scaled.x * sine + scaled.y * cosine
            ) + center
            return SIMD3<Float>(rotated.x, 0.028, rotated.y)
        }
        let worldCenter = SIMD3<Float>(center.x, 0.028, center.y)
        for index in points.indices {
            addTriangle(worldCenter, points[index], points[(index + 1) % points.count], material: material)
        }
    }

    mutating func addFlatSegment(
        from: SIMD2<Float>,
        to: SIMD2<Float>,
        z: Float,
        thickness: Float,
        material: RTMaterial
    ) {
        let direction = to - from
        guard simd_length_squared(direction) > 0.0001 else { return }
        let normalized = simd_normalize(direction)
        let perpendicular = SIMD2<Float>(-normalized.y, normalized.x) * (thickness * 0.5)
        let a = from - perpendicular
        let b = to - perpendicular
        let c = to + perpendicular
        let d = from + perpendicular
        addQuad(
            SIMD3<Float>(a.x, a.y, z),
            SIMD3<Float>(b.x, b.y, z),
            SIMD3<Float>(c.x, c.y, z),
            SIMD3<Float>(d.x, d.y, z),
            material: material
        )
    }

    mutating func addNeonPoolSign(origin: SIMD2<Float>, z: Float) {
        typealias Segment = (SIMD2<Float>, SIMD2<Float>)
        let top: Segment = (SIMD2<Float>(0, 0.9), SIMD2<Float>(0.5, 0.9))
        let middle: Segment = (SIMD2<Float>(0, 0.45), SIMD2<Float>(0.5, 0.45))
        let bottom: Segment = (SIMD2<Float>(0, 0), SIMD2<Float>(0.5, 0))
        let left: Segment = (SIMD2<Float>(0, 0), SIMD2<Float>(0, 0.9))
        let upperLeft: Segment = (SIMD2<Float>(0, 0.45), SIMD2<Float>(0, 0.9))
        let upperRight: Segment = (SIMD2<Float>(0.5, 0.45), SIMD2<Float>(0.5, 0.9))
        let lowerRight: Segment = (SIMD2<Float>(0.5, 0), SIMD2<Float>(0.5, 0.45))
        let right: Segment = (SIMD2<Float>(0.5, 0), SIMD2<Float>(0.5, 0.9))
        let center: Segment = (SIMD2<Float>(0.25, 0), SIMD2<Float>(0.25, 0.9))
        let diagonal: Segment = (SIMD2<Float>(0, 0.9), SIMD2<Float>(0.5, 0))
        let risingLeft: Segment = (SIMD2<Float>(0, 0), SIMD2<Float>(0.25, 0.9))
        let fallingRight: Segment = (SIMD2<Float>(0.25, 0.9), SIMD2<Float>(0.5, 0))

        let glyphs: [[Segment]] = [
            [left, top, middle, upperRight],
            [top, center, bottom],
            [top, upperLeft, middle, lowerRight, bottom],
            [top, left, bottom],
            [top, center, bottom],
            [left, right, diagonal],
            [risingLeft, fallingRight, middle]
        ]
        let halo = RTMaterial(
            color: SIMD3<Float>(0.18, 0.002, 0.002),
            roughness: 0.2,
            emission: SIMD3<Float>(0.75, 0.008, 0.004),
            kind: 6
        )
        let core = RTMaterial(
            color: SIMD3<Float>(1.0, 0.015, 0.008),
            roughness: 0.08,
            emission: SIMD3<Float>(7.0, 0.035, 0.012),
            kind: 6
        )

        for (glyphIndex, glyph) in glyphs.enumerated() {
            let offset = origin + SIMD2<Float>(Float(glyphIndex) * 0.72, 0)
            for segment in glyph {
                addFlatSegment(
                    from: segment.0 + offset,
                    to: segment.1 + offset,
                    z: z - 0.015,
                    thickness: 0.12,
                    material: halo
                )
                addFlatSegment(
                    from: segment.0 + offset,
                    to: segment.1 + offset,
                    z: z,
                    thickness: 0.045,
                    material: core
                )
            }
        }
    }

    mutating func addNeonSheeritSign(origin: SIMD2<Float>, z: Float) {
        typealias Segment = (SIMD2<Float>, SIMD2<Float>)
        let top: Segment = (SIMD2<Float>(0, 0.9), SIMD2<Float>(0.5, 0.9))
        let middle: Segment = (SIMD2<Float>(0, 0.45), SIMD2<Float>(0.5, 0.45))
        let bottom: Segment = (SIMD2<Float>(0, 0), SIMD2<Float>(0.5, 0))
        let left: Segment = (SIMD2<Float>(0, 0), SIMD2<Float>(0, 0.9))
        let right: Segment = (SIMD2<Float>(0.5, 0), SIMD2<Float>(0.5, 0.9))
        let upperLeft: Segment = (SIMD2<Float>(0, 0.45), SIMD2<Float>(0, 0.9))
        let upperRight: Segment = (SIMD2<Float>(0.5, 0.45), SIMD2<Float>(0.5, 0.9))
        let lowerRight: Segment = (SIMD2<Float>(0.5, 0), SIMD2<Float>(0.5, 0.45))
        let center: Segment = (SIMD2<Float>(0.25, 0), SIMD2<Float>(0.25, 0.9))
        let diagonal: Segment = (SIMD2<Float>(0.22, 0.45), SIMD2<Float>(0.5, 0))

        let glyphs: [[Segment]] = [
            [top, upperLeft, middle, lowerRight, bottom],
            [left, right, middle],
            [left, top, middle, bottom],
            [left, top, middle, bottom],
            [left, top, upperRight, middle, diagonal],
            [top, center, bottom],
            [top, center]
        ]

        let totalSignWidth = Float(glyphs.count - 1) * 0.72 + 0.50
        let signCenter = origin + SIMD2<Float>(totalSignWidth * 0.5, 0.45)

        // 1. Placa de Montaje Arquitectónica de Titanio Oscuro (da contraste, presencia y evita que el letrero se pierda en el muro vacío)
        let mountBackplate = RTMaterial(
            color: SIMD3<Float>(0.045, 0.055, 0.08),
            roughness: 0.35,
            reflectivity: 0.16,
            kind: 0.0
        )
        let mountBorder = RTMaterial(
            color: SIMD3<Float>(0.02, 0.45, 0.95),
            roughness: 0.15,
            emission: SIMD3<Float>(0.05, 0.45, 2.2),
            reflectivity: 0.45,
            kind: 7
        )
        // Panel trasero biselado montado sobre el muro (frente al muro Z = 17.60)
        addBox(center: SIMD3<Float>(signCenter.x, signCenter.y, z + 0.05), size: SIMD3<Float>(totalSignWidth + 0.90, 1.38, 0.03), material: mountBackplate)
        // Marco perimetral neón cian que encuadra el letrero
        addBox(center: SIMD3<Float>(signCenter.x, signCenter.y + 0.67, z + 0.04), size: SIMD3<Float>(totalSignWidth + 0.92, 0.035, 0.035), material: mountBorder)
        addBox(center: SIMD3<Float>(signCenter.x, signCenter.y - 0.67, z + 0.04), size: SIMD3<Float>(totalSignWidth + 0.92, 0.035, 0.035), material: mountBorder)
        addBox(center: SIMD3<Float>(signCenter.x - (totalSignWidth + 0.90) * 0.5, signCenter.y, z + 0.04), size: SIMD3<Float>(0.035, 1.38, 0.035), material: mountBorder)
        addBox(center: SIMD3<Float>(signCenter.x + (totalSignWidth + 0.90) * 0.5, signCenter.y, z + 0.04), size: SIMD3<Float>(0.035, 1.38, 0.035), material: mountBorder)

        // 2. Tubos de Neón con emisión vibrante y visibilidad nítida en espejos a 35m
        let halo = RTMaterial(
            color: SIMD3<Float>(0.005, 0.04, 0.32),
            roughness: 0.18,
            emission: SIMD3<Float>(0.015, 0.42, 3.2),
            kind: 7
        )
        let core = RTMaterial(
            color: SIMD3<Float>(0.02, 0.35, 1.0),
            roughness: 0.05,
            emission: SIMD3<Float>(0.08, 2.2, 14.0),
            kind: 7
        )

        for (glyphIndex, glyph) in glyphs.enumerated() {
            let offset = origin + SIMD2<Float>(Float(glyphIndex) * 0.72, 0)
            for segment in glyph {
                addFlatSegment(
                    from: segment.0 + offset,
                    to: segment.1 + offset,
                    z: z + 0.018,
                    thickness: 0.15,
                    material: halo
                )
                addFlatSegment(
                    from: segment.0 + offset,
                    to: segment.1 + offset,
                    z: z,
                    thickness: 0.065,
                    material: core
                )
            }
        }
    }

    enum CharacterPose {
        case stand
        case walk
        case cover
        case swim
        case sit
        case climb
    }

    /// 👹 Fase 2: Construye la cabeza, orejas puntiagudas, gafas Cat-Eye en V, boca con 4 colmillos y lengua del Diablillo de Gelatina
    mutating func addJellyGremlinHeadAndTorso(
        bellyCenter: SIMD3<Float>,
        headCenter: SIMD3<Float>,
        jellyMat: RTMaterial
    ) {
        let innerEarMat = RTMaterial(color: SIMD3<Float>(0.10, 0.48, 0.08), roughness: 0.25, reflectivity: 0.15, kind: 9.0)
        let glassesFrame = RTMaterial(color: SIMD3<Float>(0.04, 0.16, 0.06), roughness: 0.10, reflectivity: 0.65)
        let glassesLens = RTMaterial(color: SIMD3<Float>(0.05, 0.52, 0.22), roughness: 0.02, emission: SIMD3<Float>(0.02, 0.22, 0.08), reflectivity: 0.94, kind: 1.0)
        let mouthCavity = RTMaterial(color: SIMD3<Float>(0.03, 0.11, 0.03), roughness: 0.85, reflectivity: 0.04)
        let tongueMat = RTMaterial(color: SIMD3<Float>(0.18, 0.68, 0.26), roughness: 0.22, reflectivity: 0.25)
        let fangMat = RTMaterial(color: SIMD3<Float>(0.96, 0.95, 0.86), roughness: 0.12, emission: SIMD3<Float>(0.12, 0.12, 0.08), reflectivity: 0.35)

        // 1. Cuerpo aperado (Pancita ancha abajo + torso/cabeza rechoncha arriba)
        addSphere(center: bellyCenter, radii: SIMD3<Float>(0.40, 0.44, 0.35), material: jellyMat, segments: 16, rings: 10)
        addSphere(center: headCenter, radii: SIMD3<Float>(0.37, 0.38, 0.33), material: jellyMat, segments: 16, rings: 10)

        // 2. Orejas largas puntiagudas de Diablillo / Goblin (curvadas hacia arriba y afuera)
        for side: Float in [-1.0, 1.0] {
            addSphere(center: headCenter + SIMD3<Float>(side * 0.28, 0.24, -0.02), radii: SIMD3<Float>(0.11, 0.16, 0.08), material: jellyMat, segments: 10, rings: 6)
            addSphere(center: headCenter + SIMD3<Float>(side * 0.36, 0.38, -0.03), radii: SIMD3<Float>(0.085, 0.15, 0.065), material: jellyMat, segments: 10, rings: 6)
            addSphere(center: headCenter + SIMD3<Float>(side * 0.43, 0.52, -0.04), radii: SIMD3<Float>(0.055, 0.12, 0.045), material: jellyMat, segments: 8, rings: 5)
            addSphere(center: headCenter + SIMD3<Float>(side * 0.48, 0.63, -0.05), radii: SIMD3<Float>(0.030, 0.07, 0.030), material: jellyMat, segments: 8, rings: 4)
            // Cavidad interna de la oreja
            addSphere(center: headCenter + SIMD3<Float>(side * 0.34, 0.36, 0.025), radii: SIMD3<Float>(0.055, 0.12, 0.035), material: innerEarMat, segments: 8, rings: 5)
        }

        // 3. Cejas fruncidas sobre las gafas
        addSphere(center: headCenter + SIMD3<Float>(-0.11, 0.14, 0.28), radii: SIMD3<Float>(0.11, 0.055, 0.07), material: jellyMat, segments: 8, rings: 5)
        addSphere(center: headCenter + SIMD3<Float>( 0.11, 0.14, 0.28), radii: SIMD3<Float>(0.11, 0.055, 0.07), material: jellyMat, segments: 8, rings: 5)

        // 4. Gafas Cat-Eye en "V" (Montura oscura puntiaguda + Lentes Esmeralda Reflectivos)
        // Puente central de las gafas
        addBox(center: headCenter + SIMD3<Float>(0, 0.04, 0.34), size: SIMD3<Float>(0.10, 0.045, 0.05), material: glassesFrame)
        for side: Float in [-1.0, 1.0] {
            // Escalones en V hacia las puntas exteriores Cat-Eye
            addBox(center: headCenter + SIMD3<Float>(side * 0.12, 0.06, 0.33), size: SIMD3<Float>(0.14, 0.09, 0.05), material: glassesFrame)
            addBox(center: headCenter + SIMD3<Float>(side * 0.22, 0.10, 0.30), size: SIMD3<Float>(0.14, 0.09, 0.05), material: glassesFrame)
            addBox(center: headCenter + SIMD3<Float>(side * 0.31, 0.15, 0.26), size: SIMD3<Float>(0.11, 0.07, 0.045), material: glassesFrame)
            addBox(center: headCenter + SIMD3<Float>(side * 0.37, 0.19, 0.22), size: SIMD3<Float>(0.07, 0.045, 0.04), material: glassesFrame)
            // Lentes verdes brillantes reflectivos
            addSphere(center: headCenter + SIMD3<Float>(side * 0.15, 0.07, 0.345), radii: SIMD3<Float>(0.10, 0.042, 0.025), material: glassesLens, segments: 8, rings: 5)
            addSphere(center: headCenter + SIMD3<Float>(side * 0.25, 0.11, 0.315), radii: SIMD3<Float>(0.08, 0.036, 0.025), material: glassesLens, segments: 8, rings: 5)
        }

        // 5. Boca ancha abierta con lengua verde y 4 colmillos blancos afilados
        addSphere(center: headCenter + SIMD3<Float>(0, -0.13, 0.26), radii: SIMD3<Float>(0.23, 0.12, 0.10), material: mouthCavity, segments: 12, rings: 6)
        // Lengua
        addSphere(center: headCenter + SIMD3<Float>(0, -0.17, 0.28), radii: SIMD3<Float>(0.11, 0.042, 0.09), material: tongueMat, segments: 8, rings: 5)
        // Labio inferior
        addSphere(center: headCenter + SIMD3<Float>(0, -0.24, 0.28), radii: SIMD3<Float>(0.20, 0.045, 0.08), material: jellyMat, segments: 10, rings: 5)
        // 2 Colmillos superiores + 2 Colmillos inferiores
        for side: Float in [-1.0, 1.0] {
            addSphere(center: headCenter + SIMD3<Float>(side * 0.12, -0.06, 0.32), radii: SIMD3<Float>(0.026, 0.052, 0.026), material: fangMat, segments: 6, rings: 4)
            addSphere(center: headCenter + SIMD3<Float>(side * 0.10, -0.19, 0.32), radii: SIMD3<Float>(0.024, 0.046, 0.024), material: fangMat, segments: 6, rings: 4)
        }
    }

    mutating func addCharacter(
        origin: SIMD3<Float>,
        color: SIMD3<Float>,
        eyes: Bool = true,
        holdsTool: Bool = false,
        pose: CharacterPose = .stand,
        isJellyGremlin: Bool = false
    ) {
        let suit = isJellyGremlin
            ? RTMaterial(color: SIMD3<Float>(0.24, 0.84, 0.14), roughness: 0.12, reflectivity: 0.24, kind: 9.0)
            : RTMaterial(color: color, roughness: 0.68, reflectivity: 0.04)
        let armor = isJellyGremlin
            ? RTMaterial(color: SIMD3<Float>(0.18, 0.72, 0.11), roughness: 0.14, reflectivity: 0.22, kind: 9.0)
            : RTMaterial(color: SIMD3<Float>(0.08, 0.10, 0.14), roughness: 0.75, reflectivity: 0.04)
        let visor = RTMaterial(color: SIMD3<Float>(0.05, 0.85, 0.98), roughness: 0.25, emission: SIMD3<Float>(0.2, 0.65, 0.95), reflectivity: 0.08, kind: 0.0)
        let coreEmissive = RTMaterial(color: SIMD3<Float>(1.0, 0.2, 0.4), roughness: 0.35, emission: SIMD3<Float>(3.5, 0.8, 1.2), reflectivity: 0.04, kind: 5.0)
        let dark = RTMaterial(color: SIMD3<Float>(repeating: 0.012), roughness: 0.92)
        let scubaTankMat = RTMaterial(color: SIMD3<Float>(0.22, 0.24, 0.28), roughness: 0.65, reflectivity: 0.05)
        let flipperMat = isJellyGremlin
            ? RTMaterial(color: SIMD3<Float>(0.20, 0.76, 0.12), roughness: 0.14, reflectivity: 0.22, kind: 9.0)
            : RTMaterial(color: SIMD3<Float>(0.95, 0.45, 0.05), roughness: 0.55, reflectivity: 0.04)
        let clawMat = RTMaterial(color: SIMD3<Float>(0.92, 0.94, 0.80), roughness: 0.45, reflectivity: 0.06)
        let toolMat = RTMaterial(color: SIMD3<Float>(0.055, 0.060, 0.065), roughness: 0.55, reflectivity: 0.04)

        switch pose {
        case .cover:
            // 🛡️ GTA Tactical Crouch Cover (Centro de gravedad bajo, rodilla hincada a tierra, rodilla frontal flexionada, codos en guardia)
            let bootMat = isJellyGremlin ? clawMat : armor

            if isJellyGremlin {
                addJellyGremlinHeadAndTorso(
                    bellyCenter: origin + SIMD3<Float>(0, 0.44, 0.04),
                    headCenter: origin + SIMD3<Float>(0, 0.88, 0.10),
                    jellyMat: suit
                )
            } else {
                let torsoO = origin + SIMD3<Float>(0, 0.48, 0.04)
                addSphere(center: torsoO, radii: SIMD3<Float>(0.32, 0.42, 0.26), material: suit)
                addBox(center: origin + SIMD3<Float>(0, 0.52, 0.16), size: SIMD3<Float>(0.42, 0.36, 0.12), material: armor)
                addSphere(center: origin + SIMD3<Float>(0, 0.54, 0.22), radii: SIMD3<Float>(repeating: 0.08), material: coreEmissive)
                addBox(center: origin + SIMD3<Float>(0, 0.50, -0.16), size: SIMD3<Float>(0.28, 0.46, 0.18), material: scubaTankMat)
                addSphere(center: origin + SIMD3<Float>(0, 0.74, -0.16), radii: SIMD3<Float>(repeating: 0.08), material: armor)
                addSphere(center: origin + SIMD3<Float>(0, 0.98, 0.10), radii: SIMD3<Float>(repeating: 0.30), material: suit)
                addBox(center: origin + SIMD3<Float>(0, 1.00, 0.28), size: SIMD3<Float>(0.36, 0.17, 0.14), material: visor)
                if eyes {
                    addSphere(center: origin + SIMD3<Float>(-0.10, 1.02, 0.35), radii: SIMD3<Float>(repeating: 0.038), material: dark, segments: 7, rings: 4)
                    addSphere(center: origin + SIMD3<Float>( 0.10, 1.02, 0.35), radii: SIMD3<Float>(repeating: 0.038), material: dark, segments: 7, rings: 4)
                }
            }

            // 🦾 Codos en guardia táctica cubriendo pecho/cabeza apoyados hacia la roca
            addSphere(center: origin + SIMD3<Float>(-0.36, 0.68, 0.08), radii: SIMD3<Float>(repeating: 0.10), material: armor)
            addSphere(center: origin + SIMD3<Float>( 0.36, 0.68, 0.08), radii: SIMD3<Float>(repeating: 0.10), material: armor)
            addBox(center: origin + SIMD3<Float>(-0.32, 0.56, 0.16), size: SIMD3<Float>(0.13, 0.24, 0.14), material: suit)
            addBox(center: origin + SIMD3<Float>( 0.32, 0.56, 0.16), size: SIMD3<Float>(0.13, 0.24, 0.14), material: suit)
            // Codos articulados flexionados a 90º
            addSphere(center: origin + SIMD3<Float>(-0.28, 0.44, 0.22), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addSphere(center: origin + SIMD3<Float>( 0.28, 0.44, 0.22), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            // Antebrazos en guardia
            addBox(center: origin + SIMD3<Float>(-0.16, 0.46, 0.28), size: SIMD3<Float>(0.24, 0.12, 0.14), material: suit)
            addBox(center: origin + SIMD3<Float>( 0.16, 0.46, 0.28), size: SIMD3<Float>(0.24, 0.12, 0.14), material: suit)
            if holdsTool {
                addHeldGadget(center: origin + SIMD3<Float>(0.24, 0.46, 0.36))
            }

            // 🦵 Articulación de piernas y rodillas (Fiel a SalonStudio 3D)
            // Pelvis central
            addSphere(center: origin + SIMD3<Float>(0, 0.42, 0.02), radii: SIMD3<Float>(0.18, 0.12, 0.16), material: armor)
            addSphere(center: origin + SIMD3<Float>(-0.14, 0.42, 0.04), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addSphere(center: origin + SIMD3<Float>( 0.14, 0.42, -0.04), radii: SIMD3<Float>(repeating: 0.095), material: armor)

            // Pierna Izq (Rodilla alzada adelante hacia la roca)
            // Muslo inclinado hacia adelante
            addBox(center: origin + SIMD3<Float>(-0.14, 0.34, 0.14), size: SIMD3<Float>(0.14, 0.20, 0.16), material: suit)
            // Rótula / Rodilla Izquierda (Marcador verde visible)
            addSphere(center: origin + SIMD3<Float>(-0.14, 0.26, 0.24), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            // Canilla vertical al piso
            addBox(center: origin + SIMD3<Float>(-0.14, 0.14, 0.24), size: SIMD3<Float>(0.13, 0.22, 0.14), material: suit)
            // Bota táctica plana en el suelo (y = 0.03)
            addBox(center: origin + SIMD3<Float>(-0.14, 0.03, 0.30), size: SIMD3<Float>(0.15, 0.06, 0.24), material: bootMat)

            // Pierna Der (Rodilla hincada tocando el suelo a ras de piso)
            // Muslo inclinado hacia atrás y abajo
            addBox(center: origin + SIMD3<Float>(0.14, 0.25, -0.10), size: SIMD3<Float>(0.14, 0.24, 0.16), material: suit)
            // Rótula / Rodilla Derecha apoyada firmemente en el suelo (y = 0.08)
            addSphere(center: origin + SIMD3<Float>(0.14, 0.08, -0.18), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            // Canilla horizontal a lo largo del suelo
            addBox(center: origin + SIMD3<Float>(0.14, 0.06, -0.05), size: SIMD3<Float>(0.13, 0.10, 0.22), material: suit)
            // Bota táctica derecha apoyada en tierra
            addBox(center: origin + SIMD3<Float>(0.14, 0.03, 0.08), size: SIMD3<Float>(0.15, 0.06, 0.22), material: bootMat)

        case .swim:
            // 🏊 Mario Buceo: Brazos arqueados en braza y patada alterna de aletas
            if isJellyGremlin {
                addJellyGremlinHeadAndTorso(
                    bellyCenter: origin + SIMD3<Float>(0, 0.78, 0),
                    headCenter: origin + SIMD3<Float>(0, 1.32, 0.04),
                    jellyMat: suit
                )
            } else {
                let torsoO = origin + SIMD3<Float>(0, 0.86, 0)
                addSphere(center: torsoO, radii: SIMD3<Float>(0.34, 0.50, 0.27), material: suit)
                addBox(center: origin + SIMD3<Float>(0, 0.92, 0.16), size: SIMD3<Float>(0.44, 0.42, 0.12), material: armor)
                addSphere(center: origin + SIMD3<Float>(0, 0.95, 0.23), radii: SIMD3<Float>(repeating: 0.08), material: coreEmissive)
                addBox(center: origin + SIMD3<Float>(0, 0.92, -0.22), size: SIMD3<Float>(0.28, 0.55, 0.18), material: scubaTankMat)
                addSphere(center: origin + SIMD3<Float>(0, 1.22, -0.22), radii: SIMD3<Float>(repeating: 0.09), material: armor)
                addSphere(center: origin + SIMD3<Float>(0, 1.55, 0), radii: SIMD3<Float>(repeating: 0.32), material: suit)
                addBox(center: origin + SIMD3<Float>(0, 1.58, 0.22), size: SIMD3<Float>(0.38, 0.18, 0.14), material: visor)
                if eyes {
                    addSphere(center: origin + SIMD3<Float>(-0.11, 1.60, 0.29), radii: SIMD3<Float>(repeating: 0.04), material: dark, segments: 7, rings: 4)
                    addSphere(center: origin + SIMD3<Float>( 0.11, 1.60, 0.29), radii: SIMD3<Float>(repeating: 0.04), material: dark, segments: 7, rings: 4)
                }
            }

            // Brazos arqueados para impulso en agua
            addSphere(center: origin + SIMD3<Float>(-0.46, 1.15, 0), radii: SIMD3<Float>(repeating: 0.11), material: armor)
            addSphere(center: origin + SIMD3<Float>( 0.46, 1.15, 0), radii: SIMD3<Float>(repeating: 0.11), material: armor)
            addBox(center: origin + SIMD3<Float>(-0.48, 0.98, 0.08), size: SIMD3<Float>(0.14, 0.28, 0.15), material: suit)
            addBox(center: origin + SIMD3<Float>( 0.48, 0.98, 0.08), size: SIMD3<Float>(0.14, 0.28, 0.15), material: suit)
            // Codos arqueados
            addSphere(center: origin + SIMD3<Float>(-0.50, 0.82, 0.14), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addSphere(center: origin + SIMD3<Float>( 0.50, 0.82, 0.14), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addBox(center: origin + SIMD3<Float>(-0.42, 0.68, 0.22), size: SIMD3<Float>(0.13, 0.26, 0.16), material: suit)
            addBox(center: origin + SIMD3<Float>( 0.42, 0.68, 0.22), size: SIMD3<Float>(0.13, 0.26, 0.16), material: suit)
            if holdsTool {
                addHeldGadget(center: origin + SIMD3<Float>(0.47, 0.68, 0.32))
            }

            // Piernas en patada de aletas (Flutter Kick)
            addSphere(center: origin + SIMD3<Float>(-0.16, 0.52, 0), radii: SIMD3<Float>(repeating: 0.10), material: armor)
            addSphere(center: origin + SIMD3<Float>( 0.16, 0.52, 0), radii: SIMD3<Float>(repeating: 0.10), material: armor)
            // Pierna Izq (arriba batiendo)
            addBox(center: origin + SIMD3<Float>(-0.16, 0.40, -0.08), size: SIMD3<Float>(0.15, 0.26, 0.16), material: suit)
            addSphere(center: origin + SIMD3<Float>(-0.16, 0.26, -0.14), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addBox(center: origin + SIMD3<Float>(-0.16, 0.14, -0.20), size: SIMD3<Float>(0.14, 0.24, 0.15), material: suit)
            addBox(center: origin + SIMD3<Float>(-0.16, 0.04, -0.34), size: SIMD3<Float>(0.17, 0.05, 0.38), material: flipperMat)
            // Pierna Der (abajo)
            addBox(center: origin + SIMD3<Float>( 0.16, 0.38, 0.08), size: SIMD3<Float>(0.15, 0.26, 0.16), material: suit)
            addSphere(center: origin + SIMD3<Float>( 0.16, 0.22, 0.12), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addBox(center: origin + SIMD3<Float>( 0.16, 0.10, 0.10), size: SIMD3<Float>(0.14, 0.24, 0.15), material: suit)
            addBox(center: origin + SIMD3<Float>( 0.16, 0.02, 0.24), size: SIMD3<Float>(0.17, 0.05, 0.38), material: flipperMat)

        case .sit:
            // 🛷 Tobogán: Sentado con piernas extendidas al frente y rodillas a 30º
            if isJellyGremlin {
                addJellyGremlinHeadAndTorso(
                    bellyCenter: origin + SIMD3<Float>(0, 0.54, -0.10),
                    headCenter: origin + SIMD3<Float>(0, 1.06, -0.04),
                    jellyMat: suit
                )
            } else {
                let torsoO = origin + SIMD3<Float>(0, 0.58, -0.10)
                addSphere(center: torsoO, radii: SIMD3<Float>(0.34, 0.48, 0.27), material: suit)
                addBox(center: origin + SIMD3<Float>(0, 0.64, 0.06), size: SIMD3<Float>(0.44, 0.40, 0.12), material: armor)
                addSphere(center: origin + SIMD3<Float>(0, 0.67, 0.13), radii: SIMD3<Float>(repeating: 0.08), material: coreEmissive)
                addBox(center: origin + SIMD3<Float>(0, 0.64, -0.32), size: SIMD3<Float>(0.28, 0.52, 0.18), material: scubaTankMat)
                addSphere(center: origin + SIMD3<Float>(0, 0.92, -0.32), radii: SIMD3<Float>(repeating: 0.09), material: armor)
                addSphere(center: origin + SIMD3<Float>(0, 1.25, -0.06), radii: SIMD3<Float>(repeating: 0.32), material: suit)
                addBox(center: origin + SIMD3<Float>(0, 1.28, 0.16), size: SIMD3<Float>(0.38, 0.18, 0.14), material: visor)
                if eyes {
                    addSphere(center: origin + SIMD3<Float>(-0.11, 1.30, 0.23), radii: SIMD3<Float>(repeating: 0.04), material: dark, segments: 7, rings: 4)
                    addSphere(center: origin + SIMD3<Float>( 0.11, 1.30, 0.23), radii: SIMD3<Float>(repeating: 0.04), material: dark, segments: 7, rings: 4)
                }
            }

            // Brazos a los lados sujetando la rampa
            addSphere(center: origin + SIMD3<Float>(-0.42, 0.86, -0.10), radii: SIMD3<Float>(repeating: 0.11), material: armor)
            addSphere(center: origin + SIMD3<Float>( 0.42, 0.86, -0.10), radii: SIMD3<Float>(repeating: 0.11), material: armor)
            addBox(center: origin + SIMD3<Float>(-0.44, 0.70, -0.08), size: SIMD3<Float>(0.14, 0.28, 0.15), material: suit)
            addBox(center: origin + SIMD3<Float>( 0.44, 0.70, -0.08), size: SIMD3<Float>(0.14, 0.28, 0.15), material: suit)
            addSphere(center: origin + SIMD3<Float>(-0.44, 0.54, -0.06), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addSphere(center: origin + SIMD3<Float>( 0.44, 0.54, -0.06), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addBox(center: origin + SIMD3<Float>(-0.42, 0.38, 0.06), size: SIMD3<Float>(0.13, 0.26, 0.16), material: suit)
            addBox(center: origin + SIMD3<Float>( 0.42, 0.38, 0.06), size: SIMD3<Float>(0.13, 0.26, 0.16), material: suit)

            // Piernas proyectadas al frente sentadas
            addSphere(center: origin + SIMD3<Float>(-0.16, 0.26, -0.04), radii: SIMD3<Float>(repeating: 0.10), material: armor)
            addSphere(center: origin + SIMD3<Float>( 0.16, 0.26, -0.04), radii: SIMD3<Float>(repeating: 0.10), material: armor)
            addBox(center: origin + SIMD3<Float>(-0.16, 0.26, 0.18), size: SIMD3<Float>(0.15, 0.18, 0.30), material: suit)
            addBox(center: origin + SIMD3<Float>( 0.16, 0.26, 0.18), size: SIMD3<Float>(0.15, 0.18, 0.30), material: suit)
            // Rodillas flexionadas hacia arriba
            addSphere(center: origin + SIMD3<Float>(-0.16, 0.30, 0.38), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addSphere(center: origin + SIMD3<Float>( 0.16, 0.30, 0.38), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addBox(center: origin + SIMD3<Float>(-0.16, 0.18, 0.52), size: SIMD3<Float>(0.14, 0.22, 0.16), material: suit)
            addBox(center: origin + SIMD3<Float>( 0.16, 0.18, 0.52), size: SIMD3<Float>(0.14, 0.22, 0.16), material: suit)
            addBox(center: origin + SIMD3<Float>(-0.16, 0.08, 0.70), size: SIMD3<Float>(0.17, 0.06, 0.36), material: flipperMat)
            addBox(center: origin + SIMD3<Float>( 0.16, 0.08, 0.70), size: SIMD3<Float>(0.17, 0.06, 0.36), material: flipperMat)

        case .walk:
            // 🏃 Walk / Run: Zancada dinámica con flexión alterna de codos y rodillas
            if isJellyGremlin {
                addJellyGremlinHeadAndTorso(
                    bellyCenter: origin + SIMD3<Float>(0, 0.76, 0.02),
                    headCenter: origin + SIMD3<Float>(0, 1.30, 0.05),
                    jellyMat: suit
                )
            } else {
                let torsoO = origin + SIMD3<Float>(0, 0.86, 0)
                addSphere(center: torsoO, radii: SIMD3<Float>(0.34, 0.50, 0.27), material: suit)
                addBox(center: origin + SIMD3<Float>(0, 0.92, 0.16), size: SIMD3<Float>(0.44, 0.42, 0.12), material: armor)
                addSphere(center: origin + SIMD3<Float>(0, 0.95, 0.23), radii: SIMD3<Float>(repeating: 0.08), material: coreEmissive)
                addBox(center: origin + SIMD3<Float>(0, 0.92, -0.22), size: SIMD3<Float>(0.28, 0.55, 0.18), material: scubaTankMat)
                addSphere(center: origin + SIMD3<Float>(0, 1.22, -0.22), radii: SIMD3<Float>(repeating: 0.09), material: armor)
                addSphere(center: origin + SIMD3<Float>(0, 1.55, 0), radii: SIMD3<Float>(repeating: 0.32), material: suit)
                addBox(center: origin + SIMD3<Float>(0, 1.58, 0.22), size: SIMD3<Float>(0.38, 0.18, 0.14), material: visor)
                if eyes {
                    addSphere(center: origin + SIMD3<Float>(-0.11, 1.60, 0.29), radii: SIMD3<Float>(repeating: 0.04), material: dark, segments: 7, rings: 4)
                    addSphere(center: origin + SIMD3<Float>( 0.11, 1.60, 0.29), radii: SIMD3<Float>(repeating: 0.04), material: dark, segments: 7, rings: 4)
                }
            }

            // Brazo Izq adelante (codo flexionado a 75º)
            addSphere(center: origin + SIMD3<Float>(-0.42, 1.15, 0.04), radii: SIMD3<Float>(repeating: 0.11), material: armor)
            addBox(center: origin + SIMD3<Float>(-0.42, 0.98, 0.08), size: SIMD3<Float>(0.14, 0.28, 0.15), material: suit)
            addSphere(center: origin + SIMD3<Float>(-0.42, 0.82, 0.15), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addBox(center: origin + SIMD3<Float>(-0.38, 0.68, 0.25), size: SIMD3<Float>(0.13, 0.26, 0.16), material: suit)

            // Brazo Der atrás
            addSphere(center: origin + SIMD3<Float>( 0.42, 1.15, -0.04), radii: SIMD3<Float>(repeating: 0.11), material: armor)
            addBox(center: origin + SIMD3<Float>( 0.42, 0.98, -0.08), size: SIMD3<Float>(0.14, 0.28, 0.15), material: suit)
            addSphere(center: origin + SIMD3<Float>( 0.42, 0.82, -0.15), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addBox(center: origin + SIMD3<Float>( 0.42, 0.68, -0.22), size: SIMD3<Float>(0.13, 0.26, 0.16), material: suit)
            if holdsTool {
                addHeldGadget(center: origin + SIMD3<Float>(0.47, 0.68, 0.12))
            }

            // Pierna Izq adelante (zancada con rodilla flexionada)
            addSphere(center: origin + SIMD3<Float>(-0.16, 0.52, 0), radii: SIMD3<Float>(repeating: 0.10), material: armor)
            addBox(center: origin + SIMD3<Float>(-0.16, 0.38, 0.12), size: SIMD3<Float>(0.15, 0.26, 0.16), material: suit)
            addSphere(center: origin + SIMD3<Float>(-0.16, 0.24, 0.20), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addBox(center: origin + SIMD3<Float>(-0.16, 0.10, 0.22), size: SIMD3<Float>(0.14, 0.24, 0.15), material: suit)
            addBox(center: origin + SIMD3<Float>(-0.16, 0.02, 0.38), size: SIMD3<Float>(0.17, 0.05, 0.36), material: flipperMat)

            // Pierna Der atrás (empuje de marcha)
            addSphere(center: origin + SIMD3<Float>( 0.16, 0.52, 0), radii: SIMD3<Float>(repeating: 0.10), material: armor)
            addBox(center: origin + SIMD3<Float>( 0.16, 0.38, -0.12), size: SIMD3<Float>(0.15, 0.26, 0.16), material: suit)
            addSphere(center: origin + SIMD3<Float>( 0.16, 0.24, -0.20), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addBox(center: origin + SIMD3<Float>( 0.16, 0.12, -0.26), size: SIMD3<Float>(0.14, 0.24, 0.15), material: suit)
            addBox(center: origin + SIMD3<Float>( 0.16, 0.04, -0.16), size: SIMD3<Float>(0.17, 0.05, 0.36), material: flipperMat)

        case .climb:
            // 🪜 Escalando escalera vertical: Sujetándose firmemente a los peldaños con ambas manos y pies escalonados
            let bootMat = isJellyGremlin ? clawMat : armor

            if isJellyGremlin {
                addJellyGremlinHeadAndTorso(
                    bellyCenter: origin + SIMD3<Float>(0, 0.84, 0.05),
                    headCenter: origin + SIMD3<Float>(0, 1.38, 0.12),
                    jellyMat: suit
                )
            } else {
                let torsoO = origin + SIMD3<Float>(0, 0.88, 0.05)
                addSphere(center: torsoO, radii: SIMD3<Float>(0.34, 0.50, 0.27), material: suit)
                addBox(center: origin + SIMD3<Float>(0, 0.94, 0.20), size: SIMD3<Float>(0.44, 0.42, 0.12), material: armor)
                addSphere(center: origin + SIMD3<Float>(0, 0.97, 0.27), radii: SIMD3<Float>(repeating: 0.08), material: coreEmissive)
                addBox(center: origin + SIMD3<Float>(0, 0.92, -0.18), size: SIMD3<Float>(0.28, 0.55, 0.18), material: scubaTankMat)
                addSphere(center: origin + SIMD3<Float>(0, 1.22, -0.18), radii: SIMD3<Float>(repeating: 0.09), material: armor)
                addSphere(center: origin + SIMD3<Float>(0, 1.55, 0.08), radii: SIMD3<Float>(repeating: 0.32), material: suit)
                addBox(center: origin + SIMD3<Float>(0, 1.60, 0.30), size: SIMD3<Float>(0.38, 0.18, 0.14), material: visor)
                if eyes {
                    addSphere(center: origin + SIMD3<Float>(-0.11, 1.62, 0.37), radii: SIMD3<Float>(repeating: 0.04), material: dark, segments: 7, rings: 4)
                    addSphere(center: origin + SIMD3<Float>( 0.11, 1.62, 0.37), radii: SIMD3<Float>(repeating: 0.04), material: dark, segments: 7, rings: 4)
                }
            }

            // 💪 Brazos elevados al frente sujetando los peldaños de la escalera:
            // Brazo Izquierdo (elevado alto agarrando el peldaño superior)
            addSphere(center: origin + SIMD3<Float>(-0.40, 1.20, 0.12), radii: SIMD3<Float>(repeating: 0.11), material: armor)
            addBox(center: origin + SIMD3<Float>(-0.36, 1.35, 0.22), size: SIMD3<Float>(0.13, 0.30, 0.14), material: suit)
            addSphere(center: origin + SIMD3<Float>(-0.32, 1.48, 0.32), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addBox(center: origin + SIMD3<Float>(-0.28, 1.58, 0.38), size: SIMD3<Float>(0.12, 0.22, 0.13), material: suit)
            addSphere(center: origin + SIMD3<Float>(-0.24, 1.68, 0.42), radii: SIMD3<Float>(repeating: 0.085), material: armor)

            // Brazo Derecho (apoyado en el peldaño intermedio)
            addSphere(center: origin + SIMD3<Float>( 0.40, 1.18, 0.10), radii: SIMD3<Float>(repeating: 0.11), material: armor)
            addBox(center: origin + SIMD3<Float>( 0.36, 1.24, 0.22), size: SIMD3<Float>(0.13, 0.28, 0.14), material: suit)
            addSphere(center: origin + SIMD3<Float>( 0.32, 1.34, 0.32), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addBox(center: origin + SIMD3<Float>( 0.28, 1.42, 0.38), size: SIMD3<Float>(0.12, 0.20, 0.13), material: suit)
            addSphere(center: origin + SIMD3<Float>( 0.24, 1.50, 0.42), radii: SIMD3<Float>(repeating: 0.085), material: armor)

            // 🦵 Piernas flexionadas en escalón (apoyadas sobre los peldaños):
            // Pierna Izquierda: Rodilla alzada escalonando peldaño superior
            addSphere(center: origin + SIMD3<Float>(-0.16, 0.52, 0.04), radii: SIMD3<Float>(repeating: 0.10), material: armor)
            addBox(center: origin + SIMD3<Float>(-0.16, 0.42, 0.18), size: SIMD3<Float>(0.14, 0.22, 0.20), material: suit)
            addSphere(center: origin + SIMD3<Float>(-0.16, 0.36, 0.30), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addBox(center: origin + SIMD3<Float>(-0.16, 0.22, 0.28), size: SIMD3<Float>(0.13, 0.26, 0.14), material: suit)
            addBox(center: origin + SIMD3<Float>(-0.16, 0.12, 0.34), size: SIMD3<Float>(0.15, 0.08, 0.22), material: bootMat)

            // Pierna Derecha: Pierna estirada apoyando la punta en peldaño inferior
            addSphere(center: origin + SIMD3<Float>( 0.16, 0.52, 0.02), radii: SIMD3<Float>(repeating: 0.10), material: armor)
            addBox(center: origin + SIMD3<Float>( 0.16, 0.36, 0.08), size: SIMD3<Float>(0.14, 0.26, 0.16), material: suit)
            addSphere(center: origin + SIMD3<Float>( 0.16, 0.20, 0.14), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addBox(center: origin + SIMD3<Float>( 0.16, 0.10, 0.16), size: SIMD3<Float>(0.13, 0.20, 0.14), material: suit)
            addBox(center: origin + SIMD3<Float>( 0.16, 0.02, 0.22), size: SIMD3<Float>(0.15, 0.08, 0.22), material: bootMat)

        case .stand:
            // 🧍 Stand: Pose erguida de combate con articulaciones naturales
            if isJellyGremlin {
                addJellyGremlinHeadAndTorso(
                    bellyCenter: origin + SIMD3<Float>(0, 0.76, 0.02),
                    headCenter: origin + SIMD3<Float>(0, 1.30, 0.04),
                    jellyMat: suit
                )
            } else {
                let torsoO = origin + SIMD3<Float>(0, 0.86, 0)
                addSphere(center: torsoO, radii: SIMD3<Float>(0.34, 0.50, 0.27), material: suit)
                addBox(center: origin + SIMD3<Float>(0, 0.92, 0.16), size: SIMD3<Float>(0.44, 0.42, 0.12), material: armor)
                addSphere(center: origin + SIMD3<Float>(0, 0.95, 0.23), radii: SIMD3<Float>(repeating: 0.08), material: coreEmissive)
                addBox(center: origin + SIMD3<Float>(0, 0.92, -0.22), size: SIMD3<Float>(0.28, 0.55, 0.18), material: scubaTankMat)
                addSphere(center: origin + SIMD3<Float>(0, 1.22, -0.22), radii: SIMD3<Float>(repeating: 0.09), material: armor)
                addSphere(center: origin + SIMD3<Float>(0, 1.55, 0), radii: SIMD3<Float>(repeating: 0.32), material: suit)
                addBox(center: origin + SIMD3<Float>(0, 1.58, 0.22), size: SIMD3<Float>(0.38, 0.18, 0.14), material: visor)
                if eyes {
                    addSphere(center: origin + SIMD3<Float>(-0.11, 1.60, 0.29), radii: SIMD3<Float>(repeating: 0.04), material: dark, segments: 7, rings: 4)
                    addSphere(center: origin + SIMD3<Float>( 0.11, 1.60, 0.29), radii: SIMD3<Float>(repeating: 0.04), material: dark, segments: 7, rings: 4)
                }
            }

            // Brazos
            addSphere(center: origin + SIMD3<Float>(-0.42, 1.15, 0), radii: SIMD3<Float>(repeating: 0.11), material: armor)
            addSphere(center: origin + SIMD3<Float>( 0.42, 1.15, 0), radii: SIMD3<Float>(repeating: 0.11), material: armor)
            addBox(center: origin + SIMD3<Float>(-0.42, 0.96, 0), size: SIMD3<Float>(0.14, 0.28, 0.15), material: suit)
            addBox(center: origin + SIMD3<Float>( 0.42, 0.96, 0), size: SIMD3<Float>(0.14, 0.28, 0.15), material: suit)
            // Codos articulados flexionados al frente
            addSphere(center: origin + SIMD3<Float>(-0.42, 0.80, 0.03), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addSphere(center: origin + SIMD3<Float>( 0.42, 0.80, 0.03), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addBox(center: origin + SIMD3<Float>(-0.42, 0.65, 0.09), size: SIMD3<Float>(0.13, 0.26, 0.16), material: suit)
            addBox(center: origin + SIMD3<Float>( 0.42, 0.65, 0.09), size: SIMD3<Float>(0.13, 0.26, 0.16), material: suit)
            if isJellyGremlin {
                // Garras en manos y pies del Diablillo
                for side: Float in [-1.0, 1.0] {
                    addSphere(center: origin + SIMD3<Float>(side * 0.42, 0.50, 0.13), radii: SIMD3<Float>(0.03, 0.06, 0.03), material: clawMat, segments: 6, rings: 4)
                    addSphere(center: origin + SIMD3<Float>(side * 0.38, 0.51, 0.16), radii: SIMD3<Float>(0.025, 0.055, 0.025), material: clawMat, segments: 6, rings: 4)
                    addSphere(center: origin + SIMD3<Float>(side * 0.19, 0.04, 0.36), radii: SIMD3<Float>(0.032, 0.035, 0.06), material: clawMat, segments: 6, rings: 4)
                    addSphere(center: origin + SIMD3<Float>(side * 0.13, 0.04, 0.36), radii: SIMD3<Float>(0.032, 0.035, 0.06), material: clawMat, segments: 6, rings: 4)
                }
            }
            if holdsTool {
                addHeldGadget(center: origin + SIMD3<Float>(0.47, 0.65, 0.28))
            }

            // Piernas
            addSphere(center: origin + SIMD3<Float>(-0.16, 0.52, 0), radii: SIMD3<Float>(repeating: 0.10), material: armor)
            addSphere(center: origin + SIMD3<Float>( 0.16, 0.52, 0), radii: SIMD3<Float>(repeating: 0.10), material: armor)
            addBox(center: origin + SIMD3<Float>(-0.16, 0.38, 0), size: SIMD3<Float>(0.15, 0.26, 0.16), material: suit)
            addBox(center: origin + SIMD3<Float>( 0.16, 0.38, 0), size: SIMD3<Float>(0.15, 0.26, 0.16), material: suit)
            // Rodillas articuladas
            addSphere(center: origin + SIMD3<Float>(-0.16, 0.23, 0.03), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addSphere(center: origin + SIMD3<Float>( 0.16, 0.23, 0.03), radii: SIMD3<Float>(repeating: 0.095), material: armor)
            addBox(center: origin + SIMD3<Float>(-0.16, 0.10, 0.03), size: SIMD3<Float>(0.14, 0.24, 0.15), material: suit)
            addBox(center: origin + SIMD3<Float>( 0.16, 0.10, 0.03), size: SIMD3<Float>(0.14, 0.24, 0.15), material: suit)
            addBox(center: origin + SIMD3<Float>(-0.16, 0.02, 0.16), size: SIMD3<Float>(0.17, 0.05, 0.36), material: flipperMat)
            addBox(center: origin + SIMD3<Float>( 0.16, 0.02, 0.16), size: SIMD3<Float>(0.17, 0.05, 0.36), material: flipperMat)
        }
    }
}

private extension MTLDevice {
    var isHardwareRayTracingSupported: Bool {
        let selector = Selector(("supportsRaytracing"))
        if self.responds(to: selector) {
            return self.supportsRaytracing
        }
        return false
    }
}

private struct RTMeshResources {
    let vertexBuffer: MTLBuffer
    let primitiveBuffer: MTLBuffer
    let accelerationStructure: MTLAccelerationStructure?
    let descriptor: MTLPrimitiveAccelerationStructureDescriptor?
    let scratchBuffer: MTLBuffer?
    let vertexCount: Int
}

enum MetalRayRendererError: Error {
    case rayTracingUnavailable
    case resourceCreationFailed
    case shaderMissing
}

final class MetalRayRenderer: NSObject, MTKViewDelegate {
    var onFPSUpdate: ((Double) -> Void)?
    var onNearbyLightUpdate: ((GameLightFixture?) -> Void)?
    var onToolStatusUpdate: ((GameToolStatus) -> Void)?
    var onFlashlightBatteryUpdate: ((Float) -> Void)?
    var flashlightBattery: Float = 1.0
    var onLaserBatteryUpdate: ((Float) -> Void)?
    var laserBattery: Float = 1.0
    var onMirrorHeatUpdate: ((Float, Bool) -> Void)?
    var mirrorHeat: Float = 0.0
    var mirrorOverheated: Bool = false
    var onScoreUpdate: ((Int) -> Void)?
    var playerScore: Int = 0
    var isRainbowGateUnlocked: Bool { playerScore >= 3000 }
    var onRainbowGateStatusUpdate: ((Bool, Int, Int) -> Void)?
    private var previousGateUnlocked: Bool = false
    var onDamageTaken: ((Float) -> Void)?
    var onWaveUpdate: ((Int, Int, Int, Bool, Float) -> Void)?
    var onLocalPlayerTransformUpdate: ((SIMD3<Float>, Float) -> Void)?
    var isPlayerDead: Bool = false
    var isHost: Bool = true
    var isRecoveringInChamber: Bool = false
    var remotePlayerIsRecovering: Bool = false
    var recoveryTimeRemaining: Float = 0.0
    var onNearRecoveryConsoleUpdate: ((Bool) -> Void)?
    var onRecoveryProgressUpdate: ((Float, Bool) -> Void)?
    var onRecoveryCompleted: (() -> Void)?
    var onMirrorReflectionKill: (() -> Void)?
    var onDroneDeflectionKill: (() -> Void)?
    var onQuantumPuzzleSolved: (() -> Void)?
    var onCampaignVictory: (() -> Void)?
    var chronoSwitchSolved: Bool = false
    var onSlideCompleted: (() -> Void)?
    var onCrossedRainbowGate: (() -> Void)?
    var onColossusDefeated: (() -> Void)?
    var onDeepDiveReached: (() -> Void)?
    var isRemotePlayerConnected: Bool = false
    var remotePlayerPosition: SIMD3<Float> = SIMD3<Float>(-3.8, 0, 3.8)
    var remotePlayerYaw: Float = .pi
    var remotePlayerHeldTool: GameHeldTool = .laser
    var remotePlayerIsFiringLaser: Bool = false
    var remoteAgents: [RemoteAgentState] = []
    var secondaryCameraPos: SIMD3<Float> = SIMD3<Float>(-3.8, 1.45, 3.8)
    var secondaryCameraFwd: SIMD3<Float> = SIMD3<Float>(0, 0, -1)
    private var smoothedRemotePos: SIMD3<Float> = SIMD3<Float>(-3.8, 0, 3.8)
    private var smoothedRemoteAgents: [String: SIMD3<Float>] = [:]
    private var netSyncTimer: Float = 0

    // Sincronización multijugador autoritativa de enemigos
    var isAuthorityForNPCs: Bool = true
    var isVersusMode: Bool = false
    var initialSpawnPosition: SIMD3<Float> = SIMD3<Float>(3.8, 0, 3.8)
    var initialSpawnYaw: Float = .pi
    var onNPCSyncUpdate: (([SIMD3<Float>], [Float], Int, Int, Int, Bool, Float, [SIMD3<Float>], [SIMD3<Float>]) -> Void)?
    var onClientNPCHit: ((Int, Float) -> Void)?
    var onRemotePlayerHit: ((Float) -> Void)?
    var onRemoteAgentHit: ((String, Float) -> Void)?
    var onBotDamageToRemotePlayer: ((Float) -> Void)?
    var onRemoteNPCEliminated: ((Int) -> Void)?
    private var remotePlayerHitCooldown: Float = 0
    private var playerLaserHitCooldowns = [Float](repeating: 0, count: 5)
    private var npcNetworkSyncCountdown: Float = 0
    private var syncedNPCNetworkPositions: [SIMD3<Float>]?
    private var remoteDamageAccumulator: Float = 0
    private(set) var currentBotLaserStarts = [SIMD3<Float>](repeating: .zero, count: 5)
    private(set) var currentBotLaserEnds = [SIMD3<Float>](repeating: .zero, count: 5)

    private var currentWave: Int = 1
    private var botsKilledInCurrentWave: Int = 0
    private var botsSpawnedInCurrentWave: Int = 2
    private var totalBotsInWave: Int = 2
    private var isWaveIntermission: Bool = false
    private var intermissionTimeRemaining: Float = 0
    private var waveStatusReportCountdown: Float = 0

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private let waterPipeline: MTLComputePipelineState
    private let waterVertexPipeline: MTLComputePipelineState
    private let laserPipeline: MTLComputePipelineState
    private let waterTextures: [MTLTexture]
    private let uniformBuffer: MTLBuffer
    private let laserResultBuffer: MTLBuffer
    private let staticMesh: RTMeshResources
    private let playerMesh: RTMeshResources
    private let playerWalkMesh: RTMeshResources
    private let playerCoverMesh: RTMeshResources
    private let playerSwimMesh: RTMeshResources
    private let playerSitMesh: RTMeshResources
    private let playerClimbMesh: RTMeshResources
    private let npcMesh: RTMeshResources
    private let fotofagoMesh: RTMeshResources
    private let waterMesh: RTMeshResources
    private let floatMesh: RTMeshResources
    private let mirrorShieldMesh: RTMeshResources
    private let rainbowGateMesh: RTMeshResources
    private let airPumpMesh: RTMeshResources
    private let instanceBuffer: MTLBuffer
    private var instanceDescriptor: MTLInstanceAccelerationStructureDescriptor?
    private var instanceAccelerationStructure: MTLAccelerationStructure?
    private var instanceScratchBuffer: MTLBuffer?
    private let frameSemaphore = DispatchSemaphore(value: 1)
    private let audio: ChiptuneAudioEngine

    private var joystick = CGVector.zero
    private var cameraMode = GameCameraMode.firstPerson
    private var rayBouncesEnabled = true
    private var heldTool = GameHeldTool.flashlight
    private var lightStates = GameLightStates()
    private var lastNearbyLight: GameLightFixture?
    private var hasReportedNearbyLight = false
    private var handledJumpRequestID = 0
    private var jumpQueued = false
    private var cameraYaw: Float = 0
    private var orbitPitch: Float = 0.22
    private var firstPersonPitch: Float = 0
    private var manualCameraTimer: Float = 0
    private var playerPosition = SIMD3<Float>(3.8, 0, 3.8)
    private var horizontalVelocity = SIMD2<Float>.zero
    private var verticalVelocity: Float = 0
    private var playerYaw: Float = .pi
    private var isSlidingOnToboggan: Bool = false
    private var enteredEasterEggViaToboggan: Bool = false
    private var isClimbingLadder: Bool = false
    private var ladderClimbTimer: Float = 0
    private var ladderCooldown: Float = 0
    private var npcPositions: [SIMD3<Float>] = [
        SIMD3<Float>(-13.5, 0, -13.5),
        SIMD3<Float>(13.5, 0, -13.5),
        SIMD3<Float>(-13.5, 0, 13.5),
        SIMD3<Float>(13.5, 0, 13.5),
        SIMD3<Float>(0, 0, 14.5)
    ]
    private var npcYaws = [Float.pi * 0.25, Float.pi * 1.7, Float.pi * 0.75, Float.pi * 1.25, Float.pi * 0.0]
    private var npcRespawnTimers = [Float](repeating: 0, count: 5)
    private let npcMaxHealths: [Float] = [80.0, 120.0, 180.0, 250.0, 350.0]
    private var npcHealths: [Float] = [80.0, 120.0, 180.0, 250.0, 350.0]
    private let npcBaseScales: [Float] = [0.94, 1.00, 1.06, 1.12, 1.20]
    private var npcMeltProgress = [Float](repeating: 0, count: 5)
    private var npcDeathPositions = [SIMD3<Float>](repeating: .zero, count: 5)
    var onNPCHealthsUpdate: (([Float]) -> Void)?
    private var botLaserActiveTimers = [Float](repeating: 0, count: 5)
    private var botLaserCooldownTimers = [Float](repeating: 5.0, count: 5)
    private var botImpactAudioCooldowns = [Float](repeating: 0, count: 5)
    private var botLaserPropagationDistances = [Float](repeating: 0, count: 5)
    private var botLaserOrigins = [SIMD3<Float>](repeating: .zero, count: 5)
    private var botLaserDistancesToPlayer = [Float](repeating: 0, count: 5)
    private var botAimTargets: [SIMD3<Float>] = [
        SIMD3<Float>(-13.5, 1.1, -13.5),
        SIMD3<Float>(13.5, 1.1, -13.5),
        SIMD3<Float>(-13.5, 1.1, 13.5),
        SIMD3<Float>(13.5, 1.1, 13.5),
        SIMD3<Float>(0, 1.1, 14.5)
    ]
    private var botTeleportReactionTimers = [Float](repeating: 0, count: 5)
    private var npcPushVelocities = [SIMD2<Float>](repeating: .zero, count: 5)
    private var characterBumpAudioCooldown: Float = 0
    private var lastObservedPlayerPosForTeleportCheck = SIMD3<Float>(3.8, 0, 3.8)
    private let npcSpawnPositions = [
        SIMD3<Float>(-13.5, 0, -13.5),
        SIMD3<Float>(13.5, 0, -13.5),
        SIMD3<Float>(-13.5, 0, 13.5),
        SIMD3<Float>(13.5, 0, 13.5),
        SIMD3<Float>(0, 0, 14.5)
    ]
    private var floatPosition = SIMD3<Float>(-2.6, 0.015, -2.0)
    private var floatVelocity = SIMD2<Float>.zero
    private var dummyPositions: [SIMD3<Float>] = [
        SIMD3<Float>(6.7, 0, 0.8),
        SIMD3<Float>(7.4, 0, -1.0),
        SIMD3<Float>(-7.7, 0, 4.3)
    ]
    private var dummyAlive: [Bool] = [true, true, true]
    private var floatYaw: Float = 0
    private var floatAngularVelocity: Float = 0
    private var floatWakeCountdown: Float = 0
    private var smoothedCameraTarget = SIMD3<Float>(3.8, 1.10, 3.8)
    private var lastFrameTime = CACurrentMediaTime()
    private var elapsedTime: Float = 0
    private var playerWaterWakeCountdown: Float = 0
    private var wasPlayerInWater: Bool = false
    private var lastSubmittedGlideIntensity: Float = -1
    private var fpsFrameCount = 0
    private var fpsStartTime = CACurrentMediaTime()
    private var waterStateIndex = 0
    private var pendingWaterImpulse = SIMD4<Float>.zero
    private var lastSubmittedWaterMovementIntensity: Float = -1
    private var lastCameraPosition = SIMD3<Float>.zero
    private var lastCameraRight = SIMD3<Float>(1, 0, 0)
    private var lastCameraUp = SIMD3<Float>(0, 1, 0)
    private var lastCameraForward = SIMD3<Float>(0, 0, -1)
    private var lastToolOrigin = SIMD3<Float>.zero
    private var lastToolDirection = SIMD3<Float>(0, 0, -1)
    private var lastHeldTool = GameHeldTool.none
    private var laserActiveRemaining: Float = 0
    private var laserCooldownRemaining: Float = 0
    private var laserPropagationDistance: Float = 0
    private var mirrorActiveRemaining: Float = 0
    private var mirrorCooldownRemaining: Float = 0
    private var toolStatusCountdown: Float = 0
    var isSplitScreenMode = false

    init(view: MTKView, audio: ChiptuneAudioEngine) throws {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice() else {
            throw MetalRayRendererError.resourceCreationFailed
        }
        let library: MTLLibrary
        if let defaultLib = device.makeDefaultLibrary(), defaultLib.makeFunction(name: "raytracePatio") != nil {
            library = defaultLib
        } else if let shaderURL = Bundle.main.url(forResource: "RayShaders", withExtension: "metal"),
                  let shaderSource = try? String(contentsOf: shaderURL, encoding: .utf8),
                  let compiledLib = try? device.makeLibrary(source: shaderSource, options: nil) {
            library = compiledLib
        } else {
            throw MetalRayRendererError.shaderMissing
        }

        guard let commandQueue = device.makeCommandQueue(),
              let function = library.makeFunction(name: "raytracePatio"),
              let waterFunction = library.makeFunction(name: "updateWaterHeight"),
              let waterVertexFunction = library.makeFunction(name: "updateWaterVertices"),
              let laserFunction = library.makeFunction(name: "traceToolLaser") else {
            throw MetalRayRendererError.shaderMissing
        }

        self.device = device
        self.commandQueue = commandQueue
        self.pipeline = try device.makeComputePipelineState(function: function)
        self.waterPipeline = try device.makeComputePipelineState(function: waterFunction)
        self.waterVertexPipeline = try device.makeComputePipelineState(function: waterVertexFunction)
        self.laserPipeline = try device.makeComputePipelineState(function: laserFunction)
        self.audio = audio

        let waterDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg16Float,
            width: 64,
            height: 48,
            mipmapped: false
        )
        waterDescriptor.storageMode = .shared
        waterDescriptor.usage = [.shaderRead, .shaderWrite]
        guard let firstWaterTexture = device.makeTexture(descriptor: waterDescriptor),
              let secondWaterTexture = device.makeTexture(descriptor: waterDescriptor) else {
            throw MetalRayRendererError.resourceCreationFailed
        }
        let createdWaterTextures = [firstWaterTexture, secondWaterTexture]
        self.waterTextures = createdWaterTextures

        let zeroWaterState = [UInt16](repeating: 0, count: waterDescriptor.width * waterDescriptor.height * 2)
        zeroWaterState.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            let region = MTLRegionMake2D(0, 0, waterDescriptor.width, waterDescriptor.height)
            for texture in createdWaterTextures {
                texture.replace(
                    region: region,
                    mipmapLevel: 0,
                    withBytes: baseAddress,
                    bytesPerRow: waterDescriptor.width * MemoryLayout<UInt16>.stride * 2
                )
            }
        }

        guard let uniformBuffer = device.makeBuffer(
            length: MemoryLayout<RTUniforms>.stride,
            options: .storageModeShared
        ), let laserResultBuffer = device.makeBuffer(
            length: MemoryLayout<RTLaserResult>.stride,
            options: .storageModeShared
        ) else {
            throw MetalRayRendererError.resourceCreationFailed
        }
        self.uniformBuffer = uniformBuffer
        self.laserResultBuffer = laserResultBuffer

        let staticBuilder = Self.makeStaticScene()
        let playerBuilder = Self.makePlayerMesh(pose: .stand)
        let playerWalkBuilder = Self.makePlayerMesh(pose: .walk)
        let playerCoverBuilder = Self.makePlayerMesh(pose: .cover)
        let playerSwimBuilder = Self.makePlayerMesh(pose: .swim)
        let playerSitBuilder = Self.makePlayerMesh(pose: .sit)
        let playerClimbBuilder = Self.makePlayerMesh(pose: .climb)
        let npcBuilder = Self.makeNPCMesh()
        let fotofagoBuilder = Self.makeFotofagoMesh()
        let waterBuilder = Self.makeWaterMesh()
        let floatBuilder = Self.makeFloatMesh()
        let mirrorShieldBuilder = Self.makeMirrorShieldMesh()
        let rainbowGateBuilder = Self.makeRainbowGateMesh()
        let airPumpBuilder = Self.makeAirPumpMesh()
        self.staticMesh = try Self.makeMesh(builder: staticBuilder, device: device, queue: commandQueue)
        self.playerMesh = try Self.makeMesh(builder: playerBuilder, device: device, queue: commandQueue)
        self.playerWalkMesh = try Self.makeMesh(builder: playerWalkBuilder, device: device, queue: commandQueue)
        self.playerCoverMesh = try Self.makeMesh(builder: playerCoverBuilder, device: device, queue: commandQueue)
        self.playerSwimMesh = try Self.makeMesh(builder: playerSwimBuilder, device: device, queue: commandQueue)
        self.playerSitMesh = try Self.makeMesh(builder: playerSitBuilder, device: device, queue: commandQueue)
        self.playerClimbMesh = try Self.makeMesh(builder: playerClimbBuilder, device: device, queue: commandQueue)
        self.npcMesh = try Self.makeMesh(builder: npcBuilder, device: device, queue: commandQueue)
        self.fotofagoMesh = try Self.makeMesh(builder: fotofagoBuilder, device: device, queue: commandQueue)
        self.waterMesh = try Self.makeMesh(
            builder: waterBuilder,
            device: device,
            queue: commandQueue,
            allowsRefit: true
        )
        self.floatMesh = try Self.makeMesh(builder: floatBuilder, device: device, queue: commandQueue)
        self.mirrorShieldMesh = try Self.makeMesh(builder: mirrorShieldBuilder, device: device, queue: commandQueue)
        self.rainbowGateMesh = try Self.makeMesh(builder: rainbowGateBuilder, device: device, queue: commandQueue)
        self.airPumpMesh = try Self.makeMesh(builder: airPumpBuilder, device: device, queue: commandQueue)

        let instanceLength = MemoryLayout<MTLAccelerationStructureInstanceDescriptor>.stride * 26
        guard let instanceBuffer = device.makeBuffer(length: instanceLength, options: .storageModeShared) else {
            throw MetalRayRendererError.resourceCreationFailed
        }
        self.instanceBuffer = instanceBuffer

        if device.isHardwareRayTracingSupported,
           let staticAS = staticMesh.accelerationStructure,
           let playerAS = playerMesh.accelerationStructure,
           let playerWalkAS = playerWalkMesh.accelerationStructure,
           let playerCoverAS = playerCoverMesh.accelerationStructure,
           let playerSwimAS = playerSwimMesh.accelerationStructure,
           let playerSitAS = playerSitMesh.accelerationStructure,
           let playerClimbAS = playerClimbMesh.accelerationStructure,
           let waterAS = waterMesh.accelerationStructure,
           let floatAS = floatMesh.accelerationStructure,
           let npcAS = npcMesh.accelerationStructure,
           let fotofagoAS = fotofagoMesh.accelerationStructure,
           let shieldAS = mirrorShieldMesh.accelerationStructure,
           let rainbowGateAS = rainbowGateMesh.accelerationStructure,
           let airPumpAS = airPumpMesh.accelerationStructure {
            let descriptor = MTLInstanceAccelerationStructureDescriptor()
            descriptor.instancedAccelerationStructures = [
                staticAS,        // 0
                playerAS,        // 1 (stand)
                waterAS,         // 2
                floatAS,         // 3
                npcAS,           // 4 (Scout / Soldado Plasma)
                shieldAS,        // 5
                playerCoverAS,   // 6 (cover GTA)
                playerSwimAS,    // 7 (swim Mario)
                playerSitAS,     // 8 (sit tobogán)
                playerWalkAS,    // 9 (walk articulado)
                playerClimbAS,   // 10 (climb escalera)
                fotofagoAS,      // 11 (El Fotófago - Golem Devorador de Luz)
                rainbowGateAS,   // 12 (Puerta Holográfica Arcoíris 3,000 Pts)
                airPumpAS        // 13 (Bomba de Aire Neumática de Inflado Slime)
            ]
            descriptor.instanceCount = 26
            descriptor.instanceDescriptorBuffer = instanceBuffer
            self.instanceDescriptor = descriptor

            let sizes = device.accelerationStructureSizes(descriptor: descriptor)
            if let instanceAccelerationStructure = device.makeAccelerationStructure(size: sizes.accelerationStructureSize),
               let scratch = device.makeBuffer(
                 length: max(256, sizes.buildScratchBufferSize),
                 options: .storageModePrivate
               ) {
                self.instanceAccelerationStructure = instanceAccelerationStructure
                self.instanceScratchBuffer = scratch
            } else {
                self.instanceDescriptor = nil
                self.instanceAccelerationStructure = nil
                self.instanceScratchBuffer = nil
            }
        } else {
            self.instanceDescriptor = nil
            self.instanceAccelerationStructure = nil
            self.instanceScratchBuffer = nil
        }

        super.init()

        writeInstanceDescriptors()
        try buildInitialInstanceAccelerationStructure()
    }

    private var isSlowMotionActive = false
    private var isWaterDisturbanceQueued = false
    private var lakituPosition: SIMD3<Float> = SIMD3<Float>(0, 2.5, 5)
    private var isGamePaused = false
    private var isCoverActive = false
    private var shieldYawOffset: Float = 0
    private var shieldPitchOffset: Float = 0
    var onCoverStatusUpdate: ((Bool) -> Void)?
    var onUnderwaterStatusUpdate: ((Bool) -> Void)?

    private var handledWarpRequestID = 0
    private var handledResetRequestID = 0
    private var handledRespawnRequestID = 0
    private var handledDiveRequestID = 0
    private var diveQueued = false

    func resetSimulation() {
        playerPosition = initialSpawnPosition
        horizontalVelocity = .zero
        verticalVelocity = 0
        playerYaw = initialSpawnYaw
        cameraYaw = initialSpawnYaw - .pi
        orbitPitch = 0.22
        firstPersonPitch = 0
        isSlidingOnToboggan = false
        heldTool = .flashlight
        flashlightBattery = 1.0

        currentWave = 1
        botsKilledInCurrentWave = 0
        totalBotsInWave = 2
        botsSpawnedInCurrentWave = min(totalBotsInWave, npcPositions.count)
        isWaveIntermission = false
        intermissionTimeRemaining = 0

        for i in npcPositions.indices {
            let spawnIndex = i % npcSpawnPositions.count
            if i < botsSpawnedInCurrentWave {
                npcPositions[i] = npcSpawnPositions[spawnIndex]
                npcYaws[i] = Float.pi * (0.25 + Float(i) * 0.5)
                npcRespawnTimers[i] = 0
                npcHealths[i] = npcMaxHealths[i]
                npcMeltProgress[i] = 0
                botLaserActiveTimers[i] = 0
                botLaserCooldownTimers[i] = 6.5 + Float(i) * 2.0
                botTeleportReactionTimers[i] = 0
                botAimTargets[i] = npcSpawnPositions[spawnIndex] + SIMD3<Float>(0, 1.1, 0)
            } else {
                npcPositions[i] = SIMD3<Float>(0, -10, 0)
                npcHealths[i] = 0
                npcRespawnTimers[i] = 9999.0
                npcMeltProgress[i] = 0
                botLaserActiveTimers[i] = 0
                botLaserCooldownTimers[i] = 9999.0
                botTeleportReactionTimers[i] = 0
            }
            currentBotLaserStarts[i] = .zero
            currentBotLaserEnds[i] = .zero
            botLaserPropagationDistances[i] = 0
        }
        let results = laserResultBuffer.contents().assumingMemoryBound(to: RTLaserResult.self)
        results.pointee.bot0Start = .zero; results.pointee.bot0End = .zero
        results.pointee.bot1Start = .zero; results.pointee.bot1End = .zero
        results.pointee.bot2Start = .zero; results.pointee.bot2End = .zero
        results.pointee.bot3Start = .zero; results.pointee.bot3End = .zero
        results.pointee.bot4Start = .zero; results.pointee.bot4End = .zero
        onNPCHealthsUpdate?(npcHealths)
    }

    func setInput(
        joystick: CGVector,
        cameraMode: GameCameraMode,
        rayBouncesEnabled: Bool,
        heldTool: GameHeldTool,
        lightStates: GameLightStates,
        jumpRequestID: Int,
        isSlowMotionActive: Bool = false,
        warpRequestID: Int = 0,
        requestedWarpPosition: SIMD3<Float> = .zero,
        isPaused: Bool = false,
        resetRequestID: Int = 0,
        isCoverActive: Bool = false,
        shieldAngleOffset: CGVector = .zero,
        respawnRequestID: Int = 0,
        diveRequestID: Int = 0
    ) {
        self.joystick = joystick
        if self.cameraMode != cameraMode {
            self.cameraMode = cameraMode
            if cameraMode == .thirdPerson {
                let backDir = SIMD3<Float>(sin(cameraYaw), 0.35, cos(cameraYaw))
                self.lakituPosition = playerPosition + SIMD3<Float>(0, 1.28, 0) + backDir * 3.8
            }
        }
        self.rayBouncesEnabled = rayBouncesEnabled
        self.heldTool = heldTool
        self.lightStates = lightStates
        self.isSlowMotionActive = isSlowMotionActive
        self.isGamePaused = isPaused
        self.isCoverActive = isCoverActive
        self.shieldYawOffset = Float(shieldAngleOffset.dx) * 0.90
        self.shieldPitchOffset = -Float(shieldAngleOffset.dy) * 0.90
        if handledJumpRequestID != jumpRequestID {
            handledJumpRequestID = jumpRequestID
            jumpQueued = true
        }
        if handledDiveRequestID != diveRequestID {
            handledDiveRequestID = diveRequestID
            diveQueued = true
        }
        if handledWarpRequestID != warpRequestID {
            handledWarpRequestID = warpRequestID
            playerPosition = requestedWarpPosition
            verticalVelocity = 0
        }
        if handledResetRequestID != resetRequestID {
            handledResetRequestID = resetRequestID
            resetSimulation()
        }
        if handledRespawnRequestID != respawnRequestID {
            handledRespawnRequestID = respawnRequestID
            playerPosition = SIMD3<Float>(-1.5, 0.45, 1.8)
            horizontalVelocity = .zero
            verticalVelocity = 0
            isSlidingOnToboggan = false
            orbitPitch = 0.22
        }
    }

    func rotateCamera(deltaX: Float, deltaY: Float) {
        cameraYaw += deltaX * 0.0075
        manualCameraTimer = 1.0
        if cameraMode == .firstPerson {
            firstPersonPitch = max(-1.35, min(1.35, firstPersonPitch - deltaY * 0.0045))
        } else {
            orbitPitch = max(-0.25, min(0.68, orbitPitch - deltaY * 0.0045))
        }
    }

    func resetCamera() {
        cameraYaw = playerYaw + .pi
        orbitPitch = 0.22
        firstPersonPitch = 0
    }

    func disturbWater(screenPoint: CGPoint, viewSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        let uvX = Float(screenPoint.x / viewSize.width) * 2 - 1
        let uvY = -(Float(screenPoint.y / viewSize.height) * 2 - 1)
        let direction = simd_normalize(
            lastCameraForward + lastCameraRight * uvX + lastCameraUp * uvY
        )
        guard direction.y < -0.0001 else { return }
        let distance = (-0.07 - lastCameraPosition.y) / direction.y
        guard distance > 0 else { return }
        let hit = lastCameraPosition + direction * distance
        guard hit.x >= -5.4, hit.x <= 2.4, hit.z >= -4.2, hit.z <= 1.2 else { return }
        pendingWaterImpulse = SIMD4<Float>(hit.x, hit.z, -1.35, 1)
        audio.playWaterDisturbance(intensity: 0.72)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        if !UIApplication.shared.isIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        autoreleasepool {
            _ = frameSemaphore.wait(timeout: .distantFuture)
            guard let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue.makeCommandBuffer() else {
                frameSemaphore.signal()
                return
            }
            commandBuffer.addCompletedHandler { [frameSemaphore] _ in
                frameSemaphore.signal()
            }

            let now = CACurrentMediaTime()
            let rawDt = Float(min(1.0 / 30.0, max(0, now - lastFrameTime)))
            lastFrameTime = now
            let effectiveDt = isGamePaused ? 0.0 : (isSlowMotionActive ? rawDt * 0.20 : rawDt)
            if !isGamePaused {
                elapsedTime += effectiveDt
                updateSimulation(dt: effectiveDt, rawDt: rawDt)
            } else {
                audio.setGlideIntensity(0)
                audio.setWaterMovementIntensity(0)
            }
            writeInstanceDescriptors()
            writeUniforms(texture: drawable.texture, dt: effectiveDt)

            var renderedWaterTexture = waterTextures[waterStateIndex]
            let nextWaterStateIndex = 1 - waterStateIndex
            if let waterEncoder = commandBuffer.makeComputeCommandEncoder() {
                waterEncoder.setComputePipelineState(waterPipeline)
                waterEncoder.setBuffer(uniformBuffer, offset: 0, index: 0)
                waterEncoder.setTexture(waterTextures[waterStateIndex], index: 0)
                waterEncoder.setTexture(waterTextures[nextWaterStateIndex], index: 1)
                waterEncoder.dispatchThreads(
                    MTLSize(width: 64, height: 48, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
                )
                waterEncoder.endEncoding()
                renderedWaterTexture = waterTextures[nextWaterStateIndex]
                waterStateIndex = nextWaterStateIndex
            }

            if let waterVertexEncoder = commandBuffer.makeComputeCommandEncoder() {
                waterVertexEncoder.setComputePipelineState(waterVertexPipeline)
                waterVertexEncoder.setBuffer(waterMesh.vertexBuffer, offset: 0, index: 0)
                waterVertexEncoder.setTexture(renderedWaterTexture, index: 0)
                waterVertexEncoder.dispatchThreads(
                    MTLSize(width: waterMesh.vertexCount, height: 1, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1)
                )
                waterVertexEncoder.endEncoding()
            }

            if let instanceAS = instanceAccelerationStructure,
               let instanceDesc = instanceDescriptor,
               let instanceScratch = instanceScratchBuffer,
               let waterAS = waterMesh.accelerationStructure,
               let waterDesc = waterMesh.descriptor,
               let waterScratch = waterMesh.scratchBuffer,
               let accelerationEncoder = commandBuffer.makeAccelerationStructureCommandEncoder() {
                accelerationEncoder.refit(
                    sourceAccelerationStructure: waterAS,
                    descriptor: waterDesc,
                    destinationAccelerationStructure: waterAS,
                    scratchBuffer: waterScratch,
                    scratchBufferOffset: 0
                )
                accelerationEncoder.build(
                    accelerationStructure: instanceAS,
                    descriptor: instanceDesc,
                    scratchBuffer: instanceScratch,
                    scratchBufferOffset: 0
                )
                accelerationEncoder.endEncoding()
            }

            if let laserEncoder = commandBuffer.makeComputeCommandEncoder() {
                laserEncoder.setComputePipelineState(laserPipeline)
                laserEncoder.setBuffer(uniformBuffer, offset: 0, index: 0)
                laserEncoder.setBuffer(instanceBuffer, offset: 0, index: 1)
                if let instanceAS = instanceAccelerationStructure {
                    laserEncoder.setAccelerationStructure(instanceAS, bufferIndex: 2)
                }
                laserEncoder.setBuffer(laserResultBuffer, offset: 0, index: 3)
                laserEncoder.setTexture(renderedWaterTexture, index: 0)
                if let staticAS = staticMesh.accelerationStructure { laserEncoder.useResource(staticAS, usage: .read) }
                if let waterAS = waterMesh.accelerationStructure { laserEncoder.useResource(waterAS, usage: .read) }
                if let floatAS = floatMesh.accelerationStructure { laserEncoder.useResource(floatAS, usage: .read) }
                if let npcAS = npcMesh.accelerationStructure { laserEncoder.useResource(npcAS, usage: .read) }
                if let fotofagoAS = fotofagoMesh.accelerationStructure { laserEncoder.useResource(fotofagoAS, usage: .read) }
                if let shieldAS = mirrorShieldMesh.accelerationStructure { laserEncoder.useResource(shieldAS, usage: .read) }
                laserEncoder.dispatchThreads(
                    MTLSize(width: 1, height: 1, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1)
                )
                laserEncoder.endEncoding()
            }

            if let encoder = commandBuffer.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(uniformBuffer, offset: 0, index: 0)
                encoder.setBuffer(instanceBuffer, offset: 0, index: 1)
                if let instanceAS = instanceAccelerationStructure {
                    encoder.setAccelerationStructure(instanceAS, bufferIndex: 2)
                }
                encoder.setBuffer(laserResultBuffer, offset: 0, index: 3)
                encoder.setTexture(drawable.texture, index: 0)
                encoder.setTexture(renderedWaterTexture, index: 1)
                if let staticAS = staticMesh.accelerationStructure { encoder.useResource(staticAS, usage: .read) }
                if let playerAS = playerMesh.accelerationStructure { encoder.useResource(playerAS, usage: .read) }
                if let playerWalkAS = playerWalkMesh.accelerationStructure { encoder.useResource(playerWalkAS, usage: .read) }
                if let playerCoverAS = playerCoverMesh.accelerationStructure { encoder.useResource(playerCoverAS, usage: .read) }
                if let playerSwimAS = playerSwimMesh.accelerationStructure { encoder.useResource(playerSwimAS, usage: .read) }
                if let playerSitAS = playerSitMesh.accelerationStructure { encoder.useResource(playerSitAS, usage: .read) }
                if let playerClimbAS = playerClimbMesh.accelerationStructure { encoder.useResource(playerClimbAS, usage: .read) }
                if let waterAS = waterMesh.accelerationStructure { encoder.useResource(waterAS, usage: .read) }
                if let floatAS = floatMesh.accelerationStructure { encoder.useResource(floatAS, usage: .read) }
                if let npcAS = npcMesh.accelerationStructure { encoder.useResource(npcAS, usage: .read) }
                if let fotofagoAS = fotofagoMesh.accelerationStructure { encoder.useResource(fotofagoAS, usage: .read) }
                if let shieldAS = mirrorShieldMesh.accelerationStructure { encoder.useResource(shieldAS, usage: .read) }
                if let rainbowGateAS = rainbowGateMesh.accelerationStructure { encoder.useResource(rainbowGateAS, usage: .read) }
                if let airPumpAS = airPumpMesh.accelerationStructure { encoder.useResource(airPumpAS, usage: .read) }
                encoder.dispatchThreads(
                    MTLSize(width: drawable.texture.width, height: drawable.texture.height, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
                )
                encoder.endEncoding()
            }

            commandBuffer.present(drawable)
            commandBuffer.commit()
            pendingWaterImpulse = .zero

            fpsFrameCount += 1
            let fpsDuration = now - fpsStartTime
            if fpsDuration >= 0.5 {
                let framesPerSecond = Double(fpsFrameCount) / fpsDuration
                onFPSUpdate?(framesPerSecond)
    #if DEBUG
                print(String(format: "MetalRT %.1f FPS at %dx%d", framesPerSecond, drawable.texture.width, drawable.texture.height))
    #endif
                fpsFrameCount = 0
                fpsStartTime = now
            }
        }
    }

    private var pendingDamageAccumulator: Float = 0
    private var damageReportTimer: Float = 0
    private var playerMeltProgress: Float = 0
    private var remotePlayerMeltProgress: Float = 0

    private func accumulateDamage(_ amount: Float) {
        pendingDamageAccumulator += amount
    }

    private func flushDamageReport(rawDt: Float) {
        damageReportTimer += rawDt
        if damageReportTimer >= 0.28 {
            damageReportTimer = 0
            if pendingDamageAccumulator > 0 {
                let dmg = pendingDamageAccumulator
                pendingDamageAccumulator = 0
                onDamageTaken?(dmg)
            }
            if remoteDamageAccumulator > 0 {
                let rDmg = remoteDamageAccumulator
                remoteDamageAccumulator = 0
                onBotDamageToRemotePlayer?(rDmg)
            }
        }
    }

    private var swimStrokeTimer: Float = 0

    private func updateSimulation(dt: Float, rawDt: Float) {
        manualCameraTimer = max(0, manualCameraTimer - rawDt)
        updateToolTimers(dt: dt)
        updateNPCSimulation(dt: dt, rawDt: rawDt)
        flushDamageReport(rawDt: rawDt)
        checkCombatHits(dt: dt)
        onNPCHealthsUpdate?(npcHealths)

        if isRemotePlayerConnected {
            let interp = min(1.0, rawDt * 14.0)
            smoothedRemotePos += (remotePlayerPosition - smoothedRemotePos) * interp
            for agent in remoteAgents {
                let prev = smoothedRemoteAgents[agent.peerID] ?? agent.position
                smoothedRemoteAgents[agent.peerID] = prev + (agent.position - prev) * interp
            }
        }

        // 🧭 Sincronización continua de posición y rotación hacia el Minimapa y HUD táctico
        netSyncTimer += rawDt
        if netSyncTimer >= 0.045 {
            netSyncTimer = 0
            onLocalPlayerTransformUpdate?(playerPosition, playerYaw)
        }
        let wasRidingFloat = isStandingOnFloat(playerPosition)
        let floatDisplacement = updateFloatSimulation(dt: dt)
        if wasRidingFloat {
            playerPosition += floatDisplacement
        }

        let shouldPlayerMelt = isPlayerDead || isRecoveringInChamber
        if shouldPlayerMelt {
            playerMeltProgress = min(1.0, playerMeltProgress + rawDt * 1.6)
        } else {
            playerMeltProgress = max(0.0, playerMeltProgress - rawDt * 3.2)
        }

        let shouldRemoteMelt = remotePlayerIsRecovering
        if shouldRemoteMelt {
            remotePlayerMeltProgress = min(1.0, remotePlayerMeltProgress + rawDt * 1.6)
        } else {
            remotePlayerMeltProgress = max(0.0, remotePlayerMeltProgress - rawDt * 3.2)
        }

        // 💨 Slime Deflation & Pneumatic Air Pump Revive System
        if isRecoveringInChamber || isPlayerDead {
            horizontalVelocity = .zero
            let inPool = isInsidePoolXZ(playerPosition) && playerPosition.y <= 0.35
            let floorY = groundHeight(at: playerPosition, insidePool: inPool)
            if playerPosition.y > floorY {
                verticalVelocity -= dt * 25.0
                playerPosition.y = max(floorY, playerPosition.y + verticalVelocity * dt)
                if playerPosition.y <= floorY {
                    playerPosition.y = floorY
                    verticalVelocity = 0
                }
            } else {
                playerPosition.y = floorY
                verticalVelocity = 0
            }

            if isRecoveringInChamber {
                let distToTeammate = simd_distance(playerPosition, smoothedRemotePos)
                let teammateBoosting = isRemotePlayerConnected && !remotePlayerIsRecovering && distToTeammate < 2.5
                onRecoveryProgressUpdate?(recoveryTimeRemaining, teammateBoosting)
            }
            audio.setGlideIntensity(0)
            audio.setWaterMovementIntensity(0)
            return
        } else {
            // Proximidad a compañero caído en cualquier lugar del mapa para sacar la Bomba de Aire
            let distToFallenTeammate = simd_distance(playerPosition, smoothedRemotePos)
            let isNearFallen = isRemotePlayerConnected && remotePlayerIsRecovering && distToFallenTeammate < 2.5
            onNearRecoveryConsoleUpdate?(isNearFallen)
        }

        let inputX = max(-1.0, min(1.0, Float(joystick.dx)))
        let inputForward = max(-1.0, min(1.0, -Float(joystick.dy)))
        let magnitude = min(1.0, hypot(inputX, inputForward))
        let cameraForward = SIMD2<Float>(-sin(cameraYaw), -cos(cameraYaw))
        let cameraRight = SIMD2<Float>(cos(cameraYaw), -sin(cameraYaw))
        var desiredDirection = cameraRight * inputX + cameraForward * inputForward
        if simd_length_squared(desiredDirection) > 0.0001 {
            desiredDirection = simd_normalize(desiredDirection)
        }

        // 🌊 Subterranean Easter Egg & Posito de 10 cm con Pozo Profundo
        let currentlyInPool = isInsidePoolXZ(playerPosition) && playerPosition.y <= 0.35
        let isSubterranean = playerPosition.y <= -4.75
        if isSubterranean {
            onDeepDiveReached?()
        }
        let currentGroundHeight = isSubterranean ? -11.0 : groundHeight(at: playerPosition, insidePool: currentlyInPool)
        let currentlyOnFloat = currentlyInPool && isStandingOnFloat(playerPosition)
        onUnderwaterStatusUpdate?(currentlyInPool && !currentlyOnFloat && playerPosition.y < -0.25 || isSubterranean)
        let isUnderFire = pendingDamageAccumulator > 0
        let isDivingInPool = currentlyInPool && !currentlyOnFloat && playerPosition.y <= -0.65
        let baseSpeed: Float = isDivingInPool ? 4.2 : (currentlyInPool && !currentlyOnFloat ? 3.6 : (isSubterranean ? 4.6 : 4.0))
        let movementSpeed: Float = isUnderFire ? baseSpeed * 1.30 : baseSpeed // ⚡ Escape Evasion Boost (+30% speed under fire!)
        let targetVelocity = desiredDirection * (magnitude > 0.08 ? movementSpeed * magnitude : 0)
        let response = 1 - exp(-dt * (magnitude > 0.08 ? 16 : 22))
        horizontalVelocity += (targetVelocity - horizontalVelocity) * response
        if simd_length(horizontalVelocity) < 0.015 && magnitude <= 0.08 {
            horizontalVelocity = .zero
        }

        if ladderCooldown > 0 {
            ladderCooldown = max(0, ladderCooldown - dt)
        }

        // 🪜 Escalera Vertical de la Pared (Z = -16.85) para subir a la plataforma del tobogán
        let nearWallLadder = ladderCooldown <= 0 && playerPosition.x >= -4.60 && playerPosition.x <= -3.00 && playerPosition.z >= -17.2 && playerPosition.z <= -14.8 && playerPosition.y <= 5.85

        if nearWallLadder {
            let isAtTopPlatform = playerPosition.y >= 5.10
            let wantsDown = inputForward < -0.12 || (isAtTopPlatform && (magnitude > 0.12 || playerPosition.z < -15.2))
            let wantsUp = inputForward > 0.12 && !isAtTopPlatform

            if wantsUp || wantsDown || isClimbingLadder {
                isClimbingLadder = true
                let snapT = min(1.0, dt * 14.0)
                playerPosition.x += (-3.80 - playerPosition.x) * snapT
                playerPosition.z += (-16.02 - playerPosition.z) * snapT
                playerYaw = Float.pi
                horizontalVelocity = .zero

                if jumpQueued {
                    // 🚀 Salto de desenganche de la escalera hacia afuera
                    jumpQueued = false
                    isClimbingLadder = false
                    ladderCooldown = 0.50
                    verticalVelocity = 4.2
                    horizontalVelocity = SIMD2<Float>(0, 4.4)
                    audio.playLanding(intensity: 0.35)
                } else if wantsUp {
                    verticalVelocity = 2.4 * max(0.5, magnitude)
                    ladderClimbTimer -= dt
                    if ladderClimbTimer <= 0 {
                        audio.playLanding(intensity: 0.28)
                        ladderClimbTimer = 0.26
                    }
                    if playerPosition.y >= 5.50 {
                        // Desembarco suave en la plataforma del tobogán
                        playerPosition.y = 5.55
                        playerPosition.z = -15.4
                        verticalVelocity = 0
                        isClimbingLadder = false
                        ladderCooldown = 0.35
                        audio.playLanding(intensity: 0.45)
                    }
                } else if wantsDown {
                    verticalVelocity = -2.4 * max(0.5, magnitude)
                    ladderClimbTimer -= dt
                    if ladderClimbTimer <= 0 {
                        audio.playLanding(intensity: 0.24)
                        ladderClimbTimer = 0.28
                    }
                    if playerPosition.y <= 0.15 {
                        // Desembarco en el suelo
                        playerPosition.y = 0.0
                        verticalVelocity = 0
                        isClimbingLadder = false
                        ladderCooldown = 0.30
                        audio.playLanding(intensity: 0.35)
                    }
                } else {
                    verticalVelocity = 0
                }
            }
        } else {
            isClimbingLadder = false
        }

        // 🌊 Rodadero Recto 3D de Alta Velocidad (Straight water slide ramp from platform at Z = -14.5 into pool at Z = -3.8)
        let slideStart = SIMD3<Float>(-3.8, 5.55, -14.5)
        let slideEnd = SIMD3<Float>(-2.2, 0.05, -3.8)
        let slideVec = slideEnd - slideStart
        let slideLenSq = simd_length_squared(slideVec)

        let playerRel = playerPosition - slideStart
        let tProj = max(0, min(1, simd_dot(playerRel, slideVec) / slideLenSq))
        let closestSlidePoint = slideStart + slideVec * tProj
        let distToSlide = simd_distance(playerPosition, closestSlidePoint)

        let isOnTopPlatform = playerPosition.y >= 4.5 && playerPosition.x >= -5.5 && playerPosition.x <= -2.1 && playerPosition.z >= -17.2 && playerPosition.z <= -13.5
        let isValidSlideAccess = isSlidingOnToboggan || (isOnTopPlatform && distToSlide < 1.8)

        if isValidSlideAccess {
            isSlidingOnToboggan = true
            let slideDir = simd_normalize(slideVec)
            let slideLen = sqrt(slideLenSq)

            // Direct lock & smooth progression along straight slide vector
            let nextTProj = min(1.0, tProj + (8.5 * dt / slideLen))
            let nextSlidePoint = slideStart + slideVec * nextTProj

            playerPosition = nextSlidePoint
            horizontalVelocity = SIMD2<Float>(slideDir.x, slideDir.z) * 8.5
            verticalVelocity = slideDir.y * 8.5

            // Continuous water spray & splash disturbance along slide chute!
            pendingWaterImpulse = SIMD4<Float>(playerPosition.x, playerPosition.z, -0.45, 1)
        } else {
            isSlidingOnToboggan = false
        }

        // 🌀 Subterranean Easter Egg Portal Plunge Trigger (Toboggan Slide plunge into underwater realm)
        let nearSlidePlungeZone = playerPosition.x >= -4.5 && playerPosition.x <= -0.5 && playerPosition.z >= -7.8 && playerPosition.z <= -1.0
        if isSlidingOnToboggan && (tProj >= 0.70 || playerPosition.y <= 1.8) && nearSlidePlungeZone {
            onSlideCompleted?()
            playerPosition = SIMD3<Float>(-2.5, -5.5, -2.5)
            verticalVelocity = -0.8
            isSlidingOnToboggan = false
            enteredEasterEggViaToboggan = true
            audio.setGlideIntensity(0)
            audio.setWaterMovementIntensity(0)
            audio.playSubterraneanPortalPlungeSound()
            pendingWaterImpulse = SIMD4<Float>(playerPosition.x, playerPosition.z, -1.8, 1)
        } else if isSlidingOnToboggan && (tProj >= 0.95 || playerPosition.y <= 0.25) {
            playerPosition = SIMD3<Float>(-2.2, -0.22, -2.5)
            verticalVelocity = -0.4
            horizontalVelocity = SIMD2<Float>(0, 3.0)
            isSlidingOnToboggan = false
            audio.setGlideIntensity(0)
            pendingWaterImpulse = SIMD4<Float>(playerPosition.x, playerPosition.z, -1.85, 1)
            audio.playWaterDisturbance(intensity: 0.95)
        }

        // 🛡️ 🪨 Tactical Rock Cover System (Pegarse a Cobertura)
        var nearCoverRock: RTRiverRock?
        var minRockDist: Float = 1.6
        for rock in rtRiverRocks {
            let rCenter = SIMD2<Float>(rock.center.x, rock.center.z)
            let pCenter = SIMD2<Float>(playerPosition.x, playerPosition.z)
            let dist = simd_distance(pCenter, rCenter) - rock.radii.x
            if dist < minRockDist {
                minRockDist = dist
                nearCoverRock = rock
            }
        }
        onCoverStatusUpdate?(nearCoverRock != nil)

        if isCoverActive, let rock = nearCoverRock {
            let rCenter = SIMD2<Float>(rock.center.x, rock.center.z)
            let pCenter = SIMD2<Float>(playerPosition.x, playerPosition.z)
            var awayDir = pCenter - rCenter
            if simd_length_squared(awayDir) > 0.0001 { awayDir = simd_normalize(awayDir) } else { awayDir = SIMD2<Float>(0, 1) }
            let coverPos = rCenter + awayDir * (rock.radii.x + 0.38)
            playerPosition.x = coverPos.x
            playerPosition.z = coverPos.y
            // 🛡️ Crouch Cover: Agacharse pegado al suelo detrás de la piedra a nivel de suelo
            playerPosition.y = currentGroundHeight
            verticalVelocity = 0
            horizontalVelocity *= exp(-dt * 6.0)

            // Orientación firme hacia la roca: el frente del personaje (+Z) y codos se pegan a la roca
            let rockDir = -awayDir
            let targetCoverYaw = atan2(rockDir.x, rockDir.y)
            var diff = targetCoverYaw - playerYaw
            while diff > Float.pi { diff -= 2 * Float.pi }
            while diff < -Float.pi { diff += 2 * Float.pi }
            playerYaw += diff * min(1.0, dt * 14.0)
        }


        if currentlyOnFloat && magnitude > 0.08 {
            floatVelocity -= desiredDirection * (dt * 0.58 * magnitude)
            let playerOffset = SIMD2<Float>(
                playerPosition.x - floatPosition.x,
                playerPosition.z - floatPosition.z
            )
            floatAngularVelocity += (
                playerOffset.x * desiredDirection.y - playerOffset.y * desiredDirection.x
            ) * dt * 0.22
        }

        var proposed = playerPosition
        proposed.x += horizontalVelocity.x * dt
        proposed.z += horizontalVelocity.y * dt
        clampToArenaBounds(position: &proposed, previousPosition: playerPosition, margin: 0.38, velocity: &horizontalVelocity)
        resolveFloatCollision(position: &proposed)
        resolveRockCollisions(position: &proposed)
        resolveParkourAndCabinCollisions(position: &proposed)
        resolveCharacterCollisions(playerPos: &proposed, dt: dt)
        resolveRockCollisions(position: &proposed)
        resolveParkourAndCabinCollisions(position: &proposed)
        clampToArenaBounds(position: &proposed, previousPosition: playerPosition, margin: 0.38, velocity: &horizontalVelocity)
        audio.setArenaZone(isRainbowHall: proposed.z > 18.0)
        let willBeInPool = isInsidePoolXZ(proposed) && proposed.y <= 0.35
        let isDeepInWater = playerPosition.y < -0.25
        let isInWater = (willBeInPool || currentlyInPool || isDeepInWater)
        let nextGroundHeight = groundHeight(at: proposed, insidePool: willBeInPool)
        let willBeOnFloat = willBeInPool && nextGroundHeight > -0.1
        let wasGrounded = playerPosition.y <= currentGroundHeight + 0.05

        // Smooth Auto-Step Up for Stairs & Ramps (step height up to 0.50m)
        if (!currentlyInPool || playerPosition.y >= -0.40) && nextGroundHeight > currentGroundHeight && (nextGroundHeight - currentGroundHeight) <= 0.50 {
            if playerPosition.y <= currentGroundHeight + 0.25 {
                proposed.y = nextGroundHeight
            }
        }

        let onTrampolineBoard = playerPosition.x >= 0.7 && playerPosition.x <= 2.1 && playerPosition.z >= -6.9 && playerPosition.z <= -3.7 && playerPosition.y >= 2.7

        if diveQueued {
            diveQueued = false
            if willBeInPool || currentlyInPool || isDeepInWater {
                verticalVelocity = -3.8 // Impulso inmediato de inmersión / buceo hacia el fondo
                enteredEasterEggViaToboggan = true
                audio.playSwimStrokeSound(intensity: 0.95)
                pendingWaterImpulse = SIMD4<Float>(playerPosition.x, playerPosition.z, -1.35, 1)
            }
        }

        if jumpQueued {
            jumpQueued = false
            if isInWater && !willBeOnFloat {
                if isDeepInWater {
                    // 🏊‍♂️ En la piscina profunda / abisal: brazada potente de ascenso continuo hacia la superficie
                    verticalVelocity = 5.2
                    audio.playSwimStrokeSound(intensity: 0.95)
                    pendingWaterImpulse = SIMD4<Float>(playerPosition.x, playerPosition.z, -1.20, 1)
                } else {
                    // 🚀 Salto natural en el posito de 14 cm
                    var jumpHVel = horizontalVelocity
                    if simd_length(desiredDirection) > 0.08 {
                        jumpHVel = desiredDirection * 3.4
                    }
                    verticalVelocity = 4.8
                    horizontalVelocity = jumpHVel
                    audio.playWaterDisturbance(intensity: 0.5)
                }
            } else if onTrampolineBoard {
                verticalVelocity = 5.2
                horizontalVelocity = SIMD2<Float>(0.0, 5.8)
            } else if wasGrounded || playerPosition.y <= currentGroundHeight + 0.18 {
                verticalVelocity = 5.0
            }
        }

        if isInWater && !willBeOnFloat {
            let isSwimming = magnitude > 0.08

            if !isDeepInWater {
                // 🌊 En la superficie: Posito de 14 cm de agua
                // El jugador camina y corre normalmente. Si cae al fondo, reposa en -0.14m.
                if proposed.y < -0.14 {
                    proposed.y = -0.14
                    verticalVelocity = max(0, verticalVelocity)
                } else if proposed.y > -0.14 {
                    // Gravedad aérea estándar: cuando saltas, subes y caes de vuelta con física realista
                    verticalVelocity -= 9.8 * dt
                }
            } else {
                // 🏊‍♂️ En la piscina profunda / reino subterráneo: Nado 3D libre y flotabilidad neutra
                if isSwimming {
                    // En 1ra persona: nadas en la dirección a donde miras con la cámara
                    let targetVerticalSwim = sin(firstPersonPitch) * movementSpeed * magnitude * 1.45
                    verticalVelocity += (targetVerticalSwim - verticalVelocity) * min(1.0, dt * 5.0)
                }

                // Amortiguación suave hidrodinámica (flotabilidad neutra sin gravedad forzada)
                verticalVelocity *= exp(-dt * 2.0)

                if isSwimming {
                    swimStrokeTimer -= dt
                    if swimStrokeTimer <= 0 {
                        audio.playSwimStrokeSound(intensity: 0.38 * magnitude)
                        swimStrokeTimer = 0.50
                    }
                } else {
                    swimStrokeTimer = min(swimStrokeTimer, 0.12)
                }
                horizontalVelocity *= exp(-dt * 1.5)
            }
        } else if isCoverActive {
            verticalVelocity = 0
        } else {
            verticalVelocity -= 9.8 * dt
        }

        var landingSpeed: Float = 0
        // 🌊 Al emerger a la superficie del posito de 14 cm (y >= -0.15m), desembarcar en el posito
        if proposed.y >= -0.15 {
            enteredEasterEggViaToboggan = false
        }
        proposed.y += verticalVelocity * dt

        // 🧱 Techo sólido del salón (altura 6.5m): previene atravesar el techo
        if proposed.y >= 6.40 {
            proposed.y = 6.40
            verticalVelocity = min(0, verticalVelocity)
        }

        let isInsideShaft = proposed.x >= -5.15 && proposed.x <= 2.15 && proposed.z >= -3.95 && proposed.z <= 0.95

        if isSlidingOnToboggan {
            proposed = playerPosition
        } else if proposed.y < -0.20 {
            // 🌊 ZONA SUBACUÁTICA: Pozo de agua y cámara subterránea colosal
            // 1. Piso abisal (Y = -11.0m)
            if proposed.y <= -11.0 {
                proposed.y = -11.0
                verticalVelocity = max(0, verticalVelocity)
            }

            // 2. 🧱 TECHO SÓLIDO SUBTERRÁNEO (Piscina Subterránea)
            // El techo visual está centrado en Y = -4.70m con espesor 0.25m -> base del techo en Y = -4.825m.
            // La altura de la cabeza del personaje sobre los pies es de 1.60m (ojos a y + 1.56m).
            // Para que la cabeza colisione físicamente contra el techo sin atravesarlo:
            // maxPiesY = -4.825 - 1.58 = -6.405m.
            let maxSubCeilingY: Float = -6.40

            if !isInsideShaft {
                // Fuera del hueco central del pozo, HAY TECHO SÓLIDO HERMÉTICO
                if proposed.y >= maxSubCeilingY {
                    proposed.y = maxSubCeilingY
                    if verticalVelocity > 0 {
                        verticalVelocity = 0
                        audio.playWaterDisturbance(intensity: 0.35)
                    }
                }
                // Asistencia de orientación: si nada hacia arriba cerca del techo, guiar suavemente hacia el pozo (-1.5, -1.5)
                if proposed.y >= -6.75 && verticalVelocity >= 0 {
                    let shaftCenter = SIMD2<Float>(-1.5, -1.5)
                    let currentXZ = SIMD2<Float>(proposed.x, proposed.z)
                    let diff = shaftCenter - currentXZ
                    let dist = simd_length(diff)
                    if dist > 0.25 {
                        let dir = diff / dist
                        proposed.x += dir.x * dt * 2.2
                        proposed.z += dir.y * dt * 2.2
                    }
                }
            } else {
                // Dentro del hueco del pozo, puede ascender hacia la superficie (-0.14m).
                // Pero mientras esté dentro del tiro vertical del pozo (-6.40 < y < -0.20),
                // las paredes del pozo contienen al jugador herméticamente para no salir al vacío:
                if proposed.y > maxSubCeilingY && proposed.y < -0.20 {
                    proposed.x = max(-5.05, min(2.05, proposed.x))
                    proposed.z = max(-3.85, min(0.85, proposed.z))
                }
            }

            // 3. Paredes perimetrales de la cámara subterránea colosal (36m x 36m)
            proposed.x = max(-17.0, min(17.0, proposed.x))
            proposed.z = max(-17.0, min(17.0, proposed.z))
        } else if currentlyInPool && !willBeOnFloat {
            // 🧱 Fondo cerámico SÓLIDO: sin importar la velocidad de caída, nunca se atraviesa
            if proposed.y <= nextGroundHeight {
                proposed.y = nextGroundHeight
                verticalVelocity = max(0, verticalVelocity)
            }
        } else if proposed.y <= nextGroundHeight {
            if !wasGrounded && !isCoverActive && verticalVelocity < -1.2 {
                landingSpeed = -verticalVelocity
            }
            proposed.y = nextGroundHeight
            verticalVelocity = 0
        }
        playerPosition = proposed
        reportNearbyLightIfNeeded()
        _ = waterImmersion(
            at: playerPosition,
            insidePool: willBeInPool
        )

        let isPlayerCurrentlyInWater = willBeInPool && !willBeOnFloat
        let enteredWaterThisFrame = isPlayerCurrentlyInWater && !wasPlayerInWater
        if enteredWaterThisFrame {
            let entryIntensity = min(1, max(0.38, -verticalVelocity / 3.8))
            pendingWaterImpulse = SIMD4<Float>(playerPosition.x, playerPosition.z, -1.05, 1)
            audio.playWaterDisturbance(intensity: entryIntensity)
        }
        wasPlayerInWater = isPlayerCurrentlyInWater

        if landingSpeed > 0 && !enteredWaterThisFrame && !isPlayerCurrentlyInWater {
            let impact = min(1, max(0.15, (landingSpeed - 1.0) / 4.2))
            audio.playLanding(intensity: impact)
        }

        let isAimingOrFiringTool = (heldTool == .laser && laserActiveRemaining > 0) || (heldTool == .mirror && mirrorActiveRemaining > 0)
        if cameraMode == .firstPerson {
            playerYaw = cameraYaw + .pi
        } else if isAimingOrFiringTool && !isCoverActive {
            // 🎯 Disparo y apuntado en 3ra persona: orientar el cuerpo hacia la retícula de disparo para que el arma siempre apunte al frente
            let aimYaw = cameraYaw + .pi
            let deltaAim = atan2(sin(aimYaw - playerYaw), cos(aimYaw - playerYaw))
            playerYaw += deltaAim * min(1.0, dt * 26.0)
        } else if magnitude > 0.08 {
            let targetYaw = atan2(desiredDirection.x, desiredDirection.y)
            let delta = atan2(sin(targetYaw - playerYaw), cos(targetYaw - playerYaw))
            playerYaw += delta * min(1, dt * 11)

            // 🎥 Cámara Lakitu 3D Auto-Follow: Persigue suavemente por la espalda al personaje en 3ra persona
            if manualCameraTimer <= 0 {
                let desiredCameraYaw = playerYaw + .pi
                let deltaCam = atan2(sin(desiredCameraYaw - cameraYaw), cos(desiredCameraYaw - cameraYaw))
                let followSpeed: Float = isPlayerCurrentlyInWater ? 3.8 : 2.8
                cameraYaw += deltaCam * min(1.0, dt * followSpeed)
            }
        }

        let speed = simd_length(horizontalVelocity)
        let isGrounded = playerPosition.y <= nextGroundHeight + 0.015
        if currentlyInPool && !currentlyOnFloat && playerPosition.y >= -0.25 && (speed > 0.04 || magnitude > 0.08) {
            playerWaterWakeCountdown -= dt
            if playerWaterWakeCountdown <= 0 {
                pendingWaterImpulse = SIMD4<Float>(
                    playerPosition.x,
                    playerPosition.z,
                    -1.45,
                    1
                )
                playerWaterWakeCountdown = 0.38 // Cadencia de ondulación visual en la superficie
            }
        } else {
            playerWaterWakeCountdown = 0
        }
        let floatWaterMovement = min(0.72, max(0, (simd_length(floatVelocity) - 0.04) / 0.95))
        let waterMovementIntensity: Float = currentlyInPool ? max(min(1.0, speed / 1.5), floatWaterMovement) : 0
        let waterStateChanged = (waterMovementIntensity > 0.01) !=
            (lastSubmittedWaterMovementIntensity > 0.01)
        if waterStateChanged ||
            abs(waterMovementIntensity - lastSubmittedWaterMovementIntensity) >= 0.025 {
            lastSubmittedWaterMovementIntensity = waterMovementIntensity
            audio.setWaterMovementIntensity(waterMovementIntensity)
        }
        if !currentlyInPool && lastSubmittedWaterMovementIntensity > 0 {
            lastSubmittedWaterMovementIntensity = 0
            audio.setWaterMovementIntensity(0)
        }
        let glideIntensity: Float = (!willBeInPool || willBeOnFloat) && isGrounded
            ? min(1, speed / 3.6)
            : 0
        let glideStateChanged = (glideIntensity > 0.01) != (lastSubmittedGlideIntensity > 0.01)
        if glideStateChanged || abs(glideIntensity - lastSubmittedGlideIntensity) >= 0.035 {
            lastSubmittedGlideIntensity = glideIntensity
            audio.setGlideIntensity(glideIntensity)
        }
    }

    private var isMirrorReflectingLaser = false
    private var mirrorReflectHitCooldowns = [Float](repeating: 0, count: 5)

    private func updateToolTimers(dt: Float) {
        if laserCooldownRemaining > 0 { laserCooldownRemaining = max(0, laserCooldownRemaining - dt) }
        if mirrorCooldownRemaining > 0 { mirrorCooldownRemaining = max(0, mirrorCooldownRemaining - dt) }
        for i in mirrorReflectHitCooldowns.indices where mirrorReflectHitCooldowns[i] > 0 {
            mirrorReflectHitCooldowns[i] = max(0, mirrorReflectHitCooldowns[i] - dt)
        }

        if heldTool != lastHeldTool {
            lastHeldTool = heldTool
            if heldTool == .laser {
                laserPropagationDistance = 0.0
                if laserBattery > 0.02 {
                    audio.playLaserIgnition()
                }
            } else if heldTool == .mirror && !mirrorOverheated {
                audio.playLaserReflectionSound()
            }
        }

        // ⚡ GESTIÓN DE BATERÍA DEL LÁSER (TEMPORAL)
        if heldTool == .laser {
            if laserBattery > 0.005 {
                laserBattery = max(0.0, laserBattery - dt / 16.0)
                laserActiveRemaining = 10.0
                if isSlowMotionActive {
                    laserPropagationDistance += dt * 14.0
                } else {
                    laserPropagationDistance = 100.0
                }
            } else {
                laserBattery = 0.0
                laserActiveRemaining = 0.0
            }

            // Daño a dummies de entrenamiento solo si la batería no está agotada
            if laserBattery > 0.005 {
                let origin = smoothedCameraTarget
                let forward = lastCameraForward
                for i in dummyPositions.indices where dummyAlive[i] {
                    let center = dummyPositions[i] + SIMD3<Float>(0, 0.85, 0)
                    let toCenter = center - origin
                    let proj = simd_dot(toCenter, forward)
                    if proj > 0 && proj < 22.0 {
                        let closest = origin + forward * proj
                        if simd_distance(center, closest) < 0.70 {
                            dummyAlive[i] = false
                            audio.playLightsaberDefeatSound()
                            onScoreUpdate?(300)
                        }
                    }
                }
            }
        } else {
            // Recarga gradual de la batería del láser cuando no está en uso
            laserBattery = min(1.0, laserBattery + dt / 10.0)
            laserActiveRemaining = 0.0
        }
        onLaserBatteryUpdate?(laserBattery)

        // 🛡️🔥 GESTIÓN TÉRMICA DEL ESCUDO ESPEJO (SE CALIENTA Y DISIPA)
        if heldTool == .mirror {
            if mirrorOverheated {
                mirrorActiveRemaining = 0.0
                // Enfriamiento tras sobrecalentamiento
                mirrorHeat = max(0.0, mirrorHeat - dt / 3.5)
                if mirrorHeat <= 0.05 {
                    mirrorOverheated = false
                }
            } else {
                // Calentamiento progresivo por mantener activo el escudo de fotones (modo pasivo)
                mirrorHeat = min(1.0, mirrorHeat + dt / 16.0)
                if mirrorHeat >= 1.0 {
                    mirrorOverheated = true
                    mirrorActiveRemaining = 0.0
                    audio.playLightsaberDefeatSound()
                } else {
                    mirrorActiveRemaining = 10.0
                }
            }
        } else {
            // Disipación térmica rápida al guardar o bajar el espejo
            mirrorHeat = max(0.0, mirrorHeat - dt / 3.0)
            if mirrorOverheated && mirrorHeat <= 0.05 {
                mirrorOverheated = false
            }
            mirrorActiveRemaining = 0.0
        }
        onMirrorHeatUpdate?(mirrorHeat, mirrorOverheated)

        // 🔦 GESTIÓN DE BATERÍA DE LA LINTERNA
        if heldTool == .flashlight {
            flashlightBattery = max(0.0, flashlightBattery - dt / 50.0)
        } else {
            flashlightBattery = min(1.0, flashlightBattery + dt / 22.0)
        }
        onFlashlightBatteryUpdate?(flashlightBattery)

        toolStatusCountdown -= dt
        if toolStatusCountdown <= 0 {
            toolStatusCountdown = 0.08
            let active: Float
            let cooldown: Float
            switch heldTool {
            case .flashlight:
                active = flashlightBattery; cooldown = 0
            case .laser:
                active = laserBattery; cooldown = laserBattery <= 0.01 ? 1.0 : 0
            case .mirror:
                active = max(0.0, 1.0 - mirrorHeat); cooldown = mirrorOverheated ? 1.0 : 0
            default:
                active = 0; cooldown = 0
            }
            let label: String
            if heldTool == .laser {
                if laserBattery <= 0.01 {
                    label = "⚠️ Batería láser agotada"
                } else {
                    label = String(format: "Batería Láser %d%%", Int((laserBattery * 100).rounded()))
                }
            } else if heldTool == .mirror {
                if mirrorOverheated {
                    label = String(format: "🔥 SOBRECALENTADO (Enfriando %d%%)", Int((mirrorHeat * 100).rounded()))
                } else {
                    label = String(format: "Calor Espejo %d%%", Int((mirrorHeat * 100).rounded()))
                }
            } else if heldTool == .flashlight {
                label = String(format: "Batería Linterna %d%%", Int((flashlightBattery * 100).rounded()))
            } else {
                label = ""
            }
            onToolStatusUpdate?(GameToolStatus(activeRemaining: active, cooldownRemaining: cooldown, label: label))
        }
    }

    private func recordBotElimination() {
        botsKilledInCurrentWave += 1
        let remainingQuota = max(0, totalBotsInWave - botsKilledInCurrentWave)

        // 🛡️ CONDICIÓN DE VICTORIA ESTRICTA:
        // Una oleada SOLO termina si la cuota de bajas se cumplió Y ningún enemigo activo sigue vivo en el mapa.
        let activeAliveBots = npcPositions.indices.filter({ npcHealths[$0] > 0 && npcRespawnTimers[$0] <= 0 }).count

        if remainingQuota <= 0 && activeAliveBots == 0 {
            // 🏆 Victoria de Campaña al superar la Oleada 15
            if currentWave == 15 {
                onCampaignVictory?()
            }
            // Wave TRULY cleared! Trigger 10-second intermission rest
            isWaveIntermission = true
            intermissionTimeRemaining = 10.0
            for i in npcPositions.indices {
                currentBotLaserStarts[i] = .zero
                currentBotLaserEnds[i] = .zero
                botLaserActiveTimers[i] = 0
                botLaserPropagationDistances[i] = 0
            }
            let res = laserResultBuffer.contents().assumingMemoryBound(to: RTLaserResult.self)
            res.pointee.bot0Start = .zero; res.pointee.bot0End = .zero
            res.pointee.bot1Start = .zero; res.pointee.bot1End = .zero
            res.pointee.bot2Start = .zero; res.pointee.bot2End = .zero
            res.pointee.bot3Start = .zero; res.pointee.bot3End = .zero
            res.pointee.bot4Start = .zero; res.pointee.bot4End = .zero

            if isRecoveringInChamber {
                isRecoveringInChamber = false
                recoveryTimeRemaining = 0
                onRecoveryCompleted?()
            }
            audio.playLaserReflectionSound()
            onScoreUpdate?(500)
            onRemoteNPCEliminated?(500)
            onDamageTaken?(-25.0) // Health regen rest reward (+25 HP)
            onWaveUpdate?(currentWave, 0, totalBotsInWave, true, 10.0)
        } else {
            let displayedRemaining = max(activeAliveBots, remainingQuota)
            onWaveUpdate?(currentWave, displayedRemaining, totalBotsInWave, false, 0)
        }

        if isAuthorityForNPCs {
            let displayedRemaining = (remainingQuota <= 0 && activeAliveBots == 0) ? 0 : max(activeAliveBots, remainingQuota)
            onNPCSyncUpdate?(npcPositions, npcHealths, currentWave, displayedRemaining, totalBotsInWave, isWaveIntermission, max(0, intermissionTimeRemaining), currentBotLaserStarts, currentBotLaserEnds)
        }
    }

    private func handleNPCElimination(index: Int) {
        guard index >= 0 && index < npcPositions.count else { return }
        if index >= 2 || currentWave >= 3 {
            onColossusDefeated?()
        }
        // Guardar posición de muerte en el piso e iniciar animación de derretimiento líquido (Melt)
        npcDeathPositions[index] = SIMD3<Float>(npcPositions[index].x, max(0.0, npcPositions[index].y), npcPositions[index].z)
        npcMeltProgress[index] = 0.01

        // Cortar de inmediato cualquier láser activo y limpiar coordenadas para que no floten en el aire
        botLaserActiveTimers[index] = 0
        botLaserPropagationDistances[index] = 0
        currentBotLaserStarts[index] = .zero
        currentBotLaserEnds[index] = .zero
        let results = laserResultBuffer.contents().assumingMemoryBound(to: RTLaserResult.self)
        switch index {
        case 0: results.pointee.bot0Start = .zero; results.pointee.bot0End = .zero
        case 1: results.pointee.bot1Start = .zero; results.pointee.bot1End = .zero
        case 2: results.pointee.bot2Start = .zero; results.pointee.bot2End = .zero
        case 3: results.pointee.bot3Start = .zero; results.pointee.bot3End = .zero
        case 4: results.pointee.bot4Start = .zero; results.pointee.bot4End = .zero
        default: break
        }

        // Ensure dead NPC health is zeroed and notified to HUD
        npcHealths[index] = 0
        onNPCHealthsUpdate?(npcHealths)

        if botsSpawnedInCurrentWave < totalBotsInWave {
            botsSpawnedInCurrentWave += 1
            npcRespawnTimers[index] = 4.2
        } else {
            npcRespawnTimers[index] = 9999.0
        }
        npcPositions[index].y = -10
        audio.playLightsaberDefeatSound()
        recordBotElimination()

        if isAuthorityForNPCs {
            let activeAliveBots = npcPositions.indices.filter({ npcHealths[$0] > 0 && npcRespawnTimers[$0] <= 0 }).count
            let remainingQuota = max(0, totalBotsInWave - botsKilledInCurrentWave)
            let remaining = max(activeAliveBots, remainingQuota)
            onNPCSyncUpdate?(npcPositions, npcHealths, currentWave, remaining, totalBotsInWave, isWaveIntermission, max(0, intermissionTimeRemaining), currentBotLaserStarts, currentBotLaserEnds)
        }
    }

    func applyRemoteNPCSync(
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
        guard !isAuthorityForNPCs else { return }
        self.syncedNPCNetworkPositions = positions
        for i in 0..<min(healths.count, npcHealths.count) {
            let prevHealth = npcHealths[i]
            npcHealths[i] = healths[i]
            if healths[i] <= 0 {
                if prevHealth > 0 {
                    npcDeathPositions[i] = SIMD3<Float>(npcPositions[i].x, max(0.0, npcPositions[i].y), npcPositions[i].z)
                    npcMeltProgress[i] = 0.01
                    audio.playLightsaberDefeatSound()
                }
                npcRespawnTimers[i] = 9999.0
                npcPositions[i].y = -10
            } else {
                npcRespawnTimers[i] = 0
                npcMeltProgress[i] = 0
            }
        }
        self.currentWave = wave
        self.totalBotsInWave = total
        self.isWaveIntermission = isIntermission
        self.intermissionTimeRemaining = intermissionTime
        onNPCHealthsUpdate?(npcHealths)
        onWaveUpdate?(wave, remaining, total, isIntermission, intermissionTime)

        let results = laserResultBuffer.contents().assumingMemoryBound(to: RTLaserResult.self)
        if let starts = laserStarts, let ends = laserEnds {
            let makeLaserVec: (Int) -> (SIMD4<Float>, SIMD4<Float>) = { idx in
                guard idx < starts.count, idx < ends.count else { return (.zero, .zero) }
                // Si estamos en intermisión o el bot está muerto/inactivo en el cliente, jamás renderizar su láser
                if isIntermission || (idx < self.npcHealths.count && self.npcHealths[idx] <= 0) {
                    return (.zero, .zero)
                }
                let s = starts[idx]
                let e = ends[idx]
                // Validar que el rayo tenga origen real no en el origen nulo (0,0,0) y longitud visible (> 0.2m)
                if simd_length_squared(s) > 0.04 && simd_length_squared(s - e) > 0.04 {
                    return (SIMD4<Float>(s, 1.0), SIMD4<Float>(e, 1.0))
                }
                return (.zero, .zero)
            }
            let (b0s, b0e) = makeLaserVec(0); results.pointee.bot0Start = b0s; results.pointee.bot0End = b0e
            let (b1s, b1e) = makeLaserVec(1); results.pointee.bot1Start = b1s; results.pointee.bot1End = b1e
            let (b2s, b2e) = makeLaserVec(2); results.pointee.bot2Start = b2s; results.pointee.bot2End = b2e
            let (b3s, b3e) = makeLaserVec(3); results.pointee.bot3Start = b3s; results.pointee.bot3End = b3e
            let (b4s, b4e) = makeLaserVec(4); results.pointee.bot4Start = b4s; results.pointee.bot4End = b4e
        } else {
            results.pointee.bot0Start = .zero; results.pointee.bot0End = .zero
            results.pointee.bot1Start = .zero; results.pointee.bot1End = .zero
            results.pointee.bot2Start = .zero; results.pointee.bot2End = .zero
            results.pointee.bot3Start = .zero; results.pointee.bot3End = .zero
            results.pointee.bot4Start = .zero; results.pointee.bot4End = .zero
        }
    }

    func applyRemoteNPCDamage(index: Int, damage: Float) {
        guard isAuthorityForNPCs else { return }
        guard index >= 0 && index < npcPositions.count else { return }
        guard npcHealths[index] > 0 && npcRespawnTimers[index] <= 0 else { return }
        npcHealths[index] = max(0, npcHealths[index] - damage)
        onNPCHealthsUpdate?(npcHealths)
        if npcHealths[index] <= 0 {
            audio.playLaserPlayerHitSound()
            handleNPCElimination(index: index)
            onRemoteNPCEliminated?(250)
        } else {
            audio.playLaserPlayerHitSound()
        }
    }

    // 🛸 Centinelas Aéreos / Drones Voladores con Láser (Aparecen a partir de la Oleada 7)
    private func isBotFlyingDrone(index: Int) -> Bool {
        guard currentWave >= 7 else { return false }
        if currentWave == 7 {
            return index == 0
        } else if currentWave == 8 {
            return index == 0 || index == 1
        } else {
            return index == 0 || index == 1 || index == 2
        }
    }

    private func updateNPCSimulation(dt: Float, rawDt: Float) {
        if isVersusMode {
            // En modo Versus no hay bots; es un combate 1 vs 1 directo entre jugadores
            for index in npcPositions.indices {
                npcPositions[index] = SIMD3<Float>(0, -500, 0)
                npcHealths[index] = 0
                npcRespawnTimers[index] = 99999.0
            }
            for i in mirrorReflectHitCooldowns.indices {
                if mirrorReflectHitCooldowns[i] > 0 {
                    mirrorReflectHitCooldowns[i] = max(0, mirrorReflectHitCooldowns[i] - dt)
                }
            }
            let results = laserResultBuffer.contents().assumingMemoryBound(to: RTLaserResult.self)
            isMirrorReflectingLaser = false

            let isRivalFiring = isRemotePlayerConnected && remotePlayerHeldTool == .laser && !remotePlayerIsRecovering && remotePlayerIsFiringLaser
            if isRivalFiring {
                let rPos = smoothedRemotePos
                let rYaw = remotePlayerYaw
                let rForward = SIMD3<Float>(sin(rYaw), 0, cos(rYaw))
                let rRight = SIMD3<Float>(cos(rYaw), 0, -sin(rYaw))
                let rOrigin = rPos + SIMD3<Float>(0, 1.15, 0) + rRight * 0.28 + rForward * 0.35
                let rEnd = rOrigin + rForward * 32.0

                // Detección de intercepción con el escudo espejo del jugador local
                let effYaw = playerYaw + shieldYawOffset
                let baseMirrorPitch: Float = (cameraMode == .firstPerson) ? firstPersonPitch : -(orbitPitch - 0.22) * 1.15
                let effPitch = max(-0.95, min(0.95, baseMirrorPitch + shieldPitchOffset))

                let shieldCenter = playerPosition + SIMD3<Float>(sin(effYaw) * 0.58, 1.12 + sin(effPitch) * 0.25, cos(effYaw) * 0.58)
                let shieldNormal = simd_normalize(SIMD3<Float>(
                    sin(effYaw) * cos(effPitch),
                    sin(effPitch),
                    cos(effYaw) * cos(effPitch)
                ))

                let toShield = shieldCenter - rOrigin
                let alongRivalRay = simd_dot(toShield, rForward)
                let facingDot = simd_dot(-rForward, shieldNormal)
                let isMirrorReady = (heldTool == .mirror && mirrorActiveRemaining > 0)

                var intercepted = false
                if isMirrorReady && alongRivalRay > 0.3 && alongRivalRay < 32.0 && facingDot > -0.25 {
                    let closestPtOnRay = rOrigin + rForward * alongRivalRay
                    if simd_distance(closestPtOnRay, shieldCenter) < 1.35 {
                        intercepted = true
                    }
                }

                if intercepted {
                    isMirrorReflectingLaser = true
                    // El rayo rival choca y se corta en el escudo
                    results.pointee.bot0Start = SIMD4<Float>(rOrigin, 1.0)
                    results.pointee.bot0End = SIMD4<Float>(shieldCenter, 1.0)

                    // Rayo reflejado sale desde el escudo hacia shieldNormal
                    let refOrigin = shieldCenter
                    let refDir = shieldNormal
                    let refEnd = refOrigin + refDir * 32.0
                    results.pointee.bot1Start = SIMD4<Float>(refOrigin, 1.0)
                    results.pointee.bot1End = SIMD4<Float>(refEnd, 1.0)

                    // Daño reflejado de vuelta al rival si la mira del escudo apunta a él
                    let toRival = (smoothedRemotePos + SIMD3<Float>(0, 0.95, 0)) - refOrigin
                    let alongReflect = simd_dot(toRival, refDir)
                    if alongReflect > 0.4 && alongReflect < 32.0 {
                        let closestToRival = refOrigin + refDir * alongReflect
                        let clampedY = max(smoothedRemotePos.y + 0.15, min(smoothedRemotePos.y + 1.85, closestToRival.y))
                        let rivalBodyPt = SIMD3<Float>(smoothedRemotePos.x, clampedY, smoothedRemotePos.z)
                        if simd_distance(closestToRival, rivalBodyPt) < 1.15 {
                            if mirrorReflectHitCooldowns[0] <= 0 {
                                mirrorReflectHitCooldowns[0] = 0.25
                                audio.playLaserReflectionSound()
                                onRemotePlayerHit?(25.0)
                            }
                        }
                    }
                } else {
                    results.pointee.bot0Start = SIMD4<Float>(rOrigin, 1.0)
                    results.pointee.bot0End = SIMD4<Float>(rEnd, 1.0)
                    results.pointee.bot1Start = .zero
                    results.pointee.bot1End = .zero
                }
            } else {
                results.pointee.bot0Start = .zero
                results.pointee.bot0End = .zero
                results.pointee.bot1Start = .zero
                results.pointee.bot1End = .zero
            }
            results.pointee.bot2Start = .zero; results.pointee.bot2End = .zero
            results.pointee.bot3Start = .zero; results.pointee.bot3End = .zero
            results.pointee.bot4Start = .zero; results.pointee.bot4End = .zero
            return
        }

        let results = laserResultBuffer.contents().assumingMemoryBound(to: RTLaserResult.self)

        // Avanzar animación de disolución / derretimiento líquido (Melt) de bots eliminados
        for idx in npcMeltProgress.indices {
            if npcMeltProgress[idx] > 0 && npcMeltProgress[idx] < 1.0 {
                npcMeltProgress[idx] = min(1.0, npcMeltProgress[idx] + rawDt * 0.62)
            }
        }

        // Sincronización periódica de red (Host -> Cliente) a ~12 Hz
        if isAuthorityForNPCs {
            npcNetworkSyncCountdown -= dt
            if npcNetworkSyncCountdown <= 0 {
                npcNetworkSyncCountdown = 0.08
                let activeAliveBots = npcPositions.indices.filter({ npcHealths[$0] > 0 && npcRespawnTimers[$0] <= 0 }).count
                let remainingQuota = max(0, totalBotsInWave - botsKilledInCurrentWave)
                let remaining = max(activeAliveBots, remainingQuota)
                onNPCSyncUpdate?(npcPositions, npcHealths, currentWave, remaining, totalBotsInWave, isWaveIntermission, max(0, intermissionTimeRemaining), currentBotLaserStarts, currentBotLaserEnds)
            }
        } else {
            // Cliente: interpolar suavemente posiciones recibidas del Host y reflejar estados
            if isWaveIntermission {
                for index in npcPositions.indices {
                    npcPositions[index].y = -10
                }
            } else if let netPositions = syncedNPCNetworkPositions {
                for index in npcPositions.indices {
                    if npcHealths[index] <= 0 {
                        npcPositions[index].y = -10
                    } else if index < netPositions.count {
                        let target = netPositions[index]
                        let interp = min(1.0, dt * 18.0)
                        npcPositions[index] += (target - npcPositions[index]) * interp
                        let toPlayer = playerPosition - npcPositions[index]
                        if simd_length_squared(SIMD2<Float>(toPlayer.x, toPlayer.z)) > 0.04 {
                            npcYaws[index] = atan2(toPlayer.x, toPlayer.z)
                        }
                    }
                }
            }
            return
        }

        // Periodic wave status HUD sync
        waveStatusReportCountdown -= dt
        if waveStatusReportCountdown <= 0 {
            waveStatusReportCountdown = 0.25
            if isWaveIntermission {
                onWaveUpdate?(currentWave, 0, totalBotsInWave, true, max(0, intermissionTimeRemaining))
            } else {
                let activeAliveBots = npcPositions.indices.filter({ npcHealths[$0] > 0 && npcRespawnTimers[$0] <= 0 }).count
                let remainingQuota = max(0, totalBotsInWave - botsKilledInCurrentWave)
                let remaining = max(activeAliveBots, remainingQuota)
                onWaveUpdate?(currentWave, remaining, totalBotsInWave, false, 0)
            }
        }

        // Handle Intermission Rest State between waves
        if isWaveIntermission {
            intermissionTimeRemaining -= dt
            for i in npcPositions.indices {
                currentBotLaserStarts[i] = .zero
                currentBotLaserEnds[i] = .zero
                botLaserActiveTimers[i] = 0
                botLaserPropagationDistances[i] = 0
            }
            results.pointee.bot0Start = .zero; results.pointee.bot0End = .zero
            results.pointee.bot1Start = .zero; results.pointee.bot1End = .zero
            results.pointee.bot2Start = .zero; results.pointee.bot2End = .zero
            results.pointee.bot3Start = .zero; results.pointee.bot3End = .zero
            results.pointee.bot4Start = .zero; results.pointee.bot4End = .zero

            onWaveUpdate?(currentWave, 0, totalBotsInWave, true, max(0, intermissionTimeRemaining))
            if intermissionTimeRemaining <= 0 {
                isWaveIntermission = false
                currentWave += 1
                botsKilledInCurrentWave = 0
                totalBotsInWave = (currentWave == 1) ? 2 : ((currentWave == 2) ? 3 : ((currentWave == 3) ? 4 : (5 + (currentWave - 4) * 2)))
                botsSpawnedInCurrentWave = min(totalBotsInWave, npcPositions.count)
                audio.playLaserIgnition()
                if isRecoveringInChamber {
                    isRecoveringInChamber = false
                    recoveryTimeRemaining = 0
                    onRecoveryCompleted?()
                }
                for i in npcPositions.indices {
                    if i < botsSpawnedInCurrentWave {
                        npcPositions[i] = npcSpawnPositions[i % npcSpawnPositions.count]
                        npcHealths[i] = npcMaxHealths[i]
                        npcMeltProgress[i] = 0
                        npcRespawnTimers[i] = 0.5 + Float(i) * 0.4
                        botLaserActiveTimers[i] = 0
                        botLaserCooldownTimers[i] = 3.0 + Float(i) * 1.2
                        botTeleportReactionTimers[i] = 0
                        botAimTargets[i] = npcPositions[i] + SIMD3<Float>(0, 1.1, 0)
                    } else {
                        npcPositions[i] = SIMD3<Float>(0, -10, 0)
                        npcHealths[i] = 0
                        npcRespawnTimers[i] = 9999.0
                        npcMeltProgress[i] = 0
                        botLaserActiveTimers[i] = 0
                        botLaserCooldownTimers[i] = 9999.0
                        botTeleportReactionTimers[i] = 0
                    }
                }
                onNPCHealthsUpdate?(npcHealths)
                onWaveUpdate?(currentWave, totalBotsInWave, totalBotsInWave, false, 0)
            }
            // Hide NPCs during intermission rest
            for index in npcPositions.indices {
                npcPositions[index].y = -10
            }
            return
        }

        // Teleport reaction check: If player moved > 3.0m in 1 frame (teleport / exit portal), delay bots!
        let playerMovedDist = simd_distance(playerPosition, lastObservedPlayerPosForTeleportCheck)
        let playerTeleported = playerMovedDist > 3.0
        lastObservedPlayerPosForTeleportCheck = playerPosition

        if playerTeleported {
            for idx in npcPositions.indices {
                botTeleportReactionTimers[idx] = 0.85
                botLaserActiveTimers[idx] = 0
                botLaserCooldownTimers[idx] = max(botLaserCooldownTimers[idx], 1.2)
            }
        }

        isMirrorReflectingLaser = false

        // 🎖️ Coordinación Dinámica de Escuadra: Ordenar bots vivos por cercanía al objetivo
        let aliveBotIndices = npcPositions.indices.filter {
            npcHealths[$0] > 0 && npcRespawnTimers[$0] <= 0
        }
        let squadTargetRef = (isRemotePlayerConnected && !isVersusMode && isRecoveringInChamber && !remotePlayerIsRecovering) ? smoothedRemotePos : playerPosition
        let sortedAliveByDistance = aliveBotIndices.sorted { a, b in
            simd_distance_squared(npcPositions[a], squadTargetRef) < simd_distance_squared(npcPositions[b], squadTargetRef)
        }
        let totalAliveBots = aliveBotIndices.count

        for index in npcPositions.indices {
            switch index {
            case 0: results.pointee.bot0Start = .zero; results.pointee.bot0End = .zero
            case 1: results.pointee.bot1Start = .zero; results.pointee.bot1End = .zero
            case 2: results.pointee.bot2Start = .zero; results.pointee.bot2End = .zero
            case 3: results.pointee.bot3Start = .zero; results.pointee.bot3End = .zero
            case 4: results.pointee.bot4Start = .zero; results.pointee.bot4End = .zero
            default: break
            }

            if npcRespawnTimers[index] > 0 || npcHealths[index] <= 0 {
                if npcRespawnTimers[index] > 0 {
                    npcRespawnTimers[index] = max(0, npcRespawnTimers[index] - dt)
                    npcPositions[index].y = -10
                    if npcRespawnTimers[index] == 0 {
                        npcPositions[index] = npcSpawnPositions[index]
                        npcHealths[index] = npcMaxHealths[index]
                        npcMeltProgress[index] = 0
                        botAimTargets[index] = npcSpawnPositions[index] + SIMD3<Float>(0, 1.1, 0)
                        botLaserCooldownTimers[index] = 2.0 + Float(index) * 1.2
                        botLaserActiveTimers[index] = 0
                        botTeleportReactionTimers[index] = 0
                    }
                }
                currentBotLaserStarts[index] = .zero
                currentBotLaserEnds[index] = .zero
                botLaserActiveTimers[index] = 0
                botLaserPropagationDistances[index] = 0
                continue
            }

            if botTeleportReactionTimers[index] > 0 {
                botTeleportReactionTimers[index] = max(0, botTeleportReactionTimers[index] - dt)
            }

            let playerHiddenInEasterEgg = playerPosition.y < -3.0
            if playerHiddenInEasterEgg {
                // NPCs cannot see player hidden in underwater realm!
                npcYaws[index] += sin(dt * Float(index + 1)) * 0.8 * dt
                currentBotLaserStarts[index] = .zero
                currentBotLaserEnds[index] = .zero
                botLaserActiveTimers[index] = 0
                continue
            }

            // En multijugador, el bot persigue al jugador vivo más cercano
            let targetPos: SIMD3<Float>
            let isTargetingRemote: Bool
            if isRemotePlayerConnected && !isVersusMode {
                if isRecoveringInChamber && !remotePlayerIsRecovering {
                    targetPos = smoothedRemotePos
                    isTargetingRemote = true
                } else if remotePlayerIsRecovering {
                    targetPos = playerPosition
                    isTargetingRemote = false
                } else {
                    let dLocal = simd_distance_squared(npcPositions[index], playerPosition)
                    let dRemote = simd_distance_squared(npcPositions[index], smoothedRemotePos)
                    if dRemote < dLocal {
                        targetPos = smoothedRemotePos
                        isTargetingRemote = true
                    } else {
                        targetPos = playerPosition
                        isTargetingRemote = false
                    }
                }
            } else {
                targetPos = playerPosition
                isTargetingRemote = false
            }

            let offset = SIMD2<Float>(
                targetPos.x - npcPositions[index].x,
                targetPos.z - npcPositions[index].z
            )
            let distance = simd_length(offset)
            let rawDirection = distance > 0.001 ? offset / distance : SIMD2<Float>(0, 1)

            let isFlying = isBotFlyingDrone(index: index)

            // Dynamic difficulty scaling per wave
            let speed: Float
            if isFlying {
                speed = min(4.8, 2.4 + Float(currentWave) * 0.28)
            } else {
                speed = min(3.8, 1.4 + Float(currentWave) * 0.25 + Float(index == 0 ? 0.35 : 0.10))
            }
            let botCooldown: Float = max(2.2, 5.5 - Float(currentWave) * 0.50)
            let aimSpeedScale: Float = min(10.0, 3.5 + Float(currentWave) * 0.75)

            // 🎖️ Rol Táctico Dinámico de Escuadra: Determinado por cercanía relativa entre los bots vivos
            let dynamicRoleIndex = sortedAliveByDistance.firstIndex(of: index) ?? 0
            let isColossalGolem = (index == 4 && currentWave >= 3)

            // Distancias óptimas según rol táctico dinámico:
            // Rol 0 (Asaltante de Punta): Presión directa a 6.2m
            // Rol 1 (Atajador / Interceptor): Flanqueo de intercepción a 8.5m
            // Rol 2 (Hostigador de Apoyo): Cobertura media a 11.0m
            // Rol 3+ / Gólem: Cerco perimetral envolvente (13.5m)
            let idealDist: Float = isColossalGolem ? 13.5 : (dynamicRoleIndex == 0 ? 6.2 : (dynamicRoleIndex == 1 ? 8.5 : (dynamicRoleIndex == 2 ? 11.0 : 13.0)))
            let minSafeDist: Float = max(3.2, idealDist - 1.5)
            let maxComfortDist: Float = idealDist + 2.0

            let orbitSign: Float = (dynamicRoleIndex % 2 == 0) ? 1.0 : -1.0
            let lateralTangent = SIMD2<Float>(-rawDirection.y * orbitSign, rawDirection.x * orbitSign)
            var tacticalDesiredDir: SIMD2<Float>

            let botInRainbow = npcPositions[index].z > 17.8
            let playerInRainbow = targetPos.z > 17.8
            if isFlying {
                // 🛸 Comportamiento táctico aéreo: órbita circular flotante y pasadas de ataque desde las alturas
                let flyOrbitSign: Float = (index % 2 == 0) ? 1.0 : -1.0
                let flyTangent = SIMD2<Float>(-rawDirection.y * flyOrbitSign, rawDirection.x * flyOrbitSign)
                let idealFlyDist: Float = (index == 0) ? 7.2 : 9.5
                if distance > idealFlyDist + 2.0 {
                    tacticalDesiredDir = simd_normalize(rawDirection * 0.65 + flyTangent * 0.75)
                } else if distance < idealFlyDist - 1.5 {
                    tacticalDesiredDir = simd_normalize(-rawDirection * 0.70 + flyTangent * 0.70)
                } else {
                    tacticalDesiredDir = flyTangent
                }
            } else if botInRainbow != playerInRainbow && abs(npcPositions[index].x) > 3.6 {
                // 🌈 Si el jugador cruzó al otro salón (Piscina <-> Salón Arcoíris), el bot se dirige primero al Gran Pórtico (X = 0, Z = 17.8)
                let portalTarget = SIMD2<Float>(0.0, playerInRainbow ? 20.5 : 15.0)
                let toPortal = portalTarget - SIMD2<Float>(npcPositions[index].x, npcPositions[index].z)
                let pLen = simd_length(toPortal)
                tacticalDesiredDir = pLen > 0.01 ? (toPortal / pLen) : rawDirection
            } else if distance < minSafeDist {
                // 🛡️ Si el jugador se acerca demasiado, retrocede en diagonal buscando línea de tiro
                tacticalDesiredDir = simd_normalize(-rawDirection * 0.75 + lateralTangent * 0.65)
            } else {
                switch dynamicRoleIndex {
                case 0:
                    // 🔴 ROL 0: ASALTANTE DE PUNTA (Point Attacker) - Presión frontal directa y ataque constante
                    tacticalDesiredDir = distance > maxComfortDist
                        ? simd_normalize(rawDirection * 0.85 + lateralTangent * 0.40)
                        : simd_normalize(rawDirection * 0.35 + lateralTangent * 0.90)
                case 1:
                    // 🩷 ROL 1: EL ATAJADOR (Interceptor / Flanker) - ¡Ataja! Corta el paso hacia donde huye o se mueve el jugador
                    let leadTime: Float = min(3.5, max(1.2, distance / max(1.0, speed)))
                    let interceptTarget = SIMD2<Float>(targetPos.x, targetPos.z) + horizontalVelocity * leadTime
                    let toIntercept = interceptTarget - SIMD2<Float>(npcPositions[index].x, npcPositions[index].z)
                    let intLen = simd_length(toIntercept)
                    let intDir = intLen > 0.01 ? (toIntercept / intLen) : rawDirection
                    // Corre hacia el punto de corte en semicírculo para emboscarlo
                    tacticalDesiredDir = distance > maxComfortDist
                        ? intDir
                        : simd_normalize(intDir * 0.50 + lateralTangent * 0.85)
                case 2:
                    // 🩵 ROL 2: HOSTIGADOR DE COBERTURA (Support / Suppression) - Mantiene línea de tiro lateral
                    let playerLook2D = SIMD2<Float>(sin(playerYaw), cos(playerYaw))
                    let playerLookingAtBot = simd_dot(playerLook2D, -rawDirection) > 0.70
                    if playerLookingAtBot {
                        tacticalDesiredDir = simd_normalize(lateralTangent * 0.85 - rawDirection * 0.45)
                    } else {
                        tacticalDesiredDir = distance > maxComfortDist ? rawDirection : lateralTangent * 0.80
                    }
                default:
                    // 🌑 ROL 3+: CERCO PERIMETRAL ENVOLVENTE
                    tacticalDesiredDir = distance > maxComfortDist
                        ? simd_normalize(rawDirection * 0.70 + lateralTangent * 0.70)
                        : lateralTangent
                }
            }

            // 🪨 Dynamic Rock Evasion & Flanking Steering:
            var moveDirection = tacticalDesiredDir
            let botPos2D = SIMD2<Float>(npcPositions[index].x, npcPositions[index].z)
            var strongestAvoidance = SIMD2<Float>.zero
            var maxAvoidanceWeight: Float = 0

            for rock in rtRiverRocks {
                guard npcPositions[index].y < rock.center.y + rock.radii.y + 0.50 else { continue }
                let rockCenter2D = SIMD2<Float>(rock.center.x, rock.center.z)
                let toRock = rockCenter2D - botPos2D
                let distToRock = simd_length(toRock)
                let rockRadius = max(rock.radii.x, rock.radii.z) + 0.42

                guard distToRock > 0.001 else { continue }
                let dirToRock = toRock / distToRock

                let isNearRock = distToRock < (rockRadius + 0.35)
                let forwardDot = simd_dot(tacticalDesiredDir, dirToRock)
                let isHeadingIntoRock = forwardDot > 0.10 && distToRock < (rockRadius + 2.4)

                if isNearRock || isHeadingIntoRock {
                    // Compute tangents clockwise and counter-clockwise around the rock
                    let tangentL = SIMD2<Float>(-dirToRock.y, dirToRock.x)
                    let tangentR = SIMD2<Float>(dirToRock.y, -dirToRock.x)

                    let dotL = simd_dot(tangentL, tacticalDesiredDir)
                    let dotR = simd_dot(tangentR, tacticalDesiredDir)
                    let chosenTangent = (dotL >= dotR) ? tangentL : tangentR

                    let normalAway = -dirToRock
                    let steer = isNearRock
                        ? simd_normalize(chosenTangent * 0.82 + normalAway * 0.45)
                        : chosenTangent

                    let weight: Float = isNearRock ? 1.0 : max(0, min(1.0, 1.0 - (distToRock - rockRadius) / 2.4))
                    if weight > maxAvoidanceWeight {
                        maxAvoidanceWeight = weight
                        strongestAvoidance = steer
                    }
                }
            }

            if maxAvoidanceWeight > 0 {
                let blend = min(0.96, maxAvoidanceWeight * 0.92)
                moveDirection = simd_normalize(tacticalDesiredDir * (1.0 - blend) + strongestAvoidance * blend)
            }

            // 🧱 Evasión de Muros Perimetrales y Salientes para la IA (evita que los bots choquen de frente o queden atrapados al huir):
            let inRainbowRoom = npcPositions[index].z > 17.8
            let wallMinX: Float = inRainbowRoom ? -27.0 : -17.8
            let wallMaxX: Float = inRainbowRoom ?  27.0 :  17.8
            let wallMinZ: Float = inRainbowRoom ?  17.8 : -17.8
            let wallMaxZ: Float = inRainbowRoom ?  72.0 :  17.8
            let wallBuffer: Float = 2.6

            var wallInward = SIMD2<Float>.zero
            let dWest = botPos2D.x - wallMinX
            if dWest < wallBuffer {
                wallInward.x += (wallBuffer - dWest) / wallBuffer
            }
            let dEast = wallMaxX - botPos2D.x
            if dEast < wallBuffer {
                wallInward.x -= (wallBuffer - dEast) / wallBuffer
            }
            let dNorth = botPos2D.y - wallMinZ
            if dNorth < wallBuffer {
                let atPortal = abs(botPos2D.x) <= 4.8
                if !inRainbowRoom || !atPortal {
                    wallInward.y += (wallBuffer - dNorth) / wallBuffer
                }
            }
            let dSouth = wallMaxZ - botPos2D.y
            if dSouth < wallBuffer {
                let atPortal = abs(botPos2D.x) <= 4.8
                if inRainbowRoom || !atPortal {
                    wallInward.y -= (wallBuffer - dSouth) / wallBuffer
                }
            }

            if simd_length_squared(wallInward) > 0.0001 {
                let wallNormal = simd_normalize(wallInward)
                let headingIntoWall = simd_dot(moveDirection, wallNormal) < 0.20
                if headingIntoWall {
                    let t1 = SIMD2<Float>(-wallNormal.y, wallNormal.x)
                    let t2 = -t1
                    let wallTangent = (simd_dot(t1, lateralTangent) >= simd_dot(t2, lateralTangent)) ? t1 : t2
                    let wallWeight = min(1.0, simd_length(wallInward))
                    let wallSteer = simd_normalize(wallTangent * 0.78 + wallNormal * 0.55)
                    moveDirection = simd_normalize(moveDirection * (1.0 - wallWeight * 0.85) + wallSteer * (wallWeight * 0.85))
                }
            }

            // Cuando el bot está disparando activamente, planta los pies para apuntar con precisión
            let stepFactor: Float = (botLaserActiveTimers[index] > 0 && distance >= minSafeDist) ? 0.22 : 1.0
            var proposedX = npcPositions[index].x + (moveDirection.x * speed * stepFactor + npcPushVelocities[index].x) * dt
            var proposedZ = npcPositions[index].z + (moveDirection.y * speed * stepFactor + npcPushVelocities[index].y) * dt
            npcPushVelocities[index] *= exp(-dt * 7.5)

            // Solid Pool Coping Wall Colliders for NPCs
            let isInsidePool = proposedX >= -5.60 && proposedX <= 2.60 && proposedZ >= -4.45 && proposedZ <= 1.45
            let wasInsidePool = npcPositions[index].x >= -5.60 && npcPositions[index].x <= 2.60 && npcPositions[index].z >= -4.45 && npcPositions[index].z <= 1.45
            if !wasInsidePool && isInsidePool && npcPositions[index].y < 0.2 {
                proposedX = npcPositions[index].x
                proposedZ = npcPositions[index].z
                npcPushVelocities[index] *= -0.35
            }

            // 🤝 Separación amplia Bot contra Bot (para que rodeen el mapa desde distintos ángulos sin amontonarse)
            let minBotSeparation: Float = 2.60
            for otherIdx in npcPositions.indices where otherIdx != index && npcHealths[otherIdx] > 0 && npcRespawnTimers[otherIdx] <= 0 {
                let toSelf = SIMD2<Float>(proposedX - npcPositions[otherIdx].x, proposedZ - npcPositions[otherIdx].z)
                let botDist = simd_length(toSelf)
                if botDist < minBotSeparation {
                    let sepDir = botDist > 0.001 ? toSelf / botDist : SIMD2<Float>(cos(Float(index)), sin(Float(index)))
                    let overlap = minBotSeparation - botDist
                    proposedX += sepDir.x * (overlap * 0.50)
                    proposedZ += sepDir.y * (overlap * 0.50)
                }
            }

            // 🤜🤛 Separación física de cuerpos entre Bot y Jugador (evitar solapamiento de cápsulas sin teletransportes)
            let minPhysicalSeparation: Float = isColossalGolem ? 1.60 : 1.05
            if abs(playerPosition.y - npcPositions[index].y) < 1.85 {
                let toBot = SIMD2<Float>(proposedX - playerPosition.x, proposedZ - playerPosition.z)
                let playerDist = simd_length(toBot)
                if playerDist < minPhysicalSeparation && playerDist > 0.0001 {
                    let pushDir = toBot / playerDist
                    let overlap = minPhysicalSeparation - playerDist
                    proposedX += pushDir.x * overlap
                    proposedZ += pushDir.y * overlap
                }
            }

            // 🛸 Vuelo aéreo dinámico (3.5m a 4.8m sobre el suelo) o contacto con suelo
            if isFlying {
                let hoverBase: Float = (index == 0) ? 3.8 : ((index == 1) ? 4.3 : 3.5)
                let targetHoverY: Float = hoverBase + sin(elapsedTime * 2.5 + Float(index) * 1.8) * 0.45
                npcPositions[index].y += (targetHoverY - npcPositions[index].y) * min(1.0, dt * 3.5)
            } else {
                let inPool = isInsidePoolXZ(npcPositions[index]) && npcPositions[index].y <= 0.35
                let isSub = npcPositions[index].y <= -4.75
                let groundY = isSub ? -11.0 : groundHeight(at: npcPositions[index], insidePool: inPool)
                npcPositions[index].y += (groundY - npcPositions[index].y) * min(1.0, dt * 8.0)
            }

            // Apply Scenario Rock, Cabin & Arena Collisions to NPCs (los drones voladores planean por encima)
            var npcPos = SIMD3<Float>(proposedX, npcPositions[index].y, proposedZ)
            if !isFlying {
                resolveRockCollisions(position: &npcPos)
                resolveParkourAndCabinCollisions(position: &npcPos)
            }
            clampToArenaBounds(position: &npcPos, previousPosition: npcPositions[index], margin: 1.15)

            // Si el bot fue frenado por un muro, roca o estructura, anular la velocidad de empuje residual
            if abs(npcPos.x - proposedX) > 0.001 {
                npcPushVelocities[index].x = 0
            }
            if abs(npcPos.z - proposedZ) > 0.001 {
                npcPushVelocities[index].y = 0
            }

            proposedX = npcPos.x
            proposedZ = npcPos.z

            npcPositions[index].x = proposedX
            npcPositions[index].z = proposedZ
            npcYaws[index] = atan2(rawDirection.x, rawDirection.y)

            // Smooth human-like aim tracking & dispersion
            let actualPlayerCenter = targetPos + SIMD3<Float>(0, 1.10, 0)
            let pHorizSpeed = simd_length(horizontalVelocity)
            let wobbleTime = CACurrentMediaTime() * 3.2 + Double(index) * 2.1
            let dispersionScale = 0.08 + min(0.35, distance * 0.02 + pHorizSpeed * 0.04)
            let aimWobble = SIMD3<Float>(
                Float(sin(wobbleTime * 2.3)) * dispersionScale,
                Float(cos(wobbleTime * 1.9)) * (dispersionScale * 0.7),
                Float(sin(wobbleTime * 2.7)) * dispersionScale
            )
            let targetWithNoise = actualPlayerCenter + aimWobble
            
            // Aim tracking interpolation speed (human reaction curve)
            let aimSpeed = min(1.0, dt * (aimSpeedScale + Float(index) * 0.8))
            botAimTargets[index] += (targetWithNoise - botAimTargets[index]) * aimSpeed
            let currentAimTarget = botAimTargets[index]

            let targetIsUsingMirror = isTargetingRemote ? (remotePlayerHeldTool == .mirror) : (heldTool == .mirror && mirrorActiveRemaining > 0)

            // 🎯 Director Dinámico de Fuego de Escuadra:
            // Asegura que SIEMPRE haya al menos un bot atacando activamente mientras haya bots vivos
            let activeShootersCount = npcPositions.indices.filter {
                $0 != index && npcHealths[$0] > 0 && npcRespawnTimers[$0] <= 0 && botLaserActiveTimers[$0] > 0
            }.count
            let maxConcurrentShooters = (currentWave >= 4 && totalAliveBots >= 3) ? 2 : 1

            // 🔥 ALTERNANCIA DINÁMICA: Si ningún bot está disparando actualmente en la sala,
            // el asaltante de punta (Rol 0) o el atajador (Rol 1 si son 2) toma el token de ataque de inmediato
            if activeShootersCount == 0 && (dynamicRoleIndex == 0 || (dynamicRoleIndex == 1 && totalAliveBots <= 2)) {
                if botLaserCooldownTimers[index] > 0.35 && distance < 36.0 && botTeleportReactionTimers[index] <= 0 {
                    botLaserCooldownTimers[index] = 0.20 // Asume el ataque de inmediato
                }
            }

            let isTargetAlive = isTargetingRemote ? !remotePlayerIsRecovering : !isPlayerDead
            let botHandOrigin = npcPositions[index] + SIMD3<Float>(0.42, isFlying ? 0.35 : 0.88, 0.20)
            let targetCenter = targetPos + SIMD3<Float>(0, 1.10, 0)
            let bTotalDist = max(0.001, simd_distance(botHandOrigin, targetCenter))
            let bDir = simd_normalize(targetCenter - botHandOrigin)

            if !isTargetAlive {
                botLaserActiveTimers[index] = 0
                botLaserCooldownTimers[index] = 1.0
            } else if botInRainbow != playerInRainbow {
                // 🚫 El bot y el jugador están en salones separados por el muro y el espejo mágico (Z = 17.8).
                // Cortar cualquier disparo activo y esperar a cruzar el portal.
                botLaserActiveTimers[index] = 0
                botLaserCooldownTimers[index] = max(0.6, botLaserCooldownTimers[index])
                currentBotLaserStarts[index] = .zero
                currentBotLaserEnds[index] = .zero
            } else if botLaserCooldownTimers[index] > 0 {
                let cooldownRate: Float = (targetIsUsingMirror && distance < 22.0) ? 3.2 : 1.0
                botLaserCooldownTimers[index] = max(0, botLaserCooldownTimers[index] - dt * cooldownRate)
                let maxEngageDist: Float = (botInRainbow || playerInRainbow) ? 38.0 : 28.0
                if botLaserCooldownTimers[index] == 0 && distance < maxEngageDist && distance >= 1.2 && botTeleportReactionTimers[index] <= 0 {
                    // Verificar línea de visión libre antes de iniciar disparo
                    let los = findRayObstacleHit(from: botHandOrigin, to: targetCenter)
                    if !los.hit || los.hitDistance >= (distance - 0.45) {
                        if activeShootersCount < maxConcurrentShooters {
                            botLaserActiveTimers[index] = targetIsUsingMirror ? 2.6 : 1.9
                            botLaserPropagationDistances[index] = 0
                            botLaserOrigins[index] = botHandOrigin
                            botLaserDistancesToPlayer[index] = simd_distance(botLaserOrigins[index], currentAimTarget)
                        } else {
                            // Espera su turno de disparo mientras ataja / flanquea tácticamente
                            botLaserCooldownTimers[index] = 0.45 + Float(dynamicRoleIndex) * 0.20
                        }
                    } else {
                        // Obstruido por cobertura
                        botLaserCooldownTimers[index] = 0.35
                    }
                }
            } else if botLaserActiveTimers[index] > 0 && botTeleportReactionTimers[index] <= 0 {
                botLaserActiveTimers[index] = max(0, botLaserActiveTimers[index] - dt)

                // 🪨 Comprobar oclusión por Muro Divisor/Espejo (Z = 17.8), muros perimetrales, rocas y cabañas
                let obs = findRayObstacleHit(from: botHandOrigin, to: targetCenter)
                let hitObstacle = obs.hit && obs.hitDistance < (bTotalDist - 0.45)
                let closestHitDist = hitObstacle ? obs.hitDistance : bTotalDist
                let bEndActual = hitObstacle ? obs.hitPoint : (botHandOrigin + bDir * bTotalDist)

                let bProgress: Float = 1.0
                let startVec = SIMD4<Float>(botHandOrigin, 1.0)
                var endVec: SIMD4<Float> = .zero

                let effYaw = isTargetingRemote ? remotePlayerYaw : (playerYaw + shieldYawOffset)
                let baseMirrorPitch: Float = (cameraMode == .firstPerson) ? firstPersonPitch : -(orbitPitch - 0.22) * 1.15
                let effPitch = isTargetingRemote ? 0.0 : max(-0.95, min(0.95, baseMirrorPitch + shieldPitchOffset))

                let targetPlayerPos = isTargetingRemote ? smoothedRemotePos : playerPosition
                let shieldCenter = targetPlayerPos + SIMD3<Float>(sin(effYaw) * 0.58, 1.12 + sin(effPitch) * 0.25, cos(effYaw) * 0.58)
                let shieldNormal = simd_normalize(SIMD3<Float>(
                    sin(effYaw) * cos(effPitch),
                    sin(effPitch),
                    cos(effYaw) * cos(effPitch)
                ))
                let laserRayDir = bDir
                let facingDot = simd_dot(-laserRayDir, shieldNormal)

                let isUsingMirror = isTargetingRemote ? (remotePlayerHeldTool == .mirror) : (heldTool == .mirror && mirrorActiveRemaining > 0 && !mirrorOverheated)

                if isUsingMirror && !hitObstacle && facingDot > -0.20 {
                    if !isTargetingRemote {
                        isMirrorReflectingLaser = true
                        mirrorHeat = min(1.0, mirrorHeat + dt * 0.18)
                        if mirrorHeat >= 1.0 {
                            mirrorOverheated = true
                            mirrorActiveRemaining = 0.0
                            audio.playLightsaberDefeatSound()
                        }
                    }
                    // El rayo enemigo choca contra el escudo espejo
                    endVec = SIMD4<Float>(shieldCenter, 1.0)

                    // El rayo reflejado sale exactamente hacia la mira del espejo (shieldNormal) controlada por el jugador
                    if !isTargetingRemote {
                        let reflectedDir = shieldNormal

                        // 💎 Detección de reflejo del Escudo hacia el Interruptor Cuántico del Chrono-Core
                        let chronoSwitchPos = SIMD3<Float>(-17.55, 2.4, -6.5)
                        let toSwitchFromShield = chronoSwitchPos - shieldCenter
                        let alongShield = simd_dot(toSwitchFromShield, reflectedDir)
                        if alongShield > 0.5 && alongShield < 35.0 {
                            let closestToSwitch = shieldCenter + reflectedDir * alongShield
                            if simd_distance(closestToSwitch, chronoSwitchPos) < 1.35 {
                                if !chronoSwitchSolved {
                                    chronoSwitchSolved = true
                                    audio.playLaserReflectionSound()
                                    audio.playLanding(intensity: 1.0)
                                    onQuantumPuzzleSolved?()
                                }
                            }
                        }

                        for targetIdx in npcPositions.indices where npcRespawnTimers[targetIdx] <= 0 && npcHealths[targetIdx] > 0 {
                            let scale = npcBaseScales[targetIdx]
                            let botCenter = npcPositions[targetIdx] + SIMD3<Float>(0, 0.90 * scale, 0)
                            let toBot = botCenter - shieldCenter
                            let alongR = simd_dot(toBot, reflectedDir)
                            if alongR > 0.2 && alongR < 30.0 {
                                let closestPoint = shieldCenter + reflectedDir * alongR
                                if simd_distance(botCenter, closestPoint) < (0.95 * scale) {
                                    if mirrorReflectHitCooldowns[targetIdx] <= 0 {
                                        mirrorReflectHitCooldowns[targetIdx] = 0.18
                                        // Sobrecarga del núcleo de singularidad del Fotófago al reflejar su propio láser con el espejo
                                        let damage: Float = (targetIdx >= 2) ? 85.0 : 55.0
                                        npcHealths[targetIdx] = max(0, npcHealths[targetIdx] - damage)
                                        audio.playLaserReflectionSound()
                                        onNPCHealthsUpdate?(npcHealths)

                                        if npcHealths[targetIdx] <= 0 {
                                            botLaserActiveTimers[index] = 0
                                            botLaserCooldownTimers[index] = botCooldown
                                            audio.playLaserPlayerHitSound()
                                            onScoreUpdate?(500)
                                            handleNPCElimination(index: targetIdx)
                                            onMirrorReflectionKill?()
                                            if isBotFlyingDrone(index: targetIdx) {
                                                onDroneDeflectionKill?()
                                            }
                                        }
                                    }
                                    break
                                }
                            }
                        }
                    }
                } else {
                    endVec = SIMD4<Float>(bEndActual, 1.0)
                    // Damage only applies when photon front reaches target AND bot is actually aligned AND NO WALL/ROCK OBSTRUCTS
                    if bProgress >= 1.0 && !hitObstacle {
                        let aimRay = simd_normalize(botAimTargets[index] - botHandOrigin)
                        let targetRay = simd_normalize(targetCenter - botHandOrigin)
                        let aimAlignment = simd_dot(aimRay, targetRay)
                        let botDamagePerSec: Float = 14.0 + min(16.0, Float(currentWave - 1) * 3.5)
                        if aimAlignment > 0.94 && distance < 24.0 {
                            if isTargetingRemote {
                                if !remotePlayerIsRecovering {
                                    remoteDamageAccumulator += botDamagePerSec * rawDt
                                }
                            } else {
                                if !isRecoveringInChamber {
                                    botImpactAudioCooldowns[index] -= rawDt
                                    if botImpactAudioCooldowns[index] <= 0 {
                                        botImpactAudioCooldowns[index] = 0.45
                                        audio.playLaserPlayerHitSound()
                                    }
                                    accumulateDamage(botDamagePerSec * rawDt)
                                }
                            }
                        }
                    }
                }

                switch index {
                case 0: results.pointee.bot0Start = startVec; results.pointee.bot0End = endVec
                case 1: results.pointee.bot1Start = startVec; results.pointee.bot1End = endVec
                case 2: results.pointee.bot2Start = startVec; results.pointee.bot2End = endVec
                case 3: results.pointee.bot3Start = startVec; results.pointee.bot3End = endVec
                case 4: results.pointee.bot4Start = startVec; results.pointee.bot4End = endVec
                default: break
                }
                currentBotLaserStarts[index] = SIMD3<Float>(startVec.x, startVec.y, startVec.z)
                currentBotLaserEnds[index] = SIMD3<Float>(endVec.x, endVec.y, endVec.z)

                if botLaserActiveTimers[index] == 0 {
                    botLaserCooldownTimers[index] = 3.5 + Float(index) * 0.8
                    botLaserPropagationDistances[index] = 0
                    currentBotLaserStarts[index] = .zero
                    currentBotLaserEnds[index] = .zero
                    switch index {
                    case 0: results.pointee.bot0Start = .zero; results.pointee.bot0End = .zero
                    case 1: results.pointee.bot1Start = .zero; results.pointee.bot1End = .zero
                    case 2: results.pointee.bot2Start = .zero; results.pointee.bot2End = .zero
                    case 3: results.pointee.bot3Start = .zero; results.pointee.bot3End = .zero
                    case 4: results.pointee.bot4Start = .zero; results.pointee.bot4End = .zero
                    default: break
                    }
                }
            } else {
                currentBotLaserStarts[index] = .zero
                currentBotLaserEnds[index] = .zero
                switch index {
                case 0: results.pointee.bot0Start = .zero; results.pointee.bot0End = .zero
                case 1: results.pointee.bot1Start = .zero; results.pointee.bot1End = .zero
                case 2: results.pointee.bot2Start = .zero; results.pointee.bot2End = .zero
                case 3: results.pointee.bot3Start = .zero; results.pointee.bot3End = .zero
                case 4: results.pointee.bot4Start = .zero; results.pointee.bot4End = .zero
                default: break
                }
            }
        }
    }

    private func findRayObstacleHit(from origin: SIMD3<Float>, to target: SIMD3<Float>) -> (hit: Bool, hitDistance: Float, hitPoint: SIMD3<Float>) {
        let diff = target - origin
        let totalDist = simd_length(diff)
        guard totalDist > 0.001 else { return (false, totalDist, target) }
        let dir = diff / totalDist
        var closestHitDist = totalDist
        var hitObstacle = false
        var bestHitPoint = target

        // 🚪 1. Muro Divisor Sur y Gran Espejo Mágico Portal (Z = 17.8)
        // Separa el Salón Piscina (Z <= 17.8) del Gran Salón Arcoíris (Z > 17.8).
        // Tanto el muro de concreto como el espejo portal son 100% impenetrables para los rayos láser.
        if (origin.z < 17.8 && target.z > 17.8) || (origin.z > 17.8 && target.z < 17.8) {
            if abs(dir.z) > 0.0001 {
                let t = (17.8 - origin.z) / dir.z
                if t > 0.02 && t < closestHitDist {
                    let hp = origin + dir * t
                    // El muro y el portal abarcan todo el ancho X (-27.5 a 27.5) y altura Y (-1.0 a 10.0)
                    if hp.x >= -27.5 && hp.x <= 27.5 && hp.y >= -1.0 && hp.y <= 10.0 {
                        closestHitDist = t
                        hitObstacle = true
                        bestHitPoint = hp
                    }
                }
            }
        }

        // 🧱 2. Muros perimetrales
        // Muro Norte Piscina (Z = -17.8)
        if (origin.z > -17.8 && target.z < -17.8) || (origin.z < -17.8 && target.z > -17.8) {
            if abs(dir.z) > 0.0001 {
                let t = (-17.8 - origin.z) / dir.z
                if t > 0.02 && t < closestHitDist {
                    closestHitDist = t
                    hitObstacle = true
                    bestHitPoint = origin + dir * t
                }
            }
        }
        // Muro Sur Arcoíris (Z = 72.0)
        if (origin.z < 72.0 && target.z > 72.0) || (origin.z > 72.0 && target.z < 72.0) {
            if abs(dir.z) > 0.0001 {
                let t = (72.0 - origin.z) / dir.z
                if t > 0.02 && t < closestHitDist {
                    closestHitDist = t
                    hitObstacle = true
                    bestHitPoint = origin + dir * t
                }
            }
        }

        // 🪨 3. Rocas del Río y Patio
        for rock in rtRiverRocks {
            let center = rock.center
            let radius = max(rock.radii.x, rock.radii.z)
            let toCenter = center - origin
            let proj = simd_dot(toCenter, dir)
            if proj > 0.1 && proj < closestHitDist {
                let closestPointOnRay = origin + dir * proj
                let distToRock = simd_distance(center, closestPointOnRay)
                if distToRock < (radius + 0.35) {
                    let hitDist = max(0.1, proj - 0.2)
                    if hitDist < closestHitDist {
                        closestHitDist = hitDist
                        hitObstacle = true
                        bestHitPoint = origin + dir * hitDist
                    }
                }
            }
        }

        // 🌈 4. Cabañas y Cajas de Parkour Arcoíris
        for box in rtRainbowParkourBoxes {
            let half = box.size * 0.5
            let bMin = box.center - half
            let bMax = box.center + half
            let invDir = SIMD3<Float>(
                abs(dir.x) > 0.0001 ? 1.0 / dir.x : 1e6,
                abs(dir.y) > 0.0001 ? 1.0 / dir.y : 1e6,
                abs(dir.z) > 0.0001 ? 1.0 / dir.z : 1e6
            )
            let t1 = (bMin - origin) * invDir
            let t2 = (bMax - origin) * invDir
            let tMin = max(max(min(t1.x, t2.x), min(t1.y, t2.y)), min(t1.z, t2.z))
            let tMax = min(min(max(t1.x, t2.x), max(t1.y, t2.y)), max(t1.z, t2.z))
            if tMax >= max(0.15, tMin) && tMin < closestHitDist {
                let hitDist = max(0.15, tMin - 0.1)
                if hitDist < closestHitDist {
                    closestHitDist = hitDist
                    hitObstacle = true
                    bestHitPoint = origin + dir * hitDist
                }
            }
        }

        return (hitObstacle, closestHitDist, bestHitPoint)
    }

    private func checkCombatHits(dt: Float) {
        for i in playerLaserHitCooldowns.indices {
            if playerLaserHitCooldowns[i] > 0 {
                playerLaserHitCooldowns[i] = max(0, playerLaserHitCooldowns[i] - dt)
            }
        }

        guard !isPlayerDead, !isGamePaused, heldTool == .laser, laserActiveRemaining > 0, laserBattery > 0.005 else { return }

        let origin: SIMD3<Float>
        let direction: SIMD3<Float>
        if cameraMode == .firstPerson {
            origin = lastCameraPosition
            direction = lastCameraForward
        } else {
            origin = lastToolOrigin
            direction = lastToolDirection
        }
        var closestIndex: Int?
        var closestDistance: Float = 72

        for index in npcPositions.indices where npcRespawnTimers[index] <= 0 && npcHealths[index] > 0 {
            let isColossalGolem = (index == 4 && currentWave >= 3)
            let scale: Float = isColossalGolem ? 1.65 : npcBaseScales[index]
            let center = npcPositions[index] + SIMD3<Float>(0, 0.88 * scale, 0)
            let alongRay = simd_dot(center - origin, direction)
            guard alongRay > 0, alongRay < closestDistance else { continue }
            let closestPoint = origin + direction * alongRay
            guard simd_distance(center, closestPoint) < (1.42 * scale) else { continue }

            // 🛡️ Comprobar que no haya un muro, el espejo portal, rocas o cajas bloqueando el tiro
            let obs = findRayObstacleHit(from: origin, to: center)
            if obs.hit && obs.hitDistance < (alongRay - 0.45) {
                continue
            }

            closestIndex = index
            closestDistance = alongRay
        }

        if let closestIndex, playerLaserHitCooldowns[closestIndex] <= 0 {
            playerLaserHitCooldowns[closestIndex] = 0.20
            // El Fotófago absorbe parte de los fotones directos (armadura Vantablack), requiriendo más impactos o usar el espejo
            let damage: Float = (closestIndex >= 3) ? 26.0 : 35.0
            if isAuthorityForNPCs {
                npcHealths[closestIndex] = max(0, npcHealths[closestIndex] - damage)
                onNPCHealthsUpdate?(npcHealths)

                if npcHealths[closestIndex] <= 0 {
                    audio.playLaserPlayerHitSound()
                    onScoreUpdate?(250)
                    handleNPCElimination(index: closestIndex)
                } else {
                    audio.playLaserPlayerHitSound()
                    onScoreUpdate?(25)
                }
            } else {
                audio.playLaserPlayerHitSound()
                onScoreUpdate?(25)
                onClientNPCHit?(closestIndex, damage)
            }
        }

        // Detección de impacto de láser sobre otros jugadores (Versus / Equipos 1v1, 2v2, 3v3, 4v4 - sin fuego amigo a compañeros de escuadra)
        if isRemotePlayerConnected && isVersusMode {
            remotePlayerHitCooldown = max(0, remotePlayerHitCooldown - dt)
            let targets: [RemoteAgentState] = remoteAgents.isEmpty
                ? [RemoteAgentState(peerID: "", position: remotePlayerPosition, yaw: remotePlayerYaw, heldToolRaw: remotePlayerHeldTool.rawValue, isSameTeam: false)]
                : remoteAgents.filter { !$0.isSameTeam && $0.health > 0 }

            for target in targets {
                let tPos = target.position
                let alongRay = simd_dot((tPos + SIMD3<Float>(0, 0.95, 0)) - origin, direction)
                if alongRay > 0.4 && alongRay < 68.0 {
                    let closestPoint = origin + direction * alongRay
                    let clampedY = max(tPos.y + 0.15, min(tPos.y + 1.85, closestPoint.y))
                    let segmentPoint = SIMD3<Float>(tPos.x, clampedY, tPos.z)
                    let distToBody = simd_distance(closestPoint, segmentPoint)

                    if distToBody < 0.78 && remotePlayerHitCooldown <= 0 {
                        let obs = findRayObstacleHit(from: origin, to: segmentPoint)
                        let hitObstacle = obs.hit && obs.hitDistance < (alongRay - 0.45)
                        if !hitObstacle {
                            let rivalFacing = SIMD3<Float>(sin(target.yaw), 0, cos(target.yaw))
                            let facingDot = simd_dot(-direction, rivalFacing)
                            let targetTool = GameHeldTool(rawValue: target.heldToolRaw) ?? .none
                            if targetTool == .mirror && facingDot > -0.20 {
                                remotePlayerHitCooldown = 0.35
                                audio.playLaserReflectionSound()
                                accumulateDamage(25.0)
                            } else {
                                remotePlayerHitCooldown = 0.35
                                audio.playLaserPlayerHitSound()
                                if !target.peerID.isEmpty {
                                    onRemoteAgentHit?(target.peerID, 15.0)
                                } else {
                                    onRemotePlayerHit?(15.0)
                                }
                            }
                        }
                        break
                    }
                }
            }
        }

        // The rear wall mirror can send the player's own beam back at them.
        let mirrorZ: Float = -17.55
        guard direction.z < -0.001 else { return }
        let mirrorDistance = (mirrorZ - origin.z) / direction.z
        guard mirrorDistance > 0, mirrorDistance < 40 else { return }
        let mirrorPoint = origin + direction * mirrorDistance
        guard mirrorPoint.x > 1.35, mirrorPoint.x < 5.65,
              mirrorPoint.y > 0.72, mirrorPoint.y < 3.38 else { return }
        let reflected = SIMD3<Float>(direction.x, direction.y, -direction.z)

        // 💎 ENIGMA DEL CHRONO-CORE: Alineación de Espejos Continuos
        let chronoSwitchPos = SIMD3<Float>(-17.55, 2.4, -6.5)
        let eastPrismPos = SIMD3<Float>(8.5, 1.8, -6.5)

        // Opción 1: Refracción continua en cadena (Espejo Norte -> Prisma Oriental -> Interruptor Occidental)
        let toPrism = eastPrismPos - mirrorPoint
        let alongToPrism = simd_dot(toPrism, reflected)
        if alongToPrism > 0.5 && alongToPrism < 35.0 {
            let closestToPrism = mirrorPoint + reflected * alongToPrism
            if simd_distance(closestToPrism, eastPrismPos) < 1.35 {
                // Segundo rebote en el prisma oriental orientado hacia la pared occidental (-X)
                let prismReflectedDir = simd_normalize(SIMD3<Float>(-1.0, 0.04, 0.0))
                let toSwitchFromPrism = chronoSwitchPos - eastPrismPos
                let alongToSwitch = simd_dot(toSwitchFromPrism, prismReflectedDir)
                if alongToSwitch > 0.5 {
                    let closestToSwitch = eastPrismPos + prismReflectedDir * alongToSwitch
                    if simd_distance(closestToSwitch, chronoSwitchPos) < 1.60 {
                        if !chronoSwitchSolved {
                            chronoSwitchSolved = true
                            audio.playLaserReflectionSound()
                            audio.playLanding(intensity: 1.0)
                            onQuantumPuzzleSolved?()
                        }
                    }
                }
            }
        }

        // Opción 2: Rebote angular directo del Espejo Norte hacia el Interruptor Occidental
        let toSwitchFromNorth = chronoSwitchPos - mirrorPoint
        let alongToSwitchNorth = simd_dot(toSwitchFromNorth, reflected)
        if alongToSwitchNorth > 0.5 && alongToSwitchNorth < 40.0 {
            let closestToSwitchNorth = mirrorPoint + reflected * alongToSwitchNorth
            if simd_distance(closestToSwitchNorth, chronoSwitchPos) < 1.35 {
                if !chronoSwitchSolved {
                    chronoSwitchSolved = true
                    audio.playLaserReflectionSound()
                    audio.playLanding(intensity: 1.0)
                    onQuantumPuzzleSolved?()
                }
            }
        }

        let playerCenter = playerPosition + SIMD3<Float>(0, 0.85, 0)
        let toPlayer = playerCenter - mirrorPoint
        let reflectedDistance = simd_dot(toPlayer, reflected)
        guard reflectedDistance > 0, reflectedDistance < 22 else { return }
        let reflectedClosestPoint = mirrorPoint + reflected * reflectedDistance
        if simd_distance(playerCenter, reflectedClosestPoint) < 0.52 {
            laserActiveRemaining = 0
            laserCooldownRemaining = 1.0
        }

        // A reflected beam is still a gameplay beam: it can tag any rival
        // that lies on the outgoing segment after the mirror.
        var reflectedTarget: Int?
        var closestReflectedDistance: Float = 22
        for index in npcPositions.indices where npcRespawnTimers[index] <= 0 && npcHealths[index] > 0 {
            let center = npcPositions[index] + SIMD3<Float>(0, 0.85, 0)
            let alongRay = simd_dot(center - mirrorPoint, reflected)
            guard alongRay > 0, alongRay < closestReflectedDistance else { continue }
            let closestPoint = mirrorPoint + reflected * alongRay
            guard simd_distance(center, closestPoint) < 0.48 else { continue }

            let obs = findRayObstacleHit(from: mirrorPoint, to: center)
            if obs.hit && obs.hitDistance < (alongRay - 0.45) {
                continue
            }

            reflectedTarget = index
            closestReflectedDistance = alongRay
        }
        if let reflectedTarget, playerLaserHitCooldowns[reflectedTarget] <= 0 {
            playerLaserHitCooldowns[reflectedTarget] = 0.20
            let damage: Float = 50.0
            if isAuthorityForNPCs {
                npcHealths[reflectedTarget] = max(0, npcHealths[reflectedTarget] - damage)
                audio.playLanding(intensity: 0.85)
                onNPCHealthsUpdate?(npcHealths)

                if npcHealths[reflectedTarget] <= 0 {
                    audio.playLaserPlayerHitSound()
                    onScoreUpdate?(350)
                    handleNPCElimination(index: reflectedTarget)
                } else {
                    onScoreUpdate?(35)
                }
            } else {
                audio.playLanding(intensity: 0.85)
                onScoreUpdate?(35)
                onClientNPCHit?(reflectedTarget, damage)
            }
        }

        // Reflejo en espejo impactando al jugador rival (1v1 Versus únicamente)
        if isRemotePlayerConnected && isVersusMode && remotePlayerHitCooldown <= 0 {
            let toRemote = (remotePlayerPosition + SIMD3<Float>(0, 0.95, 0)) - mirrorPoint
            let reflectedDist = simd_dot(toRemote, reflected)
            if reflectedDist > 0 && reflectedDist < 25.0 {
                let reflectedClosest = mirrorPoint + reflected * reflectedDist
                let clampedY = max(remotePlayerPosition.y + 0.15, min(remotePlayerPosition.y + 1.85, reflectedClosest.y))
                let segmentPoint = SIMD3<Float>(remotePlayerPosition.x, clampedY, remotePlayerPosition.z)
                if simd_distance(reflectedClosest, segmentPoint) < 0.75 {
                    remotePlayerHitCooldown = 0.35
                    audio.playLaserPlayerHitSound()
                    onRemotePlayerHit?(18.0)
                }
            }
        }
    }

    private func isInsidePoolXZ(_ position: SIMD3<Float>) -> Bool {
        position.x > -5.28 && position.x < 2.28 &&
        position.z > -4.08 && position.z < 1.08
    }

    private func waterImmersion(at position: SIMD3<Float>, insidePool: Bool) -> Float {
        guard insidePool else { return 0 }
        let waterSurface: Float = 0.40
        return min(1, max(0.20, (waterSurface - position.y) / 0.80))
    }

    private func groundHeight(at position: SIMD3<Float>, insidePool: Bool) -> Float {
        // 🌀 Tobogán Vertical Ladder & Platform Top
        if position.x >= -5.5 && position.x <= -2.1 && position.z >= -17.2 && position.z <= -13.5 {
            if position.y >= 3.5 {
                return 5.55
            }
        }
        // 🌈 Plataformas de Parkour Multi-Altura y Techos de Cabañas en el Gran Salón Arcoíris (Z > 18)
        if position.z > 18.0 {
            var highestPlatform: Float = 0.0
            for box in rtRainbowParkourBoxes {
                let halfX = box.size.x * 0.5 + 0.16
                let halfZ = box.size.z * 0.5 + 0.16
                if abs(position.x - box.center.x) <= halfX && abs(position.z - box.center.z) <= halfZ {
                    let topY = box.center.y + box.size.y * 0.5
                    let bottomY = box.center.y - box.size.y * 0.5
                    // Si es un techo alto de cabaña (bottomY > 1.8), solo pararse si los pies están sobre el techo
                    if bottomY > 1.8 {
                        if position.y >= topY - 0.25 {
                            highestPlatform = max(highestPlatform, topY)
                        }
                    } else if position.y >= topY - 0.25 {
                        highestPlatform = max(highestPlatform, topY)
                    }
                }
            }
            for rock in rtRiverRocks where rock.center.z > 18.0 {
                let rx = (position.x - rock.center.x) / (rock.radii.x * 1.05)
                let rz = (position.z - rock.center.z) / (rock.radii.z * 1.05)
                let distSq = rx * rx + rz * rz
                if distSq < 1.0 {
                    let rockTop = rock.center.y + rock.radii.y * sqrt(max(0.0, 1.0 - distSq)) * 1.02
                    if rockTop > 0.05 && position.y >= rockTop - 0.45 {
                        highestPlatform = max(highestPlatform, rockTop)
                    }
                }
            }
            return highestPlatform
        }

        // 🪨 Superficie superior de las Rocas de Río / Búlders (soporte sólido para pararse encima y no caer dentro)
        var highestRock: Float = 0.0
        for rock in rtRiverRocks where rock.center.z <= 18.0 {
            let rx = (position.x - rock.center.x) / (rock.radii.x * 1.05)
            let rz = (position.z - rock.center.z) / (rock.radii.z * 1.05)
            let distSq = rx * rx + rz * rz
            if distSq < 1.0 {
                let rockTop = rock.center.y + rock.radii.y * sqrt(max(0.0, 1.0 - distSq)) * 1.02
                if rockTop > 0.05 && position.y >= rockTop - 0.45 {
                    highestRock = max(highestRock, rockTop)
                }
            }
        }
        if highestRock > 0.05 {
            return highestRock
        }

        // 📚 Mesa de Madera con Libros en el Patio de la Piscina (X: 7.3, Z: 4.8)
        let tableHalfX: Float = 1.60 + 0.12
        let tableHalfZ: Float = 0.36 + 0.12
        let dxTable = position.x - 7.3
        let dzTable = position.z - 4.8
        if abs(dxTable) <= tableHalfX && abs(dzTable) <= tableHalfZ {
            let isOverBooks = position.x >= 6.35 && position.x <= 8.10
            let targetSurfaceY: Float = isOverBooks ? 0.75 : 0.65
            if position.y >= targetSurfaceY - 0.45 {
                return targetSurfaceY
            }
        }

        // 🌊 Si está bajo la superficie (en el pozo abisal o cámara subterránea), el suelo es el fondo abisal:
        if position.y < -0.30 {
            return -11.0
        }
        guard insidePool else { return 0 }
        let floatCenter = SIMD2<Float>(floatPosition.x, floatPosition.z)
        let distance = simd_distance(SIMD2<Float>(position.x, position.z), floatCenter)
        let floatTop = floatPosition.y + 0.13
        if distance < 0.84 && position.y >= floatTop - 0.10 {
            return floatTop
        }
        // 🌊 Lógica del "Posito de 14 cm":
        // Si el jugador entra al pozo profundo tras usar el tobogán o bucear,
        // el fondo es el piso abisal (-11.0m) para nadar en 3D.
        // Pero si camina en la superficie, reposa en -0.14m.
        if enteredEasterEggViaToboggan {
            return -11.0
        } else {
            return -0.14 // 🌊 Posito de 14 cm: pies en -0.14m sin hundirse
        }
    }

    private func clampToArenaBounds(
        position: inout SIMD3<Float>,
        previousPosition: SIMD3<Float>,
        margin: Float = 0.38
    ) {
        var dummyVelocity = SIMD2<Float>.zero
        clampToArenaBounds(position: &position, previousPosition: previousPosition, margin: margin, velocity: &dummyVelocity)
    }

    private func clampToArenaBounds(
        position: inout SIMD3<Float>,
        previousPosition: SIMD3<Float>,
        margin: Float = 0.38,
        velocity: inout SIMD2<Float>
    ) {
        // 🏊‍♂️ Pozo de la Piscina / Tramo Estrecho (-4.70 <= Y < 0.20):
        // Conexión vertical entre la piscina superior y la cámara subterránea
        if position.y < 0.20 && position.y >= -4.70 {
            let shaftMargin = max(0.40, margin)
            let minX: Float = -5.28 + shaftMargin
            let maxX: Float = 2.28 - shaftMargin
            let minZ: Float = -4.08 + shaftMargin
            let maxZ: Float = 1.08 - shaftMargin
            if position.x < minX {
                position.x = minX
                if velocity.x < 0 { velocity.x = 0 }
            } else if position.x > maxX {
                position.x = maxX
                if velocity.x > 0 { velocity.x = 0 }
            }
            if position.z < minZ {
                position.z = minZ
                if velocity.y < 0 { velocity.y = 0 }
            } else if position.z > maxZ {
                position.z = maxZ
                if velocity.y > 0 { velocity.y = 0 }
            }
            return
        }

        // 🌊 Gran Cámara Acuática Subterránea Abisal (Y < -4.70):
        if position.y < -4.70 {
            let poolMargin = max(0.40, margin)
            let minX: Float = -17.8 + poolMargin
            let maxX: Float = 17.8 - poolMargin
            let minZ: Float = -17.8 + poolMargin
            let maxZ: Float = 17.8 - poolMargin
            if position.x < minX {
                position.x = minX
                if velocity.x < 0 { velocity.x = 0 }
            } else if position.x > maxX {
                position.x = maxX
                if velocity.x > 0 { velocity.x = 0 }
            }
            if position.z < minZ {
                position.z = minZ
                if velocity.y < 0 { velocity.y = 0 }
            } else if position.z > maxZ {
                position.z = maxZ
                if velocity.y > 0 { velocity.y = 0 }
            }
            // Techo subterráneo sólido fuera de la boca del pozo:
            let underShaft = position.x >= -5.28 && position.x <= 2.28 && position.z >= -4.08 && position.z <= 1.08
            if !underShaft && position.y > -4.95 {
                position.y = -4.95
            }
            return
        }

        let portalHalfWidth: Float = 5.10
        let isGateUnlocked = isRainbowGateUnlocked
        let distToGate = simd_distance(position, SIMD3<Float>(0, position.y, 17.8))
        if margin < 1.0 {
            if distToGate < 6.0 {
                onRainbowGateStatusUpdate?(isGateUnlocked, playerScore, 3000)
            } else {
                onRainbowGateStatusUpdate?(isGateUnlocked, -1, 3000)
            }
        }

        // 1. Límites globales norte y sur del mapa completo
        let minZ = -17.8 + margin
        let maxZ = 72.0 - margin
        if position.z < minZ {
            position.z = minZ
            if velocity.y < 0 { velocity.y = 0 }
        } else if position.z > maxZ {
            position.z = maxZ
            if velocity.y > 0 { velocity.y = 0 }
        }

        // 2. Control estricto del Muro Divisor Sur (Z = 17.8) entre Salón Piscina y Gran Salón Arcoíris
        // Determinar si el ente se encuentra dentro del vano del Gran Pórtico (X) y si el portal está abierto
        let inPortalX = abs(position.x) <= portalHalfWidth
        let canCrossDividingWall = inPortalX && isGateUnlocked

        if previousPosition.z <= 17.8 {
            // Estaba en el Patio de la Piscina (Z <= 17.8)
            let wallZ = 17.8 - margin
            if position.z > wallZ {
                if canCrossDividingWall {
                    position.x = max(-portalHalfWidth, min(portalHalfWidth, position.x))
                    if position.x <= -portalHalfWidth && velocity.x < 0 { velocity.x = 0 }
                    if position.x >= portalHalfWidth && velocity.x > 0 { velocity.x = 0 }
                    if previousPosition.z < 17.8 && position.z >= 17.8 && margin < 1.0 {
                        audio.playLaserIgnition()
                        onCrossedRainbowGate?()
                    }
                } else {
                    // Bloqueo continuo anti-túnel: el muro sur retiene físicamente al personaje con deslizamiento suave
                    position.z = wallZ
                    if velocity.y > 0 { velocity.y = 0 }
                }
            }
        } else {
            // Estaba en el Gran Salón Arcoíris (Z > 17.8)
            let wallZ = 17.8 + margin
            if position.z < wallZ {
                if canCrossDividingWall {
                    position.x = max(-portalHalfWidth, min(portalHalfWidth, position.x))
                    if position.x <= -portalHalfWidth && velocity.x < 0 { velocity.x = 0 }
                    if position.x >= portalHalfWidth && velocity.x > 0 { velocity.x = 0 }
                    if previousPosition.z > 17.8 && position.z <= 17.8 && margin < 1.0 {
                        audio.playLaserIgnition()
                    }
                } else {
                    // Bloqueo continuo anti-túnel: las alas del muro retienen al personaje en el Salón Arcoíris con deslizamiento suave
                    position.z = wallZ
                    if velocity.y < 0 { velocity.y = 0 }
                }
            }
        }

        // 3. Límites perimetrales laterales Este-Oeste según la zona resultante
        if position.z <= 17.8 {
            let minX = -17.8 + margin
            let maxX = 17.8 - margin
            if position.x < minX {
                position.x = minX
                if velocity.x < 0 { velocity.x = 0 }
            } else if position.x > maxX {
                position.x = maxX
                if velocity.x > 0 { velocity.x = 0 }
            }
        } else {
            let minX = -27.0 + margin
            let maxX = 27.0 - margin
            if position.x < minX {
                position.x = minX
                if velocity.x < 0 { velocity.x = 0 }
            } else if position.x > maxX {
                position.x = maxX
                if velocity.x > 0 { velocity.x = 0 }
            }
        }
    }

    private func resolveParkourAndCabinCollisions(position: inout SIMD3<Float>) {
        // 📚 Colisión física horizontal con la Mesa de Madera y Libros en el Patio de la Piscina (X: 7.3, Z: 4.8)
        let tableHalfX: Float = 1.60 + 0.36
        let tableHalfZ: Float = 0.36 + 0.36
        let tableTopY: Float = 0.65
        let dxTable = position.x - 7.3
        let dzTable = position.z - 4.8
        if abs(dxTable) < tableHalfX && abs(dzTable) < tableHalfZ {
            // Si el jugador está subido a la mesa (pies en o sobre la superficie), no empujar lateralmente para permitir caminar
            if position.y < tableTopY - 0.08 {
                let overlapX = tableHalfX - abs(dxTable)
                let overlapZ = tableHalfZ - abs(dzTable)
                if overlapX < overlapZ {
                    position.x += dxTable >= 0 ? overlapX : -overlapX
                } else {
                    position.z += dzTable >= 0 ? overlapZ : -overlapZ
                }
            }
        }

        guard position.z > 17.5 else { return }
        let playerRadius: Float = 0.46
        for box in rtRainbowParkourBoxes {
            let topY = box.center.y + box.size.y * 0.5
            let bottomY = box.center.y - box.size.y * 0.5
            // Si es un techo flotante alto (como el techo de una cabaña) y estamos debajo de él, podemos caminar por debajo libremente
            if bottomY > 1.8 && position.y + 1.55 < bottomY {
                continue
            }
            // Si los pies del jugador están realmente sobre la superficie del cubo o escalón, permitir caminar libremente sobre él
            if position.y >= topY - 0.05 {
                continue
            }

            let halfX = box.size.x * 0.5 + playerRadius
            let halfZ = box.size.z * 0.5 + playerRadius
            let dx = position.x - box.center.x
            let dz = position.z - box.center.z

            if abs(dx) < halfX && abs(dz) < halfZ {
                // Auto-step up para bordes o escalones bajos transitables (altura del escalón <= 0.38m sobre los pies del jugador):
                let stepDiff = topY - position.y
                if stepDiff > 0.0 && stepDiff <= 0.38 {
                    let edgeMarginX = box.size.x * 0.5 + 0.04
                    let edgeMarginZ = box.size.z * 0.5 + 0.04
                    if abs(dx) < edgeMarginX && abs(dz) < edgeMarginZ {
                        position.y = topY
                        continue
                    }
                }

                // Para paredes o bloques más altos que un escalón: ¡colisión sólida impenetrable que expulsa al jugador hacia afuera!
                let overlapX = halfX - abs(dx)
                let overlapZ = halfZ - abs(dz)
                if overlapX < overlapZ {
                    position.x += dx >= 0 ? overlapX : -overlapX
                } else {
                    position.z += dz >= 0 ? overlapZ : -overlapZ
                }
            }
        }
    }

    private func isStandingOnFloat(_ position: SIMD3<Float>) -> Bool {
        let center = SIMD2<Float>(floatPosition.x, floatPosition.z)
        let distance = simd_distance(SIMD2<Float>(position.x, position.z), center)
        let floatTop = floatPosition.y + 0.13
        return distance < 0.84 &&
            abs(position.y - floatTop) < 0.045 &&
            abs(verticalVelocity) < 0.15
    }

    private func updateFloatSimulation(dt: Float) -> SIMD3<Float> {
        let previousPosition = floatPosition
        let speed = simd_length(floatVelocity)
        if speed > 1.65 {
            floatVelocity *= 1.65 / speed
        }

        floatVelocity *= exp(-dt * 1.35)
        floatVelocity += SIMD2<Float>(
            sin(elapsedTime * 0.47),
            cos(elapsedTime * 0.39)
        ) * (dt * 0.012)
        floatPosition.x += floatVelocity.x * dt
        floatPosition.z += floatVelocity.y * dt

        let minimumX: Float = -4.62
        let maximumX: Float = 1.62
        let minimumZ: Float = -3.42
        let maximumZ: Float = 0.42
        if floatPosition.x < minimumX || floatPosition.x > maximumX {
            floatPosition.x = min(maximumX, max(minimumX, floatPosition.x))
            floatVelocity.x *= -0.32
        }
        if floatPosition.z < minimumZ || floatPosition.z > maximumZ {
            floatPosition.z = min(maximumZ, max(minimumZ, floatPosition.z))
            floatVelocity.y *= -0.32
        }

        floatPosition.y = 0.015 +
            sin(elapsedTime * 1.35) * 0.014 +
            sin(elapsedTime * 0.61 + 0.8) * 0.006
        floatAngularVelocity *= exp(-dt * 1.8)
        floatYaw += floatAngularVelocity * dt

        floatWakeCountdown -= dt
        if simd_length(floatVelocity) > 0.09 && floatWakeCountdown <= 0 {
            pendingWaterImpulse = SIMD4<Float>(floatPosition.x, floatPosition.z, -0.24, 1)
            floatWakeCountdown = 0.24
        }

        return floatPosition - previousPosition
    }

    private func reportNearbyLightIfNeeded() {
        let point = SIMD2<Float>(playerPosition.x, playerPosition.z)
        var candidates: [(GameLightFixture, Float)] = []

        // Detección cercana y confiable (~4.2m) para interactuar con luminarias
        let postDistance = simd_distance(point, SIMD2<Float>(-7.55, 12.65))
        if postDistance < 4.2 {
            candidates.append((.post, postDistance))
        }
        let piscinaDistance = simd_distance(point, SIMD2<Float>(-7.70, -16.80))
        if piscinaDistance < 4.2 {
            candidates.append((.piscinaNeon, piscinaDistance))
        }
        let sheeritDistance = simd_distance(point, SIMD2<Float>(6.20, 16.80))
        if sheeritDistance < 4.2 {
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

        // 🌈 Terminales de Luz Arcoíris junto a las 4 Cabañas en el Gran Salón Arcoíris (Z > 18)
        let rainbowPostDist = simd_distance(point, SIMD2<Float>(-12.5, 32.0))
        if rainbowPostDist < 4.2 {
            candidates.append((.post, rainbowPostDist))
        }
        let rainbowPiscinaDist = simd_distance(point, SIMD2<Float>(12.5, 32.0))
        if rainbowPiscinaDist < 4.2 {
            candidates.append((.piscinaNeon, rainbowPiscinaDist))
        }
        let rainbowSheeritDist = simd_distance(point, SIMD2<Float>(-12.5, 56.0))
        if rainbowSheeritDist < 4.2 {
            candidates.append((.sheeritNeon, rainbowSheeritDist))
        }
        let rainbowStripsDist = min(
            simd_distance(point, SIMD2<Float>(12.5, 56.0)),
            simd_distance(point, SIMD2<Float>(0.0, 45.0))
        )
        if rainbowStripsDist < 4.5 {
            candidates.append((.poolStrips, rainbowStripsDist))
        }

        let nearby = candidates.min(by: { $0.1 < $1.1 })?.0
        guard !hasReportedNearbyLight || nearby != lastNearbyLight else { return }
        hasReportedNearbyLight = true
        lastNearbyLight = nearby
        onNearbyLightUpdate?(nearby)
    }

    private func resolveFloatCollision(position: inout SIMD3<Float>) {
        guard isInsidePoolXZ(position) else { return }
        let center = SIMD2<Float>(floatPosition.x, floatPosition.z)
        let floatTop = floatPosition.y + 0.13
        guard position.y < floatTop - 0.10 else { return }
        var offset = SIMD2<Float>(position.x, position.z) - center
        let minimumDistance: Float = 0.84
        let distance = simd_length(offset)
        guard distance < minimumDistance else { return }

        if distance < 0.0001 {
            offset = SIMD2<Float>(1, 0)
        } else {
            offset /= distance
        }
        let corrected = center + offset * minimumDistance
        position.x = corrected.x
        position.z = corrected.y

        let relativeVelocity = horizontalVelocity - floatVelocity
        let inwardSpeed = simd_dot(relativeVelocity, offset)
        if inwardSpeed < 0 {
            horizontalVelocity -= offset * inwardSpeed * 0.78
            floatVelocity += offset * inwardSpeed * 0.52
            let torque = offset.x * relativeVelocity.y - offset.y * relativeVelocity.x
            floatAngularVelocity += torque * 0.18
        }
        pendingWaterImpulse = SIMD4<Float>(floatPosition.x, floatPosition.z, -0.52, 1)
    }

    private func resolveRockCollisions(position: inout SIMD3<Float>) {
        let playerRadius: Float = 0.38

        for rock in rtRiverRocks {
            let rockTop = rock.center.y + rock.radii.y * 1.02
            // Si el jugador está sobre la roca (o en el tope), no empujar lateralmente para permitir caminar encima
            guard position.y < rockTop - 0.10 else { continue }

            let center = SIMD2<Float>(rock.center.x, rock.center.z)
            let expandedRadii = SIMD2<Float>(rock.radii.x * 1.02 + playerRadius, rock.radii.z * 1.02 + playerRadius)
            var offset = SIMD2<Float>(position.x, position.z) - center
            var normalizedOffset = offset / expandedRadii
            var normalizedDistance = simd_length(normalizedOffset)
            guard normalizedDistance < 1 else { continue }

            if normalizedDistance < 0.0001 {
                let fallback = simd_length_squared(horizontalVelocity) > 0.0001
                    ? -simd_normalize(horizontalVelocity)
                    : SIMD2<Float>(1, 0)
                offset = fallback * expandedRadii
                normalizedOffset = fallback
                normalizedDistance = 1
            }

            let corrected = center + offset / normalizedDistance
            position.x = corrected.x
            position.z = corrected.y

            var surfaceNormal = SIMD2<Float>(
                offset.x / (expandedRadii.x * expandedRadii.x),
                offset.y / (expandedRadii.y * expandedRadii.y)
            )
            if simd_length_squared(surfaceNormal) > 0.0001 {
                surfaceNormal = simd_normalize(surfaceNormal)
                let inwardSpeed = simd_dot(horizontalVelocity, surfaceNormal)
                if inwardSpeed < 0 {
                    horizontalVelocity -= surfaceNormal * inwardSpeed
                }
            }
        }
    }

    private func resolveCharacterCollisions(playerPos: inout SIMD3<Float>, dt: Float) {
        if characterBumpAudioCooldown > 0 {
            characterBumpAudioCooldown = max(0, characterBumpAudioCooldown - dt)
        }
        guard !isWaveIntermission else { return }

        let minSeparation: Float = 0.92 // Radio combinado de cápsulas jugador (0.46m) + rival (0.46m)

        for index in npcPositions.indices {
            guard npcHealths[index] > 0, npcRespawnTimers[index] <= 0 else { continue }
            // Verificar solapamiento vertical (altura de personaje ~1.55m)
            guard abs(playerPos.y - npcPositions[index].y) < 1.55 else { continue }

            let player2D = SIMD2<Float>(playerPos.x, playerPos.z)
            let npc2D = SIMD2<Float>(npcPositions[index].x, npcPositions[index].z)
            let offset = player2D - npc2D
            let dist = simd_length(offset)
            guard dist < minSeparation else { continue }

            // Vector normal apuntando desde el NPC hacia el jugador
            let normal: SIMD2<Float>
            if dist > 0.0001 {
                normal = offset / dist
            } else {
                normal = simd_length_squared(horizontalVelocity) > 0.0001
                    ? -simd_normalize(horizontalVelocity)
                    : SIMD2<Float>(1, 0)
            }

            let overlap = minSeparation - dist
            let inwardSpeed = max(0, -simd_dot(horizontalVelocity, normal))

            // 1. Empujar físicamente al personaje rival hacia atrás (-normal)
            var pushedNPC = npcPositions[index]
            let npcPushShare: Float = inwardSpeed > 0.15 ? 0.68 : 0.45
            pushedNPC.x -= normal.x * (overlap * npcPushShare)
            pushedNPC.z -= normal.y * (overlap * npcPushShare)

            // Respetar bordes de la piscina, rocas, estructuras y muros para el NPC empujado
            let wasInsidePool = npcPositions[index].x >= -5.60 && npcPositions[index].x <= 2.60 && npcPositions[index].z >= -4.45 && npcPositions[index].z <= 1.45
            let isInsidePool = pushedNPC.x >= -5.60 && pushedNPC.x <= 2.60 && pushedNPC.z >= -4.45 && pushedNPC.z <= 1.45
            if !wasInsidePool && isInsidePool && pushedNPC.y < 0.2 {
                pushedNPC.x = npcPositions[index].x
                pushedNPC.z = npcPositions[index].z
            }
            resolveRockCollisions(position: &pushedNPC)
            resolveParkourAndCabinCollisions(position: &pushedNPC)
            clampToArenaBounds(position: &pushedNPC, previousPosition: npcPositions[index], margin: 1.15)

            // Si el NPC chocó con un muro/roca y fue frenado, anular empuje residual
            if abs(pushedNPC.x - (npcPositions[index].x - normal.x * (overlap * npcPushShare))) > 0.001 {
                npcPushVelocities[index].x = 0
            }
            if abs(pushedNPC.z - (npcPositions[index].z - normal.y * (overlap * npcPushShare))) > 0.001 {
                npcPushVelocities[index].y = 0
            }

            npcPositions[index] = pushedNPC

            // Transferir impulso de empuje (empujón físico) al rival
            if inwardSpeed > 0.05 {
                let shoveStrength = min(5.2, max(1.8, inwardSpeed * 1.15))
                npcPushVelocities[index] -= normal * shoveStrength
            }

            // 2. Separar sólidamente al jugador respecto a la posición final del NPC (incluso si el NPC está acorralado contra una roca/pared)
            let finalNPC2D = SIMD2<Float>(npcPositions[index].x, npcPositions[index].z)
            let postOffset = SIMD2<Float>(playerPos.x, playerPos.z) - finalNPC2D
            let postDist = simd_length(postOffset)
            if postDist < minSeparation {
                let postNormal = postDist > 0.0001 ? postOffset / postDist : normal
                let correctedPlayer = finalNPC2D + postNormal * minSeparation
                playerPos.x = correctedPlayer.x
                playerPos.z = correctedPlayer.y
            }

            // 3. Respuesta de velocidad en el jugador (deslizamiento lateral + freno de impacto cuerpo a cuerpo)
            if inwardSpeed > 0 {
                horizontalVelocity += normal * (inwardSpeed * 0.78)
                if inwardSpeed > 1.6 && characterBumpAudioCooldown <= 0 {
                    characterBumpAudioCooldown = 0.28
                    let bumpIntensity = min(0.75, max(0.22, inwardSpeed / 4.5))
                    audio.playLanding(intensity: bumpIntensity)
                }
            }
        }
    }

    // 🎯 🦾 SpringArm Raycast Collision & Anti-Clipping System
    // Detecta muros, escaleras, tobogán, paredes/piso de piscina y rocas/pilares intermedios para acercar dinámicamente la cámara
    private func resolveCameraSpringArm(
        from origin: SIMD3<Float>,
        to target: SIMD3<Float>,
        isSubterranean: Bool
    ) -> SIMD3<Float> {
        let rayVec = target - origin
        let maxDist = simd_length(rayVec)
        guard maxDist > 0.05 else { return target }
        let rayDir = rayVec / maxDist
        let cameraBumper: Float = 0.35
        var closestHit: Float = maxDist

        // 1. Muros Perimetrales del Salón & Delimitación de Piscina
        if isSubterranean {
            let inOpening = origin.x >= -5.35 && origin.x <= 2.35 && origin.z >= -4.20 && origin.z <= 1.20
            let subCeil: Float = inOpening ? 1.5 : -5.00
            let bMin = SIMD3<Float>(-17.2, -11.0, -17.2)
            let bMax = SIMD3<Float>(17.2, subCeil, 17.2)
            for i in 0..<3 {
                let o = origin[i]
                let d = rayDir[i]
                if d > 1e-5 {
                    let t = (bMax[i] - o) / d
                    if t > 0.05 && t < closestHit { closestHit = t }
                } else if d < -1e-5 {
                    let t = (bMin[i] - o) / d
                    if t > 0.05 && t < closestHit { closestHit = t }
                }
            }
        } else if origin.y < -0.15 && origin.y > -4.75 {
            // 🏊‍♂️ En la piscina: delimitar estrictamente el rayo para no atravesar paredes de cerámica ni piso
            let poolBMin = SIMD3<Float>(-5.25, -4.42, -4.05)
            let poolBMax = SIMD3<Float>(2.25, 0.10, 1.05)
            for i in 0..<3 {
                let o = origin[i]
                let d = rayDir[i]
                if d > 1e-5 {
                    if i == 1 {
                        let tTop = (poolBMax[1] - o) / d
                        let exitPos = origin + rayDir * tTop
                        let inOpening = exitPos.x >= -5.20 && exitPos.x <= 2.20 && exitPos.z >= -4.00 && exitPos.z <= 1.00
                        if !inOpening {
                            if tTop > 0.05 && tTop < closestHit { closestHit = tTop }
                        }
                    } else {
                        let t = (poolBMax[i] - o) / d
                        if t > 0.05 && t < closestHit { closestHit = t }
                    }
                } else if d < -1e-5 {
                    let t = (poolBMin[i] - o) / d
                    if t > 0.05 && t < closestHit { closestHit = t }
                }
            }
            let roomBMin = SIMD3<Float>(-17.2, 0.20, -17.2)
            let roomBMax = SIMD3<Float>(17.2, 6.85, 17.2)
            for i in 0..<3 {
                let o = origin[i]
                let d = rayDir[i]
                if d > 1e-5 {
                    let t = (roomBMax[i] - o) / d
                    if t > 0.05 && t < closestHit { closestHit = t }
                } else if d < -1e-5 {
                    let t = (roomBMin[i] - o) / d
                    if t > 0.05 && t < closestHit { closestHit = t }
                }
            }
        } else {
            let inRainbowHall = origin.z > 17.5
            let bMin = inRainbowHall ? SIMD3<Float>(-26.4, 0.20, -17.2) : SIMD3<Float>(-17.2, 0.20, -17.2)
            let bMax = inRainbowHall ? SIMD3<Float>(26.4, 8.85, 71.4) : SIMD3<Float>(17.2, 6.85, 71.4)
            for i in 0..<3 {
                let o = origin[i]
                let d = rayDir[i]
                if d > 1e-5 {
                    let t = (bMax[i] - o) / d
                    if t > 0.05 && t < closestHit { closestHit = t }
                } else if d < -1e-5 {
                    let t = (bMin[i] - o) / d
                    if t > 0.05 && t < closestHit { closestHit = t }
                }
            }
        }

        // 2. Obstáculos, Pilares Azules y Rocas (Ray vs Ellipsoid: Anti-Oclusión completa)
        for rock in rtRiverRocks {
            let expanded = rock.radii * 1.25 + SIMD3<Float>(repeating: cameraBumper + 0.12)
            let relO = (origin - rock.center) / expanded
            let relD = rayDir / expanded
            let a = simd_dot(relD, relD)
            let b = 2.0 * simd_dot(relO, relD)
            let c = simd_dot(relO, relO) - 1.0
            let disc = b * b - 4.0 * a * c
            if disc >= 0 {
                let sqrtDisc = sqrt(disc)
                let t0 = (-b - sqrtDisc) / (2.0 * a)
                let t1 = (-b + sqrtDisc) / (2.0 * a)
                if t0 > 0.05 && t0 < closestHit {
                    closestHit = t0
                } else if t1 > 0.05 && t1 < closestHit && c < 0 {
                    closestHit = min(closestHit, 0.15)
                }
            }
        }

        // 3. Estructuras Sólidas (Torre de Tobogán, Escalera Vertical, Rampa, Trampolín, Paredes de Piscina y Deck)
        let staticAABBs: [(SIMD3<Float>, SIMD3<Float>)] = [
            // Plataforma alta del tobogán (X: -5.35..-2.25, Y: 5.4..7.0, Z: -17.2..-14.4)
            (SIMD3<Float>(-5.35, 5.45, -17.2), SIMD3<Float>(-2.25, 7.00, -14.4)),
            // Escalera metálica vertical (X: -4.55..-3.05, Y: 0..5.7, Z: -17.2..-16.5)
            (SIMD3<Float>(-4.55, 0.00, -17.2), SIMD3<Float>(-3.05, 5.70, -16.5)),
            // Rodadero y canaleta recta
            (SIMD3<Float>(-4.70, 0.05, -15.0), SIMD3<Float>(-1.80, 5.80, -3.60)),
            // Trampolín de salto
            (SIMD3<Float>(0.90, 2.70, -6.60), SIMD3<Float>(1.90, 3.05, -4.00)),
            // 🏊‍♂️ Paredes perimetrales de la piscina profunda (evita salir al vacío por los costados del agua)
            (SIMD3<Float>(-5.40, -4.60, -4.20), SIMD3<Float>(2.40, 0.15, -4.05)), // Pared Norte
            (SIMD3<Float>(-5.40, -4.60, 1.05), SIMD3<Float>(2.40, 0.15, 1.20)),  // Pared Sur
            (SIMD3<Float>(-5.40, -4.60, -4.20), SIMD3<Float>(-5.25, 0.15, 1.20)), // Pared Oeste
            (SIMD3<Float>(2.25, -4.60, -4.20), SIMD3<Float>(2.40, 0.15, 1.20)),  // Pared Este
            (SIMD3<Float>(-5.40, -4.65, -4.20), SIMD3<Float>(2.40, -4.42, 1.20)), // Piso Piscina
            // Escalera metálica blanca de la piscina (X: 2.10..2.30, Y: -0.85..0.35, Z: -2.35..-1.45)
            (SIMD3<Float>(2.10, -0.85, -2.35), SIMD3<Float>(2.30, 0.35, -1.45)),
            // Deck que rodea la piscina a Y = -0.12 (evita atravesar el suelo exterior al rotar en el agua)
            (SIMD3<Float>(-17.2, -0.30, -17.2), SIMD3<Float>(17.2, 0.05, -4.08)),
            (SIMD3<Float>(-17.2, -0.30, 1.08), SIMD3<Float>(17.2, 0.05, 17.2)),
            (SIMD3<Float>(-17.2, -0.30, -4.08), SIMD3<Float>(-5.28, 0.05, 1.08)),
            (SIMD3<Float>(2.28, -0.30, -4.08), SIMD3<Float>(17.2, 0.05, 1.08)),
            // 🌈 Muros Perimetrales del Gran Salón Arcoíris (Z: 17.8..72.0, X: -27.0..27.0, Y: 0..9.0)
            (SIMD3<Float>(-27.2, 0.0, 17.8), SIMD3<Float>(-26.8, 9.0, 72.2)), // Muro Oeste
            (SIMD3<Float>( 26.8, 0.0, 17.8), SIMD3<Float>( 27.2, 9.0, 72.2)), // Muro Este
            (SIMD3<Float>(-27.2, 0.0, 71.8), SIMD3<Float>( 27.2, 9.0, 72.2)), // Muro Sur Final
            // Muro Divisor Sur (Alas Este y Oeste en Z = 17.8)
            (SIMD3<Float>(-18.0, 0.0, 17.6), SIMD3<Float>(-5.2, 7.0, 18.0)),
            (SIMD3<Float>(  5.2, 0.0, 17.6), SIMD3<Float>( 18.0, 7.0, 18.0))
        ]

        var allAABBs = staticAABBs
        // 🌈 Bloques de Parkour de Cuerpo Completo y Cabañas Arcoíris (evita que la cámara 3ra persona atraviese los bloques)
        for box in rtRainbowParkourBoxes {
            let half = box.size * 0.5
            allAABBs.append((box.center - half, box.center + half))
        }

        for (boxMin, boxMax) in allAABBs {
            let expMin = boxMin - SIMD3<Float>(repeating: cameraBumper)
            let expMax = boxMax + SIMD3<Float>(repeating: cameraBumper)

            var tMin: Float = -Float.greatestFiniteMagnitude
            var tMax: Float = Float.greatestFiniteMagnitude
            var hit = true
            for i in 0..<3 {
                let o = origin[i]
                let d = rayDir[i]
                if abs(d) < 1e-6 {
                    if o < expMin[i] || o > expMax[i] { hit = false; break }
                } else {
                    var t1 = (expMin[i] - o) / d
                    var t2 = (expMax[i] - o) / d
                    if t1 > t2 { swap(&t1, &t2) }
                    tMin = max(tMin, t1)
                    tMax = min(tMax, t2)
                    if tMin > tMax { hit = false; break }
                }
            }
            if hit {
                if tMin > 0.05 && tMin < closestHit {
                    closestHit = tMin
                } else if tMax > 0.05 && tMin < 0 && tMax < closestHit {
                    closestHit = min(closestHit, 0.08)
                }
            }
        }

        let finalDist = max(0.08, min(maxDist, closestHit - cameraBumper))
        return origin + rayDir * finalDist
    }

    private func writeUniforms(texture: MTLTexture, dt: Float) {
        let currentlyInPool = isInsidePoolXZ(playerPosition) && playerPosition.y <= 0.35
        let isSubterraneanTarget = playerPosition.y <= -4.75
        let isUnderwaterCamera = (currentlyInPool || isSubterraneanTarget) && playerPosition.y < -0.10

        // 🎯 Elevación del punto de mira (lookAt) hacia la cabeza / hombro superior para evitar enfocar la espalda baja
        let targetOffsetY: Float
        if isPlayerDead || isRecoveringInChamber {
            targetOffsetY = 0.20 // 🟢 Enfoque cinemático directo al charco de slime burbujeante derretido en el suelo
        } else if isCoverActive {
            targetOffsetY = (cameraMode == .firstPerson ? 0.70 : 0.65)
        } else if currentlyInPool && cameraMode == .thirdPerson {
            targetOffsetY = 1.35
        } else if isClimbingLadder {
            targetOffsetY = 1.40
        } else {
            targetOffsetY = (cameraMode == .firstPerson ? 1.56 : 1.28)
        }

        let rawTarget = playerPosition + SIMD3<Float>(0, targetOffsetY, 0)
        let follow = min(1, dt * (cameraMode == .firstPerson ? 24 : 18))
        smoothedCameraTarget += (rawTarget - smoothedCameraTarget) * follow

        let viewForward = SIMD3<Float>(-sin(cameraYaw), 0, -cos(cameraYaw))
        var rawRight = SIMD3<Float>(cos(cameraYaw), 0, -sin(cameraYaw))
        if simd_length_squared(rawRight) < 0.0001 { rawRight = SIMD3<Float>(1, 0, 0) }
        rawRight = simd_normalize(rawRight)

        let cameraPosition: SIMD3<Float>
        let cameraForward: SIMD3<Float>
        let fieldOfView: Float

        let isDeflatedOrDead = isPlayerDead || isRecoveringInChamber
        // 🔒 1ª Persona FPS Fija: Se mantiene siempre en primera persona (la 3ª persona se conserva en el código pero archivada/inactiva)
        let effectiveCameraMode: GameCameraMode = cameraMode

        if effectiveCameraMode == .firstPerson {
            let pitchCosine = cos(firstPersonPitch)
            cameraForward = simd_normalize(SIMD3<Float>(
                viewForward.x * pitchCosine,
                sin(firstPersonPitch),
                viewForward.z * pitchCosine
            ))
            var camPos = smoothedCameraTarget + viewForward * 0.10
            if isClimbingLadder {
                camPos.z = max(-16.12, camPos.z)
            }

            // 🛡️ Collider Fino de Cámara FPS (Anti-Clipping & Near-Plane Protection)
            // a) Tramo estrecho del pozo de la piscina (-4.70 <= Y < 0.25):
            if camPos.y < 0.25 && camPos.y >= -4.75 {
                camPos.x = max(-5.05, min(2.05, camPos.x))
                camPos.z = max(-3.85, min(0.85, camPos.z))
            }
            // b) Cámara subterránea abisal (Y < -4.75):
            else if camPos.y < -4.75 {
                camPos.x = max(-17.3, min(17.3, camPos.x))
                camPos.z = max(-17.3, min(17.3, camPos.z))
                camPos.y = max(-11.3, camPos.y)
                let underShaft = camPos.x >= -5.15 && camPos.x <= 2.15 && camPos.z >= -3.95 && camPos.z <= 0.95
                if !underShaft {
                    camPos.y = min(-4.95, camPos.y)
                }
            }
            // c) Gran Salón Arcoíris (Z >= 17.5):
            else if camPos.z >= 17.5 {
                camPos.x = max(-26.4, min(26.4, camPos.x))
                camPos.z = max(18.0, min(71.4, camPos.z))
                camPos.y = max(0.15, min(8.6, camPos.y))

                // Anti-clipping contra cada bloque de parkour:
                let camSkin: Float = 0.18
                for box in rtRainbowParkourBoxes {
                    let bMin = box.center - box.size * 0.5 - SIMD3<Float>(repeating: camSkin)
                    let bMax = box.center + box.size * 0.5 + SIMD3<Float>(repeating: camSkin)
                    if camPos.x > bMin.x && camPos.x < bMax.x &&
                       camPos.y > bMin.y && camPos.y < bMax.y &&
                       camPos.z > bMin.z && camPos.z < bMax.z {
                        let dMinX = camPos.x - bMin.x
                        let dMaxX = bMax.x - camPos.x
                        let dMinY = camPos.y - bMin.y
                        let dMaxY = bMax.y - camPos.y
                        let dMinZ = camPos.z - bMin.z
                        let dMaxZ = bMax.z - camPos.z
                        let minD = min(min(min(dMinX, dMaxX), min(dMinY, dMaxY)), min(dMinZ, dMaxZ))
                        if minD == dMinX { camPos.x = bMin.x }
                        else if minD == dMaxX { camPos.x = bMax.x }
                        else if minD == dMinY { camPos.y = bMin.y }
                        else if minD == dMaxY { camPos.y = bMax.y }
                        else if minD == dMinZ { camPos.z = bMin.z }
                        else if minD == dMaxZ { camPos.z = bMax.z }
                    }
                }
            }
            // d) Patio / Salón Principal (Z < 17.5, Y >= 0.0):
            else {
                camPos.x = max(-17.3, min(17.3, camPos.x))
                camPos.z = max(-17.3, min(17.3, camPos.z))
                camPos.y = max(0.15, min(6.8, camPos.y))
            }

            cameraPosition = camPos
            fieldOfView = 72
        } else {
            // ☁️ 🐢 Super Mario 64 Lakitu Camera + SpringArm Anti-Clipping
            let distance: Float = isDeflatedOrDead ? 2.6 : (isUnderwaterCamera ? 3.4 : 4.0)
            let shoulderOffset: Float = isDeflatedOrDead ? 0.0 : (isUnderwaterCamera ? 0.28 : 0.36)
            let pitchClamped = isDeflatedOrDead ? 0.42 : max(-0.25, min(0.68, orbitPitch))
            let cosP = cos(pitchClamped)
            let sinP = sin(pitchClamped)

            // Vector unitario esférico hacia atrás/arriba de la cámara respecto al pivote
            let backwardDir = SIMD3<Float>(
                sin(cameraYaw) * cosP,
                sinP,
                cos(cameraYaw) * cosP
            )

            var idealLakituPos = smoothedCameraTarget + backwardDir * distance + rawRight * shoulderOffset

            if isSubterraneanTarget {
                let inOpening = isInsidePoolXZ(playerPosition)
                if inOpening {
                    idealLakituPos.y = max(-10.2, min(0.60, idealLakituPos.y))
                } else {
                    idealLakituPos.y = max(-10.2, min(-5.15, idealLakituPos.y))
                }
            } else if currentlyInPool {
                idealLakituPos.y = max(smoothedCameraTarget.y + 0.30, min(1.80, idealLakituPos.y))
            } else {
                idealLakituPos.y = max(0.25, idealLakituPos.y)
            }

            // 🎯 🦾 SpringArm Raycast: Acercar inmediatamente la cámara si un muro, escalera o pilar se interpone
            let safeCameraPos = resolveCameraSpringArm(
                from: smoothedCameraTarget,
                to: idealLakituPos,
                isSubterranean: isSubterraneanTarget
            )

            // Organic Lakitu Spring-Damped Trailing con zoom-in instantáneo anti-clipping
            let lagFactor = exp(-dt * 9.5)
            if simd_distance_squared(lakituPosition, safeCameraPos) > 64.0 {
                lakituPosition = safeCameraPos
            } else {
                let currentDistToTarget = simd_distance(lakituPosition, smoothedCameraTarget)
                let safeDistToTarget = simd_distance(safeCameraPos, smoothedCameraTarget)
                if safeDistToTarget < currentDistToTarget - 0.05 {
                    lakituPosition = mix(safeCameraPos, lakituPosition, t: exp(-dt * 26.0))
                } else {
                    lakituPosition = mix(safeCameraPos, lakituPosition, t: lagFactor)
                }
            }

            // 🔒 Contención estricta en piscina y reino subterráneo: la cámara jamás sale al vacío exterior
            if currentlyInPool && lakituPosition.y < 0.15 {
                lakituPosition.x = max(-5.15, min(2.15, lakituPosition.x))
                lakituPosition.z = max(-3.95, min(0.95, lakituPosition.z))
                lakituPosition.y = max(-4.40, lakituPosition.y)
            } else if isSubterraneanTarget {
                let inOpening = isInsidePoolXZ(playerPosition)
                if !inOpening {
                    lakituPosition.y = min(-4.95, lakituPosition.y)
                }
            }

            cameraPosition = lakituPosition
            let shoulderPivot = smoothedCameraTarget + rawRight * shoulderOffset
            let aimTarget = shoulderPivot - backwardDir * 30.0
            cameraForward = simd_normalize(aimTarget - cameraPosition)
            fieldOfView = isUnderwaterCamera ? 68 : 62
        }

        var right = simd_cross(cameraForward, SIMD3<Float>(0, 1, 0))
        if simd_length_squared(right) < 0.0001 { right = SIMD3<Float>(1, 0, 0) }
        right = simd_normalize(right)
        let up = simd_normalize(simd_cross(right, cameraForward))
        let aspect = Float(texture.width) / max(1, Float(texture.height))
        let imagePlaneHeight = tan(fieldOfView * .pi / 360)
        let toolOrigin: SIMD3<Float>
        var toolDirection: SIMD3<Float>
        if cameraMode == .firstPerson {
            // 🎯 Anclaje anatómico exacto en la boca del cañón del Blaster / Linterna en la mano derecha (visión FPS):
            // La mano del slime está en (right: 0.22, down: 0.18) y el cañón proyecta la boca a 0.65m al frente
            let toolRightOffset: Float = 0.22
            let toolDownOffset: Float = 0.18
            let toolForwardOffset: Float = (heldTool == .laser) ? 0.65 : 0.45
            toolOrigin = cameraPosition + right * toolRightOffset - up * toolDownOffset + cameraForward * toolForwardOffset

            // Apuntar directamente hacia el centro de la retícula para que el haz sea ultra preciso:
            let aimPoint = cameraPosition + cameraForward * 35.0
            let toAim = aimPoint - toolOrigin
            toolDirection = simd_length_squared(toAim) > 0.001 ? simd_normalize(toAim) : cameraForward
        } else {
            // 🎯 En 3ra persona y reflejos en espejos: anclar el origen EXACTAMENTE en la boca del cañón dorado/rubí en la mano derecha
            let isGroundedInPool = currentlyInPool && playerPosition.y >= -0.25
            let isDeepSubmerged = (currentlyInPool || isSubterraneanTarget) && playerPosition.y < -0.25
            let pPitch: Float
            if isPlayerDead {
                pPitch = 1.57
            } else if isCoverActive || isClimbingLadder || isGroundedInPool {
                pPitch = 0
            } else if isDeepSubmerged && abs(verticalVelocity) > 0.25 {
                pPitch = max(-0.45, min(0.45, (orbitPitch - 0.22) * 0.9))
            } else if isSlidingOnToboggan {
                pPitch = -0.62
            } else {
                pPitch = 0
            }

            let toolLocalOffset: SIMD3<Float>
            if isCoverActive {
                toolLocalOffset = SIMD3<Float>(0.28, 0.46, 0.68)
            } else if isSlidingOnToboggan {
                toolLocalOffset = SIMD3<Float>(0.42, 0.40, 0.60)
            } else if isDeepSubmerged {
                toolLocalOffset = SIMD3<Float>(0.47, 0.68, 0.62)
            } else {
                toolLocalOffset = SIMD3<Float>(0.47, 0.69, 0.59)
            }

            let cy = cos(playerYaw), sy = sin(playerYaw)
            let cp = cos(pPitch), sp = sin(pPitch)
            let col0 = SIMD3<Float>(cy, sy * sp, -sy * cp)
            let col1 = SIMD3<Float>(0, cp, sp)
            let col2 = SIMD3<Float>(sy, -cy * sp, cy * cp)

            var pPos: SIMD3<Float> = isSlidingOnToboggan ? playerPosition + SIMD3<Float>(0, -0.15, 0) : playerPosition
        if isDeflatedOrDead {
            let inPool = isInsidePoolXZ(playerPosition) && playerPosition.y <= 0.35
            let floorY = groundHeight(at: playerPosition, insidePool: inPool)
            pPos.y = min(pPos.y, floorY) // Slime siempre pegado a la superficie del suelo
        }
            toolOrigin = pPos + col0 * toolLocalOffset.x + col1 * toolLocalOffset.y + col2 * toolLocalOffset.z

            let aimPoint = cameraPosition + cameraForward * 32.0
            let toAim = aimPoint - toolOrigin
            toolDirection = simd_length_squared(toAim) > 0.001 ? simd_normalize(toAim) : cameraForward
        }

        let renderTool: GameHeldTool
        switch heldTool {
        case .laser: renderTool = (laserBattery > 0.005) ? .laser : .none
        case .mirror: renderTool = (!mirrorOverheated) ? .mirror : .none
        default: renderTool = heldTool
        }

        let isUnderwaterShooting = currentlyInPool && cameraPosition.y < 0.20
        if isUnderwaterShooting && heldTool == .laser {
            let waterNormal = SIMD3<Float>(0, 1, 0)
            let eta: Float = 1.0 / 1.33 // Snell's Law underwater refraction index!
            let cosI = max(-1.0, min(1.0, -simd_dot(waterNormal, toolDirection)))
            let sinT2 = eta * eta * (1.0 - cosI * cosI)
            if sinT2 < 1.0 {
                let cosT = sqrt(1.0 - sinT2)
                toolDirection = simd_normalize(eta * toolDirection + (eta * cosI - cosT) * waterNormal)
            }
        }

        let isBlackout = lightStates.areAllLightsOff
        let isSubterraneanIlluminated = !isBlackout && (cameraPosition.y <= -4.75 || playerPosition.y <= -4.75)
        let isPoolSubmerged = !isBlackout && (currentlyInPool && cameraPosition.y < 0.20)
        let activeLightPos = isSubterraneanIlluminated ? SIMD4<Float>(0.0, -5.2, 0.0, 1) : (isPoolSubmerged ? SIMD4<Float>(-1.5, -3.5, -1.5, 1) : SIMD4<Float>(-7.55, 2.72, 12.65, 1))
        let activeLightColor: SIMD4<Float>
        if isBlackout {
            activeLightColor = SIMD4<Float>(0, 0, 0, 0)
        } else if isSubterraneanIlluminated {
            activeLightColor = SIMD4<Float>(0.10, 0.95, 0.98, 48.0)
        } else if isPoolSubmerged {
            activeLightColor = SIMD4<Float>(0.08, 0.85, 0.95, 38.0)
        } else {
            activeLightColor = SIMD4<Float>(1.0, 0.66, 0.24, lightStates.effectiveIntensity(.post) * 46)
        }

        let moveMagnitude = Float(hypot(joystick.dx, joystick.dy))
        let swimMotionValue: Float = (cameraMode == .firstPerson) ? (1.0 + min(1.0, moveMagnitude * 1.5)) : 0.0

        var effectiveToolOrigin = toolOrigin
        var effectiveToolDirection = toolDirection
        var effectiveToolParamY: Float = 0
        if renderTool == .flashlight {
            effectiveToolParamY = flashlightBattery
        } else if renderTool == .laser {
            effectiveToolParamY = (laserActiveRemaining > 0) ? max(0.05, laserPropagationDistance) : 0.0
        } else if renderTool == .mirror {
            let effYaw = playerYaw + shieldYawOffset
            let baseMirrorPitch: Float = (cameraMode == .firstPerson) ? firstPersonPitch : -(orbitPitch - 0.22) * 1.15
            let effPitch = max(-0.95, min(0.95, baseMirrorPitch + shieldPitchOffset))
            effectiveToolOrigin = playerPosition + SIMD3<Float>(sin(effYaw) * 0.58, 1.12 + sin(effPitch) * 0.25, cos(effYaw) * 0.58)
            effectiveToolDirection = simd_normalize(SIMD3<Float>(
                sin(effYaw) * cos(effPitch),
                sin(effPitch),
                cos(effYaw) * cos(effPitch)
            ))
            effectiveToolParamY = isMirrorReflectingLaser ? 2.0 : (mirrorActiveRemaining > 0 ? 1.5 : 1.0)
        }

        var uniforms = RTUniforms(
            viewport: SIMD4<Float>(Float(texture.width), Float(texture.height), elapsedTime, rayBouncesEnabled ? 1 : 0),
            cameraPosition: SIMD4<Float>(cameraPosition, 1),
            cameraRight: SIMD4<Float>(right * aspect * imagePlaneHeight, 0),
            cameraUp: SIMD4<Float>(up * imagePlaneHeight, 0),
            cameraForward: SIMD4<Float>(cameraForward, 0),
            lightPosition: activeLightPos,
            lightColor: activeLightColor,
            waterSimulation: SIMD4<Float>(dt, elapsedTime, swimMotionValue, instanceAccelerationStructure != nil ? 1 : 0),
            waterImpulse: pendingWaterImpulse,
            toolOrigin: SIMD4<Float>(effectiveToolOrigin, 1),
            toolDirection: SIMD4<Float>(effectiveToolDirection, 0),
            toolParameters: SIMD4<Float>(Float(renderTool.rawValue), effectiveToolParamY, isSlowMotionActive ? 1.0 : 0.0, isSplitScreenMode ? 1.0 : 0.0),
            lightStates: SIMD4<Float>(
                lightStates.effectiveIntensity(.post),
                lightStates.effectiveIntensity(.piscinaNeon),
                lightStates.effectiveIntensity(.sheeritNeon),
                lightStates.effectiveIntensity(.poolStrips)
            ),
            secondaryCameraPosition: SIMD4<Float>(secondaryCameraPos, 1.0),
            secondaryCameraForward: SIMD4<Float>(secondaryCameraFwd, 0.0)
        )
        lastCameraPosition = cameraPosition
        lastCameraRight = right * aspect * imagePlaneHeight
        lastCameraUp = up * imagePlaneHeight
        lastCameraForward = cameraForward
        lastToolOrigin = effectiveToolOrigin
        lastToolDirection = effectiveToolDirection
        withUnsafeBytes(of: &uniforms) { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            uniformBuffer.contents().copyMemory(from: baseAddress, byteCount: bytes.count)
        }
    }

    private func writeInstanceDescriptors() {
        let isDeflatedOrDead = isPlayerDead || isRecoveringInChamber
        // 🔒 1ª Persona FPS Fija: Se mantiene siempre en primera persona (la 3ª persona se conserva en el código pero archivada/inactiva)
        let effectiveCameraMode: GameCameraMode = cameraMode
        let currentlyInPool = isInsidePoolXZ(playerPosition) && playerPosition.y <= 0.35
        let isSubterraneanTarget = playerPosition.y <= -4.75
        let isGroundedInPool = currentlyInPool && playerPosition.y >= -0.25
        let isDeepSubmerged = (currentlyInPool || isSubterraneanTarget) && playerPosition.y < -0.25
        let isSwimmingInWater = isDeepSubmerged && !isClimbingLadder && !isSlidingOnToboggan
        let isPlayerDead = self.isPlayerDead
        let isMirrorActive = (heldTool == .mirror && !mirrorOverheated)
        let isMoving = hypot(joystick.dx, joystick.dy) > 0.15

        let melt = playerMeltProgress
        let isRecovering = isRecoveringInChamber
        let recoveryFrac = isRecovering ? max(0.0, min(1.0, 1.0 - recoveryTimeRemaining / 5.0)) : 0.0
        let effectiveMelt = isRecovering ? (1.0 - recoveryFrac) * melt : melt
        let pumpPuff = (isRecovering && recoveryFrac > 0) ? abs(sin(elapsedTime * 14.0)) * (1.0 - recoveryFrac * 0.4) * 0.20 : 0.0

        let wobble = sin(elapsedTime * 9.0) * 0.05 * effectiveMelt
        let pScale: SIMD3<Float>
        let pPitch: Float
        if effectiveMelt > 0.01 {
            // 🟢 Slime Deflation & Inflation Animation: aplastado en charco o inflando con rebote de bomba de aire
            let scaleY = max(0.06, (1.0 - effectiveMelt * 0.94) + wobble * 0.3 + pumpPuff)
            let scaleXZ = max(0.85, 1.0 + effectiveMelt * 1.30 + wobble - pumpPuff * 0.12)
            pScale = SIMD3<Float>(scaleXZ, scaleY, scaleXZ)
            pPitch = 0.0 // Slime derretido apoyado horizontalmente sobre el suelo
        } else if isPlayerDead {
            // ☠️ Fallback si no ha comenzado el derretimiento: tumbado
            pScale = SIMD3<Float>(1, 1, 1)
            pPitch = 1.57
        } else if isCoverActive || isClimbingLadder || isGroundedInPool {
            // 🧍 De pie / caminando en el fondo de la piscina o en cobertura/escalera: estrictamente vertical (0 pitch)
            pScale = SIMD3<Float>(1, 1, 1)
            pPitch = 0
        } else if isSwimmingInWater {
            // 🏊‍♂️ Postura natural de nado: cuerpo inclinado horizontalmente cortando el agua
            pScale = SIMD3<Float>(1, 1, 1)
            let swimTilt: Float = isMoving ? -0.42 : -0.12
            pPitch = swimTilt + max(-0.35, min(0.35, (orbitPitch - 0.22) * 0.8))
        } else if isSlidingOnToboggan {
            pScale = SIMD3<Float>(1, 1, 1)
            pPitch = -0.62
        } else {
            pScale = SIMD3<Float>(1, 1, 1)
            pPitch = 0
        }

        let rMelt = remotePlayerMeltProgress
        let rWobble = sin(elapsedTime * 9.0) * 0.05 * rMelt
        let rScale: SIMD3<Float> = rMelt > 0.01
            ? SIMD3<Float>(1.0 + rMelt * 1.30 + rWobble, max(0.06, (1.0 - rMelt * 0.94) + rWobble * 0.3), 1.0 + rMelt * 1.30 + rWobble)
            : SIMD3<Float>(1, 1, 1)

        var pPos: SIMD3<Float> = isSlidingOnToboggan ? playerPosition + SIMD3<Float>(0, -0.15, 0) : playerPosition
        if isDeflatedOrDead {
            let inPool = isInsidePoolXZ(playerPosition) && playerPosition.y <= 0.35
            let floorY = groundHeight(at: playerPosition, insidePool: inPool)
            pPos.y = min(pPos.y, floorY) // Slime siempre pegado a la superficie del suelo
        }
        let effYaw = playerYaw + shieldYawOffset
        let baseMirrorPitch: Float = (cameraMode == .firstPerson) ? firstPersonPitch : -(orbitPitch - 0.22) * 1.15
        let effPitch = max(-0.95, min(0.95, baseMirrorPitch + shieldPitchOffset))
        let isFirstPerson = (effectiveCameraMode == .firstPerson)
        let shieldPos: SIMD3<Float>
        let shieldMask: UInt32
        if isMirrorActive {
            shieldPos = pPos + SIMD3<Float>(sin(effYaw) * 0.58, 1.12 + sin(effPitch) * 0.25, cos(effYaw) * 0.58)
            shieldMask = isFirstPerson ? 0x02 : 0x01
        } else {
            shieldPos = SIMD3<Float>(0, -500, 0)
            shieldMask = 0x00
        }

        // 🎯 🦾 Oclusión del Jugador y Near Clipping con Espejos Realistas:
        let headPos = playerPosition + SIMD3<Float>(0, 1.15, 0)
        let distToCamera = simd_distance(lakituPosition, headPos)
        let shouldHideInThirdPerson = !isDeflatedOrDead && (!isFirstPerson && (distToCamera < 1.25 || (isClimbingLadder && distToCamera < 1.50)))
        let playerRenderPos = shouldHideInThirdPerson ? SIMD3<Float>(0, -500, 0) : pPos
        let playerInstanceMask: UInt32 = isDeflatedOrDead ? 0x01 : (isFirstPerson ? 0x02 : (shouldHideInThirdPerson ? 0x00 : 0x01))

        let playerASIndex: UInt32
        if isPlayerDead {
            playerASIndex = 1
        } else if isClimbingLadder {
            playerASIndex = 10 // 🪜 Climb Vertical Ladder (Sujeto a los peldaños)
        } else if isCoverActive {
            playerASIndex = 6 // 🛡️ GTA Crouch Cover
        } else if isSlidingOnToboggan {
            playerASIndex = 8 // 🛷 Sit Tobogán
        } else if isSwimmingInWater {
            playerASIndex = 7 // 🏊 Swim Pose in water (brazos arqueados y aletas de buceo)
        } else if isMoving {
            playerASIndex = 9 // 🏃 Walk / Run articulado
        } else {
            playerASIndex = 1 // 🧍 Stand articulado
        }

        var descriptors: [MTLAccelerationStructureInstanceDescriptor] = [
            Self.makeInstanceDescriptor(translation: .zero, yaw: 0, pitch: 0, mask: 0x01, accelerationStructureIndex: 0),
            Self.makeInstanceDescriptor(translation: playerRenderPos, yaw: playerYaw, pitch: pPitch, scale: pScale, mask: playerInstanceMask, accelerationStructureIndex: playerASIndex),
            Self.makeInstanceDescriptor(translation: .zero, yaw: 0, pitch: 0, mask: 0x04, accelerationStructureIndex: 2),
            Self.makeInstanceDescriptor(translation: floatPosition, yaw: floatYaw, pitch: 0, mask: 0x01, accelerationStructureIndex: 3),
            makeNPCInstanceDescriptor(index: 0),
            makeNPCInstanceDescriptor(index: 1),
            makeNPCInstanceDescriptor(index: 2),
            makeNPCInstanceDescriptor(index: 3),
            makeNPCInstanceDescriptor(index: 4),
            Self.makeInstanceDescriptor(translation: shieldPos, yaw: effYaw, pitch: effPitch, mask: shieldMask, accelerationStructureIndex: 5)
        ]

        // Hasta 7 jugadores remotos simultáneos (8 jugadores totales en sala para 4 vs 4 o escuadrón)
        let activeAgents: [RemoteAgentState]
        if !remoteAgents.isEmpty {
            activeAgents = Array(remoteAgents.prefix(7))
        } else if isRemotePlayerConnected {
            activeAgents = [RemoteAgentState(
                peerID: "remote_primary",
                position: remotePlayerPosition,
                yaw: remotePlayerYaw,
                heldToolRaw: remotePlayerHeldTool.rawValue,
                isRecovering: remotePlayerIsRecovering
            )]
        } else {
            activeAgents = []
        }

        for slot in 0..<7 {
            if slot < activeAgents.count {
                let agent = activeAgents[slot]
                let smoothPos = smoothedRemoteAgents[agent.peerID] ?? (slot == 0 ? smoothedRemotePos : agent.position)
                var renderPos = smoothPos
                let isAgentDeflated = agent.isRecovering || (slot == 0 && (remotePlayerIsRecovering || rMelt > 0.01))
                if isAgentDeflated {
                    let remoteInPool = isInsidePoolXZ(smoothPos) && smoothPos.y <= 0.35
                    let remoteGround = groundHeight(at: smoothPos, insidePool: remoteInPool)
                    renderPos.y = remoteGround // ¡La plasta siempre se apoya estrictamente sobre el piso o plataforma!
                }
                let isMovingAgent = simd_distance_squared(smoothPos, agent.position) > 0.002 && !isAgentDeflated
                let agentAS: UInt32 = isMovingAgent ? 9 : 1
                let agentScale: SIMD3<Float> = slot == 0 ? rScale : SIMD3<Float>(1, 1, 1)
                let agentTool = GameHeldTool(rawValue: agent.heldToolRaw) ?? .none
                let hasShield = (agentTool == .mirror && !agent.isRecovering)

                descriptors.append(
                    Self.makeInstanceDescriptor(
                        translation: renderPos,
                        yaw: agent.yaw,
                        pitch: 0,
                        scale: agentScale,
                        mask: 0x01,
                        accelerationStructureIndex: agentAS
                    )
                )
                descriptors.append(
                    Self.makeInstanceDescriptor(
                        translation: hasShield
                            ? (smoothPos + SIMD3<Float>(0, 1.08, 0) + SIMD3<Float>(sin(agent.yaw), 0, cos(agent.yaw)) * 0.52)
                            : SIMD3<Float>(0, -500, 0),
                        yaw: agent.yaw,
                        pitch: 0,
                        mask: hasShield ? 0x01 : 0x00,
                        accelerationStructureIndex: 5
                    )
                )
            } else {
                descriptors.append(Self.makeInstanceDescriptor(translation: SIMD3<Float>(0, -500, 0), yaw: 0, pitch: 0, mask: 0x00, accelerationStructureIndex: 1))
                descriptors.append(Self.makeInstanceDescriptor(translation: SIMD3<Float>(0, -500, 0), yaw: 0, pitch: 0, mask: 0x00, accelerationStructureIndex: 5))
            }
        }

        // 🌟 Gran Espejo Mágico / Cuadro Portal estilo Super Mario 64 (Z = 17.8)
        let isGateUnlocked = isRainbowGateUnlocked
        if isGateUnlocked && !previousGateUnlocked {
            previousGateUnlocked = true
            audio.playRecoveryCompleteSound()
        } else if !isGateUnlocked {
            previousGateUnlocked = false
        }
        // El cuadro/espejo se mantiene SIEMPRE visible en Z = 17.8; al desbloquearlo el jugador lo atraviesa como en Mario 64
        descriptors.append(Self.makeInstanceDescriptor(translation: SIMD3<Float>(0, 0, 17.8), yaw: 0, pitch: 0, mask: 0x01, accelerationStructureIndex: 12))

        // 💨 Bomba de Aire Neumática 3D (AS Index 13)
        let pumpPos: SIMD3<Float>
        let pumpMask: UInt32
        let pumpAnim = Float(abs(sin(Double(elapsedTime) * 14.0)))
        let pumpScale = SIMD3<Float>(1.0, 0.88 + pumpAnim * 0.24, 1.0)
        let pumpYaw: Float

        if isRecoveringInChamber {
            // Colocada justo al lado del charco de slime en el suelo
            let inPool = isInsidePoolXZ(playerPosition) && playerPosition.y <= 0.35
            let floorY = groundHeight(at: playerPosition, insidePool: inPool)
            pumpPos = SIMD3<Float>(playerPosition.x + cos(playerYaw + 1.2) * 0.68, floorY - 0.02, playerPosition.z + sin(playerYaw + 1.2) * 0.68)
            pumpYaw = playerYaw + 1.57
            pumpMask = 0x01
        } else if isRemotePlayerConnected && remotePlayerIsRecovering && simd_distance(playerPosition, smoothedRemotePos) < 2.5 {
            let inPool = isInsidePoolXZ(smoothedRemotePos) && smoothedRemotePos.y <= 0.35
            let floorY = groundHeight(at: smoothedRemotePos, insidePool: inPool)
            pumpPos = SIMD3<Float>(smoothedRemotePos.x + 0.65, floorY - 0.02, smoothedRemotePos.z)
            pumpYaw = 0.0
            pumpMask = 0x01
        } else {
            pumpPos = SIMD3<Float>(0, -500, 0)
            pumpYaw = 0.0
            pumpMask = 0x00
        }
        descriptors.append(Self.makeInstanceDescriptor(translation: pumpPos, yaw: pumpYaw, pitch: 0, scale: pumpScale, mask: pumpMask, accelerationStructureIndex: 13))

        descriptors.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            instanceBuffer.contents().copyMemory(from: baseAddress, byteCount: bytes.count)
        }
    }

    private func makeNPCInstanceDescriptor(index: Int) -> MTLAccelerationStructureInstanceDescriptor {
        let isColossalGolem = (index == 4 && currentWave >= 3)
        let isFlying = isBotFlyingDrone(index: index)
        let baseScale: Float = isColossalGolem ? 1.65 : (isFlying ? npcBaseScales[index] * 0.90 : npcBaseScales[index])
        let isFotofago = index >= 2
        let asIndex: UInt32 = isFotofago ? 11 : 4
        let isAlive = npcHealths[index] > 0 && npcRespawnTimers[index] <= 0 && !isWaveIntermission
        let melt = npcMeltProgress[index]
        let isMelting = !isAlive && melt > 0.005 && melt < 1.0 && !isWaveIntermission && !isVersusMode

        if isAlive {
            // Animación pesada de respiración, gravitación de cristales y zancada del Fotófago / Gólem Colosal / Drones Aéreos
            let bobFreq: Float = isFlying ? 4.2 : (isColossalGolem ? 2.4 : (isFotofago ? 3.4 : 5.8))
            let bobAmp: Float = isFlying ? 0.085 : (isColossalGolem ? 0.068 : (isFotofago ? 0.048 : 0.024))
            let strideBob = isFlying ? (sin(elapsedTime * bobFreq + Float(index) * 1.5) * bobAmp) : (abs(sin(elapsedTime * bobFreq + Float(index) * 1.4)) * bobAmp)
            let breathe = 1.0 + sin(elapsedTime * 2.6 + Float(index)) * 0.028
            let swayPitch: Float = isFlying ? -0.18 : sin(elapsedTime * (bobFreq * 0.5) + Float(index)) * (isFotofago ? 0.042 : 0.020)
            let pos = npcPositions[index] + SIMD3<Float>(0, strideBob, 0)
            let scale = SIMD3<Float>(baseScale * breathe, isFlying ? baseScale * 0.85 : baseScale, baseScale * breathe)
            return Self.makeInstanceDescriptor(
                translation: pos,
                yaw: npcYaws[index],
                pitch: swayPitch,
                scale: scale,
                mask: 0x01,
                accelerationStructureIndex: asIndex
            )
        } else if isMelting {
            // 🧪 Animación de Disolución / Derretimiento Líquido Cromático en el suelo
            let wobble = sin(elapsedTime * 12.0 + Float(index) * 1.7) * 0.06 * melt
            let scaleY = baseScale * max(0.035, (1.0 - melt * 0.965) + wobble * 0.25)
            let scaleXZ = baseScale * (1.0 + melt * 1.75 + wobble)
            let scale = SIMD3<Float>(scaleXZ, scaleY, scaleXZ)
            return Self.makeInstanceDescriptor(
                translation: npcDeathPositions[index],
                yaw: npcYaws[index] + melt * 0.35,
                pitch: 0,
                scale: scale,
                mask: 0x01,
                accelerationStructureIndex: asIndex
            )
        } else {
            return Self.makeInstanceDescriptor(
                translation: SIMD3<Float>(0, -500, 0),
                yaw: npcYaws[index],
                pitch: 0,
                scale: SIMD3<Float>(repeating: baseScale),
                mask: 0x00,
                accelerationStructureIndex: asIndex
            )
        }
    }

    private func buildInitialInstanceAccelerationStructure() throws {
        guard let instanceAS = instanceAccelerationStructure,
              let instanceDesc = instanceDescriptor,
              let instanceScratch = instanceScratchBuffer,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeAccelerationStructureCommandEncoder() else {
            return
        }
        encoder.build(
            accelerationStructure: instanceAS,
            descriptor: instanceDesc,
            scratchBuffer: instanceScratch,
            scratchBufferOffset: 0
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if commandBuffer.status == .error {
            throw commandBuffer.error ?? MetalRayRendererError.resourceCreationFailed
        }
    }

    private static func makeInstanceDescriptor(
        translation: SIMD3<Float>,
        yaw: Float,
        pitch: Float = 0,
        scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
        mask: UInt32,
        accelerationStructureIndex: UInt32
    ) -> MTLAccelerationStructureInstanceDescriptor {
        let cy = cos(yaw), sy = sin(yaw)
        let cp = cos(pitch), sp = sin(pitch)
        var descriptor = MTLAccelerationStructureInstanceDescriptor()
        descriptor.transformationMatrix.columns.0 = MTLPackedFloat3Make(cy * scale.x, 0, -sy * scale.x)
        descriptor.transformationMatrix.columns.1 = MTLPackedFloat3Make(-sy * sp * scale.y, cp * scale.y, -cy * sp * scale.y)
        descriptor.transformationMatrix.columns.2 = MTLPackedFloat3Make(sy * cp * scale.z, sp * scale.z, cy * cp * scale.z)
        descriptor.transformationMatrix.columns.3 = MTLPackedFloat3Make(translation.x, translation.y, translation.z)
        descriptor.options = .opaque
        descriptor.mask = mask
        descriptor.intersectionFunctionTableOffset = 0
        descriptor.accelerationStructureIndex = accelerationStructureIndex
        return descriptor
    }

    private static func makeMesh(
        builder: RTMeshBuilder,
        device: MTLDevice,
        queue: MTLCommandQueue,
        allowsRefit: Bool = false
    ) throws -> RTMeshResources {
        guard !builder.vertices.isEmpty, builder.vertices.count / 3 == builder.triangles.count else {
            throw MetalRayRendererError.resourceCreationFailed
        }

        let vertexBuffer = builder.vertices.withUnsafeBytes { bytes -> MTLBuffer? in
            guard let baseAddress = bytes.baseAddress else { return nil }
            return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: .storageModeShared)
        }
        let primitiveBuffer = builder.triangles.withUnsafeBytes { bytes -> MTLBuffer? in
            guard let baseAddress = bytes.baseAddress else { return nil }
            return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: .storageModeShared)
        }
        guard let vertexBuffer, let primitiveBuffer else {
            throw MetalRayRendererError.resourceCreationFailed
        }

        guard device.isHardwareRayTracingSupported else {
            return RTMeshResources(
                vertexBuffer: vertexBuffer,
                primitiveBuffer: primitiveBuffer,
                accelerationStructure: nil,
                descriptor: nil,
                scratchBuffer: nil,
                vertexCount: builder.vertices.count
            )
        }

        let geometry = MTLAccelerationStructureTriangleGeometryDescriptor()
        geometry.vertexBuffer = vertexBuffer
        geometry.vertexFormat = .float3
        geometry.vertexStride = MemoryLayout<SIMD3<Float>>.stride
        geometry.triangleCount = builder.triangles.count
        geometry.primitiveDataBuffer = primitiveBuffer
        geometry.primitiveDataStride = MemoryLayout<RTTriangleData>.stride
        geometry.primitiveDataElementSize = MemoryLayout<RTTriangleData>.stride
        geometry.opaque = true

        let descriptor = MTLPrimitiveAccelerationStructureDescriptor()
        descriptor.geometryDescriptors = [geometry]
        if allowsRefit {
            descriptor.usage = .refit
        }
        let sizes = device.accelerationStructureSizes(descriptor: descriptor)
        guard let accelerationStructure = device.makeAccelerationStructure(size: sizes.accelerationStructureSize),
              let scratch = device.makeBuffer(
                length: max(256, sizes.buildScratchBufferSize, sizes.refitScratchBufferSize),
                options: .storageModePrivate
              ),
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeAccelerationStructureCommandEncoder() else {
            throw MetalRayRendererError.resourceCreationFailed
        }

        encoder.build(
            accelerationStructure: accelerationStructure,
            descriptor: descriptor,
            scratchBuffer: scratch,
            scratchBufferOffset: 0
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if commandBuffer.status == .error {
            throw commandBuffer.error ?? MetalRayRendererError.resourceCreationFailed
        }
        return RTMeshResources(
            vertexBuffer: vertexBuffer,
            primitiveBuffer: primitiveBuffer,
            accelerationStructure: accelerationStructure,
            descriptor: descriptor,
            scratchBuffer: scratch,
            vertexCount: builder.vertices.count
        )
    }

    private static func makePlayerMesh(pose: RTMeshBuilder.CharacterPose = .stand) -> RTMeshBuilder {
        var builder = RTMeshBuilder()
        builder.addCharacter(
            origin: .zero,
            color: SIMD3<Float>(0.24, 0.88, 0.22),
            holdsTool: true,
            pose: pose,
            isJellyGremlin: true
        )
        return builder
    }

    private static func makeNPCMesh() -> RTMeshBuilder {
        var builder = RTMeshBuilder()
        builder.addCharacter(origin: .zero, color: SIMD3<Float>(0.92, 0.18, 0.34), holdsTool: true)
        return builder
    }

    private static func makeFotofagoMesh() -> RTMeshBuilder {
        var builder = RTMeshBuilder()
        // 🌑 EL FOTÓFAGO: Silueta humanoide limpia y sólida en Vantablack mate (sin bloques flotantes ni transparencias raras)
        builder.addCharacter(origin: .zero, color: SIMD3<Float>(0.018, 0.018, 0.025), holdsTool: true)
        let vantablackArmor = RTMaterial(
            color: SIMD3<Float>(0.012, 0.012, 0.018),
            roughness: 0.85,
            emission: .zero,
            reflectivity: 0.04,
            kind: 10.0
        )
        let darkCore = RTMaterial(
            color: SIMD3<Float>(0.02, 0.01, 0.04),
            roughness: 0.35,
            emission: SIMD3<Float>(0.35, 0.05, 0.65),
            reflectivity: 0.12,
            kind: 5.0
        )
        // Hombreras monolíticas pesadas, cresta dorsal y peto de basalto Vantablack (imponente como Gólem Colosal en Oleada 3+)
        builder.addBox(center: SIMD3<Float>(-0.36, 1.06, 0.0), size: SIMD3<Float>(0.20, 0.16, 0.24), material: vantablackArmor)
        builder.addBox(center: SIMD3<Float>( 0.36, 1.06, 0.0), size: SIMD3<Float>(0.20, 0.16, 0.24), material: vantablackArmor)
        builder.addBox(center: SIMD3<Float>( 0.00, 0.90, 0.17), size: SIMD3<Float>(0.38, 0.32, 0.10), material: vantablackArmor)
        builder.addBox(center: SIMD3<Float>( 0.00, 0.96, -0.17), size: SIMD3<Float>(0.32, 0.36, 0.10), material: vantablackArmor)
        builder.addSphere(center: SIMD3<Float>(0.00, 0.92, 0.23), radii: SIMD3<Float>(repeating: 0.075), material: darkCore, segments: 10, rings: 6)
        return builder
    }

    private static func makeRainbowGateMesh() -> RTMeshBuilder {
        var builder = RTMeshBuilder()
        // 🌟 Marco de Cuadro / Espejo Portal estilo Castillo de Peach (Super Mario 64)
        let frameGold = RTMaterial(color: SIMD3<Float>(0.90, 0.76, 0.28), roughness: 0.22, reflectivity: 0.52, kind: 0.0)
        let frameEbony = RTMaterial(color: SIMD3<Float>(0.12, 0.11, 0.14), roughness: 0.45, reflectivity: 0.18, kind: 0.0)
        let frameGildedMedallion = RTMaterial(color: SIMD3<Float>(1.00, 0.85, 0.32), roughness: 0.15, emission: SIMD3<Float>(1.2, 0.9, 0.25), reflectivity: 0.65, kind: 0.0)

        // Espejo Mágico Portal Ray-Traced (Kind 1.0, 98% reflectividad pura, cero emisión cegadora)
        let mirrorGlass = RTMaterial(color: SIMD3<Float>(0.94, 0.96, 0.98), roughness: 0.005, emission: .zero, reflectivity: 0.98, kind: 1.0)

        // 1. Superficie del Espejo / Pintura Mágica Portal (10.0m de ancho x 4.60m de alto x 0.04m de grosor)
        // Refleja en tiempo real con Ray Tracing la sala de piscina por un lado y la pista arcoíris por el otro
        builder.addBox(center: SIMD3<Float>(0, 2.34, 0), size: SIMD3<Float>(10.00, 4.60, 0.04), material: mirrorGlass)

        // 2. Molduras Interiores Doradas estilo Marco de Cuadro Mario 64
        // Columnas doradas biseladas a los lados (X = ±5.04)
        builder.addBox(center: SIMD3<Float>(-5.04, 2.34, 0), size: SIMD3<Float>(0.18, 4.68, 0.12), material: frameGold)
        builder.addBox(center: SIMD3<Float>( 5.04, 2.34, 0), size: SIMD3<Float>(0.18, 4.68, 0.12), material: frameGold)
        // Dintel superior dorado
        builder.addBox(center: SIMD3<Float>( 0.00, 4.68, 0), size: SIMD3<Float>(10.26, 0.16, 0.12), material: frameGold)
        // Zócalo inferior dorado a ras de suelo
        builder.addBox(center: SIMD3<Float>( 0.00, 0.06, 0), size: SIMD3<Float>(10.26, 0.12, 0.12), material: frameGold)

        // 3. Moldura Exterior de Ébano Tallado
        builder.addBox(center: SIMD3<Float>(-5.16, 2.34, 0), size: SIMD3<Float>(0.12, 4.76, 0.16), material: frameEbony)
        builder.addBox(center: SIMD3<Float>( 5.16, 2.34, 0), size: SIMD3<Float>(0.12, 4.76, 0.16), material: frameEbony)
        builder.addBox(center: SIMD3<Float>( 0.00, 4.78, 0), size: SIMD3<Float>(10.44, 0.14, 0.16), material: frameEbony)

        // 4. Medallón Estelar Central Mario 64 en la cima del cuadro (emblema dorado sutil)
        builder.addBox(center: SIMD3<Float>(0, 4.88, 0.03), size: SIMD3<Float>(0.55, 0.55, 0.14), material: frameGildedMedallion)
        builder.addBox(center: SIMD3<Float>(0, 4.88, -0.03), size: SIMD3<Float>(0.55, 0.55, 0.14), material: frameGildedMedallion)

        return builder
    }

    private static func makeMirrorShieldMesh() -> RTMeshBuilder {
        var builder = RTMeshBuilder()
        let mirrorFrame = RTMaterial(color: SIMD3<Float>(0.02, 0.72, 0.95), roughness: 0.08, emission: SIMD3<Float>(0.05, 0.40, 0.65), reflectivity: 0.88, kind: 1.0)
        let mirrorGlassFront = RTMaterial(color: SIMD3<Float>(0.92, 0.95, 0.98), roughness: 0.0, emission: SIMD3<Float>(0, 0, 0), reflectivity: 0.98, kind: 1.0)
        
        // One-Way Visor Backing (-Z facing player in 1st person): See-through cyan tinted glass visor
        let oneWayVisorBack = RTMaterial(color: SIMD3<Float>(0.05, 0.45, 0.65), roughness: 0.05, emission: SIMD3<Float>(0.02, 0.15, 0.25), reflectivity: 0.08, kind: 0.0)

        // Compact tactical shield size: 0.48m wide x 0.58m tall
        // Outward (+Z): 100% Reflective Mirror Glass (Centrado en origen para rotar sobre su propio eje)
        builder.addBox(center: SIMD3<Float>(0, 0, 0.012), size: SIMD3<Float>(0.52, 0.62, 0.015), material: mirrorFrame)
        builder.addBox(center: SIMD3<Float>(0, 0, 0.018), size: SIMD3<Float>(0.46, 0.56, 0.010), material: mirrorGlassFront)
        // Inward (-Z facing player in 1st person): One-way see-through cyan glass visor
        builder.addBox(center: SIMD3<Float>(0, 0, -0.012), size: SIMD3<Float>(0.46, 0.56, 0.010), material: oneWayVisorBack)
        return builder
    }

    private static func makeAirPumpMesh() -> RTMeshBuilder {
        var builder = RTMeshBuilder()
        let pumpRed = RTMaterial(color: SIMD3<Float>(0.92, 0.18, 0.14), roughness: 0.28, reflectivity: 0.25)
        let pumpChrome = RTMaterial(color: SIMD3<Float>(0.90, 0.92, 0.95), roughness: 0.08, reflectivity: 0.85)
        let pumpRubber = RTMaterial(color: SIMD3<Float>(0.10, 0.11, 0.12), roughness: 0.85, reflectivity: 0.05)
        let pumpGaugeYellow = RTMaterial(color: SIMD3<Float>(1.0, 0.85, 0.20), roughness: 0.20, emission: SIMD3<Float>(0.4, 0.3, 0.05), reflectivity: 0.30, kind: 5.0)

        // 1. Base del inflador (pedal de pie en el suelo)
        builder.addBox(center: SIMD3<Float>(0, 0.03, 0), size: SIMD3<Float>(0.36, 0.06, 0.18), material: pumpRubber)

        // 2. Cilindro principal de aire (cuerpo rojo brillante)
        builder.addBox(center: SIMD3<Float>(0, 0.40, 0), size: SIMD3<Float>(0.14, 0.70, 0.14), material: pumpRed)

        // 3. Manómetro de presión analógico en la base
        builder.addBox(center: SIMD3<Float>(0.09, 0.25, 0), size: SIMD3<Float>(0.08, 0.08, 0.08), material: pumpGaugeYellow)

        // 4. Vástago / pistón cromado
        builder.addBox(center: SIMD3<Float>(0, 0.82, 0), size: SIMD3<Float>(0.05, 0.22, 0.05), material: pumpChrome)

        // 5. Mango / empuñadura T de bombeo
        builder.addBox(center: SIMD3<Float>(0, 0.94, 0), size: SIMD3<Float>(0.38, 0.06, 0.08), material: pumpRubber)

        // 6. Manguera negra que va hacia el slime
        builder.addBox(center: SIMD3<Float>(-0.25, 0.06, 0), size: SIMD3<Float>(0.42, 0.04, 0.04), material: pumpRubber)
        // Boquilla dorada de inflado
        builder.addBox(center: SIMD3<Float>(-0.48, 0.06, 0), size: SIMD3<Float>(0.08, 0.05, 0.05), material: pumpChrome)

        return builder
    }

    private static func makeFloatMesh() -> RTMeshBuilder {
        var builder = RTMeshBuilder()
        let orange = RTMaterial(
            color: SIMD3<Float>(0.95, 0.24, 0.08),
            roughness: 0.20,
            reflectivity: 0.18
        )
        let grip = RTMaterial(
            color: SIMD3<Float>(0.96, 0.92, 0.78),
            roughness: 0.34,
            reflectivity: 0.08
        )
        builder.addTorus(
            center: .zero,
            majorRadius: 0.48,
            minorRadius: 0.12,
            material: orange,
            majorSegments: 24,
            minorSegments: 10
        )
        builder.addBox(center: SIMD3<Float>(0.47, 0.085, 0), size: SIMD3<Float>(0.16, 0.035, 0.10), material: grip)
        builder.addBox(center: SIMD3<Float>(-0.47, 0.085, 0), size: SIMD3<Float>(0.16, 0.035, 0.10), material: grip)
        return builder
    }

    private static func makeWaterMesh() -> RTMeshBuilder {
        var builder = RTMeshBuilder()
        let water = RTMaterial(
            color: SIMD3<Float>(0.008, 0.025, 0.035),
            roughness: 0.012,
            reflectivity: 0.54,
            kind: 2
        )
        let columns = 32
        let rows = 24
        let minimum = SIMD2<Float>(-5.4, -4.2)
        let size = SIMD2<Float>(7.8, 5.4)

        for row in 0..<(rows - 1) {
            for column in 0..<(columns - 1) {
                let x0 = minimum.x + size.x * Float(column) / Float(columns - 1)
                let x1 = minimum.x + size.x * Float(column + 1) / Float(columns - 1)
                let z0 = minimum.y + size.y * Float(row) / Float(rows - 1)
                let z1 = minimum.y + size.y * Float(row + 1) / Float(rows - 1)
                builder.addQuad(
                    SIMD3<Float>(x0, 0.00, z1),
                    SIMD3<Float>(x1, 0.00, z1),
                    SIMD3<Float>(x1, 0.00, z0),
                    SIMD3<Float>(x0, 0.00, z0),
                    material: water
                )
            }
        }
        return builder
    }

    private static func makeStaticScene() -> RTMeshBuilder {
        var builder = RTMeshBuilder()
        // Piso de pizarra oscura húmeda con reflejos especulares Ray-Traced
        let deck = RTMaterial(color: SIMD3<Float>(0.042, 0.052, 0.072), roughness: 0.08, reflectivity: 0.36, kind: 3)
        let wall = RTMaterial(color: SIMD3<Float>(0.035, 0.045, 0.065), roughness: 0.9)
        let poolTile = RTMaterial(color: SIMD3<Float>(0.14, 0.24, 0.26), roughness: 0.36, reflectivity: 0.08)
        let coping = RTMaterial(color: SIMD3<Float>(0.28, 0.30, 0.30), roughness: 0.12, reflectivity: 0.52, kind: 3)
        let mirror = RTMaterial(color: SIMD3<Float>(0.92, 0.95, 0.98), roughness: 0.01, reflectivity: 0.97, kind: 1)
        let shallowWater = RTMaterial(
            color: SIMD3<Float>(0.010, 0.028, 0.038),
            roughness: 0.008,
            reflectivity: 0.74,
            kind: 8
        )
        let metal = RTMaterial(color: SIMD3<Float>(0.42, 0.45, 0.48), roughness: 0.12, reflectivity: 0.58)
        let warmLight = RTMaterial(
            color: SIMD3<Float>(1.0, 0.70, 0.22),
            roughness: 0.15,
            emission: SIMD3<Float>(3.8, 2.2, 0.45),
            reflectivity: 0.08,
            kind: 5
        )
        let lampEmitter = RTMaterial(
            color: SIMD3<Float>(1.0, 0.70, 0.22),
            roughness: 0.15,
            emission: SIMD3<Float>(3.8, 2.2, 0.45),
            reflectivity: 0.08,
            kind: 4
        )



        // 🏊‍♂️ Salón Deck Framing the Pool Opening (North, South, West, East sections)
        builder.addBox(center: SIMD3<Float>(0, -0.12, -11.1), size: SIMD3<Float>(36.0, 0.24, 13.8), material: deck)
        builder.addBox(center: SIMD3<Float>(0, -0.12, 9.6), size: SIMD3<Float>(36.0, 0.24, 16.8), material: deck)
        builder.addBox(center: SIMD3<Float>(-11.7, -0.12, -1.5), size: SIMD3<Float>(12.6, 0.24, 5.4), material: deck)
        builder.addBox(center: SIMD3<Float>(10.2, -0.12, -1.5), size: SIMD3<Float>(15.6, 0.24, 5.4), material: deck)
        builder.addBox(center: SIMD3<Float>(0, 3.5, -17.8), size: SIMD3<Float>(36, 7, 0.4), material: wall)
        // 🌈 Pared Sur con Gran Pórtico Abierto (X: -5.2 a +5.2, altura 4.8m) hacia el Gran Salón Arcoíris
        builder.addBox(center: SIMD3<Float>(-11.6, 3.5, 17.8), size: SIMD3<Float>(12.8, 7.0, 0.4), material: wall)
        builder.addBox(center: SIMD3<Float>( 11.6, 3.5, 17.8), size: SIMD3<Float>(12.8, 7.0, 0.4), material: wall)
        builder.addBox(center: SIMD3<Float>(  0.0, 5.9, 17.8), size: SIMD3<Float>(10.4, 2.2, 0.4), material: wall)
        builder.addBox(center: SIMD3<Float>(-17.8, 3.5, 0), size: SIMD3<Float>(0.4, 7, 36), material: wall)
        builder.addBox(center: SIMD3<Float>(17.8, 3.5, 0), size: SIMD3<Float>(0.4, 7, 36), material: wall)
        let slideCyan = RTMaterial(color: SIMD3<Float>(0.02, 0.65, 0.82), roughness: 0.32, emission: SIMD3<Float>(0.02, 0.12, 0.20), reflectivity: 0.12)
        let stairPink = RTMaterial(color: SIMD3<Float>(0.95, 0.18, 0.52), roughness: 0.20, emission: SIMD3<Float>(0.20, 0.04, 0.10), reflectivity: 0.40)
        let platformDeck = RTMaterial(color: SIMD3<Float>(0.14, 0.18, 0.22), roughness: 0.40, reflectivity: 0.20)

        // 🌀 Tobogán en Espiral 3D Elevado con Salida Directa a la Piscina (Altura: 5.6m)
        builder.addBox(center: SIMD3<Float>(-3.8, 5.60, -15.8), size: SIMD3<Float>(2.8, 0.20, 2.6), material: platformDeck)
        builder.addBox(center: SIMD3<Float>(-5.2, 6.20, -15.8), size: SIMD3<Float>(0.12, 1.2, 2.6), material: metal)
        builder.addBox(center: SIMD3<Float>(-2.4, 6.20, -15.8), size: SIMD3<Float>(0.12, 1.2, 2.6), material: metal)

        // 🪜 Escalera Metálica Totalmente Vertical (Attached to back wall platform at Z = -16.85)
        let ladderPostMaterial = RTMaterial(color: SIMD3<Float>(0.75, 0.78, 0.82), roughness: 0.15, reflectivity: 0.80)
        builder.addBox(center: SIMD3<Float>(-4.35, 2.80, -16.85), size: SIMD3<Float>(0.08, 5.60, 0.08), material: ladderPostMaterial)
        builder.addBox(center: SIMD3<Float>(-3.25, 2.80, -16.85), size: SIMD3<Float>(0.08, 5.60, 0.08), material: ladderPostMaterial)

        for rung in 0..<22 {
            let rungY = Float(rung) * 0.25 + 0.10
            builder.addBox(center: SIMD3<Float>(-3.80, rungY, -16.85), size: SIMD3<Float>(1.02, 0.06, 0.06), material: stairPink)
        }

        // 🌊 High 5.6m Straight Water Slide Chute ("Rodadero Recto de Alta Velocidad")
        let slideStart = SIMD3<Float>(-3.8, 5.55, -14.5)
        let slideEnd = SIMD3<Float>(-2.2, 0.05, -3.8)
        for step in 0..<50 {
            let progress = Float(step) / 49.0
            let stepPos = slideStart + (slideEnd - slideStart) * progress
            // Molded cyan slide trough
            builder.addBox(center: stepPos, size: SIMD3<Float>(1.5, 0.08, 0.32), material: slideCyan)
            // Safety side rails
            builder.addBox(center: stepPos + SIMD3<Float>(-0.70, 0.22, 0), size: SIMD3<Float>(0.10, 0.40, 0.32), material: slideCyan)
            builder.addBox(center: stepPos + SIMD3<Float>(0.70, 0.22, 0), size: SIMD3<Float>(0.10, 0.40, 0.32), material: slideCyan)
        }

        // 🌊 💎 CÁMARA ACUÁTICA SUBTERRÁNEA COLOSAL (Secret Realm & Water Generators)
        let subFloorMat = RTMaterial(color: SIMD3<Float>(0.02, 0.06, 0.10), roughness: 0.65, reflectivity: 0.12)
        let subWallMat = RTMaterial(color: SIMD3<Float>(0.03, 0.08, 0.13), roughness: 0.45, reflectivity: 0.18)
        let subCeilingMat = RTMaterial(color: SIMD3<Float>(0.02, 0.05, 0.09), roughness: 0.70, reflectivity: 0.10)
        let subWallNeonCyan = RTMaterial(color: SIMD3<Float>(0.0, 0.95, 1.0), roughness: 0.05, emission: SIMD3<Float>(0.6, 4.8, 7.5), reflectivity: 0.85, kind: 5)
        let subWallNeonEmerald = RTMaterial(color: SIMD3<Float>(0.0, 1.0, 0.6), roughness: 0.05, emission: SIMD3<Float>(0.4, 6.2, 3.8), reflectivity: 0.85, kind: 5)
        let bioCrystal = RTMaterial(color: SIMD3<Float>(0.10, 0.95, 0.85), roughness: 0.10, emission: SIMD3<Float>(0.20, 2.8, 3.8), reflectivity: 0.60)
        let sunkenObelisk = RTMaterial(color: SIMD3<Float>(0.12, 0.18, 0.22), roughness: 0.65, reflectivity: 0.12)
        let treasureGold = RTMaterial(color: SIMD3<Float>(0.98, 0.82, 0.12), roughness: 0.15, emission: SIMD3<Float>(0.45, 0.35, 0.05), reflectivity: 0.50)
        let generatorMetal = RTMaterial(color: SIMD3<Float>(0.25, 0.32, 0.38), roughness: 0.22, reflectivity: 0.70)
        let bubbleMat = RTMaterial(color: SIMD3<Float>(0.75, 0.95, 1.0), roughness: 0.02, emission: SIMD3<Float>(0.15, 0.65, 0.95), reflectivity: 0.85, kind: 5)

        // 1. Piso Abisal Profundo (Y = -11.6m, 36m x 36m)
        builder.addBox(center: SIMD3<Float>(0, -11.60, 0), size: SIMD3<Float>(36.0, 0.30, 36.0), material: subFloorMat)

        // 2. Cuatro Paredes Subterráneas que cierran herméticamente el cuarto (Y = -11.5m a Y = -4.7m)
        builder.addBox(center: SIMD3<Float>(0, -7.85, -17.8), size: SIMD3<Float>(36.0, 6.30, 0.4), material: subWallMat)
        builder.addBox(center: SIMD3<Float>(0, -7.85, 17.8), size: SIMD3<Float>(36.0, 6.30, 0.4), material: subWallMat)
        builder.addBox(center: SIMD3<Float>(-17.8, -7.85, 0), size: SIMD3<Float>(0.4, 6.30, 36.0), material: subWallMat)
        builder.addBox(center: SIMD3<Float>(17.8, -7.85, 0), size: SIMD3<Float>(0.4, 6.30, 36.0), material: subWallMat)

        // 3. Techo Sólido Subterráneo (Y = -4.70m, debajo de la piscina ultra profunda) que sella todo excepto el acceso de la piscina
        builder.addBox(center: SIMD3<Float>(0, -4.70, -11.0), size: SIMD3<Float>(36.0, 0.25, 13.6), material: subCeilingMat)
        builder.addBox(center: SIMD3<Float>(0, -4.70, 9.6), size: SIMD3<Float>(36.0, 0.25, 16.8), material: subCeilingMat)
        builder.addBox(center: SIMD3<Float>(-11.6, -4.70, -1.5), size: SIMD3<Float>(12.5, 0.25, 5.4), material: subCeilingMat)
        builder.addBox(center: SIMD3<Float>(10.1, -4.70, -1.5), size: SIMD3<Float>(15.5, 0.25, 5.4), material: subCeilingMat)

        // 4. Luces en las Paredes Subterráneas (Tiras Neón Cian & Esmeralda)
        // Banda Superior Cian a Y = -6.0m
        builder.addBox(center: SIMD3<Float>(0, -6.00, -17.58), size: SIMD3<Float>(35.0, 0.15, 0.08), material: subWallNeonCyan)
        builder.addBox(center: SIMD3<Float>(0, -6.00, 17.58), size: SIMD3<Float>(35.0, 0.15, 0.08), material: subWallNeonCyan)
        builder.addBox(center: SIMD3<Float>(-17.58, -6.00, 0), size: SIMD3<Float>(0.08, 0.15, 35.0), material: subWallNeonCyan)
        builder.addBox(center: SIMD3<Float>(17.58, -6.00, 0), size: SIMD3<Float>(0.08, 0.15, 35.0), material: subWallNeonCyan)

        // Banda Inferior Esmeralda a Y = -9.6m
        builder.addBox(center: SIMD3<Float>(0, -9.60, -17.58), size: SIMD3<Float>(35.0, 0.15, 0.08), material: subWallNeonEmerald)
        builder.addBox(center: SIMD3<Float>(0, -9.60, 17.58), size: SIMD3<Float>(35.0, 0.15, 0.08), material: subWallNeonEmerald)
        builder.addBox(center: SIMD3<Float>(-17.58, -9.60, 0), size: SIMD3<Float>(0.08, 0.15, 35.0), material: subWallNeonEmerald)
        builder.addBox(center: SIMD3<Float>(17.58, -9.60, 0), size: SIMD3<Float>(0.08, 0.15, 35.0), material: subWallNeonEmerald)

        // 5. 🌊 Generadores de Agua & Turbinas de Fondo con Columnas de Burbujas
        let generatorLocs: [SIMD2<Float>] = [
            SIMD2<Float>(-10.5, -10.5),
            SIMD2<Float>(10.5, -10.5),
            SIMD2<Float>(-10.5, 10.5),
            SIMD2<Float>(10.5, 10.5)
        ]
        for loc in generatorLocs {
            // Base de la turbina
            builder.addBox(center: SIMD3<Float>(loc.x, -11.0, loc.y), size: SIMD3<Float>(2.4, 0.8, 2.4), material: generatorMetal)
            // Núcleo brillante emisor
            builder.addBox(center: SIMD3<Float>(loc.x, -10.55, loc.y), size: SIMD3<Float>(1.6, 0.20, 1.6), material: subWallNeonCyan)
            // Columna de burbujas ascendentes
            let bubbleHeights: [Float] = [-9.8, -8.6, -7.4, -6.2, -5.2]
            for (idx, bY) in bubbleHeights.enumerated() {
                let jitterX = sin(Float(idx) * 1.7) * 0.28
                let jitterZ = cos(Float(idx) * 2.1) * 0.28
                let bRadius: Float = idx % 2 == 0 ? 0.22 : 0.30
                builder.addSphere(center: SIMD3<Float>(loc.x + jitterX, bY, loc.y + jitterZ), radii: SIMD3<Float>(repeating: bRadius), material: bubbleMat, segments: 8, rings: 5)
            }
        }

        // Sunken Ancient Obelisks & Pillars
        builder.addBox(center: SIMD3<Float>(-4.2, -7.5, -3.8), size: SIMD3<Float>(0.85, 5.0, 0.85), material: sunkenObelisk)
        builder.addBox(center: SIMD3<Float>(3.8, -7.5, 2.8), size: SIMD3<Float>(0.85, 5.0, 0.85), material: sunkenObelisk)
        builder.addBox(center: SIMD3<Float>(-3.2, -8.0, 3.2), size: SIMD3<Float>(0.75, 4.0, 0.75), material: sunkenObelisk)

        // Glowing Bioluminescent Crystals & Subterranean Illuminating Lamps
        let subLampEmitter = RTMaterial(color: SIMD3<Float>(0.10, 0.90, 0.98), roughness: 0.05, emission: SIMD3<Float>(0.85, 3.8, 5.5), reflectivity: 0.75)
        builder.addSphere(center: SIMD3<Float>(-8.0, -7.0, -8.0), radii: SIMD3<Float>(repeating: 0.65), material: subLampEmitter, segments: 10, rings: 6)
        builder.addSphere(center: SIMD3<Float>(8.0, -7.0, -8.0), radii: SIMD3<Float>(repeating: 0.65), material: subLampEmitter, segments: 10, rings: 6)
        builder.addSphere(center: SIMD3<Float>(-8.0, -7.0, 8.0), radii: SIMD3<Float>(repeating: 0.65), material: subLampEmitter, segments: 10, rings: 6)
        builder.addSphere(center: SIMD3<Float>(8.0, -7.0, 8.0), radii: SIMD3<Float>(repeating: 0.65), material: subLampEmitter, segments: 10, rings: 6)

        builder.addSphere(center: SIMD3<Float>(-3.8, -9.2, -3.2), radii: SIMD3<Float>(repeating: 0.45), material: bioCrystal, segments: 8, rings: 5)
        builder.addSphere(center: SIMD3<Float>(3.5, -9.2, 2.2), radii: SIMD3<Float>(repeating: 0.45), material: bioCrystal, segments: 8, rings: 5)
        builder.addSphere(center: SIMD3<Float>(1.8, -9.2, -4.2), radii: SIMD3<Float>(repeating: 0.40), material: bioCrystal, segments: 8, rings: 5)

        // Sunken Treasure Chest
        builder.addBox(center: SIMD3<Float>(2.8, -9.5, -1.8), size: SIMD3<Float>(1.2, 0.75, 0.85), material: treasureGold)

        // 🏊‍♂️ Pozo de Agua / Piscina Profunda Subterránea
        // En la superficie se comporta como un posito de 10 cm, pero conecta directamente con la piscina abisal
        // Paredes del pozo profundo (4.70m de alto, bajando hasta el techo de la cámara subterránea)
        builder.addBox(center: SIMD3<Float>(-1.5, -2.35, -4.14), size: SIMD3<Float>(7.8, 4.70, 0.12), material: poolTile)
        builder.addBox(center: SIMD3<Float>(-1.5, -2.35, 1.14), size: SIMD3<Float>(7.8, 4.70, 0.12), material: poolTile)
        builder.addBox(center: SIMD3<Float>(-5.34, -2.35, -1.5), size: SIMD3<Float>(0.12, 4.70, 5.4), material: poolTile)
        builder.addBox(center: SIMD3<Float>(2.34, -2.35, -1.5), size: SIMD3<Float>(0.12, 4.70, 5.4), material: poolTile)

        // Tiras LED neón subacuáticas en el pozo profundo (Y = -2.35m)
        builder.addBox(center: SIMD3<Float>(-1.5, -2.35, -4.06), size: SIMD3<Float>(7.2, 0.06, 0.06), material: subWallNeonCyan)
        builder.addBox(center: SIMD3<Float>(-1.5, -2.35, 1.06), size: SIMD3<Float>(7.2, 0.06, 0.06), material: subWallNeonCyan)
        builder.addBox(center: SIMD3<Float>(-5.26, -2.35, -1.5), size: SIMD3<Float>(0.06, 0.06, 4.8), material: subWallNeonCyan)
        builder.addBox(center: SIMD3<Float>(2.26, -2.35, -1.5), size: SIMD3<Float>(0.06, 0.06, 4.8), material: subWallNeonCyan)

        // 🪜 Escalera Metálica Cromada de la Piscina (Postes y peldaños visibles bajo el agua y sobre el deck)
        builder.addBox(center: SIMD3<Float>(2.22, -0.40, -2.15), size: SIMD3<Float>(0.05, 1.45, 0.05), material: metal)
        builder.addBox(center: SIMD3<Float>(2.22, -0.40, -1.65), size: SIMD3<Float>(0.05, 1.45, 0.05), material: metal)
        builder.addBox(center: SIMD3<Float>(2.35, 0.48, -2.15), size: SIMD3<Float>(0.26, 0.32, 0.05), material: metal)
        builder.addBox(center: SIMD3<Float>(2.35, 0.48, -1.65), size: SIMD3<Float>(0.26, 0.32, 0.05), material: metal)
        builder.addBox(center: SIMD3<Float>(2.20, -1.00, -1.90), size: SIMD3<Float>(0.06, 0.04, 0.46), material: metal)
        builder.addBox(center: SIMD3<Float>(2.20, -0.70, -1.90), size: SIMD3<Float>(0.06, 0.04, 0.46), material: metal)
        builder.addBox(center: SIMD3<Float>(2.20, -0.40, -1.90), size: SIMD3<Float>(0.06, 0.04, 0.46), material: metal)
        builder.addBox(center: SIMD3<Float>(2.20, -0.10, -1.90), size: SIMD3<Float>(0.06, 0.04, 0.46), material: metal)

        builder.addBox(center: SIMD3<Float>(-1.5, 0.14, -4.38), size: SIMD3<Float>(8.1, 0.28, 0.34), material: coping)
        builder.addBox(center: SIMD3<Float>(-1.5, 0.14, 1.38), size: SIMD3<Float>(8.1, 0.28, 0.34), material: coping)
        builder.addBox(center: SIMD3<Float>(-5.55, 0.14, -1.5), size: SIMD3<Float>(0.34, 0.28, 5.42), material: coping)
        builder.addBox(center: SIMD3<Float>(2.55, 0.14, -1.5), size: SIMD3<Float>(0.34, 0.28, 5.42), material: coping)

        builder.addBox(center: SIMD3<Float>(-1.5, 0.30, -4.20), size: SIMD3<Float>(7.7, 0.035, 0.07), material: warmLight)
        builder.addBox(center: SIMD3<Float>(-1.5, 0.30, 1.20), size: SIMD3<Float>(7.7, 0.035, 0.07), material: warmLight)
        builder.addBox(center: SIMD3<Float>(-5.35, 0.30, -1.5), size: SIMD3<Float>(0.07, 0.035, 5.1), material: warmLight)
        builder.addBox(center: SIMD3<Float>(2.35, 0.30, -1.5), size: SIMD3<Float>(0.07, 0.035, 5.1), material: warmLight)

        builder.addQuad(
            SIMD3<Float>(1.35, 0.72, -17.55), SIMD3<Float>(5.65, 0.72, -17.55),
            SIMD3<Float>(5.65, 3.38, -17.55), SIMD3<Float>(1.35, 3.38, -17.55),
            material: mirror
        )
        builder.addBox(center: SIMD3<Float>(3.5, 3.49, -17.52), size: SIMD3<Float>(4.62, 0.16, 0.16), material: metal)
        builder.addBox(center: SIMD3<Float>(3.5, 0.61, -17.52), size: SIMD3<Float>(4.62, 0.16, 0.16), material: metal)
        builder.addBox(center: SIMD3<Float>(1.24, 2.05, -17.52), size: SIMD3<Float>(0.16, 2.72, 0.16), material: metal)
        builder.addBox(center: SIMD3<Float>(5.76, 2.05, -17.52), size: SIMD3<Float>(0.16, 2.72, 0.16), material: metal)
        builder.addNeonPoolSign(origin: SIMD2<Float>(-7.7, 3.30), z: -17.58)
        builder.addNeonSheeritSign(origin: SIMD2<Float>(6.3, 3.28), z: 17.50)

        // 💎 ENIGMA DEL CHRONO-CORE: Prisma Reflectante Oriental y Receptor Cuántico Occidental
        let chronoGold = RTMaterial(color: SIMD3<Float>(1.0, 0.82, 0.28), roughness: 0.12, emission: SIMD3<Float>(0.8, 0.6, 0.1), reflectivity: 0.70)
        let chronoCoreCrystal = RTMaterial(color: SIMD3<Float>(0.08, 0.92, 1.0), roughness: 0.02, emission: SIMD3<Float>(0.6, 2.5, 3.2), reflectivity: 0.95, kind: 5.0)
        let chronoPedestal = RTMaterial(color: SIMD3<Float>(0.15, 0.18, 0.22), roughness: 0.35, reflectivity: 0.40)
        let prismFaceMirror = RTMaterial(color: SIMD3<Float>(0.96, 0.98, 1.0), roughness: 0.005, emission: SIMD3<Float>(0.1, 0.4, 0.6), reflectivity: 0.98, kind: 1.0)

        // 1. Prisma Óptico Oriental (X = 8.5, Y = 1.8, Z = -6.5)
        // Columna de bronce y cuarzo con espejo diagonal orientador
        builder.addBox(center: SIMD3<Float>(8.5, 0.80, -6.5), size: SIMD3<Float>(0.45, 1.60, 0.45), material: chronoPedestal)
        builder.addBox(center: SIMD3<Float>(8.5, 1.65, -6.5), size: SIMD3<Float>(0.55, 0.12, 0.55), material: chronoGold)
        // Cara del espejo diagonal
        builder.addBox(center: SIMD3<Float>(8.5, 1.85, -6.5), size: SIMD3<Float>(0.60, 0.75, 0.08), material: prismFaceMirror)
        builder.addBox(center: SIMD3<Float>(8.5, 2.30, -6.5), size: SIMD3<Float>(0.24, 0.24, 0.24), material: chronoCoreCrystal)

        // 2. Interruptor / Receptor Cuántico del Chrono-Core (Pared Oeste, X = -17.55, Y = 2.4, Z = -6.5)
        builder.addBox(center: SIMD3<Float>(-17.55, 2.40, -6.5), size: SIMD3<Float>(0.16, 1.15, 1.15), material: chronoGold)
        builder.addBox(center: SIMD3<Float>(-17.44, 2.40, -6.5), size: SIMD3<Float>(0.14, 0.75, 0.75), material: chronoCoreCrystal)
        builder.addBox(center: SIMD3<Float>(-17.38, 2.40, -6.5), size: SIMD3<Float>(0.08, 0.35, 0.35), material: prismFaceMirror)

        let lampPosition = SIMD3<Float>(-7.55, 0, 12.65)
        builder.addBox(center: lampPosition + SIMD3<Float>(0, 1.42, 0), size: SIMD3<Float>(0.13, 2.75, 0.13), material: metal)
        builder.addBox(center: lampPosition + SIMD3<Float>(0, 2.72, 0), size: SIMD3<Float>(0.32, 0.52, 0.32), material: lampEmitter)
        builder.addBox(center: lampPosition + SIMD3<Float>(0, 2.99, 0), size: SIMD3<Float>(0.54, 0.08, 0.54), material: metal)
        builder.addBox(center: lampPosition + SIMD3<Float>(0, 2.45, 0), size: SIMD3<Float>(0.46, 0.08, 0.46), material: metal)
        builder.addBox(center: lampPosition + SIMD3<Float>(0, 0.08, 0), size: SIMD3<Float>(0.62, 0.16, 0.62), material: metal)

        for (index, rock) in rtRiverRocks.enumerated() {
            let stone = RTMaterial(color: rock.color, roughness: 0.92, reflectivity: 0.01, kind: 3)
            builder.addRiverRock(
                center: rock.center,
                radii: rock.radii,
                seed: Float(index) + 0.7,
                material: stone
            )
        }

        // 🪜 Escalera metálica de la piscina (Exclusivamente en la superficie: del deck a -0.75m en el agua)
        builder.addBox(center: SIMD3<Float>(2.20, -0.20, -2.25), size: SIMD3<Float>(0.08, 1.10, 0.08), material: metal)
        builder.addBox(center: SIMD3<Float>(2.20, -0.20, -1.55), size: SIMD3<Float>(0.08, 1.10, 0.08), material: metal)
        // Pasamanos curvados sobre el deck (Y = 0.20 a 0.38m)
        builder.addBox(center: SIMD3<Float>(2.32, 0.36, -2.25), size: SIMD3<Float>(0.24, 0.08, 0.08), material: metal)
        builder.addBox(center: SIMD3<Float>(2.32, 0.36, -1.55), size: SIMD3<Float>(0.24, 0.08, 0.08), material: metal)
        // 3 peldaños metálicos sumergidos en la superficie del agua
        let poolRungHeights: [Float] = [-0.60, -0.35, -0.10]
        for rY in poolRungHeights {
            builder.addBox(
                center: SIMD3<Float>(2.20, rY, -1.90),
                size: SIMD3<Float>(0.08, 0.06, 0.65),
                material: metal
            )
        }

        let wood = RTMaterial(color: SIMD3<Float>(0.30, 0.18, 0.10), roughness: 0.52, reflectivity: 0.08)
        builder.addBox(center: SIMD3<Float>(7.3, 0.56, 4.8), size: SIMD3<Float>(3.2, 0.18, 0.72), material: wood)
        builder.addBox(center: SIMD3<Float>(6.1, 0.28, 4.8), size: SIMD3<Float>(0.18, 0.55, 0.58), material: wood)
        builder.addBox(center: SIMD3<Float>(8.5, 0.28, 4.8), size: SIMD3<Float>(0.18, 0.55, 0.58), material: wood)
        builder.addBox(center: SIMD3<Float>(6.8, 0.70, 4.8), size: SIMD3<Float>(0.72, 0.10, 0.52), material: RTMaterial(color: SIMD3<Float>(0.10, 0.64, 0.72), roughness: 0.46))
        builder.addBox(center: SIMD3<Float>(7.65, 0.70, 4.8), size: SIMD3<Float>(0.72, 0.10, 0.52), material: RTMaterial(color: SIMD3<Float>(0.90, 0.24, 0.34), roughness: 0.46))

        // =========================================================================
        // 🌈 🏎️ GRAN SALÓN ARCOÍRIS ESTILO MARIO KART (SENDA ARCOÍRIS / RAINBOW ROAD)
        // (54m x 54m, Z: 18m a 72m, X: -27m a +27m)
        // =========================================================================
        // 1. Muros Perimetrales Monumentales de 9m de altura en Titanio Mate Cyber
        let wallDarkMatte = RTMaterial(color: SIMD3<Float>(0.08, 0.09, 0.12), roughness: 0.65, reflectivity: 0.06)
        // Muro Sur Final (Z = 72.0)
        builder.addBox(center: SIMD3<Float>(0, 4.5, 72.0), size: SIMD3<Float>(54.4, 9.0, 0.4), material: wallDarkMatte)
        // Muro Oeste (X = -27.0) y Muro Este (X = +27.0)
        builder.addBox(center: SIMD3<Float>(-27.0, 4.5, 45.0), size: SIMD3<Float>(0.4, 9.0, 54.4), material: wallDarkMatte)
        builder.addBox(center: SIMD3<Float>( 27.0, 4.5, 45.0), size: SIMD3<Float>(0.4, 9.0, 54.4), material: wallDarkMatte)
        // Alas Norte que conectan el Salón de la Piscina (±17.8) con el ancho del Salón Arcoíris (±27.0) en Z = 17.8
        builder.addBox(center: SIMD3<Float>(-22.4, 4.5, 17.8), size: SIMD3<Float>(9.6, 9.0, 0.4), material: wallDarkMatte)
        builder.addBox(center: SIMD3<Float>( 22.4, 4.5, 17.8), size: SIMD3<Float>(9.6, 9.0, 0.4), material: wallDarkMatte)

        // 2. 7 Colores del Espectro Arcoíris Mario Kart:
        let rainbowColors: [(SIMD3<Float>, SIMD3<Float>)] = [
            (SIMD3<Float>(0.98, 0.12, 0.28), SIMD3<Float>(2.8, 0.3, 0.8)), // Carril 0: Rubí Neón
            (SIMD3<Float>(1.00, 0.48, 0.05), SIMD3<Float>(2.6, 1.2, 0.2)), // Carril 1: Naranja Solar
            (SIMD3<Float>(0.98, 0.86, 0.10), SIMD3<Float>(2.4, 2.1, 0.3)), // Carril 2: Oro Estelar
            (SIMD3<Float>(0.10, 0.88, 0.38), SIMD3<Float>(0.3, 2.5, 1.0)), // Carril 3: Verde Esmeralda
            (SIMD3<Float>(0.05, 0.82, 0.98), SIMD3<Float>(0.2, 2.2, 2.8)), // Carril 4: Cian Eléctrico
            (SIMD3<Float>(0.22, 0.35, 0.95), SIMD3<Float>(0.8, 1.1, 2.9)), // Carril 5: Azul Índigo Cósmico
            (SIMD3<Float>(0.76, 0.16, 0.95), SIMD3<Float>(2.2, 0.5, 2.8))  // Carril 6: Violeta Galáctico
        ]

        // Materiales para la Pista de Suelo: Acabado Satinado / Mate sedoso con emisión balanceada
        // Evita reflejos tipo espejo molestos (roughness: 0.45, reflectivity: 0.08)
        let rainbowFloorMats: [RTMaterial] = rainbowColors.map { col, em in
            RTMaterial(color: col, roughness: 0.45, emission: em * 0.48, reflectivity: 0.08, kind: 0)
        }

        // Tiras de división blancas brillantes entre carriles estilo Mario Kart
        let laneDividerMat = RTMaterial(color: SIMD3<Float>(0.95, 0.98, 1.0), roughness: 0.25, emission: SIMD3<Float>(3.2, 3.2, 3.8), reflectivity: 0.15, kind: 0)

        // Pista de 7 Carriles Mario Kart Rainbow Road en el Suelo (Z: 18 a 72m, total 54m de largo)
        let laneCount = 7
        let laneWidth: Float = 54.0 / Float(laneCount) // 7.714m por carril
        for i in 0..<laneCount {
            let xCenter = -27.0 + laneWidth * 0.5 + Float(i) * laneWidth
            builder.addBox(
                center: SIMD3<Float>(xCenter, -0.12, 45.0),
                size: SIMD3<Float>(laneWidth - 0.14, 0.24, 54.0),
                material: rainbowFloorMats[i]
            )
            if i > 0 {
                let xDiv = -27.0 + Float(i) * laneWidth
                builder.addBox(
                    center: SIMD3<Float>(xDiv, -0.11, 45.0),
                    size: SIMD3<Float>(0.14, 0.24, 54.0),
                    material: laneDividerMat
                )
            }
        }

        // Materiales Neón para Bordes y Muros
        let rainbowNeonMats: [RTMaterial] = rainbowColors.map { col, em in
            RTMaterial(color: col, roughness: 0.20, emission: em * 0.85, reflectivity: 0.20, kind: 5)
        }

        // 3. Columnas y Dintel Estructural del Pórtico del Cuadro/Espejo Portal en el Muro Sur (Z = 17.8)
        let archStone = RTMaterial(color: SIMD3<Float>(0.12, 0.14, 0.18), roughness: 0.60, reflectivity: 0.08, kind: 0.0)
        builder.addBox(center: SIMD3<Float>(-5.25, 2.40, 17.80), size: SIMD3<Float>(0.35, 4.80, 0.50), material: archStone)
        builder.addBox(center: SIMD3<Float>( 5.25, 2.40, 17.80), size: SIMD3<Float>(0.35, 4.80, 0.50), material: archStone)
        builder.addBox(center: SIMD3<Float>( 0.00, 4.82, 17.80), size: SIMD3<Float>(10.85, 0.28, 0.50), material: archStone)

        // 4. Bandas Horizontales Arcoíris en Muros Perimetrales (Guarda-raíles estilo Mario Kart Rainbow Road)
        for i in 0..<7 {
            let mat = rainbowNeonMats[i]
            let yStrip: Float = 1.20 + Float(i) * 1.05 // Alturas de 1.2m a 7.5m
            // Muro Oeste (X = -26.78) y Muro Este (X = 26.78) a todo lo largo (54m de Z: 18 a 72)
            builder.addBox(center: SIMD3<Float>(-26.78, yStrip, 45.0), size: SIMD3<Float>(0.06, 0.20, 54.0), material: mat)
            builder.addBox(center: SIMD3<Float>( 26.78, yStrip, 45.0), size: SIMD3<Float>(0.06, 0.20, 54.0), material: mat)
            // Muro Sur Final (Z = 71.78) a todo lo ancho (54m de X: -27 a +27)
            builder.addBox(center: SIMD3<Float>(0, yStrip, 71.78), size: SIMD3<Float>(54.0, 0.20, 0.06), material: mat)
        }

        // 6. Los 4 Pilones / Faroles de Luz Arcoíris Interactivos junto a las 4 Cabañas (conectados a los 4 interruptores de luz)
        let rainbowPylons: [(SIMD3<Float>, Int)] = [
            (SIMD3<Float>(-12.5, 0, 32.0), 0), // Sector Noroeste (Cabaña Rubí)
            (SIMD3<Float>( 12.5, 0, 32.0), 3), // Sector Noreste (Cabaña Esmeralda)
            (SIMD3<Float>(-12.5, 0, 56.0), 4), // Sector Suroeste (Cabaña Cian)
            (SIMD3<Float>( 12.5, 0, 56.0), 6)  // Sector Sureste (Cabaña Violeta)
        ]
        for (pPos, colorIdx) in rainbowPylons {
            let pylonMat = rainbowNeonMats[colorIdx % rainbowNeonMats.count]
            builder.addBox(center: pPos + SIMD3<Float>(0, 0.10, 0), size: SIMD3<Float>(0.85, 0.20, 0.85), material: metal)
            builder.addBox(center: pPos + SIMD3<Float>(0, 1.85, 0), size: SIMD3<Float>(0.18, 3.50, 0.18), material: metal)
            builder.addBox(center: pPos + SIMD3<Float>(0, 3.65, 0), size: SIMD3<Float>(0.55, 0.75, 0.55), material: pylonMat)
            builder.addBox(center: pPos + SIMD3<Float>(0, 4.10, 0), size: SIMD3<Float>(0.78, 0.10, 0.78), material: metal)
        }

        // 7. Bloques de Parkour de Cuerpo Completo, Pasarelas Elevadas y Las 4 Cabañas Arcoíris
        // 100% Sólidos, Opacos y Mate Arquitectónico (cero transparencia, sin reflejos tipo espejo, cero emisión en el cuerpo)
        for (idx, box) in rtRainbowParkourBoxes.enumerated() {
            let baseColor: SIMD3<Float>
            if simd_length_squared(box.color) > 0.005 {
                baseColor = simd_clamp(box.color * 2.4, SIMD3<Float>(repeating: 0.0), SIMD3<Float>(repeating: 0.96))
            } else {
                baseColor = rainbowColors[idx % rainbowColors.count].0 * 0.85
            }

            let mat = RTMaterial(
                color: baseColor,
                roughness: 0.96,
                emission: .zero,
                reflectivity: 0.0,
                kind: 0
            )
            builder.addBox(center: box.center, size: box.size, material: mat, doubleSided: false)
        }

        return builder
    }
}
