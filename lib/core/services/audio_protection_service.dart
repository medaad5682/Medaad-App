import 'package:flutter/services.dart';
import 'dart:async';

// ✅ إضافة دالة آمنة للطباعة تظهر فقط في وضع التطوير (Debug) 
// ويتم إزالتها تلقائياً في نسخة الإنتاج (Release) لمنع تسريب السجلات
void _safePrint(Object? message) {
  assert(() {
    print(message);
    return true;
  }());
}

class AudioProtectionService {
  static const platform = MethodChannel('medaad.app.com/audio_protection');
  // Singleton Pattern
  static final AudioProtectionService _instance =
      AudioProtectionService._internal();
  factory AudioProtectionService() => _instance;
  AudioProtectionService._internal();

  // Stream للاستماع لحالة التسجيل
  final StreamController<bool> _recordingStateController =
      StreamController.broadcast();
  Stream<bool> get recordingStateStream => _recordingStateController.stream;

  Timer? _monitoringTimer;
  bool _isRecording = false;

  /// بدء المراقبة المستمرة
  Future<void> startMonitoring() async {
    // TEMP-AD-RECORDING: disabled so ad videos can be recorded. Restore to re-enable.
    // // استقبال إشارات من Native
    // platform.setMethodCallHandler((call) async {
    //   if (call.method == 'onRecordingDetected') {
    //     _handleRecordingDetected();
    //   }
    // });

    // // فحص دوري إضافي من جانب Flutter
    // // ✅ إلغاء أي مؤقّت قديم أولاً: الخدمة Singleton وكل مشغّل يستدعي
    // // startMonitoring() عند فتحه، فكان كل فتح جديد يضيف Timer إضافي
    // // (تراكم مؤقتات) بدل استبدال القديم.
    // _monitoringTimer?.cancel();
    // _monitoringTimer =
    //     Timer.periodic(const Duration(seconds: 3), (timer) async {
    //   await checkRecordingStatus();
    // });
  }

  /// فحص حالة التسجيل
  Future<bool> checkRecordingStatus() async {
    // TEMP-AD-RECORDING: disabled so ad videos can be recorded. Restore to re-enable.
    // try {
    //   final bool isRecording =
    //       await platform.invokeMethod('checkRecording') ?? false;

    //   if (isRecording && !_isRecording) {
    //     _handleRecordingDetected();
    //   } else if (!isRecording && _isRecording) {
    //     _isRecording = false;
    //     _recordingStateController.add(false);
    //   }

    //   return isRecording;
    // } catch (e) {
    //   _safePrint('⚠️ خطأ في فحص التسجيل: $e'); // ✅ استخدام الطباعة الآمنة
    //   return false;
    // }
    return false;
  }

  /// معالجة اكتشاف التسجيل
  void _handleRecordingDetected() {
    _isRecording = true;
    _recordingStateController.add(true);
  }

  /// حظر التقاط الصوت (Android 10+)
  Future<bool> blockAudioCapture() async {
    // TEMP-AD-RECORDING: disabled so ad videos can be recorded. Restore to re-enable.
    // try {
    //   final bool result =
    //       await platform.invokeMethod('blockAudioCapture') ?? false;
    //   return result;
    // } catch (e) {
    //   _safePrint('⚠️ خطأ في حظر الصوت: $e'); // ✅ استخدام الطباعة الآمنة
    //   return false;
    // }
    return false;
  }

  /// إيقاف المراقبة
  void stopMonitoring() {
    _monitoringTimer?.cancel();
  }

  /// Dispose
  void dispose() {
    stopMonitoring();
    _recordingStateController.close();
  }
}
