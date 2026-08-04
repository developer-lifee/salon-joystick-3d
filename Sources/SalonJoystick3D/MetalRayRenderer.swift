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
    RTRiverRock(center: SIMD3<Float>(5.15, 0.15, -4.45), radii: SIMD3<Float>(0.48, 0.15, 0.58), color: SIMD3<Float>(0.19, 0.18, 0.17))
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

        // Torso & Armor Chest Plate
        addSphere(center: origin + SIMD3<Float>(0, 0.86, 0), radii: SIMD3<Float>(0.34, 0.50, 0.27), material: suit)
        addBox(center: origin + SIMD3<Float>(0, 0.92, 0.16), size: SIMD3<Float>(0.44, 0.42, 0.12), material: armor)
        addSphere(center: origin + SIMD3<Float>(0, 0.95, 0.23), radii: SIMD3<Float>(repeating: 0.08), material: coreEmissive)

        // Retopologized Helmet & Curved Visor
        addSphere(center: origin + SIMD3<Float>(0, 1.55, 0), radii: SIMD3<Float>(repeating: 0.32), material: suit)
        addBox(center: origin + SIMD3<Float>(0, 1.58, 0.22), size: SIMD3<Float>(0.38, 0.18, 0.14), material: visor)

        // Shoulder Pads & Joint Guards
        addBox(center: origin + SIMD3<Float>(-0.44, 1.12, 0), size: SIMD3<Float>(0.18, 0.16, 0.22), material: armor)
        addBox(center: origin + SIMD3<Float>( 0.44, 1.12, 0), size: SIMD3<Float>(0.18, 0.16, 0.22), material: armor)
        addBox(center: origin + SIMD3<Float>(-0.16, 0.28, 0.12), size: SIMD3<Float>(0.16, 0.14, 0.08), material: armor)
        addBox(center: origin + SIMD3<Float>( 0.16, 0.28, 0.12), size: SIMD3<Float>(0.16, 0.14, 0.08), material: armor)

        // Limbs & Tactical Boots
        addBox(center: origin + SIMD3<Float>(-0.16, 0.28, 0), size: SIMD3<Float>(0.14, 0.56, 0.17), material: suit)
        addBox(center: origin + SIMD3<Float>( 0.16, 0.28, 0), size: SIMD3<Float>(0.14, 0.56, 0.17), material: suit)
        addBox(center: origin + SIMD3<Float>(-0.42, 0.88, 0), size: SIMD3<Float>(0.14, 0.55, 0.16), material: suit)
        addBox(center: origin + SIMD3<Float>( 0.42, 0.88, 0), size: SIMD3<Float>(0.14, 0.55, 0.16), material: suit)
        addBox(center: origin + SIMD3<Float>(-0.16, 0.04, 0.06), size: SIMD3<Float>(0.16, 0.10, 0.26), material: armor)
        addBox(center: origin + SIMD3<Float>( 0.16, 0.04, 0.06), size: SIMD3<Float>(0.16, 0.10, 0.26), material: armor)

        if eyes {
            addSphere(center: origin + SIMD3<Float>(-0.11, 1.60, 0.29), radii: SIMD3<Float>(repeating: 0.04), material: dark, segments: 7, rings: 4)
            addSphere(center: origin + SIMD3<Float>( 0.11, 1.60, 0.29), radii: SIMD3<Float>(repeating: 0.04), material: dark, segments: 7, rings: 4)
        }
        if holdsTool {
            let tool = RTMaterial(color: SIMD3<Float>(0.055, 0.060, 0.065), roughness: 0.34, reflectivity: 0.10)
            addBox(
                center: origin + SIMD3<Float>(0.47, 0.72, 0.22),
                size: SIMD3<Float>(0.14, 0.16, 0.42),
                material: tool
            )
        }
    }
}

