import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/services/file_crypto_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/pdf_annotation_store.dart';
import '../../core/constants/api_constants.dart';

import '../../core/models/drawing_model.dart';
import '../../core/models/comment_model.dart';
import '../../core/models/shape_model.dart';
import '../../core/models/highlight_model.dart';
import '../../core/models/pdf_tool_settings.dart';

import '../../core/pdf_viewer/pdf_tool.dart';
import '../../core/pdf_viewer/pdf_layout_engine.dart';
import '../../core/pdf_viewer/pdf_page_text_cache.dart';
import '../../core/pdf_viewer/pdf_highlight_controller.dart';
import '../../core/pdf_viewer/pdf_shape_controller.dart';
import '../../core/pdf_viewer/pdf_text_note_controller.dart';
import '../../core/pdf_viewer/pdf_image_annotation_controller.dart';
import '../../core/pdf_viewer/palm_rejection_filter.dart';

import '../widgets/pdf_tools/pdf_annotation_toolbar.dart';
import '../widgets/pdf_tools/movable_text_note.dart';
import '../widgets/pdf_tools/movable_resizable_image.dart';
import '../widgets/pdf_tools/color_palette_row.dart';

class PdfViewerScreen extends StatefulWidget {
  final String pdfId;
  final String title;

  const PdfViewerScreen({super.key, required this.pdfId, required this.title});

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final PdfViewerController _pdfController = PdfViewerController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // --- متغيرات فك التشفير (بدون أي تغيير عن النسخة الأصلية) ---
  File? _encryptedFile;
  int? _originalFileSize;
  String? _sessionToken;

  // --- متغيرات العرض الأونلاين ---
  String? _onlineUrl;
  Map<String, String>? _onlineHeaders;

  bool _loading = true;
  String _loadingMessage = "جار التحقق من الملف...";
  String? _error;
  bool _isOffline = false;
  String _watermarkText = '';

  // --- إعدادات الأدوات والقراءة (محفوظة بين الجلسات) ---
  late PdfAnnotationStore _store;
  PdfToolSettings _settings = PdfToolSettings();
  CommentDefaults _commentDefaults = CommentDefaults();

  bool _isDrawingMode = false;
  PdfTool _activeTool = PdfTool.none;

  // القلم/الممحاة (الرسم الحر) - يبقى كما كان
  Map<int, List<DrawingLine>> _pageDrawings = {};
  DrawingLine? _currentLine;
  double _eraserSize = 0.04;

  // الملاحظات (Notes)
  Map<int, List<CommentModel>> _pageComments = {};

  // المحركات الجديدة لكل أداة
  late PdfHighlightController _highlightController;
  late PdfShapeController _shapeController;
  late PdfTextNoteController _textNoteController;
  late PdfImageAnnotationController _imageController;
  final PdfPageTextCache _textCache = PdfPageTextCache();
  final PalmRejectionFilter _palmFilter = PalmRejectionFilter();

  int _activePage = 0;
  int _totalPages = 0;

  @override
  void initState() {
    super.initState();
    _sessionToken = _generateSecureToken();
    _store = PdfAnnotationStore(widget.pdfId);
    _highlightController = PdfHighlightController(
      store: _store,
      textCache: _textCache,
      onChanged: () => setState(() {}),
    );
    _shapeController = PdfShapeController(store: _store, onChanged: () => setState(() {}));
    _textNoteController = PdfTextNoteController(store: _store, onChanged: () => setState(() {}));
    _imageController = PdfImageAnnotationController(
      pdfId: widget.pdfId,
      store: _store,
      onChanged: () => setState(() {}),
    );
    _initWatermarkText();
    _loadToolSettings();
    _preparePdf();
  }

  @override
  void dispose() {
    if (_isOffline) _saveAnnotationsToHive();
    super.dispose();
  }

