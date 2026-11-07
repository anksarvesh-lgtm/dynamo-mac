// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.ui.theme

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// ===========================================================================
// Vector Icons & Artwork
// ===========================================================================

fun vectorFromSvg(
    name: String,
    svgPath: String,
    strokeColor: Color? = Color.White,
    strokeWidth: Float = 1.8f,
    fillColor: Color? = null,
    viewportSize: Float = 24f,
): ImageVector {
    val nodes = androidx.compose.ui.graphics.vector.PathParser().parsePathString(svgPath).toNodes()
    return ImageVector.Builder(
        name = name,
        defaultWidth = viewportSize.dp,
        defaultHeight = viewportSize.dp,
        viewportWidth = viewportSize,
        viewportHeight = viewportSize,
    ).addPath(
        pathData = nodes,
        fill = fillColor?.let { SolidColor(it) },
        stroke = strokeColor?.let { SolidColor(it) },
        strokeLineWidth = strokeWidth,
        strokeLineCap = androidx.compose.ui.graphics.StrokeCap.Round,
        strokeLineJoin = androidx.compose.ui.graphics.StrokeJoin.Round,
    ).build()
}

/** Classic Apple logo icon vector */
val AppleLogoIcon: ImageVector by lazy {
    vectorFromSvg(
        name = "AppleLogo",
        svgPath = "M18.71,19.5 C17.88,20.74 17.0,21.95 15.66,21.97 C14.32,22.0 13.89,21.18 12.37,21.18 C10.84,21.18 10.37,21.95 9.1,22.0 C7.79,22.05 6.8,20.68 5.96,19.47 C4.25,17.0 2.94,12.45 4.7,9.39 C5.57,7.87 7.13,6.91 8.82,6.88 C10.1,6.86 11.32,7.75 12.11,7.75 C12.89,7.75 14.37,6.68 15.92,6.84 C16.57,6.87 18.39,7.1 19.56,8.82 C19.47,8.88 17.39,10.1 17.41,12.63 C17.44,15.65 20.06,16.66 20.09,16.67 C20.06,16.74 19.67,18.11 18.71,19.5 Z M15.97,6.37 C16.59,5.62 17.01,4.57 16.89,3.52 C15.99,3.56 14.91,4.12 14.28,4.86 C13.72,5.5 13.24,6.57 13.37,7.6 C14.38,7.68 15.38,7.09 15.97,6.37 Z",
        strokeColor = null,
        fillColor = Color.White,
    )
}

/** Crown icon vector for top header */
val CrownIcon: ImageVector by lazy {
    vectorFromSvg(
        name = "Crown",
        svgPath = "M3,18 L21,18 L19,8 L14,13 L12,6 L10,13 L5,8 Z",
        strokeWidth = 1.9f,
    )
}

/** Help question icon */
val HelpCircleIcon: ImageVector by lazy {
    vectorFromSvg(
        name = "HelpCircle",
        svgPath = "M12,22 A10,10 0 1,1 22,12 A10,10 0 0,1 12,22 Z M12,17 H12.01 M9.09,9 A3,3 0 0,1 15,9.5 C15,11.5 12,12.5 12,14",
        strokeWidth = 1.9f,
    )
}

/** QR / Four squares grid icon */
val QrGridIcon: ImageVector by lazy {
    vectorFromSvg(
        name = "QrGrid",
        svgPath = "M3.5,4 A1.5,1.5 0 0,1 5,2.5 H9 A1.5,1.5 0 0,1 10.5,4 V8 A1.5,1.5 0 0,1 9,9.5 H5 A1.5,1.5 0 0,1 3.5,8 Z M13.5,4 A1.5,1.5 0 0,1 15,2.5 H19 A1.5,1.5 0 0,1 20.5,4 V8 A1.5,1.5 0 0,1 19,9.5 H15 A1.5,1.5 0 0,1 13.5,8 Z M3.5,14 A1.5,1.5 0 0,1 5,12.5 H9 A1.5,1.5 0 0,1 10.5,14 V18 A1.5,1.5 0 0,1 9,19.5 H5 A1.5,1.5 0 0,1 3.5,18 Z M13.5,14 A1.5,1.5 0 0,1 15,12.5 H19 A1.5,1.5 0 0,1 20.5,14 V18 A1.5,1.5 0 0,1 19,19.5 H15 A1.5,1.5 0 0,1 13.5,18 Z",
        strokeWidth = 1.8f,
    )
}

