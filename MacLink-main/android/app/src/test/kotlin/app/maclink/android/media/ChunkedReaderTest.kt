// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.media

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.IOException
import java.util.Collections

class ChunkedReaderTest {
    private val chunk = ChunkedReader.CHUNK.toInt()
    private val file = ByteArray(chunk * 5 + 1234) { (it % 251).toByte() }

    /** Reads from [file], recording each read's offset. */
    private class Pc(private val file: ByteArray) {
        val reads: MutableList<Long> = Collections.synchronizedList(mutableListOf())
        @Volatile var failing = false

        fun read(offset: Long, length: Long): ByteArray {
            reads += offset
            if (failing) throw IllegalStateException("offline")
            val from = offset.toInt().coerceAtMost(file.size)
            return file.copyOfRange(from, (from + length.toInt()).coerceAtMost(file.size))
        }
    }

    private fun readAll(reader: ChunkedReader, at: Long, size: Int): ByteArray {
        val out = ByteArray(size)
        var done = 0
        while (done < size) {
            val n = reader.readAt(at + done, out, done, size - done)
            if (n < 0) break
            done += n
        }
        return out.copyOf(done)
    }

    @Test
    fun readsComeBackAsTheFileIsAcrossPieces() {
        val pc = Pc(file)
        val reader = ChunkedReader(file.size.toLong(), pc::read)
        // Across a piece's end, and the file's.
        val at = chunk - 100L
        assertArrayEquals(file.copyOfRange(at.toInt(), at.toInt() + 300), readAll(reader, at, 300))
        val tail = file.size - 50L
        assertArrayEquals(file.copyOfRange(tail.toInt(), file.size), readAll(reader, tail, 500))
        assertEquals(-1, reader.readAt(file.size.toLong(), ByteArray(10), 0, 10))
        reader.close()
    }

    @Test
    fun piecesAheadAreReadAndAPieceIsReadOnce() {
        val pc = Pc(file)
        val reader = ChunkedReader(file.size.toLong(), pc::read)
        readAll(reader, 0, 10)
        readAll(reader, 20, 10)
        // Read ahead lands soon after.
        val deadline = System.currentTimeMillis() + 5_000
        while (pc.reads.size < 4 && System.currentTimeMillis() < deadline) Thread.sleep(10)
        assertEquals(listOf(0L, chunk.toLong(), 2L * chunk, 3L * chunk), pc.reads.sorted())
        reader.close()
    }

    @Test
    fun aFailedPieceIsReadAgainNextTime() {
        val pc = Pc(file)
        val reader = ChunkedReader(file.size.toLong(), pc::read)
        pc.failing = true
        try {
            reader.readAt(0, ByteArray(10), 0, 10)
            fail("a failed read says so")
        } catch (_: IOException) {
        }
        pc.failing = false
        assertArrayEquals(file.copyOfRange(0, 10), readAll(reader, 0, 10))
        reader.close()
    }

    @Test
    fun aClosedReaderReadsNothing() {
        val reader = ChunkedReader(file.size.toLong(), Pc(file)::read)
        reader.close()
        assertTrue(reader.readAt(0, ByteArray(10), 0, 10) < 0)
    }
}
