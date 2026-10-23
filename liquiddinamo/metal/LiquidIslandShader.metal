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

// MARK: - Procedural Water Bottom Evaluation

inline float evaluateWaterDisplacement(
    float2 p,
    device const float *lobes,
    int lobeCount,
    float4 waterParams,  // (sagAmount, irregularity, sloshPhase, meniscusIntensity)
    float4 waterParams2  // (seed, time, cursorLean, reserved)
) {
    if (waterParams.x <= 0.001f || lobeCount < 2) {
        return 0.0f;
    }

    // Body is lobe 1 (offset 8 floats: [centerX, centerY, halfW, halfH, cornerRadius, isActive, weight, reserved])
    int base = 8;
    float bodyActive = lobes[base + 5];
    if (bodyActive < 0.5f) {
        return 0.0f;
    }

    float centerX = lobes[base + 0];
    float centerY = lobes[base + 1];
    float halfW   = lobes[base + 2];
    float halfH   = lobes[base + 3];

    // Only displace the bottom edge / lower half of the body
    if (p.y < centerY - 2.0f) {
        return 0.0f;
    }

    float u = (p.x - centerX) / max(halfW, 1.0f);
    if (abs(u) >= 1.08f) {
        return 0.0f;
    }

    float sagAmount    = waterParams.x;
    float irregularity = clamp(waterParams.y, 0.0f, 1.0f);
    float slosh        = waterParams.z;
    float seed         = max(1.0f, waterParams2.x);
    float time         = waterParams2.y;
    float cursorLean   = waterParams2.z;

    // Smooth envelope tapering to 0 at the side corners (u = +/- 1)
    float env = max(0.0f, 1.0f - u * u);
    float smoothEnv = env * env; // C1 continuity at corners: zero kink, zero corner

    // Deterministic pseudo-random parameters from seed
    float drift = (fract(seed * 0.1031f) - 0.5f) * 0.40f * irregularity;

    float f1 = 1.0f + 0.35f * fract(seed * 0.2317f);
    float phi1 = fract(seed * 0.3731f) * 6.28318f;
    float a1 = (0.22f + 0.28f * fract(seed * 0.4193f)) * irregularity;

    float f2 = 2.0f + 0.5f * fract(seed * 0.5873f);
    float phi2 = fract(seed * 0.6419f) * 6.28318f;
    float a2 = (0.12f + 0.22f * fract(seed * 0.7937f)) * irregularity;

    // 3rd soft asymmetric harmonic for rich 2-3 bulge organic water silhouette
    float f3 = 3.0f + 0.4f * fract(seed * 0.9123f);
    float phi3 = fract(seed * 0.1543f) * 6.28318f;
    float a3 = (0.06f + 0.12f * fract(seed * 0.8351f)) * irregularity;

    float shape = 1.0f + drift * u + a1 * sin(f1 * 3.14159f * u + phi1) + a2 * sin(f2 * 3.14159f * u + phi2) + a3 * sin(f3 * 3.14159f * u + phi3);
    shape = max(0.15f, shape);

    // Dynamic wave slosh: progressive running wave along bottom contour
    float sloshWave = slosh * (sin(3.14159f * u - time * 2.5f) * 2.8f + sin(2.0f * 3.14159f * u + 0.6f) * 1.2f);

    // Very gentle hold ripple (max 1.5pt amplitude)
    float ripple = sin(3.0f * 3.14159f * u + time * 1.5f) * 1.2f;

    // Cursor attraction lean (max 4pt)
    float lean = cursorLean * u * 3.5f;

    float totalSag = (sagAmount * shape + sloshWave + ripple + lean) * smoothEnv;

    // Vertical weight: 0 at body center, ramps smoothly to 1 towards bottom edge
    float yWeight = smoothstep(centerY - 2.0f, centerY + halfH * 0.60f, p.y);

    return totalSag * yWeight;
}

inline float evaluateCompositeSDFWithWater(
    float2 p,
    device const float *lobes,
    int lobeCount,
    float k,
    float4 waterParams,
    float4 waterParams2
) {
    float kEff = (waterParams.x > 0.001f && lobeCount > 1 && p.y > lobes[8 + 1]) ? max(k, k + 8.0f) : k;
    float d = evaluateCompositeSDF(p, lobes, lobeCount, kEff);
    float waterDisp = evaluateWaterDisplacement(p, lobes, lobeCount, waterParams, waterParams2);
    return d - waterDisp;
}

