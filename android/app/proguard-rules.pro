# الحفاظ على مكتبات FFmpeg Kit
-keep class com.arthenica.ffmpegkit.** { *; }
-keep class com.arthenica.smartexception.** { *; }

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