/** Device app icon (computer and phone) */
val DeviceAppIcon: ImageVector by lazy {
    vectorFromSvg(
        name = "DeviceApp",
        svgPath = "M2,6 A2,2 0 0,1 4,4 H15 A2,2 0 0,1 17,6 V11 H15 V6 H4 V14 H10 V16 H4 A2,2 0 0,1 2,14 Z M15,10 A2,2 0 0,1 17,8 H21 A2,2 0 0,1 23,10 V19 A2,2 0 0,1 21,21 H17 A2,2 0 0,1 15,19 Z M17,11 H21 V17 H17 Z",
        strokeWidth = 1.8f,
    )
}

/** Laptop chip icon */
val LaptopChipIcon: ImageVector by lazy {
    vectorFromSvg(
        name = "LaptopChip",
        svgPath = "M4,6 A2,2 0 0,1 6,4 H18 A2,2 0 0,1 20,6 V14 A2,2 0 0,1 18,16 H6 A2,2 0 0,1 4,14 Z M1,19 H23",
        strokeWidth = 1.8f,
    )
}

/** Wifi chip icon */
val WifiChipIcon: ImageVector by lazy {
    vectorFromSvg(
        name = "WifiChip",
        svgPath = "M12,19.5 A1.5,1.5 0 1,1 10.5,18 A1.5,1.5 0 0,1 12,19.5 Z M8.5,15.5 A5,5 0 0,1 15.5,15.5 M5,12 A10,10 0 0,1 19,12 M1.5,8.5 A15,15 0 0,1 22.5,8.5",
        strokeWidth = 1.8f,
    )
}

/** Send paper plane icon */
val SendPlaneIcon: ImageVector by lazy {
    vectorFromSvg(
        name = "SendPlane",
        svgPath = "M22,2 L11,13 M22,2 L15,22 L11,13 L2,9 Z",
        strokeWidth = 1.9f,
    )
}

/** Stack / layers icon for system and power */
val LayersStackIcon: ImageVector by lazy {
    vectorFromSvg(
        name = "LayersStack",
        svgPath = "M12,2 L2,7 L12,12 L22,7 Z M2,12 L12,17 L22,12 M2,17 L12,22 L22,17",
        strokeWidth = 1.8f,
    )
}

/** Upload tray icon for Send Files */
val UploadTrayIcon: ImageVector by lazy {
    vectorFromSvg(
        name = "UploadTray",
        svgPath = "M12,15 V3 M7,8 L12,3 L17,8 M4,17 V19 A2,2 0 0,0 6,21 H18 A2,2 0 0,0 20,19 V17",
        strokeWidth = 1.9f,
    )
}

/** Lock action icon */
val LockActionIcon: ImageVector by lazy {
    vectorFromSvg(
        name = "LockAction",
        svgPath = "M7,11 V7 A5,5 0 0,1 17,7 V11 M5,11 H19 A2,2 0 0,1 21,13 V19 A2,2 0 0,1 19,21 H5 A2,2 0 0,1 3,19 V13 A2,2 0 0,1 5,11 Z M12,15 V17",
        strokeWidth = 1.8f,
    )
}

/** Moon action icon for sleep */
val MoonActionIcon: ImageVector by lazy {
    vectorFromSvg(
        name = "MoonAction",
        svgPath = "M21,12.79 A9,9 0 1,1 11.21,3 A7,7 0 0,0 21,12.79 Z",
        strokeWidth = 1.8f,
    )
}

/** Shield check icon for permissions */
val ShieldCheckIcon: ImageVector by lazy {
    vectorFromSvg(
        name = "ShieldCheck",
        svgPath = "M12,2 L4,5 V11 C4,16.55 7.84,21.74 12,23 C16.16,21.74 20,16.55 20,11 V5 Z M9,12 L11,14 L15,10",
        strokeWidth = 1.8f,
    )
}

/** Chevron right icon */
val ChevronRightIcon: ImageVector by lazy {
    vectorFromSvg(
        name = "ChevronRight",
        svgPath = "M9,18 L15,12 L9,6",
        strokeWidth = 2.0f,
    )
}

/** Folder with Search / Browse Files icon */
val FolderSearchIcon: ImageVector by lazy {
    vectorFromSvg(
        name = "FolderSearch",
        svgPath = "M3,7 A2,2 0 0,1 5,5 H9.5 A2,2 0 0,1 11.2,6.1 L12.1,7.2 A2,2 0 0,0 13.8,8.1 H19 A2,2 0 0,1 21,10.1 V13 M3,7 V18 A2,2 0 0,0 5,20 H12 M15,15 L21,21 M18.5,13 A3.5,3.5 0 1,1 15,9.5 A3.5,3.5 0 0,1 18.5,13 Z",
        strokeWidth = 1.8f,
    )
}

