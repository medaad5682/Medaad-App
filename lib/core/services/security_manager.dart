import 'dart:async';
import 'package:Medaad/core/services/audio_protection_service.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:safe_device/safe_device.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:sensors_plus/sensors_plus.dart';

// =========================================================
// 🛡️ كلاس إدارة الحماية (Security Manager)
// + تسجيل تفصيلي لكل سبب في Firebase Crashlytics (Non-fatal)
// =========================================================

/// نوع الخرق الأمني (يُستخدم كـ key وكـ تجميع Issue في Crashlytics)
enum BreachType {
  emulator,
  rootJailbreak,
  developerOptions,
  screenRecording,
  screenshot,
  unknown,
}

/// نتيجة فحص الهاردوير (محاكي / جهاز حقيقي) مع سبب الفشل بالظبط
class _HardwareResult {
  final bool isReal;

  /// اسم الاختبار الذي فشل (native_root / battery / accelerometer) أو null
  final String? failedStep;

  /// تفاصيل ما حدث في الاختبار
  final String? detail;

  /// تفاصيل كل الخطوات (تُسجَّل دائماً حتى لو نجح الفحص)
  final Map<String, String> steps;

  const _HardwareResult(this.isReal, this.failedStep, this.detail, this.steps);
}

class SecurityManager {
  static final SecurityManager instance = SecurityManager._internal();
  SecurityManager._internal();

  // [FIX F-04 / F-14] Native root detection MethodChannel (implemented in MainActivity.kt)
  static const _nativeChannel = MethodChannel('medaad.app.com/audio_protection');

  final ValueNotifier<String?> securityBreachReason = ValueNotifier(null);

  final AudioProtectionService _audioProtection = AudioProtectionService();

  // نتيجة فحص الهاردوير (Cache) لعدم تكراره عند العودة من الخلفية
  bool? _cachedIsHardwareReal;

  void initListeners() {
    _audioProtection.startMonitoring();

    _audioProtection.recordingStateStream.listen((isRecording) {
      if (isRecording) {
        _triggerBreach(
          "تم اكتشاف تسجيل للشاشة أو الصوت!",
          type: BreachType.screenRecording,
          source: 'recording_stream',
        );
      }
    });

    ScreenProtector.addListener(() {
      // Screenshot callback
    }, (isCapturing) {
      if (isCapturing) {
        _triggerBreach(
          "تم اكتشاف تصوير للشاشة!",
          type: BreachType.screenshot,
          source: 'screen_protector_capture_callback',
        );
      }
    });
  }

