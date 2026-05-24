import 'dart:async';
import 'package:Medaad/core/services/audio_protection_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safe_device/safe_device.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:sensors_plus/sensors_plus.dart';

// =========================================================
// 🛡️ كلاس إدارة الحماية (Security Manager) - النسخة المحدثة
// =========================================================

class SecurityManager {
  static final SecurityManager instance = SecurityManager._internal();
  SecurityManager._internal();

  // [FIX F-04 / F-14] Native root detection MethodChannel (implemented in MainActivity.kt)
  // ملاحظة: تأكد أن اسم القناة هنا يطابق الموجود في ملف MainActivity.kt
  static const _nativeChannel = MethodChannel('medaad.app.com/audio_protection');

  final ValueNotifier<String?> securityBreachReason = ValueNotifier(null);

  final AudioProtectionService _audioProtection = AudioProtectionService();

  void initListeners() {
    _audioProtection.startMonitoring();

    _audioProtection.recordingStateStream.listen((isRecording) {
      if (isRecording) {
        _triggerBreach("تم اكتشاف تسجيل للشاشة أو الصوت!");
      }
    });

    ScreenProtector.addListener(() {
      // Screenshot callback
    }, (isCapturing) {
      if (isCapturing) _triggerBreach("تم اكتشاف تصوير للشاشة!");
    });
  }

  // [FIX F-14] Enhanced emulator detection using hardware-based signals:
  //   - Battery presence (real devices always have a battery)
  //   - Accelerometer availability (emulators often lack real sensors)
  //   - Native root check via MainActivity (F-04 fix)
  // These supplement SafeDevice's build-prop checks which Genymotion / Magisk
  // can spoof by modifying ro.product.model and ro.kernel.qemu.
  Future<bool> _isHardwareRealDevice() async {
    // 1. Native root / build-tag check (MainActivity.kt)
    try {
      final bool nativeRooted = await _nativeChannel.invokeMethod('isDeviceRooted') ?? false;
      if (nativeRooted) return false;
    } catch (_) {}

    // 2. Battery presence — emulators return BatteryState.unknown or unavailable
    try {
      final battery = Battery();
      final level = await battery.batteryLevel;
      if (level <= 0) return false; // emulator typically returns 0 or -1
    } catch (_) {
      return false; // inability to read battery = emulator
    }

    // 3. Accelerometer availability — emulators usually have no real gyro data
    bool sensorPresent = false;
    try {
      final sub = accelerometerEventStream(samplingPeriod: SensorInterval.normalInterval)
          .timeout(const Duration(milliseconds: 500))
          .listen((_) { sensorPresent = true; });
      await Future.delayed(const Duration(milliseconds: 600));
      await sub.cancel();
    } catch (_) {}

    if (!sensorPresent) return false;

    return true;
  }

  Future<bool> checkSecurity() async {
    if (securityBreachReason.value != null) return false;

    try {
      bool isJailBroken = await SafeDevice.isJailBroken;
      bool isDevMode = await SafeDevice.isDevelopmentModeEnable;
      bool isRealDeviceSafe = await SafeDevice.isRealDevice;

      // [FIX F-14] Use combined hardware + software check
      bool isRealDeviceHardware = await _isHardwareRealDevice();

      if (!isRealDeviceSafe || !isRealDeviceHardware) {
        _triggerBreach("غير مسموح بتشغيل التطبيق على المحاكي (Emulator)");
        return false;
      }

      if (isJailBroken) {
        _triggerBreach("عفواً، الجهاز مكسور الحماية (Root / Jailbreak)");
        return false;
      }

      if (isDevMode) {
        _triggerBreach("خيارات المطور مفعلة (Developer Options)");
        return false;
      }
    } catch (e) {
      debugPrint("Security Check Error: $e");
    }
    return true;
  }

  void startPeriodicCheck() {
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      await checkSecurity();
    });
  }

  void _triggerBreach(String reason) {
    debugPrint("🚨 SECURITY BREACH: $reason");

    WidgetsBinding.instance.addPostFrameCallback((_) {
      securityBreachReason.value = reason;
    });

    _audioProtection.blockAudioCapture();
    HapticFeedback.heavyImpact();
  }

  Future<bool> forceReCheck() async {
    bool isRecording = await _audioProtection.checkRecordingStatus();
    bool isDevMode = await SafeDevice.isDevelopmentModeEnable;
    bool isJailBroken = await SafeDevice.isJailBroken;
    bool isRealDeviceSafe = await SafeDevice.isRealDevice;
    bool isRealDeviceHardware = await _isHardwareRealDevice();

    if (!isRecording && !isDevMode && !isJailBroken && isRealDeviceSafe && isRealDeviceHardware) {
      securityBreachReason.value = null;
      return true;
    } else {
      if (isRecording) {
        securityBreachReason.value = "لا يزال تسجيل الشاشة قيد العمل!";
      } else if (!isRealDeviceSafe || !isRealDeviceHardware) {
        securityBreachReason.value = "لا يمكنك استخدام المحاكي، استخدم هاتف حقيقي!";
      } else if (isDevMode) {
        securityBreachReason.value = "خيارات المطور لا تزال مفعلة!";
      } else if (isJailBroken) {
        securityBreachReason.value = "الجهاز لا يزال مكسور الحماية!";
      } else {
        securityBreachReason.value = "تم اكتشاف خرق أمني!";
      }
      return false;
    }
  }
}
