import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

// App Check debug token.
// Reads from local.properties first, then from environment variables.
val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        FileInputStream(localPropertiesFile).use { load(it) }
    }
}

val firebaseAppCheckDebugToken: String =
    (localProperties.getProperty("firebaseAppCheckDebugToken")
        ?: System.getenv("FIREBASE_APPCHECK_DEBUG_TOKEN")
        ?: "")

android {
    ndkVersion = "28.2.13676358"
    namespace = "medaad.app.com"
    compileSdk = 36

    defaultConfig {
        applicationId = "medaad.app.com"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            keyAlias = System.getenv("KEY_ALIAS")?.trim()
                ?: throw GradleException("KEY_ALIAS not set")

            keyPassword = System.getenv("KEY_PASSWORD")?.trim()
                ?: throw GradleException("KEY_PASSWORD not set")

            storePassword = System.getenv("STORE_PASSWORD")?.trim()
                ?: throw GradleException("STORE_PASSWORD not set")

            storeFile = file("keystore/upload-keystore.jks")
        }
    }

    buildTypes {

        release {
            // توقيع نسخة الريليز
            signingConfig = signingConfigs.getByName("release")

            isMinifyEnabled = true
            isShrinkResources = true

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            // استخدام نفس App Check Debug Token في الـ Release
            manifestPlaceholders["firebaseAppCheckDebugToken"] =
                firebaseAppCheckDebugToken
        }

        getByName("debug") {
            // استخدام توقيع الريليز في الديبج
            signingConfig = signingConfigs.getByName("release")

            // استخدام نفس App Check Debug Token في الـ Debug
            manifestPlaceholders["firebaseAppCheckDebugToken"] =
                firebaseAppCheckDebugToken
        }
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true

        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Desugaring support
    coreLibraryDesugaring(
        "com.android.tools:desugar_jdk_libs:2.1.5"
    )

    implementation(
        platform("com.google.firebase:firebase-bom:34.8.0")
    )

    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-crashlytics")
    implementation("androidx.multidex:multidex:2.0.1")
}