  // ---------------------------------------------------------
  // 🔬 Native diagnostics helpers
  // ---------------------------------------------------------
  Future<Map<String, String>> _nativeMap(String method) async {
    try {
      final raw = await _nativeChannel.invokeMethod<Map<dynamic, dynamic>>(method);
      if (raw == null) return {};
      return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (e) {
      return {'diag_error': '$method failed: ${e.runtimeType}: $e'};
    }
  }

  // [FIX F-14] Enhanced emulator detection using hardware-based signals.
  // الآن يرجع النتيجة + اسم الاختبار الفاشل + تفاصيله بالظبط.
  Future<_HardwareResult> _hardwareCheck() async {
    final steps = <String, String>{};

    if (_cachedIsHardwareReal == true) {
      return const _HardwareResult(true, null, null, {'cached': 'true'});
    }

    // 1. Native root / build-tag check (MainActivity.kt)
    try {
      final bool nativeRooted =
          await _nativeChannel.invokeMethod('isDeviceRooted') ?? false;
      steps['native_root'] = nativeRooted ? 'ROOTED' : 'ok';
      if (nativeRooted) {
        final diag = await _nativeMap('getSecurityDiagnostics');
        // السبب المحدد داخل الفحص native
        final reasons = <String>[];
        if (diag['su_paths_found'] != null && diag['su_paths_found'] != 'none') {
          reasons.add('su_paths_found=${diag['su_paths_found']}');
        }
        if (diag['system_writable'] == 'true') {
          reasons.add('/system writable');
        }
        if (diag['test_keys'] == 'true') {
          reasons.add('build_tags=${diag['build_tags']} (test-keys)');
        }
        if (diag['cpu_cores_too_low'] == 'true') {
          reasons.add('cpu_cores=${diag['cpu_cores']} (<2)');
        }
        return _HardwareResult(
          false,
          'native_root',
          'فحص native root/build فشل: ${reasons.isEmpty ? 'unknown' : reasons.join(' | ')}',
          steps,
        );
      }
    } catch (e) {
      steps['native_root'] = 'channel_error: ${e.runtimeType}';
    }

    // 2. Battery presence — emulators return 0 / -1 or throw
    try {
      final battery = Battery();
      final level = await battery.batteryLevel;
      steps['battery_level'] = level.toString();
      if (level <= 0) {
        return _HardwareResult(
          false,
          'battery',
          'مستوى البطارية = $level (المحاكي عادة يرجّع 0 أو -1)',
          steps,
        );
      }
    } catch (e) {
      steps['battery_level'] = 'exception: ${e.runtimeType}';
      return _HardwareResult(
        false,
        'battery',
        'تعذّر قراءة البطارية (${e.runtimeType}: $e) → اعتُبر محاكي',
        steps,
      );
    }

    // 3. Accelerometer availability
    bool sensorPresent = false;
    String? sensorError;
    int sensorEvents = 0;
    try {
      final sub = accelerometerEventStream(
              samplingPeriod: SensorInterval.normalInterval)
          .timeout(const Duration(milliseconds: 500))
          .listen(
        (_) {
          sensorPresent = true;
          sensorEvents++;
        },
        onError: (error) {
          sensorPresent = false;
          sensorError = '${error.runtimeType}: $error';
        },
      );
      await Future.delayed(const Duration(milliseconds: 600));
      await sub.cancel();
    } catch (e) {
      sensorError = '${e.runtimeType}: $e';
    }
    steps['accelerometer'] =
        'events=$sensorEvents, error=${sensorError ?? 'none'}';

    if (!sensorPresent) {
      return _HardwareResult(
        false,
        'accelerometer',
        sensorError != null
            ? 'الحساس رمى خطأ: $sensorError'
            : 'لم تصل أي قراءة من الأكسيليرومتر خلال 600ms (لا يوجد حساس حقيقي)',
        steps,
      );
    }

    _cachedIsHardwareReal = true;
    return _HardwareResult(true, null, null, steps);
  }

  // ✅ منع تداخل الفحوصات: أي استدعاء أثناء فحص جارٍ ينتظر نفس النتيجة
  Future<bool>? _inFlightCheck;

  Future<bool> checkSecurity() {
    if (securityBreachReason.value != null) return Future.value(false);
    return _inFlightCheck ??=
        _runCheck().whenComplete(() => _inFlightCheck = null);
  }

  /// يجمع نتائج كل الفحوصات مرة واحدة (بدون short-circuit) عشان نسجل
  /// كل الأسباب الفاشلة وليس أول واحد فقط.
  Future<_ScanResult> _scan() async {
    final isJailBroken = await SafeDevice.isJailBroken;
    final isDevMode = await SafeDevice.isDevelopmentModeEnable;
    final isRealDeviceSafe = await SafeDevice.isRealDevice;
    final hw = await _hardwareCheck();
    return _ScanResult(
      isJailBroken: isJailBroken,
      isDevMode: isDevMode,
      isRealDeviceSafe: isRealDeviceSafe,
      hardware: hw,
    );
  }

  Future<bool> _runCheck() async {
    try {
      final scan = await _scan();

      if (!scan.isRealDeviceSafe || !scan.hardware.isReal) {
        _triggerBreach(
          "غير مسموح بتشغيل التطبيق على المحاكي (Emulator)",
          type: BreachType.emulator,
          source: 'periodic_or_startup_check',
          scan: scan,
        );
        return false;
      }

      if (scan.isJailBroken) {
        _triggerBreach(
          "عفواً، الجهاز مكسور الحماية (Root / Jailbreak)",
          type: BreachType.rootJailbreak,
          source: 'periodic_or_startup_check',
          scan: scan,
        );
        return false;
      }

      if (scan.isDevMode) {
        _triggerBreach(
          "خيارات المطور مفعلة (Developer Options)",
          type: BreachType.developerOptions,
          source: 'periodic_or_startup_check',
          scan: scan,
        );
        return false;
      }
    } catch (e, st) {
      debugPrint("Security Check Error: $e");
      // فشل الفحص نفسه (مش خرق) — نسجله كـ non-fatal للمتابعة
      _safeRecord(
        StateError('SecurityCheck internal error: $e'),
        st,
        reason: 'SecurityCheck internal error',
      );
    }
    return true;
  }

  // ✅ [PERF FIX] الفحص كل 5 دقائق + عند كل عودة من الخلفية
  static const Duration _periodicInterval = Duration(minutes: 5);
  Timer? _periodicTimer;

  void startPeriodicCheck() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(_periodicInterval, (_) {
      final state = WidgetsBinding.instance.lifecycleState;
      if (state != null && state != AppLifecycleState.resumed) return;
      checkSecurity();
    });
  }

