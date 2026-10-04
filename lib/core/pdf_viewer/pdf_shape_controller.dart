import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/shape_model.dart';
import '../services/pdf_annotation_store.dart';

/// يدير أدوات الأشكال الهندسية (سهم/دائرة/مربع/مستطيل):
/// - الرسم بالسحب (نقطة بداية إلى نقطة نهاية).
/// - الرسم الفعلي على الـ Canvas.
/// - تحريك وتغيير الحجم وحذف الأشكال الموجودة.
///
/// ── الشكل الذي يمتد على أكثر من صفحة ────────────────────────────────────────
/// الشكل يُحسب بإحداثيات المستند (document space) ثم يُقسَّم على الصفحات التي
/// يلامسها، تماماً كما يفعل الخط الحر: لكل صفحة جزء (ShapeModel) بإحداثيات نسبية
/// لتلك الصفحة، وكل صفحة تقصّ رسمها عند حدودها. أجزاء الشكل الواحد تشترك في
/// [ShapeModel.groupId]، فالحذف وتغيير اللون/السماكة/التعبئة يسري على كل الأجزاء،
/// والتحريك/تغيير الحجم يُعيد تقسيم الشكل على الصفحات التي صار يلامسها.
class PdfShapeController {
  PdfShapeController({
    required this.store,
    required this.onChanged,
  });

  final PdfAnnotationStore store;
  final VoidCallback onChanged;

  /// مستطيلات الصفحات بفضاء المستند (الفهرس = رقم الصفحة − 1). يزوّدها العارض.
  /// إن لم تتوفر يعود المتحكم للسلوك القديم (الشكل على صفحة البداية فقط).
  List<Rect>? Function()? layoutProvider;

  bool isActive = false;
  ShapeType activeType = ShapeType.rectangle;
  int borderColor = 0xFFEF4444;
  int? fillColor; // null = شفاف
  double borderWidth = 0.004;

  final Map<int, List<ShapeModel>> _shapes = {};
  final Map<int, Future<void>> _loadFutures = {};

  // ── الرسم الجاري ──
  final Map<int, ShapeModel> _previews = {}; // رقم الصفحة → الجزء الحي
  int? _drawingPage;
  String? _drawingGroupId;
  ShapeType _drawingType = ShapeType.rectangle;
  List<Rect>? _drawingLayouts; // null = الوضع القديم (صفحة واحدة)
  Offset? _docStart;
  Offset? _docEnd;
  double _docBorderWidth = 0; // بوحدات المستند

  // مجموعة الشكل → أرقام صفحات أجزائه (للتراجع/الحذف دون تحميل كل الصفحات).
  final Map<String, Set<int>> _groupPagesById = {};

  // أشكال جرى تحريكها فعلاً ولم يُعَد تقسيمها/حفظها بعد. (onPanCancel في Flutter
  // يُستدعى أيضاً عند النقر العادي بلا سحب؛ لا نريد إعادة تقسيم وكتابة بلا تحريك.)
  final Set<String> _pendingMoves = <String>{};

  // العمليات غير المتزامنة على الأشكال تُنفَّذ بالتتابع (سلايدر الحجم يطلق عدة
  // طلبات متتالية؛ كل طلب يبني على نتيجة سابقه).
  Future<void> _serial = Future<void>.value();

