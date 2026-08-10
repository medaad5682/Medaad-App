import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

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
  // ── Fix: first-open stuck loading ──
  // _pdfController is declared nullable and only initialized inside _preparePdf()
  // so it is never attached to a PdfViewer until the document is ready.
  // A new UniqueKey + new controller are assigned together, guaranteeing a
  // completely fresh widget subtree on every open (including the very first one
  // after app launch where Flutter might otherwise reuse stale internal state).
  Key _viewerKey = UniqueKey();

  // Null until _preparePdf() succeeds; the build() method guards against null.
  PdfViewerController? _pdfController;
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

  // ── Smooth drawing: ValueNotifier per page so only the canvas layer
  //    repaints on every pan event instead of the whole widget tree.
  final Map<int, ValueNotifier<DrawingLine?>> _strokeNotifiers = {};

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

  // ── Fix: مشكلة عدم ظهور التمييز/التسطير على بعض الصفحات ──
  // نستمع لتغييرات حالة صفحات الوثيقة (PdfDocumentPageStatusChangedEvent)
  // التي يُصدرها pdfrx داخلياً كل مرة يستبدل فيها صفحة "placeholder" مؤقتة
  // (كانت لا تزال قيد التحميل التدريجي) بالصفحة الحقيقية المحمّلة فعلياً من
  // PDFium. عند حدوث ذلك، أي نص (PdfPageText) قمنا بتخزينه مسبقاً لتلك
  // الصفحة قد يكون فارغاً/غير موثوق (راجع تعليق PdfPageTextCache.ensureLoaded)
  // لذلك نُبطله هنا فوراً لإجبار إعادة حسابه من الصفحة الحقيقية، مما يجعل
  // أي تمييز/تسطير مخزّن على تلك الصفحة يظهر بصرياً في أول إعادة رسم بعد ذلك.
  StreamSubscription<PdfDocumentEvent>? _documentEventsSubscription;

  @override
  void initState() {
    super.initState();
    _sessionToken = _generateSecureToken();
    _store = PdfAnnotationStore(widget.pdfId);
    // ── Fix: "Null check operator used on a null value" في setState ──
    // كل هذه الـ controllers تنفّذ عمليات غير متزامنة (مثل تحميل نص
    // الصفحة) وتستدعي onChanged() لاحقاً بعد اكتمالها. إن أغلق المستخدم
    // الشاشة (زر الرجوع) قبل اكتمال هذه العملية — وهو بالضبط ما يحدث عند
    // الفتح الأول البطيء بعد إغلاق التطبيق — يُستدعى onChanged() على شاشة
    // تم التخلص منها (disposed)، فيحاول setState() الوصول لعنصر (element)
    // لم يعد موجوداً فيرمي هذا الخطأ ويُسقط التطبيق بالكامل. فحص `mounted`
    // هنا يجعل onChanged() لا تفعل شيئاً بأمان إن كانت الشاشة قد أُغلقت.
    _highlightController = PdfHighlightController(
      store: _store,
      textCache: _textCache,
      onChanged: () {
        if (!mounted) return;
        setState(() {});
      },
    );
    _shapeController = PdfShapeController(
      store: _store,
      onChanged: () {
        if (!mounted) return;
        setState(() {});
      },
    );
    _textNoteController = PdfTextNoteController(
      store: _store,
      onChanged: () {
        if (!mounted) return;
        setState(() {});
      },
    );
    _imageController = PdfImageAnnotationController(
      pdfId: widget.pdfId,
      store: _store,
      onChanged: () {
        if (!mounted) return;
        setState(() {});
      },
    );
    _initWatermarkText();
    _loadToolSettings();
    _preparePdf();
  }

  @override
  void dispose() {
    if (_isOffline) _saveAnnotationsToHive();
    _documentEventsSubscription?.cancel();
    for (final n in _strokeNotifiers.values) {
      n.dispose();
    }
    super.dispose();
  }

  /// يربط الاستماع لأحداث الوثيقة (تغيّر حالة الصفحات) بمجرد توفر المستند،
  /// لإبطال ذاكرة نص الصفحات المؤقتة عند اكتمال تحميل أي صفحة فعلياً.
  void _attachDocumentEventsListener(PdfDocument? document) {
    _documentEventsSubscription?.cancel();
    _documentEventsSubscription = null;
    if (document == null) return;

    _documentEventsSubscription = document.events.listen((event) {
      if (!mounted) return;
      if (event is PdfDocumentPageStatusChangedEvent) {
        for (final pageNumber in event.changes.keys) {
          _textCache.invalidate(pageNumber);
        }
        // إعادة رسم فورية بدل انتظار إعادة الرسم الطبيعية القادمة، لأي صفحة
        // قد تحتوي تمييزاً/تسطيراً محفوظاً مسبقاً ولم يكن قد ظهر بصرياً بعد.
        setState(() {});
      }
    });
  }

  String _generateSecureToken() {
    final random = math.Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64Url.encode(values);
  }

  Future<int> _customRead(Uint8List buffer, int position, int size) async {
    try {
      if (_sessionToken == null) throw Exception("Unauthorized access context");
      if (_encryptedFile == null) throw Exception("File not initialized");

      final decryptedData = await FileCryptoService.readAndDecryptRange(
          _encryptedFile!, position, size);

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
      displayText = AppState().userData!['phone'] != null
          ? AppState().userData!['phone']
          : '';
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
      setState(() => _watermarkText = displayText.isNotEmpty
          ? displayText
          : AppState().userData!['username'] ?? 'Unknown User');
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
      // ✅ تطبيق الإعدادات المحفوظة للملاحظات على المتحكم مباشرة
      _textNoteController.defaultColor = settings.textColor;
      _textNoteController.defaultFontSize = settings.textFontSize;
      // سماكة الهايلايتر الحر محفوظة في _settings.freehandHighlighterThickness
    });
  }

  Future<void> _persistToolSettings() =>
      PdfAnnotationStore.saveGlobalSettings(_settings);

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

          int numChunks =
              (totalSize / FileCryptoService.ENCRYPTED_CHUNK_SIZE).ceil();
          // ── Fix: PDF crash on specific offline files (EXC_BREAKPOINT in
          // PDFium RebuildCrossRef) ──
          // Each chunk on disk has NONCE_LENGTH + MAC_LENGTH bytes of overhead,
          // not just NONCE_LENGTH. Omitting MAC_LENGTH here made
          // `originalSize` (the size we tell pdfrx/PDFium the decrypted PDF
          // is) too large by (MAC_LENGTH * numChunks) bytes. For files where
          // that drift pushed PDFium's reads past the real end of the
          // decrypted stream, it read garbage/short data for the xref
          // table/trailer, fell back to RebuildCrossRef, and crashed while
          // parsing the corrupted object stream. This matches
          // FileCryptoService.readAndDecryptRange's own chunk math and the
          // (correct) equivalent calculation in local_proxy.dart.
          int originalSize = totalSize -
              (numChunks *
                  (FileCryptoService.NONCE_LENGTH +
                      FileCryptoService.MAC_LENGTH));

          if (mounted) {
            // ── Fix: force fresh PdfViewer to avoid first-open stuck loading ──
            // Create the controller INSIDE setState so it is never attached to
            // any widget until this exact rebuild — preventing a stale-controller
            // race on the first open after app launch.
            setState(() {
              _isOffline = true;
              _encryptedFile = file;
              _originalFileSize = originalSize;
              _pdfController = PdfViewerController();
              _viewerKey = UniqueKey();
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

      // ✅ 1. محاولة جلب توكن Firebase App Check
      String? appCheckToken;
      try {
        appCheckToken = await FirebaseAppCheck.instance.getToken(false).timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint("App Check Error in PDF: $e");
      }

      // ✅ 2. بناء الترويسات الأساسية
      _onlineHeaders = {
        'Authorization': 'Bearer $token',
        'x-device-id': deviceId ?? '',
        'x-app-secret': 'My_Sup3r_S3cr3t_K3y_For_Android_App_Only',
      };

      // ✅ 3. إضافة توكن الحماية في حال نجاح جلبه
      if (appCheckToken != null) {
        _onlineHeaders!['X-Firebase-AppCheck'] = appCheckToken;
      }

      _onlineUrl =
          '${ApiConstants.apiUrl}/secure/get-pdf?pdfId=${widget.pdfId}';

      if (mounted) {
        // ── Fix: force fresh PdfViewer to avoid first-open stuck loading ──
        // Create the controller INSIDE setState so it is never attached to
        // any widget until this exact rebuild — preventing a stale-controller
        // race on the first open after app launch.
        setState(() {
          _pdfController = PdfViewerController();
          _viewerKey = UniqueKey();
          _loading = false;
        });
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance
          .recordError(e, stack, reason: "PDF Secure Load Failed");
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
    // _pdfController is guaranteed non-null here: _preparePdf() always
    // assigns it before setting _loading = false.
    final controller = _pdfController!;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.backgroundPrimary,
      endDrawer: _buildPageDrawer(),
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          _isOffline && _encryptedFile != null && _originalFileSize != null
              ? PdfViewer.custom(
                  key: _viewerKey,
                  fileSize: _originalFileSize!,
                  read: _customRead,
                  sourceName: _encryptedFile!.path,
                  controller: controller,
                  params: _buildPdfParams(),
                )
              : PdfViewer.uri(
                  key: _viewerKey,
                  Uri.parse(_onlineUrl!),
                  headers: _onlineHeaders,
                  controller: controller,
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
                style: TextStyle(
                    color: AppColors.accentYellow,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(
            backgroundColor: Colors.transparent,
            leading: const BackButton(color: Colors.white)),
        body: Center(
            child: Text(_error!, style: const TextStyle(color: Colors.white))));
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
        IconButton(
          icon: Icon(LucideIcons.list, color: AppColors.accentYellow),
          onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
        ),
      ],
    );
  }

  Widget _buildBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _isOffline
            ? Colors.green.withOpacity(0.2)
            : Colors.blue.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: _isOffline ? Colors.green : Colors.blue, width: 1),
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
            color: _isDrawingMode ? Colors.black : AppColors.accentYellow,
            size: 16),
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
                    color: AppColors.accentYellow,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ),
          const Divider(color: Colors.white10),
          Expanded(
            child: _totalPages == 0
                ? Center(
                    child: CircularProgressIndicator(
                        color: AppColors.accentYellow))
                : ListView.builder(
                    itemCount: _totalPages,
                    itemBuilder: (context, index) {
                      final pageNum = index + 1;
                      final isCurrent = _pdfController?.pageNumber == pageNum;
                      return ListTile(
                        title: Text("صفحة $pageNum",
                            style: TextStyle(
                                color: isCurrent
                                    ? AppColors.accentYellow
                                    : AppColors.textPrimary,
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal)),
                        leading: Icon(LucideIcons.fileText,
                            color: isCurrent
                                ? AppColors.accentYellow
                                : AppColors.textSecondary,
                            size: 18),
                        onTap: () {
                          _pdfController?.goToPage(pageNumber: pageNum);
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
    return PdfViewerParams(
      backgroundColor: AppColors.backgroundPrimary,
      layoutPages: PdfLayoutEngine.layout,
      pageAnchor: PdfLayoutEngine.anchorStart,
      pageAnchorEnd: PdfLayoutEngine.anchorEnd,
      scrollHorizontallyByMouseWheel:
          PdfLayoutEngine.scrollHorizontallyByMouseWheel,
      scrollPhysics: PdfLayoutEngine.scrollPhysics,
      // ✅ تحديد النص: يُفعَّل دائماً في وضع الهايلايتر/التسطير مع إتاحة الوقت
      // للمستخدم لضبط نقطتَي البداية والنهاية قبل تطبيق التمييز.
      textSelectionParams: PdfTextSelectionParams(
        enabled: _isDrawingMode &&
            (_activeTool == PdfTool.highlighter ||
                _activeTool == PdfTool.underline),
        onTextSelectionChange: (selection) {
          // نحفظ التحديد فقط دون تطبيق — يُطبَّق عبر زر القائمة
          _highlightController.updatePendingSelection(selection);
          // ── Fix: pre-warm text cache eagerly as soon as the user starts selecting ──
          // هذا يحل مشكلة الصفحات التي لا تستجيب للتمييز/التسطير:
          // عند بدء التحديد نبدأ تحميل نص الصفحة النشطة فوراً بشكل غير متزامن
          // حتى يكون الكاش جاهزاً عند الضغط على زر التمييز/التسطير.
          if (selection.hasSelectedText && _pdfController != null) {
            final pageNum = _activePage > 0 ? _activePage : 1;
            _textCache.ensureLoadedByPageNumber(pageNum, _pdfController!);
          }
        },
      ),
      // قائمة السياق: تعرض أزرار "تمييز"/"تسطير" و"تعديل" (للعناصر الموجودة).
      // التطبيق يحدث هنا — بعد أن يضبط المستخدم نقطتَي التحديد.
      buildContextMenu: (context, params) {
        if (!_isDrawingMode) return null;
        if (_activeTool != PdfTool.highlighter &&
            _activeTool != PdfTool.underline) return null;
        final label = _activeTool == PdfTool.highlighter ? 'تمييز' : 'تسطير';
        return Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 6)
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // زر التمييز / التسطير
                TextButton.icon(
                  onPressed: () async {
                    await _highlightController
                        .applyPendingSelection(_pdfController!);
                  },
                  icon: Icon(
                    _activeTool == PdfTool.highlighter
                        ? Icons.format_color_fill
                        : Icons.format_underline,
                    color: AppColors.accentYellow,
                    size: 18,
                  ),
                  label: Text(label,
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 14)),
                ),
                // فاصل
                Container(
                  width: 1,
                  height: 24,
                  color: AppColors.textSecondary.withOpacity(0.3),
                ),
                // زر تعديل: يكتشف أي تمييز/تسطير يتداخل مع التحديد الحالي ويفتح نافذة التعديل
                TextButton.icon(
                  onPressed: () async {
                    final ranges = await _highlightController
                        .getPendingSelectionRanges(_pdfController!);
                    if (ranges.isEmpty) return;
                    for (final r in ranges) {
                      final result = _highlightController.findOverlappingMarkup(
                        pageNumber: r.pageNumber,
                        selectionStart: r.start,
                        selectionEnd: r.end,
                      );
                      if (result.highlight != null ||
                          result.underline != null) {
                        if (mounted) {
                          _showMarkupEditSheet(
                            highlight: result.highlight,
                            underline: result.underline,
                            pageNumber: r.pageNumber,
                          );
                        }
                        return;
                      }
                    }
                    // لم يُعثر على عنصر متداخل
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'لا يوجد تمييز أو تسطير في هذا التحديد',
                            style: TextStyle(color: AppColors.textPrimary),
                          ),
                          backgroundColor: AppColors.backgroundSecondary,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  icon: Icon(Icons.edit_outlined,
                      color: AppColors.accentYellow, size: 18),
                  label: Text('تعديل',
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 14)),
                ),
              ],
            ),
          ),
        );
      },
      pagePaintCallbacks: [
        _highlightController.paint,
      ],
      loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
        return Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.black54, borderRadius: BorderRadius.circular(12)),
            child: CircularProgressIndicator(color: AppColors.accentYellow),
          ),
        );
      },
      onDocumentChanged: (document) {
        _attachDocumentEventsListener(document);
        if (mounted) setState(() => _totalPages = document?.pages.length ?? 0);
      },
      onPageChanged: (pageNumber) {
        if (pageNumber != null) {
          _activePage = pageNumber;
          // ── Fix (highlight/underline): pre-warm text cache for the new page
          // and its immediate neighbours so getSelectedTextRanges never races
          // against an empty cache on any page.
          if (_pdfController != null) {
            final ctrl = _pdfController!;
            final doc = ctrl.document;
            if (doc != null) {
              final total = doc.pages.length;
              for (int p = (pageNumber - 1).clamp(1, total);
                  p <= (pageNumber + 1).clamp(1, total);
                  p++) {
                _textCache.ensureLoadedByPageNumber(p, ctrl);
              }
            }
          }
        }
      },
      pageOverlaysBuilder: (context, pageRect, page) {
        // تحميل نص الصفحة مسبقاً (للتمييز/التسطير)
        // ── Fix: also pre-warm the page before and after, so that when the
        // user scrolls half a page and selects text the cache is already hot.
        _textCache.ensureLoaded(page);
        if (_pdfController != null) {
          final doc = _pdfController!.document;
          if (doc != null) {
            final total = doc.pages.length;
            if (page.pageNumber > 1) {
              _textCache.ensureLoadedByPageNumber(
                  page.pageNumber - 1, _pdfController!);
            }
            if (page.pageNumber < total) {
              _textCache.ensureLoadedByPageNumber(
                  page.pageNumber + 1, _pdfController!);
            }
          }
        }

        return [
          Positioned.fill(
            child: FutureBuilder(
              future: _isOffline
                  ? _loadAnnotationsForPage(page.pageNumber)
                  : Future.value(),
              builder: (context, snapshot) {
                final lines = _pageDrawings[page.pageNumber] ?? [];
                // _currentLine is now tracked by _strokeNotifierFor; we no longer
                // add it to allLines here so the outer FutureBuilder stays stable.
                final allLines = [...lines];

                final comments = _isOffline
                    ? (_pageComments[page.pageNumber] ?? [])
                    : <dynamic>[];
                final shapes = _shapeController.shapesForPage(page.pageNumber);
                final shapePreview =
                    _shapeController.drawingShapeForPage(page.pageNumber);
                final textNotes =
                    _textNoteController.notesForPage(page.pageNumber);
                final images = _imageController.imagesForPage(page.pageNumber);

                return Stack(
                  children: [
                    // طبقة الصور المُدرجة (أسفل طبقة الأشكال حتى تُرسم الأشكال فوقها)
                    ...images.map((img) => Positioned(
                          left: img.dx * pageRect.width,
                          top: img.dy * pageRect.height,
                          // ── Fix (image tool): removed the GestureDetector onTap that
                          // used to auto-switch _activeTool to PdfTool.image when the
                          // user tapped an existing image. That caused scrolling, panning
                          // and zooming to freeze because the viewer's internal gesture
                          // arena was captured by the image-tool overlay.
                          // Images are now always editable (movable/resizable/deletable)
                          // while in drawing mode regardless of which tool is active,
                          // and tapping one does NOT change the active tool.
                          child: MovableResizableImage(
                            image: img,
                            pageWidth: pageRect.width,
                            pageHeight: pageRect.height,
                            editable: _isDrawingMode,
                            onMoveDelta: (delta) => _imageController.moveImage(
                                page.pageNumber, img, delta),
                            onResizeDelta: (delta) => _imageController
                                .resizeImage(page.pageNumber, img, delta),
                            onResizeEnd: (fw, fh) => _imageController
                                .setFinalSize(page.pageNumber, img, fw, fh),
                            onMoveEnd: (fdx, fdy) =>
                                _imageController.setFinalPosition(
                                    page.pageNumber, img, fdx, fdy),
                            onDelete: () => _imageController.deleteImage(
                                page.pageNumber, img),
                          ),
                        )),

                    // طبقة الرسم الحر (القلم/الممحاة/هايلايتر حر) + الأشكال (رسم جديد)
                    // هذه الطبقة فوق الصور حتى تُرسم الأشكال والتعليقات فوق الصور.
                    // ملاحظة: نستخدم HitTestBehavior.translucent بدلاً من opaque حتى
                    // لا تمتص هذه الطبقة اللمسات الموجهة للملاحظات والصور فوقها.
                    IgnorePointer(
                      ignoring: !_isDrawingMode ||
                          _activeTool == PdfTool.none ||
                          _activeTool == PdfTool.highlighter ||
                          _activeTool == PdfTool.underline,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTapUp: (details) =>
                            _handleTapUp(details, context, pageRect, page),
                        onPanStart: (details) =>
                            _handlePanStart(details, context, pageRect, page),
                        onPanUpdate: (details) =>
                            _handlePanUpdate(details, context, pageRect, page),
                        onPanEnd: (details) => _handlePanEnd(page, pageRect),
                        // ── Smooth drawing: ValueListenableBuilder scopes repaints
                        //    to this CustomPaint only — the outer FutureBuilder /
                        //    Stack are NOT rebuilt on every touch event.
                        child: ValueListenableBuilder<DrawingLine?>(
                          valueListenable: _strokeNotifierFor(page.pageNumber),
                          builder: (_, liveStroke, __) {
                            final displayLines = liveStroke != null
                                ? [...allLines, liveStroke]
                                : allLines;
                            return CustomPaint(
                              isComplex: true,
                              willChange: liveStroke != null,
                              painter: _CombinedOverlayPainter(
                                lines: displayLines,
                                shapes: shapes,
                                shapePreview: shapePreview,
                                pageSize: pageRect.size,
                                shapeController: _shapeController,
                              ),
                              size: Size.infinite,
                            );
                          },
                        ),
                      ),
                    ),

                    // طبقة الأشكال القابلة للسحب (تعمل حتى بدون تفعيل أداة الأشكال)
                    if (_isDrawingMode)
                      ...shapes.map((shape) {
                        final left = math.min(shape.startDx, shape.endDx) *
                            pageRect.width;
                        final top = math.min(shape.startDy, shape.endDy) *
                            pageRect.height;
                        final right = math.max(shape.startDx, shape.endDx) *
                            pageRect.width;
                        final bottom = math.max(shape.startDy, shape.endDy) *
                            pageRect.height;
                        return Positioned(
                          left: left,
                          top: top,
                          width: right - left,
                          height: bottom - top,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            // السحب لتحريك الشكل
                            onPanUpdate: _activeTool == PdfTool.shape ||
                                    _activeTool == PdfTool.none
                                ? (details) => _shapeController.moveShape(
                                      shape,
                                      page.pageNumber,
                                      Offset(
                                        details.delta.dx / pageRect.width,
                                        details.delta.dy / pageRect.height,
                                      ),
                                    )
                                : null,
                            // النقر لفتح نافذة التعديل
                            onTap: () => _tryEditExistingShape(
                              Offset(
                                (left + (right - left) / 2) / pageRect.width,
                                (top + (bottom - top) / 2) / pageRect.height,
                              ),
                              page.pageNumber,
                            ),
                            child: const SizedBox.expand(),
                          ),
                        );
                      }),

                    // طبقة النصوص المكتوبة
                    ...textNotes.map((note) => Positioned(
                          left: note.dx * pageRect.width,
                          top: note.dy * pageRect.height,
                          child: MovableTextNote(
                            note: note,
                            pageWidth: pageRect.width,
                            // ✅ الملاحظات قابلة للسحب في أي وضع تعديل (كشف ذكي)
                            // النقر يفتح المحرر فقط إذا كانت أداة النص نشطة أو none
                            editable: _isDrawingMode,
                            onDragDelta: (delta) => _textNoteController
                                .moveNote(page.pageNumber, note, delta),
                            onTap: () {
                              if (_isDrawingMode) {
                                // تفعيل أداة النص تلقائياً عند النقر على مربع نص
                                if (_activeTool != PdfTool.text) {
                                  setState(() {
                                    _activeTool = PdfTool.text;
                                    _highlightController.activeTool =
                                        TextMarkupTool.none;
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

                    // طبقة أيقونات الملاحظات (Comments) - نفس المنطق الأصلي
                    ...comments.map((comment) {
                      Color solidColor = Color(comment.color).withOpacity(1.0);
                      double currentOpacity = Color(comment.color).opacity;

                      return Positioned(
                        left: (comment.dx * pageRect.width) -
                            (20 * comment.scale),
                        top: (comment.dy * pageRect.height) -
                            (20 * comment.scale),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          // السحب يعمل في وضع التعديل بغض النظر عن الأداة النشطة
                          onScaleStart: _isDrawingMode ? (_) {} : null,
                          onScaleEnd: _isDrawingMode ? (_) {} : null,
                          onScaleUpdate: _isDrawingMode
                              ? (details) {
                                  setState(() {
                                    if (details.pointerCount == 1) {
                                      comment.dx += details.focalPointDelta.dx /
                                          pageRect.width;
                                      comment.dy += details.focalPointDelta.dy /
                                          pageRect.height;
                                    }
                                  });
                                }
                              : null,
                          onTap: () =>
                              _showCommentDialog(page.pageNumber, comment),
                          child: Transform.scale(
                            scale: comment.scale,
                            child: Opacity(
                              opacity: currentOpacity,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: AppColors.backgroundSecondary
                                        .withOpacity(0.85),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: solidColor, width: 1.5),
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black.withOpacity(0.4),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2))
                                    ]),
                                child: Icon(Icons.comment_rounded,
                                    color: solidColor, size: 24),
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

  /// Returns (or lazily creates) the per-page ValueNotifier used to push
  /// live stroke updates without rebuilding the whole widget tree.
  ValueNotifier<DrawingLine?> _strokeNotifierFor(int pageNumber) {
    return _strokeNotifiers.putIfAbsent(
        pageNumber, () => ValueNotifier<DrawingLine?>(null));
  }

  void _handleTapUp(
      TapUpDetails details, BuildContext context, Rect pageRect, PdfPage page) {
    if (!_isDrawingMode) return;
    if (!_palmAllows(details.kind)) return;

    final renderBox = context.findRenderObject() as RenderBox;
    final localPos = renderBox.globalToLocal(details.globalPosition);
    final relativePoint =
        Offset(localPos.dx / pageRect.width, localPos.dy / pageRect.height);

    switch (_activeTool) {
      case PdfTool.comment:
        _addComment(relativePoint, page.pageNumber);
        break;
      case PdfTool.text:
        final note =
            _textNoteController.addNote(page.pageNumber, relativePoint);
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
      case PdfTool.none:
        // كشف ذكي: النقر على شكل موجود يفتح نافذة التعديل حتى بدون تفعيل أداة الأشكال
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
    final pdfPoint =
        localPos.toPdfPoint(page: page, scaledPageSize: pageRect.size);
    final result = _highlightController.hitTest(
      pageNumber: page.pageNumber,
      pdfX: pdfPoint.x,
      pdfY: pdfPoint.y,
    );
    if (result.highlight != null) {
      _showMarkupEditSheet(
          highlight: result.highlight, pageNumber: page.pageNumber);
    } else if (result.underline != null) {
      _showMarkupEditSheet(
          underline: result.underline, pageNumber: page.pageNumber);
    }
  }

  void _showMarkupEditSheet(
      {HighlightModel? highlight,
      UnderlineModel? underline,
      required int pageNumber}) {
    final isHighlight = highlight != null;
    final currentColor =
        Color(isHighlight ? highlight!.color : underline!.color);

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
                style: TextStyle(
                    color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ColorPaletteRow(
              selectedColor: currentColor,
              onColorSelected: (c) {
                if (isHighlight) {
                  _highlightController.updateHighlightColor(
                      highlight!, c.value);
                } else {
                  _highlightController.updateUnderlineColor(
                      underline!, c.value);
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

    // حساب الحجم الحالي كنسبة مئوية للاستخدام في slider التكبير/التصغير
    // نبدأ دائماً من 1.0 (الحجم الحالي للشكل = 100%)
    double sizeScale = 1.0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("تعديل الشكل",
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              // ── شريط تغيير الحجم ──
              Row(
                children: [
                  Icon(Icons.photo_size_select_large,
                      size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: sizeScale.clamp(0.2, 3.0),
                      min: 0.2,
                      max: 3.0,
                      divisions: 28,
                      activeColor: AppColors.accentYellow,
                      inactiveColor: AppColors.accentYellow.withOpacity(0.3),
                      onChanged: (v) {
                        // نحسب نسبة التغيير بالنسبة للقيمة الحالية للـ slider
                        final factor = v / sizeScale;
                        _shapeController.resizeShape(shape, pageNumber, factor);
                        setSheetState(() => sizeScale = v);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    child: Text(
                      "${(sizeScale * 100).toInt()}%",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ),
                ],
              ),
              Text("الحدود",
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ColorPaletteRow(
                selectedColor: Color(shape.borderColor),
                onColorSelected: (c) {
                  _shapeController.updateBorderColor(
                      shape, pageNumber, c.value);
                  setSheetState(() {});
                },
              ),
              // سماكة الحدود
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.line_weight,
                      size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: shape.borderWidth.clamp(0.001, 0.02),
                      min: 0.001,
                      max: 0.02,
                      activeColor: Color(shape.borderColor),
                      inactiveColor: Color(shape.borderColor).withOpacity(0.3),
                      onChanged: (v) {
                        _shapeController.updateBorderWidth(
                            shape, pageNumber, v);
                        setSheetState(() {});
                      },
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      "${(shape.borderWidth * 1000).toInt()}",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ),
                ],
              ),
              // خيار التعبئة (مخفي للسهم)
              if (shape.type != ShapeType.arrow) ...[
                const SizedBox(height: 8),
                Text("التعبئة",
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                ColorPaletteRow(
                  selectedColor: shape.fillColor != null
                      ? Color(shape.fillColor!)
                      : Colors.transparent,
                  isTransparentSelected: shape.fillColor == null,
                  allowTransparentOption: true,
                  onTransparentSelected: () {
                    _shapeController.updateFillColor(shape, pageNumber, null);
                    setSheetState(() {});
                  },
                  onColorSelected: (c) {
                    _shapeController.updateFillColor(
                        shape, pageNumber, c.value);
                    setSheetState(() {});
                  },
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: () {
                    _shapeController.deleteShape(shape, pageNumber);
                    Navigator.pop(ctx);
                  },
                  icon:
                      const Icon(Icons.delete_outline, color: Colors.redAccent),
                  label: const Text("حذف الشكل",
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handlePanStart(DragStartDetails details, BuildContext context,
      Rect pageRect, PdfPage page) {
    if (!_isDrawingMode) return;
    if (!_palmAllows(details.kind)) return;

    final renderBox = context.findRenderObject() as RenderBox;
    final localPos = renderBox.globalToLocal(details.globalPosition);
    final relativePoint =
        Offset(localPos.dx / pageRect.width, localPos.dy / pageRect.height);

    if (_activeTool == PdfTool.pen ||
        _activeTool == PdfTool.eraser ||
        _activeTool == PdfTool.freehandHighlighter) {
      _activePage = page.pageNumber;
      DrawingLine newLine;
      if (_activeTool == PdfTool.freehandHighlighter) {
        // هايلايتر حر: خط عريض شفاف بنمط تمييز
        newLine = DrawingLine(
          points: [relativePoint],
          color: _settings.highlighterColor,
          strokeWidth: _settings.freehandHighlighterThickness,
          isHighlighter: true,
          isEraser: false,
          opacity: _settings.highlighterOpacity,
        );
      } else {
        newLine = DrawingLine(
          points: [relativePoint],
          color: _activeTool == PdfTool.eraser ? 0 : _settings.penColor,
          strokeWidth: _activeTool == PdfTool.eraser
              ? _eraserSize
              : _settings.penThickness,
          isHighlighter: false,
          isEraser: _activeTool == PdfTool.eraser,
          opacity: _activeTool == PdfTool.eraser ? 1.0 : _settings.penOpacity,
        );
      }
      _currentLine = newLine;
      // Push to notifier — no setState, so the whole tree is NOT rebuilt.
      _strokeNotifierFor(page.pageNumber).value = newLine;
    } else if (_activeTool == PdfTool.shape) {
      _shapeController.startDrawing(page.pageNumber, relativePoint);
    }
  }

  void _handlePanUpdate(DragUpdateDetails details, BuildContext context,
      Rect pageRect, PdfPage page) {
    if (!_isDrawingMode) return;
    if (!_palmAllows(details.kind)) return;

    final renderBox = context.findRenderObject() as RenderBox;
    final localPos = renderBox.globalToLocal(details.globalPosition);
    final relativePoint =
        Offset(localPos.dx / pageRect.width, localPos.dy / pageRect.height);

    if (_activeTool == PdfTool.pen ||
        _activeTool == PdfTool.eraser ||
        _activeTool == PdfTool.freehandHighlighter) {
      if (_currentLine != null) {
        // Minimum-distance filter — keeps enough points for smooth curves
        // while avoiding redundant work from identical touch samples.
        // 0.00001 ≈ 1 px on a 100 pt-wide page (tighter than the old 0.00003
        // which dropped too many points and made curves look angular).
        const double minDistSq = 0.00001;
        final pts = _currentLine!.points;
        if (pts.isNotEmpty) {
          final last = pts.last;
          final dx = relativePoint.dx - last.dx;
          final dy = relativePoint.dy - last.dy;
          if (dx * dx + dy * dy < minDistSq) return;
        }
        // Mutate the list directly (no copy) then kick the ValueNotifier.
        // This does NOT call setState, so the widget tree is untouched —
        // only the CustomPaint inside ValueListenableBuilder repaints.
        _currentLine!.points.add(relativePoint);
        // Trigger notifier with same object reference — listeners rebuild.
        final notifier = _strokeNotifierFor(page.pageNumber);
        notifier.value =
            null; // force ValueListenableBuilder to detect a change
        notifier.value = _currentLine;
      }
    } else if (_activeTool == PdfTool.shape) {
      _shapeController.updateDrawing(relativePoint);
    }
  }

  void _handlePanEnd(PdfPage page, Rect pageRect) {
    if (_activeTool == PdfTool.pen ||
        _activeTool == PdfTool.eraser ||
        _activeTool == PdfTool.freehandHighlighter) {
      if (_currentLine != null) {
        final committed = _currentLine!;
        _currentLine = null;
        // Clear the live-stroke notifier first (stops the preview).
        _strokeNotifierFor(page.pageNumber).value = null;
        // Now commit to persistent list and trigger a normal repaint.
        setState(() {
          _pageDrawings.putIfAbsent(page.pageNumber, () => []).add(committed);
          _store.saveDrawings(page.pageNumber, _pageDrawings[page.pageNumber]!);
        });
      }
    } else if (_activeTool == PdfTool.shape) {
      _shapeController.endDrawing(pageSize: pageRect.size);
    }
  }

  // --- منطق الملاحظات (Comments) - محافظ على نفس السلوك الأصلي تماماً ---

  void _addComment(Offset relativePoint, int pageNumber) {
    // ✅ إنشاء ملاحظة جديدة بالإعدادات الافتراضية المحفوظة (اللون + الحجم + الشفافية)
    final newComment = CommentModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: '',
      dx: relativePoint.dx,
      dy: relativePoint.dy,
      color: _commentDefaults.color, // اللون مع الشفافية المحفوظة
      scale: _commentDefaults.scale, // الحجم المحفوظ
    );
    _showCommentDialog(pageNumber, newComment, isNew: true);
  }

  void _showCommentDialog(int pageNumber, CommentModel comment,
      {bool isNew = false}) {
    TextEditingController controller =
        TextEditingController(text: comment.text);

    showDialog(
        context: context,
        barrierDismissible: !isNew,
        builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) {
              return AlertDialog(
                  backgroundColor: AppColors.backgroundSecondary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  title: Row(
                    children: [
                      Icon(Icons.comment_rounded,
                          color: Color(comment.color).withOpacity(1.0)),
                      const SizedBox(width: 8),
                      Text(isNew ? "إضافة تعليق" : "التعليق",
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 16)),
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
                            hintText: _isDrawingMode
                                ? "اكتب ملاحظاتك هنا..."
                                : "لا يوجد نص...",
                            hintStyle:
                                TextStyle(color: AppColors.textSecondary),
                            filled: true,
                            fillColor: AppColors.backgroundPrimary,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none),
                          ),
                        ),
                        if (_isDrawingMode) ...[
                          const SizedBox(height: 16),
                          ColorPaletteRow(
                            selectedColor:
                                Color(comment.color).withOpacity(1.0),
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
                            child: Text(
                                "حجم الأيقونة: ${(comment.scale).toStringAsFixed(1)}",
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12)),
                          ),
                          Slider(
                              value: comment.scale,
                              min: 0.5,
                              max: 4.0,
                              activeColor: AppColors.accentYellow,
                              inactiveColor:
                                  AppColors.accentYellow.withOpacity(0.3),
                              onChanged: (val) {
                                setDialogState(() => comment.scale = val);
                                setState(() {});
                              }),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                                "الشفافية: ${(Color(comment.color).opacity * 100).toInt()}%",
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12)),
                          ),
                          Slider(
                              value: Color(comment.color).opacity,
                              min: 0.1,
                              max: 1.0,
                              activeColor: AppColors.accentYellow,
                              inactiveColor:
                                  AppColors.accentYellow.withOpacity(0.3),
                              onChanged: (val) {
                                setDialogState(() {
                                  Color baseColor = Color(comment.color);
                                  comment.color =
                                      baseColor.withOpacity(val).value;
                                });
                                setState(() {});
                              }),
                          const SizedBox(height: 10),
                          // ✅ حفظ هذا الشكل كافتراضي للملاحظات القادمة (اللون + الشفافية + الحجم)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () {
                                // نحفظ اللون كاملاً بما فيه الشفافية
                                _commentDefaults = CommentDefaults(
                                  color: comment
                                      .color, // يتضمن قيمة الشفافية الحالية
                                  scale: comment.scale,
                                );
                                PdfAnnotationStore.saveCommentDefaults(
                                    _commentDefaults);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content:
                                          Text("تم حفظ الإعدادات الافتراضية")),
                                );
                              },
                              icon: Icon(Icons.bookmark_outline,
                                  size: 16, color: AppColors.accentYellow),
                              label: Text("حفظ كافتراضي",
                                  style: TextStyle(
                                      color: AppColors.accentYellow,
                                      fontSize: 12)),
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
                            _store.saveComments(
                                pageNumber, _pageComments[pageNumber] ?? []);
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text("حذف",
                            style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold)),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(_isDrawingMode ? "إلغاء" : "إغلاق",
                          style: const TextStyle(color: Colors.grey)),
                    ),
                    if (_isDrawingMode)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accentYellow,
                            foregroundColor: Colors.black),
                        onPressed: () {
                          setState(() {
                            comment.text = controller.text;
                            if (isNew && comment.text.trim().isNotEmpty) {
                              _pageComments
                                  .putIfAbsent(pageNumber, () => [])
                                  .add(comment);
                            }
                            _store.saveComments(
                                pageNumber, _pageComments[pageNumber] ?? []);
                          });
                          Navigator.pop(ctx);
                        },
                        child: const Text("حفظ",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                  ]);
            }));
  }

  /// يحدد اتجاه النص تلقائياً بناءً على أول حرف قوي (نفس منطق أداة النص الجديدة)
  /// لإصلاح مشكلة خلط النص العربي والإنجليزي في الملاحظات.
  TextDirection _autoDirection(String text) {
    for (final rune in text.runes) {
      if (rune >= 0x0600 && rune <= 0x06FF) return TextDirection.rtl;
      if ((rune >= 0x0041 && rune <= 0x005A) ||
          (rune >= 0x0061 && rune <= 0x007A)) {
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
    bool previewUnderline = note.underline as bool;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // معاينة حية للنص
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundPrimary,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Color(previewColor).withOpacity(0.5)),
                  ),
                  child: Text(
                    controller.text.isNotEmpty
                        ? controller.text
                        : "معاينة النص...",
                    style: TextStyle(
                      color: Color(previewColor),
                      fontSize: previewFontSize * 400, // عرض نسبي للمعاينة
                      fontWeight:
                          previewBold ? FontWeight.bold : FontWeight.normal,
                      decoration: previewUnderline
                          ? TextDecoration.underline
                          : TextDecoration.none,
                      decorationColor: Color(previewColor),
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
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
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
                    Icon(Icons.format_size,
                        size: 16, color: AppColors.textSecondary),
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
                          _textNoteController.updateFontSize(
                              pageNumber, note, v);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        "${(previewFontSize * 1000).toInt()}",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                // خط عريض
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text("عريض",
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
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
                // تسطير
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text("تسطير",
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                    Switch(
                      value: previewUnderline,
                      activeColor: AppColors.accentYellow,
                      onChanged: (v) {
                        setSheetState(() => previewUnderline = v);
                        _textNoteController.updateUnderline(
                            pageNumber, note, v);
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
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent),
                          label: const Text("حذف",
                              style: TextStyle(color: Colors.redAccent)),
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
                        label: Text("حفظ",
                            style: TextStyle(color: AppColors.accentYellow)),
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
            : (tool == PdfTool.underline
                ? TextMarkupTool.underline
                : TextMarkupTool.none);
        // ── Fix (highlight/underline): eagerly pre-warm the text cache for the
        // current page (and neighbours) the moment the user activates either
        // markup tool, so it is guaranteed to be ready before they finish
        // selecting text and press the context-menu button.
        if ((tool == PdfTool.highlighter || tool == PdfTool.underline) &&
            _pdfController != null) {
          final ctrl = _pdfController!;
          final doc = ctrl.document;
          if (doc != null) {
            final total = doc.pages.length;
            final cur = _activePage > 0 ? _activePage : 1;
            for (int p = (cur - 1).clamp(1, total);
                p <= (cur + 1).clamp(1, total);
                p++) {
              _textCache.ensureLoadedByPageNumber(p, ctrl);
            }
          }
        }
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
      freehandHighlighterThickness: _settings.freehandHighlighterThickness,
      onFreehandHighlighterThicknessChanged: (v) {
        setState(() => _settings.freehandHighlighterThickness = v);
        _persistToolSettings();
      },
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
      textUnderline: _textNoteController.defaultUnderline,
      onTextUnderlineChanged: (v) {
        setState(() => _textNoteController.defaultUnderline = v);
      },
      shapeType: _shapeController.activeType,
      onShapeTypeChanged: (t) =>
          setState(() => _shapeController.activeType = t),
      shapeBorderColor: Color(_settings.shapeBorderColor),
      onShapeBorderColorChanged: (c) {
        setState(() {
          _settings.shapeBorderColor = c.value;
          _shapeController.borderColor = c.value;
        });
        _persistToolSettings();
      },
      shapeFillColor: _settings.shapeFillColor != null
          ? Color(_settings.shapeFillColor!)
          : null,
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
    if (_activeTool == PdfTool.pen ||
        _activeTool == PdfTool.eraser ||
        _activeTool == PdfTool.freehandHighlighter) {
      if (_pageDrawings[_activePage]?.isNotEmpty ?? false) {
        setState(() => _pageDrawings[_activePage]!.removeLast());
        _store.saveDrawings(_activePage, _pageDrawings[_activePage]!);
      }
    }
  }
}

/// رسّام موحّد للرسم الحر (القلم/الممحاة/هايلايتر) والأشكال (مع معاينة فورية أثناء السحب).
///
/// التحسينات المُطبَّقة:
/// • Catmull-Rom spline للقلم والممحاة — نعومة حقيقية بدلاً من Bézier ثنائي.
/// • Catmull-Rom أيضاً للهايلايتر الحر — يزيل الزوايا الحادة مع الحفاظ على مظهر التظليل.
/// • shouldRepaint يقارن الطول فقط (خفيف جداً في الأداء).
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

  // ── Catmull-Rom spline helper ────────────────────────────────────────────
  // Converts a list of control points into a smooth Path using Catmull-Rom
  // parameterization converted to cubic Bézier segments (Flutter's native form).
  // `tension` ∈ [0, 1]: 0 = tight / angular, 0.5 = centripetal (best for drawing),
  // 1 = slack.  We use 0.5 (centripetal) which avoids cusps on abrupt direction
  // changes — ideal for hand-drawn strokes.
  static Path _catmullRomPath(
    List<Offset> pts,
    double w,
    double h, {
    double tension = 0.5,
  }) {
    final path = Path();
    if (pts.isEmpty) return path;

    // Scale from normalised coordinates to canvas pixels once.
    final scaled = pts.map((p) => Offset(p.dx * w, p.dy * h)).toList();

    path.moveTo(scaled[0].dx, scaled[0].dy);
    if (scaled.length == 1) return path;
    if (scaled.length == 2) {
      path.lineTo(scaled[1].dx, scaled[1].dy);
      return path;
    }

    for (int i = 0; i < scaled.length - 1; i++) {
      // Phantom points at the ends: mirror the neighbouring point.
      final p0 = i == 0 ? scaled[0] : scaled[i - 1];
      final p1 = scaled[i];
      final p2 = scaled[i + 1];
      final p3 = i + 2 < scaled.length ? scaled[i + 2] : scaled.last;

      // Catmull-Rom → cubic Bézier conversion:
      //   cp1 = p1 + (p2 - p0) * tension / 3
      //   cp2 = p2 - (p3 - p1) * tension / 3
      final cp1 = Offset(
        p1.dx + (p2.dx - p0.dx) * tension / 3,
        p1.dy + (p2.dy - p0.dy) * tension / 3,
      );
      final cp2 = Offset(
        p2.dx - (p3.dx - p1.dx) * tension / 3,
        p2.dy - (p3.dy - p1.dy) * tension / 3,
      );
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());
    final w = pageSize.width;
    final h = pageSize.height;

    for (var line in lines) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = line.strokeWidth * w;

      if (line.isEraser) {
        paint.blendMode = BlendMode.clear;
        paint.color = Colors.transparent;
      } else if (line.isHighlighter) {
        // هايلايتر حر: BlendMode.multiply للتداخل الطبيعي مع محتوى الصفحة
        paint.blendMode = BlendMode.multiply;
        paint.color = Color(line.color).withOpacity(line.opacity);
        paint.strokeCap =
            StrokeCap.square; // حواف مستقيمة لمظهر تظليل أكثر واقعية
      } else {
        paint.color = Color(line.color).withOpacity(line.opacity);
      }

      final pts = line.points;
      if (pts.length > 1) {
        // Both pen/eraser AND highlighter now use Catmull-Rom for maximum
        // smoothness.  The highlighter keeps StrokeCap.square + multiply
        // blendMode so it still looks like a real highlighter pen.
        final path = _catmullRomPath(pts, w, h, tension: 0.5);
        canvas.drawPath(path, paint);
      } else if (pts.isNotEmpty) {
        // Single tap — draw a dot.
        final p = Offset(pts[0].dx * w, pts[0].dy * h);
        canvas.drawPoints(PointMode.points, [p], paint);
      }
    }
    canvas.restore();

    shapeController.paintShapes(canvas, pageSize, shapes,
        preview: shapePreview);
  }

  @override
  bool shouldRepaint(covariant _CombinedOverlayPainter old) {
    // Fast path: only deep-compare when counts differ or a shape changed.
    // During active drawing lines.last grows, so the total length changes —
    // that's our cue to repaint without comparing every point.
    if (lines.length != old.lines.length) return true;
    if (lines.isNotEmpty && old.lines.isNotEmpty) {
      final cur = lines.last;
      final prev = old.lines.last;
      if (cur.points.length != prev.points.length) return true;
    }
    if (shapes.length != old.shapes.length) return true;
    if (shapePreview != old.shapePreview) return true;
    return false;
  }
}