private struct RTMeshResources {
    let vertexBuffer: MTLBuffer
    let primitiveBuffer: MTLBuffer
    let accelerationStructure: MTLAccelerationStructure
    let descriptor: MTLPrimitiveAccelerationStructureDescriptor
    let scratchBuffer: MTLBuffer
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
    private let instanceDescriptor: MTLInstanceAccelerationStructureDescriptor
    private let instanceAccelerationStructure: MTLAccelerationStructure
    private let instanceScratchBuffer: MTLBuffer
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
    private var npcPositions = [
        SIMD3<Float>(-7.2, 0, 3.7),
        SIMD3<Float>(6.7, 0, -6.0)
    ]
    private var npcYaws = [Float.pi * 0.25, Float.pi * 1.7]
    private var npcRespawnTimers = [Float](repeating: 0, count: 2)
    private var botLaserActiveTimers = [Float](repeating: 0, count: 2)
    private var botLaserCooldownTimers = [Float](repeating: 5.0, count: 2)
    private var botImpactAudioCooldowns = [Float](repeating: 0, count: 2)
    private let npcSpawnPositions = [
        SIMD3<Float>(-7.2, 0, 3.7),
        SIMD3<Float>(6.7, 0, -6.0)
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

        let descriptor = MTLInstanceAccelerationStructureDescriptor()
        descriptor.instancedAccelerationStructures = [
            staticMesh.accelerationStructure,
            playerMesh.accelerationStructure,
            waterMesh.accelerationStructure,
            floatMesh.accelerationStructure,
            npcMesh.accelerationStructure,
            mirrorShieldMesh.accelerationStructure
        ]
        descriptor.instanceCount = 10
        descriptor.instanceDescriptorBuffer = instanceBuffer
        self.instanceDescriptor = descriptor

        let sizes = device.accelerationStructureSizes(descriptor: descriptor)
        guard let instanceAccelerationStructure = device.makeAccelerationStructure(size: sizes.accelerationStructureSize),
              let scratch = device.makeBuffer(
                length: max(256, sizes.buildScratchBufferSize),
                options: .storageModePrivate
              ) else {
            throw MetalRayRendererError.resourceCreationFailed
        }
        self.instanceAccelerationStructure = instanceAccelerationStructure
        self.instanceScratchBuffer = scratch

        super.init()

        writeInstanceDescriptors()
        try buildInitialInstanceAccelerationStructure()
    }

    func setInput(
        joystick: CGVector,
        cameraMode: GameCameraMode,
        rayBouncesEnabled: Bool,
        heldTool: GameHeldTool,
        lightStates: GameLightStates,
        jumpRequestID: Int
    ) {
        self.joystick = joystick
        self.cameraMode = cameraMode
        self.rayBouncesEnabled = rayBouncesEnabled
        self.heldTool = heldTool
        self.lightStates = lightStates
        if handledJumpRequestID != jumpRequestID {
            handledJumpRequestID = jumpRequestID
            jumpQueued = true
        }
    }

