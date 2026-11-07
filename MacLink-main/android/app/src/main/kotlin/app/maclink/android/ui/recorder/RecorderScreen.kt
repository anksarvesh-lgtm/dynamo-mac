// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.ui.recorder

import android.Manifest
import android.media.MediaPlayer
import android.text.format.Formatter
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.maclink.android.R
import app.maclink.android.core.Core
import app.maclink.android.core.CoreState
import app.maclink.android.core.Device
import app.maclink.android.recorder.DeliveryState
import app.maclink.android.recorder.RecorderService
import app.maclink.android.recorder.SavedRecording
import app.maclink.android.ui.theme.LocalAppFonts
import app.maclink.android.ui.theme.LocalReducedMotion
import kotlin.math.sin
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun RecorderScreen(
    device: Device,
    state: CoreState,
    core: Core,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val initialSession = remember { RecorderService.currentSession() }
    val session by remember {
        RecorderService.session.distinctUntilChanged { a, b ->
            a.active == b.active &&
                a.paused == b.paused &&
                a.pcId == b.pcId &&
                a.markers == b.markers &&
                (a.elapsedMs / 1000L) == (b.elapsedMs / 1000L)
        }
    }.collectAsStateWithLifecycle(initialValue = initialSession)
    val recordings by core.recordings.recordings.collectAsStateWithLifecycle()

    var hasMicPermission by remember { mutableStateOf(RecorderService.hasPermission(context)) }
    var startAfterGrant by remember { mutableStateOf(false) }
    val askMic = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        hasMicPermission = granted
        if (granted && startAfterGrant) {
            startAfterGrant = false
            RecorderService.start(context, device.id)
        } else {
            startAfterGrant = false
        }
    }

    var markerText by rememberSaveable { mutableStateOf("") }
    var playingId by remember { mutableStateOf<String?>(null) }
    val playerRef = remember { mutableStateOf<MediaPlayer?>(null) }

    fun stopPlayback() {
        playerRef.value?.let { mp ->
            runCatching { mp.stop() }
            runCatching { mp.release() }
        }
        playerRef.value = null
        playingId = null
    }

    fun togglePlayback(rec: SavedRecording) {
        if (playingId == rec.id) {
            stopPlayback()
            return
        }
        stopPlayback()
        val file = core.recordings.fileFor(rec)
        if (!file.exists()) return
        runCatching {
            val mp = MediaPlayer().apply {
                setDataSource(file.absolutePath)
                setOnCompletionListener {
                    runCatching { release() }
                    if (playerRef.value === this) {
                        playerRef.value = null
                        playingId = null
                    }
                }
                prepare()
                start()
            }
            playerRef.value = mp
            playingId = rec.id
        }
    }

    DisposableEffect(Unit) {
        onDispose { stopPlayback() }
    }

    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Header: Back, PC name, online dot
        item(key = "header", contentType = "header") {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = onBack) {
                    Icon(
                        painter = painterResource(R.drawable.ic_back),
                        contentDescription = stringResource(R.string.action_back),
                    )
                }
                Spacer(Modifier.width(4.dp))
                Text(
                    device.name,
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.weight(1f),
                )
                val dotColor = if (device.online) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
                Spacer(
                    modifier = Modifier
                        .size(10.dp)
                        .drawBehind { drawCircle(dotColor) },
                )
            }
        }

        // Contextual permission card when microphone access has not been granted yet
        if (!hasMicPermission) {
            item(key = "mic_permission", contentType = "permission_banner") {
                Surface(
                    shape = MaterialTheme.shapes.extraLarge,
                    color = MaterialTheme.colorScheme.secondaryContainer,
                ) {
                    Column(Modifier.fillMaxWidth().padding(20.dp)) {
                        Text(
                            stringResource(R.string.recorder_permission_title),
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onSecondaryContainer,
                        )
                        Spacer(Modifier.height(4.dp))
                        Text(
                            stringResource(R.string.recorder_permission_text, device.name),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSecondaryContainer,
                        )
                        Spacer(Modifier.height(12.dp))
                        Button(
                            onClick = {
                                startAfterGrant = false
                                askMic.launch(Manifest.permission.RECORD_AUDIO)
                            },
                        ) {
                            Text(stringResource(R.string.recorder_allow_mic))
                        }
                    }
                }
            }
        }

        // Offline notice when PC isn't currently connected
        if (!device.online) {
            item(key = "offline_notice", contentType = "offline_banner") {
                Surface(
                    shape = MaterialTheme.shapes.large,
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                ) {
                    Column(Modifier.fillMaxWidth().padding(16.dp)) {
                        Text(
                            stringResource(R.string.transfer_waiting, device.name),
                            style = MaterialTheme.typography.titleSmall,
                        )
                        Spacer(Modifier.height(2.dp))
                        Text(
                            stringResource(R.string.recorder_offline_hint, device.name),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }

        // Main Recorder Card: elapsed time, live level meter, big record/pause/stop buttons, markers
        item(key = "recorder_card", contentType = "recorder_card") {
            Surface(
                shape = MaterialTheme.shapes.extraLarge,
                color = MaterialTheme.colorScheme.primaryContainer,
                contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
            ) {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        text = when {
                            session.active && session.paused -> stringResource(R.string.recorder_status_paused)
                            session.active -> stringResource(R.string.recorder_status_recording, device.name)
                            else -> stringResource(R.string.recorder_status_ready, device.name)
                        },
                        style = MaterialTheme.typography.labelLarge,
                    )
                    Spacer(Modifier.height(12.dp))
                    Text(
                        text = RecorderService.formatDuration(session.elapsedMs),
                        style = MaterialTheme.typography.displayMedium.copy(
                            fontFamily = LocalAppFonts.current.mono,
                        ),
                        maxLines = 1,
                        softWrap = false,
                    )
                    Spacer(Modifier.height(16.dp))

                    // Live level meter (collects 25Hz mic level internally in draw phase)
                    LevelMeter(
                        active = session.active && !session.paused,
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(40.dp),
                    )

                    Spacer(Modifier.height(24.dp))

                    if (!session.active) {
                        val startDesc = stringResource(R.string.recorder_start)
                        Button(
                            onClick = {
                                stopPlayback()
                                if (RecorderService.hasPermission(context)) {
                                    hasMicPermission = true
                                    RecorderService.start(context, device.id)
                                } else {
                                    startAfterGrant = true
                                    askMic.launch(Manifest.permission.RECORD_AUDIO)
                                }
                            },
                            modifier = Modifier
                                .height(64.dp)
                                .fillMaxWidth(0.75f)
                                .semantics { contentDescription = startDesc },
                            shape = CircleShape,
                        ) {
                            Text(
                                stringResource(R.string.recorder_start),
                                style = MaterialTheme.typography.titleMedium,
                            )
                        }
                    } else {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            val pauseResumeLabel = stringResource(
                                if (session.paused) R.string.recorder_resume else R.string.recorder_pause,
                            )
                            FilledTonalButton(
                                onClick = {
                                    if (session.paused) {
                                        RecorderService.resume(context)
                                    } else {
                                        RecorderService.pause(context)
                                    }
                                },
                                modifier = Modifier
                                    .height(56.dp)
                                    .weight(1f)
                                    .semantics { contentDescription = pauseResumeLabel },
                            ) {
                                Text(pauseResumeLabel, style = MaterialTheme.typography.titleMedium)
                            }

                            val stopLabel = stringResource(R.string.action_stop)
                            Button(
                                onClick = { RecorderService.stop(context) },
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = MaterialTheme.colorScheme.error,
                                    contentColor = MaterialTheme.colorScheme.onError,
                                ),
                                modifier = Modifier
                                    .height(56.dp)
                                    .weight(1f)
                                    .semantics { contentDescription = stopLabel },
                            ) {
                                Text(stopLabel, style = MaterialTheme.typography.titleMedium)
                            }
                        }

                        Spacer(Modifier.height(16.dp))

                        // Marker controls while recording
                        val markerHint = stringResource(R.string.recorder_marker_hint)
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            OutlinedTextField(
                                value = markerText,
                                onValueChange = { markerText = it },
                                placeholder = { Text(markerHint) },
                                singleLine = true,
                                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                                keyboardActions = KeyboardActions(
                                    onDone = {
                                        RecorderService.addMarker(markerText)
                                        markerText = ""
                                    },
                                ),
                                modifier = Modifier
                                    .weight(1f)
                                    .semantics { contentDescription = markerHint },
                            )
                            val addMarkerDesc = stringResource(R.string.recorder_add_marker)
                            FilledTonalButton(
                                onClick = {
                                    RecorderService.addMarker(markerText)
                                    markerText = ""
                                },
                                modifier = Modifier
                                    .height(52.dp)
                                    .semantics { contentDescription = addMarkerDesc },
                            ) {
                                Text(addMarkerDesc)
                            }
                        }

                        if (session.markers.isNotEmpty()) {
                            Spacer(Modifier.height(12.dp))
                            FlowRow(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                session.markers.forEachIndexed { idx, m ->
                                    val ts = RecorderService.formatDuration(m.atMs.toLong())
                                    val label = m.label ?: stringResource(R.string.recorder_marker_default, idx + 1)
                                    // A label, not a button: markers aren't actionable here.
                                    Text(
                                        text = stringResource(R.string.recorder_marker_chip, ts, label),
                                        style = MaterialTheme.typography.labelLarge,
                                        color = MaterialTheme.colorScheme.onSecondaryContainer,
                                        modifier = Modifier
                                            .background(MaterialTheme.colorScheme.secondaryContainer, RoundedCornerShape(8.dp))
                                            .padding(horizontal = 12.dp, vertical = 6.dp),
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        // Saved recordings list: play, send again, delete
        if (recordings.isNotEmpty()) {
            item(key = "saved_header", contentType = "section_header") {
                Text(
                    stringResource(R.string.recorder_saved_title),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
            items(recordings, key = { it.id }, contentType = { "recording_row" }) { rec ->
                RecordingRow(
                    recording = rec,
                    pcName = state.nameOf(rec.targetPcId ?: device.id) ?: device.name,
                    playing = playingId == rec.id,
                    onPlayToggle = { togglePlayback(rec) },
                    onSend = { core.sendSavedRecording(device.id, rec.id) },
                    onDelete = {
                        if (playingId == rec.id) stopPlayback()
                        core.recordings.delete(rec.id)
                    },
                )
            }
        }
    }
}

@Composable
private fun LevelMeter(
    active: Boolean,
    modifier: Modifier = Modifier,
) {
    val rawLevel by remember {
        RecorderService.session.map { if (it.active && !it.paused) it.level else 0f }.distinctUntilChanged()
    }.collectAsStateWithLifecycle(initialValue = 0f)
    val reducedMotion = LocalReducedMotion.current
    val animatedLevelState = animateFloatAsState(
        targetValue = if (active) rawLevel else 0f,
        animationSpec = if (reducedMotion) snap() else spring(),
        label = "micLevel",
    )
    val activeColor = MaterialTheme.colorScheme.primary
    val inactiveColor = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.2f)
    Canvas(modifier = modifier) {
        val level = animatedLevelState.value
        val barCount = 24
        val gap = 4.dp.toPx()
        val totalGaps = gap * (barCount - 1)
        val barWidth = ((size.width - totalGaps) / barCount).coerceAtLeast(2f)
        for (i in 0 until barCount) {
            val centerDist = kotlin.math.abs(i - (barCount - 1) / 2f) / (barCount / 2f)
            val envelope = (1f - centerDist * 0.55f)
            val wave = if (active) (0.18f + 0.82f * level * envelope + 0.06f * sin(i * 0.9f)).coerceIn(0.12f, 1f) else 0.12f
            val h = (size.height * wave).coerceAtLeast(4.dp.toPx())
            val x = i * (barWidth + gap)
            val y = (size.height - h) / 2f
            drawRoundRect(
                color = if (active && (i.toFloat() / barCount) <= (level * 1.25f + 0.15f)) activeColor else inactiveColor,
                topLeft = Offset(x, y),
                size = Size(barWidth, h),
                cornerRadius = CornerRadius(barWidth / 2f, barWidth / 2f),
            )
        }
    }
}

@Composable
private fun RecordingRow(
    recording: SavedRecording,
    pcName: String,
    playing: Boolean,
    onPlayToggle: () -> Unit,
    onSend: () -> Unit,
    onDelete: () -> Unit,
) {
    val context = LocalContext.current
    val title = recording.fileName.removeSuffix(".m4a")
    val durationText = RecorderService.formatDuration(recording.durationMs)
    val sizeText = Formatter.formatShortFileSize(context, recording.sizeBytes)
    val markersText = if (recording.markers.isEmpty()) {
        null
    } else {
        pluralStringResource(R.plurals.recorder_markers_count, recording.markers.size, recording.markers.size)
    }
    val statusText = when (recording.delivery) {
        DeliveryState.Waiting -> stringResource(R.string.transfer_waiting, pcName)
        DeliveryState.Sending -> stringResource(R.string.transfer_sending, pcName)
        DeliveryState.Sent -> stringResource(R.string.transfer_sent_to, pcName)
        DeliveryState.Denied -> stringResource(R.string.recorder_denied_text, pcName)
        DeliveryState.Failed -> stringResource(R.string.transfer_failed)
        DeliveryState.Idle -> null
    }

    Surface(
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceContainer,
    ) {
        Column(Modifier.fillMaxWidth().padding(16.dp)) {
            Text(
                title,
                style = MaterialTheme.typography.titleSmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(4.dp))
            val meta = listOfNotNull(durationText, sizeText, markersText, statusText).joinToString(" · ")
            Text(
                meta,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilledTonalButton(
                    onClick = onPlayToggle,
                    contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp),
                ) {
                    Text(stringResource(if (playing) R.string.action_stop else R.string.media_play))
                }
                OutlinedButton(
                    onClick = onSend,
                    contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp),
                ) {
                    Text(
                        stringResource(
                            if (recording.delivery == DeliveryState.Sent) R.string.recorder_send_again
                            else R.string.recorder_send_now,
                        ),
                    )
                }
                Spacer(Modifier.weight(1f))
                TextButton(
                    onClick = onDelete,
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
                ) {
                    Text(stringResource(R.string.recorder_delete))
                }
            }
        }
    }
}
