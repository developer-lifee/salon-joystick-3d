#include <metal_stdlib>
#include <simd/simd.h>

using namespace metal;
using namespace raytracing;

struct RTUniforms {
    float4 viewport;
    float4 cameraPosition;
    float4 cameraRight;
    float4 cameraUp;
    float4 cameraForward;
    float4 lightPosition;
    float4 lightColor;
    float4 waterSimulation;
    float4 waterImpulse;
    float4 toolOrigin;
    float4 toolDirection;
    float4 toolParameters;
    float4 lightStates;
    float4 secondaryCameraPosition;
    float4 secondaryCameraForward;
};

struct RTLaserResult {
    float4 primaryStart;
    float4 primaryEnd;
    float4 reflectedEnd;
    float4 bot0Start;
    float4 bot0End;
    float4 bot1Start;
    float4 bot1End;
    float4 bot2Start;
    float4 bot2End;
    float4 bot3Start;
    float4 bot3End;
    float4 bot4Start;
    float4 bot4End;
};

struct RTTriangleData {
    float4 normalRoughness;
    float4 albedoReflectivity;
    float4 emissionKind;
};

inline float3 transformedNormal(float3 normal,
                                constant MTLAccelerationStructureInstanceDescriptor *instances,
                                uint instanceIndex) {
    float4x4 transform(1.0f);
    for (int column = 0; column < 4; ++column) {
        for (int row = 0; row < 3; ++row) {
            transform[column][row] = instances[instanceIndex].transformationMatrix[column][row];
        }
    }
    return normalize((transform * float4(normal, 0.0f)).xyz);
}

inline float3 nightSky(float3 direction) {
    float horizon = saturate(direction.y * 0.5f + 0.5f);
    return mix(float3(0.14f, 0.18f, 0.25f), float3(0.28f, 0.34f, 0.42f), horizon);
}

inline float3 toneMap(float3 color) {
    color = max(color * 1.28f, 0.0f);
    color = color / (1.0f + color);
    return pow(color, float3(1.0f / 2.2f));
}

inline float3 simulatedWaterNormal(
    float3 position,
    texture2d<float, access::read> waterState) {
    uint2 waterSize = uint2(waterState.get_width(), waterState.get_height());
    float2 poolUV = clamp(
        float2((position.x + 5.4f) / 7.8f, (position.z + 4.2f) / 5.4f),
        0.0f,
        1.0f
    );
    uint2 waterCoordinate = clamp(
        uint2(poolUV * float2(waterSize - 1)),
        uint2(1),
        waterSize - 2
    );
    float leftHeight = waterState.read(waterCoordinate - uint2(1, 0)).r;
    float rightHeight = waterState.read(waterCoordinate + uint2(1, 0)).r;
    float nearHeight = waterState.read(waterCoordinate - uint2(0, 1)).r;
    float farHeight = waterState.read(waterCoordinate + uint2(0, 1)).r;
    float cellWidth = 7.8f / float(waterSize.x - 1);
    float cellLength = 5.4f / float(waterSize.y - 1);
    float slopeX = (rightHeight - leftHeight) / (2.0f * cellWidth);
    float slopeZ = (farHeight - nearHeight) / (2.0f * cellLength);
    return normalize(float3(-slopeX * 1.15f, 1.0f, -slopeZ * 1.15f));
}

inline float3 shallowPuddleNormal(float3 position, float time) {
    float phaseA = dot(position.xz, float2(4.2f, 2.7f)) + time * 0.62f;
    float phaseB = dot(position.xz, float2(-2.4f, 5.1f)) - time * 0.41f;
    float slopeX = cos(phaseA) * 0.050f - cos(phaseB) * 0.022f;
    float slopeZ = cos(phaseA) * 0.032f + cos(phaseB) * 0.046f;
    return normalize(float3(-slopeX, 1.0f, -slopeZ));
}

inline float laserBeamIntensity(
    float3 cameraOrigin,
    float3 cameraDirection,
    float maximumCameraDistance,
    float3 segmentStart,
    float3 segmentEnd) {
    float3 segment = segmentEnd - segmentStart;
    float segmentLengthSquared = length_squared(segment);
    if (segmentLengthSquared < 1e-5f) {
        return 0.0f;
    }

    float3 originDelta = cameraOrigin - segmentStart;
    float directionDotSegment = dot(cameraDirection, segment);
    float directionDotDelta = dot(cameraDirection, originDelta);
    float segmentDotDelta = dot(segment, originDelta);
    float denominator = segmentLengthSquared - directionDotSegment * directionDotSegment;
    float segmentT = abs(denominator) > 1e-5f
        ? (segmentDotDelta - directionDotSegment * directionDotDelta) / denominator
        : 0.0f;
    segmentT = clamp(segmentT, 0.0f, 1.0f);

    float3 closestOnSegment = segmentStart + segment * segmentT;
    float cameraDistance = dot(closestOnSegment - cameraOrigin, cameraDirection);
    if (cameraDistance < 0.16f || cameraDistance > maximumCameraDistance) {
        return 0.0f;
    }

    float3 closestOnCameraRay = cameraOrigin + cameraDirection * cameraDistance;
    float distance = length(closestOnSegment - closestOnCameraRay);
    float coreRadius = 0.024f + cameraDistance * 0.0022f;
    float glowRadius = 0.095f + cameraDistance * 0.0075f;
    float core = 1.0f - smoothstep(0.0f, coreRadius, distance);
    float glow = 1.0f - smoothstep(coreRadius, glowRadius, distance);
    return core * 2.8f + glow * 0.75f;
}

inline float3 mirroredLightContribution(
    float3 position,
    float3 normal,
    float3 viewDirection,
    float3 albedo,
    float3 sourcePosition,
    float3 sourceDirection,
    float3 sourceColor,
    float sourcePower,
    bool isSpotlight) {
    if (sourcePower <= 0.0f) {
        return 0.0f;
    }

    constexpr float mirrorZ = -9.43f;
    float3 virtualSource = sourcePosition;
    virtualSource.z = 2.0f * mirrorZ - sourcePosition.z;
    float3 toVirtualSource = virtualSource - position;
    if (abs(toVirtualSource.z) < 1e-4f) {
        return 0.0f;
    }

    float mirrorT = (mirrorZ - position.z) / toVirtualSource.z;
    float3 mirrorPoint = position + toVirtualSource * mirrorT;
    bool insideMirror = mirrorT > 0.0f && mirrorT < 1.0f &&
        mirrorPoint.x > 1.35f && mirrorPoint.x < 5.65f &&
        mirrorPoint.y > 0.72f && mirrorPoint.y < 3.38f;
    if (!insideMirror) {
        return 0.0f;
    }

    float cone = 1.0f;
    if (isSpotlight) {
        float3 sourceToMirror = normalize(mirrorPoint - sourcePosition);
        cone = smoothstep(0.90f, 0.975f, dot(sourceToMirror, normalize(sourceDirection)));
        if (cone <= 0.0001f) {
            return 0.0f;
        }
    }

    float3 surfaceToMirror = mirrorPoint - position;
    float surfacePath = length(surfaceToMirror);
    float sourcePath = distance(sourcePosition, mirrorPoint);
    float3 reflectedDirection = surfaceToMirror / max(surfacePath, 1e-4f);
    float incidence = saturate(dot(normal, reflectedDirection));
    float pathDistance = surfacePath + sourcePath;
    float attenuation = sourcePower * 0.72f /
        (1.0f + pathDistance * pathDistance * 0.09f);
    float3 diffuse = albedo * sourceColor * attenuation * incidence * cone;
    float3 halfDirection = normalize(reflectedDirection - viewDirection);
    float gloss = pow(saturate(dot(normal, halfDirection)), 150.0f);
    float3 specular = sourceColor * attenuation * gloss * cone * 0.20f;
    return (diffuse + specular) * 0.92f;
}

kernel void updateWaterHeight(
    uint2 tid [[thread_position_in_grid]],
    constant RTUniforms &uniforms [[buffer(0)]],
    texture2d<float, access::read> currentState [[texture(0)]],
    texture2d<float, access::write> nextState [[texture(1)]]) {

    uint2 size = uint2(currentState.get_width(), currentState.get_height());
    if (tid.x >= size.x || tid.y >= size.y) {
        return;
    }

    if (tid.x == 0 || tid.y == 0 || tid.x + 1 == size.x || tid.y + 1 == size.y) {
        nextState.write(float4(0.0f), tid);
        return;
    }

    float dt = clamp(uniforms.waterSimulation.x, 0.0f, 1.0f / 30.0f);
    float2 state = currentState.read(tid).rg;
    float height = state.x;
    float velocity = state.y;
    float neighborSum = currentState.read(tid - uint2(1, 0)).r +
                        currentState.read(tid + uint2(1, 0)).r +
                        currentState.read(tid - uint2(0, 1)).r +
                        currentState.read(tid + uint2(0, 1)).r;
    float laplacian = neighborSum - 4.0f * height;

    velocity += (laplacian * 58.0f - height * 2.2f) * dt;
    velocity *= max(0.0f, 1.0f - 0.82f * dt);

    float2 uv = float2(tid) / float2(size - 1);
    float2 worldPosition = float2(-5.4f + uv.x * 7.8f, -4.2f + uv.y * 5.4f);

    float3 requestedImpulse = uniforms.waterImpulse.xyz;
    if (abs(requestedImpulse.z) > 0.0001f) {
        float2 delta = worldPosition - requestedImpulse.xy;
        velocity += exp(-dot(delta, delta) * 12.0f) * requestedImpulse.z;
    }

    float ambientPhase = fmod(uniforms.waterSimulation.y, 5.5f);
    if (ambientPhase < dt) {
        float eventIndex = floor(uniforms.waterSimulation.y / 5.5f);
        float2 center = float2(
            -1.5f + sin(eventIndex * 1.7f) * 1.8f,
            -1.5f + cos(eventIndex * 2.1f) * 1.15f
        );
        float2 delta = worldPosition - center;
        velocity -= exp(-dot(delta, delta) * 18.0f) * 0.15f;
    }

    height = clamp(height + velocity * dt, -0.105f, 0.105f);
    nextState.write(float4(height, velocity, 0.0f, 0.0f), tid);
}

struct AnalyticalHit {
    bool hit;
    float distance;
    float3 position;
    float3 normal;
    float3 albedo;
    float kind;
};

