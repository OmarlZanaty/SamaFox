# G1/G6 — keep rules for the release build.
#
# R8 is enabled so the 161 MB release stops costing users on metered data a
# fortune to install. Shrinking is only safe if everything reached by
# REFLECTION rather than by a direct call survives, and that is what this file
# is for. Each block below names why it exists; do not prune one without
# checking the plugin still works in a release build, because the failure mode
# is a runtime ClassNotFoundException on a device, not a build error.

# ── Flutter engine ────────────────────────────────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**

# ── flutter_webrtc / libwebrtc ────────────────────────────────────────────────
# The voice engine. Its Java layer is called from native code, so R8 cannot see
# the references and would strip them.
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**
-keep class com.cloudwebrtc.webrtc.** { *; }

# ── Our own foreground service ────────────────────────────────────────────────
# Referenced from the manifest by name, never constructed in Kotlin.
-keep class com.almobarmg.samafox.RoomAudioService { *; }
-keep class com.almobarmg.samafox.MainActivity { *; }

# ── Firebase / Google Play services (google-services.json is present) ─────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# ── Facebook login ────────────────────────────────────────────────────────────
-keep class com.facebook.** { *; }
-dontwarn com.facebook.**

# ── image_cropper (uCrop), declared as an activity in the manifest ────────────
-keep class com.yalantis.ucrop.** { *; }
-dontwarn com.yalantis.ucrop.**

# ── flutter_sound / audio ─────────────────────────────────────────────────────
-keep class com.dooboolab.** { *; }
-dontwarn com.dooboolab.**

# ── Kotlin coroutines internals reached reflectively ──────────────────────────
-keepclassmembers class kotlinx.coroutines.** { volatile <fields>; }
-dontwarn kotlinx.coroutines.**

# ── Model classes serialised to/from JSON ─────────────────────────────────────
# The Dart side does the JSON work, but any Java/Kotlin model that survives a
# plugin boundary must keep its field names.
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Keep annotations and signatures — needed for generics and for the crash
# reports to be readable.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
-keepattributes SourceFile, LineNumberTable