/** Book / Guide icon */
val BookGuideIcon: ImageVector by lazy {
    vectorFromSvg(
        name = "BookGuide",
        svgPath = "M4,19.5 A2.5,2.5 0 0,1 6.5,17 H20 M4,19.5 A2.5,2.5 0 0,0 6.5,22 H20 V2 H6.5 A2.5,2.5 0 0,0 4,4.5 Z M9,7 H16 M9,11 H14",
        strokeWidth = 1.8f,
    )
}

/** Settings gear icon */
val SettingsGearIcon: ImageVector by lazy {
    vectorFromSvg(
        name = "SettingsGear",
        svgPath = "M12,15.5 A3.5,3.5 0 1,1 15.5,12 A3.5,3.5 0 0,1 12,15.5 Z M19.4,13 C19.45,12.67 19.5,12.34 19.5,12 C19.5,11.66 19.45,11.33 19.4,11 L21.54,9.33 C21.73,9.18 21.79,8.91 21.66,8.69 L19.66,5.23 C19.53,5.01 19.27,4.92 19.05,5 L16.53,6.01 C16,5.6 15.43,5.26 14.8,5 L14.42,2.33 C14.38,2.08 14.17,1.9 13.92,1.9 L9.92,1.9 C9.67,1.9 9.46,2.08 9.42,2.33 L9.04,5 C8.41,5.26 7.84,5.6 7.31,6.01 L4.79,5 C4.57,4.92 4.31,5.01 4.18,5.23 L2.18,8.69 C2.05,8.91 2.11,9.18 2.3,9.33 L4.44,11 C4.39,11.33 4.34,11.66 4.34,12 C4.34,12.34 4.39,12.67 4.44,13 L2.3,14.67 C2.11,14.82 2.05,15.09 2.18,15.31 L4.18,18.77 C4.31,18.99 4.57,19.08 4.79,19 L7.31,17.99 C7.84,18.4 8.41,18.74 9.04,19 L9.42,21.67 C9.46,21.92 9.67,22.1 9.92,22.1 L13.92,22.1 C14.17,22.1 14.38,21.92 14.42,21.67 L14.8,19 C15.43,18.74 16,18.4 16.53,17.99 L19.05,19 C19.27,19.08 19.53,18.99 19.66,18.77 L21.66,15.31 C21.79,15.09 21.73,14.82 21.54,14.67 Z",
        strokeWidth = 1.8f,
    )
}

/** Home roof icon */
val HomeTabIcon: ImageVector by lazy {
    vectorFromSvg(
        name = "HomeTab",
        svgPath = "M3,10.5 L12,3 L21,10.5 V20 A1.5,1.5 0 0,1 19.5,21.5 H4.5 A1.5,1.5 0 0,1 3,20 Z M9,21.5 V13.5 H15 V21.5",
        strokeWidth = 1.8f,
    )
}

// ===========================================================================
// 3D MacBook Illustration
// ===========================================================================

