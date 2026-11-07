// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.core

import java.util.concurrent.atomic.AtomicInteger

/**
 * Tracks stops so that in-flight starts can detect if a stop occurred
 * after they began. Multiple start calls do not cancel each other.
 */
internal class StartGuard {
    private val stopCount = AtomicInteger(0)

    class Token internal constructor(internal val stopAtStart: Int)

    fun beginStart(): Token = Token(stopCount.get())

    fun stop() {
        stopCount.incrementAndGet()
    }

    fun isCancelled(token: Token): Boolean = stopCount.get() != token.stopAtStart
}
