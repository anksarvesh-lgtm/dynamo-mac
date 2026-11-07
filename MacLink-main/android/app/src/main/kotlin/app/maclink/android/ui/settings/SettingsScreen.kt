// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.ui.settings

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.compose.foundation.Image
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.runtime.rememberCoroutineScope
import kotlinx.coroutines.launch
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import app.maclink.android.ui.AppLanguage
import androidx.compose.material3.RadioButton
import androidx.compose.foundation.selection.selectable
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import android.app.Activity
import app.maclink.android.BuildConfig
import app.maclink.android.R
import app.maclink.android.calls.PhoneCalls
import app.maclink.android.telephony.TelephonySettings
import app.maclink.android.companion.PcCompanion
import app.maclink.android.contacts.PhoneContacts
import app.maclink.android.elevated.Elevated
import app.maclink.android.elevated.PairingNotification
import app.maclink.android.mirror.InputService
import app.maclink.android.photos.RecentPhotos
import app.maclink.android.sms.PhoneSms
import app.maclink.android.storage.PhoneStorage
import app.maclink.android.toggles.PhoneToggles
import app.maclink.android.update.AppUpdater
import app.maclink.android.update.CheckForUpdates
import app.maclink.android.core.BackgroundAccess
import app.maclink.android.core.CoreState
import app.maclink.android.core.Device
import androidx.compose.ui.draw.drawBehind
import app.maclink.android.notifications.NotificationListener
import app.maclink.android.ui.guide.GuideHighlightTarget
import app.maclink.android.ui.theme.Appearance
import app.maclink.android.ui.theme.LocalGlassTheme
import app.maclink.android.ui.theme.Tokens
import app.maclink.android.ui.theme.AmberTokens
import app.maclink.android.ui.theme.LiquidGlassCard
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import app.maclink.android.ui.theme.glassModalBlur
import app.maclink.android.ui.theme.glassModalContainerColor
import app.maclink.android.ui.theme.liquidGlassCard
import kotlinx.coroutines.delay