  Future<T> _run<T>(Future<T> Function() op) {
    final result = _serial.then((_) => op());
    _serial = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  List<ShapeModel> shapesForPage(int page) => _shapes[page] ?? const [];

  /// يحمّل أشكال صفحة (Future واحد لكل صفحة؛ لا يكتب فوق ما أُضيف بعد التحميل).
  Future<void> ensurePageLoaded(int pageNumber) {
    if (_shapes.containsKey(pageNumber)) return Future<void>.value();
    return _loadFutures.putIfAbsent(pageNumber, () async {
      try {
        final loaded = await store.loadShapes(pageNumber);
        _shapes.putIfAbsent(pageNumber, () => loaded);
      } catch (_) {
        _loadFutures.remove(pageNumber); // أعد المحاولة لاحقاً
        rethrow;
      }
    });
  }

  /// لا نكتب أبداً صفحة لم تُحمَّل بعد (كي لا نمسح المحفوظ بقائمة فارغة).
  Future<void> _persist(int pageNumber) {
    final list = _shapes[pageNumber];
    if (list == null) return Future<void>.value();
    return store.saveShapes(pageNumber, list);
  }

  // ───────────────────────── هندسة المستند ─────────────────────────

  static String _gidOf(ShapeModel s) => s.groupId ?? s.id;

  static Rect? _layoutRect(List<Rect>? layouts, int page) {
    if (layouts == null || page < 1 || page > layouts.length) return null;
    return layouts[page - 1];
  }

  static Offset _toDoc(Rect r, double dx, double dy) =>
      Offset(r.left + dx * r.width, r.top + dy * r.height);

  /// يكتب هندسة الشكل (بفضاء المستند) كجزء نسبي للصفحة ذات المستطيل [r].
  static void _writePortion(ShapeModel m, Rect r, Offset docStart,
      Offset docEnd, double docBorderWidth) {
    m.startDx = (docStart.dx - r.left) / r.width;
    m.startDy = (docStart.dy - r.top) / r.height;
    m.endDx = (docEnd.dx - r.left) / r.width;
    m.endDy = (docEnd.dy - r.top) / r.height;
    m.borderWidth = docBorderWidth / r.width;
  }

  /// المربع: ضلعاه متساويان بوحدات المستند (= البكسل بتكبير منتظم)، باتجاه السحب.
  static Offset _squareEnd(ShapeType type, Offset s, Offset e) {
    if (type != ShapeType.square) return e;
    final dx = e.dx - s.dx;
    final dy = e.dy - s.dy;
    final side = math.max(dx.abs(), dy.abs());
    return Offset(s.dx + (dx < 0 ? -side : side), s.dy + (dy < 0 ? -side : side));
  }

  /// الصفحات (مرتّبة) التي يلامسها الشكل. نُوسّع الصندوق بنصف سماكة الحدود، وبهامش
  /// لرأس السهم (حجمه بالبكسل فيتفاوت بالتكبير).
  static List<int> _pagesFor(List<Rect> layouts, Offset a, Offset b,
      double docBorderWidth, ShapeType type) {
    final pad = docBorderWidth / 2 + (type == ShapeType.arrow ? 40.0 : 0.0) + 0.5;
    final box = Rect.fromPoints(a, b).inflate(pad);
    final pages = <int>[];
    for (var i = 0; i < layouts.length; i++) {
      if (layouts[i].overlaps(box)) pages.add(i + 1);
    }
    return pages;
  }

  ShapeModel _newPortion(String id, String gid, ShapeType type) => ShapeModel(
        id: id,
        type: type,
        startDx: 0,
        startDy: 0,
        endDx: 0,
        endDy: 0,
        borderColor: borderColor,
        fillColor: fillColor,
        borderWidth: borderWidth,
        groupId: gid,
      );

  // ───────────────────────── الرسم (سحب لإنشاء شكل جديد) ─────────────────────────

  /// يبدأ شكلاً جديداً. عند توفر [docPoint] (نقطة البداية بفضاء المستند) و
  /// [layoutProvider] يُقسَّم الشكل على الصفحات التي يمتد عليها؛ وإلا (احتياطي)
  /// يُرسم على صفحة البداية فقط كما كان.
  void startDrawing(int pageNumber, Offset relativePoint, {Offset? docPoint}) {
    _previews.clear();
    _drawingPage = pageNumber;
    _drawingType = activeType;
    final gid = '${DateTime.now().microsecondsSinceEpoch}';
    _drawingGroupId = gid;

    final layouts = docPoint == null ? null : layoutProvider?.call();
    final startRect = _layoutRect(layouts, pageNumber);
    if (docPoint != null && layouts != null && startRect != null) {
      _drawingLayouts = layouts;
      _docStart = docPoint;
      _docEnd = docPoint;
      _docBorderWidth = borderWidth * startRect.width;
      _syncPreviews();
    } else {
      _drawingLayouts = null;
      _docStart = null;
      _docEnd = null;
      _previews[pageNumber] = _newPortion(gid, gid, _drawingType)
        ..startDx = relativePoint.dx
        ..startDy = relativePoint.dy
        ..endDx = relativePoint.dx
        ..endDy = relativePoint.dy;
    }
    onChanged();
  }

  /// يحدّث أجزاء المعاينة الحية: جزء لكل صفحة يلامسها الشكل الآن.
  void _syncPreviews() {
    final layouts = _drawingLayouts;
    final start = _docStart;
    final rawEnd = _docEnd;
    final gid = _drawingGroupId;
    if (layouts == null || start == null || rawEnd == null || gid == null) {
      return;
    }
    final end = _squareEnd(_drawingType, start, rawEnd);
    final pages = _pagesFor(layouts, start, end, _docBorderWidth, _drawingType);
    final startPage = _drawingPage;
    if (startPage != null && !pages.contains(startPage)) pages.add(startPage);
    _previews.removeWhere((page, _) => !pages.contains(page));
    for (final page in pages) {
      final r = _layoutRect(layouts, page);
      if (r == null) continue;
      final m = _previews.putIfAbsent(
          page, () => _newPortion('${gid}_$page', gid, _drawingType));
      _writePortion(m, r, start, end, _docBorderWidth);
    }
  }

  void updateDrawing(Offset relativePoint, {Offset? docPoint}) {
    final page = _drawingPage;
    if (page == null) return;
    if (_docStart != null) {
      if (docPoint == null) return;
      _docEnd = docPoint;
      _syncPreviews();
    } else {
      final m = _previews[page];
      if (m == null) return;
      m.endDx = relativePoint.dx;
      m.endDy = relativePoint.dy;
    }
    onChanged();
  }

  void _resetDrawing() {
    _previews.clear();
    _drawingPage = null;
    _drawingGroupId = null;
    _drawingLayouts = null;
    _docStart = null;
    _docEnd = null;
  }

  /// ينهي الرسم ويثبّت الشكل (كل أجزائه). يعيد معرّف مجموعة الشكل المثبَّت للتراجع
  /// ([deleteGroupById])، أو null إن أُهمل الشكل لصغره (ضغطة بالخطأ بدون سحب فعلي).
  ///
  /// [pageSize] لازم في الوضع القديم (صفحة واحدة) عند [ShapeType.square]؛ فالضلعان
  /// المتساويان يُحسبان بفضاء البكسل لا بالإحداثيات النسبية (عرض الصفحة ≠ ارتفاعها).
  Future<String?> endDrawing({Size? pageSize}) async {
    final page = _drawingPage;
    final gid = _drawingGroupId;
    if (page == null || gid == null || _previews.isEmpty) {
      _resetDrawing();
      onChanged();
      return null;
    }
    String? committed;
    try {
      committed = (_docStart != null && _drawingLayouts != null)
          ? await _commitMulti(page, gid)
          : await _commitSingle(page, gid, pageSize);
    } finally {
      _resetDrawing();
      onChanged();
    }
    return committed;
  }

  Future<String?> _commitMulti(int page, String gid) async {
    final layouts = _drawingLayouts!;
    final startRect = _layoutRect(layouts, page);
    final start = _docStart!;
    final end = _squareEnd(_drawingType, start, _docEnd ?? start);
    if (startRect == null) return null;
    // تجاهل الأشكال الصغيرة جداً (ضغطة بالخطأ بدون سحب فعلي)
    final tiny = (end.dx - start.dx).abs() <= 0.01 * startRect.width &&
        (end.dy - start.dy).abs() <= 0.01 * startRect.height;
    if (tiny) return null;

    _syncPreviews(); // الهندسة النهائية (بعد تثبيت المربع)
    final pages = _previews.keys.toList()..sort();
    for (final p in pages) {
      await ensurePageLoaded(p); // قبل الإضافة: كي لا يُكتب فوق المحفوظ
    }
    for (final p in pages) {
      final m = _previews[p];
      if (m == null) continue;
      m.groupId = gid;
      m.groupPages = List<int>.of(pages);
      _shapes.putIfAbsent(p, () => []).add(m);
    }
    _groupPagesById[gid] = pages.toSet();
    // الأجزاء صارت في قوائم الصفحات: أزل المعاينة فوراً (وإلا رُسم الجزء مرتين
    // أثناء انتظار الحفظ، فيغمّق التعبئة الشفافة لحظةً).
    _previews.clear();
    onChanged();
    for (final p in pages) {
      await _persist(p);
    }
    return gid;
  }

  Future<String?> _commitSingle(int page, String gid, Size? pageSize) async {
    final shape = _previews[page];
    if (shape == null) return null;
    // تجاهل الأشكال الصغيرة جداً (ضغطة بالخطأ بدون سحب فعلي)
    final dx = (shape.endDx - shape.startDx).abs();
    final dy = (shape.endDy - shape.startDy).abs();
    if (dx <= 0.01 && dy <= 0.01) return null;

    // ── تثبيت المربع: حفظ الأبعاد المتساوية في فضاء البكسل ──
    // السبب: الإحداثيات النسبية (0–1) تمثّل نسباً مختلفة من البكسلات
    // على المحورين (عرض الصفحة ≠ ارتفاعها)، لذا يجب حساب ضلع المربع
    // في فضاء البكسل ثم تحويله للإحداثيات النسبية للتخزين.
    if (shape.type == ShapeType.square &&
        pageSize != null &&
        pageSize.width > 0 &&
        pageSize.height > 0) {
      final pxStartX = shape.startDx * pageSize.width;
      final pxStartY = shape.startDy * pageSize.height;
      final pxEndX = shape.endDx * pageSize.width;
      final pxEndY = shape.endDy * pageSize.height;
      final pdx = pxEndX - pxStartX;
      final pdy = pxEndY - pxStartY;
      // اختيار أكبر امتداد (وليس أصغره) حفاظاً على الحجم الذي رسمه المستخدم
      final side = math.max(pdx.abs(), pdy.abs());
      shape.endDx = (pxStartX + (pdx < 0 ? -side : side)) / pageSize.width;
      shape.endDy = (pxStartY + (pdy < 0 ? -side : side)) / pageSize.height;
    } else if (shape.type == ShapeType.square) {
      // احتياطي: إذا لم تتوفر pageSize، استخدم أكبر امتداد نسبي
      final sdx = shape.endDx - shape.startDx;
      final sdy = shape.endDy - shape.startDy;
      final side = math.max(sdx.abs(), sdy.abs());
      shape.endDx = shape.startDx + (sdx < 0 ? -side : side);
      shape.endDy = shape.startDy + (sdy < 0 ? -side : side);
    }
    shape.groupId = gid;
    shape.groupPages = <int>[page];
    await ensurePageLoaded(page);
    _shapes.putIfAbsent(page, () => []).add(shape);
    _groupPagesById[gid] = <int>{page};
    _previews.clear();
    onChanged();
    await _persist(page);
    return gid;
  }

  /// الجزء الجاري رسمه حالياً (لإظهار معاينة فورية أثناء السحب) لصفحة معينة.
  ShapeModel? drawingShapeForPage(int pageNumber) => _previews[pageNumber];

  // ───────────────────────── مجموعات الأشكال (أجزاء الصفحات) ─────────────────────────

  Set<int> _groupPageSet(ShapeModel s, int pageNumber) => <int>{
        pageNumber,
        ...?s.groupPages,
        ...?_groupPagesById[_gidOf(s)],
      };

  /// كل أجزاء الشكل المنطقي الذي ينتمي إليه [s] (يحمّل صفحاتها عند الحاجة).
  Future<List<_Member>> _members(ShapeModel s, int pageNumber) async {
    final gid = _gidOf(s);
    final result = <_Member>[];
    for (final p in _groupPageSet(s, pageNumber)) {
      await ensurePageLoaded(p);
      for (final m in _shapes[p] ?? const <ShapeModel>[]) {
        if (_gidOf(m) == gid) result.add(_Member(p, m));
      }
    }
    return result;
  }

  /// يُعيد تقسيم الشكل (بعد تحريك أو تغيير حجم) على الصفحات التي صار يلامسها:
  /// يحدّث أجزاءه الحالية في مكانها، ويضيف جزءاً للصفحات الجديدة، ويزيل الأجزاء
  /// من الصفحات التي لم يعد يلامسها. [scale] ≠ 1 يكبّر/يصغّر حول مركز الشكل.
  Future<void> _resplit(ShapeModel anchor, int pageNumber,
      {double scale = 1.0}) async {
    final layouts = layoutProvider?.call();
    final base = _layoutRect(layouts, pageNumber);
    if (layouts == null || base == null) {
      await _persist(pageNumber);
      return;
    }
    final gid = _gidOf(anchor);

    var docStart = _toDoc(base, anchor.startDx, anchor.startDy);
    var docEnd = _toDoc(base, anchor.endDx, anchor.endDy);
    final docWidth = anchor.borderWidth * base.width;
    if (scale != 1.0) {
      final c = (docStart + docEnd) / 2;
      final halfW = (docEnd.dx - docStart.dx).abs() / 2 * scale;
      final halfH = (docEnd.dy - docStart.dy).abs() / 2 * scale;
      final sx = docEnd.dx >= docStart.dx ? 1.0 : -1.0;
      final sy = docEnd.dy >= docStart.dy ? 1.0 : -1.0;
      docStart = Offset(c.dx - halfW * sx, c.dy - halfH * sy);
      docEnd = Offset(c.dx + halfW * sx, c.dy + halfH * sy);
    }

    final members = await _members(anchor, pageNumber);
    final byPage = <int, ShapeModel>{for (final m in members) m.page: m.shape};
    final newPages =
        _pagesFor(layouts, docStart, docEnd, docWidth, anchor.type);
    if (newPages.isEmpty) newPages.add(pageNumber);
    for (final p in newPages) {
      await ensurePageLoaded(p);
    }

    for (final p in newPages) {
      final r = _layoutRect(layouts, p);
      if (r == null) continue;
      var m = byPage[p];
      if (m == null) {
        m = ShapeModel(
          id: '${gid}_$p',
          type: anchor.type,
          startDx: 0,
          startDy: 0,
          endDx: 0,
          endDy: 0,
          borderColor: anchor.borderColor,
          fillColor: anchor.fillColor,
          borderWidth: anchor.borderWidth,
        );
        _shapes.putIfAbsent(p, () => []).add(m);
        byPage[p] = m;
      }
      _writePortion(m, r, docStart, docEnd, docWidth);
      m.groupId = gid;
      m.groupPages = List<int>.of(newPages);
    }

    final removedPages = <int>[];
    for (final e in byPage.entries.toList()) {
      if (!newPages.contains(e.key)) {
        _shapes[e.key]?.remove(e.value);
        removedPages.add(e.key);
      }
    }
    // نافذة التعديل المفتوحة قد تحمل جزءاً أُزيل: نُبقي هندسته محدّثة كي تستمر
    // عمليات السلايدر التالية من الحالة الصحيحة.
    if (!newPages.contains(pageNumber)) {
      _writePortion(anchor, base, docStart, docEnd, docWidth);
    }
    _groupPagesById[gid] = newPages.toSet();
    onChanged();

    final affected = <int>{
      ...newPages,
      ...removedPages,
      ...members.map((m) => m.page),
    };
    for (final p in affected) {
      await _persist(p);
    }
  }

  // ───────────────────────── التحريك / الحجم / التعديل / الحذف ─────────────────────────

  /// يحرّك الشكل بمقدار [deltaRelative] (نسبةً لصفحة [pageNumber]). أجزاء الشكل
  /// المقسَّم تتحرك كلها بنفس الإزاحة بفضاء المستند؛ ويُنادى [finishMove] عند انتهاء
  /// السحب لإعادة التقسيم على الصفحات الجديدة.
  Future<void> moveShape(
      ShapeModel shape, int pageNumber, Offset deltaRelative) async {
    final layouts = layoutProvider?.call();
    final base = _layoutRect(layouts, pageNumber);
    final isMulti = (shape.groupPages?.length ?? 0) > 1;
    _pendingMoves.add(_gidOf(shape));
    if (!isMulti || layouts == null || base == null) {
      shape.startDx += deltaRelative.dx;
      shape.startDy += deltaRelative.dy;
      shape.endDx += deltaRelative.dx;
      shape.endDy += deltaRelative.dy;
      await _persist(pageNumber);
      onChanged();
      return;
    }
    final ddoc = Offset(
        deltaRelative.dx * base.width, deltaRelative.dy * base.height);
    final members = await _members(shape, pageNumber);
    for (final m in members) {
      final r = _layoutRect(layouts, m.page);
      if (r == null) continue;
      m.shape.startDx += ddoc.dx / r.width;
      m.shape.endDx += ddoc.dx / r.width;
      m.shape.startDy += ddoc.dy / r.height;
      m.shape.endDy += ddoc.dy / r.height;
    }
    onChanged(); // الحفظ عند [finishMove]
  }

  /// نهاية سحب التحريك: إعادة تقسيم الشكل على الصفحات التي يلامسها + حفظ.
  Future<void> finishMove(ShapeModel shape, int pageNumber) {
    if (!_pendingMoves.remove(_gidOf(shape))) return Future<void>.value();
    return _run(() => _resplit(shape, pageNumber));
  }

  /// تغيير حجم الشكل بعامل تكبير/تصغير (0.5 = نصف الحجم، 2.0 = ضعف الحجم).
  /// يتمحور التغيير حول مركز الشكل الحالي.
  Future<void> resizeShape(
      ShapeModel shape, int pageNumber, double scaleFactor) async {
    final layouts = layoutProvider?.call();
    if (_layoutRect(layouts, pageNumber) == null) {
      // احتياطي (لا تخطيط للصفحات): الجزء وحده كما كان.
      final cx = (shape.startDx + shape.endDx) / 2;
      final cy = (shape.startDy + shape.endDy) / 2;
      final halfW = ((shape.endDx - shape.startDx).abs() / 2) * scaleFactor;
      final halfH = ((shape.endDy - shape.startDy).abs() / 2) * scaleFactor;
      final signX = shape.endDx >= shape.startDx ? 1.0 : -1.0;
      final signY = shape.endDy >= shape.startDy ? 1.0 : -1.0;
      shape.startDx = cx - halfW * signX;
      shape.startDy = cy - halfH * signY;
      shape.endDx = cx + halfW * signX;
      shape.endDy = cy + halfH * signY;
      await _persist(pageNumber);
      onChanged();
      return;
    }
    await _run(() => _resplit(shape, pageNumber, scale: scaleFactor));
  }

  /// يطبّق [apply] على كل أجزاء شكل (الجزء المعروض يتغيّر فوراً) ثم يحفظ الصفحات.
  Future<void> _applyToGroup(
      ShapeModel shape, int pageNumber, void Function(ShapeModel) apply) {
    apply(shape);
    onChanged();
    return _run(() async {
      final members = await _members(shape, pageNumber);
      final pages = <int>{pageNumber};
      for (final m in members) {
        if (!identical(m.shape, shape)) apply(m.shape);
        pages.add(m.page);
      }
      onChanged();
      for (final p in pages) {
        await _persist(p);
      }
    });
  }

  Future<void> updateBorderColor(ShapeModel shape, int pageNumber, int color) =>
      _applyToGroup(shape, pageNumber, (m) => m.borderColor = color);

  Future<void> updateFillColor(ShapeModel shape, int pageNumber, int? color) =>
      _applyToGroup(shape, pageNumber, (m) => m.fillColor = color);

  /// السماكة نسبة من عرض الصفحة؛ نحافظ على نفس السماكة الفعلية على كل الأجزاء.
  Future<void> updateBorderWidth(
      ShapeModel shape, int pageNumber, double width) {
    final layouts = layoutProvider?.call();
    final base = _layoutRect(layouts, pageNumber);
    final docWidth = base == null ? null : width * base.width;
    shape.borderWidth = width;
    onChanged();
    return _run(() async {
      final members = await _members(shape, pageNumber);
      final pages = <int>{pageNumber};
      for (final m in members) {
        pages.add(m.page);
        if (identical(m.shape, shape)) continue;
        final r = _layoutRect(layouts, m.page);
        m.shape.borderWidth =
            (docWidth != null && r != null) ? docWidth / r.width : width;
      }
      onChanged();
      for (final p in pages) {
        await _persist(p);
      }
    });
  }

  /// يحذف الشكل بكل أجزائه على كل الصفحات.
  Future<void> deleteShape(ShapeModel shape, int pageNumber) => _run(
      () => _deleteGroup(_gidOf(shape), _groupPageSet(shape, pageNumber)));

  /// للتراجع: يحذف شكلاً (بكل أجزائه) أنشأه [endDrawing] بمعرّف مجموعته.
  Future<void> deleteGroupById(String groupId) => _run(() =>
      _deleteGroup(groupId, _groupPagesById[groupId] ?? const <int>{}));

  Future<void> _deleteGroup(String gid, Set<int> pages) async {
    for (final p in pages) {
      await ensurePageLoaded(p);
      _shapes[p]?.removeWhere((s) => _gidOf(s) == gid);
    }
    _groupPagesById.remove(gid);
    onChanged();
    for (final p in pages) {
      await _persist(p);
    }
  }

  /// اكتشاف الشكل الموجود عند نقطة نسبية معينة (للنقر عليه لتحريكه/حذفه).
  ShapeModel? hitTest(int pageNumber, Offset relativePoint, {double margin = 0.015}) {
    for (final s in shapesForPage(pageNumber).reversed) {
      final rect = Rect.fromLTRB(
        math.min(s.startDx, s.endDx) - margin,
        math.min(s.startDy, s.endDy) - margin,
        math.max(s.startDx, s.endDx) + margin,
        math.max(s.startDy, s.endDy) + margin,
      );
      if (rect.contains(relativePoint)) return s;
    }
    return null;
  }

  /// يرسم كل أشكال صفحة معينة (بما فيها الشكل الجاري رسمه إن وُجد) على Canvas.
  void paintShapes(Canvas canvas, Size pageSize, List<ShapeModel> shapes, {ShapeModel? preview}) {
    final all = [...shapes];
    if (preview != null) all.add(preview);
    for (final s in all) {
      _paintOne(canvas, pageSize, s);
    }
  }

  void _paintOne(Canvas canvas, Size pageSize, ShapeModel s) {
    double startX = s.startDx;
    double startY = s.startDy;
    double endX = s.endDx;
    double endY = s.endDy;

    // ── Square Fix ──
    // The shape is stored in normalised coords (0–1 relative to page size).
    // Because page width ≠ page height, normalising dx and dy independently
    // means the same numeric delta represents a different number of pixels on
    // each axis.  We must work in pixel space to get visually equal sides.
    if (s.type == ShapeType.square) {
      // Convert to pixels
      final pxStartX = startX * pageSize.width;
      final pxStartY = startY * pageSize.height;
      final pxEndX   = endX   * pageSize.width;
      final pxEndY   = endY   * pageSize.height;

      final pdx = pxEndX - pxStartX;
      final pdy = pxEndY - pxStartY;

      // Pick the larger pixel extent as the side length (matches endDrawing)
      final side = math.max(pdx.abs(), pdy.abs());

      // Preserve the drag direction on each axis
      final pxNewEndX = pxStartX + (pdx < 0 ? -side : side);
      final pxNewEndY = pxStartY + (pdy < 0 ? -side : side);

      // Convert back to normalised coords for the rect calculation
      endX = pxNewEndX / pageSize.width;
      endY = pxNewEndY / pageSize.height;
    }

    final rect = Rect.fromLTRB(
      math.min(startX, endX) * pageSize.width,
      math.min(startY, endY) * pageSize.height,
      math.max(startX, endX) * pageSize.width,
      math.max(startY, endY) * pageSize.height,
    );
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.borderWidth * pageSize.width
      ..color = Color(s.borderColor);
    // السهم لا يحتوي على تعبئة أبداً
    final fillPaint = (s.fillColor != null && s.type != ShapeType.arrow)
        ? (Paint()
          ..style = PaintingStyle.fill
          ..color = Color(s.fillColor!))
        : null;

    switch (s.type) {
      case ShapeType.rectangle:
      case ShapeType.square:
        if (fillPaint != null) canvas.drawRect(rect, fillPaint);
        canvas.drawRect(rect, borderPaint);
        break;
      case ShapeType.circle:
        if (fillPaint != null) canvas.drawOval(rect, fillPaint);
        canvas.drawOval(rect, borderPaint);
        break;
      case ShapeType.arrow:
        _paintArrow(
          canvas,
          Offset(s.startDx * pageSize.width, s.startDy * pageSize.height),
          Offset(s.endDx * pageSize.width, s.endDy * pageSize.height),
          borderPaint,
        );
        break;
    }
  }

  /// يرسم سهماً من [start] إلى [end].
  /// الخط يمتد من البداية حتى **قاعدة رأس السهم** حيث تلتقي قاعدة المثلث بالخط
  /// بدون أن يخترق الخط رأس السهم أو يتجاوزه. نقطة الرأس الحقيقية تُحرَّك
  /// قليلاً نحو المنتصف حتى تبدو القاعدة والخط متصلَين بصرياً.
  void _paintArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    final direction = end - start;
    final length = direction.distance;
    if (length < 1) return;

    final unit = direction / length;
    final arrowSize = math.max(18.0, paint.strokeWidth * 5);
    const halfAngle = 0.40; // ~23 درجة

    // ── نحرّك نقطة الرأس قليلاً داخلياً (20%) لتبدو القاعدة وكأنها تلتصق بالخط ──
    final tipInset = arrowSize * 0.20;
    final visualTip = Offset(
      end.dx - tipInset * unit.dx,
      end.dy - tipInset * unit.dy,
    );

    // قاعدة المثلث: على مسافة arrowSize من النقطة الأصلية end
    final arrowBase = Offset(
      end.dx - arrowSize * unit.dx,
      end.dy - arrowSize * unit.dy,
    );

    final cos = math.cos(halfAngle);
    final sin = math.sin(halfAngle);

    // نقطتا الجانبين (تُحسب من النقطة الأصلية end لتحافظ على الزاوية الصحيحة)
    final p1 = Offset(
      end.dx - arrowSize * (unit.dx * cos - unit.dy * sin),
      end.dy - arrowSize * (unit.dy * cos + unit.dx * sin),
    );
    final p2 = Offset(
      end.dx - arrowSize * (unit.dx * cos + unit.dy * sin),
      end.dy - arrowSize * (unit.dy * cos - unit.dx * sin),
    );

    // ── الخط: من البداية حتى قاعدة رأس السهم (لا يتجاوزه) ──
    canvas.drawLine(start, arrowBase, paint..strokeCap = StrokeCap.round);

    // ── رأس السهم (مثلث مملوء): رأسه عند visualTip لاتصال بصري مع الخط ──
    final headPath = Path()
      ..moveTo(visualTip.dx, visualTip.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();

    canvas.drawPath(
      headPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = paint.color,
    );
  }
}

class _Member {
  _Member(this.page, this.shape);
  final int page;
  final ShapeModel shape;
}