@Composable
fun MacBookIllustration(
    modifier: Modifier = Modifier,
) {
    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height

        // 1. Under-laptop golden amber glow & reflection on glass table
        val glowBrush = Brush.radialGradient(
            colors = listOf(
                Color(0x99F49D04),
                Color(0x40D97706),
                Color(0x001A1008),
            ),
            center = Offset(w * 0.55f, h * 0.78f),
            radius = w * 0.50f,
        )
        drawOval(
            brush = glowBrush,
            topLeft = Offset(w * 0.05f, h * 0.65f),
            size = Size(w * 0.90f, h * 0.35f),
        )

        // 2. Display Lid (trapezoid at 3/4 isometric perspective)
        val screenTopLeft = Offset(w * 0.32f, h * 0.06f)
        val screenTopRight = Offset(w * 0.94f, h * 0.12f)
        val screenBottomRight = Offset(w * 0.86f, h * 0.68f)
        val screenBottomLeft = Offset(w * 0.28f, h * 0.64f)

        // Screen bezel outer path
        val bezelPath = Path().apply {
            moveTo(screenTopLeft.x, screenTopLeft.y)
            lineTo(screenTopRight.x, screenTopRight.y)
            lineTo(screenBottomRight.x, screenBottomRight.y)
            lineTo(screenBottomLeft.x, screenBottomLeft.y)
            close()
        }
        // Dark metallic outer bezel
        drawPath(
            path = bezelPath,
            brush = Brush.linearGradient(
                listOf(Color(0xFF2E2C2A), Color(0xFF1A1816)),
                start = screenTopLeft,
                end = screenBottomRight,
            ),
        )
        // Outer thin highlight rim on lid
        drawPath(
            path = bezelPath,
            color = Color(0x60FFF8F3),
            style = Stroke(width = 1.2f),
        )

        // Active glowing Amber Wallpaper surface
        val innerMarginX = w * 0.022f
        val innerMarginY = h * 0.025f
        val displayPath = Path().apply {
            moveTo(screenTopLeft.x + innerMarginX, screenTopLeft.y + innerMarginY)
            lineTo(screenTopRight.x - innerMarginX, screenTopRight.y + innerMarginY)
            lineTo(screenBottomRight.x - innerMarginX, screenBottomRight.y - innerMarginY)
            lineTo(screenBottomLeft.x + innerMarginX, screenBottomLeft.y - innerMarginY)
            close()
        }
        val wallpaperBrush = Brush.radialGradient(
            colors = listOf(
                Color(0xFFFFB52E), // Bright gold center
                Color(0xFFF49D04), // Primary amber
                Color(0xFFB45309), // Deep amber
                Color(0xFF451A03), // Dark edge
            ),
            center = Offset(w * 0.63f, h * 0.38f),
            radius = w * 0.45f,
        )
        drawPath(path = displayPath, brush = wallpaperBrush)

        // Fluid light rays across wallpaper
        val rayPath = Path().apply {
            moveTo(screenTopLeft.x + innerMarginX * 2, screenBottomLeft.y - innerMarginY * 2)
            cubicTo(
                w * 0.50f, h * 0.25f,
                w * 0.70f, h * 0.50f,
                screenTopRight.x - innerMarginX * 2, screenTopRight.y + innerMarginY * 2
            )
            lineTo(screenTopRight.x - innerMarginX * 4, screenTopRight.y + innerMarginY * 2)
            cubicTo(
                w * 0.65f, h * 0.45f,
                w * 0.45f, h * 0.30f,
                screenTopLeft.x + innerMarginX * 2, screenBottomLeft.y - innerMarginY * 4
            )
            close()
        }
        drawPath(
            path = rayPath,
            brush = Brush.linearGradient(
                listOf(Color(0x00FFFFFF), Color(0x75FFF8F3), Color(0x00FFFFFF)),
            ),
        )

        // Camera Notch
        val notchCenter = Offset((screenTopLeft.x + screenTopRight.x) * 0.5f, (screenTopLeft.y + screenTopRight.y) * 0.5f)
        drawRoundRect(
            color = Color(0xFF141312),
            topLeft = Offset(notchCenter.x - 7f, notchCenter.y - 1f),
            size = Size(14f, 6f),
            cornerRadius = CornerRadius(2f, 2f),
        )

        // 3. Laptop Base / Chassis
        val baseBackLeft = Offset(w * 0.25f, h * 0.64f)
        val baseBackRight = Offset(w * 0.88f, h * 0.68f)
        val baseFrontRight = Offset(w * 0.78f, h * 0.88f)
        val baseFrontLeft = Offset(w * 0.08f, h * 0.82f)

        val chassisPath = Path().apply {
            moveTo(baseBackLeft.x, baseBackLeft.y)
            lineTo(baseBackRight.x, baseBackRight.y)
            lineTo(baseFrontRight.x, baseFrontRight.y)
            lineTo(baseFrontLeft.x, baseFrontLeft.y)
            close()
        }
        // Silver-charcoal aluminum base
        drawPath(
            path = chassisPath,
            brush = Brush.linearGradient(
                listOf(Color(0xFF5A5753), Color(0xFF2C2A28), Color(0xFF1E1D1B)),
                start = baseBackLeft,
                end = baseFrontRight,
            ),
        )
        // Chamfered front edge
        val frontLip = Path().apply {
            moveTo(baseFrontLeft.x, baseFrontLeft.y)
            lineTo(baseFrontRight.x, baseFrontRight.y)
            lineTo(baseFrontRight.x - 1f, baseFrontRight.y + 3.5f)
            lineTo(baseFrontLeft.x + 1f, baseFrontLeft.y + 3.5f)
            close()
        }
        drawPath(
            path = frontLip,
            brush = Brush.linearGradient(
                listOf(Color(0xFF8A8680), Color(0xFF4A4744)),
            ),
        )
        // Highlight edge along the chassis rim
        drawPath(
            path = chassisPath,
            color = Color(0x70FFFFFF),
            style = Stroke(width = 1.0f),
        )

        // Keyboard recess well
        val kbBackLeft = Offset(w * 0.28f, h * 0.66f)
        val kbBackRight = Offset(w * 0.82f, h * 0.70f)
        val kbFrontRight = Offset(w * 0.73f, h * 0.79f)
        val kbFrontLeft = Offset(w * 0.20f, h * 0.75f)

        val kbPath = Path().apply {
            moveTo(kbBackLeft.x, kbBackLeft.y)
            lineTo(kbBackRight.x, kbBackRight.y)
            lineTo(kbFrontRight.x, kbFrontRight.y)
            lineTo(kbFrontLeft.x, kbFrontLeft.y)
            close()
        }
        drawPath(path = kbPath, color = Color(0xFF141312))

        // Trackpad outline
        val tpBackLeft = Offset(w * 0.38f, h * 0.78f)
        val tpBackRight = Offset(w * 0.58f, h * 0.80f)
        val tpFrontRight = Offset(w * 0.55f, h * 0.85f)
        val tpFrontLeft = Offset(w * 0.35f, h * 0.83f)

        val tpPath = Path().apply {
            moveTo(tpBackLeft.x, tpBackLeft.y)
            lineTo(tpBackRight.x, tpBackRight.y)
            lineTo(tpFrontRight.x, tpFrontRight.y)
            lineTo(tpFrontLeft.x, tpFrontLeft.y)
            close()
        }
        drawPath(path = tpPath, color = Color(0x35FFFFFF), style = Stroke(width = 0.8f))
    }
}