@Composable
fun SettingsScreen(
    state: CoreState,
    appearance: Appearance,
    onAppearance: ((Appearance) -> Appearance) -> Unit,
    touchpadSensitivity: Float,
    onTouchpadSensitivity: (Float) -> Unit,
    onUnpair: (String) -> Unit,
    onPairNew: () -> Unit,
    onAccessChanged: () -> Unit,
    updater: AppUpdater,
    onSetStorageEnabled: (pcId: String, enabled: Boolean) -> Unit = { _, _ -> },
    onSetMicEnabled: (pcId: String, enabled: Boolean) -> Unit = { _, _ -> },
    onAddSafFolder: (Uri) -> Unit = {},
    onRemoveSafFolder: (String) -> Unit = {},
    onSetClipboardHistoryEnabled: (Boolean) -> Unit = {},
    onClearClipboardHistory: () -> Unit = {},
    suggestClipboardActions: Boolean = true,
    onSetSuggestClipboardActions: (Boolean) -> Unit = {},
    backgroundServiceEnabled: Boolean = true,
    onToggleBackgroundService: (Boolean) -> Unit = {},
    onSetTimelineRetentionDays: (UInt) -> Unit = {},
    onClearTimeline: () -> Unit = {},
    onClearMessageCache: () -> Unit = {},
    onClearPhotoCache: () -> Unit = {},
    onClearReceivedFileHistory: () -> Unit = {},
    onClearEverything: () -> Unit = {},
    onToggleLocalSend: (Boolean) -> Unit = {},
    onToggleAwayMode: (Boolean) -> Unit = {},
    onOpenWalkthrough: () -> Unit = {},
    onOpenFeaturesGuide: () -> Unit = {},
    highlightTarget: GuideHighlightTarget? = null,
    onHighlightConsumed: () -> Unit = {},
    modifier: Modifier = Modifier,
) {
    var confirmUnpair by remember { mutableStateOf<Device?>(null) }
    var confirmClearEverything by remember { mutableStateOf(false) }
    var pickLanguage by remember { mutableStateOf(false) }
    var activeCategory by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf("all") }
    var pulsingSectionKey by remember { mutableStateOf<String?>(null) }
    val isGlass = LocalGlassTheme.current
    val anyDialogOpen = confirmUnpair != null || confirmClearEverything

    val categories = remember {
        listOf(
            "all" to R.string.timeline_filter_all,
            "appearance" to R.string.settings_appearance,
            "devices" to R.string.settings_category_devices,
            "permissions" to R.string.walkthrough_permissions_title,
            "features" to R.string.settings_category_features,
        )
    }

    val showAppearance = activeCategory == "all" || activeCategory == "appearance"
    val showDevices = activeCategory == "all" || activeCategory == "devices"
    val showPermissions = activeCategory == "all" || activeCategory == "permissions"
    val showFeatures = activeCategory == "all" || activeCategory == "features"

    // Keep a screen of cards composed on each side, so scrolling back does not rebuild them.
    @OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
    val listState = androidx.compose.foundation.lazy.rememberLazyListState(
        cacheWindow = androidx.compose.foundation.lazy.layout.LazyLayoutCacheWindow(aheadFraction = 1f, behindFraction = 1f),
    )

    androidx.compose.runtime.LaunchedEffect(highlightTarget) {
        val target = highlightTarget ?: return@LaunchedEffect
        val mapping = when (target) {
            GuideHighlightTarget.SETTINGS_DEVICES -> Triple("devices", "devices", 1)
            GuideHighlightTarget.SETTINGS_NOTIFICATIONS -> Triple("permissions", "notifications", 1)
            GuideHighlightTarget.SETTINGS_CONTROL -> Triple("permissions", "control", 2)
            GuideHighlightTarget.SETTINGS_BACKGROUND -> Triple("permissions", "background", 3)
            GuideHighlightTarget.SETTINGS_CALLS_CONTACTS -> Triple("permissions", "calls_contacts", 4)
            GuideHighlightTarget.SETTINGS_PHOTOS_STORAGE -> Triple("permissions", "photos", 5)
            GuideHighlightTarget.SETTINGS_CLIPBOARD -> Triple("features", "clipboard", 1)
            GuideHighlightTarget.SETTINGS_LOCALSEND -> Triple("features", "localsend", 3)
            GuideHighlightTarget.SETTINGS_DATA_STORAGE -> Triple("features", "data_storage", 4)
            else -> null
        }
        if (mapping != null) {
            val (category, sectionKey, indexInCat) = mapping
            activeCategory = category
            pulsingSectionKey = sectionKey
            onHighlightConsumed()
            delay(60)
            runCatching { listState.animateScrollToItem(indexInCat) }
            delay(2200)
            if (pulsingSectionKey == sectionKey) {
                pulsingSectionKey = null
            }
        } else {
            onHighlightConsumed()
        }
    }

    LazyColumn(
        state = listState,
        modifier = modifier.glassModalBlur(isGlass && anyDialogOpen),
        contentPadding = PaddingValues(start = 16.dp, top = 16.dp, end = 16.dp, bottom = 104.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item(key = "header", contentType = "header") {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    stringResource(R.string.settings_title),
                    style = MaterialTheme.typography.headlineMedium,
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                )
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    categories.forEach { (id, label) ->
                        val selected = activeCategory == id
                        FilterChip(
                            selected = selected,
                            onClick = { activeCategory = id },
                            label = { Text(stringResource(label)) },
                            // Solid like the cards: the row sits right on the
                            // background (Hive's comb showed through).
                            colors = FilterChipDefaults.filterChipColors(
                                containerColor = MaterialTheme.colorScheme.surfaceContainer,
                                selectedContainerColor = MaterialTheme.colorScheme.primaryContainer,
                                selectedLabelColor = MaterialTheme.colorScheme.onPrimaryContainer,
                            ),
                        )
                    }
                }
            }
        }

        if (showAppearance) {
            item(key = "appearance", contentType = "section") {
                Section(stringResource(R.string.settings_appearance)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(stringResource(R.string.settings_theme), style = MaterialTheme.typography.titleSmall)
                            Text(
                                "Apple Liquid Glass UI",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Text(
                            "Liquid Glass",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                    SettingRowDivider()
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(stringResource(R.string.settings_mode), style = MaterialTheme.typography.titleSmall)
                            Text(
                                "Matches system appearance automatically",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Text(
                            stringResource(R.string.mode_system),
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                    SettingRowDivider()
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(stringResource(R.string.settings_dynamic_color), style = MaterialTheme.typography.titleSmall)
                            Text(
                                "Frosted glass translucency over wallpaper",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Text(
                            "Active",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                    if (AppLanguage.supported) {
                        SettingRowDivider()
                        // System and English, plus the language picked from the list (or More).
                        val context = LocalContext.current
                        val language = remember { AppLanguage.current(context) }
                        val other = AppLanguage.languages.firstOrNull { it.first == language && it.first != "en" }
                        Label(stringResource(R.string.settings_language))
                        Choice(
                            listOf(
                                "" to stringResource(R.string.mode_system),
                                "en" to "English",
                                (other ?: (MORE_LANGUAGES to stringResource(R.string.settings_language_more))),
                            ),
                            language,
                        ) { value ->
                            if (value == "" || value == "en") AppLanguage.set(context, value) else pickLanguage = true
                        }
                    }
                }
            }
        }

        if (showDevices) {
            item(key = "devices", contentType = "section") {
                Section(
                    title = stringResource(R.string.settings_devices),
                    highlighted = pulsingSectionKey == "devices",
                ) {
                    val context = LocalContext.current
                    state.devices.forEachIndexed { index, device ->
                        if (index > 0) {
                            SettingRowDivider()
                        }
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                                Column(Modifier.weight(1f).padding(end = 12.dp)) {
                                    Text(device.name, style = MaterialTheme.typography.titleSmall)
                                    val dotColor = if (device.online) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
                                    Row(
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                                    ) {
                                        Spacer(
                                            modifier = Modifier
                                                .size(8.dp)
                                                .drawBehind { drawCircle(dotColor) },
                                        )
                                        Text(
                                            stringResource(if (device.online) R.string.connected else R.string.not_connected),
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                }
                                OutlinedButton(onClick = { confirmUnpair = device }) { Text(stringResource(R.string.action_unpair)) }
                            }
                            val storageToggleTitle = stringResource(R.string.storage_pc_toggle)
                            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                                Column(Modifier.weight(1f).padding(end = 12.dp)) {
                                    Text(storageToggleTitle, style = MaterialTheme.typography.bodyMedium)
                                    Text(
                                        stringResource(R.string.storage_pc_toggle_hint),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                                Switch(
                                    checked = device.storageEnabled,
                                    onCheckedChange = { enabled ->
                                        onSetStorageEnabled(device.id, enabled)
                                        if (enabled && !state.storageAllFilesAccess && state.storageSafFolders.isEmpty()) {
                                            runCatching { context.startActivity(PhoneStorage.allFilesAccessIntent(context)) }
                                        }
                                    },
                                    colors = app.maclink.android.ui.theme.maclinkSwitchColors(),
                                    modifier = Modifier.semantics { contentDescription = storageToggleTitle },
                                )
                            }
                            if (!device.isAndroid) {
                                val micToggleTitle = stringResource(R.string.mic_pc_toggle)
                                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                                    Column(Modifier.weight(1f).padding(end = 12.dp)) {
                                        Text(micToggleTitle, style = MaterialTheme.typography.bodyMedium)
                                        Text(
                                            stringResource(R.string.mic_pc_toggle_hint),
                                            style = MaterialTheme.typography.bodySmall,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        )
                                    }
                                    Switch(
                                        checked = device.micEnabled,
                                        onCheckedChange = { enabled -> onSetMicEnabled(device.id, enabled) },
                                        colors = app.maclink.android.ui.theme.maclinkSwitchColors(),
                                        modifier = Modifier.semantics { contentDescription = micToggleTitle },
                                    )
                                }
                            }
                        }
                    }
                    FilledTonalButton(onClick = onPairNew) { Text(stringResource(R.string.action_pair_new)) }

                }
            }
        }

        if (showPermissions) {
            item(key = "notifications", contentType = "section") {
                Section(
                    title = stringResource(R.string.settings_notifications),
                    highlighted = pulsingSectionKey == "notifications",
                ) {
                    NotificationAccess(state.notificationAccess)
                }
            }

            item(key = "control", contentType = "section") {
                Section(
                    title = stringResource(R.string.settings_control),
                    highlighted = pulsingSectionKey == "control",
                ) {
                    ControlAccess(state.inputAccess)
                    SettingRowDivider()
                    ElevatedAccess()
                    SettingRowDivider()
                    BankingPauseAccess()
                    SettingRowDivider()
                    DndAccess(state.dndAccess)
                    SettingRowDivider()
                    WriteSettingsAccess(state.writeSettingsAccess || state.elevated)
                }
            }

            item(key = "background", contentType = "section") {
                Section(
                    title = stringResource(R.string.settings_background_title),
                    highlighted = pulsingSectionKey == "background",
                ) {
                    val runInBackgroundTitle = stringResource(R.string.settings_run_in_background)
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.weight(1f).padding(end = 12.dp)) {
                            Text(runInBackgroundTitle, style = MaterialTheme.typography.titleSmall)
                            Text(
                                stringResource(R.string.settings_run_in_background_hint),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = backgroundServiceEnabled,
                            onCheckedChange = onToggleBackgroundService,
                            colors = app.maclink.android.ui.theme.maclinkSwitchColors(),
                            modifier = Modifier.semantics { contentDescription = runInBackgroundTitle },
                        )
                    }
                    SettingRowDivider()
                    BackgroundBatteryAccess(state.backgroundUnrestricted)
                    SettingRowDivider()
                    CompanionWakeAccess(
                        associated = state.companionAssociated,
                        devices = state.devices,
                        onAccessChanged = onAccessChanged,
                    )
                }
            }

            item(key = "calls_contacts", contentType = "section") {
                Section(
                    title = stringResource(R.string.settings_calls_and_contacts),
                    highlighted = pulsingSectionKey == "calls_contacts",
                ) {
                    val callsContext = LocalContext.current
                    val telephonySettings = remember { TelephonySettings.get(callsContext) }
                    var allowCallControl by remember { mutableStateOf(telephonySettings.allowCallControl) }
                    var shareCallHistory by remember { mutableStateOf(telephonySettings.shareCallHistory) }

                    RuntimePermissionAccess(
                        title = stringResource(R.string.calls_title),
                        textOn = stringResource(R.string.calls_on),
                        textOff = stringResource(R.string.calls_off),
                        granted = state.callAccess,
                        permissions = PhoneCalls.permissions,
                        onAccessChanged = onAccessChanged,
                    )
                    SettingRowDivider()
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    ) {
                        Column(Modifier.weight(1f).padding(end = 12.dp)) {
                            Text(
                                stringResource(R.string.calls_share_history_title),
                                style = MaterialTheme.typography.titleSmall,
                            )
                            Text(
                                stringResource(R.string.calls_share_history_desc),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = shareCallHistory,
                            onCheckedChange = { checked ->
                                shareCallHistory = checked
                                telephonySettings.shareCallHistory = checked
                                onAccessChanged()
                            },
                            colors = app.maclink.android.ui.theme.maclinkSwitchColors(),
                        )
                    }
                    SettingRowDivider()
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                    ) {
                        Column(Modifier.weight(1f).padding(end = 12.dp)) {
                            Text(
                                stringResource(R.string.calls_control_title),
                                style = MaterialTheme.typography.titleSmall,
                            )
                            Text(
                                stringResource(R.string.calls_control_desc),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = allowCallControl,
                            onCheckedChange = { checked ->
                                allowCallControl = checked
                                telephonySettings.allowCallControl = checked
                                onAccessChanged()
                            },
                            colors = app.maclink.android.ui.theme.maclinkSwitchColors(),
                        )
                    }
                    SettingRowDivider()
                    RuntimePermissionAccess(
                        title = stringResource(R.string.contacts_title),
                        textOn = stringResource(R.string.contacts_on),
                        textOff = stringResource(R.string.contacts_off),
                        granted = state.contactsAccess,
                        permissions = PhoneContacts.permissions,
                        onAccessChanged = onAccessChanged,
                    )
                    SettingRowDivider()
                    RuntimePermissionAccess(
                        title = stringResource(R.string.sms_title),
                        textOn = stringResource(R.string.sms_on),
                        textOff = stringResource(R.string.sms_off),
                        granted = state.smsAccess,
                        permissions = PhoneSms.permissions,
                        onAccessChanged = onAccessChanged,
                    )
                }
            }

            item(key = "photos", contentType = "section") {
                Section(
                    title = stringResource(R.string.settings_photos),
                    highlighted = pulsingSectionKey == "photos",
                ) {
                    PhotosAccess(
                        granted = state.photoAccess,
                        partial = state.photoPartialAccess,
                        onAccessChanged = onAccessChanged,
                    )
                    SettingRowDivider()
                    StorageAccess(
                        allFiles = state.storageAllFilesAccess,
                        safFolders = state.storageSafFolders,
                        onAddSafFolder = onAddSafFolder,
                        onRemoveSafFolder = onRemoveSafFolder,
                    )
                }
            }
        }

        if (showFeatures) {
            item(key = "clipboard", contentType = "section") {
                Section(
                    title = stringResource(R.string.settings_clipboard_title),
                    highlighted = pulsingSectionKey == "clipboard",
                ) {
                    val context = LocalContext.current
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.weight(1f).padding(end = 12.dp)) {
                            Text(stringResource(R.string.settings_background_clipboard_title), style = MaterialTheme.typography.titleSmall)
                            Text(
                                if (state.elevated) {
                                    stringResource(R.string.settings_wireless_debugging_active)
                                } else {
                                    stringResource(R.string.settings_wireless_debugging_hint)
                                },
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        if (state.elevated) {
                            OutlinedButton(onClick = { openDeveloperOptionsSettings(context) }) {
                                Text(stringResource(R.string.action_manage))
                            }
                        } else {
                            Button(onClick = {
                                PairingNotification.show(context)
                                openDeveloperOptionsSettings(context)
                            }) {
                                Text(stringResource(R.string.action_allow))
                            }
                        }
                    }
                    SettingRowDivider()
                    val suggestionsTitle = stringResource(R.string.settings_clipboard_suggestions)
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.weight(1f).padding(end = 12.dp)) {
                            Text(suggestionsTitle, style = MaterialTheme.typography.titleSmall)
                            Text(
                                stringResource(R.string.settings_clipboard_suggestions_hint),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = suggestClipboardActions,
                            onCheckedChange = onSetSuggestClipboardActions,
                            colors = app.maclink.android.ui.theme.maclinkSwitchColors(),
                            modifier = Modifier.semantics { contentDescription = suggestionsTitle },
                        )
                    }
                }
            }

            item(key = "remote", contentType = "section") {
                Section(stringResource(R.string.settings_remote)) {
                    val sensitivityTitle = stringResource(R.string.settings_touchpad_sensitivity)
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                        Text(
                            sensitivityTitle,
                            style = MaterialTheme.typography.titleSmall,
                            modifier = Modifier.weight(1f),
                        )
                        Text(
                            stringResource(R.string.settings_touchpad_sensitivity_value, touchpadSensitivity),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Slider(
                        value = touchpadSensitivity,
                        onValueChange = onTouchpadSensitivity,
                        valueRange = 0.5f..2.5f,
                        modifier = Modifier.semantics { contentDescription = sensitivityTitle },
                    )
                }
            }

            item(key = "localsend", contentType = "section") {
                Section(
                    title = stringResource(R.string.settings_localsend_title),
                    highlighted = pulsingSectionKey == "localsend",
                ) {
                    val localsendTitle = stringResource(R.string.settings_localsend_title)
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.weight(1f).padding(end = 12.dp)) {
                            Text(localsendTitle, style = MaterialTheme.typography.titleSmall)
                            Text(
                                stringResource(R.string.settings_localsend_subtitle),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = state.localsendEnabled,
                            onCheckedChange = onToggleLocalSend,
                            colors = app.maclink.android.ui.theme.maclinkSwitchColors(),
                            modifier = Modifier.semantics { contentDescription = localsendTitle },
                        )
                    }
                }
            }

            item(key = "data_storage", contentType = "section") {
                Section(
                    title = stringResource(R.string.settings_data_storage_title),
                    highlighted = pulsingSectionKey == "data_storage",
                ) {
                    // 1. Notification history
                    Column(Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.data_notifications_title), style = MaterialTheme.typography.titleSmall)
                        Text(
                            stringResource(R.string.data_notifications_subtitle),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    SettingRowDivider()

                    // 2. Clipboard history
                    val clipboardHistoryTitle = stringResource(R.string.data_clipboard_title)
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.weight(1f).padding(end = 12.dp)) {
                            Text(clipboardHistoryTitle, style = MaterialTheme.typography.titleSmall)
                            Text(
                                stringResource(R.string.data_clipboard_subtitle),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            if (state.clipboardHistory.isNotEmpty()) {
                                Text(
                                    pluralStringResource(
                                        R.plurals.data_clipboard_count,
                                        state.clipboardHistory.size,
                                        state.clipboardHistory.size,
                                    ),
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.padding(top = 2.dp),
                                )
                            }
                        }
                        Switch(
                            checked = state.clipboardHistoryEnabled,
                            onCheckedChange = onSetClipboardHistoryEnabled,
                            colors = app.maclink.android.ui.theme.maclinkSwitchColors(),
                            modifier = Modifier.semantics { contentDescription = clipboardHistoryTitle },
                        )
                    }
                    if (state.clipboardHistory.isNotEmpty()) {
                        OutlinedButton(onClick = onClearClipboardHistory) {
                            Text(stringResource(R.string.data_action_clear))
                        }
                    }
                    SettingRowDivider()

                    // 3. Timeline
                    Text(stringResource(R.string.data_timeline_title), style = MaterialTheme.typography.titleSmall)
                    Text(
                        stringResource(R.string.data_timeline_subtitle),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Choice(
                        listOf(
                            "30" to stringResource(R.string.timeline_retention_30d),
                            "90" to stringResource(R.string.timeline_retention_90d),
                            "365" to stringResource(R.string.timeline_retention_1y),
                            "0" to stringResource(R.string.timeline_retention_all),
                        ),
                        state.timelineRetentionDays.toString(),
                    ) { value -> value.toUIntOrNull()?.let(onSetTimelineRetentionDays) }
                    if (state.timeline.isNotEmpty() || state.timelineTotal > 0u) {
                        OutlinedButton(onClick = onClearTimeline) {
                            Text(stringResource(R.string.data_action_clear))
                        }
                    }
                    SettingRowDivider()

                    // 4. Message cache
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.weight(1f).padding(end = 12.dp)) {
                            Text(stringResource(R.string.data_messages_title), style = MaterialTheme.typography.titleSmall)
                            Text(
                                stringResource(R.string.data_messages_subtitle),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        if (state.cachedMmsFiles > 0) {
                            OutlinedButton(onClick = onClearMessageCache) {
                                Text(stringResource(R.string.data_action_clear))
                            }
                        }
                    }
                    SettingRowDivider()

                    // 5. Photo thumbnails & camera cache
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.weight(1f).padding(end = 12.dp)) {
                            Text(stringResource(R.string.data_photos_title), style = MaterialTheme.typography.titleSmall)
                            Text(
                                stringResource(R.string.data_photos_subtitle),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        if (state.cachedPhotoFiles > 0) {
                            OutlinedButton(onClick = onClearPhotoCache) {
                                Text(stringResource(R.string.data_action_clear))
                            }
                        }
                    }
                    SettingRowDivider()

                    // 6. Received-file history
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.weight(1f).padding(end = 12.dp)) {
                            Text(stringResource(R.string.data_received_files_title), style = MaterialTheme.typography.titleSmall)
                            Text(
                                stringResource(R.string.data_received_files_subtitle),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        if (state.receivedFileRecords > 0 || state.transfers.isNotEmpty()) {
                            OutlinedButton(onClick = onClearReceivedFileHistory) {
                                Text(stringResource(R.string.data_action_clear))
                            }
                        }
                    }
                    SettingRowDivider()

                    // FTP File Server (MinimalFTP)
                    val ftpContext = LocalContext.current
                    val ftpManager = remember { app.maclink.android.storage.ftp.FtpServerManager.getInstance(ftpContext) }
                    val ftpState by ftpManager.state.collectAsState()
                    val ftpTitle = stringResource(R.string.data_ftp_server_title)
                    val clipboard = androidx.compose.ui.platform.LocalClipboardManager.current
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.weight(1f).padding(end = 12.dp)) {
                            Text(ftpTitle, style = MaterialTheme.typography.titleSmall)
                            Text(
                                stringResource(R.string.data_ftp_server_subtitle),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            if (ftpState.isRunning) {
                                Text(
                                    ftpState.url,
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.padding(top = 4.dp),
                                )
                            }
                        }
                        Switch(
                            checked = ftpState.isRunning,
                            onCheckedChange = { enable ->
                                if (enable) {
                                    ftpManager.start()
                                } else {
                                    ftpManager.stop()
                                }
                            },
                            colors = app.maclink.android.ui.theme.maclinkSwitchColors(),
                            modifier = Modifier.semantics { contentDescription = ftpTitle },
                        )
                    }
                    if (ftpState.isRunning) {
                        OutlinedButton(
                            onClick = {
                                clipboard.setText(androidx.compose.ui.text.AnnotatedString(ftpState.url))
                                android.widget.Toast.makeText(ftpContext, ftpContext.getString(R.string.data_ftp_server_copied), android.widget.Toast.LENGTH_SHORT).show()
                            }
                        ) {
                            Text(stringResource(R.string.data_ftp_server_copy))
                        }
                    }
                    SettingRowDivider()

                    // 7. Clear everything
                    Text(
                        stringResource(R.string.data_clear_everything_hint),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    OutlinedButton(onClick = { confirmClearEverything = true }) {
                        Text(stringResource(R.string.data_clear_everything_button))
                    }
                }
            }
        }

        if (showFeatures) {
            item(key = "about", contentType = "section") {
                Section(stringResource(R.string.settings_about)) {
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.weight(1f).padding(end = 12.dp)) {
                            Text(stringResource(R.string.guide_open_walkthrough), style = MaterialTheme.typography.titleSmall)
                            Text(
                                stringResource(R.string.settings_walkthrough_body),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        OutlinedButton(onClick = onOpenWalkthrough) {
                            Text(stringResource(R.string.clip_action_open))
                        }
                    }
                    SettingRowDivider()
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(vertical = 4.dp)) {
                        Image(
                            painter = painterResource(R.drawable.maclink_logo),
                            contentDescription = "MacLink Logo",
                            modifier = Modifier
                                .size(48.dp)
                                .clip(RoundedCornerShape(12.dp)),
                        )
                        Spacer(Modifier.width(12.dp))
                        Column {
                            Text("MacLink", style = MaterialTheme.typography.titleMedium)
                            Text(stringResource(R.string.about_version, BuildConfig.VERSION_NAME), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    CheckForUpdates(updater)
                }
            }
        }
    }

    confirmUnpair?.let { device ->
        AlertDialog(
            onDismissRequest = { confirmUnpair = null },
            containerColor = glassModalContainerColor(),
            title = { Text(stringResource(R.string.unpair_title, device.name)) },
            text = { Text(stringResource(R.string.unpair_text)) },
            confirmButton = {
                TextButton(onClick = { onUnpair(device.id); confirmUnpair = null }) {
                    Text(stringResource(R.string.action_unpair))
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmUnpair = null }) { Text(stringResource(R.string.action_cancel)) }
            },
        )
    }

    if (pickLanguage && AppLanguage.supported) {
        val context = LocalContext.current
        val language = remember { AppLanguage.current(context) }
        AlertDialog(
            onDismissRequest = { pickLanguage = false },
            containerColor = glassModalContainerColor(),
            title = { Text(stringResource(R.string.settings_language)) },
            text = {
                Column {
                    AppLanguage.languages.forEach { (tag, name) ->
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .selectable(selected = tag == language, role = Role.RadioButton) {
                                    pickLanguage = false
                                    AppLanguage.set(context, tag)
                                }
                                .padding(vertical = 12.dp),
                        ) {
                            RadioButton(selected = tag == language, onClick = null)
                            Spacer(Modifier.width(12.dp))
                            Text(name, style = MaterialTheme.typography.bodyLarge)
                        }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { pickLanguage = false }) { Text(stringResource(R.string.action_cancel)) }
            },
        )
    }

    if (confirmClearEverything) {
        AlertDialog(
            onDismissRequest = { confirmClearEverything = false },
            containerColor = glassModalContainerColor(),
            title = { Text(stringResource(R.string.data_clear_everything_dialog_title)) },
            text = { Text(stringResource(R.string.data_clear_everything_dialog_body)) },
            confirmButton = {
                TextButton(onClick = {
                    onClearEverything()
                    confirmClearEverything = false
                }) {
                    Text(stringResource(R.string.data_clear_everything_confirm))
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmClearEverything = false }) {
                    Text(stringResource(R.string.action_cancel))
                }
            },
        )
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is android.content.ContextWrapper -> baseContext.findActivity()
    else -> null
}

private fun openAppInfoSettings(context: Context) {
    runCatching {
        context.startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }
}

private fun openDeveloperOptionsSettings(context: Context) {
    val devIntent = Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    if (runCatching { context.startActivity(devIntent) }.isFailure) {
        runCatching {
            context.startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}

/**
 * Notification access, which mirroring needs. Android shows the switch in
 * its own settings; sideloaded apps on Android 13+ must first be allowed
 * "restricted settings" there.
 */
@Composable
private fun NotificationAccess(granted: Boolean) {
    val context = LocalContext.current
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            Text(stringResource(R.string.notifications_title), style = MaterialTheme.typography.titleSmall)
            Text(
                stringResource(if (granted) R.string.notifications_on else R.string.notifications_off),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        val open = { runCatching { context.startActivity(NotificationListener.settingsIntent(context)) }.let {} }
        if (granted) {
            OutlinedButton(onClick = open) { Text(stringResource(R.string.action_manage)) }
        } else {
            Button(onClick = open) { Text(stringResource(R.string.action_allow)) }
        }
    }
    if (!granted && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text(
                stringResource(R.string.notifications_restricted),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = { openAppInfoSettings(context) }) { Text(stringResource(R.string.action_app_info)) }
        }
    }
}

/** Unrestricted background execution and OEM-specific battery settings. */
@Composable
private fun BackgroundBatteryAccess(unrestricted: Boolean) {
    val context = LocalContext.current
    val oemGuide = BackgroundAccess.oemGuideResId()?.let { stringResource(it) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.weight(1f).padding(end = 12.dp)) {
                Text(stringResource(R.string.background_title), style = MaterialTheme.typography.titleSmall)
                Text(
                    stringResource(if (unrestricted) R.string.background_on else R.string.background_text),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (!unrestricted) {
                Button(onClick = {
                    runCatching { context.startActivity(BackgroundAccess.requestIntent(context)) }
                }) {
                    Text(stringResource(R.string.action_allow))
                }
            } else {
                OutlinedButton(onClick = {
                    runCatching { context.startActivity(BackgroundAccess.oemSettingsIntent(context)) }
                }) {
                    Text(stringResource(R.string.battery_open_oem_settings))
                }
            }
        }
        if (oemGuide != null) {
            Text(
                oemGuide,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (!unrestricted) {
            OutlinedButton(onClick = {
                runCatching { context.startActivity(BackgroundAccess.oemSettingsIntent(context)) }
            }) {
                Text(stringResource(R.string.battery_open_oem_settings))
            }
        }
    }
}

/** Companion Device Manager association for waking when a PC BLE beacon is nearby. */
@Composable
private fun CompanionWakeAccess(
    associated: Boolean,
    devices: List<Device>,
    onAccessChanged: () -> Unit,
) {
    val context = LocalContext.current
    val chooserLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartIntentSenderForResult(),
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            PcCompanion.startObservingPresence(context)
        }
        onAccessChanged()
    }
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            Text(stringResource(R.string.companion_wake_title), style = MaterialTheme.typography.titleSmall)
            Text(
                stringResource(if (associated) R.string.companion_wake_on else R.string.companion_wake_off),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        val primaryPc = devices.firstOrNull { it.online } ?: devices.firstOrNull()
        val triggerAssociate = {
            val activity = context.findActivity()
            if (activity != null) {
                PcCompanion.requestAssociation(
                    activity = activity,
                    pcName = primaryPc?.name ?: "PC",
                    pcDeviceIdHex = primaryPc?.id,
                    onResult = { onAccessChanged() },
                    onLauncherFallback = { sender ->
                        runCatching {
                            chooserLauncher.launch(IntentSenderRequest.Builder(sender).build())
                        }
                    },
                )
            }
        }
        if (associated) {
            OutlinedButton(onClick = triggerAssociate) {
                Text(stringResource(R.string.action_manage))
            }
        } else {
            Button(onClick = triggerAssociate) {
                Text(stringResource(R.string.companion_wake_associate))
            }
        }
    }
}

/** Do Not Disturb and silent ringer control from a PC. */
@Composable
private fun DndAccess(granted: Boolean) {
    val context = LocalContext.current
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            Text(stringResource(R.string.dnd_access_title), style = MaterialTheme.typography.titleSmall)
            Text(
                stringResource(if (granted) R.string.dnd_access_on else R.string.dnd_access_off),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        val open = { runCatching { context.startActivity(PhoneToggles.dndSettingsIntent()) }.let {} }
        if (granted) {
            OutlinedButton(onClick = open) { Text(stringResource(R.string.action_manage)) }
        } else {
            Button(onClick = open) { Text(stringResource(R.string.action_allow)) }
        }
    }
}

/** Screen brightness control from a PC (Modify system settings, or Elevated). */
@Composable
private fun WriteSettingsAccess(granted: Boolean) {
    val context = LocalContext.current
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            Text(stringResource(R.string.write_settings_title), style = MaterialTheme.typography.titleSmall)
            Text(
                stringResource(if (granted) R.string.write_settings_on else R.string.write_settings_off),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        val open = { runCatching { context.startActivity(PhoneToggles.writeSettingsIntent(context)) }.let {} }
        if (granted) {
            OutlinedButton(onClick = open) { Text(stringResource(R.string.action_manage)) }
        } else {
            Button(onClick = open) { Text(stringResource(R.string.action_allow)) }
        }
    }
}

/** Control from the PC: MacLink's accessibility service, turned on in Android's settings. */
@Composable
private fun ControlAccess(on: Boolean) {
    val context = LocalContext.current
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            Text(stringResource(R.string.control_title), style = MaterialTheme.typography.titleSmall)
            Text(
                stringResource(if (on) R.string.control_on else R.string.control_off),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        val open = { runCatching { context.startActivity(InputService.settingsIntent()) }.let {} }
        if (on) {
            OutlinedButton(onClick = open) { Text(stringResource(R.string.action_manage)) }
        } else {
            Button(onClick = open) { Text(stringResource(R.string.action_allow)) }
        }
    }
    if (!on && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text(
                stringResource(R.string.notifications_restricted),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.weight(1f).padding(end = 12.dp),
            )
            OutlinedButton(onClick = { openAppInfoSettings(context) }) { Text(stringResource(R.string.action_app_info)) }
        }
    }
}

/** Elevated through the phone's own wireless debugging: real touch and keys. */
@Composable
private fun ElevatedAccess() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val state by Elevated.state.collectAsStateWithLifecycle()
    var steps by remember { mutableStateOf(false) }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.weight(1f).padding(end = 12.dp)) {
                Text(stringResource(R.string.elevated_title), style = MaterialTheme.typography.titleSmall)
                Text(
                    stringResource(
                        when (state) {
                            Elevated.State.NotSetUp -> R.string.elevated_not_set_up
                            Elevated.State.Waiting -> R.string.elevated_waiting
                            Elevated.State.Starting -> R.string.elevated_starting
                            Elevated.State.Running ->
                                if (Elevated.rootActive) R.string.elevated_running_root else R.string.elevated_running
                            is Elevated.State.Failed -> when ((state as Elevated.State.Failed).reason) {
                                Elevated.Reason.NotPaired -> R.string.elevated_not_paired
                                Elevated.Reason.RootDenied -> R.string.elevated_root_failed
                                else -> R.string.elevated_failed
                            }
                        },
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            when (state) {
                Elevated.State.NotSetUp, is Elevated.State.Failed -> Button(onClick = { steps = true }) {
                    Text(stringResource(R.string.elevated_set_up))
                }
                Elevated.State.Waiting -> Button(onClick = {
                    scope.launch {
                        PairingNotification.show(context)
                        if (!Elevated.start()) {
                            openDeveloperOptionsSettings(context)
                        }
                    }
                }) {
                    Text(stringResource(R.string.elevated_try_again))
                }
                Elevated.State.Running -> OutlinedButton(onClick = { scope.launch { Elevated.forget() } }) {
                    Text(stringResource(R.string.elevated_turn_off))
                }
                Elevated.State.Starting -> {}
            }
        }
        if (state == Elevated.State.Waiting || state is Elevated.State.Failed) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = {
                    PairingNotification.show(context)
                    openDeveloperOptionsSettings(context)
                }) {
                    Text(stringResource(R.string.elevated_open_developer))
                }
            }
        }
        // Root only when the user picks it, and only on a rooted phone.
        val rootOffered = Elevated.isRootAvailable() &&
            (state == Elevated.State.NotSetUp || state is Elevated.State.Failed)
        if (rootOffered) {
            Text(
                stringResource(R.string.elevated_root_hint),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            OutlinedButton(onClick = { scope.launch { Elevated.setUpWithRoot() } }) {
                Text(stringResource(R.string.elevated_use_root))
            }
        }
    }
    if (steps) {
        AlertDialog(
            onDismissRequest = { steps = false },
            title = { Text(stringResource(R.string.elevated_steps_title)) },
            text = { Text(stringResource(R.string.elevated_steps)) },
            confirmButton = {
                TextButton(onClick = {
                    steps = false
                    PairingNotification.show(context)
                    openDeveloperOptionsSettings(context)
                }) { Text(stringResource(R.string.elevated_open_developer)) }
            },
            dismissButton = {
                TextButton(onClick = { steps = false }) { Text(stringResource(R.string.action_cancel)) }
            },
        )
    }
}

