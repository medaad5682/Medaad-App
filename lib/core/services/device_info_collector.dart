import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 📱 يجمع تفاصيل الجهاز (الشركة المصنعة، الموديل، رقم البناء، نسخة النظام ...)
/// لإرسالها مع طلب تسجيل الدخول وحفظها في السيرفر (devices.device_info).
///
/// ⚠️ لا يرمي استثناءات أبداً: أي فشل يرجع Map أصغر بدل ما يمنع تسجيل الدخول.
class DeviceInfoCollector {
  DeviceInfoCollector._();

  static Future<Map<String, dynamic>> collect() async {
    final Map<String, dynamic> info = {};

    try {
      if (Platform.isAndroid) {
        info.addAll(await _android());
      } else if (Platform.isIOS) {
        info.addAll(await _ios());
      } else {
        info['platform'] = Platform.operatingSystem;
      }
    } catch (e) {
      debugPrint('DeviceInfoCollector (device): $e');
      info['platform'] ??= Platform.isIOS ? 'ios' : (Platform.isAndroid ? 'android' : Platform.operatingSystem);
    }

    // الشاشة واللغة والمنطقة الزمنية
    try {
      final dispatcher = WidgetsBinding.instance.platformDispatcher;
      if (dispatcher.views.isNotEmpty) {
        final view = dispatcher.views.first;
        info['screen'] = {
          'width_px': view.physicalSize.width.round(),
          'height_px': view.physicalSize.height.round(),
          'pixel_ratio': double.parse(view.devicePixelRatio.toStringAsFixed(2)),
        };
      }
      info['locale'] = dispatcher.locale.toLanguageTag();
      final now = DateTime.now();
      info['timezone'] = now.timeZoneName;
      info['timezone_offset_minutes'] = now.timeZoneOffset.inMinutes;
    } catch (e) {
      debugPrint('DeviceInfoCollector (screen): $e');
    }

    // نسخة التطبيق
    try {
      final pkg = await PackageInfo.fromPlatform();
      info['app_version'] = pkg.version;
      info['app_build'] = pkg.buildNumber;
      info['app_package'] = pkg.packageName;
    } catch (e) {
      debugPrint('DeviceInfoCollector (app): $e');
    }

    return info;
  }

  // قراءة آمنة لحقول قد لا تتوفر في كل إصدارات device_info_plus
  static dynamic _safe(dynamic Function() read) {
    try {
      return read();
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> _android() async {
    final a = await DeviceInfoPlugin().androidInfo;
    final dynamic d = a;
    return {
      'platform': 'android',
      'manufacturer': a.manufacturer,
      'brand': a.brand,
      'model': a.model,
      'device': a.device,
      'product': a.product,
      'board': a.board,
      'hardware': a.hardware,
      'host': a.host,
      'type': a.type,
      'tags': a.tags,
      'bootloader': a.bootloader,
      'build_id': a.id, // رقم البناء (Build ID)
      'display': a.display, // سلسلة العرض الكاملة للبناء
      'build_fingerprint': a.fingerprint,
      'os_version': a.version.release,
      'sdk_int': a.version.sdkInt,
      'security_patch': a.version.securityPatch,
      'codename': a.version.codename,
      'incremental': a.version.incremental,
      'abis': a.supportedAbis,
      'is_physical_device': a.isPhysicalDevice,
      // حقول اختيارية (قد لا تتوفر في كل إصدارات المكتبة)
      'ram_mb': _safe(() => d.physicalRamSize),
      'total_disk_mb': _toMb(_safe(() => d.totalDiskSize)),
      'is_low_ram_device': _safe(() => d.isLowRamDevice),
    };
  }

  static Future<Map<String, dynamic>> _ios() async {
    final i = await DeviceInfoPlugin().iosInfo;
    final dynamic d = i;
    return {
      'platform': 'ios',
      'manufacturer': 'Apple',
      'brand': 'Apple',
      'name': i.name,
      'model': i.model,
      'localized_model': i.localizedModel,
      'system_name': i.systemName,
      'os_version': i.systemVersion,
      'machine': i.utsname.machine, // مثال: iPhone14,5
      'kernel_sysname': i.utsname.sysname,
      'kernel_release': i.utsname.release,
      'kernel_version': i.utsname.version,
      'is_physical_device': i.isPhysicalDevice,
      // حقول اختيارية (قد لا تتوفر في كل إصدارات المكتبة)
      'model_name': _safe(() => d.modelName),
      'ram_mb': _safe(() => d.physicalRamSize),
      'total_disk_mb': _toMb(_safe(() => d.totalDiskSize)),
    };
  }

  // بعض إصدارات المكتبة ترجع المساحة بالبايت وبعضها بالميجابايت؛ نوحدها هنا
  static int? _toMb(dynamic v) {
    if (v is! num) return null;
    // قيمة أكبر من 1 مليون تعني غالباً بايت
    return v > 1000000 ? (v / (1024 * 1024)).round() : v.round();
  }
}