// ===========================================================================
// Glass Badge Chip (MacBook Air, Same Network)
// ===========================================================================

@Composable
fun GlassBadgeChip(
    icon: ImageVector,
    text: String,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(12.dp))
            .background(AmberTokens.GlassBackgroundSubtle, RoundedCornerShape(12.dp))
            .drawWithCache {
                val stroke = 0.8f.dp.toPx()
                val rim = Brush.linearGradient(
                    0f to AmberTokens.GlassBorder,
                    1f to AmberTokens.GlassBorderSubtle,
                )
                onDrawWithContent {
                    drawContent()
                    drawRoundRect(
                        brush = rim,
                        topLeft = Offset(stroke * 0.5f, stroke * 0.5f),
                        size = Size(size.width - stroke, size.height - stroke),
                        cornerRadius = CornerRadius(12.dp.toPx(), 12.dp.toPx()),
                        style = Stroke(width = stroke),
                    )
                }
            }
            .padding(horizontal = 10.dp, vertical = 5.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = AmberTokens.SecondaryText,
                modifier = Modifier.size(13.dp),
            )
            Spacer(modifier = Modifier.width(5.dp))
            Text(
                text = text,
                color = AmberTokens.PrimaryText,
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}

// ===========================================================================
// Liquid Glass Card Component
// ===========================================================================

@Composable
fun LiquidGlassCard(
    modifier: Modifier = Modifier,
    cornerRadius: Dp = 24.dp,
    hasGlow: Boolean = false,
    glowColor: Color = AmberTokens.GlassShadowAmber,
    borderColor: Color = AmberTokens.GlassBorder,
    backgroundColor: Color = AmberTokens.GlassBackground,
    onClick: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val shape = remember(cornerRadius) { RoundedCornerShape(cornerRadius) }
    val clickMod = if (onClick != null) {
        Modifier.clickable(
            interactionSource = remember { MutableInteractionSource() },
            indication = null,
            onClick = onClick,
        )
    } else Modifier

    Box(
        modifier = modifier
            .then(
                if (hasGlow) {
                    Modifier.drawBehind {
                        drawRoundRect(
                            color = glowColor,
                            cornerRadius = CornerRadius(cornerRadius.toPx(), cornerRadius.toPx()),
                            size = Size(size.width + 12f, size.height + 12f),
                            topLeft = Offset(-6f, -6f),
                        )
                    }
                } else Modifier
            )
            .clip(shape)
            .background(backgroundColor, shape)
            .drawWithCache {
                val strokeWidth = 1.dp.toPx()
                val radius = cornerRadius.toPx()
                val insetSize = Size(size.width - strokeWidth, size.height - strokeWidth)
                val topLeft = Offset(strokeWidth * 0.5f, strokeWidth * 0.5f)

                // Specular rim: bright at top left, soft at bottom right
                val rimBrush = Brush.linearGradient(
                    0.0f to borderColor,
                    0.5f to borderColor.copy(alpha = borderColor.alpha * 0.45f),
                    1.0f to borderColor.copy(alpha = borderColor.alpha * 0.70f),
                    start = Offset.Zero,
                    end = Offset(size.width, size.height),
                )
                onDrawWithContent {
                    drawContent()
                    drawRoundRect(
                        brush = rimBrush,
                        topLeft = topLeft,
                        size = insetSize,
                        cornerRadius = CornerRadius(radius, radius),
                        style = Stroke(width = strokeWidth),
                    )
                }
            }
            .then(clickMod),
    ) {
        content()
    }
}

// ===========================================================================
// Main Quick Action Tile (Control PC, Deck, Desk Clock)
// ===========================================================================

