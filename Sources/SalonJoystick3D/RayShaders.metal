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
    return mix(float3(0.008f, 0.012f, 0.024f),
               float3(0.018f, 0.028f, 0.055f), horizon);
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
    float radius = 0.012f + cameraDistance * 0.0011f;
    return 1.0f - smoothstep(radius, radius * 2.6f, distance);
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
    if (uniforms.toolParameters.x < 1.5f) {
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
        result.primaryEnd = float4(origin + direction * laserRay.max_distance, 1.0f);
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
        if (hit.type == intersection_type::none) {
            accumulated += throughput * nightSky(currentRay.direction);
            break;
        }
        if (bounce == 0) {
            firstSurfaceDistance = hit.distance;
        }

        RTTriangleData material = *(const device RTTriangleData *)hit.primitive_data;
        float3 position = currentRay.origin + currentRay.direction * hit.distance;
        float3 normal = transformedNormal(material.normalRoughness.xyz, instances, hit.instance_id);
        if (dot(normal, currentRay.direction) > 0.0f) {
            normal = -normal;
        }

        float kind = material.emissionKind.w;
        bool poolWaterSurface = kind > 1.5f && kind < 2.5f;
        bool puddleSurface = kind > 7.5f && kind < 8.5f;
        bool waterSurface = poolWaterSurface || puddleSurface;
        if (poolWaterSurface) {
            normal = simulatedWaterNormal(position, waterState);
        } else if (puddleSurface) {
            normal = shallowPuddleNormal(position, uniforms.waterSimulation.y);
        }

        float3 albedo = material.albedoReflectivity.xyz;
        float baseReflectivity = material.albedoReflectivity.w;
        if ((kind > 1.5f && kind < 3.5f) || puddleSurface) {
            float viewCosine = saturate(dot(-currentRay.direction, normal));
            float fresnel = pow(1.0f - viewCosine, 5.0f);
            float maximumReflectivity = waterSurface ? 0.92f : 0.96f;
            baseReflectivity = mix(baseReflectivity, maximumReflectivity, fresnel);
        }
        float reflectivity = rayBouncesEnabled ? baseReflectivity : 0.0f;
        float3 emission = material.emissionKind.xyz;
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
                mix(18.0f, 280.0f, 1.0f - material.normalRoughness.w)
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

        if (!rayBouncesEnabled || reflectivity < 0.04f || bounce == 2) {
            break;
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

    if (uniforms.toolParameters.x > 1.5f && laserResult.primaryEnd.w > 0.5f) {
        float primaryBeam = laserBeamIntensity(
            uniforms.cameraPosition.xyz,
            primaryDirection,
            firstSurfaceDistance,
            laserResult.primaryStart.xyz,
            laserResult.primaryEnd.xyz
        );
        float reflectedBeam = laserResult.reflectedEnd.w > 0.5f
            ? laserBeamIntensity(
                uniforms.cameraPosition.xyz,
                primaryDirection,
                firstSurfaceDistance,
                laserResult.primaryEnd.xyz,
                laserResult.reflectedEnd.xyz
            )
            : 0.0f;
        accumulated += float3(5.5f, 0.008f, 0.003f) *
                       (primaryBeam * 0.62f + reflectedBeam * 0.46f);
    }

    output.write(half4(half3(toneMap(clamp(accumulated, 0.0f, 96.0f))), half(1.0f)), tid);
}
