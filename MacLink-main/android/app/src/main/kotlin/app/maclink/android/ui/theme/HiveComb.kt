// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.ui.theme

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.RuntimeShader
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import androidx.annotation.RequiresApi
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import kotlinx.coroutines.delay
import kotlin.math.PI
import kotlin.math.sin
import kotlin.math.sqrt

/** The Hive theme is active. */
val LocalHiveTheme = compositionLocalOf { false }

/** True while Android's battery saver is on: decorative animation rests. */
@Composable
fun rememberPowerSaver(): Boolean {
    val context = LocalContext.current
    val power = remember(context) { context.getSystemService(PowerManager::class.java) }
    var saving by remember { mutableStateOf(power?.isPowerSaveMode == true) }
    DisposableEffect(context) {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                saving = power?.isPowerSaveMode == true
            }
        }
        context.registerReceiver(receiver, IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED))
        onDispose { runCatching { context.unregisterReceiver(receiver) } }
    }
    return saving
}

/**
 * Hive's living honeycomb behind the app, the same comb as the Windows app
 * and the installer: it breathes slowly and sends a soft pulse of light
 * outward from [origin] every few seconds.
 *
 * Light on the battery: on Android 13 and newer one GPU shader draws it;
 * time advances about 30 times a second (the motion is slow enough that more
 * looks the same), and only while the app is in front. Only the backdrop
 * redraws, never the content above it. With [animate] false it holds still.
 * Older Android draws the same comb from a cached path and only breathes.
 */
@Composable
fun HiveComb(
    dark: Boolean,
    animate: Boolean,
    modifier: Modifier = Modifier,
    cellDp: Float = Tokens.COMB_CELL_DP,
    origin: (androidx.compose.ui.geometry.Size) -> Offset = { Offset(it.width / 2f, it.height * 0.18f) },
) {
    val line = if (dark) {
        Color(0xFFFFB95F).copy(alpha = Tokens.COMB_LINE_ALPHA_DARK)
    } else {
        Color(0xFF8A5100).copy(alpha = Tokens.COMB_LINE_ALPHA_LIGHT)
    }
    val glow = if (dark) {
        Color(1.0f, 0.62f, 0.18f, Tokens.COMB_GLOW_ALPHA_DARK)
    } else {
        Color(1.0f, 0.72f, 0.37f, Tokens.COMB_GLOW_ALPHA_LIGHT)
    }
    val cellPx = with(LocalDensity.current) { cellDp * density }

    // Seconds, carried across pauses so it picks up where it stopped.
    var time by remember { mutableFloatStateOf(0f) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(animate, lifecycle) {
        if (!animate) return@LaunchedEffect
        lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            val base = time
            val since = SystemClock.uptimeMillis()
            while (true) {
                delay(Tokens.COMB_FRAME_MS)
                time = base + (SystemClock.uptimeMillis() - since) / 1000f
            }
        }
    }
    val pulse = if (animate) 1f else 0f

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        ShaderComb(modifier, { time }, pulse, cellPx, line, glow, origin)
    } else {
        PathComb(modifier, { time }, pulse, cellPx, line, glow, origin)
    }
}

@RequiresApi(Build.VERSION_CODES.TIRAMISU)
@Composable
private fun ShaderComb(
    modifier: Modifier,
    time: () -> Float,
    pulse: Float,
    cell: Float,
    line: Color,
    glow: Color,
    origin: (androidx.compose.ui.geometry.Size) -> Offset,
) {
    val shader = remember { RuntimeShader(COMB_AGSL) }
    val brush = remember(shader) { ShaderBrush(shader) }
    Canvas(modifier.fillMaxSize()) {
        val o = origin(size)
        shader.setFloatUniform("size", size.width, size.height)
        shader.setFloatUniform("origin", o.x, o.y)
        shader.setFloatUniform("time", time())
        shader.setFloatUniform("cell", cell)
        shader.setFloatUniform("pulse", pulse)
        shader.setFloatUniform("breathPeriod", Tokens.COMB_BREATH_SECONDS)
        shader.setFloatUniform("pulsePeriod", Tokens.COMB_PULSE_SECONDS)
        shader.setFloatUniform("lineColor", line.red, line.green, line.blue, line.alpha)
        shader.setFloatUniform("glowColor", glow.red, glow.green, glow.blue, glow.alpha)
        drawRect(brush)
    }
}

