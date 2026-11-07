// SPDX-License-Identifier: GPL-3.0-or-later
// Generated from docs/design/tokens.json by `cargo xtask tokens`. Do not edit.
package app.maclink.android.ui.theme

import androidx.compose.runtime.Immutable
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color

/**
 * Amber Liquid Glass Design System Tokens
 * Reference: MacLink Amber Liquid Glass Edition
 */
object AmberTokens {
    // Primary Color System - Deep obsidian dark surfaces for crisp white text visibility
    val Background = Color(0xFF0E0C09)
    val DeepBackground = Color(0xFF080604)
    val DarkAmber = Color(0xFF2C1905)
    val BurntOrange = Color(0xFF422808)
    val BrownSurface = Color(0xFF33200A)
    val PrimaryAccent = Color(0xFFF49D04)
    val SecondaryAccent = Color(0xFFCB7501)
    val Highlight = Color(0xFFFFB52E)
    // High-contrast clean black & white text scale
    val PrimaryText = Color(0xFFFFFFFF)
    val SecondaryText = Color(0xEEFFFFFF)
    val MutedText = Color(0xB3FFFFFF)

    // Glass Styling Tokens
    val GlassBorder = Color(0x33FFFFFF)
    val GlassBorderBright = Color(0x75FFB52E)
    val GlassBorderSubtle = Color(0x1AFFFFFF)
    val GlassBackground = Color(0x66181109)
    val GlassBackgroundSubtle = Color(0x4D1A130A)
    val GlassBackgroundDark = Color(0x990A0806)
    val GlassInnerHighlight = Color(0x1EFFFFFF)
    val GlassShadowAmber = Color(0x40F49D04)
    val GlowGreen = Color(0xFF4ADE80)
    val GlowRed = Color(0xFFEF4444)
    val OnlineGreen = GlowGreen
    val OfflineGray = MutedText

    // Gradients
    val ActiveCardGradient = Brush.verticalGradient(
        listOf(
            Color(0xFFF49D04),
            Color(0xFFAC5A00)
        )
    )
    val CardGradient = Brush.verticalGradient(
        listOf(
            Color(0x80241A0E),
            Color(0x99140E07)
        )
    )
    val SurfaceGradient = Brush.verticalGradient(
        listOf(
            Color(0x802C1E10),
            Color(0x99100C08)
        )
    )
    val PillActiveGradient = Brush.horizontalGradient(
        listOf(
            Color(0xFFF49D04),
            Color(0xFFC76A00)
        )
    )
    val WaveGradient = Brush.horizontalGradient(
        listOf(
            Color(0x00F49D04),
            Color(0x4DF49D04),
            Color(0x99FFB52E),
            Color(0x4DF49D04),
            Color(0x00F49D04)
        )
    )
}

/** Material color roles of one theme variant. */
@Immutable
data class Palette(
    val primary: Color,
    val onPrimary: Color,
    val primaryContainer: Color,
    val onPrimaryContainer: Color,
    val secondaryContainer: Color,
    val onSecondaryContainer: Color,
    val surface: Color,
    val surfaceContainerLow: Color,
    val surfaceContainer: Color,
    val surfaceContainerHigh: Color,
    val surfaceContainerHighest: Color,
    val onSurface: Color,
    val onSurfaceVariant: Color,
    val outline: Color,
    val outlineVariant: Color,
)

/** A Bloom color preset: its seed swatch and light and dark palettes. */
@Immutable
data class Seed(val color: Color, val light: Palette, val dark: Palette)

object Tokens {
    const val DEFAULT_SEED = "honey"

