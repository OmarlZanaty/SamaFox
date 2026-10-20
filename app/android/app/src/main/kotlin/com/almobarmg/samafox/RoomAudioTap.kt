package com.almobarmg.samafox

import java.lang.reflect.Proxy
import java.util.concurrent.CopyOnWriteArrayList

/** Uses flutter_webrtc 1.3.x's existing ADM adapters. No second microphone and
 * no replacement of WebRTC's processing callbacks. Reflection is isolated here
 * so an SDK change selects the explicitly reported playback-capture fallback. */
class RoomAudioTap(private val receive: (Boolean, ByteArray, Int, Int, Long) -> Unit) {
    private val registrations = mutableListOf<Pair<Any, Any>>()
    @Volatile private var active = false

    fun attach(): Boolean = try {
        val pluginClass = Class.forName("com.cloudwebrtc.webrtc.FlutterWebRTCPlugin")
        val plugin = pluginClass.getField("sharedSingleton").get(null) ?: error("No WebRTC instance")
        val handlerField = pluginClass.getDeclaredField("methodCallHandler").apply { isAccessible = true }
        val handler = handlerField.get(plugin) ?: error("No WebRTC handler")
        // These adapters are the same sample sources used by the plugin's
        // AudioSamplesInterceptor. Playback adapter avoids installing/replacing
        // OutputAudioSamplesInterceptor's low-level AudioTrack callback.
        register(handler, "recordSamplesReadyCallbackAdapter", false)
        register(handler, "playbackSamplesReadyCallbackAdapter", true)
        active = true
        true
    } catch (_: Exception) {
        close()
        false
    }

    private fun register(handler: Any, name: String, remote: Boolean) {
        val adapter = handler.javaClass.getField(name).get(handler) ?: error("ADM not initialized")
        // 1.3.0's playback adapter iterates an ArrayList without synchronization.
        // Copy-on-write makes recording start/stop safe while its audio thread
        // iterates. Existing callbacks are preserved, including SDK recording.
        val callbacksField = adapter.javaClass.getDeclaredField("callbacks").apply { isAccessible = true }
        @Suppress("UNCHECKED_CAST")
        val existing = callbacksField.get(adapter) as MutableList<Any>
        synchronized(existing) {
            if (existing !is CopyOnWriteArrayList<*>) callbacksField.set(adapter, CopyOnWriteArrayList(existing))
        }
        val add = adapter.javaClass.methods.first { it.name == "addCallback" }
        val callbackType = add.parameterTypes[0]
        val proxy = Proxy.newProxyInstance(callbackType.classLoader, arrayOf(callbackType)) { proxy, method, args ->
            when (method.name) {
                "equals" -> proxy === args?.firstOrNull()
                "hashCode" -> System.identityHashCode(proxy)
                "toString" -> "SamaFoxRecorderAudioTap"
                else -> {
                    if (active && args?.size == 1) {
                        try {
                            val samples = args[0]
                            val type = samples.javaClass
                            // PCM16 is the ADM's normal format. Unknown formats
                            // are ignored rather than interpreted as corrupt PCM.
                            if (type.getMethod("getAudioFormat").invoke(samples) == 2) {
                                val bytes = type.getMethod("getData").invoke(samples) as ByteArray
                                val rate = type.getMethod("getSampleRate").invoke(samples) as Int
                                val channels = type.getMethod("getChannelCount").invoke(samples) as Int
                                receive(remote, bytes.copyOf(), rate, channels, System.nanoTime())
                            }
                        } catch (_: Exception) { /* Never throw on WebRTC's audio thread. */ }
                    }
                    null
                }
            }
        }
        add.invoke(adapter, proxy)
        registrations.add(adapter to proxy)
    }

    fun close() {
        active = false
        registrations.forEach { (adapter, callback) ->
            runCatching { adapter.javaClass.methods.first { it.name == "removeCallback" }.invoke(adapter, callback) }
        }
        registrations.clear()
    }
}
