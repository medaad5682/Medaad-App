// ✅ نموذج إعدادات المشغلات الديناميكي
// -----------------------------------------------------------------------
// يطابق الشكل الجديد القادم من الباك إند: { "players": [...], "downloads": {...} }
// بدلاً من 3 خانات ثابتة (player_1/player_2/player_3)، أصبح عدد المشغلات
// غير محدود ويُتحكم به بالكامل من لوحة تحكم الأدمن.
//
// كل مشغل يحمل حقل "engine" الذي يحدد منطق الجلب/التشغيل الذي يجب أن
// يستخدمه التطبيق. القيم المدعومة حالياً:
//   - explode_direct : استخراج مباشر لروابط الفيديو (get-stream-proxy)
//   - bunny_hls       : Bunny Stream عبر get-video-id، يُشغَّل بواجهة media_kit
//   - bunny_native     : نفس بيانات Bunny Stream، لكن يُشغَّل بواجهة مشغل
//                         بديلة (video_player/ExoPlayer) بدون media_kit
//   - youtube         : تشغيل عبر مشغل يوتيوب (يتطلب youtube_video_id)
class PlayerEngine {
  static const String explodeDirect = 'explode_direct';
  static const String bunnyHls = 'bunny_hls';
  static const String bunnyNative = 'bunny_native';
  static const String youtube = 'youtube';
}

class PlayerSettings {
  final List<PlayerConfig> players;
  final DownloadSettings downloads;

  PlayerSettings({
    required this.players,
    required this.downloads,
  });

  factory PlayerSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return PlayerSettings.defaultSettings();

    // ✅ الشكل الجديد: مصفوفة players
    if (json['players'] is List) {
      final list = (json['players'] as List)
          .whereType<Map>()
          .map((p) => PlayerConfig.fromJson(Map<String, dynamic>.from(p)))
          .toList();

      if (list.isEmpty) return PlayerSettings.defaultSettings();

      return PlayerSettings(
        players: list,
        downloads: DownloadSettings.fromJson(json['downloads']),
      );
    }

    // ✅ توافق رجعي: شكل قديم (player_1/player_2/player_3 كخصائص ثابتة)
    // في حال وصل التطبيق لنسخة باك إند قديمة لم تُحدَّث بعد.
    final legacyKeys = <String, String>{
      'player_1': PlayerEngine.explodeDirect,
      'player_2': PlayerEngine.bunnyHls,
      'player_3': PlayerEngine.youtube,
    };

    final legacyPlayers = <PlayerConfig>[];
    legacyKeys.forEach((key, engine) {
      if (json[key] is Map) {
        legacyPlayers.add(PlayerConfig.fromJson(
          Map<String, dynamic>.from(json[key]),
          fallbackId: key,
          fallbackEngine: engine,
        ));
      }
    });

    if (legacyPlayers.isEmpty) return PlayerSettings.defaultSettings();

    return PlayerSettings(
      players: legacyPlayers,
      downloads: DownloadSettings.fromJson(json['downloads']),
    );
  }

  static PlayerSettings defaultSettings() {
    return PlayerSettings(
      players: [
        PlayerConfig(
          id: 'player_1',
          engine: PlayerEngine.explodeDirect,
          enabled: true,
          name: "المشغل الأساسي",
          description: "سريع ومستقر",
          order: 1,
        ),
        PlayerConfig(
          id: 'player_2',
          engine: PlayerEngine.bunnyHls,
          enabled: true,
          name: "سيرفر احتياطي",
          description: "استخدمه في حال التقطيع",
          order: 2,
        ),
        PlayerConfig(
          id: 'player_3',
          engine: PlayerEngine.youtube,
          enabled: false,
          name: "مشغل يوتيوب",
          description: "جودة تلقائية",
          order: 3,
        ),
      ],
      downloads: DownloadSettings(videoEnabled: true, pdfEnabled: true),
    );
  }

  // ✅ دالة ذكية لجلب المشغلات المفعلة فقط وترتيبها حسب رقم الـ order.
  // مشغلات الـ engine == youtube تُستبعد تلقائياً إن لم يكن للفيديو رابط يوتيوب.
  List<PlayerConfig> getSortedEnabledPlayers(bool hasYoutubeId) {
    List<PlayerConfig> list = players.where((p) {
      if (!p.enabled) return false;
      if (p.engine == PlayerEngine.youtube && !hasYoutubeId) return false;
      return true;
    }).toList();

    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }
}

class PlayerConfig {
  final String id;
  final String engine;
  final bool enabled;
  final String name;
  final String description;
  final int order;

  PlayerConfig({
    required this.id,
    required this.engine,
    required this.enabled,
    required this.name,
    required this.description,
    required this.order,
  });

  factory PlayerConfig.fromJson(
    Map<String, dynamic>? json, {
    String? fallbackId,
    String? fallbackEngine,
  }) {
    final rawEngine = json?['engine']?.toString() ?? fallbackEngine ?? PlayerEngine.bunnyHls;

    // حماية: أي engine غير معروف يُعامل كـ bunny_hls (الأكثر أماناً/شيوعاً)
    const validEngines = [
      PlayerEngine.explodeDirect,
      PlayerEngine.bunnyHls,
      PlayerEngine.bunnyNative,
      PlayerEngine.youtube,
    ];
    final engine = validEngines.contains(rawEngine) ? rawEngine : PlayerEngine.bunnyHls;

    return PlayerConfig(
      id: json?['id']?.toString() ?? fallbackId ?? 'player_unknown',
      engine: engine,
      enabled: json?['enabled'] ?? false,
      name: json?['name'] ?? '',
      description: json?['description'] ?? '',
      order: json?['order'] is int
          ? json!['order']
          : int.tryParse(json?['order']?.toString() ?? '') ?? 99,
    );
  }
}

class DownloadSettings {
  final bool videoEnabled;
  final bool pdfEnabled;

  DownloadSettings({
    required this.videoEnabled,
    required this.pdfEnabled,
  });

  factory DownloadSettings.fromJson(Map<String, dynamic>? json) {
    return DownloadSettings(
      videoEnabled: json?['video_enabled'] ?? false,
      pdfEnabled: json?['pdf_enabled'] ?? false,
    );
  }
}