// MARK: - Stitchable Shader for SwiftUI ShaderLibrary

[[stitchable]] half4 liquidIsland(
    float2 position,
    half4 baseColor,
    float4 bounds,               // (x, y, width, height)
    device const float *lobeData,// 8 lobes * 8 floats = 64 floats
    int lobeDataCount,           // automatically supplied by SwiftUI for .floatArray
    float k,                     // smoothing radius
    float4 lightDirAndTight,     // (lightX, lightY, lightZ, tightPower)
    float4 lightingParams,       // (tightSpecIntensity, broadSpecIntensity, fresnelIntensity, bevelWidth)
    half4 tintColor,             // (r, g, b, a) passed as half4 by SwiftUI .color
    float4 waterParams,          // (sagAmount, irregularity, sloshPhase, meniscusIntensity)
    float4 waterParams2          // (seed, time, cursorLean, reduceTransparency)
) {
    int lobeCount = min(lobeDataCount / 8, 8);

    // 1. Evaluate distance field with procedural water bottom deformation
    float d = evaluateCompositeSDFWithWater(position, lobeData, lobeCount, k, waterParams, waterParams2);

    // 2. High-quality anti-aliased alpha boundary
    float alpha = smoothstep(0.75f, -0.75f, d);
    if (alpha <= 0.001f) {
        return half4(0.0h, 0.0h, 0.0h, 0.0h);
    }

    // 3. 2D gradient estimation via central differences
    float eps = 1.0f;
    float dXPlus  = evaluateCompositeSDFWithWater(position + float2(eps, 0.0f), lobeData, lobeCount, k, waterParams, waterParams2);
    float dXMinus = evaluateCompositeSDFWithWater(position - float2(eps, 0.0f), lobeData, lobeCount, k, waterParams, waterParams2);
    float dYPlus  = evaluateCompositeSDFWithWater(position + float2(0.0f, eps), lobeData, lobeCount, k, waterParams, waterParams2);
    float dYMinus = evaluateCompositeSDFWithWater(position - float2(0.0f, eps), lobeData, lobeCount, k, waterParams, waterParams2);

    float2 grad = float2(dXPlus - dXMinus, dYPlus - dYMinus) * 0.5f;
    float gradLen = length(grad);
    float2 n2D = gradLen > 0.001f ? (grad / gradLen) : float2(0.0f, 1.0f);

    // Local SDF boundary curvature from discrete Laplacian
    float curvature = max(0.0f, (dXPlus + dXMinus + dYPlus + dYMinus - 4.0f * d));

    // 4. Reconstruct 3D normal from a depth-based height profile:
    // - Depth u = max(-d, 0.0) is the distance from the shape edge inward
    // - Curved rounded bevel of width bevelWidth (default ~5.5pt)
    // - Completely flat interior (u >= bevelWidth) where normal is (0, 0, 1)
    float bevelWidth = max(2.0f, lightingParams.w);
    float u = max(-d, 0.0f);
    float s = clamp(u / bevelWidth, 0.0f, 1.0f);

    float theta = s * (M_PI_F * 0.5f);
    float3 normal = float3(n2D * cos(theta), sin(theta));

    // Highlights only occur on the rounded edge bevel (s < 1.0).
    // In the interior (s >= 1.0), bevelMask is 0.0, keeping the body pure optical black.
    float bevelMask = cos(s * (M_PI_F * 0.5f));

    // 5. Hardware notch seam suppression:
    // Fluid directly attached to the hardware notch stays pure black in the top 10-12pt
    // so it blends seamlessly with the hardware notch cutout without visible edge seams.
    float notchHighlightSuppression = 1.0f;
    if (lobeDataCount >= 8 && lobeData[5] > 0.5f) { // Root lobe (lobe 0) is active
        float rootCenterX = lobeData[0];
        float rootCenterY = lobeData[1];
        float rootHalfW   = lobeData[2];
        float rootHalfH   = lobeData[3];
        float rootBottom  = rootCenterY + rootHalfH;

        float xDist = abs(position.x - rootCenterX);
        if (xDist < rootHalfW + 16.0f) {
            float xFactor = smoothstep(rootHalfW + 16.0f, rootHalfW, xDist);
            float yFactor = 1.0f - smoothstep(rootBottom, rootBottom + 12.0f, position.y);
            notchHighlightSuppression = 1.0f - (xFactor * yFactor);
        }
    }

    // 6. 3D Lighting Calculations
    float3 lightDir = normalize(float3(lightDirAndTight.x, lightDirAndTight.y, lightDirAndTight.z));
    float3 viewDir = float3(0.0f, 0.0f, 1.0f);
    float3 halfVec = normalize(lightDir + viewDir);

    float nDotH = max(0.0f, dot(normal, halfVec));
    float tightPower = max(4.0f, lightDirAndTight.w);

    float effectiveBevel = bevelMask * notchHighlightSuppression;
    float tightSpec = pow(nDotH, tightPower) * lightingParams.x * effectiveBevel;
    float broadSpec = pow(nDotH, 5.0f) * lightingParams.y * effectiveBevel;

    // Fresnel rim light (strongest at grazing angles along fluid perimeter, zero in flat interior)
    float fresnel = pow(1.0f - normal.z, 3.0f) * lightingParams.z * effectiveBevel;

    // 7. Meniscus Rim Light along the irregular water contour (stronger where curve is tighter)
    float meniscusIntensity = waterParams.w;
    float meniscusRim = 0.0f;
    float bodyCenterY = lobeCount > 1 ? lobeData[8 + 1] : 0.0f;
    if (meniscusIntensity > 0.001f && position.y > bodyCenterY) {
        float downward = max(0.0f, normal.y);
        float edgeProximity = smoothstep(1.0f, 0.05f, s);
        float curvatureBoost = 1.0f + clamp(curvature * 2.5f, 0.0f, 2.5f);
        meniscusRim = pow(downward * edgeProximity, 1.6f) * meniscusIntensity * curvatureBoost * effectiveBevel;
    }

    // 8. Caustic Shimmer: slow subtle glimmer near bottom fluid interior
    float caustic = 0.0f;
    if (waterParams.x > 0.001f && position.y > bodyCenterY && lobeCount > 1) {
        float bodyCenterX = lobeData[8 + 0];
        float bodyHalfW = max(lobeData[8 + 2], 1.0f);
        float uCoord = (position.x - bodyCenterX) / bodyHalfW;
        float cWave = sin(uCoord * 12.0f + position.y * 0.18f + waterParams2.y * 1.8f) * 0.5f + 0.5f;
        caustic = cWave * smoothstep(-10.0f, -2.0f, d) * (1.0f - smoothstep(-2.0f, -0.5f, d)) * 0.07f * effectiveBevel;
    }

    // Reduce Transparency & Global Transparency Handling:
    // waterParams2.w carries either -1.0 (Reduce Transparency enabled) or transparency level (0.0 to 1.0)
    float tParam = waterParams2.w;
    bool isReduceTransparency = tParam < -0.5f;
    float transparency = isReduceTransparency ? 0.0f : clamp(tParam, 0.0f, 1.0f);

    if (isReduceTransparency) {
        caustic = 0.0f;
        tightSpec = 0.0f;
        broadSpec = 0.0f;
        fresnel = 0.0f;
        meniscusRim = 0.0f;
    }

    // 9. Opacity Ramp & Hardware Notch Seam Floor:
    // - Top 10-12pt directly under notch and concave ears stays 100% opaque pure black (#000000)
    // - Ramps down smoothly to chosen transparency (default 60%, floor of 0.38 alpha)
    // - Water-bottom hangs with translucent liquid glass blur while rim highlights stay crisp
    float rootBottom = 12.0f;
    if (lobeDataCount >= 8 && lobeData[5] > 0.5f) {
        rootBottom = lobeData[1] + lobeData[3] + 4.0f;
    }

    float yFromNotch = max(0.0f, position.y - rootBottom);
    float rampProgress = smoothstep(0.0f, max(24.0f, (bounds.w - rootBottom) * 0.75f), yFromNotch);
    float targetAlpha = max(0.38f, 1.0f - (transparency * 0.62f));
    float interiorAlpha = mix(1.0f, targetAlpha, rampProgress);

    // Hard guarantee: top 12pt under hardware notch is 100% pure opaque black
    if (position.y <= 12.0f) {
        interiorAlpha = 1.0f;
    }

    float effectiveAlpha = alpha * interiorAlpha;

    // 10. Optical Black Glass Color Composition:
    // Body interior has a glassy dark obsidian tint with specular reflections on the edge bevel.
    float3 rgb = float3(0.0f, 0.0f, 0.0f);

    float3 tint = float3(tintColor.rgb);

    // Tight glossy specular highlight (clean white with gentle tint fringe)
    float3 tightSpecColor = mix(float3(1.0f), tint, 0.25f) * tightSpec;
    rgb += tightSpecColor;

    // Broad specular sheen along the bevel curve
    rgb += tint * broadSpec;

    // Fresnel rim refraction
    rgb += tint * fresnel;

    // Meniscus rim highlight following the organic water contour
    rgb += mix(float3(1.0f), tint, 0.35f) * meniscusRim;

    // Gentle caustic wave shimmer
    rgb += tint * caustic;

    // Multiply highlights by boundary alpha for anti-aliasing
    return half4(half3(rgb * alpha), half(effectiveAlpha));
}