@Composable
private fun RuntimePermissionAccess(
    title: String,
    textOn: String,
    textOff: String,
    granted: Boolean,
    permissions: Array<String>,
    onAccessChanged: () -> Unit,
) {
    val context = LocalContext.current
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { grants ->
        onAccessChanged()
        if (grants.values.none { it }) {
            openAppInfoSettings(context)
        }
    }
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Text(
                if (granted) textOn else textOff,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (granted) {
            OutlinedButton(onClick = { openAppInfoSettings(context) }) {
                Text(stringResource(R.string.action_manage))
            }
        } else {
            Button(onClick = { ask.launch(permissions) }) { Text(stringResource(R.string.action_allow)) }
        }
    }
}

@Composable
private fun PhotosAccess(
    granted: Boolean,
    partial: Boolean,
    onAccessChanged: () -> Unit,
) {
    val context = LocalContext.current
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { grants ->
        onAccessChanged()
        if (grants.values.none { it }) {
            openAppInfoSettings(context)
        }
    }
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            Text(stringResource(R.string.photos_title), style = MaterialTheme.typography.titleSmall)
            Text(
                stringResource(
                    when {
                        partial -> R.string.photos_partial
                        granted -> R.string.photos_on
                        else -> R.string.photos_off
                    },
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        when {
            partial -> OutlinedButton(onClick = { ask.launch(RecentPhotos.permissions) }) {
                Text(stringResource(R.string.action_select_photos))
            }
            granted -> OutlinedButton(onClick = { openAppInfoSettings(context) }) {
                Text(stringResource(R.string.action_manage))
            }
            else -> Button(onClick = { ask.launch(RecentPhotos.permissions) }) {
                Text(stringResource(R.string.action_allow))
            }
        }
    }
}

@Composable
private fun StorageAccess(
    allFiles: Boolean,
    safFolders: List<String>,
    onAddSafFolder: (Uri) -> Unit,
    onRemoveSafFolder: (String) -> Unit,
) {
    val context = LocalContext.current
    val pickFolder = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) onAddSafFolder(uri)
    }
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            Text(stringResource(R.string.storage_all_files_title), style = MaterialTheme.typography.titleSmall)
            Text(
                stringResource(if (allFiles) R.string.storage_all_files_on else R.string.storage_all_files_off),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        val open = { runCatching { context.startActivity(PhoneStorage.allFilesAccessIntent(context)) }.let {} }
        if (allFiles) {
            OutlinedButton(onClick = open) { Text(stringResource(R.string.action_manage)) }
        } else {
            Button(onClick = open) { Text(stringResource(R.string.action_allow)) }
        }
    }
    if (!allFiles) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Column(Modifier.weight(1f).padding(end = 12.dp)) {
                Text(stringResource(R.string.storage_saf_title), style = MaterialTheme.typography.titleSmall)
                Text(
                    stringResource(R.string.storage_saf_hint),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            OutlinedButton(onClick = { pickFolder.launch(null) }) {
                Text(stringResource(R.string.storage_add_folder))
            }
        }
        safFolders.forEach { name ->
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Text(name, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                TextButton(onClick = { onRemoveSafFolder(name) }) {
                    Text(stringResource(R.string.storage_remove_folder))
                }
            }
        }
    }
}