@Composable
fun QuickActionTile(
    title: String,
    icon: ImageVector,
    isActive: Boolean = false,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale = if (isPressed) 0.96f else 1.0f
    val cornerRadius = 20.dp
    val shape = remember { RoundedCornerShape(cornerRadius) }

    Box(
        modifier = modifier
            .scale(scale)
            .then(
                if (isActive) {
                    Modifier.drawBehind {
                        // Radiant golden amber glow surrounding the active card
                        drawRoundRect(
                            color = Color(0x66F49D04),
                            cornerRadius = CornerRadius(cornerRadius.toPx() + 4f, cornerRadius.toPx() + 4f),
                            size = Size(size.width + 10f, size.height + 10f),
                            topLeft = Offset(-5f, -5f),
                        )
                    }
                } else Modifier
            )
            .clip(shape)
            .background(
                brush = if (isActive) AmberTokens.ActiveCardGradient else AmberTokens.CardGradient,
                shape = shape,
            )
            .drawWithCache {
                val strokeWidth = if (isActive) 1.5.dp.toPx() else 1.0.dp.toPx()
                val rimColor = if (isActive) AmberTokens.Highlight else AmberTokens.GlassBorder
                val rimBrush = Brush.linearGradient(
                    0.0f to rimColor,
                    0.6f to rimColor.copy(alpha = rimColor.alpha * 0.5f),
                    1.0f to rimColor,
                    start = Offset.Zero,
                    end = Offset(size.width, size.height),
                )
                onDrawWithContent {
                    drawContent()
                    drawRoundRect(
                        brush = rimBrush,
                        topLeft = Offset(strokeWidth * 0.5f, strokeWidth * 0.5f),
                        size = Size(size.width - strokeWidth, size.height - strokeWidth),
                        cornerRadius = CornerRadius(cornerRadius.toPx(), cornerRadius.toPx()),
                        style = Stroke(width = strokeWidth),
                    )
                }
            }
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = onClick,
            )
            .padding(vertical = 18.dp, horizontal = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = title,
                tint = if (isActive) Color.White else AmberTokens.PrimaryText,
                modifier = Modifier.size(28.dp),
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = title,
                color = if (isActive) Color.White else AmberTokens.PrimaryText,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                textAlign = TextAlign.Center,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

// ===========================================================================
// Transfer Action Card (Send Files, Send Folder, Send Clipboard, Browse Files)
// ===========================================================================

@Composable
fun TransferActionCard(
    title: String,
    icon: ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale = if (isPressed) 0.95f else 1.0f
    val cornerRadius = 16.dp
    val shape = remember { RoundedCornerShape(cornerRadius) }

    Box(
        modifier = modifier
            .scale(scale)
            .clip(shape)
            .background(AmberTokens.GlassBackgroundSubtle, shape)
            .drawWithCache {
                val stroke = 1.dp.toPx()
                val rim = Brush.linearGradient(
                    0f to AmberTokens.GlassBorder,
                    1f to AmberTokens.GlassBorderSubtle,
                )
                onDrawWithContent {
                    drawContent()
                    drawRoundRect(
                        brush = rim,
                        topLeft = Offset(stroke * 0.5f, stroke * 0.5f),
                        size = Size(size.width - stroke, size.height - stroke),
                        cornerRadius = CornerRadius(cornerRadius.toPx(), cornerRadius.toPx()),
                        style = Stroke(width = stroke),
                    )
                }
            }
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = onClick,
            )
            .padding(vertical = 14.dp, horizontal = 6.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = title,
                tint = AmberTokens.PrimaryText,
                modifier = Modifier.size(24.dp),
            )
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                text = title,
                color = AmberTokens.PrimaryText,
                fontSize = 11.sp,
                fontWeight = FontWeight.Medium,
                textAlign = TextAlign.Center,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

// ===========================================================================
// System & Power Action Button (Record, Ring PC, Lock PC, Sleep)
// ===========================================================================

@Composable
fun PowerActionButton(
    title: String,
    icon: ImageVector,
    isRecord: Boolean = false,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale = if (isPressed) 0.94f else 1.0f

    Column(
        modifier = modifier
            .scale(scale)
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = onClick,
            ),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        // Circle Button
        Box(
            modifier = Modifier
                .size(54.dp)
                .clip(CircleShape)
                .background(AmberTokens.GlassBackgroundSubtle, CircleShape)
                .drawWithCache {
                    val stroke = 1.dp.toPx()
                    val rim = Brush.linearGradient(
                        0f to AmberTokens.GlassBorder,
                        1f to AmberTokens.GlassBorderSubtle,
                    )
                    onDrawWithContent {
                        drawContent()
                        drawCircle(
                            brush = rim,
                            radius = (size.minDimension - stroke) * 0.5f,
                            style = Stroke(width = stroke),
                        )
                    }
                },
            contentAlignment = Alignment.Center,
        ) {
            if (isRecord) {
                // Red record circle
                Box(
                    modifier = Modifier
                        .size(16.dp)
                        .clip(CircleShape)
                        .background(AmberTokens.GlowRed, CircleShape),
                )
            } else {
                Icon(
                    imageVector = icon,
                    contentDescription = title,
                    tint = AmberTokens.PrimaryText,
                    modifier = Modifier.size(22.dp),
                )
            }
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = title,
            color = AmberTokens.PrimaryText,
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            textAlign = TextAlign.Center,
            maxLines = 1,
        )
    }
}

// ===========================================================================
// Amber Light Wave with Golden Apple Logo
// ===========================================================================

@Composable
fun AmberLightWave(
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(56.dp),
        contentAlignment = Alignment.Center,
    ) {
        Canvas(modifier = Modifier.fillMaxWidth().height(56.dp)) {
            val w = size.width
            val h = size.height

            // Wave 1: Flowing amber ribbon
            val path1 = Path().apply {
                moveTo(0f, h * 0.70f)
                cubicTo(
                    w * 0.25f, h * 0.25f,
                    w * 0.40f, h * 0.85f,
                    w * 0.50f, h * 0.45f
                )
                cubicTo(
                    w * 0.60f, h * 0.05f,
                    w * 0.75f, h * 0.75f,
                    w, h * 0.40f
                )
            }
            drawPath(
                path = path1,
                brush = Brush.horizontalGradient(
                    listOf(
                        Color(0x00F49D04),
                        Color(0x40F49D04),
                        Color(0xD9FFB52E),
                        Color(0x40F49D04),
                        Color(0x00F49D04),
                    )
                ),
                style = Stroke(width = 2.5f),
            )

            // Wave 2: Secondary soft amber wave
            val path2 = Path().apply {
                moveTo(0f, h * 0.45f)
                cubicTo(
                    w * 0.20f, h * 0.80f,
                    w * 0.35f, h * 0.30f,
                    w * 0.50f, h * 0.55f
                )
                cubicTo(
                    w * 0.65f, h * 0.80f,
                    w * 0.80f, h * 0.35f,
                    w, h * 0.65f
                )
            }
            drawPath(
                path = path2,
                brush = Brush.horizontalGradient(
                    listOf(
                        Color(0x00F49D04),
                        Color(0x25F49D04),
                        Color(0x99F49D04),
                        Color(0x25F49D04),
                        Color(0x00F49D04),
                    )
                ),
                style = Stroke(width = 1.8f),
            )

            // Radial halo around the center
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(
                        Color(0x80F49D04),
                        Color(0x20F49D04),
                        Color(0x001A1008),
                    ),
                    center = Offset(w * 0.5f, h * 0.5f),
                    radius = 36.dp.toPx(),
                ),
                radius = 36.dp.toPx(),
                center = Offset(w * 0.5f, h * 0.5f),
            )
        }

        // Golden Apple logo at the center of the wave
        Icon(
            imageVector = AppleLogoIcon,
            contentDescription = "Apple",
            tint = AmberTokens.Highlight,
            modifier = Modifier.size(24.dp),
        )
    }
}