/** Android 12 and older: the comb as one cached path, breathing as a whole. */
@Composable
private fun PathComb(
    modifier: Modifier,
    time: () -> Float,
    pulse: Float,
    cell: Float,
    line: Color,
    glow: Color,
    origin: (androidx.compose.ui.geometry.Size) -> Offset,
) {
    androidx.compose.foundation.layout.Box(
        modifier.fillMaxSize().drawWithCache {
            val path = combPath(size.width, size.height, cell, origin(size))
            val stroke = Stroke(width = 1.2f * density)
            val o = origin(size)
            val glowRadius = 150f * density
            onDrawBehind {
                val breathe = 0.78f + 0.22f * sin(time() * 2f * PI.toFloat() / Tokens.COMB_BREATH_SECONDS) * pulse
                drawPath(path, line.copy(alpha = line.alpha * breathe), style = stroke)
                drawCircle(
                    brush = androidx.compose.ui.graphics.Brush.radialGradient(
                        listOf(glow.copy(alpha = glow.alpha * 0.32f * breathe), Color.Transparent),
                        center = o,
                        radius = glowRadius,
                    ),
                    radius = glowRadius,
                    center = o,
                )
            }
        },
    )
}

/** Hexagons of the shader's grid (flat sides left and right), in pixels. */
private fun combPath(width: Float, height: Float, cell: Float, origin: Offset): Path {
    val path = Path()
    val s = sqrt(3f)
    val half = 0.5f * cell
    val top = cell / s
    val side = 0.5f * cell / s
    val rows = (height / (s * cell)).toInt() + 3
    val cols = (width / cell).toInt() + 3
    val startCol = -(origin.x / cell).toInt() - 2
    val startRow = -(origin.y / (s * cell)).toInt() - 2
    for (row in startRow until startRow + rows) {
        for (col in startCol until startCol + cols) {
            for (shift in 0..1) {
                val cx = origin.x + (col + 0.5f * shift) * cell
                val cy = origin.y + (row + 0.5f * shift) * s * cell
                path.moveTo(cx, cy - top)
                path.lineTo(cx + half, cy - side)
                path.lineTo(cx + half, cy + side)
                path.lineTo(cx, cy + top)
                path.lineTo(cx - half, cy + side)
                path.lineTo(cx - half, cy - side)
                path.close()
            }
        }
    }
    return path
}

/** The comb's shader, the same as the Windows app's (desktop/app/shaders/hive.frag). */
private const val COMB_AGSL = """
uniform float2 size;
uniform float2 origin;
uniform float time;
uniform float cell;
uniform float pulse;
uniform float breathPeriod;
uniform float pulsePeriod;
uniform float4 lineColor;
uniform float4 glowColor;

const float2 S = float2(1.0, 1.7320508);

float4 hexCoords(float2 p) {
    float4 c = floor(float4(p, p - float2(0.5, 1.0)) / S.xyxy) + 0.5;
    float4 h = float4(p - c.xy * S, p - (c.zw + 0.5) * S);
    return dot(h.xy, h.xy) < dot(h.zw, h.zw) ? float4(h.xy, c.xy) : float4(h.zw, c.zw + 0.5);
}

float hexDist(float2 p) {
    p = abs(p);
    return max(dot(p, S * 0.5), p.x);
}

float hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

half4 main(float2 px) {
    float d = distance(px, origin);
    float far = length(size);

    float4 h = hexCoords((px - origin) / cell);
    float edge = 0.5 - hexDist(h.xy);
    float line = 1.0 - smoothstep(0.0, 1.5 / cell, edge);

    // Carries across the whole screen, fading only a little.
    float falloff = exp(-d / (far * 2.4));
    float breathe = 0.78 + 0.22 * sin(time * 6.2831853 / breathPeriod) * pulse;

    float t = fract(time / pulsePeriod);
    float ring = exp(-pow((d - t * far * 1.05) / (far * 0.06), 2.0)) * (1.0 - t) * pulse;

    float shade = 0.75 + 0.5 * hash(h.zw);

    float lineA = line * falloff * breathe * shade * 1.2 + line * ring * 1.6;
    float fillA = ring * 0.08 * shade;
    float glowA = exp(-d / (far * 0.12)) * breathe * 0.32;

    float3 rgb = lineColor.rgb * lineA * lineColor.a + glowColor.rgb * (glowA + fillA) * glowColor.a;
    float a = clamp(lineA * lineColor.a + (glowA + fillA) * glowColor.a, 0.0, 1.0);
    return half4(half3(rgb), half(a));
}
"""