inline AnalyticalHit analyticalPatioIntersect(ray r) {
    AnalyticalHit result;
    result.hit = false;
    result.distance = 1e5f;
    result.position = float3(0.0f);
    result.normal = float3(0.0f, 1.0f, 0.0f);
    result.albedo = float3(0.3f);
    result.kind = 0.0f;

    // 1. Ground / Floor Plane (y = 0.0 outside pool, y = -4.50 inside pool)
    if (r.direction.y < -0.001f) {
        float tFloor = (0.0f - r.origin.y) / r.direction.y;
        if (tFloor > 0.01f && tFloor < result.distance) {
            float3 pFloor = r.origin + r.direction * tFloor;
            bool insidePool = (pFloor.x > -5.35f && pFloor.x < 2.35f &&
                               pFloor.z > -4.20f && pFloor.z < 1.20f);
            if (!insidePool) {
                result.hit = true;
                result.distance = tFloor;
                result.position = pFloor;
                result.normal = float3(0.0f, 1.0f, 0.0f);
                float2 grid = fract(pFloor.xz * 0.8f);
                float grout = step(0.03f, grid.x) * step(0.03f, grid.y);
                result.albedo = mix(float3(0.15f, 0.16f, 0.18f), float3(0.42f, 0.45f, 0.48f), grout);
                result.kind = 0.0f;
            }
        }
        // Fondo cerámico profundo de la piscina a y = -4.50m
        float tDeepPool = (-4.50f - r.origin.y) / r.direction.y;
        if (tDeepPool > 0.01f && tDeepPool < result.distance) {
            float3 pPool = r.origin + r.direction * tDeepPool;
            if (pPool.x > -5.35f && pPool.x < 2.35f && pPool.z > -4.20f && pPool.z < 1.20f) {
                result.hit = true;
                result.distance = tDeepPool;
                result.position = pPool;
                result.normal = float3(0.0f, 1.0f, 0.0f);
                float2 grid = fract(pPool.xz * 1.5f);
                float grout = step(0.04f, grid.x) * step(0.04f, grid.y);
                result.albedo = mix(float3(0.02f, 0.25f, 0.42f), float3(0.12f, 0.65f, 0.85f), grout);
                result.kind = 3.0f;
            }
        }
    }

    // 2. Room Walls
    // Back Wall (z = -9.0)
    if (r.direction.z > 0.001f) {
        float tWall = (-9.0f - r.origin.z) / r.direction.z;
        if (tWall > 0.01f && tWall < result.distance) {
            result.hit = true;
            result.distance = tWall;
            result.position = r.origin + r.direction * tWall;
            result.normal = float3(0.0f, 0.0f, -1.0f);
            result.albedo = float3(0.28f, 0.35f, 0.42f);
            result.kind = 0.0f;
        }
    }
    // Front Wall (z = 9.0)
    if (r.direction.z < -0.001f) {
        float tWall = (9.0f - r.origin.z) / r.direction.z;
        if (tWall > 0.01f && tWall < result.distance) {
            result.hit = true;
            result.distance = tWall;
            result.position = r.origin + r.direction * tWall;
            result.normal = float3(0.0f, 0.0f, 1.0f);
            result.albedo = float3(0.28f, 0.35f, 0.42f);
            result.kind = 0.0f;
        }
    }
    // Left Wall (x = -9.0)
    if (r.direction.x < -0.001f) {
        float tWall = (-9.0f - r.origin.x) / r.direction.x;
        if (tWall > 0.01f && tWall < result.distance) {
            result.hit = true;
            result.distance = tWall;
            result.position = r.origin + r.direction * tWall;
            result.normal = float3(1.0f, 0.0f, 0.0f);
            result.albedo = float3(0.24f, 0.30f, 0.38f);
            result.kind = 0.0f;
        }
    }
    // Right Wall (x = 9.0)
    if (r.direction.x > 0.001f) {
        float tWall = (9.0f - r.origin.x) / r.direction.x;
        if (tWall > 0.01f && tWall < result.distance) {
            result.hit = true;
            result.distance = tWall;
            result.position = r.origin + r.direction * tWall;
            result.normal = float3(-1.0f, 0.0f, 0.0f);
            result.albedo = float3(0.24f, 0.30f, 0.38f);
            result.kind = 0.0f;
        }
    }

    // 3. Pool Water Surface (y = 0.48)
    if (r.direction.y < -0.001f && r.origin.y > 0.48f) {
        float tWater = (0.48f - r.origin.y) / r.direction.y;
        if (tWater > 0.01f && tWater < result.distance) {
            float3 pWater = r.origin + r.direction * tWater;
            if (pWater.x > -5.35f && pWater.x < 2.35f && pWater.z > -4.20f && pWater.z < 1.20f) {
                result.hit = true;
                result.distance = tWater;
                result.position = pWater;
                result.normal = float3(0.0f, 1.0f, 0.0f);
                result.albedo = float3(0.08f, 0.52f, 0.72f);
                result.kind = 2.0f;
            }
        }
    }

    // 4. Rear Wall Mirror (Espejo de Pared at z = -8.95)
    if (r.direction.z < -0.001f) {
        float tMirror = (-8.95f - r.origin.z) / r.direction.z;
        if (tMirror > 0.01f && tMirror < result.distance) {
            float3 pMirror = r.origin + r.direction * tMirror;
            if (pMirror.x > 1.35f && pMirror.x < 5.65f && pMirror.y > 0.72f && pMirror.y < 3.38f) {
                result.hit = true;
                result.distance = tMirror;
                result.position = pMirror;
                result.normal = float3(0.0f, 0.0f, 1.0f);
                result.albedo = float3(0.95f, 0.96f, 0.98f);
                result.kind = 1.0f; // Mirror surface!
            }
        }
    }

    // 5. Post Neon Light Fixture Sign (x = -7.55, y = 2.72, z = 6.65)
    float3 postCenter = float3(-7.55f, 2.72f, 6.65f);
    float3 ocPost = r.origin - postCenter;
    float bPost = dot(ocPost, r.direction);
    float cPost = dot(ocPost, ocPost) - 0.45f * 0.45f;
    float discPost = bPost * bPost - cPost;
    if (discPost > 0.0f) {
        float tPost = -bPost - sqrt(discPost);
        if (tPost > 0.01f && tPost < result.distance) {
            result.hit = true;
            result.distance = tPost;
            result.position = r.origin + r.direction * tPost;
            result.normal = normalize(result.position - postCenter);
            result.albedo = float3(1.0f, 0.75f, 0.25f);
            result.kind = 4.0f; // Emissive Neon Light Sign!
        }
    }

    // 6. Springboard & Pool Ladder (Trampolín at y = 2.85)
    if (r.direction.y < -0.001f) {
        float tTramp = (2.85f - r.origin.y) / r.direction.y;
        if (tTramp > 0.01f && tTramp < result.distance) {
            float3 pTramp = r.origin + r.direction * tTramp;
            if (pTramp.x > 0.5f && pTramp.x < 2.2f && pTramp.z > -8.5f && pTramp.z < -4.2f) {
                result.hit = true;
                result.distance = tTramp;
                result.position = pTramp;
                result.normal = float3(0.0f, 1.0f, 0.0f);
                result.albedo = float3(0.85f, 0.85f, 0.88f);
                result.kind = 0.0f;
            }
        }
    }

    // 7. Toboggan Water Slide Chute (Slanted chute from top platform into pool)
    float3 slideStart = float3(-3.8f, 3.8f, -3.5f);
    float3 slideEnd = float3(-2.2f, 0.45f, -0.5f);
    float3 slideAxis = slideEnd - slideStart;
    float slideLen = length(slideAxis);
    float3 slideDir = slideAxis / slideLen;
    float3 ocSlide = r.origin - slideStart;
    float projSlide = dot(ocSlide, slideDir);
    if (projSlide > 0.0f && projSlide < slideLen) {
        float3 closestPtOnSlide = slideStart + slideDir * projSlide;
        float3 ocChute = r.origin - closestPtOnSlide;
        float bChute = dot(ocChute, r.direction);
        float cChute = dot(ocChute, ocChute) - 0.55f * 0.55f;
        float discChute = bChute * bChute - cChute;
        if (discChute > 0.0f) {
            float tChute = -bChute - sqrt(discChute);
            if (tChute > 0.01f && tChute < result.distance) {
                result.hit = true;
                result.distance = tChute;
                result.position = r.origin + r.direction * tChute;
                result.normal = normalize(result.position - closestPtOnSlide);
                result.albedo = float3(0.12f, 0.65f, 0.95f); // Cyan Water Slide!
                result.kind = 0.0f;
            }
        }
    }

    // 7.5. Bio-Stasis Recovery Pods (x = -0.95, z = 6.2 and x = 0.95, z = 6.2)
    float2 podPositions[2] = { float2(-0.95f, 6.2f), float2(0.95f, 6.2f) };
    for (int p = 0; p < 2; ++p) {
        float2 ocPod = r.origin.xz - podPositions[p];
        float aPod = dot(r.direction.xz, r.direction.xz);
        if (aPod > 0.0001f) {
            float bPod = dot(ocPod, r.direction.xz);
            float cPod = dot(ocPod, ocPod) - 0.58f * 0.58f;
            float discPod = bPod * bPod - aPod * cPod;
            if (discPod > 0.0f) {
                float tPod = (-bPod - sqrt(discPod)) / aPod;
                if (tPod > 0.01f && tPod < result.distance) {
                    float yHit = r.origin.y + r.direction.y * tPod;
                    if (yHit >= 0.12f && yHit <= 2.25f) {
                        result.hit = true;
                        result.distance = tPod;
                        result.position = r.origin + r.direction * tPod;
                        result.normal = normalize(float3(result.position.x - podPositions[p].x, 0.0f, result.position.z - podPositions[p].y));
                        result.albedo = float3(0.08f, 0.78f, 0.92f);
                        result.kind = 1.0f; // Glass stasis reflection
                    }
                }
            }
        }
    }

    // 8. Ceiling Plane (y = 8.5f)
    if (r.direction.y > 0.001f) {
        float tCeil = (8.5f - r.origin.y) / r.direction.y;
        if (tCeil > 0.01f && tCeil < result.distance) {
            result.hit = true;
            result.distance = tCeil;
            result.position = r.origin + r.direction * tCeil;
            result.normal = float3(0.0f, -1.0f, 0.0f);
            float2 grid = fract(result.position.xz * 0.4f);
            float tile = step(0.03f, grid.x) * step(0.03f, grid.y);
            result.albedo = mix(float3(0.18f, 0.22f, 0.28f), float3(0.35f, 0.40f, 0.46f), tile);
            result.kind = 0.0f;
        }
    }

    return result;
}

kernel void updateWaterVertices(
    uint tid [[thread_position_in_grid]],
    device float3 *vertices [[buffer(0)]],
    texture2d<float, access::sample> waterState [[texture(0)]]) {

    constexpr sampler waterSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float3 position = vertices[tid];
    float2 uv = clamp(
        float2((position.x + 5.4f) / 7.8f, (position.z + 4.2f) / 5.4f),
        0.0f,
        1.0f
    );
    position.y = 0.00f + waterState.sample(waterSampler, uv).r;
    vertices[tid] = position;
}