// ===========================================================================
// Liquid Glass Button & Toggles
// ===========================================================================

@Composable
fun LiquidGlassButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    isPrimary: Boolean = false,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale = if (isPressed) 0.96f else 1.0f
    val cornerRadius = 16.dp
    val shape = remember { RoundedCornerShape(cornerRadius) }

    Box(
        modifier = modifier
            .scale(scale)
            .clip(shape)
            .background(
                brush = if (isPrimary) AmberTokens.ActiveCardGradient else AmberTokens.CardGradient,
                shape = shape,
            )
            .drawWithCache {
                val stroke = 1.dp.toPx()
                val rim = Brush.linearGradient(
                    0f to if (isPrimary) AmberTokens.Highlight else AmberTokens.GlassBorder,
                    1f to AmberTokens.GlassBorderSubtle,
                )
                onDrawWithContent {
                    drawContent()
                    drawRoundRect(
                        brush = rim,
                        topLeft = Offset(stroke * 0.5f, stroke * 0.5f),
                        size = Size(size.width - stroke, size.height - stroke),
                        cornerRadius = CornerRadius(cornerRadius.toPx(), cornerRadius.toPx()),
                        style = Stroke(width = stroke),
                    )
                }
            }
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = onClick,
            )
            .padding(horizontal = 18.dp, vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center,
        ) {
            if (icon != null) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = if (isPrimary) Color.White else AmberTokens.PrimaryText,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(modifier = Modifier.width(8.dp))
            }
            Text(
                text = text,
                color = if (isPrimary) Color.White else AmberTokens.PrimaryText,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@Composable
fun LiquidGlassToggle(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val knobOffset = remember { Animatable(if (checked) 20f else 2f) }
    LaunchedEffect(checked) {
        knobOffset.animateTo(
            targetValue = if (checked) 20f else 2f,
            animationSpec = tween(durationMillis = 180),
        )
    }

    Box(
        modifier = modifier
            .size(width = 46.dp, height = 26.dp)
            .clip(RoundedCornerShape(13.dp))
            .background(
                if (checked) AmberTokens.PrimaryAccent else AmberTokens.GlassBackgroundSubtle,
                RoundedCornerShape(13.dp),
            )
            .drawWithCache {
                val stroke = 1.dp.toPx()
                val rim = Brush.linearGradient(
                    0f to if (checked) AmberTokens.Highlight else AmberTokens.GlassBorder,
                    1f to AmberTokens.GlassBorderSubtle,
                )
                onDrawWithContent {
                    drawContent()
                    drawRoundRect(
                        brush = rim,
                        topLeft = Offset(stroke * 0.5f, stroke * 0.5f),
                        size = Size(size.width - stroke, size.height - stroke),
                        cornerRadius = CornerRadius(13.dp.toPx(), 13.dp.toPx()),
                        style = Stroke(width = stroke),
                    )
                }
            }
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = { onCheckedChange(!checked) },
            ),
        contentAlignment = Alignment.CenterStart,
    ) {
        Box(
            modifier = Modifier
                .padding(start = knobOffset.value.dp)
                .size(22.dp)
                .clip(CircleShape)
                .background(Color.White, CircleShape)
                .shadow(elevation = 2.dp, shape = CircleShape),
        )
    }
}