  void stopPeriodicCheck() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  void _triggerBreach(
    String reason, {
    required BreachType type,
    required String source,
    _ScanResult? scan,
  }) {
    debugPrint("🚨 SECURITY BREACH: $reason");

    WidgetsBinding.instance.addPostFrameCallback((_) {
      securityBreachReason.value = reason;
    });

    // سجّل السبب التفصيلي في Crashlytics (fire-and-forget، لا يعطّل الشاشة الحمراء)
    unawaited(_reportBreach(
      type: type,
      uiMessage: reason,
      source: source,
      scan: scan,
    ));

    _audioProtection.blockAudioCapture();
    HapticFeedback.heavyImpact();
  }

  // ---------------------------------------------------------
  // 📝 Crashlytics reporting
  // ---------------------------------------------------------

  // لتفادي تكرار نفس البلاغ (مثلاً سباق بين فحصين متزامنين)
  String? _lastReportKey;
  DateTime? _lastReportAt;

  Future<void> _reportBreach({
    required BreachType type,
    required String uiMessage,
    required String source,
    _ScanResult? scan,
  }) async {
    try {
      // dedupe: نفس النوع+المصدر خلال 30 ثانية
      final key = '${type.name}|$source';
      final now = DateTime.now();
      if (_lastReportKey == key &&
          _lastReportAt != null &&
          now.difference(_lastReportAt!) < const Duration(seconds: 30)) {
        return;
      }
      _lastReportKey = key;
      _lastReportAt = now;

      final keys = <String, Object>{
        'sec_breach_type': type.name,
        'sec_ui_message': uiMessage,
        'sec_source': source,
        'sec_lifecycle': '${WidgetsBinding.instance.lifecycleState}',
        'sec_is_release': kReleaseMode,
        'sec_time': now.toIso8601String(),
      };

      final lines = <String>[
        '🚨 SECURITY BREACH [${type.name}] source=$source',
        'رسالة الشاشة الحمراء: $uiMessage',
      ];

      // ===== تفاصيل الفحص (محاكي / روت / خيارات المطور) =====
      if (scan != null) {
        keys['sec_safedevice_isRealDevice'] = scan.isRealDeviceSafe;
        keys['sec_safedevice_isJailBroken'] = scan.isJailBroken;
        keys['sec_safedevice_isDevMode'] = scan.isDevMode;
        keys['sec_hw_isReal'] = scan.hardware.isReal;
        keys['sec_hw_failed_step'] = scan.hardware.failedStep ?? 'none';

        lines.add('SafeDevice.isRealDevice = ${scan.isRealDeviceSafe}'
            '${scan.isRealDeviceSafe ? '' : '  ← فشل: SafeDevice اعتبره محاكي (build props)'}');
        lines.add('SafeDevice.isJailBroken = ${scan.isJailBroken}'
            '${scan.isJailBroken ? '  ← فشل: SafeDevice اكتشف Root/Jailbreak' : ''}');
        lines.add('SafeDevice.isDevelopmentModeEnable = ${scan.isDevMode}'
            '${scan.isDevMode ? '  ← فشل: خيارات المطور مفعلة' : ''}');
        lines.add('فحص الهاردوير: isReal=${scan.hardware.isReal}'
            '${scan.hardware.failedStep != null ? ' | الاختبار الفاشل=${scan.hardware.failedStep} | ${scan.hardware.detail}' : ''}');

        scan.hardware.steps.forEach((k, v) {
          keys['sec_hw_step_$k'] = v;
          lines.add('  hw.$k = $v');
        });

        // أسباب مفصلة لكل نوع
        final failed = <String>[
          if (!scan.isRealDeviceSafe) 'safedevice_isRealDevice',
          if (!scan.hardware.isReal) 'hardware:${scan.hardware.failedStep}',
          if (scan.isJailBroken) 'safedevice_isJailBroken',
          if (scan.isDevMode) 'safedevice_isDevMode',
        ];
        keys['sec_all_failed_checks'] = failed.join(',');
        lines.add('كل الفحوصات الفاشلة: ${failed.join(', ')}');

        // تشخيص native كامل (Build + su paths + dev options + adb)
        final diag = await _nativeMap('getSecurityDiagnostics');
        diag.forEach((k, v) {
          keys['sec_native_$k'] = v;
        });
        lines.add('native diagnostics: $diag');

        // لو المحاكي: وضّح أي مؤشر Build أكد ذلك
        if (type == BreachType.emulator) {
          final hints = <String>[
            if (diag['emu_hint_fingerprint'] == 'true')
              'FINGERPRINT=${diag['build_fingerprint']}',
            if (diag['emu_hint_hardware'] == 'true')
              'HARDWARE=${diag['build_hardware']}',
            if (diag['emu_hint_product'] == 'true')
              'PRODUCT=${diag['build_product']}',
          ];
          keys['sec_emulator_build_hints'] =
              hints.isEmpty ? 'none (قرار من حساسات/بطارية/SafeDevice)' : hints.join(' | ');
          lines.add('مؤشرات المحاكي من Build: ${keys['sec_emulator_build_hints']}');
        }
      }

      // ===== تفاصيل التسجيل / السكرين شوت =====
      if (type == BreachType.screenRecording) {
        final rec = await _nativeMap('getRecordingDiagnostics');
        rec.forEach((k, v) => keys['sec_rec_$k'] = v);
        lines.add('recording diagnostics: $rec');
        lines.add(_explainRecording(rec));
      } else if (type == BreachType.screenshot) {
        lines.add(
            'ScreenProtector capture callback أبلغ بـ isCapturing=true (screenshot/screen-capture)');
      }

      // ===== اكتب في Crashlytics =====
      final c = FirebaseCrashlytics.instance;
      for (final e in keys.entries) {
        final v = e.value;
        final key = e.key;
        if (v is bool) {
          unawaited(c.setCustomKey(key, v));
        } else {
          // Crashlytics يقصّ القيم > 1024 حرف
          final s = v.toString();
          unawaited(c.setCustomKey(key, s.length > 1000 ? s.substring(0, 1000) : s));
        }
      }
      for (final l in lines) {
        unawaited(c.log(l));
      }

      // Stack مخصص لكل نوع => Crashlytics يفصل كل سبب في Issue مستقلة
      final stack = StackTrace.fromString(
          '#0      SecurityBreach.${type.name} (package:Medaad/core/services/security_manager.dart:1:1)\n'
          '#1      SecurityManager._triggerBreach (package:Medaad/core/services/security_manager.dart:1:1)\n');

      await _safeRecord(
        SecurityBreachException(type, uiMessage, lines.join('\n')),
        stack,
        reason: 'SecurityBreach:${type.name} - $uiMessage',
      );
    } catch (e) {
      debugPrint('⚠️ Failed to report security breach: $e');
    }
  }

