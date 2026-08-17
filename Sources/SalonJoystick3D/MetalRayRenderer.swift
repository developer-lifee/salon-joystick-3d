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
    RTRiverRock(center: SIMD3<Float>(13.8, 1.2, 13.8), radii: SIMD3<Float>(1.2, 1.3, 1.2), color: SIMD3<Float>(0.20, 0.25, 0.30))
]

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

    mutating func addBox(center: SIMD3<Float>, size: SIMD3<Float>, material: RTMaterial) {
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
        segments: Int = 14,
        rings: Int = 7
    ) {
        func point(ring: Int, segment: Int) -> SIMD3<Float> {
            let latitude = -.pi / 2 + .pi * Float(ring) / Float(rings)
            let longitude = 2 * .pi * Float(segment) / Float(segments)
            let noise = 1
                + sin(longitude * 3.0 + seed * 1.7) * 0.075
                + cos(longitude * 5.0 - latitude * 2.0 + seed) * 0.045
                + sin(latitude * 4.0 + seed * 2.3) * 0.035
            let latitudeCosine = cos(latitude)
            let lowerFlattening: Float = latitude < 0 ? 0.82 : 1
            return center + SIMD3<Float>(
                latitudeCosine * cos(longitude) * radii.x * noise,
                sin(latitude) * radii.y * lowerFlattening,
                latitudeCosine * sin(longitude) * radii.z * noise
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
        let halo = RTMaterial(
            color: SIMD3<Float>(0.002, 0.025, 0.16),
            roughness: 0.2,
            emission: SIMD3<Float>(0.005, 0.12, 0.85),
            kind: 7
        )
        let core = RTMaterial(
            color: SIMD3<Float>(0.01, 0.20, 1.0),
            roughness: 0.08,
            emission: SIMD3<Float>(0.04, 1.15, 8.0),
            kind: 7
        )

        for (glyphIndex, glyph) in glyphs.enumerated() {
            let offset = origin + SIMD2<Float>(Float(glyphIndex) * 0.72, 0)
            for segment in glyph {
                addFlatSegment(
                    from: segment.0 + offset,
                    to: segment.1 + offset,
                    z: z + 0.015,
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

    mutating func addCharacter(
        origin: SIMD3<Float>,
        color: SIMD3<Float>,
        eyes: Bool = true,
        holdsTool: Bool = false
    ) {
        let suit = RTMaterial(color: color, roughness: 0.42, reflectivity: 0.18)
        let armor = RTMaterial(color: SIMD3<Float>(0.08, 0.12, 0.16), roughness: 0.18, reflectivity: 0.65)
        let visor = RTMaterial(color: SIMD3<Float>(0.05, 0.85, 0.98), roughness: 0.02, emission: SIMD3<Float>(0.1, 0.45, 0.75), reflectivity: 0.94, kind: 1.0)
        let coreEmissive = RTMaterial(color: SIMD3<Float>(1.0, 0.2, 0.4), roughness: 0.10, emission: SIMD3<Float>(3.5, 0.8, 1.2), reflectivity: 0.50, kind: 5.0)
        let dark = RTMaterial(color: SIMD3<Float>(repeating: 0.012), roughness: 0.92)
        let scubaTankMat = RTMaterial(color: SIMD3<Float>(0.92, 0.85, 0.12), roughness: 0.15, reflectivity: 0.75)
        let flipperMat = RTMaterial(color: SIMD3<Float>(0.95, 0.45, 0.05), roughness: 0.25, reflectivity: 0.40)

        // Torso & Armor Chest Plate
        addSphere(center: origin + SIMD3<Float>(0, 0.86, 0), radii: SIMD3<Float>(0.34, 0.50, 0.27), material: suit)
        addBox(center: origin + SIMD3<Float>(0, 0.92, 0.16), size: SIMD3<Float>(0.44, 0.42, 0.12), material: armor)
        addSphere(center: origin + SIMD3<Float>(0, 0.95, 0.23), radii: SIMD3<Float>(repeating: 0.08), material: coreEmissive)

        // 🤿 Scuba Oxygen Tank on Back & Regulator Valve
        addBox(center: origin + SIMD3<Float>(0, 0.92, -0.22), size: SIMD3<Float>(0.28, 0.55, 0.18), material: scubaTankMat)
        addSphere(center: origin + SIMD3<Float>(0, 1.22, -0.22), radii: SIMD3<Float>(repeating: 0.09), material: armor)

        // Helmet & Curved Visor
        addSphere(center: origin + SIMD3<Float>(0, 1.55, 0), radii: SIMD3<Float>(repeating: 0.32), material: suit)
        addBox(center: origin + SIMD3<Float>(0, 1.58, 0.22), size: SIMD3<Float>(0.38, 0.18, 0.14), material: visor)

        // 🦾 Articulated Upper Arms, Elbow Joints & Forearms
        // Left & Right Shoulder Joints
        addSphere(center: origin + SIMD3<Float>(-0.42, 1.15, 0), radii: SIMD3<Float>(repeating: 0.11), material: armor)
        addSphere(center: origin + SIMD3<Float>( 0.42, 1.15, 0), radii: SIMD3<Float>(repeating: 0.11), material: armor)
        // Upper Arms
        addBox(center: origin + SIMD3<Float>(-0.42, 0.96, 0), size: SIMD3<Float>(0.14, 0.28, 0.15), material: suit)
        addBox(center: origin + SIMD3<Float>( 0.42, 0.96, 0), size: SIMD3<Float>(0.14, 0.28, 0.15), material: suit)
        // 🦾 ELBOW JOINTS (Articulaciones de Codo Visibles)
        addSphere(center: origin + SIMD3<Float>(-0.42, 0.80, 0.02), radii: SIMD3<Float>(repeating: 0.095), material: armor)
        addSphere(center: origin + SIMD3<Float>( 0.42, 0.80, 0.02), radii: SIMD3<Float>(repeating: 0.095), material: armor)
        // Forearms (Bent forward slightly at elbow joint!)
        addBox(center: origin + SIMD3<Float>(-0.42, 0.65, 0.08), size: SIMD3<Float>(0.13, 0.26, 0.16), material: suit)
        addBox(center: origin + SIMD3<Float>( 0.42, 0.65, 0.08), size: SIMD3<Float>(0.13, 0.26, 0.16), material: suit)

        // 🦵 Articulated Thighs, Knee Joints, Calves & Scuba Flippers
        // Hip Joints
        addSphere(center: origin + SIMD3<Float>(-0.16, 0.52, 0), radii: SIMD3<Float>(repeating: 0.10), material: armor)
        addSphere(center: origin + SIMD3<Float>( 0.16, 0.52, 0), radii: SIMD3<Float>(repeating: 0.10), material: armor)
        // Thighs
        addBox(center: origin + SIMD3<Float>(-0.16, 0.38, 0), size: SIMD3<Float>(0.15, 0.26, 0.16), material: suit)
        addBox(center: origin + SIMD3<Float>( 0.16, 0.38, 0), size: SIMD3<Float>(0.15, 0.26, 0.16), material: suit)
        // 🦵 KNEE JOINTS (Articulaciones de Rodilla Visibles)
        addSphere(center: origin + SIMD3<Float>(-0.16, 0.23, 0.02), radii: SIMD3<Float>(repeating: 0.095), material: armor)
        addSphere(center: origin + SIMD3<Float>( 0.16, 0.23, 0.02), radii: SIMD3<Float>(repeating: 0.095), material: armor)
        // Calves
        addBox(center: origin + SIMD3<Float>(-0.16, 0.10, 0.03), size: SIMD3<Float>(0.14, 0.24, 0.15), material: suit)
        addBox(center: origin + SIMD3<Float>( 0.16, 0.10, 0.03), size: SIMD3<Float>(0.14, 0.24, 0.15), material: suit)
        // 🤿 Scuba Diving Flippers / Boots
        addBox(center: origin + SIMD3<Float>(-0.16, 0.02, 0.16), size: SIMD3<Float>(0.17, 0.05, 0.36), material: flipperMat)
        addBox(center: origin + SIMD3<Float>( 0.16, 0.02, 0.16), size: SIMD3<Float>(0.17, 0.05, 0.36), material: flipperMat)

        if eyes {
            addSphere(center: origin + SIMD3<Float>(-0.11, 1.60, 0.29), radii: SIMD3<Float>(repeating: 0.04), material: dark, segments: 7, rings: 4)
            addSphere(center: origin + SIMD3<Float>( 0.11, 1.60, 0.29), radii: SIMD3<Float>(repeating: 0.04), material: dark, segments: 7, rings: 4)
        }
        if holdsTool {
            let tool = RTMaterial(color: SIMD3<Float>(0.055, 0.060, 0.065), roughness: 0.34, reflectivity: 0.10)
            addBox(
                center: origin + SIMD3<Float>(0.47, 0.65, 0.28),
                size: SIMD3<Float>(0.14, 0.16, 0.42),
                material: tool
            )
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
    var onScoreUpdate: ((Int) -> Void)?
    var onDamageTaken: ((Float) -> Void)?
    var onWaveUpdate: ((Int, Int, Int, Bool, Float) -> Void)?
    var isPlayerDead: Bool = false

    private var currentWave: Int = 1
    private var botsKilledInCurrentWave: Int = 0
    private var totalBotsInWave: Int = 5
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
    private let npcMesh: RTMeshResources
    private let waterMesh: RTMeshResources
    private let floatMesh: RTMeshResources
    private let mirrorShieldMesh: RTMeshResources
    private let instanceBuffer: MTLBuffer
    private var instanceDescriptor: MTLInstanceAccelerationStructureDescriptor?
    private var instanceAccelerationStructure: MTLAccelerationStructure?
    private var instanceScratchBuffer: MTLBuffer?
    private let frameSemaphore = DispatchSemaphore(value: 1)
    private let audio: ChiptuneAudioEngine

    private var joystick = CGVector.zero
    private var cameraMode = GameCameraMode.thirdPerson
    private var rayBouncesEnabled = true
    private var heldTool = GameHeldTool.flashlight
    private var lightStates = GameLightStates()
    private var lastNearbyLight: GameLightFixture?
    private var hasReportedNearbyLight = false
    private var handledJumpRequestID = 0
    private var jumpQueued = false
    private var cameraYaw: Float = 0
    private var orbitPitch: Float = 0.36
    private var firstPersonPitch: Float = 0
    private var playerPosition = SIMD3<Float>(3.8, 0, 3.8)
    private var horizontalVelocity = SIMD2<Float>.zero
    private var verticalVelocity: Float = 0
    private var playerYaw: Float = .pi
    private var isSlidingOnToboggan: Bool = false
    private var npcPositions: [SIMD3<Float>] = [
        SIMD3<Float>(-3.8, 0, -2.8),
        SIMD3<Float>(1.8, 0, -2.8),
        SIMD3<Float>(-3.8, 0, 0.2),
        SIMD3<Float>(1.8, 0, 0.2),
        SIMD3<Float>(-1.0, 0, -3.5)
    ]
    private var npcYaws = [Float.pi * 0.25, Float.pi * 1.7, Float.pi * 0.75, Float.pi * 1.25, Float.pi * 0.0]
    private var npcRespawnTimers = [Float](repeating: 0, count: 5)
    private let npcMaxHealths: [Float] = [80.0, 120.0, 180.0, 250.0, 350.0]
    private var npcHealths: [Float] = [80.0, 120.0, 180.0, 250.0, 350.0]
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
        let playerBuilder = Self.makePlayerMesh()
        let npcBuilder = Self.makeNPCMesh()
        let waterBuilder = Self.makeWaterMesh()
        let floatBuilder = Self.makeFloatMesh()
        let mirrorShieldBuilder = Self.makeMirrorShieldMesh()
        self.staticMesh = try Self.makeMesh(builder: staticBuilder, device: device, queue: commandQueue)
        self.playerMesh = try Self.makeMesh(builder: playerBuilder, device: device, queue: commandQueue)
        self.npcMesh = try Self.makeMesh(builder: npcBuilder, device: device, queue: commandQueue)
        self.waterMesh = try Self.makeMesh(
            builder: waterBuilder,
            device: device,
            queue: commandQueue,
            allowsRefit: true
        )
        self.floatMesh = try Self.makeMesh(builder: floatBuilder, device: device, queue: commandQueue)
        self.mirrorShieldMesh = try Self.makeMesh(builder: mirrorShieldBuilder, device: device, queue: commandQueue)

        let instanceLength = MemoryLayout<MTLAccelerationStructureInstanceDescriptor>.stride * 10
        guard let instanceBuffer = device.makeBuffer(length: instanceLength, options: .storageModeShared) else {
            throw MetalRayRendererError.resourceCreationFailed
        }
        self.instanceBuffer = instanceBuffer

        if device.isHardwareRayTracingSupported,
           let staticAS = staticMesh.accelerationStructure,
           let playerAS = playerMesh.accelerationStructure,
           let waterAS = waterMesh.accelerationStructure,
           let floatAS = floatMesh.accelerationStructure,
           let npcAS = npcMesh.accelerationStructure,
           let shieldAS = mirrorShieldMesh.accelerationStructure {
            let descriptor = MTLInstanceAccelerationStructureDescriptor()
            descriptor.instancedAccelerationStructures = [
                staticAS,
                playerAS,
                waterAS,
                floatAS,
                npcAS,
                shieldAS
            ]
            descriptor.instanceCount = 10
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

    private var handledWarpRequestID = 0
    private var handledResetRequestID = 0
    private var handledRespawnRequestID = 0

    func resetSimulation() {
        playerPosition = SIMD3<Float>(3.8, 0, 3.8)
        horizontalVelocity = .zero
        verticalVelocity = 0
        playerYaw = .pi
        cameraYaw = 0
        orbitPitch = 0.36
        firstPersonPitch = 0
        isSlidingOnToboggan = false

        currentWave = 1
        botsKilledInCurrentWave = 0
        totalBotsInWave = 5
        isWaveIntermission = false
        intermissionTimeRemaining = 0
        npcHealths = npcMaxHealths

        for i in npcPositions.indices {
            let spawnIndex = i % npcSpawnPositions.count
            npcPositions[i] = npcSpawnPositions[spawnIndex]
            npcYaws[i] = Float.pi * (0.25 + Float(i) * 0.5)
            npcRespawnTimers[i] = 0
            npcHealths[i] = npcMaxHealths[i]
            botLaserActiveTimers[i] = 0
            botLaserCooldownTimers[i] = 5.0
            botTeleportReactionTimers[i] = 0
            botAimTargets[i] = npcSpawnPositions[spawnIndex] + SIMD3<Float>(0, 1.1, 0)
        }
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
        respawnRequestID: Int = 0
    ) {
        self.joystick = joystick
        self.cameraMode = cameraMode
        self.rayBouncesEnabled = rayBouncesEnabled
        self.heldTool = heldTool
        self.lightStates = lightStates
        self.isSlowMotionActive = isSlowMotionActive
        self.isGamePaused = isPaused
        self.isCoverActive = isCoverActive
        self.shieldYawOffset = Float(shieldAngleOffset.dx) * 0.75
        self.shieldPitchOffset = -Float(shieldAngleOffset.dy) * 0.60
        if handledJumpRequestID != jumpRequestID {
            handledJumpRequestID = jumpRequestID
            jumpQueued = true
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
            orbitPitch = 0.36
        }
    }

    func rotateCamera(deltaX: Float, deltaY: Float) {
        cameraYaw += deltaX * 0.0075
        if cameraMode == .firstPerson {
            firstPersonPitch = max(-1.35, min(1.35, firstPersonPitch - deltaY * 0.0045))
        } else {
            orbitPitch = max(-1.10, min(1.25, orbitPitch - deltaY * 0.0045))
        }
    }

    func resetCamera() {
        cameraYaw = playerYaw + .pi
        orbitPitch = 0.36
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
                if let waterAS = waterMesh.accelerationStructure { encoder.useResource(waterAS, usage: .read) }
                if let floatAS = floatMesh.accelerationStructure { encoder.useResource(floatAS, usage: .read) }
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

    private func accumulateDamage(_ amount: Float) {
        pendingDamageAccumulator += amount
    }

    private func flushDamageReport(rawDt: Float) {
        damageReportTimer += rawDt
        if damageReportTimer >= 0.10 && pendingDamageAccumulator > 0 {
            let dmg = pendingDamageAccumulator
            pendingDamageAccumulator = 0
            damageReportTimer = 0
            onDamageTaken?(dmg)
        }
    }

    private func updateSimulation(dt: Float, rawDt: Float) {
        updateToolTimers(dt: dt)
        updateNPCSimulation(dt: dt, rawDt: rawDt)
        flushDamageReport(rawDt: rawDt)
        checkCombatHits()
        onNPCHealthsUpdate?(npcHealths)
        let wasRidingFloat = isStandingOnFloat(playerPosition)
        let floatDisplacement = updateFloatSimulation(dt: dt)
        if wasRidingFloat {
            playerPosition += floatDisplacement
        }
        let previousWaterImmersion = waterImmersion(
            at: playerPosition,
            insidePool: isInsidePoolXZ(playerPosition)
        )

        let inputX = max(-1.0, min(1.0, Float(joystick.dx)))
        let inputForward = max(-1.0, min(1.0, -Float(joystick.dy)))
        let magnitude = min(1.0, hypot(inputX, inputForward))
        let cameraForward = SIMD2<Float>(-sin(cameraYaw), -cos(cameraYaw))
        let cameraRight = SIMD2<Float>(cos(cameraYaw), -sin(cameraYaw))
        var desiredDirection = cameraRight * inputX + cameraForward * inputForward
        if simd_length_squared(desiredDirection) > 0.0001 {
            desiredDirection = simd_normalize(desiredDirection)
        }

        let currentlyInPool = isInsidePoolXZ(playerPosition) && playerPosition.y > -3.0
        let isSubterranean = playerPosition.y <= -3.0
        let currentGroundHeight = isSubterranean ? -8.50 : groundHeight(at: playerPosition, insidePool: currentlyInPool)
        let currentlyOnFloat = currentlyInPool && isStandingOnFloat(playerPosition)
        let movementSpeed: Float = currentlyInPool && !currentlyOnFloat ? 2.8 : (isSubterranean ? 3.8 : 3.6)
        let targetVelocity = desiredDirection * (magnitude > 0.08 ? movementSpeed * magnitude : 0)
        let response = 1 - exp(-dt * (magnitude > 0.08 ? 13 : 18))
        horizontalVelocity += (targetVelocity - horizontalVelocity) * response
        if simd_length(horizontalVelocity) < 0.015 && magnitude <= 0.08 {
            horizontalVelocity = .zero
        }

        // 🪜 Vertical Ladder Climb Physics (Climbs straight up to top platform at Z = -15.8)
        let nearVerticalLadder = playerPosition.x >= -4.45 && playerPosition.x <= -3.15 && playerPosition.z >= -17.2 && playerPosition.z <= -15.5
        if nearVerticalLadder && playerPosition.y < 5.60 {
            if magnitude > 0.05 || jumpQueued {
                jumpQueued = false
                playerPosition.x = -3.80
                horizontalVelocity = .zero
                verticalVelocity = 4.2
            }
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

        // 🌀 Subterranean Easter Egg Portal Plunge Trigger (EXCLUSIVELY for Toboggan Slide)
        let nearSlidePlungeZone = playerPosition.x >= -4.5 && playerPosition.x <= -0.5 && playerPosition.z >= -7.8 && playerPosition.z <= -1.0
        if isSlidingOnToboggan && (tProj >= 0.65 || playerPosition.y <= 2.2) && nearSlidePlungeZone {
            // 🌀 High-speed plunge launch directly into subterranean underwater realm!
            playerPosition = SIMD3<Float>(-2.5, -5.5, -2.5)
            verticalVelocity = -0.5
            isSlidingOnToboggan = false
            audio.playLaserIgnition()
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
            // 🛡️ Crouch Cover: Agacharse pegado al suelo detrás de la piedra (Y = groundHeight + 0.15m)
            playerPosition.y = currentGroundHeight + 0.15
            horizontalVelocity *= exp(-dt * 6.0)
        }

        // 🌀 Salida del Easter Egg (Underwater Portal Exit Ring at X=0, Z=0)
        if playerPosition.y <= -3.0 {
            let distToExit = simd_distance(SIMD2<Float>(playerPosition.x, playerPosition.z), SIMD2<Float>(0, 0))
            if distToExit < 1.8 {
                // Teleport back up smoothly onto the patio pool deck safely out of water!
                playerPosition = SIMD3<Float>(-1.5, 0.45, 1.8)
                verticalVelocity = 0.5
                audio.playWaterDisturbance(intensity: 1.0)
            }
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
        proposed.x = max(-17.0, min(17.0, proposed.x))
        proposed.z = max(-17.0, min(17.0, proposed.z))
        resolveFloatCollision(position: &proposed)
        resolveRockCollisions(position: &proposed)
        let willBeInPool = isInsidePoolXZ(proposed) && proposed.y > -3.0
        let nextGroundHeight = groundHeight(at: proposed, insidePool: willBeInPool)
        let willBeOnFloat = willBeInPool && nextGroundHeight > -0.1
        let wasGrounded = playerPosition.y <= currentGroundHeight + 0.05 || (currentlyInPool && playerPosition.y <= 0.1)

        // Smooth Auto-Step Up for Stairs & Ramps (step height up to 0.45m)
        if !currentlyInPool && nextGroundHeight > currentGroundHeight && (nextGroundHeight - currentGroundHeight) <= 0.45 {
            if playerPosition.y <= currentGroundHeight + 0.15 {
                proposed.y = nextGroundHeight
            }
        }

        let isSubterraneanSubmerged = playerPosition.y <= -3.0 || proposed.y <= -3.0
        let onTrampolineBoard = playerPosition.x >= 0.7 && playerPosition.x <= 2.1 && playerPosition.z >= -6.9 && playerPosition.z <= -3.7 && playerPosition.y >= 2.7

        if jumpQueued {
            jumpQueued = false
            if isSubterraneanSubmerged {
                verticalVelocity = 3.2
                audio.playUnderwaterGlug(intensity: 0.85)
            } else if onTrampolineBoard {
                verticalVelocity = 4.8
                horizontalVelocity = SIMD2<Float>(0.0, 5.5)
            } else if wasGrounded {
                verticalVelocity = currentlyInPool ? 3.8 : 5.2
            }
        }

        if isSubterraneanSubmerged {
            // Smooth zero-gravity underwater swimming & viscous fluid drag
            horizontalVelocity *= exp(-dt * 2.8)
            verticalVelocity = max(-0.55, verticalVelocity - dt * 1.5)
            if Float.random(in: 0...1) < dt * 0.95 {
                audio.playUnderwaterGlug(intensity: 0.45)
            }
        } else if willBeInPool && !willBeOnFloat {
            // Smooth pool fluid physics without surface bobbing glitches
            let depthInWater = max(0, -proposed.y)
            let targetY: Float = -0.35
            if depthInWater > 0 {
                let diff = targetY - proposed.y
                verticalVelocity += diff * 12.0 * dt
                verticalVelocity *= exp(-dt * 3.5)
            } else {
                verticalVelocity -= 6.5 * dt
            }
            horizontalVelocity *= exp(-dt * 2.2)
        } else {
            verticalVelocity -= 9.8 * dt
        }

        var landingSpeed: Float = 0
        proposed.y += verticalVelocity * dt
        if proposed.y <= -3.0 || playerPosition.y <= -3.0 {
            proposed.y = max(-8.50, proposed.y)
        } else if isSlidingOnToboggan {
            // Position locked during slide descent to prevent ground clamping
            proposed = playerPosition
        } else if currentlyInPool && !willBeOnFloat {
            proposed.y = max(-0.66, min(1.5, proposed.y))
        } else if proposed.y <= nextGroundHeight {
            if !wasGrounded && verticalVelocity < -1.2 {
                landingSpeed = -verticalVelocity
            }
            proposed.y = nextGroundHeight
            verticalVelocity = 0
        }
        playerPosition = proposed
        reportNearbyLightIfNeeded()
        let currentWaterImmersion = waterImmersion(
            at: playerPosition,
            insidePool: willBeInPool
        )

        if currentWaterImmersion > 0 && previousWaterImmersion <= 0 {
            let entryIntensity = min(1, max(0.38, -verticalVelocity / 3.8))
            pendingWaterImpulse = SIMD4<Float>(playerPosition.x, playerPosition.z, -1.05, 1)
            audio.playWaterDisturbance(intensity: entryIntensity)
        }

        let enteredWaterThisFrame = currentWaterImmersion > 0 && previousWaterImmersion <= 0
        if landingSpeed > 0 && !enteredWaterThisFrame && currentWaterImmersion <= 0 {
            let impact = min(1, max(0.15, (landingSpeed - 1.0) / 4.2))
            if currentWaterImmersion <= 0 || willBeOnFloat {
                audio.playLanding(intensity: impact)
            }
        }

        if cameraMode == .firstPerson {
            playerYaw = cameraYaw + .pi
        } else if magnitude > 0.08 {
            let targetYaw = atan2(desiredDirection.x, desiredDirection.y)
            let delta = atan2(sin(targetYaw - playerYaw), cos(targetYaw - playerYaw))
            playerYaw += delta * min(1, dt * 11)
        }

        let speed = simd_length(horizontalVelocity)
        let isGrounded = playerPosition.y <= nextGroundHeight + 0.015
        let playerWaterMovement = min(1, speed / 1.2) * currentWaterImmersion
        if playerWaterMovement > 0.04 && currentlyInPool {
            playerWaterWakeCountdown -= dt
            if playerWaterWakeCountdown <= 0 {
                pendingWaterImpulse = SIMD4<Float>(
                    playerPosition.x,
                    playerPosition.z,
                    -0.38 - playerWaterMovement * 0.42,
                    1
                )
                playerWaterWakeCountdown = 0.12
            }
        } else if !currentlyInPool {
            playerWaterWakeCountdown = 0
        }
        let floatWaterMovement = min(0.72, max(0, (simd_length(floatVelocity) - 0.04) / 0.95))
        let waterMovementIntensity = max(playerWaterMovement, floatWaterMovement)
        let waterStateChanged = (waterMovementIntensity > 0.01) !=
            (lastSubmittedWaterMovementIntensity > 0.01)
        if waterStateChanged ||
            abs(waterMovementIntensity - lastSubmittedWaterMovementIntensity) >= 0.025 {
            lastSubmittedWaterMovementIntensity = waterMovementIntensity
            audio.setWaterMovementIntensity(waterMovementIntensity)
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

    private func updateToolTimers(dt: Float) {
        if laserCooldownRemaining > 0 { laserCooldownRemaining = max(0, laserCooldownRemaining - dt) }
        if mirrorCooldownRemaining > 0 { mirrorCooldownRemaining = max(0, mirrorCooldownRemaining - dt) }

        if heldTool != lastHeldTool {
            lastHeldTool = heldTool
            if heldTool == .laser && laserCooldownRemaining <= 0 {
                laserActiveRemaining = 4.0
                laserPropagationDistance = 0.0
                audio.playLaserIgnition()
            } else if heldTool == .mirror && mirrorCooldownRemaining <= 0 {
                mirrorActiveRemaining = 3.0
            }
        }

        if heldTool == .laser && laserActiveRemaining > 0 {
            laserActiveRemaining = max(0, laserActiveRemaining - dt)
            if laserActiveRemaining == 0 { laserCooldownRemaining = 6.0 }

            if isSlowMotionActive {
                laserPropagationDistance += dt * 14.0
            } else {
                laserPropagationDistance = 100.0
            }

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
                        audio.playWaterDisturbance(intensity: 0.90)
                        onScoreUpdate?(300)
                    }
                }
            }
            for i in npcPositions.indices where npcRespawnTimers[i] <= 0 {
                let center = npcPositions[i] + SIMD3<Float>(0, 0.85, 0)
                let toCenter = center - origin
                let proj = simd_dot(toCenter, forward)
                if proj > 0 && proj < 22.0 {
                    let closest = origin + forward * proj
                    if simd_distance(center, closest) < 0.70 {
                        audio.playWaterDisturbance(intensity: 0.90)
                        onScoreUpdate?(400)
                        handleNPCElimination(index: i)
                    }
                }
            }
        }
        if heldTool == .mirror && mirrorActiveRemaining > 0 {
            mirrorActiveRemaining = max(0, mirrorActiveRemaining - dt)
            if mirrorActiveRemaining == 0 { mirrorCooldownRemaining = 5.0 }
        }

        toolStatusCountdown -= dt
        if toolStatusCountdown <= 0 {
            toolStatusCountdown = 0.08
            let active: Float
            let cooldown: Float
            switch heldTool {
            case .laser:
                active = laserActiveRemaining; cooldown = laserCooldownRemaining
            case .mirror:
                active = mirrorActiveRemaining; cooldown = mirrorCooldownRemaining
            default:
                active = 0; cooldown = 0
            }
            let label: String
            if cooldown > 0.01 {
                label = String(format: "Recarga %.1f s", cooldown)
            } else if active > 0.01 {
                label = String(format: "Activo %.1f s", active)
            } else {
                label = ""
            }
            onToolStatusUpdate?(GameToolStatus(activeRemaining: active, cooldownRemaining: cooldown, label: label))
        }
    }

    private func recordBotElimination() {
        botsKilledInCurrentWave += 1
        let remainingInWave = max(0, totalBotsInWave - botsKilledInCurrentWave)
        onWaveUpdate?(currentWave, remainingInWave, totalBotsInWave, isWaveIntermission, intermissionTimeRemaining)

        if remainingInWave <= 0 {
            // Wave cleared! Trigger 10-second intermission rest
            isWaveIntermission = true
            intermissionTimeRemaining = 10.0
            audio.playWaterDisturbance(intensity: 1.0)
            onDamageTaken?(-25.0) // Health regen rest reward (+25 HP)
        }
    }

    private func handleNPCElimination(index: Int) {
        let activeBotsCount = npcPositions.indices.filter({ npcRespawnTimers[$0] <= 0 }).count
        let totalWaveSpawnsSoFar = botsKilledInCurrentWave + activeBotsCount
        if totalWaveSpawnsSoFar < totalBotsInWave {
            npcRespawnTimers[index] = 4.0
        } else {
            npcRespawnTimers[index] = 9999.0
        }
        npcPositions[index].y = -10
        recordBotElimination()
    }

    private func updateNPCSimulation(dt: Float, rawDt: Float) {
        let results = laserResultBuffer.contents().assumingMemoryBound(to: RTLaserResult.self)

        // Periodic wave status HUD sync
        waveStatusReportCountdown -= dt
        if waveStatusReportCountdown <= 0 {
            waveStatusReportCountdown = 0.25
            let remaining = max(0, totalBotsInWave - botsKilledInCurrentWave)
            onWaveUpdate?(currentWave, remaining, totalBotsInWave, isWaveIntermission, intermissionTimeRemaining)
        }

        // Handle Intermission Rest State between waves
        if isWaveIntermission {
            intermissionTimeRemaining -= dt
            onWaveUpdate?(currentWave, 0, totalBotsInWave, true, max(0, intermissionTimeRemaining))
            if intermissionTimeRemaining <= 0 {
                isWaveIntermission = false
                currentWave += 1
                botsKilledInCurrentWave = 0
                totalBotsInWave = 5 + (currentWave - 1) * 3
                audio.playLaserIgnition()
                onWaveUpdate?(currentWave, totalBotsInWave, totalBotsInWave, false, 0)
                for i in npcPositions.indices {
                    npcRespawnTimers[i] = 0.5 + Float(i) * 0.4
                    botLaserActiveTimers[i] = 0
                    botTeleportReactionTimers[i] = 0
                }
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

        for index in npcPositions.indices {
            switch index {
            case 0: results.pointee.bot0Start = .zero; results.pointee.bot0End = .zero
            case 1: results.pointee.bot1Start = .zero; results.pointee.bot1End = .zero
            case 2: results.pointee.bot2Start = .zero; results.pointee.bot2End = .zero
            case 3: results.pointee.bot3Start = .zero; results.pointee.bot3End = .zero
            case 4: results.pointee.bot4Start = .zero; results.pointee.bot4End = .zero
            default: break
            }

            if npcRespawnTimers[index] > 0 {
                npcRespawnTimers[index] = max(0, npcRespawnTimers[index] - dt)
                npcPositions[index].y = -10
                if npcRespawnTimers[index] == 0 {
                    npcPositions[index] = npcSpawnPositions[index]
                    npcHealths[index] = npcMaxHealths[index]
                    botAimTargets[index] = npcSpawnPositions[index] + SIMD3<Float>(0, 1.1, 0)
                    botLaserCooldownTimers[index] = 2.0 + Float(index) * 1.2
                    botLaserActiveTimers[index] = 0
                    botTeleportReactionTimers[index] = 0
                }
                continue
            }

            if botTeleportReactionTimers[index] > 0 {
                botTeleportReactionTimers[index] = max(0, botTeleportReactionTimers[index] - dt)
            }

            let playerHiddenInEasterEgg = playerPosition.y < -3.0
            if playerHiddenInEasterEgg {
                // NPCs cannot see player hidden in underwater realm!
                npcYaws[index] += sin(dt * Float(index + 1)) * 0.8 * dt
                continue
            }

            let offset = SIMD2<Float>(
                playerPosition.x - npcPositions[index].x,
                playerPosition.z - npcPositions[index].z
            )
            let distance = simd_length(offset)
            let direction = distance > 0.001 ? offset / distance : SIMD2<Float>(0, 1)

            // Dynamic difficulty scaling per wave (Call of Duty Black Ops Zombies style!)
            let speed: Float = min(4.2, 2.0 + Float(currentWave) * 0.35 + Float(index) * 0.3)
            let botCooldown: Float = max(1.4, 4.5 - Float(currentWave) * 0.40)
            let aimSpeedScale: Float = min(12.0, 5.5 + Float(currentWave) * 0.75)
            if distance > 0.65 {
                var proposedX = npcPositions[index].x + direction.x * speed * dt
                var proposedZ = npcPositions[index].z + direction.y * speed * dt

                // Outer Patio Wall Colliders (Expanded 34m x 34m Arena)
                proposedX = max(-17.0, min(17.0, proposedX))
                proposedZ = max(-17.0, min(17.0, proposedZ))

                // Solid Pool Coping Wall Colliders for NPCs
                let isInsidePool = proposedX >= -5.0 && proposedX <= 5.0 && proposedZ >= -5.0 && proposedZ <= 5.0
                let wasInsidePool = npcPositions[index].x >= -5.0 && npcPositions[index].x <= 5.0 && npcPositions[index].z >= -5.0 && npcPositions[index].z <= 5.0
                if !wasInsidePool && isInsidePool && npcPositions[index].y < 0.2 {
                    // Push NPC back outside pool rim
                    proposedX = npcPositions[index].x
                    proposedZ = npcPositions[index].z
                }

                // Player Body Solid Push-Back Collider
                let toPlayer = SIMD2<Float>(proposedX - playerPosition.x, proposedZ - playerPosition.z)
                let playerDist = simd_length(toPlayer)
                if playerDist < 0.62 {
                    let pushDir = playerDist > 0.001 ? toPlayer / playerDist : SIMD2<Float>(1, 0)
                    proposedX = playerPosition.x + pushDir.x * 0.62
                    proposedZ = playerPosition.z + pushDir.y * 0.62
                }

                // Apply Scenario Rock Collisions to NPCs (Same rules as player!)
                var npcPos = SIMD3<Float>(proposedX, npcPositions[index].y, proposedZ)
                resolveRockCollisions(position: &npcPos)
                proposedX = npcPos.x
                proposedZ = npcPos.z

                npcPositions[index].x = proposedX
                npcPositions[index].z = proposedZ
            }
            npcYaws[index] = atan2(direction.x, direction.y)

            // Smooth human-like aim tracking & dispersion
            let actualPlayerCenter = playerPosition + SIMD3<Float>(0, 1.10, 0)
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
            let playerTarget = botAimTargets[index]

            // Bot Laser Combat AI with symmetric active/cooldown windows & 3D visual beams
            if botLaserCooldownTimers[index] > 0 {
                botLaserCooldownTimers[index] = max(0, botLaserCooldownTimers[index] - dt)
                if botLaserCooldownTimers[index] == 0 && distance < 12.0 && botTeleportReactionTimers[index] <= 0 {
                    botLaserActiveTimers[index] = 2.2
                    // Reset propagation when bot fires a new burst
                    botLaserPropagationDistances[index] = 0
                    botLaserOrigins[index] = npcPositions[index] + SIMD3<Float>(0.42, 0.88, 0.20)
                    botLaserDistancesToPlayer[index] = simd_distance(botLaserOrigins[index], playerTarget)
                }
            } else if botLaserActiveTimers[index] > 0 && botTeleportReactionTimers[index] <= 0 {
                botLaserActiveTimers[index] = max(0, botLaserActiveTimers[index] - dt)

                let botHandOrigin = npcPositions[index] + SIMD3<Float>(0.42, 0.88, 0.20)
                let playerTarget = playerPosition + SIMD3<Float>(0, 1.10, 0)
                let bTotalDist = max(0.001, simd_distance(botHandOrigin, playerTarget))
                let bDir = simd_normalize(playerTarget - botHandOrigin)

                // 🪨 Check Rock Cover Oclusion (El láser de bot NO atraviesa las piedras)
                var closestHitDist: Float = bTotalDist
                var hitRock = false
                for rock in rtRiverRocks {
                    let center = rock.center
                    let radius = max(rock.radii.x, rock.radii.z)
                    let toCenter = center - botHandOrigin
                    let proj = simd_dot(toCenter, bDir)
                    if proj > 0.1 && proj < closestHitDist {
                        let closestPointOnRay = botHandOrigin + bDir * proj
                        let distToRock = simd_distance(center, closestPointOnRay)
                        if distToRock < (radius + 0.35) {
                            closestHitDist = proj - 0.2
                            hitRock = true
                        }
                    }
                }

                let bEndActual = botHandOrigin + bDir * closestHitDist
                let bProgress: Float = 1.0
                let startVec = SIMD4<Float>(botHandOrigin, 1.0)
                var endVec: SIMD4<Float> = .zero

                let playerIsUsingMirror = (heldTool == .mirror && mirrorActiveRemaining > 0)
                let effYaw = playerYaw + shieldYawOffset
                let effPitch = (cameraMode == .firstPerson ? firstPersonPitch : orbitPitch) + shieldPitchOffset

                let shieldCenter = playerPosition + SIMD3<Float>(sin(effYaw) * 0.50, 1.05 + sin(effPitch) * 0.30, cos(effYaw) * 0.50)
                let shieldNormal = SIMD3<Float>(
                    sin(effYaw) * cos(effPitch),
                    sin(effPitch),
                    cos(effYaw) * cos(effPitch)
                )
                let laserRayDir = bDir
                let facingDot = simd_dot(-laserRayDir, shieldNormal)

                if playerIsUsingMirror && facingDot > 0.15 {
                    // Real 3D Optical Reflection (Snell's Law: R = I - 2 * (I · N) * N)
                    let reflectedDir = simd_normalize(laserRayDir - 2.0 * simd_dot(laserRayDir, shieldNormal) * shieldNormal)
                    var reflectedHitEnd = shieldCenter + reflectedDir * 22.0

                    // Check if reflected beam hits any rival bot along angle R
                    for targetIdx in npcPositions.indices where npcRespawnTimers[targetIdx] <= 0 {
                        let botCenter = npcPositions[targetIdx] + SIMD3<Float>(0, 0.85, 0)
                        let toBot = botCenter - shieldCenter
                        let alongR = simd_dot(toBot, reflectedDir)
                        if alongR > 0.2 && alongR < 25.0 {
                            let closestPoint = shieldCenter + reflectedDir * alongR
                            if simd_distance(botCenter, closestPoint) < 0.65 {
                                // Dynamic Angle Hit! Reflected laser beam deals 50 HP damage to rival bot!
                                reflectedHitEnd = closestPoint
                                let damage: Float = 50.0
                                npcHealths[targetIdx] = max(0, npcHealths[targetIdx] - damage)
                                audio.playLaserReflectionSound()
                                onNPCHealthsUpdate?(npcHealths)

                                if npcHealths[targetIdx] <= 0 {
                                    botLaserActiveTimers[index] = 0
                                    botLaserCooldownTimers[index] = botCooldown
                                    audio.playWaterDisturbance(intensity: 1.0)
                                    onScoreUpdate?(500)
                                    handleNPCElimination(index: targetIdx)
                                }
                                break
                            }
                        }
                    }

                    endVec = SIMD4<Float>(reflectedHitEnd, 1.0)
                } else {
                    endVec = SIMD4<Float>(bEndActual, 1.0)
                    // Damage only applies when photon front reaches player AND bot is actually aligned AND NO ROCK OBSTRUCTS
                    if bProgress >= 1.0 && !hitRock {
                        let aimRay = simd_normalize(botAimTargets[index] - botHandOrigin)
                        let playerRay = simd_normalize(playerTarget - botHandOrigin)
                        let aimAlignment = simd_dot(aimRay, playerRay)
                        if aimAlignment > 0.94 && distance < 16.0 {
                            botImpactAudioCooldowns[index] -= rawDt
                            if botImpactAudioCooldowns[index] <= 0 {
                                botImpactAudioCooldowns[index] = 0.45
                                audio.playLaserPlayerHitSound()
                            }
                            accumulateDamage(12.0 * rawDt)
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

                if botLaserActiveTimers[index] == 0 {
                    botLaserCooldownTimers[index] = 3.5 + Float(index) * 0.8
                    botLaserPropagationDistances[index] = 0
                }
            }
        }
    }

    private func checkCombatHits() {
        guard heldTool == .laser, laserActiveRemaining > 0 else { return }

        let origin = lastCameraPosition
        let direction = lastCameraForward
        var closestIndex: Int?
        var closestDistance: Float = 35

        for index in npcPositions.indices where npcRespawnTimers[index] <= 0 {
            let center = npcPositions[index] + SIMD3<Float>(0, 0.85, 0)
            let alongRay = simd_dot(center - origin, direction)
            guard alongRay > 0, alongRay < closestDistance else { continue }
            let closestPoint = origin + direction * alongRay
            guard simd_distance(center, closestPoint) < 0.68 else { continue }
            closestIndex = index
            closestDistance = alongRay
        }

        if let closestIndex {
            let damage: Float = 35.0
            npcHealths[closestIndex] = max(0, npcHealths[closestIndex] - damage)
            audio.playLaserPlayerHitSound()
            onNPCHealthsUpdate?(npcHealths)

            if npcHealths[closestIndex] <= 0 {
                audio.playWaterDisturbance(intensity: 0.85)
                onScoreUpdate?(250)
                handleNPCElimination(index: closestIndex)
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
        let playerCenter = playerPosition + SIMD3<Float>(0, 0.85, 0)
        let toPlayer = playerCenter - mirrorPoint
        let reflectedDistance = simd_dot(toPlayer, reflected)
        guard reflectedDistance > 0, reflectedDistance < 22 else { return }
        let reflectedClosestPoint = mirrorPoint + reflected * reflectedDistance
        if simd_distance(playerCenter, reflectedClosestPoint) < 0.52 {
            laserActiveRemaining = 0
            laserCooldownRemaining = 6.0
        }

        // A reflected beam is still a gameplay beam: it can tag any rival
        // that lies on the outgoing segment after the mirror.
        var reflectedTarget: Int?
        var closestReflectedDistance: Float = 22
        for index in npcPositions.indices where npcRespawnTimers[index] <= 0 {
            let center = npcPositions[index] + SIMD3<Float>(0, 0.85, 0)
            let alongRay = simd_dot(center - mirrorPoint, reflected)
            guard alongRay > 0, alongRay < closestReflectedDistance else { continue }
            let closestPoint = mirrorPoint + reflected * alongRay
            guard simd_distance(center, closestPoint) < 0.48 else { continue }
            reflectedTarget = index
            closestReflectedDistance = alongRay
        }
        if let reflectedTarget {
            let damage: Float = 50.0
            npcHealths[reflectedTarget] = max(0, npcHealths[reflectedTarget] - damage)
            audio.playLanding(intensity: 0.85)
            onNPCHealthsUpdate?(npcHealths)

            if npcHealths[reflectedTarget] <= 0 {
                onScoreUpdate?(350)
                handleNPCElimination(index: reflectedTarget)
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
        // 🏊‍♂️ Trampolín Ladder & Platform
        if position.x >= 0.5 && position.x <= 2.2 && position.z >= -8.5 && position.z <= -4.2 {
            if position.z <= -6.8 {
                let t = max(0, min(1, (position.z - (-8.5)) / (-6.8 - (-8.5))))
                return t * 2.85
            } else if position.y >= 1.5 {
                return 2.85
            }
        }
        // 🌀 Tobogán Vertical Ladder & Platform Top
        if position.x >= -5.5 && position.x <= -2.1 && position.z >= -17.2 && position.z <= -13.5 {
            if position.y >= 3.5 {
                return 5.55
            }
        }
        guard insidePool else { return 0 }
        let floatCenter = SIMD2<Float>(floatPosition.x, floatPosition.z)
        let distance = simd_distance(SIMD2<Float>(position.x, position.z), floatCenter)
        let floatTop = floatPosition.y + 0.13
        if distance < 0.84 && position.y >= floatTop - 0.10 {
            return floatTop
        }
        return -0.66
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
            guard position.y < rock.center.y + rock.radii.y + 0.08 else { continue }

            let center = SIMD2<Float>(rock.center.x, rock.center.z)
            let expandedRadii = SIMD2<Float>(rock.radii.x + playerRadius, rock.radii.z + playerRadius)
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

    private func writeUniforms(texture: MTLTexture, dt: Float) {
        let currentlyInPool = isInsidePoolXZ(playerPosition) && playerPosition.y > -3.0
        let targetOffsetY: Float
        if isCoverActive {
            targetOffsetY = (cameraMode == .firstPerson ? 0.70 : 0.60)
        } else if currentlyInPool && cameraMode == .thirdPerson {
            targetOffsetY = max(1.35, 1.10 - playerPosition.y * 0.5)
        } else if playerPosition.y <= -3.0 {
            targetOffsetY = (cameraMode == .firstPerson ? 1.25 : 0.85)
        } else {
            targetOffsetY = (cameraMode == .firstPerson ? 1.56 : 1.10)
        }

        let rawTarget = playerPosition + SIMD3<Float>(0, targetOffsetY, 0)
        let follow = min(1, dt * (cameraMode == .firstPerson ? 22 : 14))
        smoothedCameraTarget += (rawTarget - smoothedCameraTarget) * follow

        let viewForward = SIMD3<Float>(-sin(cameraYaw), 0, -cos(cameraYaw))
        var rawRight = SIMD3<Float>(cos(cameraYaw), 0, -sin(cameraYaw))
        if simd_length_squared(rawRight) < 0.0001 { rawRight = SIMD3<Float>(1, 0, 0) }
        rawRight = simd_normalize(rawRight)

        let cameraPosition: SIMD3<Float>
        let cameraForward: SIMD3<Float>
        let fieldOfView: Float

        if cameraMode == .firstPerson {
            let pitchCosine = cos(firstPersonPitch)
            cameraForward = simd_normalize(SIMD3<Float>(
                viewForward.x * pitchCosine,
                sin(firstPersonPitch),
                viewForward.z * pitchCosine
            ))
            cameraPosition = smoothedCameraTarget + viewForward * 0.38
            fieldOfView = 72
        } else {
            // ☁️ 🐢 Super Mario 64 Lakitu Cloud Camera (Elevated trailing over right shoulder with organic cloud lag!)
            let isSubterraneanTarget = playerPosition.y <= -3.0
            let distance: Float = 4.6
            let shoulderOffset: Float = 0.45
            let heightOffset: Float = isSubterraneanTarget ? 1.15 : 1.75

            let horizontalDist = cos(orbitPitch) * distance
            let lakituTargetY = isSubterraneanTarget ?
                max(-7.8, min(-3.1, smoothedCameraTarget.y + heightOffset + sin(orbitPitch) * distance)) :
                max(0.42, smoothedCameraTarget.y + heightOffset + sin(orbitPitch) * distance)

            let idealLakituPos = SIMD3<Float>(
                smoothedCameraTarget.x + sin(cameraYaw) * horizontalDist,
                lakituTargetY,
                smoothedCameraTarget.z + cos(cameraYaw) * horizontalDist
            ) + rawRight * shoulderOffset

            // Organic Lakitu Cloud Spring-Damped Trailing ("Lakitu Lag")
            let lagFactor = exp(-dt * 6.5)
            if simd_distance_squared(lakituPosition, idealLakituPos) > 400.0 {
                lakituPosition = idealLakituPos
            } else {
                lakituPosition = mix(idealLakituPos, lakituPosition, t: lagFactor)
            }

            var clampedLakituPos = lakituPosition
            clampedLakituPos.x = max(-17.2, min(17.2, clampedLakituPos.x))
            clampedLakituPos.z = max(-17.2, min(17.2, clampedLakituPos.z))

            let aimTarget = smoothedCameraTarget + viewForward * 16.0 + SIMD3<Float>(0, 0.45, 0)
            cameraPosition = clampedLakituPos
            cameraForward = simd_normalize(aimTarget - cameraPosition)
            fieldOfView = 62
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
            let forwardOffset: Float = cameraPosition.y <= -3.0 ? 0.32 : 0.10
            toolOrigin = cameraPosition + right * 0.18 - up * 0.16 + cameraForward * forwardOffset
            toolDirection = cameraForward
        } else {
            let aimPoint = cameraPosition + cameraForward * 18.0
            toolOrigin = playerPosition + SIMD3<Float>(0, 1.22, 0) + right * 0.35 + viewForward * 0.30
            toolDirection = simd_normalize(aimPoint - toolOrigin)
        }

        let renderTool: GameHeldTool
        switch heldTool {
        case .laser: renderTool = laserActiveRemaining > 0 ? .laser : .none
        case .mirror: renderTool = mirrorActiveRemaining > 0 ? .mirror : .none
        default: renderTool = heldTool
        }

        if cameraPosition.y <= -3.0 && heldTool == .laser {
            let waterNormal = SIMD3<Float>(0, 1, 0)
            let eta: Float = 1.0 / 1.33 // Snell's Law underwater refraction index!
            let cosI = max(-1.0, min(1.0, -simd_dot(waterNormal, toolDirection)))
            let sinT2 = eta * eta * (1.0 - cosI * cosI)
            if sinT2 < 1.0 {
                let cosT = sqrt(1.0 - sinT2)
                toolDirection = simd_normalize(eta * toolDirection + (eta * cosI - cosT) * waterNormal)
            }
        }

        let isSubterraneanIlluminated = cameraPosition.y <= -3.0
        let activeLightPos = isSubterraneanIlluminated ? SIMD4<Float>(0.0, -5.2, 0.0, 1) : SIMD4<Float>(-7.55, 2.72, 6.65, 1)
        let activeLightColor = isSubterraneanIlluminated ? SIMD4<Float>(0.10, 0.95, 0.98, 48.0) : SIMD4<Float>(1.0, 0.66, 0.24, lightStates.effectiveIntensity(.post) * 46)

        var uniforms = RTUniforms(
            viewport: SIMD4<Float>(Float(texture.width), Float(texture.height), elapsedTime, rayBouncesEnabled ? 1 : 0),
            cameraPosition: SIMD4<Float>(cameraPosition, 1),
            cameraRight: SIMD4<Float>(right * aspect * imagePlaneHeight, 0),
            cameraUp: SIMD4<Float>(up * imagePlaneHeight, 0),
            cameraForward: SIMD4<Float>(cameraForward, 0),
            lightPosition: activeLightPos,
            lightColor: activeLightColor,
            waterSimulation: SIMD4<Float>(dt, elapsedTime, cameraMode == .firstPerson ? 1 : 0, 0),
            waterImpulse: pendingWaterImpulse,
            toolOrigin: SIMD4<Float>(toolOrigin, 1),
            toolDirection: SIMD4<Float>(toolDirection, 0),
            toolParameters: SIMD4<Float>(Float(renderTool.rawValue), laserPropagationDistance, isSlowMotionActive ? 1.0 : 0.0, isSplitScreenMode ? 1.0 : 0.0),
            lightStates: SIMD4<Float>(
                lightStates.effectiveIntensity(.post),
                lightStates.effectiveIntensity(.piscinaNeon),
                lightStates.effectiveIntensity(.sheeritNeon),
                lightStates.effectiveIntensity(.poolStrips)
            )
        )
        lastCameraPosition = cameraPosition
        lastCameraRight = right * aspect * imagePlaneHeight
        lastCameraUp = up * imagePlaneHeight
        lastCameraForward = cameraForward
        withUnsafeBytes(of: &uniforms) { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            uniformBuffer.contents().copyMemory(from: baseAddress, byteCount: bytes.count)
        }
    }

    private func writeInstanceDescriptors() {
        let isInsidePoolArea = playerPosition.x > -5.35 && playerPosition.x < 2.35 && playerPosition.z > -4.20 && playerPosition.z < 1.20
        let isSubmerged = isInsidePoolArea && playerPosition.y < 0.40
        let isPlayerDead = self.isPlayerDead
        let isMirrorActive = (heldTool == .mirror && mirrorActiveRemaining > 0)

        let pPitch: Float
        if isPlayerDead {
            // ☠️ MORIDO :v Death Animation: Fall flat face down on the floor (+90 deg pitch!)
            pPitch = 1.57
        } else if isSubmerged {
            // 🏊 Natural Swimming Pitch: Smoothly tilts with camera view (-25 to +25 deg)
            pPitch = max(-0.4, min(0.4, orbitPitch))
        } else if isCoverActive {
            // 🛡️ GTA Crouch Cover Pitch: Forward crouch tilt (+25 deg pitch!)
            pPitch = 0.44
        } else if isSlidingOnToboggan {
            // 🛷 Toboggan Sitting Pitch: Backwards sit tilt (-35 deg pitch!)
            pPitch = -0.62
        } else {
            // 🧍 Upright Walking Posture on Land (0 pitch!)
            pPitch = 0
        }

        let pPos: SIMD3<Float> = isSlidingOnToboggan ? playerPosition + SIMD3<Float>(0, -0.15, 0) : playerPosition
        let effYaw = playerYaw + shieldYawOffset
        let effPitch = pPitch + shieldPitchOffset
        let shieldPos: SIMD3<Float>
        if isMirrorActive {
            shieldPos = pPos + SIMD3<Float>(sin(effYaw) * 0.55, 0.20 + sin(effPitch) * 0.25, cos(effYaw) * 0.55)
        } else {
            shieldPos = SIMD3<Float>(0, -100, 0)
        }

        let playerRenderPos = (cameraMode == .firstPerson) ? SIMD3<Float>(0, -100, 0) : pPos

        let descriptors = [
            Self.makeInstanceDescriptor(translation: .zero, yaw: 0, pitch: 0, mask: 0x01, accelerationStructureIndex: 0),
            Self.makeInstanceDescriptor(translation: playerRenderPos, yaw: playerYaw, pitch: pPitch, mask: 0x02, accelerationStructureIndex: 1),
            Self.makeInstanceDescriptor(translation: .zero, yaw: 0, pitch: 0, mask: 0x04, accelerationStructureIndex: 2),
            Self.makeInstanceDescriptor(translation: floatPosition, yaw: floatYaw, pitch: 0, mask: 0x01, accelerationStructureIndex: 3),
            Self.makeInstanceDescriptor(translation: npcPositions[0], yaw: npcYaws[0], pitch: 0, mask: 0x01, accelerationStructureIndex: 4),
            Self.makeInstanceDescriptor(translation: npcPositions[1], yaw: npcYaws[1], pitch: 0, mask: 0x01, accelerationStructureIndex: 4),
            Self.makeInstanceDescriptor(translation: npcPositions[2], yaw: npcYaws[2], pitch: 0, mask: 0x01, accelerationStructureIndex: 4),
            Self.makeInstanceDescriptor(translation: npcPositions[3], yaw: npcYaws[3], pitch: 0, mask: 0x01, accelerationStructureIndex: 4),
            Self.makeInstanceDescriptor(translation: npcPositions[4], yaw: npcYaws[4], pitch: 0, mask: 0x01, accelerationStructureIndex: 4),
            Self.makeInstanceDescriptor(translation: shieldPos, yaw: effYaw, pitch: effPitch, mask: 0x01, accelerationStructureIndex: 5)
        ]
        descriptors.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            instanceBuffer.contents().copyMemory(from: baseAddress, byteCount: bytes.count)
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
        mask: UInt32,
        accelerationStructureIndex: UInt32
    ) -> MTLAccelerationStructureInstanceDescriptor {
        let cy = cos(yaw), sy = sin(yaw)
        let cp = cos(pitch), sp = sin(pitch)
        var descriptor = MTLAccelerationStructureInstanceDescriptor()
        descriptor.transformationMatrix.columns.0 = MTLPackedFloat3Make(cy, sy * sp, -sy * cp)
        descriptor.transformationMatrix.columns.1 = MTLPackedFloat3Make(0, cp, sp)
        descriptor.transformationMatrix.columns.2 = MTLPackedFloat3Make(sy, -cy * sp, cy * cp)
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

    private static func makePlayerMesh() -> RTMeshBuilder {
        var builder = RTMeshBuilder()
        builder.addCharacter(origin: .zero, color: SIMD3<Float>(0.08, 0.82, 0.68), holdsTool: true)
        return builder
    }

    private static func makeNPCMesh() -> RTMeshBuilder {
        var builder = RTMeshBuilder()
        builder.addCharacter(origin: .zero, color: SIMD3<Float>(0.92, 0.18, 0.34), holdsTool: true)
        return builder
    }

    private static func makeMirrorShieldMesh() -> RTMeshBuilder {
        var builder = RTMeshBuilder()
        let mirrorFrame = RTMaterial(color: SIMD3<Float>(0.02, 0.72, 0.95), roughness: 0.08, emission: SIMD3<Float>(0.05, 0.40, 0.65), reflectivity: 0.88, kind: 1.0)
        let mirrorGlassFront = RTMaterial(color: SIMD3<Float>(0.92, 0.95, 0.98), roughness: 0.0, emission: SIMD3<Float>(0, 0, 0), reflectivity: 0.98, kind: 1.0)
        
        // One-Way Visor Backing (-Z facing player in 1st person): See-through cyan tinted glass visor
        let oneWayVisorBack = RTMaterial(color: SIMD3<Float>(0.05, 0.45, 0.65), roughness: 0.05, emission: SIMD3<Float>(0.02, 0.15, 0.25), reflectivity: 0.08, kind: 0.0)

        // Compact tactical shield size: 0.48m wide x 0.58m tall
        // Outward (+Z): 100% Reflective Mirror Glass
        builder.addBox(center: SIMD3<Float>(0, 1.05, 0.012), size: SIMD3<Float>(0.52, 0.62, 0.015), material: mirrorFrame)
        builder.addBox(center: SIMD3<Float>(0, 1.05, 0.018), size: SIMD3<Float>(0.46, 0.56, 0.010), material: mirrorGlassFront)
        // Inward (-Z facing player in 1st person): One-way see-through cyan glass visor
        builder.addBox(center: SIMD3<Float>(0, 1.05, -0.012), size: SIMD3<Float>(0.46, 0.56, 0.010), material: oneWayVisorBack)
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
            color: SIMD3<Float>(0.008, 0.025, 0.030),
            roughness: 0.028,
            reflectivity: 0.055,
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
                    SIMD3<Float>(x0, -0.07, z1),
                    SIMD3<Float>(x1, -0.07, z1),
                    SIMD3<Float>(x1, -0.07, z0),
                    SIMD3<Float>(x0, -0.07, z0),
                    material: water
                )
            }
        }
        return builder
    }

    private static func makeStaticScene() -> RTMeshBuilder {
        var builder = RTMeshBuilder()
        let deck = RTMaterial(color: SIMD3<Float>(0.13, 0.16, 0.17), roughness: 0.76, reflectivity: 0.04)
        let wall = RTMaterial(color: SIMD3<Float>(0.035, 0.045, 0.065), roughness: 0.9)
        let poolTile = RTMaterial(color: SIMD3<Float>(0.16, 0.23, 0.22), roughness: 0.42, reflectivity: 0.05)
        let coping = RTMaterial(color: SIMD3<Float>(0.28, 0.30, 0.30), roughness: 0.16, reflectivity: 0.42, kind: 3)
        let mirror = RTMaterial(color: SIMD3<Float>(0.92, 0.95, 0.98), roughness: 0.01, reflectivity: 0.97, kind: 1)
        let shallowWater = RTMaterial(
            color: SIMD3<Float>(0.012, 0.034, 0.040),
            roughness: 0.018,
            reflectivity: 0.045,
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



        builder.addBox(center: SIMD3<Float>(0, -0.12, 0), size: SIMD3<Float>(36.0, 0.24, 36.0), material: deck)
        builder.addBox(center: SIMD3<Float>(0, 3.5, -17.8), size: SIMD3<Float>(36, 7, 0.4), material: wall)
        builder.addBox(center: SIMD3<Float>(0, 3.5, 17.8), size: SIMD3<Float>(36, 7, 0.4), material: wall)
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

        // 🌊 💎 Subterranean Underwater World Props (Secret Realm Props & Sunken Treasure!)
        let bioCrystal = RTMaterial(color: SIMD3<Float>(0.10, 0.95, 0.85), roughness: 0.10, emission: SIMD3<Float>(0.20, 2.8, 3.8), reflectivity: 0.60)
        let sunkenObelisk = RTMaterial(color: SIMD3<Float>(0.12, 0.18, 0.22), roughness: 0.65, reflectivity: 0.12)
        let treasureGold = RTMaterial(color: SIMD3<Float>(0.98, 0.82, 0.12), roughness: 0.15, emission: SIMD3<Float>(0.45, 0.35, 0.05), reflectivity: 0.50)
        let exitPortal = RTMaterial(color: SIMD3<Float>(0.05, 0.55, 0.98), roughness: 0.05, emission: SIMD3<Float>(0.30, 2.5, 6.0), reflectivity: 0.85, kind: 5)

        // Sunken Ancient Obelisks & Pillars
        builder.addBox(center: SIMD3<Float>(-4.2, -6.0, -3.8), size: SIMD3<Float>(0.85, 5.0, 0.85), material: sunkenObelisk)
        builder.addBox(center: SIMD3<Float>(3.8, -6.0, 2.8), size: SIMD3<Float>(0.85, 5.0, 0.85), material: sunkenObelisk)
        builder.addBox(center: SIMD3<Float>(-3.2, -6.5, 3.2), size: SIMD3<Float>(0.75, 4.0, 0.75), material: sunkenObelisk)

        // Glowing Bioluminescent Crystals & Subterranean Illuminating Lamps
        let subLampEmitter = RTMaterial(color: SIMD3<Float>(0.10, 0.90, 0.98), roughness: 0.05, emission: SIMD3<Float>(0.85, 3.8, 5.5), reflectivity: 0.75)
        builder.addSphere(center: SIMD3<Float>(-8.0, -5.5, -8.0), radii: SIMD3<Float>(repeating: 0.65), material: subLampEmitter, segments: 10, rings: 6)
        builder.addSphere(center: SIMD3<Float>(8.0, -5.5, -8.0), radii: SIMD3<Float>(repeating: 0.65), material: subLampEmitter, segments: 10, rings: 6)
        builder.addSphere(center: SIMD3<Float>(-8.0, -5.5, 8.0), radii: SIMD3<Float>(repeating: 0.65), material: subLampEmitter, segments: 10, rings: 6)
        builder.addSphere(center: SIMD3<Float>(8.0, -5.5, 8.0), radii: SIMD3<Float>(repeating: 0.65), material: subLampEmitter, segments: 10, rings: 6)

        builder.addSphere(center: SIMD3<Float>(-3.8, -8.1, -3.2), radii: SIMD3<Float>(repeating: 0.45), material: bioCrystal, segments: 8, rings: 5)
        builder.addSphere(center: SIMD3<Float>(3.5, -8.1, 2.2), radii: SIMD3<Float>(repeating: 0.45), material: bioCrystal, segments: 8, rings: 5)
        builder.addSphere(center: SIMD3<Float>(1.8, -8.1, -4.2), radii: SIMD3<Float>(repeating: 0.40), material: bioCrystal, segments: 8, rings: 5)

        // Sunken Treasure Chest
        builder.addBox(center: SIMD3<Float>(2.8, -8.2, -1.8), size: SIMD3<Float>(1.2, 0.75, 0.85), material: treasureGold)

        // 🌀 Central Glowing Blue Teleport Exit Portal Ring (Salida del Easter Egg)
        builder.addTorus(center: SIMD3<Float>(0, -8.35, 0), majorRadius: 1.45, minorRadius: 0.18, material: exitPortal, majorSegments: 16, minorSegments: 8)

        builder.addBox(center: SIMD3<Float>(-1.5, -0.72, -1.5), size: SIMD3<Float>(7.8, 0.12, 5.4), material: poolTile)
        builder.addBox(center: SIMD3<Float>(-1.5, -0.34, -4.14), size: SIMD3<Float>(7.8, 0.68, 0.12), material: poolTile)
        builder.addBox(center: SIMD3<Float>(-1.5, -0.34, 1.14), size: SIMD3<Float>(7.8, 0.68, 0.12), material: poolTile)
        builder.addBox(center: SIMD3<Float>(-5.34, -0.34, -1.5), size: SIMD3<Float>(0.12, 0.68, 5.4), material: poolTile)
        builder.addBox(center: SIMD3<Float>(2.34, -0.34, -1.5), size: SIMD3<Float>(0.12, 0.68, 5.4), material: poolTile)

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
        builder.addNeonSheeritSign(origin: SIMD2<Float>(3.05, 3.28), z: 17.58)

        let lampPosition = SIMD3<Float>(-7.55, 0, 12.65)
        builder.addBox(center: lampPosition + SIMD3<Float>(0, 1.42, 0), size: SIMD3<Float>(0.13, 2.75, 0.13), material: metal)
        builder.addBox(center: lampPosition + SIMD3<Float>(0, 2.72, 0), size: SIMD3<Float>(0.32, 0.52, 0.32), material: lampEmitter)
        builder.addBox(center: lampPosition + SIMD3<Float>(0, 2.99, 0), size: SIMD3<Float>(0.54, 0.08, 0.54), material: metal)
        builder.addBox(center: lampPosition + SIMD3<Float>(0, 2.45, 0), size: SIMD3<Float>(0.46, 0.08, 0.46), material: metal)
        builder.addBox(center: lampPosition + SIMD3<Float>(0, 0.08, 0), size: SIMD3<Float>(0.62, 0.16, 0.62), material: metal)

        builder.addPuddle(center: SIMD2<Float>(4.2, -1.1), scale: SIMD2<Float>(0.9, 0.52), rotation: 0.35, material: shallowWater)
        builder.addPuddle(center: SIMD2<Float>(5.8, 2.2), scale: SIMD2<Float>(1.25, 0.62), rotation: -0.5, material: shallowWater)
        builder.addPuddle(center: SIMD2<Float>(-7.0, 4.6), scale: SIMD2<Float>(1.1, 0.7), rotation: 0.8, material: shallowWater)

        for (index, rock) in rtRiverRocks.enumerated() {
            let stone = RTMaterial(color: rock.color, roughness: 0.32, reflectivity: 0.18, kind: 3)
            builder.addRiverRock(
                center: rock.center,
                radii: rock.radii,
                seed: Float(index) + 0.7,
                material: stone
            )
        }

        builder.addBox(center: SIMD3<Float>(2.20, 0.54, -2.25), size: SIMD3<Float>(0.10, 1.35, 0.10), material: metal)
        builder.addBox(center: SIMD3<Float>(2.20, 0.54, -1.55), size: SIMD3<Float>(0.10, 1.35, 0.10), material: metal)
        for level in 0..<3 {
            builder.addBox(
                center: SIMD3<Float>(2.20, 0.20 + Float(level) * 0.28, -1.90),
                size: SIMD3<Float>(0.10, 0.08, 0.70),
                material: metal
            )
        }

        let wood = RTMaterial(color: SIMD3<Float>(0.30, 0.18, 0.10), roughness: 0.52, reflectivity: 0.08)
        builder.addBox(center: SIMD3<Float>(7.3, 0.56, 4.8), size: SIMD3<Float>(3.2, 0.18, 0.72), material: wood)
        builder.addBox(center: SIMD3<Float>(6.1, 0.28, 4.8), size: SIMD3<Float>(0.18, 0.55, 0.58), material: wood)
        builder.addBox(center: SIMD3<Float>(8.5, 0.28, 4.8), size: SIMD3<Float>(0.18, 0.55, 0.58), material: wood)
        builder.addBox(center: SIMD3<Float>(6.8, 0.70, 4.8), size: SIMD3<Float>(0.72, 0.10, 0.52), material: RTMaterial(color: SIMD3<Float>(0.10, 0.64, 0.72), roughness: 0.46))
        builder.addBox(center: SIMD3<Float>(7.65, 0.70, 4.8), size: SIMD3<Float>(0.72, 0.10, 0.52), material: RTMaterial(color: SIMD3<Float>(0.90, 0.24, 0.34), roughness: 0.46))

        return builder
    }
}
