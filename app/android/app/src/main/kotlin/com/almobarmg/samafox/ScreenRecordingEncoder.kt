package com.almobarmg.samafox

import android.content.Context
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.*
import android.media.projection.MediaProjection
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.DisplayMetrics
import android.view.Surface
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.atomic.AtomicBoolean

/** All codec/muxer work belongs to one worker. Audio callbacks only copy PCM
 * into bounded queues, so slow storage cannot stall the room's audio thread. */
class ScreenRecordingEncoder(
    private val context: Context,
    private val projection: MediaProjection,
    private val metrics: DisplayMetrics,
    private val descriptor: ParcelFileDescriptor?,
    private val file: File?,
    private val started: (Boolean) -> Unit,
    private val completed: (Boolean, String?) -> Unit,
) {
    companion object {
        private val ownSessions = java.util.concurrent.ConcurrentHashMap.newKeySet<Int>()
        fun ownsCapture(sessionId: Int): Boolean = ownSessions.contains(sessionId)
    }
    private data class Pcm(val source: Int, val data: ByteArray, val rate: Int, val channels: Int, val at: Long)
    private data class Encoded(val video: Boolean, val data: ByteArray, val info: MediaCodec.BufferInfo)
    private val queue = ArrayBlockingQueue<Pcm>(80)
    private val stopping = AtomicBoolean(false)
    private val captures = mutableListOf<AudioRecord>()
    private val captureThreads = mutableListOf<Thread>()
    private var tap: RoomAudioTap? = null
    private var video: MediaCodec? = null
    private var audio: MediaCodec? = null
    private var muxer: MediaMuxer? = null
    private var display: VirtualDisplay? = null
    private var surface: Surface? = null
    private var muxing = false
    private var videoTrack = -1
    private var audioTrack = -1
    private var videoSamples = 0
    private var audioSamples = 0
    private val pending = ArrayList<Encoded>()
    private var pendingBytes = 0
    private var epochNs = 0L
    private var lastVideoPts = -1L
    private var lastAudioPts = -1L
    private var videoOffset: Long? = null

    fun start() { Thread({ run() }, "samafox-record-encoder").start() }
    fun stop() { stopping.set(true) }

    private fun offer(source: Int, data: ByteArray, rate: Int, channels: Int, at: Long) {
        if (!stopping.get()) queue.offer(Pcm(source, data, rate, channels, at))
    }

    private fun run() {
        var success = false
        var error: String? = null
        try {
            setup()
            val mixer = RecordingPcmMixer(epochNs)
            val rtcTap = RoomAudioTap { remote, data, rate, channels, at -> offer(if (remote) 1 else 0, data, rate, channels, at) }
            tap = rtcTap
            val hasRoomAudio = rtcTap.attach()
            if (!hasRoomAudio) startMicrophone()
            // Media/game/gift playback supplements WebRTC and is the fallback
            // for other app audio if the SDK interceptors cannot be reached.
            if (Build.VERSION.SDK_INT >= 29) runCatching { startPlayback() }
            started(hasRoomAudio)
            while (!stopping.get()) {
                collect(mixer)
                // 80 ms of lookahead tolerates callback jitter, without shifting
                // video: AAC timestamps still start at sample zero.
                val due = ((System.nanoTime() - epochNs - 80_000_000).coerceAtLeast(0) * 48000 / 1_000_000_000)
                var batches = 0
                while (mixer.frame + 480 <= due && batches++ < 20) {
                    if (!feedAudio(mixer)) break
                }
                drain(video!!, true)
                drain(audio!!, false)
                Thread.sleep(3)
            }
            tap?.close()
            stopCaptures()
            collect(mixer)
            val finalFrame = (System.nanoTime() - epochNs) * 48000 / 1_000_000_000
            val finishDeadline = System.nanoTime() + 4_000_000_000
            while (mixer.frame + 480 <= finalFrame && System.nanoTime() < finishDeadline) {
                feedAudio(mixer)
                drain(video!!, true)
                drain(audio!!, false)
            }
            display?.release(); display = null
            video!!.signalEndOfInputStream()
            var audioEosSent = false
            var videoDone = false
            var audioDone = false
            while ((!videoDone || !audioDone) && System.nanoTime() < finishDeadline) {
                if (!audioEosSent) {
                    val index = audio!!.dequeueInputBuffer(1000)
                    if (index >= 0) {
                        audio!!.queueInputBuffer(index, 0, 0, mixer.frame * 1_000_000 / 48000, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        audioEosSent = true
                    }
                }
                videoDone = drain(video!!, true) || videoDone
                audioDone = drain(audio!!, false) || audioDone
                Thread.sleep(2)
            }
            if (muxing) {
                muxer!!.stop()
                muxing = false
                success = videoDone && audioDone && videoSamples > 0 && audioSamples > 0
            }
        } catch (e: Exception) {
            error = e.message ?: e.javaClass.simpleName
        } finally {
            stopping.set(true)
            tap?.close()
            stopCaptures()
            runCatching { display?.release() }
            runCatching { video?.stop() }; runCatching { video?.release() }
            runCatching { audio?.stop() }; runCatching { audio?.release() }
            runCatching { surface?.release() }
            runCatching { if (muxing) muxer?.stop() }; runCatching { muxer?.release() }
            runCatching { descriptor?.close() }
            completed(success, error)
        }
    }

    private fun setup() {
        val scale = minOf(1.0, 720.0 / metrics.widthPixels, 1280.0 / metrics.heightPixels)
        val width = ((metrics.widthPixels * scale).toInt() / 2 * 2).coerceAtLeast(2)
        val height = ((metrics.heightPixels * scale).toInt() / 2 * 2).coerceAtLeast(2)
        video = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC).also { encoder ->
            val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                setInteger(MediaFormat.KEY_BIT_RATE, 4_000_000)
                setInteger(MediaFormat.KEY_FRAME_RATE, 30)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
                setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
                setFloat("max-fps-to-encoder", 30f)
            }
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            surface = encoder.createInputSurface()
            encoder.start()
        }
        audio = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC).also { encoder ->
            val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, 48000, 1).apply {
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                setInteger(MediaFormat.KEY_BIT_RATE, 128000)
                setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 4096)
            }
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()
        }
        muxer = if (Build.VERSION.SDK_INT >= 26 && descriptor != null)
            MediaMuxer(descriptor.fileDescriptor, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        else MediaMuxer(file!!.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        epochNs = System.nanoTime()
        display = projection.createVirtualDisplay("SamaFoxRecording", width, height, metrics.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, surface, null, null)
    }

    private fun collect(mixer: RecordingPcmMixer) {
        while (true) {
            val pcm = queue.poll() ?: break
            mixer.offer(pcm.source, pcm.data, pcm.rate, pcm.channels, pcm.at)
        }
    }

    private fun feedAudio(mixer: RecordingPcmMixer): Boolean {
        val encoder = audio!!
        val index = encoder.dequeueInputBuffer(1000)
        if (index < 0) return false
        val pts = mixer.frame * 1_000_000 / 48000
        val pcm = mixer.mix()
        encoder.getInputBuffer(index)!!.apply { clear(); put(pcm) }
        encoder.queueInputBuffer(index, 0, pcm.size, pts, 0)
        return true
    }

    private fun drain(encoder: MediaCodec, isVideo: Boolean): Boolean {
        val info = MediaCodec.BufferInfo()
        while (true) {
            val index = encoder.dequeueOutputBuffer(info, 0)
            if (index == MediaCodec.INFO_TRY_AGAIN_LATER) return false
            if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                val track = muxer!!.addTrack(encoder.outputFormat)
                if (isVideo) videoTrack = track else audioTrack = track
                if (videoTrack >= 0 && audioTrack >= 0 && !muxing) {
                    muxer!!.start(); muxing = true
                    for (sample in pending) write(sample)
                    pending.clear(); pendingBytes = 0
                }
                continue
            }
            if (index < 0) continue
            val buffer = encoder.getOutputBuffer(index)!!
            if (info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                buffer.position(info.offset); buffer.limit(info.offset + info.size)
                val bytes = ByteArray(info.size); buffer.get(bytes)
                var pts = info.presentationTimeUs
                if (isVideo) {
                    if (videoOffset == null) {
                        // Surface encoders normally use CLOCK_MONOTONIC. Some
                        // vendors start at zero; recognize that clock too.
                        videoOffset = if (pts > epochNs / 1000 - 10_000_000) epochNs / 1000 else 0
                    }
                    pts = (pts - videoOffset!!).coerceAtLeast(lastVideoPts + 1)
                    lastVideoPts = pts
                } else { pts = pts.coerceAtLeast(lastAudioPts + 1); lastAudioPts = pts }
                val sample = Encoded(isVideo, bytes, MediaCodec.BufferInfo().apply { set(0, bytes.size, pts, info.flags) })
                if (muxing) write(sample) else {
                    pendingBytes += bytes.size
                    check(pendingBytes <= 4 * 1024 * 1024) { "Encoder did not provide both track formats" }
                    pending.add(sample)
                }
            }
            val end = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
            encoder.releaseOutputBuffer(index, false)
            if (end) return true
        }
    }

    private fun write(sample: Encoded) {
        muxer!!.writeSampleData(if (sample.video) videoTrack else audioTrack, ByteBuffer.wrap(sample.data), sample.info)
        if (sample.video) videoSamples++ else audioSamples++
    }

    @Suppress("MissingPermission")
    private fun startMicrophone() {
        val size = maxOf(9600, AudioRecord.getMinBufferSize(48000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT))
        val record = AudioRecord(MediaRecorder.AudioSource.VOICE_COMMUNICATION, 48000,
            AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, size)
        startCapture(record, 0)
    }

    @android.annotation.TargetApi(29)
    @Suppress("MissingPermission")
    private fun startPlayback() {
        val config = AudioPlaybackCaptureConfiguration.Builder(projection)
            .addMatchingUsage(AudioAttributes.USAGE_MEDIA)
            .addMatchingUsage(AudioAttributes.USAGE_GAME)
            .addMatchingUsage(AudioAttributes.USAGE_UNKNOWN)
            .addMatchingUid(android.os.Process.myUid()).build()
        val format = AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT)
            .setSampleRate(48000).setChannelMask(AudioFormat.CHANNEL_IN_MONO).build()
        val record = AudioRecord.Builder().setAudioPlaybackCaptureConfig(config).setAudioFormat(format)
            .setBufferSizeInBytes(19200).build()
        startCapture(record, 2)
    }

    private fun startCapture(record: AudioRecord, source: Int) {
        ownSessions.add(record.audioSessionId)
        try {
            check(record.state == AudioRecord.STATE_INITIALIZED) { "Audio capture unavailable" }
            record.startRecording()
            check(record.recordingState == AudioRecord.RECORDSTATE_RECORDING)
        } catch (e: Exception) { ownSessions.remove(record.audioSessionId); record.release(); throw e }
        captures.add(record)
        val thread = Thread({
            val buffer = ByteArray(960)
            while (!stopping.get()) {
                val count = record.read(buffer, 0, buffer.size)
                if (count <= 0) break
                offer(source, buffer.copyOf(count), 48000, 1, System.nanoTime())
            }
        }, "samafox-record-pcm-$source")
        captureThreads.add(thread); thread.start()
    }

    private fun stopCaptures() {
        for (record in captures) runCatching { record.stop() }
        for (thread in captureThreads) runCatching { thread.join(500) }
        for (record in captures) {
            ownSessions.remove(record.audioSessionId)
            runCatching { record.release() }
        }
        captures.clear(); captureThreads.clear()
    }
}
