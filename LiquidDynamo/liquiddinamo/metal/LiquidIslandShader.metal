//
//  LiquidIslandShader.metal
//  LiquidDynamo
//
//  Metal Signed-Distance Field (SDF) and 3D Lighting Shader for Liquid Island Engine.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - Signed Distance Field Primitives

// Signed distance to a 2D rounded box with individual center and half-extents
inline float sdRoundedBox(float2 p, float2 halfSize, float radius) {
    float r = clamp(radius, 0.0f, min(halfSize.x, halfSize.y));
    float2 q = abs(p) - halfSize + float2(r);
    return min(max(q.x, q.y), 0.0f) + length(max(q, 0.0f)) - r;
}

// Polynomial smooth minimum (cubic smin for organic viscous gooey neck)
inline float smin(float a, float b, float k) {
    if (k <= 0.001f) {
        return min(a, b);
    }
    float h = max(k - abs(a - b), 0.0f) / k;
    return min(a, b) - h * h * h * k * (1.0f / 6.0f);
}

// Evaluate composite distance across up to 8 lobes
// Each lobe format (8 floats): [centerX, centerY, halfW, halfH, cornerRadius, isActive, weight, reserved]
inline float evaluateCompositeSDF(
    float2 p,
    device const float *lobes,
    int lobeCount,
    float k
) {
    float d = 10000.0f;
    bool hasActive = false;

    for (int i = 0; i < lobeCount && i < 8; ++i) {
        int base = i * 8;
        float isActive = lobes[base + 5];
        if (isActive < 0.5f) {
            continue;
        }

        float2 center = float2(lobes[base + 0], lobes[base + 1]);
        float2 halfSize = float2(lobes[base + 2], lobes[base + 3]);
        float radius = lobes[base + 4];

        float lobeDist = sdRoundedBox(p - center, halfSize, radius);

        if (!hasActive) {
            d = lobeDist;
            hasActive = true;
        } else {
            d = smin(d, lobeDist, k);
        }
    }

    return hasActive ? d : 10000.0f;
}

// MARK: - Stitchable Shader for SwiftUI ShaderLibrary

[[stitchable]] half4 liquidIsland(
    float2 position,
    half4 baseColor,
    float4 bounds,               // (x, y, width, height)
    device const float *lobeData,// 8 lobes * 8 floats = 64 floats
    float lobeCountFloat,
    float k,
    float4 lightDirAndTight,     // (lightX, lightY, lightZ, tightPower)
    float4 lightingParams,       // (tightSpecIntensity, broadSpecIntensity, fresnelIntensity, innerDepth)
    float4 tintColor             // (r, g, b, a)
) {
    int lobeCount = int(lobeCountFloat);
    // 1. Evaluate distance field at pixel position
    float d = evaluateCompositeSDF(position, lobeData, lobeCount, k);

    // 2. High-quality anti-aliased alpha boundary
    float alpha = smoothstep(0.75f, -0.75f, d);
    if (alpha <= 0.001f) {
        return half4(0.0h, 0.0h, 0.0h, 0.0h);
    }

    // 3. Normal vector estimation via finite differences
    float eps = 1.0f;
    float dXPlus  = evaluateCompositeSDF(position + float2(eps, 0.0f), lobeData, lobeCount, k);
    float dXMinus = evaluateCompositeSDF(position - float2(eps, 0.0f), lobeData, lobeCount, k);
    float dYPlus  = evaluateCompositeSDF(position + float2(0.0f, eps), lobeData, lobeCount, k);
    float dYMinus = evaluateCompositeSDF(position - float2(0.0f, eps), lobeData, lobeCount, k);

    float2 grad = float2(dXPlus - dXMinus, dYPlus - dYMinus) * 0.5f;
    float gradLenSq = dot(grad, grad);
    float nz = sqrt(max(0.0f, 1.0f - min(gradLenSq, 1.0f)));
    float3 normal = normalize(float3(grad.x, grad.y, nz));

    // 4. 3D Lighting Calculations
    float3 lightDir = normalize(float3(lightDirAndTight.x, lightDirAndTight.y, lightDirAndTight.z));
    float3 viewDir = float3(0.0f, 0.0f, 1.0f);
    float3 halfVec = normalize(lightDir + viewDir);

    float nDotH = max(0.0f, dot(normal, halfVec));
    float tightPower = max(2.0f, lightDirAndTight.w);
    float tightSpec = pow(nDotH, tightPower) * lightingParams.x;
    float broadSpec = pow(nDotH, 5.0f) * lightingParams.y;

    // Fresnel rim light (strongest at grazing angles near shape border)
    float fresnel = pow(1.0f - normal.z, 2.5f) * lightingParams.z;

    // Soft inner shadow / depth
    float innerShading = smoothstep(-18.0f, -2.0f, d) * lightingParams.w;

    // 5. Color composition
    // Master Spec Rule: Base fill must be pure optical black to seamlessly match hardware notch
    float3 rgb = float3(0.0f, 0.0f, 0.0f);

    // Add subtle ambient tint refraction inside glass depth
    rgb += tintColor.rgb * innerShading * 0.12f;

    // Add tight glossy specular highlight (white with slight tint fringe)
    float3 tightSpecColor = mix(float3(1.0f), tintColor.rgb, 0.35f) * tightSpec;
    rgb += tightSpecColor;

    // Add broad specular sheen
    rgb += tintColor.rgb * broadSpec;

    // Add fresnel rim along fluid perimeter
    rgb += tintColor.rgb * fresnel;

    // Multiply by boundary alpha for anti-aliasing
    return half4(half3(rgb * alpha), half(alpha));
}
