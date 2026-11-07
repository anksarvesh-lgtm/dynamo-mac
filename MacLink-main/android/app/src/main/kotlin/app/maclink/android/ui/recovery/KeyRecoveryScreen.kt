// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.ui.recovery

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.maclink.android.BuildConfig
import app.maclink.android.R

/**
 * Screen presented when Android Keystore fails to unlock the saved identity key
 * (e.g. AEADBadTagException after unmigrated alias or corrupted key file).
 *
 * CRITICAL LIFECYCLE & SECURITY NOTICE:
 * Resetting and creating a new device key generates a completely NEW DEVICE IDENTITY.
 * All existing crypto sessions and pairings with macOS are invalidated.
 * The user's Mac must remove ("Forget") this phone from its device list before
 * pairing again from scratch.
 *
 * In accordance with strict recovery rules:
 * - Unreadable keys are moved to `device_key.unreadable-<timestamp>` rather than deleted.
 * - Silent/automatic resets are strictly prohibited to prevent data loss and masking bugs.
 */
@Composable
fun KeyRecoveryScreen(
    message: String,
    causeChain: String,
    onResetAndPair: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    var showConfirmDialog by remember { mutableStateOf(false) }

    Surface(
        modifier = modifier
            .fillMaxSize()
            .safeDrawingPadding(),
        color = MaterialTheme.colorScheme.background,
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp)
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            // Icon
            Box(
                modifier = Modifier
                    .size(64.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.errorContainer),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    painter = painterResource(R.drawable.ic_launcher_monochrome),
                    contentDescription = null,
                    modifier = Modifier.size(36.dp),
                    tint = MaterialTheme.colorScheme.onErrorContainer,
                )
            }

            Spacer(Modifier.height(24.dp))

            // Title
            Text(
                text = stringResource(R.string.key_recovery_title),
                style = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.Bold),
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onBackground,
            )

            Spacer(Modifier.height(12.dp))

            // Plain description
            Text(
                text = stringResource(R.string.key_recovery_description),
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp),
            )

            Spacer(Modifier.height(24.dp))

            // Error diagnostic box (safe: contains no secret key bytes or passwords)
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(12.dp),
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                ),
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        text = "Diagnostics",
                        style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = "App: v${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}) | Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
                        style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.8f),
                    )
                    Spacer(Modifier.height(6.dp))
                    Text(
                        text = causeChain.ifBlank { message },
                        style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace, fontSize = 11.sp),
                        color = MaterialTheme.colorScheme.error,
                        maxLines = 6,
                    )
                }
            }

            Spacer(Modifier.height(32.dp))

            // Primary action: Reset and pair again (prompts confirmation first)
            Button(
                onClick = { showConfirmDialog = true },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp),
                shape = RoundedCornerShape(24.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primary,
                    contentColor = MaterialTheme.colorScheme.onPrimary,
                ),
            ) {
                Icon(
                    painter = painterResource(R.drawable.ic_refresh),
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    text = stringResource(R.string.key_recovery_reset_button),
                    style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
                )
            }

            Spacer(Modifier.height(12.dp))

            // Secondary action: Copy details (for bug reports / troubleshooting)
            OutlinedButton(
                onClick = {
                    val report = buildString {
                        appendLine("MacLink Android: v${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})")
                        appendLine("Device: ${Build.MANUFACTURER} ${Build.MODEL} (Android ${Build.VERSION.RELEASE}, API ${Build.VERSION.SDK_INT})")
                        appendLine("Reason: $message")
                        appendLine("Cause Chain: $causeChain")
                    }
                    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    clipboard.setPrimaryClip(ClipData.newPlainText("MacLink Diagnostic Report", report))
                    Toast.makeText(context, context.getString(R.string.key_recovery_copied_toast), Toast.LENGTH_SHORT).show()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp),
                shape = RoundedCornerShape(24.dp),
            ) {
                Icon(
                    painter = painterResource(R.drawable.ic_clipboard),
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    text = stringResource(R.string.key_recovery_copy_button),
                    style = MaterialTheme.typography.labelLarge,
                )
            }
        }
    }

    if (showConfirmDialog) {
        AlertDialog(
            onDismissRequest = { showConfirmDialog = false },
            title = {
                Text(text = stringResource(R.string.key_recovery_confirm_title))
            },
            text = {
                Text(text = stringResource(R.string.key_recovery_confirm_message))
            },
            confirmButton = {
                Button(
                    onClick = {
                        showConfirmDialog = false
                        onResetAndPair()
                    },
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error,
                        contentColor = MaterialTheme.colorScheme.onError,
                    ),
                ) {
                    Text(text = stringResource(R.string.key_recovery_confirm_action))
                }
            },
            dismissButton = {
                TextButton(onClick = { showConfirmDialog = false }) {
                    Text(text = stringResource(R.string.action_cancel))
                }
            },
        )
    }
}

