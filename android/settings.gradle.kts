pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // ✅ التغيير هنا: وضعنا البوابة في المقدمة لتجاوز الحظر
        gradlePluginPortal()
        google()
        mavenCentral()
        // 🆕 HMS: مستودع Huawei (يحتوي على إضافة com.huawei.agconnect)
        maven { url = uri("https://developer.huawei.com/repo/") }
    }

    // 🆕 HMS: إضافة Huawei غير منشورة بصيغة plugin-marker، لذلك نربط الـ id بالمكتبة يدوياً
    // ملاحظة: في app/build.gradle.kts يُطلب الـ plugin بدون version، فتكون requested.version = null، لذلك نضع نسخة احتياطية (يجب أن تطابق النسخة في plugins{} بالأسفل)
    resolutionStrategy {
        eachPlugin {
            if (requested.id.id == "com.huawei.agconnect") {
                useModule("com.huawei.agconnect:agcp:${requested.version ?: "1.9.5.302"}")
            }
        }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    // إضافة إصدارات إضافات Firebase
    id("com.google.gms.google-services") version "4.4.2" apply false
    id("com.google.firebase.crashlytics") version "3.0.2" apply false
    // 🆕 HMS: إضافة AppGallery Connect (تقرأ agconnect-services.json)
    id("com.huawei.agconnect") version "1.9.5.302" apply false
}

include(":app")

// 🆕 HMS: إصلاحات توافق لإضافات Flutter القديمة. تُطبَّق على نسخة الإضافة في pub-cache قبل تقييم المشاريع
// (تعمل محلياً وعلى GitHub Actions، ولا يتغير أي ملف إن لم تكن المشكلة موجودة):
//  1) Gradle 9 حذف jcenter() ← نستبدله بـ mavenCentral() في android/build.gradle.
//  2) Flutter الحديث حذف PluginRegistry.Registrar (v1 embedding) ← نحذف سطر import غير المستخدم
//     (هذا ما يكسر flutter_hms_gms_availability: Unresolved reference 'Registrar').
run {
    val pluginsDeps = file("../.flutter-plugins-dependencies")
    val registrarImport =
        Regex("(?m)^[ \\t]*import io\\.flutter\\.plugin\\.common\\.PluginRegistry\\.Registrar;?[ \\t]*\\r?\\n")
    if (pluginsDeps.exists()) {
        Regex("\"path\"\\s*:\\s*\"([^\"]+)\"")
            .findAll(pluginsDeps.readText())
            .map { it.groupValues[1].replace("\\\\", "/") }
            .distinct()
            .forEach { pluginDir ->
                try {
                    val buildFile = java.io.File(pluginDir, "android/build.gradle")
                    if (buildFile.isFile) {
                        val text = buildFile.readText()
                        if (text.contains("jcenter()")) {
                            buildFile.writeText(text.replace("jcenter()", "mavenCentral()"))
                            println("settings: replaced jcenter() with mavenCentral() in ${buildFile.path}")
                        }
                    }
                    java.io.File(pluginDir, "android/src").walkTopDown()
                        .filter { it.isFile && (it.extension == "kt" || it.extension == "java") }
                        .forEach { src ->
                            val code = src.readText()
                            val cleaned = registrarImport.replace(code, "")
                            // نحذف الـ import فقط إذا لم يكن Registrar مستخدماً في أي مكان آخر بالملف
                            if (cleaned != code && !cleaned.contains("Registrar")) {
                                src.writeText(cleaned)
                                println("settings: removed unused Registrar import in ${src.path}")
                            }
                        }
                } catch (e: Exception) {
                    println("settings: could not patch plugin at $pluginDir: ${e.message}")
                }
            }
    }
}