    val bloomSeeds: Map<String, Seed> = linkedMapOf(
        "black" to Seed(
            color = Color(0xFF18181C),
            light = Palette(
                primary = Color(0xFF18181C),
                onPrimary = Color(0xFFFFFFFF),
                primaryContainer = Color(0xFFDCDCE2),
                onPrimaryContainer = Color(0xFF141418),
                secondaryContainer = Color(0xFFE5E5EB),
                onSecondaryContainer = Color(0xFF18181C),
                surface = Color(0xFFFAFAFC),
                surfaceContainerLow = Color(0xFFF4F4F7),
                surfaceContainer = Color(0xFFEEEEF2),
                surfaceContainerHigh = Color(0xFFE7E7EC),
                surfaceContainerHighest = Color(0xFFE0E0E6),
                onSurface = Color(0xFF111114),
                onSurfaceVariant = Color(0xFF43434A),
                outline = Color(0xFF73737C),
                outlineVariant = Color(0xFFC7C7D0),
            ),
            dark = Palette(
                primary = Color(0xFFE2E2EA),
                onPrimary = Color(0xFF141418),
                primaryContainer = Color(0xFF2E2E36),
                onPrimaryContainer = Color(0xFFF0F0F5),
                secondaryContainer = Color(0xFF26262E),
                onSecondaryContainer = Color(0xFFE2E2EA),
                surface = Color(0xFF0A0A0C),
                surfaceContainerLow = Color(0xFF060608),
                surfaceContainer = Color(0xFF141418),
                surfaceContainerHigh = Color(0xFF1E1E24),
                surfaceContainerHighest = Color(0xFF282830),
                onSurface = Color(0xFFECECF0),
                onSurfaceVariant = Color(0xFFC2C2CA),
                outline = Color(0xFF8E8E98),
                outlineVariant = Color(0xFF3E3E48),
            ),
        ),
        "honey" to Seed(
            color = Color(0xFFF49D04),
            light = Palette(
                primary = Color(0xFF894F03),
                onPrimary = Color(0xFFFFFFFF),
                primaryContainer = Color(0xFFFFB52E),
                onPrimaryContainer = Color(0xFF1A1008),
                secondaryContainer = Color(0xFF6D4510),
                onSecondaryContainer = Color(0xFFF3F0E8),
                surface = Color(0xFFFFF8F3),
                surfaceContainerLow = Color(0xFFFBF2EB),
                surfaceContainer = Color(0xFFF5ECE4),
                surfaceContainerHigh = Color(0xFFEFE6DE),
                surfaceContainerHighest = Color(0xFFE9E1D9),
                onSurface = Color(0xFF1F1B16),
                onSurfaceVariant = Color(0xFF51453A),
                outline = Color(0xFF837468),
                outlineVariant = Color(0xFFD5C3B5),
            ),
            dark = Palette(
                primary = Color(0xFFF49D04),
                onPrimary = Color(0xFF1A1008),
                primaryContainer = Color(0xFF894F03),
                onPrimaryContainer = Color(0xFFF3F0E8),
                secondaryContainer = Color(0xFF603606),
                onSecondaryContainer = Color(0xFFB5A18B),
                surface = Color(0xFF221A0F),
                surfaceContainerLow = Color(0xFF1A1008),
                surfaceContainer = Color(0xFF6D4510),
                surfaceContainerHigh = Color(0xFF894F03),
                surfaceContainerHighest = Color(0xFF603606),
                onSurface = Color(0xFFF3F0E8),
                onSurfaceVariant = Color(0xFFB5A18B),
                outline = Color(0xFF897360),
                outlineVariant = Color(0x35FFFFFF),
            ),
        ),
        "lavender" to Seed(
            color = Color(0xFF7E6AA8),
            light = Palette(
                primary = Color(0xFF65558F),
                onPrimary = Color(0xFFFFFFFF),
                primaryContainer = Color(0xFFE9DDFF),
                onPrimaryContainer = Color(0xFF201047),
                secondaryContainer = Color(0xFFE8DEF8),
                onSecondaryContainer = Color(0xFF1D192B),
                surface = Color(0xFFFDF7FF),
                surfaceContainerLow = Color(0xFFF7F2FA),
                surfaceContainer = Color(0xFFF2ECF4),
                surfaceContainerHigh = Color(0xFFECE6EE),
                surfaceContainerHighest = Color(0xFFE6E0E9),
                onSurface = Color(0xFF1D1B20),
                onSurfaceVariant = Color(0xFF49454E),
                outline = Color(0xFF7A757F),
                outlineVariant = Color(0xFFCAC4CF),
            ),
            dark = Palette(
                primary = Color(0xFFCFBDFE),
                onPrimary = Color(0xFF36275D),
                primaryContainer = Color(0xFF4D3D75),
                onPrimaryContainer = Color(0xFFE9DDFF),
                secondaryContainer = Color(0xFF4A4458),
                onSecondaryContainer = Color(0xFFE8DEF8),
                surface = Color(0xFF141218),
                surfaceContainerLow = Color(0xFF0F0D13),
                surfaceContainer = Color(0xFF211F24),
                surfaceContainerHigh = Color(0xFF2B292F),
                surfaceContainerHighest = Color(0xFF36343A),
                onSurface = Color(0xFFE6E0E9),
                onSurfaceVariant = Color(0xFFCAC4CF),
                outline = Color(0xFF948F99),
                outlineVariant = Color(0xFF49454E),
            ),
        ),
        "ocean" to Seed(
            color = Color(0xFF3D7DA8),
            light = Palette(
                primary = Color(0xFF2F628C),
                onPrimary = Color(0xFFFFFFFF),
                primaryContainer = Color(0xFFCEE5FF),
                onPrimaryContainer = Color(0xFF001D33),
                secondaryContainer = Color(0xFFD5E4F7),
                onSecondaryContainer = Color(0xFF0E1D2A),
                surface = Color(0xFFF7F9FF),
                surfaceContainerLow = Color(0xFFF1F4FA),
                surfaceContainer = Color(0xFFECEEF4),
                surfaceContainerHigh = Color(0xFFE6E8EE),
                surfaceContainerHighest = Color(0xFFE0E2E8),
                onSurface = Color(0xFF181C20),
                onSurfaceVariant = Color(0xFF42474E),
                outline = Color(0xFF72777F),
                outlineVariant = Color(0xFFC2C7CF),
            ),
            dark = Palette(
                primary = Color(0xFF9BCBFB),
                onPrimary = Color(0xFF003354),
                primaryContainer = Color(0xFF0F4A73),
                onPrimaryContainer = Color(0xFFCEE5FF),
                secondaryContainer = Color(0xFF3B4858),
                onSecondaryContainer = Color(0xFFD5E4F7),
                surface = Color(0xFF101418),
                surfaceContainerLow = Color(0xFF0B0F13),
                surfaceContainer = Color(0xFF1C2024),
                surfaceContainerHigh = Color(0xFF262A2F),
                surfaceContainerHighest = Color(0xFF31353A),
                onSurface = Color(0xFFE0E2E8),
                onSurfaceVariant = Color(0xFFC2C7CF),
                outline = Color(0xFF8C9199),
                outlineVariant = Color(0xFF42474E),
            ),
        ),
        "sage" to Seed(
            color = Color(0xFF5B8C5A),
            light = Palette(
                primary = Color(0xFF3B6939),
                onPrimary = Color(0xFFFFFFFF),
                primaryContainer = Color(0xFFBCF0B4),
                onPrimaryContainer = Color(0xFF002204),
                secondaryContainer = Color(0xFFD6E8CF),
                onSecondaryContainer = Color(0xFF111F0F),
                surface = Color(0xFFF7FBF1),
                surfaceContainerLow = Color(0xFFF1F5EB),
                surfaceContainer = Color(0xFFEBEFE5),
                surfaceContainerHigh = Color(0xFFE6E9E0),
                surfaceContainerHighest = Color(0xFFE0E4DA),
                onSurface = Color(0xFF191D17),
                onSurfaceVariant = Color(0xFF424940),
                outline = Color(0xFF72796F),
                outlineVariant = Color(0xFFC2C8BD),
            ),
            dark = Palette(
                primary = Color(0xFFA1D39A),
                onPrimary = Color(0xFF0A390F),
                primaryContainer = Color(0xFF234F24),
                onPrimaryContainer = Color(0xFFBCF0B4),
                secondaryContainer = Color(0xFF3B4B38),
                onSecondaryContainer = Color(0xFFD6E8CF),
                surface = Color(0xFF10140F),
                surfaceContainerLow = Color(0xFF0C100B),
                surfaceContainer = Color(0xFF1D211B),
                surfaceContainerHigh = Color(0xFF272B25),
                surfaceContainerHighest = Color(0xFF32362F),
                onSurface = Color(0xFFE0E4DA),
                onSurfaceVariant = Color(0xFFC2C8BD),
                outline = Color(0xFF8C9388),
                outlineVariant = Color(0xFF424940),
            ),
        ),
    )

