// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.media

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import app.maclink.android.R
import app.maclink.android.links.LinkNotifications
import app.maclink.android.ui.watch.WatchActivity
import app.maclink.core.WatchFileOffer

/**
 * Play on phone: a PC offers to stream what one of its players plays, or a video file for the
 * phone to play itself. Android doesn't let an
 * app in the background open a screen, so the offer waits in a notification (on the links
 * channel, as links from the PC do); with MacLink in front, the Watch screen opens at once.
 */
object WatchOffers {
    private const val TAG = "watch"

    /** Shows the offer; false if notifications are off and it couldn't open either. */
    fun show(
        context: Context,
        pcId: String,
        pcName: String,
        player: String,
        title: String?,
        file: WatchFileOffer? = null,
    ): Boolean {
        val from = pcName.ifEmpty { context.getString(R.string.your_pc) }
        val watch = WatchActivity.intent(context, pcId, from, player, title, file)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        // Allowed only while MacLink is in front; otherwise Android ignores it.
        val opened = runCatching { context.startActivity(watch) }.isSuccess
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return opened
        }
        val open = PendingIntent.getActivity(
            context,
            "$pcId/$player".hashCode(),
            watch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val text = title?.takeIf { it.isNotBlank() } ?: file?.name ?: context.getString(R.string.watch_offer_untitled)
        val notification = NotificationCompat.Builder(context, LinkNotifications.CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.watch_offer_title, from))
            .setContentText(text)
            .setContentIntent(open)
            .addAction(0, context.getString(R.string.watch_offer_action), open)
            .setAutoCancel(true)
            .setTimeoutAfter(OFFER_MS)
            .setCategory(NotificationCompat.CATEGORY_RECOMMENDATION)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        val shown = runCatching {
            NotificationManagerCompat.from(context).notify(TAG, pcId.hashCode(), notification)
        }.isSuccess
        return shown || opened
    }

    /** Takes the offer's notification away (the Watch screen opened). */
    fun dismiss(context: Context, pcId: String) {
        runCatching { NotificationManagerCompat.from(context).cancel(TAG, pcId.hashCode()) }
    }

    /** As long as the PC keeps an offer open (docs/protocol/media.md §4). */
    private const val OFFER_MS = 10 * 60 * 1000L
}