kernel void traceToolLaser(
    constant RTUniforms &uniforms [[buffer(0)]],
    constant MTLAccelerationStructureInstanceDescriptor *instances [[buffer(1)]],
    instance_acceleration_structure accelerationStructure [[buffer(2)]],
    device RTLaserResult &result [[buffer(3)]],
    texture2d<float, access::read> waterState [[texture(0)]]) {

    float3 origin = uniforms.toolOrigin.xyz;
    float3 direction = normalize(uniforms.toolDirection.xyz);
    result.primaryStart = float4(origin, 1.0f);
    result.primaryEnd = float4(origin, 0.0f);
    result.reflectedEnd = float4(origin, 0.0f);

    bool isLaserGun = (uniforms.toolParameters.x > 1.5f && uniforms.toolParameters.x < 2.5f);
    bool isMirrorReflecting = (uniforms.toolParameters.x > 2.5f && uniforms.toolParameters.y > 1.5f);

    if (!isLaserGun && !isMirrorReflecting) {
        return;
    }

    bool isMirrorTool = (uniforms.toolParameters.x > 2.5f);

    intersector<triangle_data, instancing> tracer;
    tracer.assume_geometry_type(geometry_type::triangle);
    tracer.force_opacity(forced_opacity::opaque);
    tracer.accept_any_intersection(false);

    if (!isMirrorTool && uniforms.waterSimulation.z < 0.5f) {
        ray cameraAimRay;
        cameraAimRay.origin = uniforms.cameraPosition.xyz;
        cameraAimRay.direction = normalize(uniforms.cameraForward.xyz);
        cameraAimRay.max_distance = 45.0f;
        auto cameraAimHit = tracer.intersect(cameraAimRay, accelerationStructure, 0x05);
        float3 aimTarget;
        if (cameraAimHit.type != intersection_type::none) {
            aimTarget = cameraAimRay.origin + cameraAimRay.direction * cameraAimHit.distance;
        } else {
            AnalyticalHit analytical = analyticalPatioIntersect(cameraAimRay);
            if (analytical.hit) {
                aimTarget = analytical.position;
            } else {
                aimTarget = cameraAimRay.origin + cameraAimRay.direction * cameraAimRay.max_distance;
            }
        }
        float3 computedDir = normalize(aimTarget - origin);
        if (length_squared(computedDir) > 0.001f) {
            direction = computedDir;
        }
    }

    ray laserRay;
    laserRay.origin = isMirrorTool ? (origin + direction * 0.14f) : origin;
    laserRay.direction = direction;
    laserRay.max_distance = 75.0f;
    auto hit = tracer.intersect(laserRay, accelerationStructure, isMirrorTool ? 0x01 : 0x05);
    if (hit.type == intersection_type::none) {
        AnalyticalHit analytical = analyticalPatioIntersect(laserRay);
        if (analytical.hit) {
            result.primaryEnd = float4(analytical.position, 1.0f);
        } else {
            result.primaryEnd = float4(origin + direction * laserRay.max_distance, 1.0f);
        }
        return;
    }

    float3 hitPosition = origin + direction * hit.distance;
    result.primaryEnd = float4(hitPosition, 1.0f);
    RTTriangleData material = *(const device RTTriangleData *)hit.primitive_data;
    float kind = material.emissionKind.w;
    bool mirrorSurface = kind > 0.5f && kind < 1.5f;
    bool poolWaterSurface = kind > 1.5f && kind < 2.5f;
    bool puddleSurface = kind > 7.5f && kind < 8.5f;
    bool waterSurface = poolWaterSurface || puddleSurface;
    if (!mirrorSurface && !waterSurface) {
        return;
    }

    float3 normal = transformedNormal(material.normalRoughness.xyz, instances, hit.instance_id);
    if (poolWaterSurface) {
        normal = simulatedWaterNormal(hitPosition, waterState);
    } else if (puddleSurface) {
        normal = shallowPuddleNormal(hitPosition, uniforms.waterSimulation.y);
    }
    if (dot(normal, direction) > 0.0f) {
        normal = -normal;
    }

    float3 secondaryDirection = mirrorSurface
        ? reflect(direction, normal)
        : refract(direction, normal, 1.0f / 1.333f);
    if (length_squared(secondaryDirection) < 1e-5f) {
        return;
    }

    ray secondaryRay;
    secondaryRay.origin = mirrorSurface
        ? hitPosition + normal * 0.018f
        : hitPosition - normal * 0.018f;
    secondaryRay.direction = normalize(secondaryDirection);
    secondaryRay.max_distance = 55.0f;
    auto secondaryHit = tracer.intersect(
        secondaryRay,
        accelerationStructure,
        mirrorSurface ? 0x05 : 0x01
    );
    float3 secondaryEnd = secondaryHit.type == intersection_type::none
        ? secondaryRay.origin + secondaryRay.direction * secondaryRay.max_distance
        : secondaryRay.origin + secondaryRay.direction * secondaryHit.distance;
    result.reflectedEnd = float4(secondaryEnd, 1.0f);
}

struct FirstPersonHit {
    bool hit;
    float distance;
    float3 normal;
    float3 albedo;
    float3 emission;
};// Analytical intersection for first-person hands and swimming arms
inline FirstPersonHit intersectFirstPersonViewModel(
    ray r,
    float3 camPos,
    float3 cRight,
    float3 cUp,
    float3 cFwd,
    float time,
    bool isUnderwater,
    float toolKind,
    float swimSpeed
) {
    FirstPersonHit result;
    result.hit = false;
    result.distance = 1e5f;
    result.normal = float3(0, 1, 0);
    result.albedo = float3(0.20f, 0.88f, 0.28f);
    result.emission = float3(0.03f, 0.16f, 0.06f);

    if (isUnderwater) {
        float3 lHandCam, rHandCam;
        float3 lElbowCam, rElbowCam;

        if (swimSpeed < 0.12f) {
            // 🌊 Modo Flotación Relajada en Reposo (Treading Water / Sculling Idle)
            float floatBob = sin(time * 1.6f) * 0.022f;
            float scull = cos(time * 1.6f) * 0.028f;
            lHandCam = float3(-0.28f - scull, -0.26f + floatBob, 0.36f + floatBob * 0.5f);
            rHandCam = float3( 0.28f + scull, -0.26f + floatBob, 0.36f + floatBob * 0.5f);
            lElbowCam = float3(-0.35f, -0.38f + floatBob * 0.5f, 0.18f);
            rElbowCam = float3( 0.35f, -0.38f + floatBob * 0.5f, 0.18f);
        } else {
            // 🏊‍♂️ Brazada Anatómica de Braza (Natural Dynamic Breaststroke Cycle)
            float strokeRate = 2.8f + swimSpeed * 1.1f;
            float strokeT = fmod(time * strokeRate, 6.2831853f);
            float extension = sin(strokeT);
            float reachZ = 0.38f + 0.14f * extension;
            float sweepY = -0.20f - 0.08f * saturate(-extension);
            float spreadX = 0.14f + 0.18f * saturate(-extension * 0.8f + 0.4f);

            lHandCam = float3(-spreadX, sweepY, reachZ);
            rHandCam = float3( spreadX, sweepY, reachZ);

            float elbowFlex = saturate(-extension);
            lElbowCam = float3(-0.32f - elbowFlex * 0.10f, -0.34f + elbowFlex * 0.06f, 0.18f + elbowFlex * 0.04f);
            rElbowCam = float3( 0.32f + elbowFlex * 0.10f, -0.34f + elbowFlex * 0.06f, 0.18f + elbowFlex * 0.04f);
        }

        float3 lHandWorld = camPos + cRight * lHandCam.x + cUp * lHandCam.y + cFwd * lHandCam.z;
        float3 rHandWorld = camPos + cRight * rHandCam.x + cUp * rHandCam.y + cFwd * rHandCam.z;
        float3 lElbowWorld = camPos + cRight * lElbowCam.x + cUp * lElbowCam.y + cFwd * lElbowCam.z;
        float3 rElbowWorld = camPos + cRight * rElbowCam.x + cUp * rElbowCam.y + cFwd * rElbowCam.z;

        float handRadius = 0.055f;
        float armRadius = 0.046f;

        // Left hand sphere
        float3 ocL = r.origin - lHandWorld;
        float bL = dot(ocL, r.direction);
        float cL = dot(ocL, ocL) - handRadius * handRadius;
        float discL = bL * bL - cL;
        if (discL >= 0.0f) {
            float tL = -bL - sqrt(discL);
            if (tL > 0.08f && tL < result.distance) {
                result.hit = true;
                result.distance = tL;
                result.normal = normalize((r.origin + r.direction * tL) - lHandWorld);
            }
        }

        // Right hand sphere
        float3 ocR = r.origin - rHandWorld;
        float bR = dot(ocR, r.direction);
        float cR = dot(ocR, ocR) - handRadius * handRadius;
        float discR = bR * bR - cR;
        if (discR >= 0.0f) {
            float tR = -bR - sqrt(discR);
            if (tR > 0.08f && tR < result.distance) {
                result.hit = true;
                result.distance = tR;
                result.normal = normalize((r.origin + r.direction * tR) - rHandWorld);
            }
        }

        // Left forearm capsule
        float3 baL = lHandWorld - lElbowWorld;
        float3 oaL = r.origin - lElbowWorld;
        float badaL = dot(baL, baL);
        float bardL = dot(baL, r.direction);
        float baoaL = dot(baL, oaL);
        float rdoaL = dot(r.direction, oaL);
        float oaoaL = dot(oaL, oaL);

        float aCapsL = badaL - bardL * bardL;
        float bCapsL = badaL * rdoaL - baoaL * bardL;
        float cCapsL = badaL * oaoaL - baoaL * baoaL - armRadius * armRadius * badaL;
        float dCapsL = bCapsL * bCapsL - aCapsL * cCapsL;
        if (dCapsL >= 0.0f && abs(aCapsL) > 1e-6f) {
            float tCapsL = (-bCapsL - sqrt(dCapsL)) / aCapsL;
            if (tCapsL > 0.08f && tCapsL < result.distance) {
                float yCapsL = baoaL + tCapsL * bardL;
                if (yCapsL > 0.0f && yCapsL < badaL) {
                    result.hit = true;
                    result.distance = tCapsL;
                    float3 pHit = r.origin + r.direction * tCapsL;
                    result.normal = normalize(pHit - (lElbowWorld + baL * (yCapsL / badaL)));
                }
            }
        }

        // Right forearm capsule
        float3 baR = rHandWorld - rElbowWorld;
        float3 oaR = r.origin - rElbowWorld;
        float badaR = dot(baR, baR);
        float bardR = dot(baR, r.direction);
        float baoaR = dot(baR, oaR);
        float rdoaR = dot(r.direction, oaR);
        float oaoaR = dot(oaR, oaR);

        float aCapsR = badaR - bardR * bardR;
        float bCapsR = badaR * rdoaR - baoaR * bardR;
        float cCapsR = badaR * oaoaR - baoaR * baoaR - armRadius * armRadius * badaR;
        float dCapsR = bCapsR * bCapsR - aCapsR * cCapsR;
        if (dCapsR >= 0.0f && abs(aCapsR) > 1e-6f) {
            float tCapsR = (-bCapsR - sqrt(dCapsR)) / aCapsR;
            if (tCapsR > 0.08f && tCapsR < result.distance) {
                float yCapsR = baoaR + tCapsR * bardR;
                if (yCapsR > 0.0f && yCapsR < badaR) {
                    result.hit = true;
                    result.distance = tCapsR;
                    float3 pHit = r.origin + r.direction * tCapsR;
                    result.normal = normalize(pHit - (rElbowWorld + baR * (yCapsR / badaR)));
                }
            }
        }
    } else {
        // 🧍 First person idle/holding hands on land
        float breathe = sin(time * 2.2f) * 0.008f;
        float3 rHandCam = float3(0.24f, -0.22f + breathe, 0.44f);
        float3 rHandWorld = camPos + cRight * rHandCam.x + cUp * rHandCam.y + cFwd * rHandCam.z;
        float handRadius = 0.060f;

        float3 ocR = r.origin - rHandWorld;
        float bR = dot(ocR, r.direction);
        float cR = dot(ocR, ocR) - handRadius * handRadius;
        float discR = bR * bR - cR;
        if (discR >= 0.0f) {
            float tR = -bR - sqrt(discR);
            if (tR > 0.08f && tR < result.distance) {
                result.hit = true;
                result.distance = tR;
                result.normal = normalize((r.origin + r.direction * tR) - rHandWorld);
            }
        }

        // Tool body in hand (Flashlight or Laser)
        if (toolKind > 0.5f) {
            float3 toolCenter = rHandWorld + cFwd * 0.09f + cUp * 0.02f;
            float3 ocT = r.origin - toolCenter;
            float bT = dot(ocT, r.direction);
            float cT = dot(ocT, ocT) - 0.040f * 0.040f;
            float discT = bT * bT - cT;
            if (discT >= 0.0f) {
                float tT = -bT - sqrt(discT);
                if (tT > 0.08f && tT < result.distance) {
                    result.hit = true;
                    result.distance = tT;
                    result.normal = normalize((r.origin + r.direction * tT) - toolCenter);
                    result.albedo = toolKind > 1.5f ? float3(0.95f, 0.15f, 0.15f) : float3(0.92f, 0.85f, 0.20f);
                    result.emission = toolKind > 1.5f ? float3(0.6f, 0.05f, 0.05f) : float3(0.4f, 0.35f, 0.05f);
                }
            }
        }
    }

    return result;
}