    val graphitePaper = Palette(
        primary = Color(0xFF1A1918),
        onPrimary = Color(0xFFF5F2EB),
        primaryContainer = Color(0xFFE8E3D7),
        onPrimaryContainer = Color(0xFF1A1918),
        secondaryContainer = Color(0xFFE8E3D7),
        onSecondaryContainer = Color(0xFF1A1918),
        surface = Color(0xFFF5F2EB),
        surfaceContainerLow = Color(0xFFF1EDE4),
        surfaceContainer = Color(0xFFF5F2EB),
        surfaceContainerHigh = Color(0xFFEFEBE2),
        surfaceContainerHighest = Color(0xFFE8E3D7),
        onSurface = Color(0xFF1A1918),
        onSurfaceVariant = Color(0xFF5E5A54),
        outline = Color(0xFF4A4743),
        outlineVariant = Color(0xFFD5CFC2),
    )

    val graphiteSlate = Palette(
        primary = Color(0xFFE8EAED),
        onPrimary = Color(0xFF0D0D0E),
        primaryContainer = Color(0xFF1A1A1D),
        onPrimaryContainer = Color(0xFFE8EAED),
        secondaryContainer = Color(0xFF1A1A1D),
        onSecondaryContainer = Color(0xFFE8EAED),
        surface = Color(0xFF0D0D0E),
        surfaceContainerLow = Color(0xFF0B0B0C),
        surfaceContainer = Color(0xFF0D0D0E),
        surfaceContainerHigh = Color(0xFF141416),
        surfaceContainerHighest = Color(0xFF1A1A1D),
        onSurface = Color(0xFFE8EAED),
        onSurfaceVariant = Color(0xFF9A9CA1),
        outline = Color(0xFF7E8084),
        outlineVariant = Color(0xFF26272A),
    )

