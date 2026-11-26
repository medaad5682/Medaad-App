import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_constants.dart';
import '../services/api_client.dart';

// ============================================================
// 🎨 AppThemeConfig — ألوان التطبيق القابلة للتحكم من لوحة السوبر أدمن
// ============================================================
// ترتيب الأولوية (أي مستوى يفشل ننزل للي تحته، ولا شيء هنا يرمي استثناء):
//   1) ألوان السيرفر (آخر رد ناجح من /api/public/get-app-theme)
//   2) آخر ألوان محفوظة في SharedPreferences (كاش محلي)
//   3) الألوان الافتراضية المدمجة في [defaults] (وضع الطوارئ عند فشل السيرفر)
//
// ⏭️ الألوان الجديدة من السيرفر لا تُطبَّق في الجلسة الحالية أبداً (لا وميض ولا
// إعادة بناء): نحفظها في الكاش فقط، وتظهر عند الفتح التالي للتطبيق.
//
// التحميل السريع (loadFast) بيتم قبل runApp() بنفس نمط initThemeFast():
// SharedPreferences غير مشفّر ولا يمر على بوابة التخزين، فمفيش خطر تجميد.
// ⚠️ [defaults] لازم تطابق DEFAULT_APP_THEME في lib/appThemeHelper.js بالسيرفر.
// ============================================================
class AppThemeConfig {
  AppThemeConfig._();

  // مفاتيح الألوان (نفس مفاتيح السيرفر)
  static const String darkBgPrimary = 'dark_bg_primary';
  static const String darkBgSecondary = 'dark_bg_secondary';
  static const String darkTextPrimary = 'dark_text_primary';
  static const String darkTextSecondary = 'dark_text_secondary';
  static const String darkAccent = 'dark_accent';
  static const String lightBgPrimary = 'light_bg_primary';
  static const String lightBgSecondary = 'light_bg_secondary';
  static const String lightTextPrimary = 'light_text_primary';
  static const String lightTextSecondary = 'light_text_secondary';
  static const String lightAccent = 'light_accent';

  /// 🛟 الألوان الافتراضية المدمجة — تُستخدم دائماً عند غياب ألوان السيرفر/الكاش.
  static const Map<String, int> defaults = {
    darkBgPrimary: 0xFF1A1B1E,
    darkBgSecondary: 0xFF2A2B2F,
    darkTextPrimary: 0xFFE2E8F0,
    darkTextSecondary: 0xFF94A3B8,
    darkAccent: 0xFFDBA91D,
    lightBgPrimary: 0xFFE0E5EC,
    lightBgSecondary: 0xFFF8F9FA,
    lightTextPrimary: 0xFF354F52,
    lightTextSecondary: 0xFF5F7D81,
    lightAccent: 0xFFA85832,
  };

  static const String _kCacheKey = 'cached_app_theme_v1';
  static const Duration _requestTimeout = Duration(seconds: 4);

  // الألوان المخصصة الحالية (فاضية = كله افتراضي)
  static Map<String, int> _overrides = {};
  static bool _checkedThisSession = false;

  /// اللون الفعلي لمفتاح معيّن: المخصص لو موجود وإلا الافتراضي.
  static Color color(String key) =>
      Color(_overrides[key] ?? defaults[key] ?? 0xFF000000);

  // ----------------------------------------------------------
  // 1) تحميل سريع من الكاش المحلي (قبل runApp)
  // ----------------------------------------------------------
  static Future<void> loadFast() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCacheKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _overrides = _parseColors(decoded['colors']);
      }
    } catch (_) {
      // كاش تالف/غير متاح → نكمل بالافتراضي
      _overrides = {};
    }
  }

  // ----------------------------------------------------------
  // 2) جلب من السيرفر وتخزينه للفتحة القادمة (يُستدعى من الـ Splash بدون await)
  //    لا يغيّر ألوان الجلسة الحالية إطلاقاً → لا وميض ولا انتظار.
  //    أي فشل (نت/مهلة/رد غير صالح) → لا شيء يحدث، والتطبيق يكمل بالكاش أو الافتراضي.
  //    بيتنفذ مرة واحدة فقط في الجلسة.
  // ----------------------------------------------------------
  static Future<void> refreshFromServer() async {
    if (_checkedThisSession) return;
    _checkedThisSession = true;
    try {
      final response = await ApiClient.bare
          .get(
            '${ApiConstants.apiUrl}/public/get-app-theme',
            queryParameters: {'t': DateTime.now().millisecondsSinceEpoch},
            options: Options(
              sendTimeout: _requestTimeout,
              receiveTimeout: _requestTimeout,
            ),
          )
          .timeout(_requestTimeout);

      if (response.statusCode != 200) return;

      dynamic data = response.data;
      if (data is String) data = jsonDecode(data);
      if (data is! Map || data['success'] != true) return;

      // colors == null → السيرفر معمول له "إعادة للافتراضي" → نمسح التخصيص من الكاش
      final fresh = _parseColors(data['colors']);

      // _overrides = الألوان المستخدمة الآن (= الكاش وقت الإقلاع). لو متطابقة مفيش داعي للكتابة.
      if (mapEquals(fresh, _overrides)) return;

      await _persist(fresh, data['version']); // ⏭️ تُطبَّق عند الإقلاع التالي (loadFast)
    } catch (e) {
      if (kDebugMode) debugPrint('🎨 AppThemeConfig: server unreachable, keeping current colors ($e)');
    }
  }

  // ----------------------------------------------------------
  // أدوات داخلية
  // ----------------------------------------------------------
  /// يقبل فقط '#RRGGBB' وكل لون غير صالح يتجاهل (فيرجع لافتراضيه).
  static Map<String, int> _parseColors(dynamic raw) {
    final out = <String, int>{};
    if (raw is! Map) return out;
    for (final key in defaults.keys) {
      final v = raw[key];
      if (v is! String) continue;
      final m = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(v.trim());
      if (m == null) continue;
      out[key] = 0xFF000000 | int.parse(m.group(1)!, radix: 16);
    }
    return out;
  }

  static Future<void> _persist(Map<String, int> colors, dynamic version) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (colors.isEmpty) {
        await prefs.remove(_kCacheKey);
        return;
      }
      await prefs.setString(
        _kCacheKey,
        jsonEncode({
          'version': version is num ? version.toInt() : 0,
          'colors': colors.map(
            (k, v) => MapEntry(
              k,
              '#${(v & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
            ),
          ),
        }),
      );
    } catch (_) {
      // فشل الحفظ → الفتحة القادمة تكمل بالكاش القديم/الافتراضي
    }
  }
}
