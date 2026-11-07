// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.media

import android.media.MediaDataSource
import java.io.IOException
import java.util.concurrent.ExecutionException
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException

/**
 * Play on phone for a video file: the file a PC offered, read from the PC as the phone's
 * player asks for it (docs/protocol/media.md §4). It reads in pieces of [ChunkedReader.CHUNK] bytes and
 * a few ahead of where the player reads, and keeps the latest of them, so playing
 * on doesn't wait on the network and seeking back is quick.
 *
 * [read] reads `length` bytes from `offset` of the file (fewer at its end); it blocks, and
 * runs on this source's own threads.
 */
class PcFileSource(fileSize: Long, read: (offset: Long, length: Long) -> ByteArray) : MediaDataSource() {
    private val reader = ChunkedReader(fileSize, read)

    override fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int =
        reader.readAt(position, buffer, offset, size)

    override fun getSize(): Long = reader.fileSize

    override fun close() = reader.close()
}

/** [PcFileSource]'s reading, apart from Android's player so it can be tested on its own. */
class ChunkedReader(
    val fileSize: Long,
    private val read: (offset: Long, length: Long) -> ByteArray,
) {
    private val pool = Executors.newFixedThreadPool(2) { Thread(it, "pc-file").apply { isDaemon = true } }

    /** Pieces read or on their way, by index; the least recently used go first. */
    private val chunks = object : LinkedHashMap<Long, Future<ByteArray>>(KEEP, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<Long, Future<ByteArray>>?): Boolean =
            size > KEEP
    }

    @Volatile private var closed = false

    private fun chunk(index: Long): Future<ByteArray> = synchronized(chunks) {
        chunks.getOrPut(index) { pool.submit<ByteArray> { read(index * CHUNK, CHUNK) } }
    }

    /** As [MediaDataSource.readAt]: how many bytes it put in [buffer], or -1 at the end. */
    fun readAt(position: Long, buffer: ByteArray, offset: Int, size: Int): Int {
        if (closed || position >= fileSize) return -1
        if (size <= 0) return 0
        val index = position / CHUNK
        val data = try {
            val wanted = chunk(index)
            for (ahead in 1..AHEAD) {
                if ((index + ahead) * CHUNK < fileSize) chunk(index + ahead)
            }
            try {
                wanted.get(READ_TIMEOUT_S, TimeUnit.SECONDS)
            } catch (e: ExecutionException) {
                // Read ahead may have failed a while ago (the link dropped): once more, now.
                forget(index)
                chunk(index).get(READ_TIMEOUT_S, TimeUnit.SECONDS)
            }
        } catch (e: RejectedExecutionException) {
            return -1
        } catch (e: ExecutionException) {
            forget(index)
            throw IOException("can't read the PC's file", e.cause)
        } catch (e: TimeoutException) {
            forget(index)
            throw IOException("the PC's file didn't come in time", e)
        } catch (e: InterruptedException) {
            Thread.currentThread().interrupt()
            throw IOException("interrupted", e)
        }
        val within = (position - index * CHUNK).toInt()
        val count = minOf(size, data.size - within)
        if (count <= 0) return -1
        System.arraycopy(data, within, buffer, offset, count)
        return count
    }

    /** A failed piece is read again next time. */
    private fun forget(index: Long) {
        synchronized(chunks) { chunks.remove(index) }
    }

    fun close() {
        closed = true
        pool.shutdownNow()
        synchronized(chunks) { chunks.clear() }
    }

    companion object {
        const val CHUNK = 1L shl 20
        private const val AHEAD = 3
        private const val KEEP = 24
        private const val READ_TIMEOUT_S = 30L
    }
}
