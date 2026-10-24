buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        // 🆕 HMS: إضافة com.huawei.agconnect تبحث عن com.android.tools.build:gradle
        // داخل buildscript classpath لمعرفة إصدار AGP، وبدونها تفشل بـ "No value present".
        // يجب أن يطابق الإصدار القيمة في settings.gradle.kts (com.android.application).
        classpath("com.android.tools.build:gradle:8.11.1")
    }
}

allprojects {
    repositories {
        // ✅ التغيير هنا أيضاً: تغيير الترتيب
        gradlePluginPortal()
        google()
        mavenCentral()
        // 🆕 HMS: مستودع Huawei للمكتبات (huawei_push وما يتبعها)
        maven { url = uri("https://developer.huawei.com/repo/") }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