  String _generateSecureToken() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }

  Future<int> _customRead(Uint8List buffer, int position, int size) async {
    try {
      if (_sessionToken == null) throw Exception("Unauthorized access context");
      if (_encryptedFile == null) throw Exception("File not initialized");

      final decryptedData =
          await FileCryptoService.readAndDecryptRange(_encryptedFile!, position, size);

      if (decryptedData.isNotEmpty) {
        buffer.setRange(0, decryptedData.length, decryptedData);
        return decryptedData.length;
      }
      return 0;
    } catch (e) {
      debugPrint("Secure Read Error: $e");
      return 0;
    }
  }

  Future<void> _initWatermarkText() async {
    String displayText = '';
    if (AppState().userData != null) {
      displayText =
          AppState().userData!['phone'] != null ? AppState().userData!['phone'] : '';
    }
    if (displayText.isEmpty) {
      try {
        final box = await StorageService.openBox('auth_box');
        displayText = box.get('phone') ?? box.get('first_name') ?? '';
      } catch (e) {
        debugPrint("Error fetching watermark: $e");
      }
    }
    if (mounted) {
      setState(() => _watermarkText =
          displayText.isNotEmpty ? displayText : AppState().userData!['username'] ?? 'Unknown User');
    }
  }

  Future<void> _loadToolSettings() async {
    final settings = await PdfAnnotationStore.loadGlobalSettings();
    final defaults = await PdfAnnotationStore.loadCommentDefaults();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _commentDefaults = defaults;
      _palmFilter.enabled = settings.palmRejectionEnabled;
      _highlightController.highlightColor = settings.highlighterColor;
      _highlightController.underlineColor = settings.underlineColor;
      _highlightController.highlightOpacity = settings.highlighterOpacity;
      _shapeController.borderColor = settings.shapeBorderColor;
      _shapeController.fillColor = settings.shapeFillColor;
      _shapeController.borderWidth = settings.shapeBorderWidth;
      _textNoteController.defaultColor = settings.textColor;
      _textNoteController.defaultFontSize = settings.textFontSize;
    });
  }

  Future<void> _persistToolSettings() => PdfAnnotationStore.saveGlobalSettings(_settings);

  // ✅ حفظ الرسم والتعليقات (نفس منطق النسخة الأصلية، يستخدم الآن PdfAnnotationStore)
  Future<void> _saveAnnotationsToHive() async {
    try {
      for (var entry in _pageDrawings.entries) {
        await _store.saveDrawings(entry.key, entry.value);
      }
      for (var entry in _pageComments.entries) {
        await _store.saveComments(entry.key, entry.value);
      }
    } catch (_) {}
  }

  // ✅ جلب كل أنواع التعليقات/الرسومات لصفحة معينة (يضيف الأنواع الجديدة على القديمة)
  Future<void> _loadAnnotationsForPage(int pageNumber) async {
    if (!_pageDrawings.containsKey(pageNumber)) {
      _pageDrawings[pageNumber] = await _store.loadDrawings(pageNumber);
    }
    if (!_pageComments.containsKey(pageNumber)) {
      _pageComments[pageNumber] = await _store.loadComments(pageNumber);
    }
    await _highlightController.ensurePageLoaded(pageNumber);
    await _shapeController.ensurePageLoaded(pageNumber);
    await _textNoteController.ensurePageLoaded(pageNumber);
    await _imageController.ensurePageLoaded(pageNumber);
  }

  Future<void> _preparePdf() async {
    setState(() {
      _loading = true;
      _loadingMessage = "جار تهيئة الحماية...";
    });

    try {
      await FileCryptoService.init();

      final downloadsBox = await StorageService.openBox('downloads_box');
      final downloadItem = downloadsBox.get('pdf_${widget.pdfId}');

      if (downloadItem != null && downloadItem['path'] != null) {
        final file = File(downloadItem['path']);
        if (await file.exists()) {
          final totalSize = await file.length();

          int numChunks = (totalSize / FileCryptoService.ENCRYPTED_CHUNK_SIZE).ceil();
          int originalSize = totalSize - (numChunks * FileCryptoService.NONCE_LENGTH);

          if (mounted) {
            setState(() {
              _isOffline = true;
              _encryptedFile = file;
              _originalFileSize = originalSize;
              _loading = false;
            });
          }
          return;
        }
      }

      setState(() {
        _isOffline = false;
        _loadingMessage = "جار التحميل المباشر...";
      });

      var box = await StorageService.openBox('auth_box');
      final String? token = box.get('jwt_token');
      final String? deviceId = box.get('device_id');

      _onlineHeaders = {
        'Authorization': 'Bearer $token',
        'x-device-id': deviceId ?? '',
        'x-app-secret': const String.fromEnvironment('APP_SECRET'),
      };

      _onlineUrl = '${ApiConstants.apiUrl}/secure/get-pdf?pdfId=${widget.pdfId}';

      if (mounted) setState(() => _loading = false);
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: "PDF Secure Load Failed");
      if (mounted) {
        setState(() {
          _error = "فشل فتح الملف المحمي.";
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildLoadingView();
    if (_error != null) return _buildErrorView();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.backgroundPrimary,
      endDrawer: _buildPageDrawer(),
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          _isOffline && _encryptedFile != null && _originalFileSize != null
              ? PdfViewer.custom(
                  fileSize: _originalFileSize!,
                  read: _customRead,
                  sourceName: _encryptedFile!.path,
                  controller: _pdfController,
                  params: _buildPdfParams(),
                )
              : PdfViewer.uri(
                  Uri.parse(_onlineUrl!),
                  headers: _onlineHeaders,
                  controller: _pdfController,
                  params: _buildPdfParams(),
                ),
          _buildWatermark(),
          if (_isDrawingMode)
            Positioned(bottom: 40, left: 20, right: 20, child: _buildToolbar()),
        ],
      ),
    );
  }

  // --- Widgets أساسية (محافظة على شكل التطبيق الأصلي) ---

  Widget _buildLoadingView() {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.accentYellow),
            const SizedBox(height: 20),
            Text(_loadingMessage,
                style: TextStyle(color: AppColors.accentYellow, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(
            backgroundColor: Colors.transparent, leading: const BackButton(color: Colors.white)),
        body: Center(child: Text(_error!, style: const TextStyle(color: Colors.white))));
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Row(
        children: [
          Expanded(
              child: Text(widget.title,
                  style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          _buildBadge(),
          if (_isOffline) ...[
            const SizedBox(width: 12),
            _buildPenIcon(),
          ]
        ],
      ),
      backgroundColor: AppColors.backgroundSecondary,
      leading: BackButton(
          color: AppColors.accentYellow,
          onPressed: () async {
            if (_isOffline) await _saveAnnotationsToHive();
            if (context.mounted) Navigator.pop(context);
          }),
      actions: [
        _buildReadingModeButton(),
        IconButton(
          icon: Icon(LucideIcons.list, color: AppColors.accentYellow),
          onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
        ),
      ],
    );
  }

  /// زر اختيار وضع القراءة (عمودي / أفقي / صفحتان جنباً إلى جنب).
  Widget _buildReadingModeButton() {
    return PopupMenuButton<PdfReadingMode>(
      icon: Icon(_readingModeIcon(_settings.readingMode), color: AppColors.accentYellow),
      tooltip: 'وضع القراءة',
      color: AppColors.backgroundSecondary,
      onSelected: (mode) {
        setState(() => _settings.readingMode = mode);
        _persistToolSettings();
      },
      itemBuilder: (context) => [
        _readingModeMenuItem(PdfReadingMode.vertical, 'عمودي', Icons.swap_vert),
        _readingModeMenuItem(PdfReadingMode.horizontal, 'أفقي', Icons.swap_horiz),
        _readingModeMenuItem(PdfReadingMode.twoPage, 'صفحتان جنباً إلى جنب', Icons.menu_book),
      ],
    );
  }

  IconData _readingModeIcon(PdfReadingMode mode) {
    switch (mode) {
      case PdfReadingMode.vertical:
        return Icons.swap_vert;
      case PdfReadingMode.horizontal:
        return Icons.swap_horiz;
      case PdfReadingMode.twoPage:
        return Icons.menu_book;
    }
  }

  PopupMenuItem<PdfReadingMode> _readingModeMenuItem(
      PdfReadingMode mode, String label, IconData icon) {
    final bool selected = _settings.readingMode == mode;
    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          Icon(icon, size: 18, color: selected ? AppColors.accentYellow : AppColors.textSecondary),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  color: selected ? AppColors.accentYellow : AppColors.textPrimary,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  Widget _buildBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _isOffline ? Colors.green.withOpacity(0.2) : Colors.blue.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _isOffline ? Colors.green : Colors.blue, width: 1),
      ),
      child: Row(
        children: [
          Icon(_isOffline ? LucideIcons.hardDrive : LucideIcons.cloud,
              size: 12, color: _isOffline ? Colors.green : Colors.blue),
          const SizedBox(width: 4),
          Text(_isOffline ? "Offline" : "Stream",
              style: TextStyle(
                  fontSize: 10,
                  color: _isOffline ? Colors.green : Colors.blue,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildPenIcon() {
    return GestureDetector(
      onTap: () => setState(() {
        _isDrawingMode = !_isDrawingMode;
        if (!_isDrawingMode) {
          _activeTool = PdfTool.none;
          _highlightController.activeTool = TextMarkupTool.none;
        }
      }),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            color: _isDrawingMode ? AppColors.accentYellow : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.accentYellow.withOpacity(0.5))),
        child: Icon(LucideIcons.penTool,
            color: _isDrawingMode ? Colors.black : AppColors.accentYellow, size: 16),
      ),
    );
  }

  Widget _buildWatermark() {
    return IgnorePointer(
      child: Center(
        child: Opacity(
          opacity: 0.35,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(
                3,
                (index) => Transform.rotate(
                      angle: -0.5,
                      child: Text(
                        _watermarkText,
                        textScaler: const TextScaler.linear(2.2),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                            decoration: TextDecoration.none),
                      ),
                    )),
          ),
        ),
      ),
    );
  }

  Widget _buildPageDrawer() {
    return Drawer(
      backgroundColor: AppColors.backgroundSecondary,
      width: 250,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
            child: Text("فهرس الصفحات",
                style: TextStyle(
                    color: AppColors.accentYellow, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const Divider(color: Colors.white10),
          Expanded(
            child: _totalPages == 0
                ? Center(child: CircularProgressIndicator(color: AppColors.accentYellow))
                : ListView.builder(
                    itemCount: _totalPages,
                    itemBuilder: (context, index) {
                      final pageNum = index + 1;
                      final isCurrent = _pdfController.pageNumber == pageNum;
                      return ListTile(
                        title: Text("صفحة $pageNum",
                            style: TextStyle(
                                color: isCurrent ? AppColors.accentYellow : AppColors.textPrimary,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                        leading: Icon(LucideIcons.fileText,
                            color: isCurrent ? AppColors.accentYellow : AppColors.textSecondary,
                            size: 18),
                        onTap: () {
                          _pdfController.goToPage(pageNumber: pageNum);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // --- إعداد عارض PDF ---

  PdfViewerParams _buildPdfParams() {
    final layout = PdfLayoutEngine.layoutFor(_settings.readingMode);
    return PdfViewerParams(
      backgroundColor: AppColors.backgroundPrimary,
      layoutPages: layout,
      pageAnchor: PdfLayoutEngine.anchorStartFor(_settings.readingMode),
      pageAnchorEnd: PdfLayoutEngine.anchorEndFor(_settings.readingMode),
      scrollHorizontallyByMouseWheel:
          PdfLayoutEngine.scrollHorizontallyByMouseWheelFor(_settings.readingMode),
      scrollPhysics: const BouncingScrollPhysics(),
      // ✅ تفعيل تحديد النص لأدوات التمييز/التسطير دائماً (أونلاين وأوفلاين)
      textSelectionParams: PdfTextSelectionParams(
        enabled: _isDrawingMode &&
            (_activeTool == PdfTool.highlighter || _activeTool == PdfTool.underline),
        onTextSelectionChange: (selection) =>
            _highlightController.handleTextSelectionChange(selection, _pdfController),
      ),
      buildContextMenu: (context, params) => null, // ✅ منع ظهور قائمة "نسخ" نهائياً
      pagePaintCallbacks: [
        _highlightController.paint,
      ],
      loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
        return Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration:
                BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
            child: CircularProgressIndicator(color: AppColors.accentYellow),
          ),
        );
      },
      onDocumentChanged: (document) {
        if (mounted) setState(() => _totalPages = document?.pages.length ?? 0);
      },
      onPageChanged: (pageNumber) {
        if (pageNumber != null) _activePage = pageNumber;
      },
      pageOverlaysBuilder: (context, pageRect, page) {
        // تحميل نص الصفحة مسبقاً (للتمييز/التسطير)
        _textCache.ensureLoaded(page);

        return [
          Positioned.fill(
            child: FutureBuilder(
              future: _isOffline ? _loadAnnotationsForPage(page.pageNumber) : Future.value(),
              builder: (context, snapshot) {
                final lines = _pageDrawings[page.pageNumber] ?? [];
                final allLines = [...lines];
                if (_isDrawingMode && _currentLine != null && _activePage == page.pageNumber) {
                  allLines.add(_currentLine!);
                }

                final comments = _isOffline ? (_pageComments[page.pageNumber] ?? []) : <dynamic>[];
                final shapes = _shapeController.shapesForPage(page.pageNumber);
                final shapePreview = _shapeController.drawingShapeForPage(page.pageNumber);
                final textNotes = _textNoteController.notesForPage(page.pageNumber);
                final images = _imageController.imagesForPage(page.pageNumber);

                return Stack(
                  children: [
                    // طبقة الرسم الحر (القلم/الممحاة) + الأشكال
                    // تُمرَّر الإيماءات للـ PDF عندما لا توجد أداة نشطة أو عند استخدام
                    // أدوات التمييز/التسطير (التي تعتمد على تحديد نص الـ PDF مباشرة)
                    IgnorePointer(
                      ignoring: !_isDrawingMode ||
                          _activeTool == PdfTool.none ||
                          _activeTool == PdfTool.highlighter ||
                          _activeTool == PdfTool.underline,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) => _handleTapUp(details, context, pageRect, page),
                        onPanStart: (details) =>
                            _handlePanStart(details, context, pageRect, page),
                        onPanUpdate: (details) =>
                            _handlePanUpdate(details, context, pageRect, page),
                        onPanEnd: (details) => _handlePanEnd(page),
                        child: CustomPaint(
                          painter: _CombinedOverlayPainter(
                            lines: allLines,
                            shapes: shapes,
                            shapePreview: shapePreview,
                            pageSize: pageRect.size,
                            shapeController: _shapeController,
                          ),
                          size: Size.infinite,
                        ),
                      ),
                    ),

                    // طبقة النصوص المكتوبة
                    ...textNotes.map((note) => Positioned(
                          left: note.dx * pageRect.width,
                          top: note.dy * pageRect.height,
                          child: MovableTextNote(
                            note: note,
                            pageWidth: pageRect.width,
                            // قابل للتعديل إذا كانت أداة النص نشطة أو إذا كان وضع التعديل
                            // مفعّلاً ولا توجد أداة أخرى نشطة (كشف ذكي)
                            editable: _isDrawingMode &&
                                (_activeTool == PdfTool.text ||
                                    _activeTool == PdfTool.none),
                            onDragDelta: (delta) =>
                                _textNoteController.moveNote(page.pageNumber, note, delta),
                            onTap: () {
                              if (_isDrawingMode) {
                                // تفعيل أداة النص تلقائياً عند النقر على مربع نص
                                if (_activeTool != PdfTool.text) {
                                  setState(() {
                                    _activeTool = PdfTool.text;
                                    _highlightController.activeTool = TextMarkupTool.none;
                                  });
                                }
                                _editTextNote(page.pageNumber, note);
                              }
                            },
                            onDelete: _isDrawingMode
                                ? () => _textNoteController.deleteNote(
                                    page.pageNumber, note)
                                : null,
                          ),
                        )),

                    // طبقة الصور المُدرجة
                    ...images.map((img) => Positioned(
                          left: img.dx * pageRect.width,
                          top: img.dy * pageRect.height,
                          child: GestureDetector(
                            onTap: () {
                              // كشف ذكي: النقر على صورة يُفعّل أداة الصورة تلقائياً
                              if (_isDrawingMode && _activeTool != PdfTool.image) {
                                setState(() {
                                  _activeTool = PdfTool.image;
                                  _highlightController.activeTool = TextMarkupTool.none;
                                });
                              }
                            },
                            child: MovableResizableImage(
                              image: img,
                              pageWidth: pageRect.width,
                              pageHeight: pageRect.height,
                              editable: _isDrawingMode &&
                                  (_activeTool == PdfTool.image ||
                                      _activeTool == PdfTool.none),
                              onMoveDelta: (delta) =>
                                  _imageController.moveImage(page.pageNumber, img, delta),
                              onResizeDelta: (delta) =>
                                  _imageController.resizeImage(page.pageNumber, img, delta),
                              onDelete: () =>
                                  _imageController.deleteImage(page.pageNumber, img),
                            ),
                          ),
                        )),

                    // طبقة أيقونات الملاحظات (Comments) - نفس المنطق الأصلي
                    ...comments.map((comment) {
                      Color solidColor = Color(comment.color).withOpacity(1.0);
                      double currentOpacity = Color(comment.color).opacity;

                      return Positioned(
                        left: (comment.dx * pageRect.width) - (20 * comment.scale),
                        top: (comment.dy * pageRect.height) - (20 * comment.scale),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onScaleStart:
                              (_isDrawingMode && _activeTool == PdfTool.comment) ? (_) {} : null,
                          onScaleEnd:
                              (_isDrawingMode && _activeTool == PdfTool.comment) ? (_) {} : null,
                          onScaleUpdate: (_isDrawingMode && _activeTool == PdfTool.comment)
                              ? (details) {
                                  setState(() {
                                    if (details.pointerCount == 1) {
                                      comment.dx += details.focalPointDelta.dx / pageRect.width;
                                      comment.dy += details.focalPointDelta.dy / pageRect.height;
                                    }
                                  });
                                }
                              : null,
                          onTap: () => _showCommentDialog(page.pageNumber, comment),
                          child: Transform.scale(
                            scale: comment.scale,
                            child: Opacity(
                              opacity: currentOpacity,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: AppColors.backgroundSecondary.withOpacity(0.85),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: solidColor, width: 1.5),
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black.withOpacity(0.4),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2))
                                    ]),
                                child: Icon(Icons.comment_rounded, color: solidColor, size: 24),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        ];
      },
    );
  }

  // --- معالجة الإيماءات الموحّدة (تحترم رفض راحة اليد) ---

  bool _palmAllows(PointerDeviceKind? kind) => _palmFilter.isAllowed(kind);

  void _handleTapUp(TapUpDetails details, BuildContext context, Rect pageRect, PdfPage page) {
    if (!_isDrawingMode) return;
    if (!_palmAllows(details.kind)) return;

    final renderBox = context.findRenderObject() as RenderBox;
    final localPos = renderBox.globalToLocal(details.globalPosition);
    final relativePoint = Offset(localPos.dx / pageRect.width, localPos.dy / pageRect.height);

    switch (_activeTool) {
      case PdfTool.comment:
        _addComment(relativePoint, page.pageNumber);
        break;
      case PdfTool.text:
        final note = _textNoteController.addNote(page.pageNumber, relativePoint);
        _editTextNote(page.pageNumber, note, isNew: true);
        break;
      case PdfTool.highlighter:
      case PdfTool.underline:
        // النقر على تمييز/تسطير موجود مسبقاً (دون سحب) يفتح قائمة تعديل اللون أو الحذف،
        // بدلاً من بدء تحديد نص جديد.
        _tryEditExistingMarkup(localPos, pageRect, page);
        break;
      case PdfTool.shape:
        _tryEditExistingShape(relativePoint, page.pageNumber);
        break;
      case PdfTool.image:
        // الصور تُضاف من شريط الأدوات مباشرة (زر اختيار صورة)، لا من النقر على الصفحة.
        break;
      default:
        break;
    }
  }

  void _tryEditExistingMarkup(Offset localPos, Rect pageRect, PdfPage page) {
    final pdfPoint = localPos.toPdfPoint(page: page, scaledPageSize: pageRect.size);
    final result = _highlightController.hitTest(
      pageNumber: page.pageNumber,
      pdfX: pdfPoint.x,
      pdfY: pdfPoint.y,
    );
    if (result.highlight != null) {
      _showMarkupEditSheet(highlight: result.highlight, pageNumber: page.pageNumber);
    } else if (result.underline != null) {
      _showMarkupEditSheet(underline: result.underline, pageNumber: page.pageNumber);
    }
  }

  void _showMarkupEditSheet({HighlightModel? highlight, UnderlineModel? underline, required int pageNumber}) {
    final isHighlight = highlight != null;
    final currentColor = Color(isHighlight ? highlight!.color : underline!.color);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isHighlight ? "تعديل التمييز" : "تعديل التسطير",
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ColorPaletteRow(
              selectedColor: currentColor,
              onColorSelected: (c) {
                if (isHighlight) {
                  _highlightController.updateHighlightColor(highlight!, c.value);
                } else {
                  _highlightController.updateUnderlineColor(underline!, c.value);
                }
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  if (isHighlight) {
                    _highlightController.deleteHighlight(highlight!);
                  } else {
                    _highlightController.deleteUnderline(underline!);
                  }
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                label: Text(isHighlight ? "حذف التمييز" : "حذف التسطير",
                    style: const TextStyle(color: Colors.redAccent)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _tryEditExistingShape(Offset relativePoint, int pageNumber) {
    final shape = _shapeController.hitTest(pageNumber, relativePoint);
    if (shape == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("تعديل الشكل", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text("الحدود", style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ColorPaletteRow(
              selectedColor: Color(shape.borderColor),
              onColorSelected: (c) => _shapeController.updateBorderColor(shape, pageNumber, c.value),
            ),
            const SizedBox(height: 8),
            Text("التعبئة", style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ColorPaletteRow(
              selectedColor: shape.fillColor != null ? Color(shape.fillColor!) : Colors.transparent,
              isTransparentSelected: shape.fillColor == null,
              allowTransparentOption: true,
              onTransparentSelected: () => _shapeController.updateFillColor(shape, pageNumber, null),
              onColorSelected: (c) => _shapeController.updateFillColor(shape, pageNumber, c.value),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  _shapeController.deleteShape(shape, pageNumber);
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                label: const Text("حذف الشكل", style: TextStyle(color: Colors.redAccent)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handlePanStart(DragStartDetails details, BuildContext context, Rect pageRect, PdfPage page) {
    if (!_isDrawingMode) return;
    if (!_palmAllows(details.kind)) return;

    final renderBox = context.findRenderObject() as RenderBox;
    final localPos = renderBox.globalToLocal(details.globalPosition);
    final relativePoint = Offset(localPos.dx / pageRect.width, localPos.dy / pageRect.height);

    if (_activeTool == PdfTool.pen || _activeTool == PdfTool.eraser) {
      _activePage = page.pageNumber;
      setState(() {
        _currentLine = DrawingLine(
          points: [relativePoint],
          color: _activeTool == PdfTool.eraser ? 0 : _settings.penColor,
          strokeWidth: _activeTool == PdfTool.eraser ? _eraserSize : _settings.penThickness,
          isHighlighter: false,
          isEraser: _activeTool == PdfTool.eraser,
          opacity: _activeTool == PdfTool.eraser ? 1.0 : _settings.penOpacity,
        );
      });
    } else if (_activeTool == PdfTool.shape) {
      _shapeController.startDrawing(page.pageNumber, relativePoint);
    }
  }

  void _handlePanUpdate(DragUpdateDetails details, BuildContext context, Rect pageRect, PdfPage page) {
    if (!_isDrawingMode) return;
    if (!_palmAllows(details.kind)) return;

    final renderBox = context.findRenderObject() as RenderBox;
    final localPos = renderBox.globalToLocal(details.globalPosition);
    final relativePoint = Offset(localPos.dx / pageRect.width, localPos.dy / pageRect.height);

    if (_activeTool == PdfTool.pen || _activeTool == PdfTool.eraser) {
      if (_currentLine != null) setState(() => _currentLine!.points.add(relativePoint));
    } else if (_activeTool == PdfTool.shape) {
      _shapeController.updateDrawing(relativePoint);
    }
  }

  void _handlePanEnd(PdfPage page) {
    if (_activeTool == PdfTool.pen || _activeTool == PdfTool.eraser) {
      if (_currentLine != null) {
        setState(() {
          _pageDrawings.putIfAbsent(page.pageNumber, () => []).add(_currentLine!);
          _store.saveDrawings(page.pageNumber, _pageDrawings[page.pageNumber]!);
          _currentLine = null;
        });
      }
    } else if (_activeTool == PdfTool.shape) {
      _shapeController.endDrawing();
    }
  }

  // --- منطق الملاحظات (Comments) - محافظ على نفس السلوك الأصلي تماماً ---

  void _addComment(Offset relativePoint, int pageNumber) {
    final newComment = CommentModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: '',
      dx: relativePoint.dx,
      dy: relativePoint.dy,
      color: _commentDefaults.color,
      scale: _commentDefaults.scale,
    );
    _showCommentDialog(pageNumber, newComment, isNew: true);
  }

  void _showCommentDialog(int pageNumber, CommentModel comment, {bool isNew = false}) {
    TextEditingController controller = TextEditingController(text: comment.text);

    showDialog(
        context: context,
        barrierDismissible: !isNew,
        builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) {
              return AlertDialog(
                  backgroundColor: AppColors.backgroundSecondary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Row(
                    children: [
                      Icon(Icons.comment_rounded, color: Color(comment.color).withOpacity(1.0)),
                      const SizedBox(width: 8),
                      Text(isNew ? "إضافة تعليق" : "التعليق",
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
                    ],
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ✅ إصلاح خلط العربي/الإنجليزي: نسمح لـ Flutter بتحديد اتجاه
                        // كل فقرة تلقائياً بدلاً من فرض اتجاه واحد ثابت يكسر ترتيب الكلمات.
                        TextField(
                          controller: controller,
                          maxLines: 4,
                          enabled: _isDrawingMode,
                          textDirection: _autoDirection(controller.text),
                          textAlign: TextAlign.start,
                          style: TextStyle(color: AppColors.textPrimary),
                          onChanged: (_) => setDialogState(() {}),
                          decoration: InputDecoration(
                            hintText: _isDrawingMode ? "اكتب ملاحظاتك هنا..." : "لا يوجد نص...",
                            hintStyle: TextStyle(color: AppColors.textSecondary),
                            filled: true,
                            fillColor: AppColors.backgroundPrimary,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                        if (_isDrawingMode) ...[
                          const SizedBox(height: 16),
                          ColorPaletteRow(
                            selectedColor: Color(comment.color).withOpacity(1.0),
                            onColorSelected: (c) {
                              setDialogState(() {
                                final opacity = Color(comment.color).opacity;
                                comment.color = c.withOpacity(opacity).value;
                              });
                              setState(() {});
                            },
                          ),
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text("حجم الأيقونة: ${(comment.scale).toStringAsFixed(1)}",
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          ),
                          Slider(
                              value: comment.scale,
                              min: 0.5,
                              max: 4.0,
                              activeColor: AppColors.accentYellow,
                              inactiveColor: AppColors.accentYellow.withOpacity(0.3),
                              onChanged: (val) {
                                setDialogState(() => comment.scale = val);
                                setState(() {});
                              }),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                                "الشفافية: ${(Color(comment.color).opacity * 100).toInt()}%",
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          ),
                          Slider(
                              value: Color(comment.color).opacity,
                              min: 0.1,
                              max: 1.0,
                              activeColor: AppColors.accentYellow,
                              inactiveColor: AppColors.accentYellow.withOpacity(0.3),
                              onChanged: (val) {
                                setDialogState(() {
                                  Color baseColor = Color(comment.color);
                                  comment.color = baseColor.withOpacity(val).value;
                                });
                                setState(() {});
                              }),
                          const SizedBox(height: 10),
                          // ✅ حفظ هذا الشكل كافتراضي للملاحظات القادمة
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () {
                                _commentDefaults = CommentDefaults(
                                  color: Color(comment.color).withOpacity(1.0).value,
                                  scale: comment.scale,
                                );
                                PdfAnnotationStore.saveCommentDefaults(_commentDefaults);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("تم حفظ الإعدادات الافتراضية")),
                                );
                              },
                              icon:
                                  Icon(Icons.bookmark_outline, size: 16, color: AppColors.accentYellow),
                              label: Text("حفظ كافتراضي",
                                  style: TextStyle(color: AppColors.accentYellow, fontSize: 12)),
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
                  actions: [
                    if (!isNew && _isDrawingMode)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _pageComments[pageNumber]?.remove(comment);
                            _store.saveComments(pageNumber, _pageComments[pageNumber] ?? []);
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text("حذف",
                            style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(_isDrawingMode ? "إلغاء" : "إغلاق",
                          style: const TextStyle(color: Colors.grey)),
                    ),
                    if (_isDrawingMode)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accentYellow, foregroundColor: Colors.black),
                        onPressed: () {
                          setState(() {
                            comment.text = controller.text;
                            if (isNew && comment.text.trim().isNotEmpty) {
                              _pageComments.putIfAbsent(pageNumber, () => []).add(comment);
                            }
                            _store.saveComments(pageNumber, _pageComments[pageNumber] ?? []);
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text("حفظ", style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                  ]);
            }));
  }

  /// يحدد اتجاه النص تلقائياً بناءً على أول حرف قوي (نفس منطق أداة النص الجديدة)
  /// لإصلاح مشكلة خلط النص العربي والإنجليزي في الملاحظات.
  TextDirection _autoDirection(String text) {
    for (final rune in text.runes) {
      if (rune >= 0x0600 && rune <= 0x06FF) return TextDirection.rtl;
      if ((rune >= 0x0041 && rune <= 0x005A) || (rune >= 0x0061 && rune <= 0x007A)) {
        return TextDirection.ltr;
      }
    }
    return TextDirection.rtl;
  }

  // --- منطق أداة النص (Text Tool) ---

  void _editTextNote(int pageNumber, dynamic note, {bool isNew = false}) {
    final controller = TextEditingController(text: note.text as String);
    // نسخة مؤقتة من الخصائص للمعاينة الفورية قبل الحفظ
    int previewColor = note.color as int;
    double previewFontSize = note.fontSize as double;
    bool previewBold = note.bold as bool;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // معاينة حية للنص
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundPrimary,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Color(previewColor).withOpacity(0.5)),
                  ),
                  child: Text(
                    controller.text.isNotEmpty ? controller.text : "معاينة النص...",
                    style: TextStyle(
                      color: Color(previewColor),
                      fontSize: previewFontSize * 400, // عرض نسبي للمعاينة
                      fontWeight: previewBold ? FontWeight.bold : FontWeight.normal,
                    ),
                    textDirection: _autoDirection(controller.text),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: controller,
                  autofocus: isNew,
                  maxLines: 3,
                  textDirection: _autoDirection(controller.text),
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
                  decoration: InputDecoration(
                    hintText: "اكتب النص هنا...",
                    hintStyle: TextStyle(color: AppColors.textSecondary),
                    filled: true,
                    fillColor: AppColors.backgroundPrimary,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  onChanged: (_) => setSheetState(() {}),
                ),
                const SizedBox(height: 10),
                // لوحة الألوان - معاينة فورية
                ColorPaletteRow(
                  selectedColor: Color(previewColor),
                  onColorSelected: (c) {
                    setSheetState(() => previewColor = c.value);
                    // تطبيق المعاينة الفورية على العنصر الحالي
                    _textNoteController.updateColor(pageNumber, note, c.value);
                  },
                ),
                const SizedBox(height: 8),
                // حجم الخط
                Row(
                  children: [
                    Icon(Icons.format_size, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Slider(
                        value: previewFontSize.clamp(0.010, 0.060),
                        min: 0.010,
                        max: 0.060,
                        divisions: 10,
                        activeColor: Color(previewColor),
                        inactiveColor: Color(previewColor).withOpacity(0.3),
                        onChanged: (v) {
                          setSheetState(() => previewFontSize = v);
                          _textNoteController.updateFontSize(pageNumber, note, v);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        "${(previewFontSize * 1000).toInt()}",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                // خط عريض
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text("عريض", style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    Switch(
                      value: previewBold,
                      activeColor: AppColors.accentYellow,
                      onChanged: (v) {
                        setSheetState(() => previewBold = v);
                        _textNoteController.updateBold(pageNumber, note, v);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    // زر الحذف
                    if (!isNew)
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () {
                            _textNoteController.deleteNote(pageNumber, note);
                            Navigator.pop(ctx);
                          },
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          label: const Text("حذف", style: TextStyle(color: Colors.redAccent)),
                        ),
                      ),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () {
                          note.text = controller.text;
                          _textNoteController.commitNote(pageNumber, note);
                          Navigator.pop(ctx);
                        },
                        icon: Icon(Icons.check, color: AppColors.accentYellow),
                        label: Text("حفظ", style: TextStyle(color: AppColors.accentYellow)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) {
      if (note.text.toString().trim().isEmpty) {
        _textNoteController.commitNote(pageNumber, note);
      }
    });
  }

  // --- شريط الأدوات الموحّد ---

  Widget _buildToolbar() {
    return PdfAnnotationToolbar(
      activeTool: _activeTool,
      onToolTap: (tool) => setState(() {
        _activeTool = tool;
        // مزامنة الأداة النشطة مع محرك التمييز/التسطير الحقيقي (مطلوب لتفعيل
        // معالجة التحديد بشكل صحيح في onTextSelectionChange).
        _highlightController.activeTool = tool == PdfTool.highlighter
            ? TextMarkupTool.highlight
            : (tool == PdfTool.underline ? TextMarkupTool.underline : TextMarkupTool.none);
      }),
      penColor: Color(_settings.penColor),
      penThickness: _settings.penThickness,
      penOpacity: _settings.penOpacity,
      onPenColorChanged: (c) {
        setState(() => _settings.penColor = c.value);
        _persistToolSettings();
      },
      onPenThicknessChanged: (v) {
        setState(() => _settings.penThickness = v);
        _persistToolSettings();
      },
      onPenOpacityChanged: (v) {
        setState(() => _settings.penOpacity = v);
        _persistToolSettings();
      },
      highlighterColor: Color(_settings.highlighterColor),
      highlighterOpacity: _settings.highlighterOpacity,
      onHighlighterColorChanged: (c) {
        setState(() {
          _settings.highlighterColor = c.value;
          _highlightController.highlightColor = c.value;
        });
        _persistToolSettings();
      },
      onHighlighterOpacityChanged: (v) {
        setState(() {
          _settings.highlighterOpacity = v;
          _highlightController.highlightOpacity = v;
        });
        _persistToolSettings();
      },
      underlineColor: Color(_settings.underlineColor),
      onUnderlineColorChanged: (c) {
        setState(() {
          _settings.underlineColor = c.value;
          _highlightController.underlineColor = c.value;
        });
        _persistToolSettings();
      },
      eraserSize: _eraserSize,
      onEraserSizeChanged: (v) => setState(() => _eraserSize = v),
      textColor: Color(_settings.textColor),
      onTextColorChanged: (c) {
        setState(() {
          _settings.textColor = c.value;
          _textNoteController.defaultColor = c.value;
        });
        _persistToolSettings();
      },
      textFontSize: _settings.textFontSize,
      onTextFontSizeChanged: (v) {
        setState(() {
          _settings.textFontSize = v;
          _textNoteController.defaultFontSize = v;
        });
        _persistToolSettings();
      },
      textBold: _textNoteController.defaultBold,
      onTextBoldChanged: (v) {
        setState(() => _textNoteController.defaultBold = v);
      },
      shapeType: _shapeController.activeType,
      onShapeTypeChanged: (t) => setState(() => _shapeController.activeType = t),
      shapeBorderColor: Color(_settings.shapeBorderColor),
      onShapeBorderColorChanged: (c) {
        setState(() {
          _settings.shapeBorderColor = c.value;
          _shapeController.borderColor = c.value;
        });
        _persistToolSettings();
      },
      shapeFillColor: _settings.shapeFillColor != null ? Color(_settings.shapeFillColor!) : null,
      onShapeFillColorChanged: (c) {
        setState(() {
          _settings.shapeFillColor = c?.value;
          _shapeController.fillColor = c?.value;
        });
        _persistToolSettings();
      },
      shapeBorderWidth: _settings.shapeBorderWidth,
      onShapeBorderWidthChanged: (v) {
        setState(() {
          _settings.shapeBorderWidth = v;
          _shapeController.borderWidth = v;
        });
        _persistToolSettings();
      },
      onUndo: _handleUndo,
      onPickImage: () => _imageController.pickAndAddImage(_activePage),
      palmRejectionEnabled: _settings.palmRejectionEnabled,
      onPalmRejectionChanged: (enabled) {
        setState(() {
          _settings.palmRejectionEnabled = enabled;
          _palmFilter.enabled = enabled;
        });
        _persistToolSettings();
      },
    );
  }

  void _handleUndo() {
    if (_activeTool == PdfTool.pen || _activeTool == PdfTool.eraser) {
      if (_pageDrawings[_activePage]?.isNotEmpty ?? false) {
        setState(() => _pageDrawings[_activePage]!.removeLast());
        _store.saveDrawings(_activePage, _pageDrawings[_activePage]!);
      }
    }
  }
}

/// رسّام موحّد للرسم الحر (القلم/الممحاة) والأشكال (مع معاينة فورية أثناء السحب).
class _CombinedOverlayPainter extends CustomPainter {
  final List<DrawingLine> lines;
  final List<ShapeModel> shapes;
  final ShapeModel? shapePreview;
  final Size pageSize;
  final PdfShapeController shapeController;

  _CombinedOverlayPainter({
    required this.lines,
    required this.shapes,
    required this.shapePreview,
    required this.pageSize,
    required this.shapeController,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    for (var line in lines) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = line.strokeWidth * pageSize.width;

      if (line.isEraser) {
        paint.blendMode = BlendMode.clear;
        paint.color = Colors.transparent;
      } else {
        paint.color = Color(line.color).withOpacity(line.opacity);
      }

      if (line.points.length > 1) {
        final path = Path();
        path.moveTo(line.points[0].dx * pageSize.width, line.points[0].dy * pageSize.height);
        for (int i = 1; i < line.points.length; i++) {
          path.lineTo(line.points[i].dx * pageSize.width, line.points[i].dy * pageSize.height);
        }
        canvas.drawPath(path, paint);
      } else if (line.points.isNotEmpty) {
        var p = Offset(line.points[0].dx * pageSize.width, line.points[0].dy * pageSize.height);
        canvas.drawPoints(PointMode.points, [p], paint);
      }
    }
    canvas.restore();

    shapeController.paintShapes(canvas, pageSize, shapes, preview: shapePreview);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
