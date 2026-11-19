# ==============================================================================
# LOTUS PLAYER — PRODUCTION PROGUARD / R8 OPTIMIZATION & KEEP RULES
# File: android/app/proguard-rules.pro
# Updated: 2026-11-17 | Compatible: Media3 1.11.1, R8 Full Mode, AGP 8.x+
# ==============================================================================

# ── 1. DEBUGGING & STACK TRACES ──────────────────────────────────────────────
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
-keepattributes *Annotation*,InnerClasses,Signature,Exceptions,EnclosingMethod

# ── 2. FLUTTER ENGINE & EMBEDDING ────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# ── 3. LOTUS PLAYER — KEEP ALL NATIVE CODE (CRITICAL!) ───────────────────────
-keep class com.souljalazian.lotus_player.** { *; }
-keepclassmembers class com.souljalazian.lotus_player.** { *; }

# ── 4. ANDROID COMPONENTS — Services/Activities/Receivers ────────────────────
-keep public class * extends android.app.Service
-keep public class * extends android.app.Activity
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider

# ── 5. ANDROIDX CORE ────────────────────────────────────────────────────────
-keep class androidx.core.** { *; }
-dontwarn androidx.core.**

# ── 6. ANDROID AUDIO FRAMEWORK ──────────────────────────────────────────────
-keep class android.media.audiofx.** { *; }
-keepclassmembers class android.media.audiofx.** { *; }
-keep class android.media.** { *; }

# ── 7. MEDIA3 / EXOPLAYER — 1.11.1 COMPATIBLE ────────────────────────────────
-keep class androidx.media3.** { *; }
-keep interface androidx.media3.** { *; }
-keep enum androidx.media3.** { *; }
-dontwarn androidx.media3.exoplayer.**
-dontwarn androidx.media3.extractor.**
-dontwarn androidx.media3.decoder.**
-dontwarn androidx.media3.session.**

# ── 8. GUAVA / LISTENABLEFUTURE — Required by Media3 Session ─────────────────
-keep class com.google.common.util.concurrent.** { *; }
-dontwarn com.google.common.util.concurrent.**

# ── 9. JAUDIOTAGGER — Metadata Library ──────────────────────────────────────
-keep class org.jaudiotagger.** { *; }
-dontwarn org.jaudiotagger.**

# ── 10. ON_AUDIO_QUERY ──────────────────────────────────────────────────────
-keep class com.lucasjosino.on_audio_query.** { *; }
-dontwarn com.lucasjosino.on_audio_query.**

# ── 11. FLUTTER PLUGINS — Local Notifications, Permissions, FileProvider ─────
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

-keep class androidx.core.content.FileProvider { *; }

# ── 12. SHARE+ / PATH PROVIDER / URL LAUNCHER ────────────────────────────────
-keep class dev.fluttercommunity.plus.** { *; }
-dontwarn dev.fluttercommunity.plus.**

-keep class io.flutter.plugins.pathprovider.** { *; }
-dontwarn io.flutter.plugins.pathprovider.**

-keep class io.flutter.plugins.urllauncher.** { *; }
-dontwarn io.flutter.plugins.urllauncher.**

-keep class io.flutter.plugins.sharedpreferences.** { *; }
-dontwarn io.flutter.plugins.sharedpreferences.**

# ── 13. MEDIASTORE & INTENTS ─────────────────────────────────────────────────
-keep class android.provider.MediaStore { *; }
-keep class android.content.IntentSender { *; }

# ── 14. JAVA 8+ DESUGARING & KOTLIN ──────────────────────────────────────────
-keep class java.time.** { *; }
-keepclassmembers class * extends java.lang.Enum {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
-dontwarn kotlinx.coroutines.**
