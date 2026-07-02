# الحفاظ على توابع الـ Native
-keepattributes *Annotation*
-keepclasseswithmembernames class * {
    native <methods>;
}

# --- Flutter Local Notifications & Gson Fix ---
# هذه القواعد ضرورية لمنع حذف الكلاسات التي تستخدمها مكتبة الإشعارات في وضع Release
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keepattributes Signature
-keepattributes *Annotation*

# ==========================================
# --- Security Fix (N-05): Strip Logs ---
# ==========================================
# إزالة سجلات verbose/debug/info في الـ release
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
# الإبقاء على w() و e() لأنها ضرورية لتشخيص الأعطال (Crash diagnostics)

# إزالة دوال الطباعة الخاصة بجافا (System.out.println)
-assumenosideeffects class java.io.PrintStream {
    public void println(...);
    public void print(...);
}

# ==========================================
# --- Media3 / ExoPlayer HLS Fix ---
# ==========================================
# نمنع ProGuard من حذف كلاسات Media3 أثناء التصغير (minification).
# بدون هذه القواعد قد يُحذف MediaCodecVideoRenderer أو HlsMediaSource
# في نسخة الـ Release وهو ما يسبب فشل تشغيل HLS MPEG-TS.
-keep class androidx.media3.** { *; }
-keep interface androidx.media3.** { *; }
-dontwarn androidx.media3.**

# الحفاظ على فئات ExoPlayer القديمة (com.google.android.exoplayer2)
# التي قد تستخدمها مكتبات أخرى كـ youtube_player_flutter
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**
