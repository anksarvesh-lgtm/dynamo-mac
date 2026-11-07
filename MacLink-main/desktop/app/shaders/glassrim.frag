// SPDX-License-Identifier: GPL-3.0-or-later
// The edge of a Liquid Glass surface: a specular rim that catches light at the top left,
// a softer reflection at the bottom right, and a faint glow just inside the edge that
// reads as the thickness of the glass. Samples no textures.
//
// Compiled to glassrim.frag.qsb with Qt's qsb (see shaders.qrc).
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float radius;
    float strength;
    vec4 rimColor;
};

void main() {
    vec2 half_ = itemSize * 0.5;
    vec2 p = qt_TexCoord0 * itemSize - half_;
    float r = min(radius, min(half_.x, half_.y));
    vec2 q = abs(p) - half_ + r;
    // Signed distance to the rounded rectangle: negative inside.
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    vec2 outward = sign(p) * max(q, 0.0);
    float len = length(outward);
    vec2 n = len > 0.0001 ? outward / len : vec2(0.0);

    float rim = 1.0 - smoothstep(0.0, 1.1, abs(d + 0.55));
    float glow = d < 0.0 ? exp(d / 7.0) : 0.0;

    float key = pow(clamp(dot(n, normalize(vec2(-0.55, -0.84))), 0.0, 1.0), 2.2);
    float fill = pow(clamp(dot(n, normalize(vec2(0.55, 0.84))), 0.0, 1.0), 3.0) * 0.45;
    float light = key + fill;

    float a = (rim * (0.18 + 0.82 * light) + glow * 0.30 * light) * strength * rimColor.a * qt_Opacity;
    fragColor = vec4(rimColor.rgb * a, a);
}
