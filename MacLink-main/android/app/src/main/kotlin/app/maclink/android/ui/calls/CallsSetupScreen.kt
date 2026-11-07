// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.ui.calls

import android.Manifest
import android.content.Context
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import app.maclink.android.telephony.TelephonyPermissions
import app.maclink.android.telephony.TelephonySettings

/**
 * Setup and permission controls for MacLink Phone Calls feature.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CallsSetupScreen(
    onNavigateBack: () -> Unit = {},
) {
    val context = LocalContext.current
    val settings = remember { TelephonySettings.get(context) }

    var allowControl by remember { mutableStateOf(settings.allowCallControl) }
    var shareHistory by remember { mutableStateOf(settings.shareCallHistory) }

    var hasPhoneState by remember { mutableStateOf(TelephonyPermissions.hasReadPhoneState(context)) }
    var hasAnswerCalls by remember { mutableStateOf(TelephonyPermissions.hasAnswerCalls(context)) }
    var hasCallPhone by remember { mutableStateOf(TelephonyPermissions.hasCallPhone(context)) }
    var hasCallLog by remember { mutableStateOf(TelephonyPermissions.hasReadCallLog(context)) }
    var hasContacts by remember { mutableStateOf(TelephonyPermissions.hasReadContacts(context)) }

    fun refreshPermissions() {
        hasPhoneState = TelephonyPermissions.hasReadPhoneState(context)
        hasAnswerCalls = TelephonyPermissions.hasAnswerCalls(context)
        hasCallPhone = TelephonyPermissions.hasCallPhone(context)
        hasCallLog = TelephonyPermissions.hasReadCallLog(context)
        hasContacts = TelephonyPermissions.hasReadContacts(context)
    }

    val requestPermissionsLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) {
        refreshPermissions()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Calls on Mac", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Text("←", style = MaterialTheme.typography.titleLarge)
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
                ),
            )
        }
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Control and view incoming phone calls from your Mac over local Wi-Fi.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // User Switches
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f)
                    ),
                    shape = RoundedCornerShape(16.dp),
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = "Let my paired Mac answer and place calls",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Medium,
                                )
                                Text(
                                    text = "Allow answering incoming calls, ending calls, and dialing from your Mac.",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            Spacer(modifier = Modifier.width(12.dp))
                            Switch(
                                checked = allowControl,
                                onCheckedChange = { checked ->
                                    allowControl = checked
                                    settings.allowCallControl = checked
                                }
                            )
                        }

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = "Share call history with Mac",
                                    style = MaterialTheme.typography.titleMedium,
                                    fontWeight = FontWeight.Medium,
                                )
                                Text(
                                    text = "Allows your Mac to browse recent incoming and outgoing calls in memory.",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            Spacer(modifier = Modifier.width(12.dp))
                            Switch(
                                checked = shareHistory,
                                onCheckedChange = { checked ->
                                    shareHistory = checked
                                    settings.shareCallHistory = checked
                                }
                            )
                        }
                    }
                }
            }

            // Permissions Status Card
            item {
                Text(
                    text = "System Permissions",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Bold,
                )
            }

            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(16.dp),
                ) {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        PermissionRow("Call Notifications (Phone State)", hasPhoneState)
                        PermissionRow("Answer & Hang Up Calls", hasAnswerCalls)
                        PermissionRow("Dial Calls from Keypad", hasCallPhone)
                        PermissionRow("Call Log (History)", hasCallLog)
                        PermissionRow("Contacts Search", hasContacts)

                        val allGranted = hasPhoneState && hasAnswerCalls && hasCallPhone && hasCallLog && hasContacts
                        if (!allGranted) {
                            Spacer(modifier = Modifier.height(8.dp))
                            Button(
                                onClick = {
                                    requestPermissionsLauncher.launch(
                                        arrayOf(
                                            Manifest.permission.READ_PHONE_STATE,
                                            Manifest.permission.ANSWER_PHONE_CALLS,
                                            Manifest.permission.CALL_PHONE,
                                            Manifest.permission.READ_CALL_LOG,
                                            Manifest.permission.READ_CONTACTS,
                                        )
                                    )
                                },
                                modifier = Modifier.fillMaxWidth(),
                            ) {
                                Text("Grant Telephony Permissions")
                            }
                        }
                    }
                }
            }

            // Architecture Transparency Card
            item {
                Text(
                    text = "How Calls Work on MacLink",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.primary,
                    fontWeight = FontWeight.Bold,
                )
            }

            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    shape = RoundedCornerShape(16.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)
                    ),
                ) {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(
                            text = "Control is Instant via Local Wi-Fi",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            text = "Call notifications, answer/hangup actions, and dialing use MacLink's encrypted QUIC connection (sub-10ms response time).",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(modifier = Modifier.height(4.dp))
                        Text(
                            text = "Audio Routing Note",
                            style = MaterialTheme.typography.titleSmall,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Text(
                            text = "macOS does not permit standard Bluetooth Hands-Free call audio routing to system speakers without private Continuity drivers. Call audio therefore remains on your phone, speakerphone, or your phone's paired Bluetooth headset.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                Spacer(modifier = Modifier.height(24.dp))
            }
        }
    }
}

@Composable
private fun PermissionRow(title: String, granted: Boolean) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.bodyMedium,
        )
        Text(
            text = if (granted) "✓ Granted" else "Missing",
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = if (granted) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
        )
    }
}