  String _explainRecording(Map<String, String> rec) {
    final reasons = <String>[];
    if (rec['trigger_audio_mode'] == 'true') {
      reasons.add(
          'وضع الصوت = ${rec['audio_mode_name']} (مكالمة/اتصال نشط يُعتبر تسجيل)');
    }
    if (rec['trigger_active_recording'] == 'true') {
      reasons.add(
          'يوجد ${rec['active_recording_configs']} جلسة تسجيل صوت نشطة (${rec['recording_sources']})');
    }
    if (reasons.isEmpty) {
      return 'سبب التسجيل: وصلت إشارة onRecordingDetected لكن وقت التشخيص لم يعد التسجيل نشطاً';
    }
    return 'سبب التسجيل: ${reasons.join(' + ')}';
  }

  /// تسجيل non-fatal آمن (لا يرمي أبداً حتى لا يسبب كراش أثناء التبليغ)
  Future<void> _safeRecord(Object error, StackTrace? stack,
      {String? reason}) async {
    try {
      await FirebaseCrashlytics.instance
          .recordError(error, stack, reason: reason, fatal: false);
    } catch (e) {
      debugPrint('⚠️ Crashlytics.recordError failed (ignored): $e');
    }
  }

  // ---------------------------------------------------------
  // 🔁 إعادة الفحص (زر "إعادة المحاولة")
  // ---------------------------------------------------------
  Future<bool> forceReCheck() async {
    bool isRecording = await _audioProtection.checkRecordingStatus();
    final scan = await _scan();

    if (!isRecording &&
        !scan.isDevMode &&
        !scan.isJailBroken &&
        scan.isRealDeviceSafe &&
        scan.hardware.isReal) {
      securityBreachReason.value = null;
      return true;
    }

    BreachType type;
    String message;
    if (isRecording) {
      type = BreachType.screenRecording;
      message = "لا يزال تسجيل الشاشة قيد العمل!";
    } else if (!scan.isRealDeviceSafe || !scan.hardware.isReal) {
      type = BreachType.emulator;
      message = "لا يمكنك استخدام المحاكي، استخدم هاتف حقيقي!";
    } else if (scan.isDevMode) {
      type = BreachType.developerOptions;
      message = "خيارات المطور لا تزال مفعلة!";
    } else if (scan.isJailBroken) {
      type = BreachType.rootJailbreak;
      message = "الجهاز لا يزال مكسور الحماية!";
    } else {
      type = BreachType.unknown;
      message = "تم اكتشاف خرق أمني!";
    }

    securityBreachReason.value = message;
    unawaited(_reportBreach(
      type: type,
      uiMessage: message,
      source: 'retry_button_force_recheck',
      scan: scan,
    ));
    return false;
  }
}

class _ScanResult {
  final bool isJailBroken;
  final bool isDevMode;
  final bool isRealDeviceSafe;
  final _HardwareResult hardware;

  const _ScanResult({
    required this.isJailBroken,
    required this.isDevMode,
    required this.isRealDeviceSafe,
    required this.hardware,
  });
}

/// استثناء مخصص يظهر في Crashlytics باسم واضح ومعه كل التفاصيل
class SecurityBreachException implements Exception {
  final BreachType type;
  final String uiMessage;
  final String details;

  SecurityBreachException(this.type, this.uiMessage, this.details);

  @override
  String toString() =>
      'SecurityBreachException(${type.name}): $uiMessage\n$details';
}
