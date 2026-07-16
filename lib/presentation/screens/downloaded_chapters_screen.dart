import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import 'downloaded_chapter_contents_screen.dart';
import '../../l10n/generated/app_localizations.dart';
import 'package:Medaad/presentation/widgets/directional_icon.dart';
import 'package:Medaad/presentation/widgets/marquee_text.dart';

class DownloadedChaptersScreen extends StatefulWidget {
  final String courseTitle;
  final String subjectTitle;

  const DownloadedChaptersScreen({
    super.key,
    required this.courseTitle,
    required this.subjectTitle,
  });

  @override
  State<DownloadedChaptersScreen> createState() =>
      _DownloadedChaptersScreenState();
}

class _DownloadedChaptersScreenState extends State<DownloadedChaptersScreen> {
  // 🗂️ [جديد] نفس منطق طي/فتح المجلدات المستخدم في شاشة محتوى المادة:
  // المجلدات تكون مطوية (مغلقة) بشكل افتراضي عند ظهورها لأول مرة.
  final Set<String> _collapsedFolders = {};
  final Set<String> _knownFolderNames = {};

  void _syncFolderDefaults(Iterable<String> folderNames) {
    for (final name in folderNames) {
      if (name.isEmpty) continue;
      if (!_knownFolderNames.contains(name)) {
        _knownFolderNames.add(name);
        _collapsedFolders.add(name);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. جلب صندوق التخزين
    var box = Hive.box('downloads_box');

    // 2. تصفية وتجميع الفصول (Chapters)
    // Map<ChapterName, FileCount>
    final Map<String, int> groupedChapters = {};
    // اسم المجلد الخاص بكل فصل (لو موجود)
    final Map<String, String> chapterFolder = {};

    for (var key in box.keys) {
      final item = box.get(key);
      // التأكد من تطابق الكورس والمادة
      if (item['course'] == widget.courseTitle &&
          item['subject'] == widget.subjectTitle) {
        final chapter = item['chapter'] ??
            AppLocalizations.of(context)!.unknownChapterFallback;
        groupedChapters[chapter] = (groupedChapters[chapter] ?? 0) + 1;

        final String folder = ((item['folder'] as String?) ?? '').trim();
        if (folder.isNotEmpty && !chapterFolder.containsKey(chapter)) {
          chapterFolder[chapter] = folder;
        }
      }
    }

    // 🗂️ تجميع الفصول التي تشترك في نفس اسم المجلد، بنفس ترتيب أول ظهور،
    // تماماً كما في شاشة محتوى المادة أونلاين.
    final List<_DownloadedEntry> entries = [];
    final Map<String, int> folderPosition = {};

    groupedChapters.forEach((chapterName, fileCount) {
      final String folderName = chapterFolder[chapterName] ?? '';
      if (folderName.isEmpty) {
        entries.add(_DownloadedEntry.single(chapterName, fileCount));
        return;
      }
      if (folderPosition.containsKey(folderName)) {
        entries[folderPosition[folderName]!]
            .items!
            .add(MapEntry(chapterName, fileCount));
      } else {
        folderPosition[folderName] = entries.length;
        entries.add(_DownloadedEntry.folder(
            folderName, [MapEntry(chapterName, fileCount)]));
      }
    });

    _syncFolderDefaults(folderPosition.keys);

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                      ),
                      child: DirectionalFlip(child: Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow, size: 20)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.subjectTitle.toUpperCase(),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                            overflow: TextOverflow.ellipsis,
                            letterSpacing: -0.5,
                          ),
                          maxLines: 1,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppLocalizations.of(context)!.downloadedChaptersLabel,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppColors.accentYellow.withOpacity(0.8),
                            letterSpacing: 2.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Content List
            Expanded(
              child: entries.isEmpty
                  ? Center(child: Text(AppLocalizations.of(context)!.noChaptersFound, style: TextStyle(color: AppColors.textSecondary.withOpacity(0.5))))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        if (!entry.isFolder) {
                          return _buildChapterCard(
                              entry.chapterName!, entry.fileCount!);
                        }
                        return _buildFolderGroup(entry.folderName!, entry.items!);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // 🗂️ [جديد] رأس مجلد قابل للطي يحتوي على فصوله المحملة، بنفس تصميم
  // شاشة محتوى المادة أونلاين.
  Widget _buildFolderGroup(String folderName, List<MapEntry<String, int>> items) {
    final bool isCollapsed = _collapsedFolders.contains(folderName);
    final int totalFiles = items.fold(0, (sum, e) => sum + e.value);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                if (isCollapsed) {
                  _collapsedFolders.remove(folderName);
                } else {
                  _collapsedFolders.add(folderName);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.backgroundPrimary,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.accentYellow.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.folder,
                      size: 18, color: AppColors.accentYellow),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MarqueeText(
                      folderName.toUpperCase(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  Text(
                    "$totalFiles",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    isCollapsed
                        ? LucideIcons.chevronDown
                        : LucideIcons.chevronUp,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (!isCollapsed) ...[
            const SizedBox(height: 10),
            // 🌳 خط دليل رفيع يربط بصرياً بين رأس المجلد وفصوله المتداخلة.
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 6),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 2,
                      margin: const EdgeInsetsDirectional.only(end: 14),
                      decoration: BoxDecoration(
                        color: AppColors.accentYellow.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: items
                            .map<Widget>((e) => _buildChapterCard(
                                e.key, e.value,
                                compact: true))
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 🔵 بطاقة فصل واحد — تصغر تلقائياً عند عرضها داخل مجموعة مجلد
  // (compact: true) لتناسب أسلوب عرض المجلدات.
  Widget _buildChapterCard(String chapterName, int fileCount,
      {bool compact = false}) {
    final double cardPadding = compact ? 9 : 16;
    final double cardMarginBottom = compact ? 6 : 12;
    final double cardRadius = compact ? 10 : 16;
    final double badgeSize = compact ? 26 : 40;
    final double badgeRadius = compact ? 6 : 12;
    final double badgeIconSize = compact ? 13 : 18;
    final double gapWidth = compact ? 10 : 16;
    final double titleFontSize = compact ? 12 : 15;
    final double countsFontSize = compact ? 7 : 9;
    final double chevronSize = compact ? 14 : 18;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DownloadedChapterContentsScreen(
            courseTitle: widget.courseTitle,
            subjectTitle: widget.subjectTitle,
            chapterTitle: chapterName,
          ),
        ),
      ),
      child: Container(
        margin: EdgeInsets.only(bottom: cardMarginBottom),
        padding: EdgeInsets.all(cardPadding),
        decoration: BoxDecoration(
          color: compact
              ? AppColors.backgroundSecondary.withOpacity(0.55)
              : AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(cardRadius),
          border: Border.all(
            color: compact
                ? AppColors.accentYellow.withOpacity(0.12)
                : Colors.white.withOpacity(0.05),
          ),
          boxShadow: compact
              ? []
              : const [BoxShadow(color: Colors.black12, blurRadius: 4)],
        ),
        child: Row(
          children: [
            Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                color: AppColors.backgroundPrimary,
                borderRadius: BorderRadius.circular(badgeRadius),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
              ),
              child: Icon(LucideIcons.bookOpen, color: AppColors.accentYellow, size: badgeIconSize),
            ),
            SizedBox(width: gapWidth),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarqueeText(
                    chapterName.toUpperCase(),
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "$fileCount FILES",
                    style: TextStyle(
                      fontSize: countsFontSize,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary.withOpacity(0.7),
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            DirectionalFlip(child: Icon(LucideIcons.chevronRight, color: AppColors.textSecondary.withOpacity(0.6), size: chevronSize)),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 🗂️ عنصر مساعد بسيط لعرض قائمة الفصول المحملة: إما فصل منفرد (بدون
// مجلد) أو مجموعة فصول تشترك في نفس اسم المجلد الاختياري.
// ============================================================
class _DownloadedEntry {
  final bool isFolder;
  final String? chapterName; // للفصل المنفرد فقط
  final int? fileCount; // للفصل المنفرد فقط
  final String? folderName; // لمجموعة المجلد فقط
  final List<MapEntry<String, int>>? items; // فصول المجلد + عدد ملفاتها

  _DownloadedEntry.single(this.chapterName, this.fileCount)
      : isFolder = false,
        folderName = null,
        items = null;

  _DownloadedEntry.folder(this.folderName, this.items)
      : isFolder = true,
        chapterName = null,
        fileCount = null;
}