    func rotateCamera(deltaX: Float, deltaY: Float) {
        cameraYaw += deltaX * 0.0075
        if cameraMode == .firstPerson {
            firstPersonPitch = max(-0.82, min(0.82, firstPersonPitch - deltaY * 0.0045))
        } else {
            orbitPitch = max(-0.34, min(1.02, orbitPitch - deltaY * 0.0045))
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
        let dt = Float(min(1.0 / 30.0, max(0, now - lastFrameTime)))
        lastFrameTime = now
        elapsedTime += dt
        updateSimulation(dt: dt)
        writeInstanceDescriptors()
        writeUniforms(texture: drawable.texture, dt: dt)

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

        if let accelerationEncoder = commandBuffer.makeAccelerationStructureCommandEncoder() {
            accelerationEncoder.refit(
                sourceAccelerationStructure: waterMesh.accelerationStructure,
                descriptor: waterMesh.descriptor,
                destinationAccelerationStructure: waterMesh.accelerationStructure,
                scratchBuffer: waterMesh.scratchBuffer,
                scratchBufferOffset: 0
            )
            accelerationEncoder.build(
                accelerationStructure: instanceAccelerationStructure,
                descriptor: instanceDescriptor,
                scratchBuffer: instanceScratchBuffer,
                scratchBufferOffset: 0
            )
            accelerationEncoder.endEncoding()
        }

        if let laserEncoder = commandBuffer.makeComputeCommandEncoder() {
            laserEncoder.setComputePipelineState(laserPipeline)
            laserEncoder.setBuffer(uniformBuffer, offset: 0, index: 0)
            laserEncoder.setBuffer(instanceBuffer, offset: 0, index: 1)
            laserEncoder.setAccelerationStructure(instanceAccelerationStructure, bufferIndex: 2)
            laserEncoder.setBuffer(laserResultBuffer, offset: 0, index: 3)
            laserEncoder.setTexture(renderedWaterTexture, index: 0)
            laserEncoder.useResource(staticMesh.accelerationStructure, usage: .read)
            laserEncoder.useResource(waterMesh.accelerationStructure, usage: .read)
            laserEncoder.useResource(floatMesh.accelerationStructure, usage: .read)
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
            encoder.setAccelerationStructure(instanceAccelerationStructure, bufferIndex: 2)
            encoder.setBuffer(laserResultBuffer, offset: 0, index: 3)
            encoder.setTexture(drawable.texture, index: 0)
            encoder.setTexture(renderedWaterTexture, index: 1)
            encoder.useResource(staticMesh.accelerationStructure, usage: .read)
            encoder.useResource(playerMesh.accelerationStructure, usage: .read)
            encoder.useResource(waterMesh.accelerationStructure, usage: .read)
            encoder.useResource(floatMesh.accelerationStructure, usage: .read)
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

    private func updateSimulation(dt: Float) {
        updateToolTimers(dt: dt)
        updateNPCSimulation(dt: dt)
        checkCombatHits()
        let wasRidingFloat = isStandingOnFloat(playerPosition)
        let floatDisplacement = updateFloatSimulation(dt: dt)
        if wasRidingFloat {
            playerPosition += floatDisplacement
        }
        let previousWaterImmersion = waterImmersion(
            at: playerPosition,
            insidePool: isInsidePoolXZ(playerPosition)
        )

        let inputX = Float(joystick.dx)
        let inputForward = -Float(joystick.dy)
        let magnitude = min(1, hypot(inputX, inputForward))
        let cameraForward = SIMD2<Float>(-sin(cameraYaw), -cos(cameraYaw))
        let cameraRight = SIMD2<Float>(cos(cameraYaw), -sin(cameraYaw))
        var desiredDirection = cameraRight * inputX + cameraForward * inputForward
        if simd_length_squared(desiredDirection) > 0.0001 {
            desiredDirection = simd_normalize(desiredDirection)
        }

        let currentlyInPool = isInsidePoolXZ(playerPosition)
        let currentGroundHeight = groundHeight(at: playerPosition, insidePool: currentlyInPool)
        let currentlyOnFloat = currentlyInPool && isStandingOnFloat(playerPosition)
        let movementSpeed: Float = currentlyInPool && !currentlyOnFloat ? 1.85 : 3.6
        let targetVelocity = desiredDirection * (magnitude > 0.08 ? movementSpeed * magnitude : 0)
        let response = 1 - exp(-dt * (magnitude > 0.08 ? 13 : 18))
        horizontalVelocity += (targetVelocity - horizontalVelocity) * response
        if simd_length(horizontalVelocity) < 0.015 && magnitude <= 0.08 {
            horizontalVelocity = .zero
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
        proposed.x = max(-9.05, min(9.05, proposed.x))
        proposed.z = max(-9.05, min(9.05, proposed.z))
        resolveFloatCollision(position: &proposed)
        resolveRockCollisions(position: &proposed)
        let willBeInPool = isInsidePoolXZ(proposed)
        let nextGroundHeight = groundHeight(at: proposed, insidePool: willBeInPool)
        let willBeOnFloat = willBeInPool && nextGroundHeight > -0.1
        let wasGrounded = playerPosition.y <= currentGroundHeight + 0.015 && abs(verticalVelocity) < 0.1

        if jumpQueued {
            jumpQueued = false
            if playerPosition.y <= currentGroundHeight + 0.015 {
                verticalVelocity = currentlyInPool ? 3.1 : 5.2
            }
        }

        verticalVelocity -= (willBeInPool && !willBeOnFloat ? 5.4 : 9.8) * dt
        var landingSpeed: Float = 0
        proposed.y += verticalVelocity * dt
        if currentlyInPool && !willBeInPool && proposed.y < 0 {
            proposed.y = min(0, playerPosition.y + dt * 2.8)
            verticalVelocity = 0
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
        let playerWaterMovement = min(1, speed / 1.85) * sqrt(currentWaterImmersion)
        if playerWaterMovement > 0.08 {
            playerWaterWakeCountdown -= dt
            if playerWaterWakeCountdown <= 0 {
                pendingWaterImpulse = SIMD4<Float>(
                    playerPosition.x,
                    playerPosition.z,
                    -0.18 - playerWaterMovement * 0.24,
                    1
                )
                playerWaterWakeCountdown = 0.16
            }
        } else {
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
                audio.playLaserIgnition()
            } else if heldTool == .mirror && mirrorCooldownRemaining <= 0 {
                mirrorActiveRemaining = 3.0
            }
        }

        if heldTool == .laser && laserActiveRemaining > 0 {
            laserActiveRemaining = max(0, laserActiveRemaining - dt)
            if laserActiveRemaining == 0 { laserCooldownRemaining = 6.0 }

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
                        npcRespawnTimers[i] = 5.0
                        npcPositions[i].y = -10
                        audio.playWaterDisturbance(intensity: 0.90)
                        onScoreUpdate?(400)
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

    private func updateNPCSimulation(dt: Float) {
        let results = laserResultBuffer.contents().assumingMemoryBound(to: RTLaserResult.self)

        for index in npcPositions.indices {
            if index == 0 {
                results.pointee.bot0Start = .zero
                results.pointee.bot0End = .zero
            } else {
                results.pointee.bot1Start = .zero
                results.pointee.bot1End = .zero
            }

            if npcRespawnTimers[index] > 0 {
                npcRespawnTimers[index] = max(0, npcRespawnTimers[index] - dt)
                npcPositions[index].y = -10
                if npcRespawnTimers[index] == 0 {
                    npcPositions[index] = npcSpawnPositions[index]
                    botLaserCooldownTimers[index] = 2.0 + Float(index) * 1.2
                    botLaserActiveTimers[index] = 0
                }
                continue
            }

            let offset = SIMD2<Float>(
                playerPosition.x - npcPositions[index].x,
                playerPosition.z - npcPositions[index].z
            )
            let distance = simd_length(offset)
            let direction = distance > 0.001 ? offset / distance : SIMD2<Float>(0, 1)

            // Aggressive tracking & speed
            let speed: Float = 2.4 + Float(index) * 0.45
            if distance > 0.65 {
                npcPositions[index].x += direction.x * speed * dt
                npcPositions[index].z += direction.y * speed * dt
                npcPositions[index].x = max(-9.0, min(9.0, npcPositions[index].x))
                npcPositions[index].z = max(-9.0, min(9.0, npcPositions[index].z))
            }
            npcYaws[index] = atan2(direction.x, direction.y)

            // Bot Laser Combat AI with symmetric active/cooldown windows & 3D visual beams
            if botLaserCooldownTimers[index] > 0 {
                botLaserCooldownTimers[index] = max(0, botLaserCooldownTimers[index] - dt)
                if botLaserCooldownTimers[index] == 0 && distance < 12.0 {
                    botLaserActiveTimers[index] = 2.2
                }
            } else if botLaserActiveTimers[index] > 0 {
                botLaserActiveTimers[index] = max(0, botLaserActiveTimers[index] - dt)

                let botHandOrigin = npcPositions[index] + SIMD3<Float>(0.42, 0.88, 0.20)
                let playerTarget = playerPosition + SIMD3<Float>(0, 1.10, 0)
                let playerIsUsingMirror = (heldTool == .mirror && mirrorActiveRemaining > 0)
                let playerFacing = SIMD3<Float>(-sin(playerYaw), 0, -cos(playerYaw))
                let incomingLaserDir = distance > 0.001 ? -direction : SIMD2<Float>(0, -1)
                let isFacingLaser = (playerFacing.x * incomingLaserDir.x + playerFacing.z * incomingLaserDir.y) > 0.25

                let startVec = SIMD4<Float>(botHandOrigin, 1.0)
                let endVec: SIMD4<Float>

                if playerIsUsingMirror && isFacingLaser {
                    // Reflected beam sends laser back into the attacking bot!
                    endVec = SIMD4<Float>(botHandOrigin, 1.0)
                    npcRespawnTimers[index] = 5.0
                    npcPositions[index].y = -10
                    botLaserActiveTimers[index] = 0
                    botLaserCooldownTimers[index] = 5.0
                    audio.playWaterDisturbance(intensity: 0.95)
                    onScoreUpdate?(500)
                } else {
                    endVec = SIMD4<Float>(playerTarget, 1.0)
                    botImpactAudioCooldowns[index] -= dt
                    if botImpactAudioCooldowns[index] <= 0 {
                        botImpactAudioCooldowns[index] = 0.45
                        audio.playLanding(intensity: 0.55)
                    }
                    onDamageTaken?(12.0 * dt)
                }

                if index == 0 {
                    results.pointee.bot0Start = startVec
                    results.pointee.bot0End = endVec
                } else {
                    results.pointee.bot1Start = startVec
                    results.pointee.bot1End = endVec
                }

                if botLaserActiveTimers[index] == 0 {
                    botLaserCooldownTimers[index] = 3.5 + Float(index) * 0.8
                }
            }
        }
    }

    private func checkCombatHits() {
        guard heldTool == .laser, laserActiveRemaining > 0 else { return }

        let origin = playerPosition + SIMD3<Float>(0, 1.18, 0) + lastCameraRight * 0.30
        let aimPoint = lastCameraPosition + lastCameraForward * 18
        let direction = simd_normalize(aimPoint - origin)
        var closestIndex: Int?
        var closestDistance: Float = 30

        for index in npcPositions.indices where npcRespawnTimers[index] <= 0 {
            let center = npcPositions[index] + SIMD3<Float>(0, 0.85, 0)
            let alongRay = simd_dot(center - origin, direction)
            guard alongRay > 0, alongRay < closestDistance else { continue }
            let closestPoint = origin + direction * alongRay
            guard simd_distance(center, closestPoint) < 0.48 else { continue }
            closestIndex = index
            closestDistance = alongRay
        }

        if let closestIndex {
            npcRespawnTimers[closestIndex] = 2.0
            npcPositions[closestIndex].y = -10
            audio.playWaterDisturbance(intensity: 0.85)
            onScoreUpdate?(250)
        }

        // The rear wall mirror can send the player's own beam back at them.
        let mirrorZ: Float = -9.43
        guard direction.z < -0.001 else { return }
        let mirrorDistance = (mirrorZ - origin.z) / direction.z
        guard mirrorDistance > 0, mirrorDistance < 30 else { return }
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
            npcRespawnTimers[reflectedTarget] = 1.6
            npcPositions[reflectedTarget].y = -10
        }
    }

    private func isInsidePoolXZ(_ position: SIMD3<Float>) -> Bool {
        position.x > -5.28 && position.x < 2.28 &&
        position.z > -4.08 && position.z < 1.08
    }

    private func waterImmersion(at position: SIMD3<Float>, insidePool: Bool) -> Float {
        guard insidePool else { return 0 }
        let waterSurface: Float = -0.07
        return min(1, max(0, (waterSurface + 0.015 - position.y) / 0.16))
    }

    private func groundHeight(at position: SIMD3<Float>, insidePool: Bool) -> Float {
        // Tobogán Platform Top (North side deck)
        if position.x >= -2.8 && position.x <= -0.2 && position.z >= -8.3 && position.z <= -6.1 {
            return 2.50
        }
        // Tobogán Access Stairs (From Z=-9.0 up to Z=-8.3)
        if position.x >= -2.8 && position.x <= -0.2 && position.z >= -9.0 && position.z < -8.3 {
            let progress = (-8.3 - position.z) / 0.7
            return (1.0 - progress) * 2.50
        }
        // Tobogán Water Slide Ramp (Slanted directly SOUTH into pool water from Z=-6.1 down to Z=-2.0!)
        if position.x >= -2.8 && position.x <= -0.2 && position.z > -6.1 && position.z <= -2.0 {
            let progress = (position.z - (-6.1)) / 4.1
            return (1.0 - progress) * 2.50
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
        let rawTarget = playerPosition + SIMD3<Float>(0, cameraMode == .firstPerson ? 1.56 : 1.10, 0)
        let follow = min(1, dt * (cameraMode == .firstPerson ? 22 : 14))
        smoothedCameraTarget += (rawTarget - smoothedCameraTarget) * follow

        let viewForward = SIMD3<Float>(-sin(cameraYaw), 0, -cos(cameraYaw))
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
            let distance: Float = 5.6
            let horizontalDistance = cos(orbitPitch) * distance
            var desired = SIMD3<Float>(
                smoothedCameraTarget.x + sin(cameraYaw) * horizontalDistance,
                max(0.38, smoothedCameraTarget.y + sin(orbitPitch) * distance),
                smoothedCameraTarget.z + cos(cameraYaw) * horizontalDistance
            )
            desired.x = max(-9.18, min(9.18, desired.x))
            desired.z = max(-9.18, min(9.18, desired.z))
            cameraPosition = desired
            cameraForward = simd_normalize(smoothedCameraTarget - cameraPosition)
            fieldOfView = 58
        }

        var right = simd_cross(cameraForward, SIMD3<Float>(0, 1, 0))
        if simd_length_squared(right) < 0.0001 { right = SIMD3<Float>(1, 0, 0) }
        right = simd_normalize(right)
        let up = simd_normalize(simd_cross(right, cameraForward))
        let aspect = Float(texture.width) / max(1, Float(texture.height))
        let imagePlaneHeight = tan(fieldOfView * .pi / 360)
        let toolOrigin: SIMD3<Float>
        let toolDirection: SIMD3<Float>
        if cameraMode == .firstPerson {
            toolOrigin = cameraPosition + right * 0.18 - up * 0.16 + cameraForward * 0.10
            let aimPoint = cameraPosition + cameraForward * 18
            toolDirection = simd_normalize(aimPoint - toolOrigin)
        } else {
            toolOrigin = playerPosition + SIMD3<Float>(0, 1.25, 0) + right * 0.32 + cameraForward * 0.25
            toolDirection = cameraForward
        }

        let renderTool: GameHeldTool
        switch heldTool {
        case .laser: renderTool = laserActiveRemaining > 0 ? .laser : .none
        case .mirror: renderTool = mirrorActiveRemaining > 0 ? .mirror : .none
        default: renderTool = heldTool
        }

        var uniforms = RTUniforms(
            viewport: SIMD4<Float>(Float(texture.width), Float(texture.height), elapsedTime, rayBouncesEnabled ? 1 : 0),
            cameraPosition: SIMD4<Float>(cameraPosition, 1),
            cameraRight: SIMD4<Float>(right * aspect * imagePlaneHeight, 0),
            cameraUp: SIMD4<Float>(up * imagePlaneHeight, 0),
            cameraForward: SIMD4<Float>(cameraForward, 0),
            lightPosition: SIMD4<Float>(-7.55, 2.72, 6.65, 1),
            lightColor: SIMD4<Float>(
                1.0,
                0.66,
                0.24,
                lightStates.effectiveIntensity(.post) * 46
            ),
            waterSimulation: SIMD4<Float>(dt, elapsedTime, cameraMode == .firstPerson ? 1 : 0, 0),
            waterImpulse: pendingWaterImpulse,
            toolOrigin: SIMD4<Float>(toolOrigin, 1),
            toolDirection: SIMD4<Float>(toolDirection, 0),
            toolParameters: SIMD4<Float>(Float(renderTool.rawValue), 0, 0, isSplitScreenMode ? 1.0 : 0.0),
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
        let isMirrorActive = (heldTool == .mirror && mirrorActiveRemaining > 0)
        let shieldPos: SIMD3<Float>
        if isMirrorActive {
            shieldPos = playerPosition + SIMD3<Float>(-sin(playerYaw) * 0.48, 0, -cos(playerYaw) * 0.48)
        } else {
            shieldPos = SIMD3<Float>(0, -100, 0)
        }

        let d0 = dummyAlive[0] ? dummyPositions[0] : SIMD3<Float>(0, -100, 0)
        let d1 = dummyAlive[1] ? dummyPositions[1] : SIMD3<Float>(0, -100, 0)
        let d2 = dummyAlive[2] ? dummyPositions[2] : SIMD3<Float>(0, -100, 0)

        let descriptors = [
            Self.makeInstanceDescriptor(translation: .zero, yaw: 0, mask: 0x01, accelerationStructureIndex: 0),
            Self.makeInstanceDescriptor(translation: playerPosition, yaw: playerYaw, mask: 0x02, accelerationStructureIndex: 1),
            Self.makeInstanceDescriptor(translation: .zero, yaw: 0, mask: 0x04, accelerationStructureIndex: 2),
            Self.makeInstanceDescriptor(translation: floatPosition, yaw: floatYaw, mask: 0x01, accelerationStructureIndex: 3),
            Self.makeInstanceDescriptor(translation: npcPositions[0], yaw: npcYaws[0], mask: 0x01, accelerationStructureIndex: 4),
            Self.makeInstanceDescriptor(translation: npcPositions[1], yaw: npcYaws[1], mask: 0x01, accelerationStructureIndex: 4),
            Self.makeInstanceDescriptor(translation: shieldPos, yaw: playerYaw, mask: 0x01, accelerationStructureIndex: 5),
            Self.makeInstanceDescriptor(translation: d0, yaw: 0, mask: 0x01, accelerationStructureIndex: 4),
            Self.makeInstanceDescriptor(translation: d1, yaw: 0.5, mask: 0x01, accelerationStructureIndex: 4),
            Self.makeInstanceDescriptor(translation: d2, yaw: 1.2, mask: 0x01, accelerationStructureIndex: 4)
        ]
        descriptors.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            instanceBuffer.contents().copyMemory(from: baseAddress, byteCount: bytes.count)
        }
    }

    private func buildInitialInstanceAccelerationStructure() throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeAccelerationStructureCommandEncoder() else {
            throw MetalRayRendererError.resourceCreationFailed
        }
        encoder.build(
            accelerationStructure: instanceAccelerationStructure,
            descriptor: instanceDescriptor,
            scratchBuffer: instanceScratchBuffer,
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
        mask: UInt32,
        accelerationStructureIndex: UInt32
    ) -> MTLAccelerationStructureInstanceDescriptor {
        let cosine = cos(yaw)
        let sine = sin(yaw)
        var descriptor = MTLAccelerationStructureInstanceDescriptor()
        descriptor.transformationMatrix.columns.0 = MTLPackedFloat3Make(cosine, 0, -sine)
        descriptor.transformationMatrix.columns.1 = MTLPackedFloat3Make(0, 1, 0)
        descriptor.transformationMatrix.columns.2 = MTLPackedFloat3Make(sine, 0, cosine)
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
        let mirrorGlass = RTMaterial(color: SIMD3<Float>(0.20, 0.85, 0.98), roughness: 0.01, emission: SIMD3<Float>(0.08, 0.45, 0.75), reflectivity: 0.97, kind: 1.0)
        builder.addBox(center: SIMD3<Float>(0, 1.05, 0), size: SIMD3<Float>(0.92, 1.12, 0.045), material: mirrorFrame)
        builder.addBox(center: SIMD3<Float>(0, 1.05, 0), size: SIMD3<Float>(0.84, 1.04, 0.035), material: mirrorGlass)
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



        builder.addBox(center: SIMD3<Float>(0, -0.12, -7.1), size: SIMD3<Float>(20, 0.24, 5.4), material: deck)
        builder.addBox(center: SIMD3<Float>(0, -0.12, 5.6), size: SIMD3<Float>(20, 0.24, 8.4), material: deck)
        builder.addBox(center: SIMD3<Float>(-7.7, -0.12, -1.5), size: SIMD3<Float>(4.4, 0.24, 5.4), material: deck)
        builder.addBox(center: SIMD3<Float>(6.3, -0.12, -1.5), size: SIMD3<Float>(7.5, 0.24, 5.4), material: deck)
        builder.addBox(center: SIMD3<Float>(0, 2.5, -9.8), size: SIMD3<Float>(20, 5, 0.32), material: wall)
        builder.addBox(center: SIMD3<Float>(0, 2.5, 9.8), size: SIMD3<Float>(20, 5, 0.32), material: wall)
        builder.addBox(center: SIMD3<Float>(-9.8, 2.5, 0), size: SIMD3<Float>(0.32, 5, 20), material: wall)
        builder.addBox(center: SIMD3<Float>(9.8, 2.5, 0), size: SIMD3<Float>(0.32, 5, 20), material: wall)
        let slideCyan = RTMaterial(color: SIMD3<Float>(0.05, 0.82, 0.95), roughness: 0.05, emission: SIMD3<Float>(0.10, 0.35, 0.45), reflectivity: 0.88, kind: 1.0)
        let stairPink = RTMaterial(color: SIMD3<Float>(0.95, 0.18, 0.52), roughness: 0.20, emission: SIMD3<Float>(0.20, 0.04, 0.10), reflectivity: 0.40)
        let platformDeck = RTMaterial(color: SIMD3<Float>(0.14, 0.18, 0.22), roughness: 0.40, reflectivity: 0.20)

        // 3D Tobogán de Agua (Water Slide on North Deck slanting directly SOUTH into Pool Water!)
        builder.addBox(center: SIMD3<Float>(-1.5, 2.50, -7.2), size: SIMD3<Float>(2.4, 0.20, 2.2), material: platformDeck)
        builder.addBox(center: SIMD3<Float>(-2.7, 3.10, -7.2), size: SIMD3<Float>(0.12, 1.0, 2.2), material: metal)
        builder.addBox(center: SIMD3<Float>(-0.3, 3.10, -7.2), size: SIMD3<Float>(0.12, 1.0, 2.2), material: metal)
        builder.addBox(center: SIMD3<Float>(-1.5, 3.10, -8.3), size: SIMD3<Float>(2.4, 1.0, 0.12), material: metal)

        // Tobogán Back Access Stairs (From North Deck Z=-8.8 up to Platform Z=-7.2)
        for step in 0..<12 {
            let stepProgress = Float(step) / 11.0
            let stepY = stepProgress * 2.50
            let stepZ = -8.8 + stepProgress * 1.60
            builder.addBox(center: SIMD3<Float>(-1.5, stepY, stepZ), size: SIMD3<Float>(2.2, 0.18, 0.32), material: stairPink)
        }

        // Tobogán Water Slide Ramp (Slanted directly SOUTH into the pool water from Z=-6.1 down to Z=-2.0!)
        for step in 0..<16 {
            let stepProgress = Float(step) / 15.0
            let stepY = (1.0 - stepProgress) * 2.50
            let stepZ = -6.1 + stepProgress * 4.10
            builder.addBox(center: SIMD3<Float>(-1.5, stepY, stepZ), size: SIMD3<Float>(2.0, 0.16, 0.38), material: slideCyan)
            builder.addBox(center: SIMD3<Float>(-2.5, stepY + 0.18, stepZ), size: SIMD3<Float>(0.10, 0.36, 0.38), material: metal)
            builder.addBox(center: SIMD3<Float>(-0.5, stepY + 0.18, stepZ), size: SIMD3<Float>(0.10, 0.36, 0.38), material: metal)
        }

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
            SIMD3<Float>(1.35, 0.72, -9.43), SIMD3<Float>(5.65, 0.72, -9.43),
            SIMD3<Float>(5.65, 3.38, -9.43), SIMD3<Float>(1.35, 3.38, -9.43),
            material: mirror
        )
        builder.addBox(center: SIMD3<Float>(3.5, 3.49, -9.40), size: SIMD3<Float>(4.62, 0.16, 0.16), material: metal)
        builder.addBox(center: SIMD3<Float>(3.5, 0.61, -9.40), size: SIMD3<Float>(4.62, 0.16, 0.16), material: metal)
        builder.addBox(center: SIMD3<Float>(1.24, 2.05, -9.40), size: SIMD3<Float>(0.16, 2.72, 0.16), material: metal)
        builder.addBox(center: SIMD3<Float>(5.76, 2.05, -9.40), size: SIMD3<Float>(0.16, 2.72, 0.16), material: metal)
        builder.addNeonPoolSign(origin: SIMD2<Float>(-7.7, 3.30), z: -9.62)
        builder.addNeonSheeritSign(origin: SIMD2<Float>(3.05, 3.28), z: 9.62)

        let lampPosition = SIMD3<Float>(-7.55, 0, 6.65)
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

        builder.addCharacter(origin: SIMD3<Float>(6.7, 0, 0.8), color: SIMD3<Float>(0.92, 0.18, 0.45))
        builder.addCharacter(origin: SIMD3<Float>(7.4, 0, -1.0), color: SIMD3<Float>(0.96, 0.40, 0.10))
        builder.addCharacter(origin: SIMD3<Float>(-7.7, 0, 4.3), color: SIMD3<Float>(0.46, 0.20, 0.82))
        return builder
    }
}
