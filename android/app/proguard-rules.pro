# الحفاظ على مكتبات FFmpeg Kit
# ملاحظة: مشكلة "Bad JNI version returned from JNI_OnLoad" معروفة وتحدث
# بسبب R8 full mode الذي يعيد تسمية/يحسّن كلاسات تستخدمها مكتبة FFmpegKit
# داخلياً عبر JNI، حتى مع وجود -keep على الحزمة بالكامل.
-keep,allowshrinking class com.arthenica.ffmpegkit.** { *; }
-keepclassmembers class com.arthenica.ffmpegkit.** { *; }
-dontwarn com.arthenica.ffmpegkit.**
-keep class com.arthenica.smartexception.** { *; }
-dontwarn com.arthenica.smartexception.**

# --- Firebase App Check ---
-keep class com.google.firebase.appcheck.** { *; }
-dontwarn com.google.firebase.appcheck.**

# --- pdfrx (native PDF rendering bridge) ---
-keep class io.scer.pdf.** { *; }
-keep class com.github.espresso3389.pdfrx.** { *; }
-dontwarn com.github.espresso3389.pdfrx.**

# --- Hive (uses reflection for TypeAdapter registration) ---
-keep class hive.** { *; }
-keepclassmembers class * {
    @hive.HiveField *;
}

# --- Firebase general (Crashlytics/Analytics reflection-based init) ---
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

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
