// SPDX-License-Identifier: MIT
package app.maclink.companion.presentation.touchpad

import android.view.MotionEvent
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInteropFilter
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.maclink.companion.gestureengine.GestureClassifier
import app.maclink.companion.gestureengine.GestureListener
import app.maclink.companion.gestureengine.HapticGestureTrigger
import app.maclink.companion.gestureengine.RecognizedGesture
import app.maclink.companion.haptics.HapticEngine
import app.maclink.companion.haptics.HapticProfile
import app.maclink.companion.networking.ConnectionState
import app.maclink.companion.networking.TouchpadConnectionListener
import app.maclink.companion.networking.TouchpadEnvelope
import app.maclink.companion.networking.TouchpadWebSocketClient
import app.maclink.companion.touchinput.CoordinateProcessor
import app.maclink.companion.touchinput.MotionEventHandler

@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun TouchpadScreen(
    hapticEngine: HapticEngine,
    client: TouchpadWebSocketClient?,
    connectedMacName: String = "MacBook Pro",
    modifier: Modifier = Modifier
) {
    var connectionState by remember { mutableStateOf(client?.state ?: ConnectionState.DISCONNECTED) }
    var latencyMs by remember { mutableLongStateOf(0L) }
    var sensitivity by remember { mutableFloatStateOf(1.0f) }
    var activeProfile by remember { mutableStateOf(hapticEngine.profileManager.activeProfile) }
    var showControls by remember { mutableStateOf(false) }

    val coordProcessor = remember { CoordinateProcessor(pointerSensitivity = sensitivity) }
    val classifier = remember {
        val c = GestureClassifier(coordProcessor)
        c.listener = object : GestureListener {
            override fun onGestureRecognized(gesture: RecognizedGesture) {
                client?.queueGesture(gesture)
            }

            override fun onHapticRequested(trigger: HapticGestureTrigger) {
                // Critical requirement: local haptic feedback fires immediately!
                hapticEngine.trigger(trigger)
            }
        }
        c
    }
    val motionHandler = remember { MotionEventHandler(classifier) }

    Surface(
        modifier = modifier.fillMaxSize(),
        color = Color(0xFF121316)
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            // ---- Minimal Top Status Bar ----
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .size(10.dp)
                            .clip(CircleShape)
                            .background(
                                when (connectionState) {
                                    ConnectionState.CONNECTED -> Color(0xFF34C759)
                                    ConnectionState.CONNECTING, ConnectionState.RECONNECTING -> Color(0xFFFF9500)
                                    ConnectionState.DISCONNECTED -> Color(0xFFFF3B30)
                                }
                            )
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = connectedMacName,
                        color = Color.White,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }

                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (connectionState == ConnectionState.CONNECTED && latencyMs > 0) {
                        Text(
                            text = "${latencyMs}ms",
                            color = Color(0xFF8E8E93),
                            fontSize = 13.sp
                        )
                        Spacer(modifier = Modifier.width(12.dp))
                    }
                    Button(
                        onClick = { showControls = !showControls },
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF24262B)),
                        shape = RoundedCornerShape(14.dp)
                    ) {
                        Text(text = if (showControls) "Hide" else "Settings", fontSize = 12.sp, color = Color.White)
                    }
                }
            }

            // ---- Optional Expandable Controls Tray ----
            if (showControls) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp)
                        .background(Color(0xFF1C1E24), RoundedCornerShape(12.dp))
                        .padding(14.dp)
                ) {
                    Text(text = "Sensitivity: ${(sensitivity * 100).toInt()}%", color = Color.White, fontSize = 13.sp)
                    Slider(
                        value = sensitivity,
                        onValueChange = {
                            sensitivity = it
                            coordProcessor.pointerSensitivity = it
                        },
                        valueRange = 0.5f..2.5f
                    )

                    Spacer(modifier = Modifier.height(6.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(text = "Haptic Profile:", color = Color.White, fontSize = 13.sp)
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            HapticProfile.entries.forEach { p ->
                                Button(
                                    onClick = {
                                        activeProfile = p
                                        hapticEngine.profileManager.activeProfile = p
                                        hapticEngine.trigger(HapticGestureTrigger.SINGLE_CLICK)
                                    },
                                    colors = ButtonDefaults.buttonColors(
                                        containerColor = if (activeProfile == p) Color(0xFFE5A93C) else Color(0xFF2C2F36)
                                    ),
                                    shape = RoundedCornerShape(8.dp)
                                ) {
                                    Text(
                                        text = p.name.lowercase().replaceFirstChar { it.uppercase() },
                                        fontSize = 11.sp,
                                        color = if (activeProfile == p) Color.Black else Color.White
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // ---- Full-Screen Touchpad Interactive Surface ----
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(10.dp)
                    .clip(RoundedCornerShape(16.dp))
                    .background(Color(0xFF181A1F))
                    .border(1.dp, Color(0xFF2C2F36), RoundedCornerShape(16.dp))
                    .pointerInteropFilter { event ->
                        motionHandler.handleMotionEvent(event)
                    },
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = "Trackpad Surface\n(Tap, Scroll, Pinch, 3/4-finger gestures)",
                    color = Color(0xFF3A3E48),
                    fontSize = 14.sp,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center
                )
            }

            // ---- Optional Physical Left / Right Click Strip ----
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 10.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Button(
                    onClick = {
                        hapticEngine.trigger(HapticGestureTrigger.SINGLE_CLICK)
                        client?.queueGesture(RecognizedGesture.Click(button = "left", count = 1))
                    },
                    modifier = Modifier.weight(1f).height(48.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF24262B)),
                    shape = RoundedCornerShape(10.dp)
                ) {
                    Text(text = "Left Click", color = Color.White)
                }

                Button(
                    onClick = {
                        hapticEngine.trigger(HapticGestureTrigger.RIGHT_CLICK)
                        client?.queueGesture(RecognizedGesture.Click(button = "right", count = 1))
                    },
                    modifier = Modifier.weight(1f).height(48.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF24262B)),
                    shape = RoundedCornerShape(10.dp)
                ) {
                    Text(text = "Right Click", color = Color.White)
                }
            }
        }
    }
}

