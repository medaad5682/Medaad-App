import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/video_screenshot_service.dart';
import 'package:Medaad/presentation/widgets/directional_icon.dart';
import 'package:Medaad/l10n/generated/app_localizations.dart';

/// معرض "لقطات الفيديو" — يعرض اللقطات المشفّرة بعد فكّها في الذاكرة فقط
/// (لا تُكتب أي نسخة مفكوكة على القرص في أي لحظة). يمكن تمرير [lessonIds]
/// لعرض لقطات فصل/تنزيل معيّن فقط (كما تفعل شاشة المحتوى المُنزَّل)، أو
/// تركه فارغاً لعرض كل اللقطات المحفوظة في الجهاز.
class VideoScreenshotsScreen extends StatefulWidget {
  final String? title;
  final Set<String>? lessonIds;

  const VideoScreenshotsScreen({
    super.key,
    this.title,
    this.lessonIds,
  });

  @override
  State<VideoScreenshotsScreen> createState() =>
      _VideoScreenshotsScreenState();
}

class _VideoScreenshotsScreenState extends State<VideoScreenshotsScreen> {
  List<VideoScreenshotRecord> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final all = await VideoScreenshotService.listAll();
      final filtered = widget.lessonIds == null
          ? all
          : all.where((r) => widget.lessonIds!.contains(r.lessonId)).toList();
      if (!mounted) return;
      setState(() {
        _records = filtered;
        _isLoading = false;
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
        e,
        stack,
        reason: 'VideoScreenshotsScreen._load failed',
        fatal: false,
      );
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openViewer(int index) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ScreenshotViewerScreen(
          records: _records,
          initialIndex: index,
          onDeleted: _load,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24.0),
              color: AppColors.backgroundPrimary.withOpacity(0.95),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: DirectionalFlip(
                      child: Icon(LucideIcons.arrowLeft,
                          color: AppColors.accentYellow, size: 24),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      widget.title ??
                          AppLocalizations.of(context)!.videoScreenshotsTitle,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accentYellow),
                    )
                  : _records.isEmpty
                      ? _buildEmptyState(context)
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: AppColors.accentYellow,
                          child: GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 16 / 10,
                            ),
                            itemCount: _records.length,
                            itemBuilder: (context, index) {
                              final record = _records[index];
                              return _ScreenshotThumbnail(
                                record: record,
                                onTap: () => _openViewer(index),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.image,
              size: 48, color: AppColors.textSecondary.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.noVideoScreenshotsYet,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0,
              color: AppColors.textSecondary.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// بطاقة مصغّرة واحدة — تفك تشفير الصورة في الذاكرة فقط عند الحاجة للعرض
/// (FutureBuilder)، ولا تخزّن أي بايتات مفكوكة على القرص.
class _ScreenshotThumbnail extends StatelessWidget {
  final VideoScreenshotRecord record;
  final VoidCallback onTap;

  const _ScreenshotThumbnail({required this.record, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<Uint8List>(
                future: VideoScreenshotService.decryptForView(record.filePath),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accentYellow,
                        ),
                      ),
                    );
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return Icon(LucideIcons.imageOff,
                        color: AppColors.textSecondary.withOpacity(0.5));
                  }
                  return Image.memory(
                    snapshot.data!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  );
                },
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.75),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Text(
                    record.videoTitle,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// عارض ملء الشاشة مع التكبير/التصغير وحذف اللقطة — يفك التشفير في الذاكرة
/// فقط عند فتح كل صفحة (لا نسخة مفكوكة على القرص).
class _ScreenshotViewerScreen extends StatefulWidget {
  final List<VideoScreenshotRecord> records;
  final int initialIndex;
  final VoidCallback onDeleted;

  const _ScreenshotViewerScreen({
    required this.records,
    required this.initialIndex,
    required this.onDeleted,
  });

  @override
  State<_ScreenshotViewerScreen> createState() =>
      _ScreenshotViewerScreenState();
}

class _ScreenshotViewerScreenState extends State<_ScreenshotViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;
  late List<VideoScreenshotRecord> _records;

  @override
  void initState() {
    super.initState();
    _records = List.of(widget.records);
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        title: Text(loc.deleteScreenshotConfirmTitle,
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(loc.deleteScreenshotConfirmBody,
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.delete, style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final record = _records[_currentIndex];
    try {
      await VideoScreenshotService.delete(record.id);
      widget.onDeleted();
      if (!mounted) return;
      setState(() {
        _records.removeAt(_currentIndex);
        if (_records.isEmpty) {
          Navigator.pop(context);
          return;
        }
        if (_currentIndex >= _records.length) {
          _currentIndex = _records.length - 1;
        }
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(
        e,
        stack,
        reason: 'VideoScreenshotViewer delete failed',
        fatal: false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_records.isEmpty) {
      return const SizedBox.shrink();
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _records[_currentIndex].videoTitle,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.trash2, color: Colors.white),
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: _records.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (context, index) {
          final record = _records[index];
          return FutureBuilder<Uint8List>(
            future: VideoScreenshotService.decryptForView(record.filePath),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Center(
                  child: CircularProgressIndicator(
                      color: AppColors.accentYellow),
                );
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return const Center(
                  child: Icon(LucideIcons.imageOff,
                      color: Colors.white54, size: 48),
                );
              }
              return InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Image.memory(snapshot.data!, gaplessPlayback: true),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
