// SPDX-License-Identifier: GPL-3.0-or-later
// The Hive theme's backdrop (and the installer's): a honeycomb that grows
// outward from the logo, breathes slowly, and sends a soft pulse of light
// outward every few seconds.
// Samples no textures. Output is premultiplied.
//
// Compiled to hive.frag.qsb with Qt's qsb (see shaders.qrc).
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    vec2 origin;      // where it grows from, in pixels
    float time;       // seconds
    float reveal;     // how far it has grown, in pixels
    float cell;       // hexagon size, in pixels
    float pulse;      // 0: still (reduced motion), 1: pulsing
    float strength;   // overall intensity
    float breathPeriod; // seconds per breath
    float pulsePeriod;  // seconds between pulses
    float corner;       // rounded-rectangle mask radius in pixels (0: none)
    float reach;        // how far the comb carries (fraction of the diagonal)
    float pulseReach;   // how far a pulse travels (fraction of the diagonal)
    vec4 lineColor;
    vec4 glowColor;
};

const vec2 S = vec2(1.0, 1.7320508);

// Nearest hexagon centre: xy is the offset from it, zw identifies the cell.
vec4 hexCoords(vec2 p) {
    vec4 c = floor(vec4(p, p - vec2(0.5, 1.0)) / S.xyxy) + 0.5;
    vec4 h = vec4(p - c.xy * S, p - (c.zw + 0.5) * S);
    return dot(h.xy, h.xy) < dot(h.zw, h.zw) ? vec4(h.xy, c.xy) : vec4(h.zw, c.zw + 0.5);
}

// 0 at the centre of a cell, 0.5 on its edge.
float hexDist(vec2 p) {
    p = abs(p);
    return max(dot(p, S * 0.5), p.x);
}

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
    vec2 px = qt_TexCoord0 * itemSize;
    float d = distance(px, origin);
    float far = length(itemSize);

    vec4 h = hexCoords((px - origin) / cell);
    float edge = 0.5 - hexDist(h.xy);
    float lineWidth = 1.5 / cell;
    float line = 1.0 - smoothstep(0.0, lineWidth, edge);

    // Grows from the logo; the front is soft.
    float grown = 1.0 - smoothstep(reveal - 90.0, reveal, d);
    // Fades towards the corners so the content stays calm.
    float falloff = exp(-d / (far * reach));

    // Breathing: a slow rise and fall of the whole comb.
    float breathe = 0.78 + 0.22 * sin(time * 6.2831853 / breathPeriod) * pulse;

    // A pulse of light travelling outward every few seconds.
    float t = fract(time / pulsePeriod);
    float ringRadius = t * far * pulseReach;
    float ring = exp(-pow((d - ringRadius) / 70.0, 2.0)) * (1.0 - t) * pulse;

    // A little variation from cell to cell, like light on real comb.
    float shade = 0.75 + 0.5 * hash(h.zw);

    float lineA = line * grown * falloff * breathe * shade * 1.6 + line * grown * ring * 1.8;
    float fillA = grown * ring * 0.08 * shade;
    float glowA = exp(-d / 150.0) * breathe * 0.32 * grown;

    vec3 rgb = lineColor.rgb * lineA * lineColor.a + glowColor.rgb * (glowA + fillA) * glowColor.a;
    float a = clamp(lineA * lineColor.a + (glowA + fillA) * glowColor.a, 0.0, 1.0);
    // Inside a rounded rectangle when asked (the phone preview's screen).
    float inside = 1.0;
    if (corner > 0.0) {
        vec2 q = abs(px - itemSize * 0.5) - (itemSize * 0.5 - vec2(corner));
        float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner;
        inside = 1.0 - smoothstep(-0.75, 0.75, sd);
    }

    float k = strength * qt_Opacity * inside;
    fragColor = vec4(rgb * k, a * k);
}
