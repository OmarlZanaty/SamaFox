package com.almobarmg.samafox

import kotlin.math.abs
import kotlin.math.roundToInt

/** Worker-thread-only, bounded one-second timeline. All sources are converted
 * to 48 kHz mono, aligned to a common monotonic clock, summed and saturated.
 * Gaps produce silence, not shifted audio; callbacks never block on encoding. */
class RecordingPcmMixer(private val epochNs: Long) {
    private class Source {
        val pcm = IntArray(48_000)
        val stamps = LongArray(48_000) { -1 }
        var next = -1L
    }
    private val sources = Array(3) { Source() }
    var frame = 0L
        private set

    fun offer(source: Int, bytes: ByteArray, rate: Int, channels: Int, capturedNs: Long) {
        if (rate !in 8000..192000 || channels !in 1..8) return
        val count = bytes.size / (channels * 2)
        if (count == 0) return
        val outputCount = (count.toLong() * 48000 / rate).toInt()
        if (outputCount !in 1..48000) return
        val stream = sources[source]
        val estimated = ((capturedNs - epochNs) * 48000 / 1_000_000_000 - outputCount).coerceAtLeast(0)
        if (stream.next < 0 || abs(stream.next - estimated) > 9600) stream.next = estimated
        fun mono(index: Int): Int {
            var sum = 0
            for (channel in 0 until channels) {
                val at = (index * channels + channel) * 2
                sum += ((bytes[at].toInt() and 255) or (bytes[at + 1].toInt() shl 8)).toShort().toInt()
            }
            return sum / channels
        }
        for (i in 0 until outputCount) {
            val position = i.toDouble() * rate / 48000
            val left = position.toInt().coerceAtMost(count - 1)
            val right = (left + 1).coerceAtMost(count - 1)
            val a = mono(left)
            val sample = (a + (mono(right) - a) * (position - left)).roundToInt()
            val at = stream.next++
            if (at < frame || at >= frame + 48000) continue
            val slot = (at % 48000).toInt()
            stream.pcm[slot] = sample
            stream.stamps[slot] = at
        }
    }

    fun mix(count: Int = 480): ByteArray {
        val result = ByteArray(count * 2)
        for (i in 0 until count) {
            val at = frame++
            val slot = (at % 48000).toInt()
            var sum = 0
            for (source in sources) if (source.stamps[slot] == at) sum += source.pcm[slot]
            val sample = sum.coerceIn(-32768, 32767)
            result[i * 2] = sample.toByte()
            result[i * 2 + 1] = (sample shr 8).toByte()
        }
        return result
    }
}
