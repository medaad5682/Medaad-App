package medaad.app.com

import android.os.Bundle
import android.app.NotificationManager
import android.content.Context
import android.media.AudioManager
import android.media.AudioRecordingConfiguration
import android.os.Build
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 🚫 منع تسجيل الفيديو وأخذ لقطات الشاشة (FLAG_SECURE) — معطّل
        // window.setFlags(
        //     WindowManager.LayoutParams.FLAG_SECURE,
        //     WindowManager.LayoutParams.FLAG_SECURE
        // )

        // ✅ 2. منع تسجيل الصوت الداخلي (Internal Audio) - Android 10+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                audioManager?.allowedCapturePolicy = 3 // ALLOW_CAPTURE_BY_NONE
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        // 🚫 حلقة المراقبة المستمرة لتطبيقات التسجيل — معطّلة
        // startRecordingMonitoring()
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
                else -> result.notImplemented()
            }
        }
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
        // 🚫 Re-apply of FLAG_SECURE on resume — disabled.
        // window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
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
