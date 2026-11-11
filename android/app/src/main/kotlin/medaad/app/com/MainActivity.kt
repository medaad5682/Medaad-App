package medaad.app.com

import android.os.Bundle
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.AudioRecordingConfiguration
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorManager
import android.opengl.EGL14
import android.opengl.GLES20
import android.os.BatteryManager
import android.content.IntentFilter
import android.os.Build
import android.view.MotionEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import android.os.Handler
import android.os.Looper
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "medaad.app.com/audio_protection"
    
    private var audioManager: AudioManager? = null
    private var handler: Handler? = null
    private var recordingCheckRunnable: Runnable? = null

    // ✅ وضع الرسم: عند تفعيله نطلب من النظام إيصال كل عيّنة لمس منفصلة.
    // السبب: أندرويد يجمّع حركات اللمس بين كل frame والتالي في MotionEvent واحد
    // (عيّنات "تاريخية")، وFlutter يقرأ آخر عيّنة فقط ويتجاهل الباقي؛ فمع الحركة
    // السريعة بالإصبع تصل نقاط متباعدة ويظهر الخط كقطع مستقيمة. التفعيل مقصور على
    // وضع الرسم كي لا نزيد عدد أحداث اللمس في بقية التطبيق.
    @Volatile private var unbufferedInput = false

    // 🆕 HMS: التقاط الضغط على إشعار Huawei Push Kit بشكل حتمي.
    // السيرفر يرسل click_action {type: 1, action: "FLUTTER_NOTIFICATION_CLICK"}
    // (lib/hmsPush.js) وفي AndroidManifest.xml يوجد intent-filter بنفس الـ action،
    // فيفتح النظام MainActivity بهذا الـ action عند الضغط على الإشعار.
    //   - تشغيل بارد : onCreate يسجّل العلَم، وDart يستهلكه مرة واحدة (consumeLaunchTap)
    //   - التطبيق حي : onNewIntent يُبلّغ Dart مباشرة (onNotificationTap)
    // Dart لا يستمع لهذه القناة إلا عند اختيار مزوّد HMS، فلا أثر على مستخدمي FCM.
    private val TAP_CHANNEL = "medaad.app.com/notification_tap"
    private val NOTIFICATION_CLICK_ACTION = "FLUTTER_NOTIFICATION_CLICK"
    private var tapChannel: MethodChannel? = null
    @Volatile private var launchedByNotificationTap = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 🆕 HMS: تشغيل بارد بالضغط على إشعار. savedInstanceState != null يعني أن
        // النظام يعيد إنشاء النشاط (مثلاً بعد قتل العملية) بنفس الـ intent القديم،
        // فلا نعتبره ضغطة جديدة كي لا تُفتح شاشة الإشعارات من تلقاء نفسها.
        if (savedInstanceState == null && isNotificationTap(intent)) {
            launchedByNotificationTap = true
        }

        // ✅ 1. منع تسجيل الفيديو وأخذ لقطات الشاشة (FLAG_SECURE)
        // Applied in onCreate before first frame — consistent with FlutterWindowManagerPlus in Dart
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )

        // ✅ 2. منع تسجيل الصوت الداخلي (Internal Audio) - Android 10+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                audioManager?.allowedCapturePolicy = 3 // ALLOW_CAPTURE_BY_NONE
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        // ✅ 3. بدء حلقة المراقبة المستمرة للتطبيقات الخارجية
        startRecordingMonitoring()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkRecording" -> {
                    val isRecording = checkIfRecording()
                    result.success(isRecording)
                }
                "getAudioMode" -> {
                    val mode = audioManager?.mode ?: -1
                    result.success(mode)
                }
                "blockAudioCapture" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        audioManager?.allowedCapturePolicy = 3
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                // [FIX F-04] Expose native root detection to Flutter layer
                "isDeviceRooted" -> {
                    result.success(isDeviceRooted())
                }
                // كشف المحاكي بنظام نقاط (يشتغل على thread خلفي لأن فيه EGL)
                "getEmulatorSignals" -> {
                    Thread {
                        val m: Map<String, Any> = try {
                            getEmulatorSignals()
                        } catch (e: Throwable) {
                            mapOf("error" to (e.message ?: e.javaClass.simpleName))
                        }
                        runOnUiThread {
                            try { result.success(m) } catch (e: Throwable) { /* engine/activity انتهى */ }
                        }
                    }.start()
                }
                // تشخيص تفصيلي: أي فحص بالظبط فشل (يُرسل لـ Crashlytics)
                "getSecurityDiagnostics" -> {
                    result.success(getSecurityDiagnostics())
                }
                // تشخيص تفصيلي لسبب اعتبار الجهاز "بيسجل" (وضع الصوت / عدد جلسات التسجيل)
                "getRecordingDiagnostics" -> {
                    result.success(getRecordingDiagnostics())
                }
                // وضع الرسم في قارئ الـ PDF: إيصال كل عيّنات اللمس بلا تجميع
                "setUnbufferedInput" -> {
                    unbufferedInput = (call.arguments as? Boolean) ?: false
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // 🆕 HMS: قناة الضغط على الإشعارات (انظر التعليق أعلى الملف)
        val tap = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TAP_CHANNEL)
        tap.setMethodCallHandler { call, result ->
            when (call.method) {
                "consumeLaunchTap" -> {
                    val tapped = launchedByNotificationTap
                    launchedByNotificationTap = false // تُستهلك مرة واحدة
                    result.success(tapped)
                }
                else -> result.notImplemented()
            }
        }
        tapChannel = tap
    }

    // 🆕 HMS: النشاط singleTop، فالضغط على إشعار والتطبيق حي يصل هنا.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (isNotificationTap(intent)) {
            tapChannel?.invokeMethod("onNotificationTap", null)
        }
    }

    private fun isNotificationTap(intent: Intent?): Boolean {
        return intent?.action == NOTIFICATION_CLICK_ACTION
    }

    // ✅ طلب الإرسال غير المجمَّع (Unbuffered) لتيار اللمس الجاري. يُستدعى مع
    // ACTION_DOWN (وACTION_MOVE احتياطاً، فالطلب مجرد علَم ويتجاهل النظام أي حدث
    // آخر). متاح من API 21 ونحن minSdk 24.
    override fun dispatchTouchEvent(ev: MotionEvent?): Boolean {
        if (unbufferedInput && ev != null) {
            val action = ev.actionMasked
            if (action == MotionEvent.ACTION_DOWN || action == MotionEvent.ACTION_MOVE) {
                try {
                    window.decorView.requestUnbufferedDispatch(ev)
                } catch (e: Exception) {
                    // لا شيء: أسوأ حالة نعود للسلوك الافتراضي.
                }
            }
        }
        return super.dispatchTouchEvent(ev)
    }

    // ✅ دالة فحص التسجيل النشط
    private fun checkIfRecording(): Boolean {
        try {
            if (audioManager == null) {
                audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            }
            
            val audioMode = audioManager?.mode
            if (audioMode == AudioManager.MODE_IN_COMMUNICATION || 
                audioMode == AudioManager.MODE_IN_CALL) {
                return true
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val activeRecordings = audioManager?.activeRecordingConfigurations
                if (!activeRecordings.isNullOrEmpty()) {
                    return true
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }

    // =====================================================================
    // 🔬 كشف المحاكي بنظام نقاط حتمي (Deterministic scoring)
    // كل إشارة لها وزن، والمجموع >= 3 (ثابت في Dart) = محاكي.
    //  - وزن 3 : دليل قاطع لوحده (qemu / ملفات محاكيات / حساس افتراضي / GPU برمجي ...)
    //  - وزن 2 : إشارة قوية لكن مش كافية لوحدها (x86 / ARM-translation / GPU كمبيوتر)
    //  - وزن 1 : إشارة ضعيفة تكمّل غيرها
    // مفيش أي إشارة معتمدة على توقيت أو انتظار events، فنفس الجهاز بيدي
    // نفس النتيجة كل مرة.
    // =====================================================================
    private fun sysProp(key: String): String = try {
        val c = Class.forName("android.os.SystemProperties")
        (c.getMethod("get", String::class.java).invoke(null, key) as? String) ?: ""
    } catch (e: Throwable) { "" }

    private fun fileContains(path: String, needles: List<String>): Boolean = try {
        val f = File(path)
        if (!f.exists() || !f.canRead()) false
        else {
            val text = f.readText().lowercase()
            needles.any { text.contains(it) }
        }
    } catch (e: Throwable) { false }

    // قراءة GL_RENDERER من EGL context مؤقت (على thread خلفي).
    // مهم: لا نستدعي eglTerminate أبداً لأن الـ display مشترك مع Flutter.
    private fun readGlRenderer(): String {
        var display: android.opengl.EGLDisplay? = null
        var ctx: android.opengl.EGLContext? = null
        var surf: android.opengl.EGLSurface? = null
        try {
            display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            if (display == null || display == EGL14.EGL_NO_DISPLAY) return ""
            val ver = IntArray(2)
            if (!EGL14.eglInitialize(display, ver, 0, ver, 1)) return ""
            val cfgAttrs = intArrayOf(
                EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
                EGL14.EGL_NONE
            )
            val configs = arrayOfNulls<android.opengl.EGLConfig>(1)
            val num = IntArray(1)
            if (!EGL14.eglChooseConfig(display, cfgAttrs, 0, configs, 0, 1, num, 0) || num[0] <= 0) return ""
            val ctxAttrs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
            ctx = EGL14.eglCreateContext(display, configs[0], EGL14.EGL_NO_CONTEXT, ctxAttrs, 0)
            val surfAttrs = intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE)
            surf = EGL14.eglCreatePbufferSurface(display, configs[0], surfAttrs, 0)
            if (!EGL14.eglMakeCurrent(display, surf, surf, ctx)) return ""
            val renderer = GLES20.glGetString(GLES20.GL_RENDERER) ?: ""
            val vendor = GLES20.glGetString(GLES20.GL_VENDOR) ?: ""
            return "$renderer | $vendor"
        } catch (e: Throwable) {
            return ""
        } finally {
            try {
                if (display != null && display != EGL14.EGL_NO_DISPLAY) {
                    EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
                    if (surf != null) EGL14.eglDestroySurface(display, surf)
                    if (ctx != null) EGL14.eglDestroyContext(display, ctx)
                }
            } catch (e: Throwable) { /* ignore */ }
        }
    }

    private fun getEmulatorSignals(): Map<String, Any> {
        val signals = ArrayList<String>()
        var score = 0
        fun add(name: String, weight: Int) {
            signals.add("$name(+$weight)")
            score += weight
        }

        // ChromeOS (ARC) أجهزة حقيقية بمعالج x86 وبترجمة ARM — نستثنيها من إشارات x86/GPU
        val isArc = try {
            packageManager.hasSystemFeature("org.chromium.arc") ||
                packageManager.hasSystemFeature("org.chromium.arc.device_management")
        } catch (e: Throwable) { false }

        // ---- (3) بيانات الـ Build ----
        val fp = (Build.FINGERPRINT ?: "").lowercase()
        val hw = (Build.HARDWARE ?: "").lowercase()
        val prod = (Build.PRODUCT ?: "").lowercase()
        val model = (Build.MODEL ?: "").lowercase()
        val manu = (Build.MANUFACTURER ?: "").lowercase()
        val brand = (Build.BRAND ?: "").lowercase()
        val device = (Build.DEVICE ?: "").lowercase()
        val vendorNames = listOf("genymotion", "bluestacks", "droid4x", "ldplayer", "memu")
        val buildHit =
            fp.startsWith("generic") || fp.contains("vbox") || fp.contains("emulator") ||
            hw.contains("goldfish") || hw.contains("ranchu") || hw.contains("vbox") ||
            prod.contains("sdk_gphone") || prod.contains("google_sdk") ||
            prod.contains("emulator") || prod.contains("vbox") ||
            model.contains("sdk_gphone") || model.contains("emulator") ||
            model.contains("android sdk built for") ||
            device.startsWith("generic") ||
            vendorNames.any { manu.contains(it) || brand.contains(it) || model.contains(it) }
        if (buildHit) add("build_props", 3)

        // ---- (3) qemu system properties ----
        val bootHw = sysProp("ro.boot.hardware").lowercase()
        if (sysProp("ro.kernel.qemu") == "1" || sysProp("ro.boot.qemu") == "1" ||
            bootHw.contains("goldfish") || bootHw.contains("ranchu")) {
            add("qemu_props", 3)
        }

        // ---- (3) ملفات/devices خاصة بالمحاكيات (قائمة best-effort) ----
        val emuFiles = listOf(
            "/dev/socket/qemud", "/dev/qemu_pipe", "/dev/goldfish_pipe",
            "/sys/qemu_trace", "/system/bin/qemu-props",
            "/dev/socket/genyd", "/dev/socket/baseband_genyd",
            "/dev/vboxguest", "/dev/vboxuser", "/system/lib/vboxguest.ko",
            "/ueventd.android_x86.rc", "/x86.prop", "/ueventd.ttVM_x86.rc",
            "/init.ttVM_x86.rc", "/fstab.ttVM_x86", "/fstab.vbox86",
            "/init.vbox86.rc", "/ueventd.vbox86.rc",
            "/fstab.andy", "/ueventd.andy.rc",
            "/fstab.nox", "/init.nox.rc", "/ueventd.nox.rc",
            "/BigNoxGameHD", "/YSLauncher",
            "/data/.bluestacks.prop", "/mnt/windows/BstSharedFolder"
        )
        val foundEmuFiles = emuFiles.filter {
            try { File(it).exists() } catch (e: Throwable) { false }
        }
        if (foundEmuFiles.isNotEmpty()) add("emu_files[" + foundEmuFiles.joinToString(",") + "]", 3)

        if (fileContains("/proc/tty/drivers", listOf("goldfish")) ||
            fileContains("/proc/cpuinfo", listOf("goldfish", "ranchu"))) {
            add("proc_goldfish", 3)
        }

        // ---- الحساسات (حتمي: بنسأل SensorManager، مش بننتظر events) ----
        try {
            val sm = getSystemService(Context.SENSOR_SERVICE) as SensorManager
            var acc = sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
            // بعض الأجهزة الحقيقية بترجّع null من getDefaultSensor رغم وجود الحساس
            // (أو بيكون موجود كنسخة wake-up/uncalibrated فقط) — فنسأل بطرق تانية.
            if (acc == null) {
                acc = sm.getSensorList(Sensor.TYPE_ACCELEROMETER).firstOrNull()
            }
            val allSensors = try { sm.getSensorList(Sensor.TYPE_ALL) } catch (e: Throwable) { emptyList<Sensor>() }
            val hasAccFeature = try {
                packageManager.hasSystemFeature(PackageManager.FEATURE_SENSOR_ACCELEROMETER)
            } catch (e: Throwable) { false }
            signals.add("sensors_total=" + allSensors.size + ",acc_feature=" + hasAccFeature)
            if (acc == null) {
                when {
                    // مفيش ولا حساس خالص = نمط محاكي حقيقي
                    allSensors.isEmpty() -> add("no_sensors_at_all", 3)
                    // النظام نفسه معلن إن الجهاز فيه accelerometer → مش محاكي
                    hasAccFeature -> signals.add("acc_missing_but_feature_declared(+0)")
                    // غياب لوحده ضعيف: جهاز اقتصادي ممكن ناقصه الحساس
                    else -> add("no_accelerometer", 1)
                }
            } else {
                val sn = ((acc.name ?: "") + " " + (acc.vendor ?: "")).lowercase()
                if (listOf("goldfish", "ranchu", "genymotion", "bluestacks", "vbox", "emulator").any { sn.contains(it) }) {
                    add("virtual_accelerometer", 3)
                } else if (sn.contains("android open source project")) {
                    add("aosp_accelerometer_vendor", 1)
                }
            }
        } catch (e: Throwable) { /* لا إشارة */ }

        // ---- (2) معمارية x86 / ترجمة ARM ----
        if (!isArc) {
            val abis = Build.SUPPORTED_ABIS ?: emptyArray<String>()
            if (abis.any { it.startsWith("x86") }) add("x86_abi", 2)
            val translation = listOf(
                "/system/lib/libhoudini.so", "/system/lib64/libhoudini.so",
                "/system/lib/libndk_translation.so", "/system/lib64/libndk_translation.so"
            )
            if (translation.any { try { File(it).exists() } catch (e: Throwable) { false } }) {
                add("arm_translation_lib", 2)
            }
        }

        // ---- كارت الشاشة (GL_RENDERER) ----
        val gl = readGlRenderer()
        val glLower = gl.lowercase()
        if (glLower.isNotEmpty()) {
            val softwareGl = listOf("android emulator", "swiftshader", "llvmpipe",
                "virtualbox", "vmware", "gdi generic")
            val pcGpu = listOf("geforce", "radeon", "intel(r)", "intel hd", "intel uhd",
                "intel iris", "amd ")
            // استثناء ضيق: Samsung Exynos بكارت Xclipse (معمارية AMD RDNA) —
            // لازم الشروط التلاتة مع بعض: الاسم فيه xclipse + المصنّع samsung + مفيش x86.
            // فحص الكروت البرمجية (software_gpu) بيتقيّم قبله ومش بيتأثر.
            val hasX86Abi = (Build.SUPPORTED_ABIS ?: emptyArray<String>()).any { it.startsWith("x86") }
            val samsungXclipse = glLower.contains("xclipse") && manu.contains("samsung") && !hasX86Abi
            if (softwareGl.any { glLower.contains(it) }) {
                add("software_gpu", 3)
            } else if (!isArc && !glLower.contains("tegra") &&
                (pcGpu.any { glLower.contains(it) } || glLower.contains("nvidia"))) {
                if (samsungXclipse) {
                    signals.add("pc_gpu_exempt_samsung_xclipse(+0)")
                } else {
                    add("pc_gpu", 2)
                }
            }
        }

        // ---- البطارية (قراءة native فورية بدون انتظار) ----
        try {
            val b = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            if (b != null) {
                val present = b.getBooleanExtra(BatteryManager.EXTRA_PRESENT, true)
                val voltage = b.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1)
                val temp = b.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1)
                // 5000mV و25.0°C = القيم الافتراضية لبطارية الـ AVD (Li-ion الحقيقية أقصاها ~4.45V)
                if (voltage == 5000 && temp == 250) add("avd_battery_signature", 2)
                if (!present) add("no_battery_present", 1)
            }
        } catch (e: Throwable) { /* لا إشارة */ }

        if (Runtime.getRuntime().availableProcessors() < 2) add("cpu_cores_lt2", 1)

        val d = HashMap<String, Any>()
        d["score"] = score
        d["signals"] = if (signals.isEmpty()) "none" else signals.joinToString(" | ")
        d["is_arc"] = isArc
        d["gl_renderer"] = gl
        d["abis"] = (Build.SUPPORTED_ABIS ?: emptyArray<String>()).joinToString(",")
        return d
    }

    // ✅ تشخيص تفصيلي لكل فحص native على حدة + بيانات الجهاز (Build).
    // يُرجع Map<String, Any> فيها نتيجة كل فحص وسبب فشله بالظبط، بحيث
    // نسجلها في Crashlytics ونعرف أي اختبار فشل ولماذا.
    private fun getSecurityDiagnostics(): Map<String, Any> {
        val d = HashMap<String, Any>()

        // 1. مسارات ملفات الروت المعروفة
        val rootPaths = arrayOf(
            "/system/app/Superuser.apk", "/system/app/SuperSU.apk", "/sbin/su",
            "/system/bin/su", "/system/xbin/su", "/data/local/su",
            "/data/local/bin/su", "/data/local/xbin/su", "/system/sd/xbin/su",
            "/system/bin/failsafe/su", "/dev/com.koushikdutta.superuser.daemon/"
        )
        val foundPaths = rootPaths.filter {
            try { File(it).exists() } catch (e: Exception) { false }
        }
        d["su_paths_found"] = if (foundPaths.isEmpty()) "none" else foundPaths.joinToString(",")

        // 2. الكتابة على /system
        d["system_writable"] = try {
            val f = File("/system/medaad_rw_test")
            val created = f.createNewFile()
            if (created) f.delete()
            created
        } catch (e: Exception) { false }

        // 3. Build tags
        d["build_tags"] = Build.TAGS ?: "null"
        d["test_keys"] = (Build.TAGS ?: "").contains("test-keys")

        // 4. عدد الأنوية
        val cores = Runtime.getRuntime().availableProcessors()
        d["cpu_cores"] = cores
        d["cpu_cores_too_low"] = cores < 2

        // 5. مؤشرات المحاكي من Build (للتشخيص فقط)
        d["build_fingerprint"] = Build.FINGERPRINT ?: "null"
        d["build_model"] = Build.MODEL ?: "null"
        d["build_manufacturer"] = Build.MANUFACTURER ?: "null"
        d["build_brand"] = Build.BRAND ?: "null"
        d["build_device"] = Build.DEVICE ?: "null"
        d["build_product"] = Build.PRODUCT ?: "null"
        d["build_hardware"] = Build.HARDWARE ?: "null"
        d["build_board"] = Build.BOARD ?: "null"
        d["sdk_int"] = Build.VERSION.SDK_INT

        val fp = (Build.FINGERPRINT ?: "").lowercase()
        val hw = (Build.HARDWARE ?: "").lowercase()
        val prod = (Build.PRODUCT ?: "").lowercase()
        d["emu_hint_fingerprint"] = fp.startsWith("generic") || fp.contains("emulator") || fp.contains("vbox")
        d["emu_hint_hardware"] = hw.contains("goldfish") || hw.contains("ranchu") || hw.contains("vbox")
        d["emu_hint_product"] = prod.contains("sdk") || prod.contains("emulator") || prod.contains("vbox")

        // 6. خيارات المطور / ADB (قراءة مباشرة من إعدادات النظام)
        try {
            d["dev_options_enabled"] = android.provider.Settings.Global.getInt(
                contentResolver, android.provider.Settings.Global.DEVELOPMENT_SETTINGS_ENABLED, 0) == 1
        } catch (e: Exception) { d["dev_options_enabled"] = "error:" + e.javaClass.simpleName }
        try {
            d["adb_enabled"] = android.provider.Settings.Global.getInt(
                contentResolver, android.provider.Settings.Global.ADB_ENABLED, 0) == 1
        } catch (e: Exception) { d["adb_enabled"] = "error:" + e.javaClass.simpleName }

        return d
    }

    private fun getRecordingDiagnostics(): Map<String, Any> {
        val d = HashMap<String, Any>()
        try {
            if (audioManager == null) {
                audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            }
            val mode = audioManager?.mode ?: -1
            d["audio_mode"] = mode
            d["audio_mode_name"] = when (mode) {
                AudioManager.MODE_NORMAL -> "MODE_NORMAL"
                AudioManager.MODE_RINGTONE -> "MODE_RINGTONE"
                AudioManager.MODE_IN_CALL -> "MODE_IN_CALL"
                AudioManager.MODE_IN_COMMUNICATION -> "MODE_IN_COMMUNICATION"
                else -> "OTHER($mode)"
            }
            d["trigger_audio_mode"] = (mode == AudioManager.MODE_IN_CALL ||
                    mode == AudioManager.MODE_IN_COMMUNICATION)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val configs = audioManager?.activeRecordingConfigurations ?: emptyList<AudioRecordingConfiguration>()
                d["active_recording_configs"] = configs.size
                d["recording_sources"] = configs.joinToString(",") { c ->
                    try { "src=" + c.clientAudioSource + "/session=" + c.clientAudioSessionId } catch (e: Exception) { "?" }
                }
                d["trigger_active_recording"] = configs.isNotEmpty()
            }
        } catch (e: Exception) {
            d["error"] = e.javaClass.simpleName + ": " + (e.message ?: "")
        }
        return d
    }

    // [FIX F-04] Multi-vector native root detection.
    // Supplements the safe_device Flutter package (which relies only on user-space
    // heuristics easily bypassed by Magisk Hide / Shamiko / LSPosed).
    // This performs independent checks at the native layer:
    //   1. Known su binary paths (standard + common Magisk locations)
    //   2. Attempt to write to /system (only possible on rooted devices)
    //   3. CPU core count sanity (emulator heuristic)
    //   4. Build tag check (production builds are always "release-keys")
    private fun isDeviceRooted(): Boolean {
        // 1. Known root binary / app paths
        val rootPaths = arrayOf(
            "/system/app/Superuser.apk",
            "/system/app/SuperSU.apk",
            "/sbin/su",
            "/system/bin/su",
            "/system/xbin/su",
            "/data/local/su",
            "/data/local/bin/su",
            "/data/local/xbin/su",
            "/system/sd/xbin/su",
            "/system/bin/failsafe/su",
            "/dev/com.koushikdutta.superuser.daemon/"
        )
        if (rootPaths.any { File(it).exists() }) return true

        // 2. Attempt to write to /system (succeeds only on rooted devices)
        val canWriteSystem = try {
            val testFile = File("/system/medaad_rw_test")
            val created = testFile.createNewFile()
            if (created) testFile.delete()
            created
        } catch (e: Exception) {
            false
        }
        if (canWriteSystem) return true

        // 3. Emulator / build property check (defence in depth alongside safe_device)
        val buildTags = Build.TAGS
        if (buildTags != null && buildTags.contains("test-keys")) return true

        // 4. CPU core count — real devices always have ≥ 2 cores
        val cores = Runtime.getRuntime().availableProcessors()
        if (cores < 2) return true

        return false
    }

    private fun startRecordingMonitoring() {
        handler = Handler(Looper.getMainLooper())
        recordingCheckRunnable = object : Runnable {
            override fun run() {
                if (checkIfRecording()) {
                    flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                        MethodChannel(messenger, CHANNEL).invokeMethod("onRecordingDetected", true)
                    }
                }
                handler?.postDelayed(this, 2000)
            }
        }
        handler?.post(recordingCheckRunnable!!)
    }

    override fun onResume() {
        super.onResume()
        // ✅ Re-apply FLAG_SECURE on every resume so it is never left stripped
        // after returning from a child route (e.g. NativeVideoPlayerScreen) that
        // may have called FlutterWindowManagerPlus.clearFlags before popping.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            audioManager?.allowedCapturePolicy = 3
        }
    }

    override fun onDestroy() {
        if (handler != null && recordingCheckRunnable != null) {
            handler?.removeCallbacks(recordingCheckRunnable!!)
        }

        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancelAll()
        } catch (e: Exception) {
            // ignore
        }
        
        super.onDestroy()
    }
}