// MARK: - Multi-Blob Organic Liquid Shader (Step B)

inline float evaluateBlobDistanceMetal(
    float2 p,
    float2 center,
    float2 ab,
    float angle,
    float irregularity,
    float seed,
    float time
) {
    float cosA = cos(angle);
    float sinA = sin(angle);
    float2 d = p - center;
    float2 pr = float2(d.x * cosA + d.y * sinA, -d.x * sinA + d.y * cosA);

    float a = max(ab.x, 1.0f);
    float b = max(ab.y, 1.0f);

    float2 pAbs = abs(pr);
    float k0 = length(pAbs / float2(a, b));
    float k1 = length(pAbs / float2(a * a, b * b));
    float rawDist = (k0 < 0.001f) ? -min(a, b) : (k0 * (k0 - 1.0f) / max(k1, 0.0001f));

    if (irregularity > 0.001f) {
        float phi = atan2(pr.y, pr.x);
        float wave = sin(3.0f * phi + seed * 0.17f) * 0.45f
                   + sin(5.0f * phi - time * 1.8f + seed * 0.31f) * 0.30f
                   + cos(2.0f * phi + 1.2f) * 0.25f;
        float envelope = smoothstep(12.0f, 0.0f, abs(rawDist));
        rawDist -= wave * irregularity * 3.5f * envelope;
    }
    return rawDist;
}