@Composable
fun SettingsGroup(
    title: String? = null,
    modifier: Modifier = Modifier,
    content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit,
) {
    Column(modifier = modifier.fillMaxWidth()) {
        if (!title.isNullOrBlank()) {
            Text(
                text = title,
                color = AmberTokens.SecondaryText,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(start = 16.dp, bottom = 8.dp),
            )
        }
        LiquidGlassCard(
            modifier = Modifier.fillMaxWidth(),
            cornerRadius = 20.dp,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp),
                content = content,
            )
        }
    }
}

@Composable
fun LiquidGlassIconButton(
    icon: ImageVector,
    contentDescription: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: Dp = 40.dp,
    tint: Color = AmberTokens.PrimaryText,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale = if (isPressed) 0.92f else 1.0f

    Box(
        modifier = modifier
            .size(size)
            .scale(scale)
            .clip(CircleShape)
            .background(AmberTokens.GlassBackgroundSubtle, CircleShape)
            .drawWithCache {
                val stroke = 1.dp.toPx()
                val rim = Brush.linearGradient(
                    0f to AmberTokens.GlassBorder,
                    1f to AmberTokens.GlassBorderSubtle,
                )
                onDrawWithContent {
                    drawContent()
                    drawCircle(
                        brush = rim,
                        radius = (this.size.minDimension - stroke) * 0.5f,
                        style = Stroke(width = stroke),
                    )
                }
            }
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = onClick,
            ),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            tint = tint,
            modifier = Modifier.size(size * 0.52f),
        )
    }
}

// ===========================================================================
// Status Dot Indicator (Animated)
// ===========================================================================

@Composable
fun StatusIndicator(
    statusColor: Color,
    modifier: Modifier = Modifier,
    size: Dp = 8.dp,
    pulsing: Boolean = true,
) {
    val pulse = remember { Animatable(1.0f) }
    LaunchedEffect(pulsing) {
        if (pulsing) {
            pulse.animateTo(
                targetValue = 1.45f,
                animationSpec = infiniteRepeatable(
                    animation = tween(1200, easing = LinearEasing),
                    repeatMode = RepeatMode.Reverse,
                ),
            )
        } else {
            pulse.snapTo(1.0f)
        }
    }

    Box(
        modifier = modifier.size(size * 2f),
        contentAlignment = Alignment.Center,
    ) {
        if (pulsing) {
            Box(
                modifier = Modifier
                    .size(size * pulse.value)
                    .clip(CircleShape)
                    .background(statusColor.copy(alpha = 0.35f), CircleShape),
            )
        }
        Box(
            modifier = Modifier
                .size(size)
                .clip(CircleShape)
                .background(statusColor, CircleShape),
        )
    }
}
