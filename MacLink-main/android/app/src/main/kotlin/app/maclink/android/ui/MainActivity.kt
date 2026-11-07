// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.ui

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import app.maclink.android.MacLinkApplication
import app.maclink.android.R
import app.maclink.android.core.Core
import app.maclink.android.core.CoreState
import app.maclink.android.core.CoreStatus
import app.maclink.android.core.LocalNetwork
import app.maclink.android.core.PairingState
import app.maclink.android.mirror.MirrorService
import app.maclink.android.recorder.RecorderService
import app.maclink.android.service.ConnectionService
import app.maclink.android.ui.deck.DeckScreen
import app.maclink.android.ui.guide.GuideHighlightTarget
import app.maclink.android.ui.home.HomeScreen
import app.maclink.android.ui.pairing.PairingActions
import app.maclink.android.ui.pairing.PairingScreen
import app.maclink.android.ui.recovery.KeyRecoveryScreen
import app.maclink.android.ui.recorder.RecorderScreen
import app.maclink.android.ui.remote.RemoteMode
import app.maclink.android.ui.remote.RemoteScreen
import app.maclink.android.ui.settings.SettingsScreen
import app.maclink.android.ui.theme.Appearance
import app.maclink.android.ui.theme.GlassBackdrop
import app.maclink.android.ui.theme.LocalReducedMotion
import app.maclink.android.ui.theme.MacLinkTheme
import app.maclink.android.ui.theme.glassBackdropSource
import app.maclink.android.ui.theme.liquidGlass
import app.maclink.android.ui.theme.liquidGlassCard
import app.maclink.android.ui.theme.AmberTokens
import app.maclink.android.ui.theme.HomeTabIcon
import app.maclink.android.ui.theme.SettingsGearIcon
import app.maclink.android.ui.theme.BookGuideIcon
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Arrangement
import app.maclink.android.ui.walkthrough.WalkthroughScreen
import app.maclink.android.ui.walkthrough.WalkthroughStep
import app.maclink.android.ui.walkthrough.resolveStartupWalkthrough
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    @Volatile
    private var activeRemotePcId: String? = null
    private var requestedRemotePc by mutableStateOf<String?>(null)
    private var requestedRemoteMode by mutableStateOf(RemoteMode.Touchpad)
    private var requestedDeckPc by mutableStateOf<String?>(null)
    private var requestedRecordPc by mutableStateOf<String?>(null)

    /**
     * A pairing link that arrived from outside the app (a web page, another app, the system
     * camera). Pairing waits for the user to confirm: any app or site can send such a link,
     * and pairing grants that PC this phone's notifications and messages.
     */
    private var pendingPairingLink by mutableStateOf<String?>(null)

    private val permissions =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
            // The local network may have just been allowed: reconnect now.
            (application as MacLinkApplication).core.refreshNotificationAccess()
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        val core = (application as MacLinkApplication).core
        val preferences = Preferences(this)

        // Notifications (transfers, calls, requests from PCs) and, on Android
        // 17, the local network, without which no PC can be reached.
        window.decorView.post {
            val wanted = buildList {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) add(Manifest.permission.POST_NOTIFICATIONS)
                if (LocalNetwork.needed()) add(LocalNetwork.PERMISSION)
            }.filter { checkSelfPermission(it) != android.content.pm.PackageManager.PERMISSION_GRANTED }
            if (wanted.isNotEmpty()) permissions.launch(wanted.toTypedArray())
        }
        if (savedInstanceState == null) {
            handlePairingLink(intent)
            handleRemoteIntent(intent)
            handleDeckIntent(intent)
            handleRecordIntent(intent)
            (application as MacLinkApplication).updater.checkAndAutoUpdateOnStart()
        }

        setContent {
            val appearance by preferences.appearance.collectAsStateWithLifecycle()
            val state by core.state.collectAsStateWithLifecycle()
            // Stay reachable in the background while a PC is paired.
            LaunchedEffect(state.devices.isNotEmpty(), state.status is CoreStatus.Ready) {
                if (state.devices.isNotEmpty()) {
                    ConnectionService.start(this@MainActivity)
                } else if (state.status is CoreStatus.Ready) {
                    ConnectionService.stop(this@MainActivity)
                }
            }
            MacLinkTheme(
                appearance = appearance,
                mediaSeedColor = state.activeMediaColor,
                backdrop = true,
            ) {
                // Every screen sits on the theme's background, not the
                // window's (which can't follow the app's own light/dark choice).
                Surface(color = MaterialTheme.colorScheme.background) {
                    App(
                        core = core,
                        state = state,
                        appearance = appearance,
                        preferences = preferences,
                        requestedRemotePc = requestedRemotePc,
                        requestedRemoteMode = requestedRemoteMode,
                        onRemoteConsumed = { requestedRemotePc = null },
                        requestedDeckPc = requestedDeckPc,
                        onDeckConsumed = { requestedDeckPc = null },
                        requestedRecordPc = requestedRecordPc,
                        onRecordConsumed = { requestedRecordPc = null },
                        onActiveRemoteChanged = { activeRemotePcId = it },
                    )
                    pendingPairingLink?.let { link ->
                        val pcName = remember(link) {
                            android.net.Uri.parse(link).getQueryParameter("n")?.trim()?.takeIf { it.isNotEmpty() }
                        } ?: stringResource(R.string.pair_link_unknown_pc)
                        androidx.compose.material3.AlertDialog(
                            onDismissRequest = { pendingPairingLink = null },
                            title = { Text(stringResource(R.string.pair_link_title, pcName)) },
                            text = { Text(stringResource(R.string.pair_link_body)) },
                            confirmButton = {
                                androidx.compose.material3.TextButton(onClick = {
                                    pendingPairingLink = null
                                    core.joinWhenReady(link)
                                }) { Text(stringResource(R.string.pair_link_confirm)) }
                            },
                            dismissButton = {
                                androidx.compose.material3.TextButton(onClick = { pendingPairingLink = null }) {
                                    Text(stringResource(R.string.pair_link_cancel))
                                }
                            },
                        )
                    }
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        val app = application as MacLinkApplication
        app.core.start()
        app.core.reconnectNow()
        if (app.core.state.value.devices.isNotEmpty()) {
            ConnectionService.start(this)
        }
    }

    override fun onResume() {
        super.onResume()
        // Back from Settings, maybe with notification access changed.
        val app = application as MacLinkApplication
        if (app.core.state.value.status is CoreStatus.Ready) {
            app.core.refreshNotificationAccess()
            app.core.reconnectNow()
        }
        if (app.updater.enabled) {
            // Back from allowing installs: the update the user started carries on.
            app.updater.onAppResumed()
            app.updater.checkAndAutoUpdateOnStart()
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handlePairingLink(intent)
        handleRemoteIntent(intent)
        handleDeckIntent(intent)
        handleRecordIntent(intent)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        val pcId = activeRemotePcId
        if (pcId != null) {
            when (keyCode) {
                KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    if (event?.repeatCount == 0) {
                        (application as MacLinkApplication).core.remoteSlide(pcId, "next")
                    }
                    return true
                }
                KeyEvent.KEYCODE_VOLUME_UP -> {
                    if (event?.repeatCount == 0) {
                        (application as MacLinkApplication).core.remoteSlide(pcId, "previous")
                    }
                    return true
                }
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (activeRemotePcId != null &&
            (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN || keyCode == KeyEvent.KEYCODE_VOLUME_UP)
        ) {
            return true
        }
        return super.onKeyUp(keyCode, event)
    }

    private fun handleRemoteIntent(intent: Intent?) {
        val pc = intent?.getStringExtra("remote_pc") ?: return
        val mode = intent.getStringExtra("remote_mode")
        requestedRemoteMode = when {
            mode.equals("presentation", ignoreCase = true) -> RemoteMode.Presentation
            mode.equals("air", ignoreCase = true) ||
                mode.equals("air_mouse", ignoreCase = true) ||
                mode.equals("airmouse", ignoreCase = true) -> RemoteMode.AirMouse
            else -> RemoteMode.Touchpad
        }
        requestedRemotePc = pc
    }

    private fun handleDeckIntent(intent: Intent?) {
        val pc = intent?.getStringExtra("deck_pc") ?: return
        requestedDeckPc = pc
    }

    private fun handleRecordIntent(intent: Intent?) {
        val pc = intent?.getStringExtra("record_pc") ?: return
        requestedRecordPc = pc
    }


    /**
     * A PC's pairing QR code opened from another app (e.g. the camera).
     * Each link holds a one-time secret, so a link is used once: Android
     * re-delivers the original intent when the task is restored or reopened
     * from Recents, and that must not start a stale pairing.
     */
    private fun handlePairingLink(intent: Intent?) {
        val link = intent?.takeIf { it.action == Intent.ACTION_VIEW }?.dataString ?: return
        if (!link.startsWith("maclink://pair?")) return
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        if (!PairingLinks(this).consume(link)) return
        pendingPairingLink = link
    }
}

private enum class Tab { Home, Settings }

private sealed interface ScreenRoute {
    data object Starting : ScreenRoute
    data class Failed(val message: String) : ScreenRoute
    data class KeyRecovery(val message: String, val causeChain: String) : ScreenRoute
    data object Walkthrough : ScreenRoute
    data object Pairing : ScreenRoute
    data class Recorder(val pcId: String) : ScreenRoute
    data class Deck(val pcId: String) : ScreenRoute
    data class Desk(val pcId: String) : ScreenRoute
    data class Remote(val pcId: String) : ScreenRoute
    data object Main : ScreenRoute
}

@Composable
private fun App(
    core: Core,
    state: CoreState,
    appearance: Appearance,
    preferences: Preferences,
    requestedRemotePc: String?,
    requestedRemoteMode: RemoteMode,
    onRemoteConsumed: () -> Unit,
    requestedDeckPc: String?,
    onDeckConsumed: () -> Unit,
    requestedRecordPc: String?,
    onRecordConsumed: () -> Unit,
    onActiveRemoteChanged: (String?) -> Unit,
) {
    var tab by rememberSaveable { mutableStateOf(Tab.Home) }
    var pairing by rememberSaveable { mutableStateOf(false) }
    var manualWalkthroughOpen by rememberSaveable { mutableStateOf(false) }
    var pendingHighlightTarget by rememberSaveable { mutableStateOf<GuideHighlightTarget?>(null) }
    var remotePcId by rememberSaveable { mutableStateOf<String?>(null) }
    var remoteInitialMode by rememberSaveable { mutableStateOf(RemoteMode.Touchpad) }
    var deckPcId by rememberSaveable { mutableStateOf<String?>(null) }
    var deskPcId by rememberSaveable { mutableStateOf<String?>(null) }
    var recordPcId by rememberSaveable { mutableStateOf<String?>(null) }
    val walkthroughPersistence by preferences.walkthrough.collectAsStateWithLifecycle()
    val startupWalkthrough = remember(walkthroughPersistence, state.devices.isNotEmpty()) {
        resolveStartupWalkthrough(
            persistence = walkthroughPersistence,
            hasPairedDevices = state.devices.isNotEmpty(),
        )
    }
    LaunchedEffect(state.status, startupWalkthrough.markCompletedAutomatically) {
        if (state.status is CoreStatus.Ready && startupWalkthrough.markCompletedAutomatically) {
            preferences.updateWalkthrough { it.copy(completed = true) }
        }
    }
    val snackbar = remember { SnackbarHostState() }
    val undoLabel = stringResource(R.string.send_queue_undo)
    LaunchedEffect(Unit) { core.messages.collect { snackbar.showSnackbar(it) } }
    LaunchedEffect(undoLabel) {
        core.queuedNotices.collectLatest { notice ->
            val result = snackbar.showSnackbar(
                message = notice.message,
                actionLabel = undoLabel,
                duration = androidx.compose.material3.SnackbarDuration.Short,
            )
            if (result == androidx.compose.material3.SnackbarResult.ActionPerformed) {
                if (notice.queueId != null) {
                    core.cancelQueueItem(notice.queueId)
                } else if (notice.peerId != null) {
                    core.cancelAllQueueItems(notice.peerId)
                }
            }
        }
    }
    LaunchedEffect(Unit) {
        core.clipSuggestions.collectLatest { notice ->
            val result = snackbar.showSnackbar(
                message = notice.message,
                actionLabel = notice.actionLabel,
                duration = androidx.compose.material3.SnackbarDuration.Short,
            )
            if (result == androidx.compose.material3.SnackbarResult.ActionPerformed) {
                core.runClipSuggestion(notice.suggestion)
            }
        }
    }

    LaunchedEffect(requestedRemotePc, state.devices) {
        val req = requestedRemotePc ?: return@LaunchedEffect
        val target = if (req == "first") state.devices.firstOrNull()?.id else state.device(req)?.id
        if (target != null) {
            recordPcId = null
            deckPcId = null
            deskPcId = null
            remoteInitialMode = requestedRemoteMode
            remotePcId = target
            onRemoteConsumed()
        }
    }

    LaunchedEffect(requestedDeckPc, state.devices) {
        val req = requestedDeckPc ?: return@LaunchedEffect
        val target = if (req == "first") state.devices.firstOrNull()?.id else state.device(req)?.id
        if (target != null) {
            remotePcId = null
            recordPcId = null
            deskPcId = null
            deckPcId = target
            onDeckConsumed()
        }
    }

    LaunchedEffect(requestedRecordPc, state.devices) {
        val req = requestedRecordPc ?: return@LaunchedEffect
        val target = if (req == "first") state.devices.firstOrNull()?.id else state.device(req)?.id
        if (target != null) {
            remotePcId = null
            deckPcId = null
            deskPcId = null
            recordPcId = target
            onRecordConsumed()
        }
    }


    val remoteDevice = remotePcId?.let { state.device(it) }
    val deckDevice = deckPcId?.let { state.device(it) }
    val deskDevice = deskPcId?.let { state.device(it) }
    val recordDevice = recordPcId?.let { state.device(it) }
    LaunchedEffect(remoteDevice?.id) {
        onActiveRemoteChanged(remoteDevice?.id)
    }

    val actions = remember(core) {
        object : PairingActions {
            override fun visible(open: Boolean) = core.setPairingScreenOpen(open)
            override fun join(link: String) = core.joinWithLink(link)
            override fun pairNearby(id: String) = core.pairNearby(id)
            override fun confirm(matches: Boolean) = core.confirmCode(matches)
            override fun reset() = core.resetPairing()
            override suspend fun showCode(): String? = core.pairingLink()
        }
    }

    val showWalkthrough = manualWalkthroughOpen ||
        (state.status is CoreStatus.Ready && startupWalkthrough.showWalkthrough)

    val currentRoute: ScreenRoute = when {
        state.status is CoreStatus.Starting -> ScreenRoute.Starting
        state.status is CoreStatus.KeyUnlockFailed -> ScreenRoute.KeyRecovery(
            message = state.status.message,
            causeChain = state.status.causeChain,
        )
        state.status is CoreStatus.Failed && state.status.message.contains("cannot unlock device key") -> ScreenRoute.KeyRecovery(
            message = state.status.message,
            causeChain = state.status.message,
        )
        state.status is CoreStatus.Failed -> ScreenRoute.Failed(state.status.message)
        showWalkthrough -> ScreenRoute.Walkthrough
        pairing || state.pairing != PairingState.Idle -> ScreenRoute.Pairing
        recordDevice != null -> ScreenRoute.Recorder(recordDevice.id)
        deckDevice != null -> ScreenRoute.Deck(deckDevice.id)
        deskDevice != null -> ScreenRoute.Desk(deskDevice.id)
        remoteDevice != null -> ScreenRoute.Remote(remoteDevice.id)
        else -> ScreenRoute.Main
    }

    val reducedMotion = LocalReducedMotion.current
    AnimatedContent(
        targetState = currentRoute,
        transitionSpec = {
            if (reducedMotion || initialState is ScreenRoute.Starting) {
                EnterTransition.None togetherWith ExitTransition.None
            } else {
                val enteringSubScreen = targetState !is ScreenRoute.Main && initialState is ScreenRoute.Main
                val returningToMain = targetState is ScreenRoute.Main && initialState !is ScreenRoute.Main
                val spatialSpring = androidx.compose.animation.core.spring<androidx.compose.ui.unit.IntOffset>(
                    dampingRatio = androidx.compose.animation.core.Spring.DampingRatioNoBouncy,
                    stiffness = androidx.compose.animation.core.Spring.StiffnessMediumLow,
                )
                val scaleSpring = androidx.compose.animation.core.spring<Float>(
                    dampingRatio = androidx.compose.animation.core.Spring.DampingRatioNoBouncy,
                    stiffness = androidx.compose.animation.core.Spring.StiffnessMediumLow,
                )
                when {
                    enteringSubScreen -> (
                        fadeIn(tween(210, easing = FastOutSlowInEasing)) +
                            slideInHorizontally(animationSpec = spatialSpring) { (it * 0.08f).toInt() } +
                            scaleIn(initialScale = 0.95f, animationSpec = scaleSpring)
                        ) togetherWith (
                        fadeOut(tween(150)) +
                            slideOutHorizontally(animationSpec = spatialSpring) { -(it * 0.04f).toInt() } +
                            scaleOut(targetScale = 0.97f, animationSpec = scaleSpring)
                        )
                    returningToMain -> (
                        fadeIn(tween(200, easing = FastOutSlowInEasing)) +
                            slideInHorizontally(animationSpec = spatialSpring) { -(it * 0.04f).toInt() } +
                            scaleIn(initialScale = 0.97f, animationSpec = scaleSpring)
                        ) togetherWith (
                        fadeOut(tween(150)) +
                            slideOutHorizontally(animationSpec = spatialSpring) { (it * 0.08f).toInt() } +
                            scaleOut(targetScale = 0.95f, animationSpec = scaleSpring)
                        )
                    else -> fadeIn(tween(200)) togetherWith fadeOut(tween(150))
                }
            }
        },
        label = "screen_route",
    ) { route ->
        when (route) {
            ScreenRoute.Starting -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                if (reducedMotion) {
                    CircularProgressIndicator(progress = { 0.75f })
                } else {
                    CircularProgressIndicator()
                }
            }
            is ScreenRoute.KeyRecovery -> KeyRecoveryScreen(
                message = route.message,
                causeChain = route.causeChain,
                onResetAndPair = {
                    core.recoverFromKeyUnlockFailure {
                        pairing = true
                    }
                },
            )
            is ScreenRoute.Failed -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.core_failed, route.message))
            }
            ScreenRoute.Walkthrough -> {
                BackHandler(
                    enabled = manualWalkthroughOpen && walkthroughPersistence.currentStep.previous == null,
                ) {
                    manualWalkthroughOpen = false
                }
                Scaffold(
                    snackbarHost = { SnackbarHost(snackbar) },
                ) { padding ->
                    WalkthroughScreen(
                        state = state,
                        step = walkthroughPersistence.currentStep,
                        pairingActions = actions,
                        onStepChange = { nextStep ->
                            preferences.updateWalkthrough { it.goToStep(nextStep) }
                        },
                        onSkip = {
                            core.resetPairing()
                            pairing = false
                            manualWalkthroughOpen = false
                            preferences.updateWalkthrough { it.copy(completed = true) }
                        },
                        onFinishToHome = {
                            core.resetPairing()
                            pairing = false
                            manualWalkthroughOpen = false
                            tab = Tab.Home
                            preferences.updateWalkthrough {
                                it.copy(completed = true, currentStepIndex = WalkthroughStep.Done.index)
                            }
                        },
                        onAccessChanged = core::refreshNotificationAccess,
                        modifier = Modifier.fillMaxSize().padding(padding),
                    )
                }
            }
            ScreenRoute.Pairing -> {
                BackHandler(enabled = pairing || state.devices.isNotEmpty()) { core.resetPairing(); pairing = false }
                PairingScreen(state, actions, cancellable = pairing || state.devices.isNotEmpty()) { pairing = false }
            }
            is ScreenRoute.Recorder -> {
                val dev = state.device(route.pcId) ?: return@AnimatedContent
                BackHandler { recordPcId = null }
                Scaffold(
                    snackbarHost = { SnackbarHost(snackbar) },
                ) { padding ->
                    RecorderScreen(
                        device = dev,
                        state = state,
                        core = core,
                        onBack = { recordPcId = null },
                        modifier = Modifier.fillMaxSize().padding(padding),
                    )
                }
            }
            is ScreenRoute.Deck -> {
                val dev = state.device(route.pcId) ?: return@AnimatedContent
                BackHandler { deckPcId = null }
                Scaffold(
                    snackbarHost = { SnackbarHost(snackbar) },
                ) { padding ->
                    DeckScreen(
                        device = dev,
                        core = core,
                        onBack = { deckPcId = null },
                        modifier = Modifier.fillMaxSize().padding(padding),
                    )
                }
            }
            is ScreenRoute.Desk -> {
                val dev = state.device(route.pcId) ?: return@AnimatedContent
                BackHandler { deskPcId = null }
                app.maclink.android.ui.desk.DeskScreen(
                    device = dev,
                    core = core,
                    onBack = { deskPcId = null },
                    onOpenRemote = { mode ->
                        val id = dev.id
                        deskPcId = null
                        remoteInitialMode = mode
                        remotePcId = id
                    },
                    onOpenDeck = {
                        val id = dev.id
                        deskPcId = null
                        deckPcId = id
                    },
                    modifier = Modifier.fillMaxSize(),
                )
            }
            is ScreenRoute.Remote -> {
                val dev = state.device(route.pcId) ?: return@AnimatedContent
                BackHandler { remotePcId = null }
                val sensitivity by preferences.touchpadSensitivity.collectAsStateWithLifecycle()
                Scaffold(
                    contentWindowInsets = androidx.compose.foundation.layout.WindowInsets(0, 0, 0, 0),
                    snackbarHost = { SnackbarHost(snackbar) },
                ) { padding ->
                    RemoteScreen(
                        device = dev,
                        core = core,
                        sensitivity = sensitivity,
                        initialMode = remoteInitialMode,
                        onBack = { remotePcId = null },
                        modifier = Modifier.fillMaxSize().padding(padding),
                    )
                }
            }
            ScreenRoute.Main -> Box(Modifier.fillMaxSize()) {
                val isGlass = appearance.theme == "glass"
                val glassBackdrop = app.maclink.android.ui.theme.rememberGlassBackdrop()
                val onlineCount by remember(state.devices) {
                    androidx.compose.runtime.derivedStateOf { state.devices.count { it.online } }
                }
                val pairedCount = state.devices.size
                Scaffold(
                    containerColor = androidx.compose.ui.graphics.Color.Transparent,
                    snackbarHost = { SnackbarHost(snackbar) },
                    bottomBar = {
                        FloatingBottomPillDock(
                            selectedTab = tab,
                            onSelectTab = { tab = it },
                            onlineCount = onlineCount,
                            pairedCount = pairedCount,
                            isGlass = isGlass,
                            reducedMotion = reducedMotion,
                            backdrop = glassBackdrop,
                        )
                    },
                ) { padding ->
                    val context = LocalContext.current
                    val mirrorSession by MirrorService.session.collectAsStateWithLifecycle()
                    val micStreamingTo by app.maclink.android.mic.MicService.streaming.collectAsStateWithLifecycle()
                    val recorderFlow = remember {
                        RecorderService.session.distinctUntilChanged { a, b ->
                            a.active == b.active &&
                                a.paused == b.paused &&
                                a.pcId == b.pcId &&
                                (a.elapsedMs / 1000L) == (b.elapsedMs / 1000L)
                        }
                    }
                    val recorderInitial = remember { RecorderService.currentSession() }
                    val recorderSession by recorderFlow.collectAsStateWithLifecycle(recorderInitial)
                    val touchpadSensitivity by preferences.touchpadSensitivity.collectAsStateWithLifecycle()
                    val suggestClipboardActions by preferences.suggestClipboardActions.collectAsStateWithLifecycle()
                    val backgroundServiceEnabled by preferences.backgroundServiceEnabled.collectAsStateWithLifecycle()
                    val hiveInviteShown by preferences.hiveInviteShown.collectAsStateWithLifecycle()
                    val saveableStateHolder = androidx.compose.runtime.saveable.rememberSaveableStateHolder()

                    // Only apply top scaffold padding here so LazyColumns in HomeScreen/SettingsScreen
                    // (which have bottom = 104.dp contentPadding) glide smoothly behind the floating glass dock.
                    // Tabs slide toward the side of the tab you picked, on a soft spring.
                    AnimatedContent(
                        targetState = tab,
                        transitionSpec = {
                            if (reducedMotion) {
                                EnterTransition.None togetherWith ExitTransition.None
                            } else {
                                val forward = targetState.ordinal > initialState.ordinal
                                val slide = androidx.compose.animation.core.spring<androidx.compose.ui.unit.IntOffset>(
                                    dampingRatio = 0.82f,
                                    stiffness = androidx.compose.animation.core.Spring.StiffnessMediumLow,
                                )
                                (
                                    slideInHorizontally(slide) { w -> if (forward) w / 6 else -w / 6 } +
                                        fadeIn(tween(220, easing = FastOutSlowInEasing))
                                    ) togetherWith (
                                    slideOutHorizontally(slide) { w -> if (forward) -w / 10 else w / 10 } +
                                        fadeOut(tween(120))
                                    )
                            }
                        },
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(top = padding.calculateTopPadding())
                            .glassBackdropSource(glassBackdrop, enabled = isGlass),
                        label = "main_tab",
                    ) { shownTab ->
                        when (shownTab) {
                            Tab.Home -> saveableStateHolder.SaveableStateProvider("tab_home") {
                                HomeScreen(
                                    state = state,
                                    onRing = core::ring,
                                    onStopRinging = core::stopRinging,
                                    onPairNew = { pairing = true },
                                    onRefresh = core::refresh,
                                    onPower = core::pcPower,
                                    onWake = core::wake,
                                    onRemote = { id ->
                                        remoteInitialMode = RemoteMode.Touchpad
                                        remotePcId = id
                                    },
                                    onDeck = { id ->
                                        deckPcId = id
                                    },
                                    onDesk = { id ->
                                        deskPcId = id
                                    },
                                    onRecord = { id ->
                                        recordPcId = id
                                    },
                                    
                                    updater = (context.applicationContext as MacLinkApplication).updater,
                                    onSendFiles = core::sendFiles,
                                    onSendFolder = core::sendFolder,
                                    onAccessChanged = core::refreshNotificationAccess,
                                    onCancelTransfer = core::cancelTransfer,
                                    onPauseTransfer = core::pauseTransfer,
                                    onResumeTransfer = core::resumeTransfer,
                                    onAcceptTransfer = core::acceptTransfer,
                                    onCancelQueueItem = core::cancelQueueItem,
                                    onCancelAllQueueItems = { core.cancelAllQueueItems(null) },
                                    onRetryQueueItem = core::retryQueueItem,
                                    onClearFinishedQueueItems = { core.clearFinishedQueueItems(null) },
                                    onRefreshLocalSend = core::refreshLocalSend,
                                    onAllowStorage = { pcId -> core.setStorageEnabled(pcId, true) },
                                    onDismissStorageRequest = core::dismissStorageRequest,
                                    
                                                                        onCopyClipboardHistory = core::copyClipboardHistory,
                                    onPinClipboardHistory = core::pinClipboardHistory,
                                    onDeleteClipboardHistory = core::deleteClipboardHistory,
                                    onClearClipboardHistory = core::clearClipboardHistory,
                                    loadClipboardHistoryImage = core::clipboardHistoryImage,
                                    queryTimelinePage = { kind, dev, search, offset ->
                                        core.queryTimelinePage(kind, dev, search, offset)
                                    },
                                    onDeleteTimelineEntry = core::deleteTimelineEntry,
                                    onClearTimeline = core::clearTimeline,
                                    onResendTimelineEntry = core::resendTimelineEntry,
                                    onSetPcAudio = core::setPcAudio,
                                    onStopKeyboardFromPc = core::stopKeyboardFromPc,
                                    onListPcFiles = core::listPcFiles,
                                    onDownloadPcFile = core::downloadPcFile,
                                    mirrorSession = mirrorSession,
                                                                        recorderSession = recorderSession,
                                    micStreamingTo = micStreamingTo,
                                    onDeclineMicRequest = core::declineMicRequest,
                                    onStartMic = { pcId ->
                                        // Asks for the microphone permission if needed, then starts.
                                        context.startActivity(
                                            android.content.Intent(context, app.maclink.android.mic.MicStartActivity::class.java)
                                                .putExtra(app.maclink.android.mic.MicStartActivity.EXTRA_PC, pcId),
                                        )
                                    },
                                    onStopMic = { app.maclink.android.mic.MicService.stopFromUser(context) },
                                    onStopMirror = { MirrorService.stopCurrent() },
                                    
                                                                        onOpenRecorder = { pcId -> recordPcId = pcId },
                                    onStopRecorder = { RecorderService.stop(context) },
                                    showWhatsNewGuideBanner = startupWalkthrough.showWhatsNewGuideBanner,
                                    showHiveInvite = false,
                                    onTryHive = { preferences.answerHiveInvite() },
                                    onDismissHiveInvite = preferences::answerHiveInvite,
                                    backgroundServiceEnabled = backgroundServiceEnabled,
                                    onTurnOnBackgroundService = {
                                        preferences.updateBackgroundServiceEnabled(true)
                                        core.start()
                                        ConnectionService.start(context)
                                    },
                                    onDismissWhatsNewGuide = {
                                        preferences.updateWalkthrough { it.dismissWhatsNewGuide() }
                                    },
                                    onOpenWalkthrough = {
                                        preferences.updateWalkthrough { it.goToStep(WalkthroughStep.Welcome) }
                                        manualWalkthroughOpen = true
                                    },
                                    highlightTarget = pendingHighlightTarget,
                                    onHighlightConsumed = { pendingHighlightTarget = null },
                                    modifier = Modifier.fillMaxSize(),
                                )
                            }
                            Tab.Settings -> saveableStateHolder.SaveableStateProvider("tab_settings") {
                                SettingsScreen(
                                    state = state,
                                    appearance = appearance,
                                    onAppearance = preferences::update,
                                    touchpadSensitivity = touchpadSensitivity,
                                    onTouchpadSensitivity = preferences::updateTouchpadSensitivity,
                                    onUnpair = core::unpair,
                                    onPairNew = { pairing = true },
                                    onAccessChanged = core::refreshNotificationAccess,
                                    updater = (context.applicationContext as MacLinkApplication).updater,
                                    onSetStorageEnabled = core::setStorageEnabled,
                                    onSetMicEnabled = core::setMicEnabled,
                                    onAddSafFolder = core::addSafFolder,
                                    onRemoveSafFolder = core::removeSafFolder,
                                    onSetClipboardHistoryEnabled = core::setClipboardHistoryEnabled,
                                    onClearClipboardHistory = core::clearClipboardHistory,
                                    suggestClipboardActions = suggestClipboardActions,
                                    onSetSuggestClipboardActions = preferences::updateSuggestClipboardActions,
                                    backgroundServiceEnabled = backgroundServiceEnabled,
                                    onToggleBackgroundService = { enabled ->
                                        preferences.updateBackgroundServiceEnabled(enabled)
                                        if (enabled) {
                                            core.start()
                                            ConnectionService.start(context)
                                        } else {
                                            ConnectionService.stop(context)
                                        }
                                    },
                                    onSetTimelineRetentionDays = core::setTimelineRetentionDays,
                                    onClearTimeline = core::clearTimeline,
                                    onClearMessageCache = core::clearMessageCache,
                                    onClearPhotoCache = core::clearPhotoThumbnailsCache,
                                    onClearReceivedFileHistory = core::clearReceivedFileHistory,
                                    onClearEverything = core::clearEverything,
                                    onToggleLocalSend = core::setLocalSendEnabled,
                                    onToggleAwayMode = core::setAwayMode,
                                    onOpenWalkthrough = {
                                        preferences.updateWalkthrough { it.goToStep(WalkthroughStep.Welcome) }
                                        manualWalkthroughOpen = true
                                    },
                                    highlightTarget = pendingHighlightTarget,
                                    onHighlightConsumed = { pendingHighlightTarget = null },
                                    modifier = Modifier.fillMaxSize(),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun FloatingBottomPillDock(
    selectedTab: Tab,
    onSelectTab: (Tab) -> Unit,
    onlineCount: Int,
    pairedCount: Int,
    isGlass: Boolean,
    reducedMotion: Boolean,
    backdrop: GlassBackdrop? = null,
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .windowInsetsPadding(androidx.compose.foundation.layout.WindowInsets.navigationBars)
            .padding(horizontal = 24.dp, vertical = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        // Floating liquid glass dock container
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(32.dp))
                .background(AmberTokens.GlassBackgroundSubtle, RoundedCornerShape(32.dp))
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
                            cornerRadius = CornerRadius(32.dp.toPx(), 32.dp.toPx()),
                            style = Stroke(width = stroke),
                        )
                    }
                }
                .padding(horizontal = 6.dp, vertical = 6.dp),
            horizontalArrangement = Arrangement.SpaceAround,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            FloatingDockTabPill(
                selected = selectedTab == Tab.Home,
                onClick = { onSelectTab(Tab.Home) },
                icon = HomeTabIcon,
                label = stringResource(R.string.home_title),
                modifier = Modifier.weight(1f),
            )
            FloatingDockTabPill(
                selected = selectedTab == Tab.Settings,
                onClick = { onSelectTab(Tab.Settings) },
                icon = SettingsGearIcon,
                label = stringResource(R.string.settings_title),
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun FloatingDockTabPill(
    selected: Boolean,
    onClick: () -> Unit,
    icon: ImageVector,
    label: String,
    modifier: Modifier = Modifier,
) {
    val interactionSource = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale = if (isPressed) 0.94f else 1.0f

    Box(
        modifier = modifier
            .scale(scale)
            .then(
                if (selected) {
                    Modifier
                        .drawBehind {
                            drawRoundRect(
                                color = Color(0x66F49D04),
                                cornerRadius = CornerRadius(22.dp.toPx(), 22.dp.toPx()),
                                size = Size(size.width + 6f, size.height + 6f),
                                topLeft = Offset(-3f, -3f),
                            )
                        }
                        .clip(RoundedCornerShape(22.dp))
                        .background(
                            brush = AmberTokens.PillActiveGradient,
                            shape = RoundedCornerShape(22.dp),
                        )
                        .drawWithCache {
                            val stroke = 1.dp.toPx()
                            val rim = Brush.linearGradient(
                                0f to AmberTokens.Highlight,
                                1f to AmberTokens.GlassBorderBright,
                            )
                            onDrawWithContent {
                                drawContent()
                                drawRoundRect(
                                    brush = rim,
                                    topLeft = Offset(stroke * 0.5f, stroke * 0.5f),
                                    size = Size(size.width - stroke, size.height - stroke),
                                    cornerRadius = CornerRadius(22.dp.toPx(), 22.dp.toPx()),
                                    style = Stroke(width = stroke),
                                )
                            }
                        }
                } else Modifier
            )
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                onClick = onClick,
            )
            .padding(vertical = 8.dp, horizontal = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = label,
                tint = if (selected) Color.White else AmberTokens.SecondaryText,
                modifier = Modifier.size(20.dp),
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = label,
                color = if (selected) Color.White else AmberTokens.SecondaryText,
                fontSize = 11.sp,
                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                maxLines = 1,
            )
        }
    }
}