inline float evaluateBlobFieldSDFMetal(
    float2 p,
    device const float *blobs,
    int blobCount,
    float k,
    float seed,
    float time
) {
    float d = 10000.0f;
    bool hasActive = false;

    for (int i = 0; i < blobCount && i < 16; ++i) {
        int base = i * 8;
        float isActive = blobs[base + 7];
        if (isActive < 0.5f) {
            continue;
        }

        float2 center = float2(blobs[base + 0], blobs[base + 1]);
        float2 radii  = float2(blobs[base + 2], blobs[base + 3]);
        float angle   = blobs[base + 4];
        float weight  = blobs[base + 5];
        float irreg   = blobs[base + 6];

        float blobD = evaluateBlobDistanceMetal(
            p, center, radii, angle, irreg,
            seed + float(i) * 13.7f, time
        ) - (weight - 1.0f) * 4.0f;

        if (!hasActive) {
            d = blobD;
            hasActive = true;
        } else {
            d = smin(d, blobD, k);
        }
    }
    return hasActive ? d : 10000.0f;
}

[[stitchable]] half4 liquidBlobField(
    float2 position,
    half4 baseColor,
    float4 bounds,               // (x, y, width, height)
    device const float *blobData,// Up to 16 blobs * 8 floats = 128 floats
    int blobDataCount,           // automatically supplied by SwiftUI for .floatArray
    float k,                     // smoothing radius
    float4 lightDirAndTight,     // (lightX, lightY, lightZ, tightPower)
    float4 lightingParams,       // (tightSpecIntensity, broadSpecIntensity, fresnelIntensity, bevelWidth)
    half4 tintColor,             // (r, g, b, a)
    float4 envParams,            // (bgLuminance, notchLipY, time, seed)
    float4 waterParams           // (sagAmount, irregularity, sloshPhase, transparency)
) {
    int blobCount = min(blobDataCount / 8, 16);
    float bgLuminance = envParams.x;
    float notchLipY   = envParams.y;
    float time        = envParams.z;
    float seed        = envParams.w;
    float transparency = waterParams.w;

    // 1. Evaluate multi-blob signed distance field
    float d = evaluateBlobFieldSDFMetal(position, blobData, blobCount, k, seed, time);

    // 2. Anti-aliased alpha boundary
    float alpha = smoothstep(0.75f, -0.75f, d);
    if (alpha <= 0.001f) {
        return half4(0.0h, 0.0h, 0.0h, 0.0h);
    }

    // 3. Central difference gradient for 3D normal reconstruction
    float eps = 1.0f;
    float dXPlus  = evaluateBlobFieldSDFMetal(position + float2(eps, 0.0f), blobData, blobCount, k, seed, time);
    float dXMinus = evaluateBlobFieldSDFMetal(position - float2(eps, 0.0f), blobData, blobCount, k, seed, time);
    float dYPlus  = evaluateBlobFieldSDFMetal(position + float2(0.0f, eps), blobData, blobCount, k, seed, time);
    float dYMinus = evaluateBlobFieldSDFMetal(position - float2(0.0f, eps), blobData, blobCount, k, seed, time);

    float2 grad = float2(dXPlus - dXMinus, dYPlus - dYMinus) * 0.5f;
    float gradLen = length(grad);
    float2 n2D = gradLen > 0.001f ? (grad / gradLen) : float2(0.0f, 1.0f);

    float bevelWidth = max(2.5f, lightingParams.w);
    float u = max(-d, 0.0f);
    float s = clamp(u / bevelWidth, 0.0f, 1.0f);

    float theta = s * (M_PI_F * 0.5f);
    float3 normal = float3(n2D * cos(theta), sin(theta));
    float bevelMask = cos(s * (M_PI_F * 0.5f));

    // 4. Source blend at hardware notch:
    // Right under the physical notch (position.y <= notchLipY), liquid starts pure black.
    // Within 10 to 14 points, smoothly blends to transparent glass.
    float sourceRamp = smoothstep(notchLipY, notchLipY + 14.0f, position.y);

    // 5. 3D Lighting & Fresnel Water Optics
    float3 lightDir = normalize(float3(lightDirAndTight.x, lightDirAndTight.y, lightDirAndTight.z));
    float3 viewDir = float3(0.0f, 0.0f, 1.0f);
    float3 halfVec = normalize(lightDir + viewDir);

    float nDotH = max(0.0f, dot(normal, halfVec));
    float tightPower = max(6.0f, lightDirAndTight.w);

    float tightSpec = pow(nDotH, tightPower) * lightingParams.x * bevelMask * sourceRamp;
    float broadSpec = pow(nDotH, 4.0f) * lightingParams.y * bevelMask * sourceRamp;

    // Water Fresnel (IOR 1.333 -> F0 ~ 0.02)
    float fresnel = pow(1.0f - normal.z, 3.5f) * lightingParams.z * bevelMask;

    // Meniscus rim highlight
    float meniscusRim = pow(max(0.0f, normal.y) * smoothstep(1.0f, 0.05f, s), 1.5f) * 1.2f * bevelMask;

    // Edge darkening: total internal reflection causes subtle dark tint along outer boundary
    float edgeDarkening = smoothstep(bevelWidth * 1.5f, 0.0f, u) * 0.25f;

    // Adaptive luminance adjustment: on bright/white backgrounds, deepen inner tint for contrast
    float contrastBoost = bgLuminance > 0.45f ? 0.22f : 0.0f;

    // Transparency target
    float targetAlpha = max(0.20f, 1.0f - (transparency * 0.75f));
    float effectiveAlpha = (mix(1.0f, targetAlpha + contrastBoost, sourceRamp) + edgeDarkening) * alpha;

    if (position.y <= notchLipY) {
        effectiveAlpha = alpha; // Solid black at hardware notch edge
    }

    // 6. Color Composition
    float3 tint = float3(tintColor.rgb);
    float3 rgb = float3(0.0f, 0.0f, 0.0f);

    // Specular and Fresnel highlights
    float3 tightSpecColor = mix(float3(1.0f), tint, 0.2f) * tightSpec;
    rgb += tightSpecColor;
    rgb += tint * broadSpec;
    rgb += tint * fresnel;
    rgb += mix(float3(1.0f), tint, 0.3f) * meniscusRim;

    // Soft water caustics inside droplet
    float caustic = sin((position.x + position.y * 0.4f) * 0.12f + time * 1.6f) * 0.04f * bevelMask;
    rgb += tint * max(0.0f, caustic);

    // In the pure black source zone, force RGB to 0
    rgb *= sourceRamp;

    return half4(half3(rgb * alpha), half(effectiveAlpha));
}

