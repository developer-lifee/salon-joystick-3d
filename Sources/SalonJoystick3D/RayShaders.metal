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

    // 1. Ground / Floor Plane (y = 0.0)
    if (r.direction.y < -0.001f) {
        float tFloor = (0.0f - r.origin.y) / r.direction.y;
        if (tFloor > 0.01f && tFloor < result.distance) {
            result.hit = true;
            result.distance = tFloor;
            result.position = r.origin + r.direction * tFloor;
            result.normal = float3(0.0f, 1.0f, 0.0f);
            
            bool insidePool = (result.position.x > -5.35f && result.position.x < 2.35f &&
                               result.position.z > -4.20f && result.position.z < 1.20f);
            if (insidePool) {
                float2 grid = fract(result.position.xz * 1.5f);
                float grout = step(0.04f, grid.x) * step(0.04f, grid.y);
                result.albedo = mix(float3(0.02f, 0.25f, 0.42f), float3(0.12f, 0.65f, 0.85f), grout);
                result.kind = 3.0f;
            } else {
                float2 grid = fract(result.position.xz * 0.8f);
                float grout = step(0.03f, grid.x) * step(0.03f, grid.y);
                result.albedo = mix(float3(0.15f, 0.16f, 0.18f), float3(0.42f, 0.45f, 0.48f), grout);
                result.kind = 0.0f;
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

    // 7. Toboggan Water Slide Chute (Slanted chute from y=4.8 down to y=0.45)
    float3 slideStart = float3(-3.8f, 4.8f, -15.8f);
    float3 slideEnd = float3(-2.5f, 0.45f, -4.5f);
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
    position.y = -0.07f + waterState.sample(waterSampler, uv).r;
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
    if (uniforms.toolParameters.x < 1.5f || uniforms.toolParameters.x > 2.5f) {
        return;
    }

    intersector<triangle_data, instancing> tracer;
    tracer.assume_geometry_type(geometry_type::triangle);
    tracer.force_opacity(forced_opacity::opaque);
    tracer.accept_any_intersection(false);

    if (uniforms.waterSimulation.z < 0.5f) {
        ray cameraAimRay;
        cameraAimRay.origin = uniforms.cameraPosition.xyz;
        cameraAimRay.direction = normalize(uniforms.cameraForward.xyz);
        cameraAimRay.max_distance = 30.0f;
        auto cameraAimHit = tracer.intersect(cameraAimRay, accelerationStructure, 0x05);
        float3 aimTarget = cameraAimHit.type == intersection_type::none
            ? cameraAimRay.origin + cameraAimRay.direction * cameraAimRay.max_distance
            : cameraAimRay.origin + cameraAimRay.direction * cameraAimHit.distance;
        direction = normalize(aimTarget - origin);
    }

    ray laserRay;
    laserRay.origin = origin;
    laserRay.direction = direction;
    laserRay.max_distance = 30.0f;
    auto hit = tracer.intersect(laserRay, accelerationStructure, 0x05);
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
    secondaryRay.max_distance = 22.0f;
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
    if (isSplitScreen) {
        uint halfHeight = height / 2;
        bool isBottomViewport = (tid.y >= halfHeight);
        float subScreenHeight = float(halfHeight);
        float localY = isBottomViewport ? float(tid.y - halfHeight) : float(tid.y);
        uv.y = ((localY + 0.5f) / subScreenHeight) * 2.0f - 1.0f;
        uv.y = -uv.y;

        if (isBottomViewport) {
            float3 p2Origin = float3(-3.8f, 1.15f, -3.8f);
            float3 p2Forward = normalize(float3(0.0f, 0.5f, 0.0f) - p2Origin);
            float3 p2Right = normalize(cross(p2Forward, float3(0.0f, 1.0f, 0.0f)));
            float3 p2Up = cross(p2Right, p2Forward);
            currentRay.origin = p2Origin;
            currentRay.direction = normalize(uv.x * p2Right + uv.y * p2Up + p2Forward);
        }

        if (abs(int(tid.y) - int(halfHeight)) <= 2) {
            output.write(half4(0.0h, 0.85h, 1.0h, 1.0h), tid);
            return;
        }
    }

    currentRay.max_distance = 80.0f;
    float3 primaryDirection = currentRay.direction;
    float firstSurfaceDistance = currentRay.max_distance;

    intersector<triangle_data, instancing> tracer;
    tracer.assume_geometry_type(geometry_type::triangle);
    tracer.force_opacity(forced_opacity::opaque);

    float3 accumulated = 0.0f;
    float3 throughput = 1.0f;

    for (uint bounce = 0; bounce < 3; ++bounce) {
        tracer.accept_any_intersection(false);
        uint rayMask = bounce == 0 && firstPerson ? 0x05 : 0x07;
        auto hit = tracer.intersect(currentRay, accelerationStructure, rayMask);
        float3 position;
        float3 normal;
        float3 albedo;
        float kind;
        float baseReflectivity = 0.05f;
        float roughness = 0.5f;

        if (hit.type != intersection_type::none) {
            if (bounce == 0) {
                firstSurfaceDistance = hit.distance;
            }
            RTTriangleData material = *(const device RTTriangleData *)hit.primitive_data;
            position = currentRay.origin + currentRay.direction * hit.distance;
            normal = transformedNormal(material.normalRoughness.xyz, instances, hit.instance_id);
            if (dot(normal, currentRay.direction) > 0.0f) {
                normal = -normal;
            }
            kind = material.emissionKind.w;
            albedo = material.albedoReflectivity.xyz;
            baseReflectivity = material.albedoReflectivity.w;
            roughness = material.normalRoughness.w;
        } else {
            AnalyticalHit analytical = analyticalPatioIntersect(currentRay);
            // 🤖 3D Bot Analytical Fallback for Simulator & Legacy Non-RT iPhones
            for (uint b = 0; b < 5; ++b) {
                float3 botCenter = float3(instances[4 + b].transformationMatrix[3].x,
                                          instances[4 + b].transformationMatrix[3].y + 0.9f,
                                          instances[4 + b].transformationMatrix[3].z);
                if (botCenter.y > -5.0f) {
                    float3 oc = currentRay.origin - botCenter;
                    float bProj = dot(oc, currentRay.direction);
                    float c = dot(oc, oc) - 0.45f * 0.45f;
                    float disc = bProj * bProj - c;
                    if (disc > 0.0f) {
                        float tBot = -bProj - sqrt(disc);
                        if (tBot > 0.01f && tBot < analytical.distance) {
                            analytical.hit = true;
                            analytical.distance = tBot;
                            analytical.position = currentRay.origin + currentRay.direction * tBot;
                            analytical.normal = normalize(analytical.position - botCenter);
                            analytical.albedo = float3(0.85f, 0.25f, 0.25f);
                            analytical.kind = 0.0f;
                        }
                    }
                }
            }

            if (!analytical.hit) {
                accumulated += throughput * nightSky(currentRay.direction);
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

        bool poolWaterSurface = kind > 1.5f && kind < 2.5f;
        bool puddleSurface = kind > 7.5f && kind < 8.5f;
        bool waterSurface = poolWaterSurface || puddleSurface;
        if (poolWaterSurface) {
            normal = simulatedWaterNormal(position, waterState);
        } else if (puddleSurface) {
            normal = shallowPuddleNormal(position, uniforms.waterSimulation.y);
        } else if (kind > 2.5f && kind < 3.5f) {
            float2 grid = fract(position.xz * 2.2f);
            float grout = step(0.04f, grid.x) * step(0.04f, grid.y);
            float3 groutBump = float3((1.0f - grout) * 0.12f, 0.0f, (1.0f - grout) * 0.12f);
            normal = normalize(normal + groutBump);
        }

        if ((kind > 1.5f && kind < 3.5f) || puddleSurface) {
            float viewCosine = saturate(dot(-currentRay.direction, normal));
            float fresnel = pow(1.0f - viewCosine, 5.0f);
            float maximumReflectivity = waterSurface ? 0.92f : 0.96f;
            baseReflectivity = mix(baseReflectivity, maximumReflectivity, fresnel);
        }
        float reflectivity = rayBouncesEnabled ? baseReflectivity : 0.0f;
        float3 emission = float3(0.0f);
        float emitterIntensity = 1.0f;
        if (kind > 3.5f && kind < 4.5f) emitterIntensity = uniforms.lightStates.x;
        if (kind > 4.5f && kind < 5.5f) emitterIntensity = uniforms.lightStates.w;
        if (kind > 5.5f && kind < 6.5f) emitterIntensity = uniforms.lightStates.y;
        if (kind > 6.5f && kind < 7.5f) emitterIntensity = uniforms.lightStates.z;
        emission *= emitterIntensity;
        float ambientBase = 0.032f;
        float skyAmbient = ambientBase + ambientBase * saturate(normal.y);
        float3 direct = albedo * skyAmbient;

        if (uniforms.toolParameters.x > 0.5f && uniforms.toolParameters.x < 1.5f) {
            float3 fromTool = position - uniforms.toolOrigin.xyz;
            float toolDistance = length(fromTool);
            float3 toolToSurface = fromTool / max(toolDistance, 1e-4f);
            float cone = smoothstep(
                0.90f,
                0.975f,
                dot(toolToSurface, normalize(uniforms.toolDirection.xyz))
            );
            float incidence = saturate(dot(normal, -toolToSurface));
            float flashlightPower = 19.0f / (1.0f + toolDistance * toolDistance * 0.075f);
            float3 flashlightColor = float3(1.0f, 0.88f, 0.68f);
            direct += albedo * flashlightColor * flashlightPower * cone *
                      (0.16f + incidence * 0.84f);
            float3 flashlightHalf = normalize(-toolToSurface - currentRay.direction);
            float flashlightGloss = pow(saturate(dot(normal, flashlightHalf)), 180.0f);
            direct += flashlightColor * flashlightPower * cone * flashlightGloss * 0.32f;
        } else if (uniforms.toolParameters.x > 1.5f) {
            float primarySpot = laserResult.primaryEnd.w > 0.5f
                ? 1.0f - smoothstep(0.025f, 0.14f, distance(position, laserResult.primaryEnd.xyz))
                : 0.0f;
            float reflectedSpot = laserResult.reflectedEnd.w > 0.5f
                ? 1.0f - smoothstep(0.025f, 0.13f, distance(position, laserResult.reflectedEnd.xyz))
                : 0.0f;
            float laserSpot = max(primarySpot, reflectedSpot * 0.82f);
            emission += float3(7.5f, 0.018f, 0.006f) * laserSpot;
            direct += albedo * float3(2.8f, 0.012f, 0.004f) * laserSpot;
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
                direct += mirroredLightContribution(
                    position, normal, currentRay.direction, albedo,
                    uniforms.toolOrigin.xyz, uniforms.toolDirection.xyz,
                    float3(1.0f, 0.88f, 0.68f), 19.0f, true
                );
            }
        }

        if (rayBouncesEnabled && waterSurface) {
            float3 refractedDirection = refract(currentRay.direction, normal, 1.0f / 1.333f);
            if (length_squared(refractedDirection) > 0.0001f) {
                ray transmissionRay;
                transmissionRay.origin = position - normal * 0.018f;
                transmissionRay.direction = normalize(refractedDirection);
                transmissionRay.max_distance = 4.0f;
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
                    direct = mix(direct, transmissionColor, puddleSurface ? 0.82f : 0.95f);
                }
            }
        }

        accumulated += throughput * (emission + direct * (1.0f - reflectivity));

        if (!rayBouncesEnabled || reflectivity < 0.18f || bounce >= 1) {
            break; // 🚀 Locked 60/120 FPS on iPhone 15 Pro Max!
        }

        if (waterSurface) {
            throughput *= float3(0.96f) * reflectivity;
        } else {
            throughput *= mix(albedo, float3(0.96f), reflectivity) * reflectivity;
        }
        currentRay.origin = position + normal * 0.015f;
        currentRay.direction = normalize(reflect(currentRay.direction, normal));
        currentRay.max_distance = 80.0f;
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
                uniforms.cameraPosition.xyz,
                primaryDirection,
                firstSurfaceDistance,
                pStart,
                pEndActual
            );

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
                        uniforms.cameraPosition.xyz,
                        primaryDirection,
                        firstSurfaceDistance,
                        rStart,
                        rEndActual
                    );
                    photonFrontPos = rEndActual;
                }
            }

            // 🔴 Slow-Motion Photon Pulse Head (Leading edge photon packet)
            float3 hitPoint = uniforms.cameraPosition.xyz + primaryDirection * firstSurfaceDistance;
            float distToPhoton = distance(hitPoint, photonFrontPos);
            float photonPulse = 1.0f - smoothstep(0.04f, 0.28f, distToPhoton);
            float photonGlow = 1.0f - smoothstep(0.01f, 0.65f, distToPhoton);

            accumulated += float3(7.8f, 0.25f, 0.05f) * (primaryBeam * 0.85f + reflectedBeam * 0.65f)
                         + float3(18.0f, 1.2f, 0.3f) * photonPulse
                         + float3(4.5f, 0.4f, 0.1f) * photonGlow;
        }
    }

    if (laserResult.bot0End.w > 0.5f) {
        float botBeam = laserBeamIntensity(
            uniforms.cameraPosition.xyz,
            primaryDirection,
            firstSurfaceDistance,
            laserResult.bot0Start.xyz,
            laserResult.bot0End.xyz
        );
        accumulated += float3(9.5f, 0.08f, 0.02f) * (botBeam * 0.95f);
    }

    if (laserResult.bot1End.w > 0.5f) {
        float botBeam = laserBeamIntensity(
            uniforms.cameraPosition.xyz,
            primaryDirection,
            firstSurfaceDistance,
            laserResult.bot1Start.xyz,
            laserResult.bot1End.xyz
        );
        accumulated += float3(9.5f, 0.08f, 0.02f) * (botBeam * 0.95f);
    }

    if (laserResult.bot2End.w > 0.5f) {
        float botBeam = laserBeamIntensity(
            uniforms.cameraPosition.xyz,
            primaryDirection,
            firstSurfaceDistance,
            laserResult.bot2Start.xyz,
            laserResult.bot2End.xyz
        );
        accumulated += float3(9.5f, 0.08f, 0.02f) * (botBeam * 0.95f);
    }

    if (laserResult.bot3End.w > 0.5f) {
        float botBeam = laserBeamIntensity(
            uniforms.cameraPosition.xyz,
            primaryDirection,
            firstSurfaceDistance,
            laserResult.bot3Start.xyz,
            laserResult.bot3End.xyz
        );
        accumulated += float3(9.5f, 0.08f, 0.02f) * (botBeam * 0.95f);
    }

    if (laserResult.bot4End.w > 0.5f) {
        float botBeam = laserBeamIntensity(
            uniforms.cameraPosition.xyz,
            primaryDirection,
            firstSurfaceDistance,
            laserResult.bot4Start.xyz,
            laserResult.bot4End.xyz
        );
        accumulated += float3(9.5f, 0.08f, 0.02f) * (botBeam * 0.95f);
    }

    // 🌊 Clean Clear Pool Water & Underwater Pool Floor Grid
    float3 cameraPos = uniforms.cameraPosition.xyz;
    bool isCameraInPoolXZ = (cameraPos.x > -5.35f && cameraPos.x < 2.35f && cameraPos.z > -4.20f && cameraPos.z < 1.20f);
    if (isCameraInPoolXZ && cameraPos.y < 0.38f) {
        float simT = uniforms.waterSimulation.x * 2.5f;

        // 1. Pool Floor Tile Rendering (Floor at y = -3.5)
        if (primaryDirection.y < -0.01f) {
            float tFloor = (-3.5f - cameraPos.y) / primaryDirection.y;
            if (tFloor > 0.01f && tFloor < firstSurfaceDistance) {
                float3 pFloor = cameraPos + primaryDirection * tFloor;
                if (pFloor.x > -5.35f && pFloor.x < 2.35f && pFloor.z > -4.20f && pFloor.z < 1.20f) {
                    float2 tileUV = pFloor.xz * 1.5f;
                    float2 grid = fract(tileUV);
                    float grout = step(0.04f, grid.x) * step(0.04f, grid.y);
                    float3 poolTileColor = mix(float3(0.05f, 0.35f, 0.55f), float3(0.18f, 0.75f, 0.92f), grout);
                    
                    // Wave caustics reflection on floor
                    float caustic = saturate(sin(pFloor.x * 1.8f + simT) * cos(pFloor.z * 1.8f + simT * 1.2f) * 0.5f + 0.5f);
                    poolTileColor += float3(0.15f, 0.45f, 0.65f) * caustic * 0.45f;
                    
                    float fogFactor = saturate(tFloor * 0.08f);
                    float3 waterColor = mix(poolTileColor, float3(0.02f, 0.25f, 0.45f), fogFactor);
                    accumulated = mix(accumulated, waterColor, 0.85f);
                }
            }
        }

        // 2. Shimmering Surface Water Ceiling (Looking up)
        if (primaryDirection.y > 0.05f) {
            float distToSurface = max(0.1f, (0.48f - cameraPos.y) / max(0.01f, primaryDirection.y));
            if (distToSurface < firstSurfaceDistance) {
                float2 surfXZ = cameraPos.xz + primaryDirection.xz * distToSurface;
                float wSurf = sin(surfXZ.x * 0.85f + simT) * cos(surfXZ.y * 0.85f + simT * 1.2f);
                float3 surfaceLight = mix(float3(0.15f, 0.72f, 0.95f), float3(0.85f, 0.98f, 1.0f), saturate(wSurf * 0.5f + 0.5f));
                accumulated += surfaceLight * 0.45f;
            }
        }

        // 3. Clear Underwater Tint Filter
        float depthFactor = saturate((cameraPos.y + 3.5f) / 4.0f);
        float3 waterTint = mix(float3(0.01f, 0.12f, 0.25f), float3(0.05f, 0.45f, 0.70f), depthFactor);
        accumulated = mix(accumulated, waterTint, 0.35f);
    }

    output.write(half4(half3(toneMap(clamp(accumulated, 0.0f, 96.0f))), half(1.0f)), tid);
}
