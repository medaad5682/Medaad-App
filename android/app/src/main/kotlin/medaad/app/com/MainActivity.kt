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

class MainActivity: FlutterActivity() {
    // اسم القناة للتواصل مع كود Flutter
    private val CHANNEL = "com.example.edu_vantage_app/audio_protection"
    
    private var audioManager: AudioManager? = null
    private var handler: Handler? = null
    private var recordingCheckRunnable: Runnable? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // ✅ 1. منع تسجيل الفيديو وأخذ لقطات الشاشة (FLAG_SECURE)
        // وضعه في onCreate يضمن تنفيذه فوراً عند بناء النافذة
        /*
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        */

        // ✅ 2. منع تسجيل الصوت الداخلي (Internal Audio) - Android 10+
        /*
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                // الرقم 3 يعني ALLOW_CAPTURE_BY_NONE
                audioManager?.allowedCapturePolicy = 3 
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
        */

        // ✅ 3. بدء حلقة المراقبة المستمرة للتطبيقات الخارجية
       // startRecordingMonitoring()
    }

    // ✅ هذه الدالة ضرورية جداً لكي يعمل كود Dart (AudioProtectionService)
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkRecording" -> {
                    // Flutter يسأل: هل هناك تسجيل الآن؟
                    val isRecording = checkIfRecording()
                    result.success(isRecording)
                }
                "getAudioMode" -> {
                    val mode = audioManager?.mode ?: -1
                    result.success(mode)
                }
                "blockAudioCapture" -> {
                    // طلب إعادة تطبيق الحظر من Flutter
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        audioManager?.allowedCapturePolicy = 3
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // ✅ دالة فحص التسجيل النشط (تستخدمها حلقة المراقبة وكود Flutter)
    private fun checkIfRecording(): Boolean {
        try {
            if (audioManager == null) {
                audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            }
            
            // 1. فحص وضع الصوت (مثل المكالمات)
            val audioMode = audioManager?.mode
            if (audioMode == AudioManager.MODE_IN_COMMUNICATION || 
                audioMode == AudioManager.MODE_IN_CALL) {
                return true
            }

            // 2. فحص تطبيقات التسجيل النشطة (Android 7.0+)
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

    // ✅ تشغيل مراقبة مستمرة في الخلفية كل 2 ثانية
    private fun startRecordingMonitoring() {
        handler = Handler(Looper.getMainLooper())
        recordingCheckRunnable = object : Runnable {
            override fun run() {
                if (checkIfRecording()) {
                    // إرسال تنبيه فوري إلى Flutter لإيقاف الفيديو
                    flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                        MethodChannel(messenger, CHANNEL).invokeMethod("onRecordingDetected", true)
                    }
                }
                handler?.postDelayed(this, 2000) // تكرار الفحص كل 2 ثانية
            }
        }
        handler?.post(recordingCheckRunnable!!)
    }

    override fun onResume() {
        super.onResume()
        // إعادة تطبيق حظر الصوت عند العودة للتطبيق
        /*
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            audioManager?.allowedCapturePolicy = 3
        }
        */
    }

    override fun onDestroy() {
        // إيقاف حلقة المراقبة لتجنب تسريب الذاكرة
        if (handler != null && recordingCheckRunnable != null) {
            handler?.removeCallbacks(recordingCheckRunnable!!)
        }

        // حذف الإشعارات عند الإغلاق
        try {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancelAll()
        } catch (e: Exception) {
            // تجاهل الخطأ
        }
        
        super.onDestroy()
    }
}