@Composable
private fun SettingRowDivider() {
    HorizontalDivider(
        color = AmberTokens.GlassBorderSubtle,
        modifier = Modifier.padding(vertical = 4.dp),
    )
}

@Composable
private fun Section(
    title: String,
    highlighted: Boolean = false,
    content: @Composable () -> Unit,
) {
    Column(
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            title,
            style = MaterialTheme.typography.labelLarge,
            color = if (highlighted) AmberTokens.PrimaryAccent else AmberTokens.SecondaryText,
            modifier = Modifier.padding(start = 4.dp),
        )
        LiquidGlassCard(
            cornerRadius = 20.dp,
            modifier = Modifier.fillMaxWidth(),
            borderColor = if (highlighted) AmberTokens.Highlight else AmberTokens.GlassBorder,
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                content()
            }
        }
    }
}

@Composable
private fun Label(text: String) {
    Text(
        text = text,
        color = AmberTokens.PrimaryText,
        fontSize = 14.sp,
        fontWeight = FontWeight.SemiBold,
    )
}

/** The third language choice when it isn't a picked language: opens the list. */
private const val MORE_LANGUAGES = "more"

@Composable
private fun Choice(options: List<Pair<String, String>>, selected: String, onSelect: (String) -> Unit) {
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        options.forEachIndexed { index, (value, label) ->
            SegmentedButton(
                selected = value == selected,
                onClick = { onSelect(value) },
                shape = SegmentedButtonDefaults.itemShape(index, options.size),
            ) { Text(label) }
        }
    }
}