kernel void raytracePatio(
    uint2 tid [[thread_position_in_grid]],
    constant RTUniforms &uniforms [[buffer(0)]],
    constant MTLAccelerationStructureInstanceDescriptor *instances [[buffer(1)]],
    instance_acceleration_structure accelerationStructure [[buffer(2)]],
    constant RTLaserResult &laserResult [[buffer(3)]],
    texture2d<half, access::write> output [[texture(0)]],
    texture2d<float, access::read> waterState [[texture(1)]]) {

    uint width = uint(uniforms.viewport.x);
    uint height = uint(uniforms.viewport.y);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    bool rayBouncesEnabled = uniforms.viewport.w > 0.5f;
    bool firstPerson = uniforms.waterSimulation.z > 0.5f;
    float2 pixel = float2(tid) + 0.5f;
    float2 uv = pixel / float2(width, height) * 2.0f - 1.0f;
    uv.y = -uv.y;

    ray currentRay;
    currentRay.origin = uniforms.cameraPosition.xyz;
    currentRay.direction = normalize(uv.x * uniforms.cameraRight.xyz +
                                     uv.y * uniforms.cameraUp.xyz +
                                     uniforms.cameraForward.xyz);

    bool isSplitScreen = uniforms.toolParameters.w > 0.5f;
    bool isMirrorSplit = (uniforms.toolParameters.x > 2.5f);
    bool isMirrorViewport = false;
    float2 mirrorLocalUV = float2(0.0f);

    if (isMirrorSplit) {
        uint halfWidth = width / 2;
        if (abs(int(tid.x) - int(halfWidth)) <= 3) {
            bool deflecting = (uniforms.toolParameters.y > 1.5f);
            half4 divColor = deflecting ? half4(0.15h, 1.0h, 0.72h, 1.0h) : half4(0.08h, 0.88h, 1.0h, 1.0h);
            output.write(divColor, tid);
            return;
        }
        isMirrorViewport = (tid.x >= halfWidth);
        float subScreenWidth = float(halfWidth);
        float localX = isMirrorViewport ? float(tid.x - halfWidth) : float(tid.x);
        mirrorLocalUV = float2(((localX + 0.5f) / subScreenWidth) * 2.0f - 1.0f, uv.y);

        if (!isMirrorViewport) {
            // Mitad Izquierda: Vista del Escenario centrada en el jugador y el escudo espejo
            float arenaU = mirrorLocalUV.x * 0.56f;
            currentRay.origin = uniforms.cameraPosition.xyz;
            currentRay.direction = normalize(arenaU * uniforms.cameraRight.xyz +
                                             uv.y * uniforms.cameraUp.xyz +
                                             uniforms.cameraForward.xyz);
        } else {
            // Mitad Derecha: Vista Óptica en Vivo desde el Reflejo del Espejo
            firstPerson = false;
            float3 mirrorForward = normalize(uniforms.toolDirection.xyz);
            float3 mirrorRight = cross(mirrorForward, float3(0.0f, 1.0f, 0.0f));
            if (length_squared(mirrorRight) < 1e-4f) {
                mirrorRight = float3(1.0f, 0.0f, 0.0f);
            } else {
                mirrorRight = normalize(mirrorRight);
            }
            float3 mirrorUp = normalize(cross(mirrorRight, mirrorForward));
            float halfAspect = (subScreenWidth / max(1.0f, float(height))) * 0.50f;
            currentRay.origin = uniforms.toolOrigin.xyz + mirrorForward * 0.14f;
            currentRay.direction = normalize(mirrorLocalUV.x * mirrorRight * halfAspect +
                                             mirrorLocalUV.y * mirrorUp * 0.50f +
                                             mirrorForward);
        }
    } else if (isSplitScreen) {
        // 📱📱 Modo iPhone Duo: Doble Cámara de Escuadra (Izquierda: Tu Vista | Derecha: Cámara en Vivo de tu Compañero de Escuadra)
        uint halfWidth = width / 2;
        if (abs(int(tid.x) - int(halfWidth)) <= 2) {
            output.write(half4(0.08h, 0.90h, 1.0h, 1.0h), tid);
            return;
        }
        bool isSquadViewport = (tid.x >= halfWidth);
        float subScreenWidth = float(halfWidth);
        float localX = isSquadViewport ? float(tid.x - halfWidth) : float(tid.x);
        float2 splitUV = float2(((localX + 0.5f) / subScreenWidth) * 2.0f - 1.0f, uv.y);
        float halfAspectScale = 0.52f;

        if (!isSquadViewport) {
            currentRay.origin = uniforms.cameraPosition.xyz;
            currentRay.direction = normalize(splitUV.x * halfAspectScale * uniforms.cameraRight.xyz +
                                             splitUV.y * uniforms.cameraUp.xyz +
                                             uniforms.cameraForward.xyz);
        } else {
            firstPerson = false;
            float3 sqOrigin = uniforms.secondaryCameraPosition.xyz;
            float3 sqForward = normalize(uniforms.secondaryCameraForward.xyz);
            float3 sqRight = cross(sqForward, float3(0.0f, 1.0f, 0.0f));
            if (length_squared(sqRight) < 1e-4f) {
                sqRight = float3(1.0f, 0.0f, 0.0f);
            } else {
                sqRight = normalize(sqRight);
            }
            float3 sqUp = normalize(cross(sqRight, sqForward));
            float subAspect = (subScreenWidth / max(1.0f, float(height))) * 0.58f;
            currentRay.origin = sqOrigin;
            currentRay.direction = normalize(splitUV.x * sqRight * subAspect +
                                             splitUV.y * sqUp * 0.58f +
                                             sqForward);
        }
    }

    currentRay.max_distance = 145.0f;
    float3 primaryOrigin = currentRay.origin;
    float3 primaryDirection = currentRay.direction;
    float firstSurfaceDistance = currentRay.max_distance;

    intersector<triangle_data, instancing> tracer;
    tracer.assume_geometry_type(geometry_type::triangle);
    tracer.force_opacity(forced_opacity::opaque);

    float3 accumulated = 0.0f;
    float3 throughput = 1.0f;
    float3 bounce1Origin = 0.0f;
    float3 bounce1Direction = 0.0f;
    float bounce1Distance = 145.0f;
    float3 bounce1Throughput = 0.0f;
    bool hasBounce1 = false;

    for (uint bounce = 0; bounce < 3; ++bounce) {
        if (bounce == 1) {
            hasBounce1 = true;
            bounce1Origin = currentRay.origin;
            bounce1Direction = currentRay.direction;
            bounce1Throughput = throughput;
        }
        tracer.accept_any_intersection(false);
        uint rayMask = (bounce == 0 && isMirrorViewport) ? 0x01 : (bounce == 0 && firstPerson ? 0x05 : 0x07);
        auto hit = tracer.intersect(currentRay, accelerationStructure, rayMask);
        float3 position;
        float3 normal;
        float3 albedo;
        float kind;
        float baseReflectivity = 0.05f;
        float roughness = 0.5f;
        float3 emission = float3(0.0f);

        bool hitFP = false;
        if (bounce == 0 && firstPerson) {
            bool inWater = uniforms.cameraPosition.y < 0.35f || uniforms.cameraPosition.y <= -4.75f;
            FirstPersonHit fpHit = intersectFirstPersonViewModel(
                currentRay,
                uniforms.cameraPosition.xyz,
                normalize(uniforms.cameraRight.xyz),
                normalize(uniforms.cameraUp.xyz),
                normalize(uniforms.cameraForward.xyz),
                uniforms.viewport.z,
                inWater,
                uniforms.toolParameters.x,
                max(0.0f, uniforms.waterSimulation.z - 1.0f)
            );
            if (fpHit.hit && (hit.type == intersection_type::none || fpHit.distance < hit.distance)) {
                hitFP = true;
                firstSurfaceDistance = fpHit.distance;
                position = currentRay.origin + currentRay.direction * fpHit.distance;
                normal = fpHit.normal;
                if (dot(normal, currentRay.direction) > 0.0f) {
                    normal = -normal;
                }
                albedo = fpHit.albedo;
                emission = fpHit.emission;
                kind = 0.0f;
                baseReflectivity = 0.35f;
                roughness = 0.22f;
            }
        }

        if (!hitFP) {
            if (hit.type != intersection_type::none) {
                if (bounce == 0) {
                    firstSurfaceDistance = hit.distance;
                } else if (bounce == 1) {
                    bounce1Distance = hit.distance;
                }
                RTTriangleData material = *(const device RTTriangleData *)hit.primitive_data;
                position = currentRay.origin + currentRay.direction * hit.distance;
                normal = transformedNormal(material.normalRoughness.xyz, instances, hit.instance_id);
                if (dot(normal, currentRay.direction) > 0.0f) {
                    normal = -normal;
                }
                kind = material.emissionKind.w;
                emission = material.emissionKind.xyz;
                albedo = material.albedoReflectivity.xyz;
                baseReflectivity = material.albedoReflectivity.w;
                roughness = material.normalRoughness.w;
            } else {
            bool isHardwareRT = uniforms.waterSimulation.w > 0.5f;
            float totalLights = uniforms.lightStates.x + uniforms.lightStates.y + uniforms.lightStates.z + uniforms.lightStates.w;
            float lightScale = clamp(totalLights / 0.8f, 0.0f, 1.0f);
            if (isHardwareRT) {
                accumulated += throughput * nightSky(currentRay.direction) * lightScale;
                break;
            }

            AnalyticalHit analytical = analyticalPatioIntersect(currentRay);
            // 🤖 3D Articulated Robot Fallback (Head, Torso, Backpack)
            for (uint b = 0; b < 5; ++b) {
                float3 botPos = float3(instances[4 + b].transformationMatrix[3].x,
                                       instances[4 + b].transformationMatrix[3].y,
                                       instances[4 + b].transformationMatrix[3].z);
                if (botPos.y > -5.0f) {
                    // 1. Torso Armor
                    float3 torsoCenter = botPos + float3(0.0f, 0.85f, 0.0f);
                    float3 ocTorso = currentRay.origin - torsoCenter;
                    float bTorso = dot(ocTorso, currentRay.direction);
                    float cTorso = dot(ocTorso, ocTorso) - 0.38f * 0.38f;
                    float discTorso = bTorso * bTorso - cTorso;
                    if (discTorso > 0.0f) {
                        float tTorso = -bTorso - sqrt(discTorso);
                        if (tTorso > 0.32f && tTorso < analytical.distance) {
                            analytical.hit = true;
                            analytical.distance = tTorso;
                            analytical.position = currentRay.origin + currentRay.direction * tTorso;
                            analytical.normal = normalize(analytical.position - torsoCenter);
                            analytical.albedo = (b == 4) ? float3(0.65f, 0.15f, 0.85f) : (b == 0 ? float3(0.15f, 0.75f, 0.42f) : float3(0.85f, 0.22f, 0.18f));
                            analytical.kind = 0.0f;
                        }
                    }

                    // 2. Golden Robot Helmet with Visor
                    float3 headCenter = botPos + float3(0.0f, 1.45f, 0.0f);
                    float3 ocHead = currentRay.origin - headCenter;
                    float bHead = dot(ocHead, currentRay.direction);
                    float cHead = dot(ocHead, ocHead) - 0.26f * 0.26f;
                    float discHead = bHead * bHead - cHead;
                    if (discHead > 0.0f) {
                        float tHead = -bHead - sqrt(discHead);
                        if (tHead > 0.32f && tHead < analytical.distance) {
                            analytical.hit = true;
                            analytical.distance = tHead;
                            analytical.position = currentRay.origin + currentRay.direction * tHead;
                            analytical.normal = normalize(analytical.position - headCenter);
                            analytical.albedo = float3(0.92f, 0.82f, 0.20f); // Gold Helmet!
                            analytical.kind = 0.0f;
                        }
                    }

                    // 3. Cyan Battery Backpack
                    float3 packCenter = botPos + float3(0.0f, 0.95f, -0.22f);
                    float3 ocPack = currentRay.origin - packCenter;
                    float bPack = dot(ocPack, currentRay.direction);
                    float cPack = dot(ocPack, ocPack) - 0.22f * 0.22f;
                    float discPack = bPack * bPack - cPack;
                    if (discPack > 0.0f) {
                        float tPack = -bPack - sqrt(discPack);
                        if (tPack > 0.32f && tPack < analytical.distance) {
                            analytical.hit = true;
                            analytical.distance = tPack;
                            analytical.position = currentRay.origin + currentRay.direction * tPack;
                            analytical.normal = normalize(analytical.position - packCenter);
                            analytical.albedo = float3(0.15f, 0.85f, 0.95f); // Cyan Energy Cell!
                            analytical.kind = 4.0f; // Glowing energy cell!
                        }
                    }
                }
            }

            if (!analytical.hit) {
                float totalLights = uniforms.lightStates.x + uniforms.lightStates.y + uniforms.lightStates.z + uniforms.lightStates.w;
                float lightScale = clamp(totalLights / 0.8f, 0.0f, 1.0f);
                accumulated += throughput * nightSky(currentRay.direction) * lightScale;
                break;
            }
            if (bounce == 0) {
                firstSurfaceDistance = analytical.distance;
            }
            position = analytical.position;
            normal = analytical.normal;
            albedo = analytical.albedo;
            kind = analytical.kind;
            baseReflectivity = (kind == 2.0f) ? 0.35f : 0.08f;
        }
        }

        bool poolWaterSurface = kind > 1.5f && kind < 2.5f;
        bool puddleSurface = kind > 7.5f && kind < 8.5f;
        bool jellySurface = kind > 8.5f && kind < 9.5f;
        bool obsidianSurface = kind > 9.5f && kind < 10.5f;
        bool waterSurface = poolWaterSurface || puddleSurface;

        float botMelt = 0.0f;
        if (!hitFP && hit.type != intersection_type::none && hit.instance_id >= 4 && hit.instance_id <= 8) {
            float3 col0 = float3(instances[hit.instance_id].transformationMatrix[0][0],
                                 instances[hit.instance_id].transformationMatrix[0][1],
                                 instances[hit.instance_id].transformationMatrix[0][2]);
            float3 col1 = float3(instances[hit.instance_id].transformationMatrix[1][0],
                                 instances[hit.instance_id].transformationMatrix[1][1],
                                 instances[hit.instance_id].transformationMatrix[1][2]);
            float scaleXZ = length(col0);
            float scaleY = length(col1);
            float ratio = scaleY / max(scaleXZ, 0.001f);
            botMelt = saturate((0.88f - ratio) / 0.80f);
        }

        if (poolWaterSurface) {
            normal = simulatedWaterNormal(position, waterState);
        } else if (puddleSurface) {
            normal = shallowPuddleNormal(position, uniforms.waterSimulation.y);
        } else if (kind > 2.5f && kind < 3.5f) {
            if (position.y > -0.15f && position.y < 0.06f) {
                // 💧 Zonas orgánicas de piso húmedo vs. losa seca (charcos realistas por zonas, no en todo el piso)
                float2 grid = fract(position.xz * 2.2f);
                float grout = step(0.04f, grid.x) * step(0.04f, grid.y);
                float3 groutBump = float3((1.0f - grout) * 0.09f, 0.0f, (1.0f - grout) * 0.09f);

                float2 pWet = position.xz;
                float wetWave1 = sin(pWet.x * 0.42f + cos(pWet.y * 0.38f) * 1.6f) * cos(pWet.y * 0.45f - sin(pWet.x * 0.34f) * 1.4f);
                float wetWave2 = sin((pWet.x + pWet.y) * 0.27f + 1.2f) * cos((pWet.x - pWet.y) * 0.31f - 0.8f);
                float poolProximity = smoothstep(4.2f, 0.8f, abs(length(pWet - float2(0.0f, 1.5f)) - 5.2f)) * 0.25f;
                float wetField = wetWave1 * 0.58f + wetWave2 * 0.42f + poolProximity;
                float wetMask = smoothstep(0.14f, 0.46f, wetField);

                float3 wetRipple = shallowPuddleNormal(position * 0.85f, uniforms.waterSimulation.y * 0.55f) * (0.14f * wetMask);
                normal = normalize(normal + groutBump * (1.0f - wetMask * 0.72f) + float3(wetRipple.x, 0.0f, wetRipple.z));

                float3 dryAlbedo = float3(0.11f, 0.14f, 0.16f) * (0.82f + 0.18f * grout);
                float3 wetAlbedo = float3(0.022f, 0.032f, 0.044f);
                albedo = mix(dryAlbedo, wetAlbedo, wetMask);
                roughness = mix(0.76f, 0.015f, wetMask);

                float viewCosine = saturate(dot(-currentRay.direction, normal));
                float fresnel = pow(1.0f - viewCosine, 2.2f);
                float wetRefl = mix(0.62f, 0.94f, fresnel);
                baseReflectivity = mix(0.03f, wetRefl, wetMask);
            } else {
                // 🪨 Textura Geológica Procedural de Roca Búlder / Basalto & Granito Realista
                float3 rP = position * 4.8f;
                // Ruido multi-frecuencia orgánico 3D de micro-grietas y crags
                float cragNoise1 = sin(rP.x * 1.8f + cos(rP.z * 1.6f) * 2.4f) * cos(rP.y * 2.2f);
                float cragNoise2 = sin(rP.y * 3.8f + rP.x * 2.1f) * cos(rP.z * 3.4f);
                float fineGrain = sin(rP.x * 14.0f) * sin(rP.y * 14.0f) * sin(rP.z * 14.0f);

                // Estratos horizontales geológicos sedimentarios
                float strata = sin(position.y * 11.0f + sin(position.x * 2.2f) * 0.35f + cos(position.z * 2.2f) * 0.35f) * 0.12f;

                // Perturbación de normales para relieve rocoso auténtico
                float3 rockBump = float3(
                    cragNoise1 * 0.16f + fineGrain * 0.04f + strata * 0.25f,
                    cragNoise2 * 0.12f + fineGrain * 0.04f,
                    (cragNoise1 - cragNoise2) * 0.16f + fineGrain * 0.04f
                );
                normal = normalize(normal + rockBump);

                // Variación de color: vetas minerales oscuras y musgo/líquenes en la cumbre
                float topExposure = saturate(dot(normal, float3(0.0f, 1.0f, 0.0f)));
                float crevice = smoothstep(-0.2f, 0.4f, cragNoise1 * cragNoise2);
                float3 mineralVein = mix(float3(0.70f, 0.72f, 0.75f), float3(1.25f, 1.20f, 1.15f), crevice);
                float3 mossTint = float3(0.24f, 0.30f, 0.20f); // Líquenes secos en la parte superior
                albedo = mix(albedo * mineralVein, mossTint, topExposure * 0.28f);
                roughness = 0.82f;
                baseReflectivity = 0.04f;
            }
        } else if (kind < 0.5f && abs(normal.y) < 0.35f && (abs(position.x) > 16.5f || abs(position.z) > 16.5f || abs(position.x) > 25.5f || position.z > 69.5f)) {
            // 🧱 Muros Perimetrales: Paneles Modulares Cyber / Titanio con Juntas y Remaches
            float wallCoordH = (abs(normal.x) > 0.5f) ? position.z : position.x;
            float wallCoordV = position.y;

            // Juntas modulares de paneles cada 2.4m horizontales y 2.0m verticales
            float seamH = smoothstep(0.012f, 0.038f, abs(fract(wallCoordH * 0.416f) - 0.5f));
            float seamV = smoothstep(0.012f, 0.038f, abs(fract(wallCoordV * 0.500f) - 0.5f));
            float panelSeam = min(seamH, seamV); // 0 en la junta hundida, 1 en el panel

            // Micro-relieve de textura de concreto reforzado / placa de titanio mate
            float microGrain = sin(wallCoordH * 16.0f) * sin(wallCoordV * 16.0f) * 0.035f;
            normal = normalize(normal + float3(microGrain, (1.0f - panelSeam) * -0.08f, microGrain));

            // Sombra ambiental en las hendiduras de las juntas de los paneles
            float seamShadow = mix(0.38f, 1.0f, panelSeam);
            albedo = albedo * seamShadow;
            roughness = mix(0.45f, 0.78f, panelSeam);
            baseReflectivity = 0.05f;
        } else if (obsidianSurface) {
            // 🌑 Armadura Sólida Mate Vantablack del Fotófago (opaca, absorbe la luz sin transparencias ni destellos invasivos)
            float viewCos = saturate(dot(-currentRay.direction, normal));
            float edgeRim = pow(1.0f - viewCos, 3.5f);
            albedo = float3(0.012f, 0.012f, 0.018f);
            emission = float3(0.14f, 0.04f, 0.26f) * edgeRim;
            baseReflectivity = 0.04f;
            roughness = 0.85f;
        } else if (jellySurface) {
            // 🧪 Diablillo de Gelatina: Textura orgánica húmeda con micro-relieve, SSS Fresnel y motas luminosas internas
            float3 pCell = position * 28.0f;
            float3 bump = float3(
                sin(pCell.x) * cos(pCell.y * 1.1f),
                sin(pCell.y) * cos(pCell.z * 1.1f),
                sin(pCell.z) * cos(pCell.x * 1.1f)
            ) * 0.085f;
            normal = normalize(normal + bump);

            // Motas / burbujas internas brillantes de gelatina (Amarillo-Lima bioluminiscente)
            float3 cellId = floor(position * 34.0f);
            float3 cellUV = fract(position * 34.0f) - 0.5f;
            float cellHash = fract(sin(dot(cellId, float3(12.9898f, 78.233f, 37.719f))) * 43758.5453f);
            float speckle = (cellHash > 0.84f) ? smoothstep(0.32f, 0.08f, length(cellUV)) : 0.0f;
            albedo = mix(albedo, float3(0.82f, 1.0f, 0.24f), speckle * 0.85f);

            // Dispersión Subsuperficial (SSS) tipo gomita / slime translúcido en los bordes (Fresnel)
            float viewCos = saturate(dot(-currentRay.direction, normal));
            float rimSSS = pow(1.0f - viewCos, 2.2f);
            emission += albedo * float3(0.55f, 1.25f, 0.25f) * (0.28f + rimSSS * 0.85f) + float3(0.75f, 1.0f, 0.22f) * (speckle * 0.65f);
            baseReflectivity = mix(0.14f, 0.68f, pow(1.0f - viewCos, 4.0f));
            roughness = 0.12f;
        }

        // 🫠 Disolución / Derretimiento Líquido Cromático al eliminar a un enemigo
        if (botMelt > 0.02f) {
            float time = uniforms.waterSimulation.y;
            float2 rippleUV = position.xz * 12.0f;
            float ripple = sin(rippleUV.x + time * 8.5f) * cos(rippleUV.y - time * 7.5f);
            normal = normalize(mix(normal, float3(ripple * 0.14f, 1.0f, -ripple * 0.14f), botMelt));
            float swirl = 0.5f + 0.5f * sin(length(position.xz) * 15.0f - time * 9.0f + ripple * 2.2f);
            float3 neonCyan = float3(0.0f, 0.95f, 1.0f);
            float3 neonMagenta = float3(1.0f, 0.10f, 0.56f);
            float3 neonAmber = float3(1.0f, 0.58f, 0.08f);
            float3 meltColor = mix(neonMagenta, neonCyan, swirl);
            float ember = smoothstep(0.76f, 0.95f, fract(sin(dot(floor(position * 26.0f), float3(12.9898f, 78.233f, 37.719f))) * 43758.5453f));
            albedo = mix(albedo, meltColor * 0.32f, botMelt);
            emission = mix(emission, meltColor * 4.8f + neonAmber * (ember * 6.8f), botMelt);
            baseReflectivity = mix(baseReflectivity, 0.86f, botMelt);
            roughness = mix(roughness, 0.02f, botMelt);
        }

        if (waterSurface) {
            float viewCosine = saturate(dot(-currentRay.direction, normal));
            float fresnel = pow(1.0f - viewCosine, 2.2f);
            float minRefl = puddleSurface ? 0.68f : 0.52f;
            baseReflectivity = mix(minRefl, 0.95f, fresnel);
        }
        float reflectivity = rayBouncesEnabled ? baseReflectivity : 0.0f;
        float totalLights = uniforms.lightStates.x + uniforms.lightStates.y + uniforms.lightStates.z + uniforms.lightStates.w;
        float lightScale = clamp(totalLights / 0.8f, 0.0f, 1.0f);

        float emitterIntensity = 1.0f;
        if (kind > 3.5f && kind < 4.5f) {
            emitterIntensity = uniforms.lightStates.x;
        } else if (kind > 4.5f && kind < 5.5f) {
            // Si está en la piscina (-6 < x < 3, -5 < z < 2), responde al interruptor de borde de piscina
            bool isPoolStrip = (position.x > -6.0f && position.x < 3.0f && position.z > -5.0f && position.z < 2.0f && position.y > -0.2f && position.y < 0.4f);
            emitterIntensity = isPoolStrip ? uniforms.lightStates.w : 1.0f;
        } else if (kind > 5.5f && kind < 6.5f) {
            emitterIntensity = uniforms.lightStates.y;
        } else if (kind > 6.5f && kind < 7.5f) {
            emitterIntensity = uniforms.lightStates.z;
        } else {
            emitterIntensity = 1.0f;
        }
        emission *= emitterIntensity;

        // 🕳️ Aura de Absorción Fotónica del Fotófago: "Se Come la Luz" suavemente en su entorno sin anillos ni destellos molestos
        float fotofagoDrain = 1.0f;
        for (uint fIdx = 6; fIdx <= 8; ++fIdx) {
            float3 fPos = float3(instances[fIdx].transformationMatrix[3][0],
                                 instances[fIdx].transformationMatrix[3][1],
                                 instances[fIdx].transformationMatrix[3][2]);
            if (fPos.y > -5.0f) {
                float dFotofago = distance(position.xz, fPos.xz);
                float drain = smoothstep(0.8f, 4.5f, dFotofago);
                fotofagoDrain = min(fotofagoDrain, mix(0.35f, 1.0f, drain));
            }
        }

        // Iluminación ambiental nocturna de contraste garantizado para visibilidad total de noche o sin luces
        float ambientBase = (0.042f + 0.048f * lightScale) * fotofagoDrain;
        float skyAmbient = ambientBase + ambientBase * saturate(normal.y);
        float3 direct = albedo * skyAmbient;

        if (uniforms.toolParameters.x > 0.5f && uniforms.toolParameters.x < 1.5f) {
            float3 fromTool = position - uniforms.toolOrigin.xyz;
            float toolDistance = length(fromTool);
            float3 toolToSurface = fromTool / max(toolDistance, 1e-4f);
            float dotDir = dot(toolToSurface, normalize(uniforms.toolDirection.xyz));
            
            // Tactical dual-cone: haz central concentrado de alta intensidad + halo perimetral suave
            float centerBeam = smoothstep(0.85f, 0.985f, dotDir);
            float wideSpill = smoothstep(0.62f, 0.85f, dotDir) * 0.35f;
            float cone = centerBeam + wideSpill;
            
            float battery = clamp(uniforms.toolParameters.y, 0.0f, 1.0f);
            float flicker = (battery < 0.06f && battery > 0.001f) ? (0.88f + 0.12f * sin(uniforms.viewport.z * 10.0f)) : 1.0f;
            if (cone > 0.001f && toolDistance < 38.0f && battery > 0.001f) {
                float incidence = saturate(dot(normal, -toolToSurface));
                float flashlightPower = (52.0f / (1.0f + toolDistance * toolDistance * 0.032f)) * battery * flicker;
                float3 flashlightColor = float3(1.0f, 0.94f, 0.82f);
                direct += albedo * flashlightColor * flashlightPower * cone * (0.22f + incidence * 0.78f);
                
                float3 flashlightHalf = normalize(-toolToSurface - currentRay.direction);
                float flashlightGloss = pow(saturate(dot(normal, flashlightHalf)), 140.0f);
                direct += flashlightColor * flashlightPower * cone * flashlightGloss * 0.40f;
            }
        } else if (uniforms.toolParameters.x > 1.5f && uniforms.toolParameters.x < 2.5f) {
            float primarySpot = laserResult.primaryEnd.w > 0.5f
                ? 1.0f - smoothstep(0.025f, 0.14f, distance(position, laserResult.primaryEnd.xyz))
                : 0.0f;
            float reflectedSpot = laserResult.reflectedEnd.w > 0.5f
                ? 1.0f - smoothstep(0.025f, 0.13f, distance(position, laserResult.reflectedEnd.xyz))
                : 0.0f;
            float laserSpot = max(primarySpot, reflectedSpot * 0.82f);
            emission += float3(7.5f, 0.018f, 0.006f) * laserSpot;
            direct += albedo * float3(2.8f, 0.012f, 0.004f) * laserSpot;
        } else if (uniforms.toolParameters.x > 2.5f && uniforms.toolParameters.y > 1.5f) {
            float mirrorSpot = laserResult.primaryEnd.w > 0.5f
                ? 1.0f - smoothstep(0.025f, 0.16f, distance(position, laserResult.primaryEnd.xyz))
                : 0.0f;
            emission += float3(0.12f, 8.5f, 6.8f) * mirrorSpot;
            direct += albedo * float3(0.08f, 3.2f, 2.5f) * mirrorSpot;
        }

        // Six fixed samples approximate the box emitter without temporal noise.
        // Their averaged visibility creates a stable penumbra around silhouettes.
        constexpr uint lampSampleCount = 6;
        float3 lampOffsets[lampSampleCount] = {
            float3(-0.13f,  0.00f,  0.00f),
            float3( 0.13f,  0.00f,  0.00f),
            float3( 0.00f, -0.21f,  0.00f),
            float3( 0.00f,  0.21f,  0.00f),
            float3( 0.00f,  0.00f, -0.13f),
            float3( 0.00f,  0.00f,  0.13f)
        };
        float3 lampContribution = 0.0f;
        uint activeLampSamples = bounce == 0 ? lampSampleCount : 1;
        for (uint lampSample = 0; lampSample < activeLampSamples; ++lampSample) {
            float3 sampleOffset = bounce == 0 ? lampOffsets[lampSample] : float3(0.0f);
            float3 samplePosition = uniforms.lightPosition.xyz + sampleOffset;
            float3 toLight = samplePosition - position;
            float lightDistance = length(toLight);
            float3 lightDirection = toLight / max(lightDistance, 1e-4f);
            float nDotL = saturate(dot(normal, lightDirection));
            if (nDotL <= 0.0f) {
                continue;
            }

            ray shadowRay;
            shadowRay.origin = position + normal * 0.012f;
            shadowRay.direction = lightDirection;
            // Stop before the 32 x 52 x 32 cm emitter so it cannot shadow itself.
            shadowRay.max_distance = max(0.0f, lightDistance - 0.38f);
            tracer.accept_any_intersection(true);
            auto shadowHit = tracer.intersect(shadowRay, accelerationStructure, 0x03);
            if (shadowHit.type != intersection_type::none) {
                continue;
            }

            float attenuation = uniforms.lightColor.w /
                (1.0f + lightDistance * lightDistance * 0.20f);
            lampContribution += albedo * uniforms.lightColor.xyz * attenuation * nDotL;
            float3 halfDirection = normalize(lightDirection - currentRay.direction);
            float gloss = pow(
                saturate(dot(normal, halfDirection)),
                mix(18.0f, 280.0f, 1.0f - roughness)
            );
            float specularStrength = waterSurface ? 1.15f : 0.14f;
            lampContribution += uniforms.lightColor.xyz * attenuation * gloss * specularStrength;
        }
        direct += lampContribution / float(activeLampSamples);

        if (bounce == 0 && (uniforms.lightStates.y > 0.001f || uniforms.lightStates.z > 0.001f)) {
            float3 neonPositions[2] = {
                float3(-5.25f, 3.45f, -9.34f),
                float3( 5.45f, 3.45f,  9.34f)
            };
            float3 neonColors[2] = {
                float3(1.0f, 0.012f, 0.006f),
                float3(0.008f, 0.18f, 1.0f)
            };
            float neonPowers[2] = {
                38.0f * uniforms.lightStates.y,
                34.0f * uniforms.lightStates.z
            };
            for (uint neonIndex = 0; neonIndex < 2; ++neonIndex) {
                float3 toNeon = neonPositions[neonIndex] - position;
                float neonDistanceSquared = length_squared(toNeon);
                float neonDistance = sqrt(max(neonDistanceSquared, 1e-4f));
                float3 neonDirection = toNeon / neonDistance;
                float neonNDotL = saturate(dot(normal, neonDirection));
                if (neonNDotL > 0.0f && neonDistance < 10.0f) {
                    float neonAttenuation = neonPowers[neonIndex] /
                        (1.0f + neonDistanceSquared * 0.32f);
                    direct += albedo * neonColors[neonIndex] *
                              neonAttenuation * neonNDotL;
                    float3 neonHalf = normalize(neonDirection - currentRay.direction);
                    float neonGloss = pow(saturate(dot(normal, neonHalf)), 190.0f);
                    direct += neonColors[neonIndex] * neonAttenuation * neonGloss *
                              (waterSurface ? 0.82f : 0.08f);
                }
            }
        }

        // Treat the four visible pool strips as one nearest line-area sample.
        if (bounce == 0 && uniforms.lightStates.w > 0.001f) {
            float3 stripSamples[4] = {
                float3(clamp(position.x, -5.35f, 2.35f), 0.48f, -4.20f),
                float3(clamp(position.x, -5.35f, 2.35f), 0.48f,  1.20f),
                float3(-5.35f, 0.48f, clamp(position.z, -4.20f, 1.20f)),
                float3( 2.35f, 0.48f, clamp(position.z, -4.20f, 1.20f))
            };
            float3 stripPoint = stripSamples[0];
            float stripDistanceSquared = length_squared(stripPoint - position);
            for (uint sampleIndex = 1; sampleIndex < 4; ++sampleIndex) {
                float candidateDistanceSquared = length_squared(stripSamples[sampleIndex] - position);
                if (candidateDistanceSquared < stripDistanceSquared) {
                    stripDistanceSquared = candidateDistanceSquared;
                    stripPoint = stripSamples[sampleIndex];
                }
            }

            float stripDistance = sqrt(max(stripDistanceSquared, 1e-4f));
            float3 stripDirection = (stripPoint - position) / stripDistance;
            float stripNDotL = saturate(dot(normal, stripDirection));
            if (stripNDotL > 0.0f && stripDistance < 5.5f) {
                ray stripShadow;
                stripShadow.origin = position + normal * 0.012f;
                stripShadow.direction = stripDirection;
                stripShadow.max_distance = max(0.0f, stripDistance - 0.035f);
                tracer.accept_any_intersection(true);
                auto stripBlocker = tracer.intersect(stripShadow, accelerationStructure, 0x03);
                if (stripBlocker.type == intersection_type::none) {
                    float stripAttenuation = 3.5f * uniforms.lightStates.w /
                        (1.0f + stripDistanceSquared * 0.70f);
                    direct += albedo * float3(1.0f, 0.60f, 0.16f) *
                              stripAttenuation * stripNDotL;
                    float3 stripHalf = normalize(stripDirection - currentRay.direction);
                    float stripGloss = pow(saturate(dot(normal, stripHalf)), 220.0f);
                    direct += float3(1.0f, 0.60f, 0.16f) * stripAttenuation *
                              stripGloss * (waterSurface ? 0.9f : 0.07f);
                }
            }
        }

        // 🌈 Iluminación Prismática Ray-Traced del Gran Salón Arcoíris (Z > 15.0)
        // Empieza completamente apagado cuando las luces están en 0, y despierta con el espectro arcoíris al ir encendiendo las 4 luces
        if (position.z > 14.5f && totalLights > 0.001f) {
            float3 rainbowPos[4] = {
                float3(-13.5f, 5.4f, 32.0f), // Sector 1 (Rojo-Naranja): Cabaña NW + Entrada Arcoíris
                float3( 13.5f, 5.4f, 32.0f), // Sector 2 (Amarillo-Esmeralda): Cabaña NE + Parkour Medio
                float3(-13.5f, 5.4f, 56.0f), // Sector 3 (Cian-Zafiro): Cabaña SW + Parkour Norte
                float3( 13.5f, 5.4f, 56.0f)  // Sector 4 (Violeta-Magenta + Cumbre): Cabaña SE + Santuario Central
            };
            float rainbowPhase = position.z * 0.14f + position.x * 0.08f;
            float3 dynamicSpectrum = 0.52f + 0.48f * cos(rainbowPhase + float3(0.0f, 2.094f, 4.188f));
            float3 rainbowCol[4] = {
                mix(float3(1.0f, 0.22f, 0.08f), dynamicSpectrum, 0.35f),
                mix(float3(0.18f, 1.0f, 0.35f), dynamicSpectrum, 0.35f),
                mix(float3(0.06f, 0.72f, 1.0f), dynamicSpectrum, 0.35f),
                mix(float3(0.92f, 0.15f, 1.0f), dynamicSpectrum, 0.45f)
            };
            float rainbowState[4] = {
                uniforms.lightStates.x,
                uniforms.lightStates.y,
                uniforms.lightStates.z,
                uniforms.lightStates.w
            };
            for (uint rIdx = 0; rIdx < 4; ++rIdx) {
                if (rainbowState[rIdx] > 0.001f) {
                    float3 toR = rainbowPos[rIdx] - position;
                    float rDistSq = length_squared(toR);
                    float rDist = sqrt(max(rDistSq, 1e-4f));
                    float3 rDir = toR / rDist;
                    float rNDotL = saturate(dot(normal, rDir));
                    if (rNDotL > 0.0f && rDist < 38.0f) {
                        float rAtten = (68.0f * rainbowState[rIdx]) / (1.0f + rDistSq * 0.045f);
                        direct += albedo * rainbowCol[rIdx] * rAtten * rNDotL * fotofagoDrain;
                        float3 rHalf = normalize(rDir - currentRay.direction);
                        float rGloss = pow(saturate(dot(normal, rHalf)), mix(24.0f, 240.0f, 1.0f - roughness));
                        direct += rainbowCol[rIdx] * rAtten * rGloss * (0.28f * (1.0f - roughness));
                    }
                }
            }
            // Faro Corona Arcoíris en la Cumbre Central (X = 0, Y = 7.2, Z = 45.0)
            float3 toCenterCrown = float3(0.0f, 7.2f, 45.0f) - position;
            float cDistSq = length_squared(toCenterCrown);
            float cDist = sqrt(max(cDistSq, 1e-4f));
            float3 cDir = toCenterCrown / cDist;
            float cNDotL = saturate(dot(normal, cDir));
            if (cNDotL > 0.0f && cDist < 42.0f) {
                float crownPower = (54.0f * lightScale) / (1.0f + cDistSq * 0.038f);
                direct += albedo * dynamicSpectrum * crownPower * cNDotL * fotofagoDrain;
                float3 cHalf = normalize(cDir - currentRay.direction);
                float cGloss = pow(saturate(dot(normal, cHalf)), mix(24.0f, 240.0f, 1.0f - roughness));
                direct += dynamicSpectrum * crownPower * cGloss * (0.32f * (1.0f - roughness));
            }
        }

        // Every active source uses the same finite planar-mirror light transport.
        if (rayBouncesEnabled && !(kind > 0.5f && kind < 1.5f)) {
            direct += mirroredLightContribution(
                position, normal, currentRay.direction, albedo,
                uniforms.lightPosition.xyz, float3(0.0f), uniforms.lightColor.xyz,
                uniforms.lightColor.w, false
            );

            float3 neonPositions[2] = {
                float3(-5.25f, 3.45f, -9.34f),
                float3( 5.45f, 3.45f,  9.34f)
            };
            float3 neonColors[2] = {
                float3(1.0f, 0.012f, 0.006f),
                float3(0.008f, 0.18f, 1.0f)
            };
            float neonPowers[2] = {
                38.0f * uniforms.lightStates.y,
                34.0f * uniforms.lightStates.z
            };
            for (uint neonIndex = 0; neonIndex < 2; ++neonIndex) {
                direct += mirroredLightContribution(
                    position, normal, currentRay.direction, albedo,
                    neonPositions[neonIndex], float3(0.0f), neonColors[neonIndex],
                    neonPowers[neonIndex], false
                );
            }

            if (uniforms.lightStates.w > 0.001f) {
                float3 stripSources[4] = {
                    float3(clamp(position.x, -5.35f, 2.35f), 0.48f, -4.20f),
                    float3(clamp(position.x, -5.35f, 2.35f), 0.48f,  1.20f),
                    float3(-5.35f, 0.48f, clamp(position.z, -4.20f, 1.20f)),
                    float3( 2.35f, 0.48f, clamp(position.z, -4.20f, 1.20f))
                };
                for (uint stripIndex = 0; stripIndex < 4; ++stripIndex) {
                    direct += mirroredLightContribution(
                        position, normal, currentRay.direction, albedo,
                        stripSources[stripIndex], float3(0.0f), float3(1.0f, 0.60f, 0.16f),
                        2.2f * uniforms.lightStates.w, false
                    );
                }
            }

            if (uniforms.toolParameters.x > 0.5f && uniforms.toolParameters.x < 1.5f) {
                float battery = clamp(uniforms.toolParameters.y, 0.0f, 1.0f);
                if (battery > 0.001f) {
                    direct += mirroredLightContribution(
                        position, normal, currentRay.direction, albedo,
                        uniforms.toolOrigin.xyz, uniforms.toolDirection.xyz,
                        float3(1.0f, 0.88f, 0.68f), 19.0f * battery, true
                    );
                }
            }
        }

        if (rayBouncesEnabled && waterSurface) {
            float3 refractedDirection = refract(currentRay.direction, normal, 1.0f / 1.333f);
            if (length_squared(refractedDirection) > 0.0001f) {
                ray transmissionRay;
                transmissionRay.origin = position - normal * 0.018f;
                transmissionRay.direction = normalize(refractedDirection);
                transmissionRay.max_distance = 14.0f;
                tracer.accept_any_intersection(false);
                auto transmissionHit = tracer.intersect(transmissionRay, accelerationStructure, 0x01);
                if (transmissionHit.type != intersection_type::none) {
                    RTTriangleData underwaterMaterial =
                        *(const device RTTriangleData *)transmissionHit.primitive_data;
                    float3 underwaterPosition = transmissionRay.origin +
                        transmissionRay.direction * transmissionHit.distance;
                    float3 underwaterNormal = transformedNormal(
                        underwaterMaterial.normalRoughness.xyz,
                        instances,
                        transmissionHit.instance_id
                    );
                    if (dot(underwaterNormal, transmissionRay.direction) > 0.0f) {
                        underwaterNormal = -underwaterNormal;
                    }

                    float3 underwaterToLight = uniforms.lightPosition.xyz - underwaterPosition;
                    float underwaterLightDistance = length(underwaterToLight);
                    float underwaterNDotL = saturate(dot(
                        underwaterNormal,
                        underwaterToLight / max(underwaterLightDistance, 1e-4f)
                    ));
                    float underwaterLight = 0.16f + underwaterNDotL *
                        uniforms.lightColor.w /
                        (1.0f + underwaterLightDistance * underwaterLightDistance * 0.28f);
                    float3 bottomColor = underwaterMaterial.albedoReflectivity.xyz *
                        (underwaterLight + float3(0.10f, 0.07f, 0.025f));
                    float3 absorption = exp(
                        -float3(0.20f, 0.075f, 0.045f) * transmissionHit.distance
                    );
                    float3 waterTint = puddleSurface
                        ? float3(0.010f, 0.030f, 0.034f)
                        : float3(0.008f, 0.055f, 0.065f);
                    float3 transmissionColor = bottomColor * absorption +
                        waterTint * (1.0f - absorption);
                    direct = mix(direct, transmissionColor, puddleSurface ? 0.42f : 0.62f);
                }
            }
        }

        accumulated += throughput * (emission + direct * (1.0f - reflectivity));

        if (!rayBouncesEnabled || reflectivity < 0.10f || bounce >= 1) {
            break; // 🚀 Locked 60/120 FPS on iPhone 15 Pro Max!
        }

        if (waterSurface) {
            throughput *= float3(0.98f) * reflectivity;
        } else {
            throughput *= mix(albedo, float3(0.96f), reflectivity) * reflectivity;
        }
        currentRay.origin = position + normal * 0.015f;
        currentRay.direction = normalize(reflect(currentRay.direction, normal));
        currentRay.max_distance = 145.0f;
    }

    if (uniforms.toolParameters.x > 1.5f && uniforms.toolParameters.x < 2.5f && laserResult.primaryEnd.w > 0.5f) {
        float maxDist = uniforms.toolParameters.y > 0.01f ? uniforms.toolParameters.y : 100.0f;
        float3 pStart = laserResult.primaryStart.xyz;
        float3 pEndTarget = laserResult.primaryEnd.xyz;
        float pLen = distance(pStart, pEndTarget);

        if (pLen > 0.001f) {
            float3 pDir = (pEndTarget - pStart) / pLen;
            float primaryCurrentLen = min(pLen, maxDist);
            float3 pEndActual = pStart + pDir * primaryCurrentLen;

            float primaryBeam = laserBeamIntensity(
                primaryOrigin,
                primaryDirection,
                firstSurfaceDistance,
                pStart,
                pEndActual
            );
            if (hasBounce1) {
                primaryBeam += laserBeamIntensity(bounce1Origin, bounce1Direction, bounce1Distance, pStart, pEndActual) * bounce1Throughput.x * 1.15f;
            }

            float reflectedBeam = 0.0f;
            float3 photonFrontPos = pEndActual;

            if (maxDist > pLen && laserResult.reflectedEnd.w > 0.5f) {
                float remDist = maxDist - pLen;
                float3 rStart = pEndTarget;
                float3 rEndTarget = laserResult.reflectedEnd.xyz;
                float rLen = distance(rStart, rEndTarget);

                if (rLen > 0.001f) {
                    float3 rDir = (rEndTarget - rStart) / rLen;
                    float refCurrentLen = min(rLen, remDist);
                    float3 rEndActual = rStart + rDir * refCurrentLen;

                    reflectedBeam = laserBeamIntensity(
                        primaryOrigin,
                        primaryDirection,
                        firstSurfaceDistance,
                        rStart,
                        rEndActual
                    );
                    if (hasBounce1) {
                        reflectedBeam += laserBeamIntensity(bounce1Origin, bounce1Direction, bounce1Distance, rStart, rEndActual) * bounce1Throughput.x * 1.15f;
                    }
                    photonFrontPos = rEndActual;
                }
            }

            // 🔴 Slow-Motion Photon Pulse Head (Leading edge photon packet)
            float3 hitPoint = primaryOrigin + primaryDirection * firstSurfaceDistance;
            float distToPhoton = distance(hitPoint, photonFrontPos);
            float photonPulse = 1.0f - smoothstep(0.04f, 0.28f, distToPhoton);
            float photonGlow = 1.0f - smoothstep(0.01f, 0.65f, distToPhoton);

            accumulated += float3(7.8f, 0.25f, 0.05f) * (primaryBeam * 0.85f + reflectedBeam * 0.65f)
                         + float3(18.0f, 1.2f, 0.3f) * photonPulse
                         + float3(4.5f, 0.4f, 0.1f) * photonGlow;
        }
    } else if (uniforms.toolParameters.x > 2.5f && uniforms.toolParameters.y > 1.5f && laserResult.primaryEnd.w > 0.5f) {
        // 🛡️⚡ Rayo Reflejado por el Escudo Espejo (SOLO cuando un láser enemigo rebota contra el espejo!)
        float3 mStart = laserResult.primaryStart.xyz;
        float3 mEnd = laserResult.primaryEnd.xyz;
        float mirrorBeam = laserBeamIntensity(
            primaryOrigin,
            primaryDirection,
            firstSurfaceDistance,
            mStart,
            mEnd
        );
        if (hasBounce1) {
            mirrorBeam += laserBeamIntensity(bounce1Origin, bounce1Direction, bounce1Distance, mStart, mEnd) * bounce1Throughput.x * 1.15f;
        }
        float3 hitPoint = primaryOrigin + primaryDirection * firstSurfaceDistance;
        float distToTarget = distance(hitPoint, mEnd);
        float impactSpot = 1.0f - smoothstep(0.03f, 0.28f, distToTarget);
        float impactGlow = 1.0f - smoothstep(0.02f, 0.72f, distToTarget);

        // Rayo reflejado sobrecargado cian-esmeralda vibrante
        accumulated += float3(0.18f, 11.5f, 9.2f) * (mirrorBeam * 1.15f)
                     + float3(0.45f, 20.0f, 15.0f) * impactSpot
                     + float3(0.12f, 5.5f, 4.8f) * impactGlow;
    }

    if (laserResult.bot0End.w > 0.5f) {
        float botBeam = laserBeamIntensity(
            primaryOrigin,
            primaryDirection,
            firstSurfaceDistance,
            laserResult.bot0Start.xyz,
            laserResult.bot0End.xyz
        );
        if (hasBounce1) {
            botBeam += laserBeamIntensity(bounce1Origin, bounce1Direction, bounce1Distance, laserResult.bot0Start.xyz, laserResult.bot0End.xyz) * bounce1Throughput.x * 1.15f;
        }
        accumulated += float3(9.5f, 0.08f, 0.02f) * (botBeam * 0.95f);
    }

    if (laserResult.bot1End.w > 0.5f) {
        float botBeam = laserBeamIntensity(
            primaryOrigin,
            primaryDirection,
            firstSurfaceDistance,
            laserResult.bot1Start.xyz,
            laserResult.bot1End.xyz
        );
        if (hasBounce1) {
            botBeam += laserBeamIntensity(bounce1Origin, bounce1Direction, bounce1Distance, laserResult.bot1Start.xyz, laserResult.bot1End.xyz) * bounce1Throughput.x * 1.15f;
        }
        accumulated += float3(9.5f, 0.08f, 0.02f) * (botBeam * 0.95f);
    }

    if (laserResult.bot2End.w > 0.5f) {
        float botBeam = laserBeamIntensity(
            primaryOrigin,
            primaryDirection,
            firstSurfaceDistance,
            laserResult.bot2Start.xyz,
            laserResult.bot2End.xyz
        );
        if (hasBounce1) {
            botBeam += laserBeamIntensity(bounce1Origin, bounce1Direction, bounce1Distance, laserResult.bot2Start.xyz, laserResult.bot2End.xyz) * bounce1Throughput.x * 1.15f;
        }
        accumulated += float3(9.2f, 0.14f, 4.5f) * (botBeam * 0.95f);
    }

    if (laserResult.bot3End.w > 0.5f) {
        float botBeam = laserBeamIntensity(
            primaryOrigin,
            primaryDirection,
            firstSurfaceDistance,
            laserResult.bot3Start.xyz,
            laserResult.bot3End.xyz
        );
        if (hasBounce1) {
            botBeam += laserBeamIntensity(bounce1Origin, bounce1Direction, bounce1Distance, laserResult.bot3Start.xyz, laserResult.bot3End.xyz) * bounce1Throughput.x * 1.15f;
        }
        accumulated += float3(8.5f, 0.12f, 6.2f) * (botBeam * 0.95f);
    }

    if (laserResult.bot4End.w > 0.5f) {
        float botBeam = laserBeamIntensity(
            primaryOrigin,
            primaryDirection,
            firstSurfaceDistance,
            laserResult.bot4Start.xyz,
            laserResult.bot4End.xyz
        );
        if (hasBounce1) {
            botBeam += laserBeamIntensity(bounce1Origin, bounce1Direction, bounce1Distance, laserResult.bot4Start.xyz, laserResult.bot4End.xyz) * bounce1Throughput.x * 1.15f;
        }
        accumulated += float3(7.5f, 0.10f, 8.8f) * (botBeam * 1.05f);
    }

    if (isMirrorViewport) {
        // 🪞 Tinte óptico de cristal de espejo y Retícula de Puntería de Talento en la mitad derecha
        bool isDeflecting = (uniforms.toolParameters.y > 1.5f);
        float3 mirrorTint = isDeflecting ? float3(0.88f, 1.12f, 1.05f) : float3(0.86f, 1.04f, 1.14f);
        accumulated *= mirrorTint;

        float aspectHalf = (float(width) * 0.5f) / max(1.0f, float(height));
        float2 reticlePos = float2(mirrorLocalUV.x * aspectHalf, mirrorLocalUV.y);
        float rDist = length(reticlePos);
        float ring = smoothstep(0.012f, 0.003f, abs(rDist - 0.075f));
        float centerDot = 1.0f - smoothstep(0.005f, 0.014f, rDist);
        float crossH = (abs(reticlePos.y) < 0.0045f && abs(reticlePos.x) > 0.028f && abs(reticlePos.x) < 0.125f) ? 1.0f : 0.0f;
        float crossV = (abs(reticlePos.x) < 0.0045f && abs(reticlePos.y) > 0.028f && abs(reticlePos.y) < 0.125f) ? 1.0f : 0.0f;
        float reticleMask = saturate(ring + centerDot + (crossH + crossV) * 0.85f);
        float3 reticleColor = isDeflecting ? float3(0.20f, 8.0f, 4.5f) : float3(0.10f, 4.5f, 6.5f);
        accumulated = mix(accumulated, reticleColor, reticleMask * 0.85f);

        // Borde biselado de espejo en el contorno de la mitad derecha
        float edgeDist = max(abs(mirrorLocalUV.x), abs(mirrorLocalUV.y));
        if (edgeDist > 0.965f) {
            accumulated += isDeflecting ? float3(0.15f, 4.5f, 3.0f) : float3(0.08f, 2.5f, 3.8f);
        }
    }

    // 🌊 Complete Aquatic Realm: Surface Pool & Subterranean Ocean Chamber
    float3 cameraPos = uniforms.cameraPosition.xyz;
    bool isCameraInPoolXZ = (cameraPos.x > -5.35f && cameraPos.x < 2.35f && cameraPos.z > -4.20f && cameraPos.z < 1.20f);
    bool isSubterranean = (cameraPos.y < -4.75f);
    bool isUnderwater = (isCameraInPoolXZ && cameraPos.y < 0.38f) || isSubterranean;

    if (isUnderwater) {
        float simT = uniforms.waterSimulation.x * 2.5f;

        // 1. Underwater Volumetric Absorption & Abyssal Aquatic Tint
        float depth = max(0.0f, -cameraPos.y);
        float depthFactor = saturate(depth / 10.0f);
        float3 deepWaterTint = mix(float3(0.015f, 0.35f, 0.55f), float3(0.005f, 0.12f, 0.28f), depthFactor);

        // 2. Dynamic aquatic caustics dancing on surfaces
        float3 worldHit = cameraPos + primaryDirection * firstSurfaceDistance;
        float causticPattern = saturate(
            sin(worldHit.x * 1.5f + simT) *
            cos(worldHit.z * 1.5f + simT * 0.9f) *
            sin((worldHit.x + worldHit.z) * 0.8f + simT * 1.3f) * 0.5f + 0.5f
        );
        float distFade = saturate(1.0f - firstSurfaceDistance * 0.045f);
        accumulated += float3(0.08f, 0.52f, 0.72f) * causticPattern * distFade * 0.50f;

        // 3. Volumetric distance fog in water (distant architecture fades into mystical blue abyss)
        float fogAmount = saturate(firstSurfaceDistance * 0.038f);
        accumulated = mix(accumulated, deepWaterTint, fogAmount * 0.72f);

        // 4. Shimmering Pool Skylight looking up towards the pool surface
        if (primaryDirection.y > 0.05f) {
            float distToSurface = max(0.1f, (0.45f - cameraPos.y) / max(0.01f, primaryDirection.y));
            if (distToSurface < firstSurfaceDistance) {
                float2 surfXZ = cameraPos.xz + primaryDirection.xz * distToSurface;
                if (surfXZ.x > -5.35f && surfXZ.x < 2.35f && surfXZ.y > -4.20f && surfXZ.y < 1.20f) {
                    float wSurf = sin(surfXZ.x * 1.2f + simT) * cos(surfXZ.y * 1.2f + simT * 1.2f);
                    float3 surfaceGlow = mix(float3(0.35f, 0.85f, 1.0f), float3(1.0f, 1.0f, 1.0f), saturate(wSurf * 0.5f + 0.5f));
                    accumulated += surfaceGlow * 0.75f;
                }
            }
        }
    }

    output.write(half4(half3(toneMap(clamp(accumulated, 0.0f, 96.0f))), half(1.0f)), tid);
}
