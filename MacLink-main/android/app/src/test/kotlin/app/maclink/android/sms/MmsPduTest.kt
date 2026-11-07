// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.sms

import app.maclink.android.notifications.NotificationReader
import app.maclink.core.NotificationChatMessage
import app.maclink.core.SmsAttachment
import java.io.ByteArrayOutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MmsPduTest {

    @Test
    fun `writeUintvar encodes single and multi-byte values per WAP-230-WSP`() {
        fun encode(v: Int): ByteArray = ByteArrayOutputStream().also {
            PhoneSms.writeUintvar(it, v)
        }.toByteArray()

        assertArrayEquals(byteArrayOf(0x00), encode(0))
        assertArrayEquals(byteArrayOf(0x02), encode(2))
        assertArrayEquals(byteArrayOf(0x7F), encode(127))
        assertArrayEquals(byteArrayOf(0x81.toByte(), 0x00), encode(128))
        assertArrayEquals(byteArrayOf(0x82.toByte(), 0x2C), encode(300))
        assertArrayEquals(byteArrayOf(0x81.toByte(), 0x80.toByte(), 0x00), encode(16384))
    }

    @Test
    fun `buildMmsSendReqPdu encodes headers, text part, and image attachment`() {
        val imageBytes = ByteArray(300) { (it and 0xFF).toByte() }
        val pdu = PhoneSms.buildMmsSendReqPdu(
            to = listOf(" +15550100 ", "user@example.com"),
            body = "Look at this!",
            attachments = listOf(SmsAttachment(mime = "image/jpeg", data = imageBytes)),
            transactionId = "nl-1700000000",
        )

        var pos = 0
        // X-Mms-Message-Type (0x8C): m-send-req (0x80)
        assertEquals(0x8C, pdu[pos++].toInt() and 0xFF)
        assertEquals(0x80, pdu[pos++].toInt() and 0xFF)

        // X-Mms-Transaction-Id (0x98): "nl-1700000000" + NUL
        assertEquals(0x98, pdu[pos++].toInt() and 0xFF)
        val txEnd = pdu.indexOf(0, pos)
        assertEquals("nl-1700000000", String(pdu, pos, txEnd - pos, Charsets.US_ASCII))
        pos = txEnd + 1

        // X-Mms-MMS-Version (0x8D): v1.2 (0x92)
        assertEquals(0x8D, pdu[pos++].toInt() and 0xFF)
        assertEquals(0x92, pdu[pos++].toInt() and 0xFF)

        // From (0x89): length 1, Insert-address-token (0x81)
        assertEquals(0x89, pdu[pos++].toInt() and 0xFF)
        assertEquals(0x01, pdu[pos++].toInt() and 0xFF)
        assertEquals(0x81, pdu[pos++].toInt() and 0xFF)

        // First To (0x97): "+15550100/TYPE=PLMN" + NUL
        assertEquals(0x97, pdu[pos++].toInt() and 0xFF)
        val to1End = pdu.indexOf(0, pos)
        assertEquals("+15550100/TYPE=PLMN", String(pdu, pos, to1End - pos, Charsets.US_ASCII))
        pos = to1End + 1

        // Second To (0x97): "user@example.com" + NUL
        assertEquals(0x97, pdu[pos++].toInt() and 0xFF)
        val to2End = pdu.indexOf(0, pos)
        assertEquals("user@example.com", String(pdu, pos, to2End - pos, Charsets.US_ASCII))
        pos = to2End + 1

        // Content-Type (0x84): application/vnd.wap.multipart.mixed (0xA3)
        assertEquals(0x84, pdu[pos++].toInt() and 0xFF)
        assertEquals(0xA3, pdu[pos++].toInt() and 0xFF)

        // Multipart count: 2 (text + image)
        assertEquals(2, pdu[pos++].toInt() and 0xFF)

        // Part 1: text/plain (0x83)
        val textExpected = "Look at this!".toByteArray(Charsets.UTF_8)
        assertEquals(1, pdu[pos++].toInt() and 0xFF) // headersLen
        assertEquals(textExpected.size, pdu[pos++].toInt() and 0xFF) // dataLen
        assertEquals(0x83, pdu[pos++].toInt() and 0xFF) // Content-Type: text/plain
        assertArrayEquals(textExpected, pdu.copyOfRange(pos, pos + textExpected.size))
        pos += textExpected.size

        // Part 2: image/jpeg + NUL (11 bytes) and 300-byte payload (uintvar 0x82, 0x2C)
        assertEquals(11, pdu[pos++].toInt() and 0xFF) // headersLen
        assertEquals(0x82, pdu[pos++].toInt() and 0xFF) // dataLen high byte (300 = 2*128 + 44)
        assertEquals(0x2C, pdu[pos++].toInt() and 0xFF) // dataLen low byte
        val mimeEnd = pdu.indexOf(0, pos)
        assertEquals("image/jpeg", String(pdu, pos, mimeEnd - pos, Charsets.US_ASCII))
        pos = mimeEnd + 1

        assertArrayEquals(imageBytes, pdu.copyOfRange(pos, pos + imageBytes.size))
        pos += imageBytes.size
        assertEquals(pdu.size, pos)
    }

    @Test
    fun `buildMmsSendReqPdu omits text part when body is blank`() {
        val pngBytes = byteArrayOf(0x89.toByte(), 0x50, 0x4E, 0x47)
        val pdu = PhoneSms.buildMmsSendReqPdu(
            to = listOf("5550199"),
            body = "   ",
            attachments = listOf(SmsAttachment(mime = "image/png", data = pngBytes)),
            transactionId = "nl-42",
        )

        // Find Content-Type (0x84, 0xA3) at the end of the headers
        var idx = 0
        while (idx < pdu.size - 1 && !((pdu[idx].toInt() and 0xFF) == 0x84 && (pdu[idx + 1].toInt() and 0xFF) == 0xA3)) {
            idx++
        }
        assertTrue(idx < pdu.size - 2)
        var pos = idx + 2

        // Multipart count: 1 (image only)
        assertEquals(1, pdu[pos++].toInt() and 0xFF)
        assertEquals(10, pdu[pos++].toInt() and 0xFF) // "image/png\0" length
        assertEquals(pngBytes.size, pdu[pos++].toInt() and 0xFF)
        val mimeEnd = pdu.indexOf(0, pos)
        assertEquals("image/png", String(pdu, pos, mimeEnd - pos, Charsets.US_ASCII))
        pos = mimeEnd + 1
        assertArrayEquals(pngBytes, pdu.copyOfRange(pos, pdu.size))
    }

    @Test
    fun `buildConversation extracts 1-to-1 and group MessagingStyle metadata with bounds`() {
        val smallAvatar = ByteArray(1024) { 1 }
        val oversizedAvatar = ByteArray(20 * 1024) { 2 }

        val msgs = (1..30).map { i ->
            NotificationChatMessage(
                sender = if (i % 2 == 0) "Me" else "Alice",
                text = "Message $i",
                time = 1_700_000_000_000L + i * 1000L,
                selfSent = i % 2 == 0,
                avatar = if (i % 2 == 0) oversizedAvatar else smallAvatar,
            )
        }

        val conv = NotificationReader.buildConversation(
            styleTitle = null,
            fallbackTitle = "Fallback",
            isGroup = false,
            convAvatar = smallAvatar,
            messages = msgs,
        )
        assertNotNull(conv)
        assertEquals("Alice", conv!!.title)
        assertFalse(conv.group)
        assertEquals(25, conv.messages.size)
        assertEquals("Message 6", conv.messages.first().text)
        assertEquals("Message 30", conv.messages.last().text)
        // Self-sent messages drop sender and oversized avatars
        assertTrue(conv.messages.last().selfSent)
        assertNull(conv.messages.last().sender)
        assertNull(conv.messages.last().avatar)

        val groupConv = NotificationReader.buildConversation(
            styleTitle = "Family Chat",
            fallbackTitle = "Alice",
            isGroup = true,
            convAvatar = oversizedAvatar,
            messages = msgs.take(2),
        )
        assertNotNull(groupConv)
        assertEquals("Family Chat", groupConv!!.title)
        assertTrue(groupConv.group)
        assertNull(groupConv.avatar)
    }

    @Test
    fun `fuzz MmsPdu build and parse across 10000 deterministic iterations`() {
        val rng = java.util.Random(0x4E435452_2026L)
        val mimes = listOf("image/jpeg", "image/png", "audio/mp4", "", "   ", "application/octet-stream")

        for (iter in 0 until 10_000) {
            when (iter % 3) {
                0 -> {
                    // Pure random / corrupted byte arrays, oversized uintvars, truncated headers
                    val len = rng.nextInt(512)
                    val randomBytes = ByteArray(len).also(rng::nextBytes)
                    if (len >= 5 && iter % 9 == 0) {
                        // Inject 5+ continuation MSB bytes to test uintvar overflow guard
                        for (k in 0 until minOf(len, 8)) {
                            randomBytes[k] = (randomBytes[k].toInt() or 0x80).toByte()
                        }
                    }
                    val uintvar = PhoneSms.readUintvar(randomBytes, if (len > 0) rng.nextInt(len) else 0)
                    if (uintvar != null) {
                        assertTrue(uintvar.first >= 0)
                        assertTrue(uintvar.second <= randomBytes.size)
                    }
                    // Must never throw on arbitrary/corrupted bytes
                    PhoneSms.parseMmsPdu(randomBytes)
                }
                1 -> {
                    // Valid round-trip buildMmsSendReqPdu + parseMmsPdu
                    val recipientCount = rng.nextInt(4)
                    val recipients = List(recipientCount) { idx ->
                        if (idx % 2 == 0) "+1555010${rng.nextInt(100)}" else "user$idx@example.com"
                    }
                    val bodyBytes = ByteArray(rng.nextInt(96)).also(rng::nextBytes)
                    val body = if (iter % 5 == 0) "" else String(bodyBytes, Charsets.UTF_8)
                    val attCount = rng.nextInt(3)
                    val attachments = List(attCount) {
                        val payload = ByteArray(rng.nextInt(320)).also(rng::nextBytes)
                        SmsAttachment(mime = mimes[rng.nextInt(mimes.size)], data = payload)
                    }
                    val txId = "nl-$iter"
                    val pdu = PhoneSms.buildMmsSendReqPdu(
                        to = recipients,
                        body = body,
                        attachments = attachments,
                        transactionId = txId,
                    )
                    val parsed = PhoneSms.parseMmsPdu(pdu)
                    assertNotNull("Valid SendReq PDU should parse at iter=$iter", parsed)
                    assertEquals(0x80, parsed!!.messageType)
                    assertEquals(txId, parsed.transactionId)
                    assertEquals(attachments.size, parsed.attachments.size)
                }
                else -> {
                    // Mutated / truncated SendReq PDU fuzzing
                    val base = PhoneSms.buildMmsSendReqPdu(
                        to = listOf("+15550199"),
                        body = "Hello \uD83D\uDC1D $iter",
                        attachments = listOf(
                            SmsAttachment(
                                mime = "image/jpeg",
                                data = ByteArray(rng.nextInt(200)).also(rng::nextBytes),
                            ),
                        ),
                        transactionId = "tx-$iter",
                    )
                    val mutated = if (rng.nextBoolean() && base.isNotEmpty()) {
                        // Truncate at random point
                        base.copyOf(rng.nextInt(base.size))
                    } else {
                        base.copyOf().also { arr ->
                            repeat(1 + rng.nextInt(6)) {
                                if (arr.isNotEmpty()) {
                                    arr[rng.nextInt(arr.size)] = rng.nextInt(256).toByte()
                                }
                            }
                        }
                    }
                    PhoneSms.parseMmsPdu(mutated)
                }
            }
        }
    }

    @Test
    fun `fuzz MessagingStyle and ProgressStyle extraction across 10000 deterministic iterations`() {
        val rng = java.util.Random(0x4245455F_3335L)

        fun randomNullableString(maxLen: Int): String? = when (rng.nextInt(5)) {
            0 -> null
            1 -> ""
            2 -> "   \t\n  "
            else -> {
                val raw = ByteArray(rng.nextInt(maxLen + 1)).also(rng::nextBytes)
                String(raw, Charsets.UTF_8)
            }
        }

        fun randomAvatar(): ByteArray? = when (rng.nextInt(4)) {
            0 -> null
            1 -> ByteArray(0)
            2 -> ByteArray(1 + rng.nextInt(16 * 1024)) { 1 }
            else -> ByteArray(16 * 1024 + 1 + rng.nextInt(8 * 1024)) { 2 }
        }

        for (iter in 0 until 10_000) {
            val msgCount = rng.nextInt(35)
            val messages = List(msgCount) {
                NotificationChatMessage(
                    sender = randomNullableString(48),
                    text = randomNullableString(120).orEmpty(),
                    time = rng.nextLong(),
                    selfSent = rng.nextBoolean(),
                    avatar = randomAvatar(),
                )
            }
            val conv = NotificationReader.buildConversation(
                styleTitle = randomNullableString(64),
                fallbackTitle = randomNullableString(64),
                isGroup = rng.nextBoolean(),
                convAvatar = randomAvatar(),
                messages = messages,
            )
            if (messages.none { it.text.isNotBlank() }) {
                assertNull(conv)
            }
            if (conv != null) {
                assertTrue(conv.title.isNotBlank() && conv.title.length <= 256)
                assertTrue(conv.messages.size in 1..25)
                if (conv.avatar != null) {
                    assertTrue(conv.avatar!!.size <= 16 * 1024)
                }
                for (m in conv.messages) {
                    assertTrue(m.text.isNotBlank())
                    if (m.selfSent) assertNull(m.sender)
                    if (m.avatar != null) assertTrue(m.avatar!!.size <= 16 * 1024)
                }
            }

            val segCount = rng.nextInt(20)
            val segments = List(segCount) {
                app.maclink.core.LiveSegment(
                    length = rng.nextInt(500).coerceAtLeast(0).toUInt(),
                    color = if (rng.nextBoolean()) rng.nextInt().toUInt() else null,
                )
            }
            val ptCount = rng.nextInt(20)
            val points = List(ptCount) {
                app.maclink.core.LivePoint(
                    position = rng.nextInt(500).coerceAtLeast(0).toUInt(),
                    color = if (rng.nextBoolean()) rng.nextInt().toUInt() else null,
                )
            }
            val live = NotificationReader.buildLive(
                progress = rng.nextInt(400) - 100,
                progressMax = rng.nextInt(400) - 100,
                indeterminate = rng.nextBoolean(),
                chip = randomNullableString(48),
                segments = segments,
                points = points,
                chronometer = rng.nextBoolean(),
                countdown = rng.nextBoolean(),
                promoted = rng.nextBoolean(),
            )
            if (live != null) {
                live.max?.let { maxVal ->
                    live.progress?.let { p -> assertTrue(p <= maxVal) }
                }
                live.chip?.let { chip -> assertTrue(chip.length <= 16) }
                assertTrue(live.segments.size <= 16)
                assertTrue(live.points.size <= 16)
            }
        }
    }

    private fun ByteArray.indexOf(byte: Byte, startIndex: Int): Int {
        for (i in startIndex until size) {
            if (this[i] == byte) return i
        }
        return -1
    }
}
