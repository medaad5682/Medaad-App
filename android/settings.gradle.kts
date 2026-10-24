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
    resolutionStrategy {
        eachPlugin {
            if (requested.id.id == "com.huawei.agconnect") {
                useModule("com.huawei.agconnect:agcp:${requested.version}")
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