    val hiveWax = Palette(
        primary = Color(0xFF8A5100),
        onPrimary = Color(0xFFFFFFFF),
        primaryContainer = Color(0xFFFFDDB3),
        onPrimaryContainer = Color(0xFF2C1600),
        secondaryContainer = Color(0xFFF4E3CD),
        onSecondaryContainer = Color(0xFF2A1F14),
        surface = Color(0xFFFFF8F3),
        surfaceContainerLow = Color(0xFFFCF2E9),
        surfaceContainer = Color(0xFFF8ECE1),
        surfaceContainerHigh = Color(0xFFF3E5D7),
        surfaceContainerHighest = Color(0xFFEDDDCD),
        onSurface = Color(0xFF1F1B16),
        onSurfaceVariant = Color(0xFF5C4F43),
        outline = Color(0xFF85766A),
        outlineVariant = Color(0xFFDDCBBA),
    )

    val hiveComb = Palette(
        primary = Color(0xFFFFB95F),
        onPrimary = Color(0xFF2C1600),
        primaryContainer = Color(0xFF5A3A0E),
        onPrimaryContainer = Color(0xFFFFDDB3),
        secondaryContainer = Color(0xFF2F2A24),
        onSecondaryContainer = Color(0xFFF0E0CC),
        surface = Color(0xFF121214),
        surfaceContainerLow = Color(0xFF151517),
        surfaceContainer = Color(0xFF1A1A1D),
        surfaceContainerHigh = Color(0xFF212124),
        surfaceContainerHighest = Color(0xFF29292D),
        onSurface = Color(0xFFEDE6DD),
        onSurfaceVariant = Color(0xFFABA195),
        outline = Color(0xFF8D8379),
        outlineVariant = Color(0xFF34312D),
    )

    val hiveWaxWarning = Color(0xFF7A4A00)
    val hiveWaxError = Color(0xFF9E2B25)
    val hiveCombWarning = Color(0xFFF5D58A)
    val hiveCombError = Color(0xFFF0A39C)

    /** The honeycomb backdrop (themes.hive.comb). */
    const val COMB_CELL_DP = 24f
    const val COMB_LINE_ALPHA_DARK = 0.27f
    const val COMB_LINE_ALPHA_LIGHT = 0.11f
    const val COMB_GLOW_ALPHA_DARK = 0.7f
    const val COMB_GLOW_ALPHA_LIGHT = 0.75f
    const val COMB_BREATH_SECONDS = 6f
    const val COMB_PULSE_SECONDS = 4.5f
    const val COMB_FRAME_MS = 33L

    val warningLight = Color(0xFF7D5200)
    val warningDark = Color(0xFFF2C14E)
    val errorLight = Color(0xFFBA1A1A)
    val errorDark = Color(0xFFFFB4AB)
}
