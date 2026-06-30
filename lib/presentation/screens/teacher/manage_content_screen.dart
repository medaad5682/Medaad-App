import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:media_kit/media_kit.dart';
import '../../../core/services/teacher_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/app_state.dart'; // ✅ ضروري لتحديث الحالة العامة
import '../../../core/services/bunny_tus_upload_service.dart';
import '../../widgets/custom_text_field.dart';
import '../../../core/constants/app_colors.dart';
import 'package:Medaad/l10n/generated/app_localizations.dart';

enum ContentType { course, subject, chapter, video, pdf }

// ✅ مصدر الفيديو: رابط يوتيوب، أو رفع ملف مباشرةً من الجهاز (قابل للاستئناف)
enum VideoSourceMode { youtube, upload }

class ManageContentScreen extends StatefulWidget {
  final ContentType contentType;
  final String? parentId;
  final Map<String, dynamic>? initialData;

  const ManageContentScreen({
    Key? key,
    required this.contentType,
    this.parentId,
    this.initialData,
  }) : super(key: key);

  @override
  State<ManageContentScreen> createState() => _ManageContentScreenState();
}

class _ManageContentScreenState extends State<ManageContentScreen> {
  final _formKey = GlobalKey<FormState>();
  final TeacherService _teacherService = TeacherService();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();

  // ✅ إضافة متحكمات الوقت للفيديو
  final TextEditingController _hoursController = TextEditingController();
  final TextEditingController _minutesController = TextEditingController();
  final TextEditingController _secondsController = TextEditingController();

  File? _selectedFile;
  String? _selectedFileName;
  String? _uploadedFileUrl;
   
  bool _isLoading = false;
  double _uploadProgress = 0.0;
  
  // ✅ إضافة متغير التحكم في الإشعارات
  bool _notifyStudents = false;

  // ============================================================
  // 🎬 حالة رفع الفيديو المباشر (Bunny TUS) — قابل للاستئناف
  // ============================================================
  VideoSourceMode _videoSourceMode = VideoSourceMode.youtube;
  File? _videoFile;
  String? _videoFileName;
  int _videoFileSize = 0;
  int _extractedDurationSeconds = 0;
  bool _isExtractingDuration = false;
  bool _hasResumableSession = false;

  final BunnyTusUploadService _bunnyUploadService = BunnyTusUploadService();
  BunnyUploadStatus _bunnyStatus = BunnyUploadStatus.idle;
  double _bunnyProgress = 0.0;
  String? _bunnyError;

  bool get isEditing => widget.initialData != null;

  @override
  void initState() {
    super.initState();

    // ✅ الاستماع لتحديثات خدمة الرفع المباشر (تعمل حتى لو الشاشة لم تكن
    // هي من بدأت الرفع، مفيد لو رجع المستخدم لاحقاً لنفس الشاشة)
    _bunnyUploadService.onUpdate = (status, progress, error) {
      if (!mounted) return;
      setState(() {
        _bunnyStatus = status;
        _bunnyProgress = progress;
        _bunnyError = error;
      });
    };

    if (isEditing) {
      _titleController.text = widget.initialData!['title'] ?? '';
      _descController.text = widget.initialData!['description'] ?? '';
      
      // ✅ التحقق من مفتاح السعر بجميع احتمالاته (price أو fullPrice)
      var priceValue = widget.initialData!['price'] ?? widget.initialData!['fullPrice'];
      _priceController.text = priceValue?.toString() ?? '';

      if (widget.contentType == ContentType.video) {
        _urlController.text = widget.initialData!['youtube_video_id'] ?? '';
        // ✅ عند التعديل: نبدأ بنفس مصدر الفيديو الحالي (يوتيوب أو ملف مرفوع
        // عبر Bunny) لكن نسمح للمعلم بالتبديل بينهما واستبدال الفيديو فعلياً
        // (التبديل لرفع ملف يستخدم replaceVideoId لتحديث نفس السجل بدلاً من
        // إنشاء فيديو جديد، فيبقى نفس الـ id الذي يستخدمه الطلاب بالفعل).
        final bool hasExistingBunnyVideo =
            widget.initialData!['bunny_video_id'] != null;
        _videoSourceMode = hasExistingBunnyVideo
            ? VideoSourceMode.upload
            : VideoSourceMode.youtube;
        
        // ✅ توزيع الوقت الموجود مسبقاً على الحقول في حالة التعديل
        String? dur = widget.initialData!['duration'];
        if (dur != null && dur.isNotEmpty) {
          List<String> parts = dur.split(':');
          if (parts.length == 3) { // حالة (ساعات:دقائق:ثواني)
            _hoursController.text = parts[0];
            _minutesController.text = parts[1];
            _secondsController.text = parts[2];
          } else if (parts.length == 2) { // حالة (دقائق:ثواني) فقط
            _hoursController.text = '00';
            _minutesController.text = parts[0];
            _secondsController.text = parts[1];
          }
        }
      }
      if (widget.contentType == ContentType.pdf) {
        _uploadedFileUrl = widget.initialData!['file_path'] ?? widget.initialData!['file_url'];
        if (_uploadedFileUrl != null) {
          _selectedFileName = "Current PDF File";
        }
      }
    }
  }

  // ✅ دالة مساعدة لإنشاء حقل إدخال الوقت (ساعات/دقائق/ثواني)
  Widget _buildTimeField(String label, TextEditingController controller) {
    return Column(
      children: [
        SizedBox(
          width: 65,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.backgroundPrimary,
              hintText: "00",
              hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Future<void> _pickPdfFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null) {
      setState(() {
        _selectedFile = File(result.files.single.path!);
        _selectedFileName = result.files.single.name;
      });
    }
  }

  // ============================================================
  // 🎬 اختيار ملف فيديو من الجهاز + استخراج مدته تلقائياً
  // ============================================================
  Future<void> _pickVideoFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.video,
    );

    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    final fileSize = await file.length();

    setState(() {
      _videoFile = file;
      _videoFileName = result.files.single.name;
      _videoFileSize = fileSize;
      _extractedDurationSeconds = 0;
      _hasResumableSession = false;
    });

    // ✅ التحقق إن كان هناك رفع سابق متوقف لنفس الملف بالضبط (نفس المسار
    // والحجم وتاريخ التعديل) — يظهر للمعلم خيار "استئناف الرفع السابق"
    // ✅ نمرر replaceVideoId هنا أيضاً (عند التعديل) حتى يتطابق المفتاح مع
    // الذي سيُستخدم فعلياً عند بدء الرفع — وإلا لن يجد الجلسة المحفوظة
    // لاستبدال فيديو حتى لو كانت موجودة فعلاً.
    final hasSession = await _bunnyUploadService.hasResumableSession(
      file,
      isEditing ? widget.initialData!['id']?.toString() : null,
    );
    if (mounted) {
      setState(() => _hasResumableSession = hasSession);
    }

    await _extractLocalVideoDuration(file);
  }

  // يستخرج مدة الفيديو محلياً عبر مشغّل media_kit بدون عرضه (Headless)
  Future<void> _extractLocalVideoDuration(File file) async {
    setState(() => _isExtractingDuration = true);
    Player? player;
    try {
      player = Player();
      final completer = Future<int>(() async {
        await player!.open(Media(file.path), play: false);
        // ننتظر حتى تتوفر مدة حقيقية (> 0) أو تنتهي مهلة الانتظار
        for (int i = 0; i < 50; i++) {
          final d = player.state.duration;
          if (d.inMilliseconds > 0) return d.inSeconds;
          await Future.delayed(const Duration(milliseconds: 100));
        }
        return 0;
      });

      final seconds = await completer.timeout(
        const Duration(seconds: 8),
        onTimeout: () => 0,
      );

      if (mounted) {
        setState(() {
          _extractedDurationSeconds = seconds;
          if (seconds > 0) {
            final d = Duration(seconds: seconds);
            _hoursController.text = d.inHours.toString().padLeft(2, '0');
            _minutesController.text = (d.inMinutes % 60).toString().padLeft(2, '0');
            _secondsController.text = (d.inSeconds % 60).toString().padLeft(2, '0');
          }
        });
      }
    } catch (e) {
      debugPrint('⚠️ Failed to extract local video duration: $e');
    } finally {
      try {
        await player?.dispose();
      } catch (_) {}
      if (mounted) setState(() => _isExtractingDuration = false);
    }
  }

  @override
  void dispose() {
    // ✅ مهم: لا نُلغي الرفع الجاري هنا — يبقى يعمل في الخلفية عبر الـ
    // Singleton حتى لو غادر المعلم الشاشة، لكن نوقف فقط الاستماع لتحديثاته
    // من هذه الشاشة تحديداً لتفادي استدعاء setState على ودجت تم التخلص منه.
    if (_bunnyUploadService.onUpdate != null) {
      _bunnyUploadService.onUpdate = null;
    }
    _titleController.dispose();
    _descController.dispose();
    _priceController.dispose();
    _urlController.dispose();
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    super.dispose();
  }

  String? _extractYoutubeId(String url) {
    if (url.length == 11 && !url.contains('.')) return url;
    RegExp regExp = RegExp(
      r'.*(?:(?:youtu\.be\/|v\/|vi\/|u\/\w\/|embed\/|shorts\/)|(?:(?:watch)?\?v(?:i)?=|\&v(?:i)?=))([^#\&\?]*).*',
      caseSensitive: false,
      multiLine: false,
    );
    final match = regExp.firstMatch(url)?.group(1);
    return (match != null && match.length >= 11) ? match : null;
  }

  Future<void> _updateLocalCache() async {
    try {
      final updatedContent = await _teacherService.getMyContent();
      var box = await StorageService.openBox('teacher_data');
      await box.put('my_content', updatedContent);
      debugPrint("✅ Cache updated successfully in Hive");
    } catch (e) {
      debugPrint("⚠️ Failed to update local cache: $e");
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    // ============================================================
    // 🎬 فيديو مرفوع كملف من الجهاز: مسار منفصل بالكامل عبر TUS القابل
    // للاستئناف — لا يستخدم _isLoading/_uploadProgress العاديين لأن هذا
    // الرفع قد يستغرق وقتاً طويلاً ويحتاج عناصر تحكم خاصة (إيقاف/استئناف).
    // ============================================================
    // ✅ نسلك مسار رفع/استبدال Bunny TUS سواء كان إنشاءً جديداً أو تعديلاً،
    // بشرط أن المعلم اختار فعلاً ملفاً جديداً ليرفعه (_videoFile != null).
    // إن كان في وضع "رفع ملف" أثناء التعديل لكن لم يختر ملفاً جديداً، فهذا
    // يعني أنه يريد فقط تحديث العنوان/المدة دون استبدال الفيديو — في هذه
    // الحالة نكمل للمسار العادي بالأسفل (بدون لمس bunny_video_id).
    if (widget.contentType == ContentType.video &&
        _videoSourceMode == VideoSourceMode.upload &&
        _videoFile != null) {
      await _submitVideoUpload();
      return;
    }

    if (widget.contentType == ContentType.video) {
      int hVal = int.tryParse(_hoursController.text) ?? 0;
      int mVal = int.tryParse(_minutesController.text) ?? 0;
      int sVal = int.tryParse(_secondsController.text) ?? 0;

      if (hVal == 0 && mVal == 0 && sVal == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.videoDurationRequiredWarning), backgroundColor: AppColors.error),
        );
        return;
      }
      if (mVal > 59 || sVal > 59) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.minutesSecondsMaxWarning), backgroundColor: AppColors.error),
        );
        return;
      }
    }

    if (widget.contentType == ContentType.pdf && !isEditing && _selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.pleaseSelectPdfFileWarning), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _uploadProgress = 0.0;
    });

    try {
      String? finalFileUrl = _uploadedFileUrl;
      String? finalFileHash; // ✅ متغير لحفظ الهاش المرجع من السيرفر

      // 1. رفع الملف
      if (widget.contentType == ContentType.pdf && _selectedFile != null) {
        // ✅ استقبال Map بدلاً من String
        final uploadResult = await _teacherService.uploadFile(
          _selectedFile!,
          onProgress: (sent, total) {
            setState(() {
              _uploadProgress = sent / total;
            });
          },
        );
        
        finalFileUrl = uploadResult['url'];
        finalFileHash = uploadResult['contentHash']; // ✅ التقاط الهاش
      }

      setState(() => _uploadProgress = 0.0);

      // 2. تحضير البيانات للحفظ
      Map<String, dynamic> data = {
        'title': _titleController.text,
      };

      if (isEditing) {
        data['id'] = widget.initialData!['id'];
      }

      switch (widget.contentType) {
        case ContentType.course:
          data['description'] = _descController.text;
          data['price'] = double.tryParse(_priceController.text) ?? 0;
          break;
        case ContentType.subject:
          data['course_id'] = widget.parentId;
          data['price'] = double.tryParse(_priceController.text) ?? 0;
          break;
        case ContentType.chapter:
          data['subject_id'] = widget.parentId;
          break;
        case ContentType.video:
          data['chapter_id'] = widget.parentId;
          // ✅ نحدّث youtube_video_id فقط في وضع "رابط يوتيوب" — إن كان
          // المعلم يعدّل فيديو Bunny موجوداً (عنوان/مدة فقط بدون استبدال
          // الملف) فلا داعي لمسّ حقل اليوتيوب أصلاً، ولا لمحاولة استخراج
          // معرف من حقل رابط فارغ (كان سيُسبب خطأ "رابط الفيديو غير صحيح").
          if (_videoSourceMode == VideoSourceMode.youtube) {
            String? videoId = _extractYoutubeId(_urlController.text);
            if (videoId == null) throw Exception(AppLocalizations.of(context)!.invalidVideoUrlError);
            data['youtube_video_id'] = videoId;
          }
          if (!isEditing) data['notifyStudents'] = _notifyStudents;

          int hVal = int.tryParse(_hoursController.text) ?? 0;
          int mVal = int.tryParse(_minutesController.text) ?? 0;
          int sVal = int.tryParse(_secondsController.text) ?? 0;
          
          String hStr = hVal.toString().padLeft(2, '0');
          String mStr = mVal.toString().padLeft(2, '0');
          String sStr = sVal.toString().padLeft(2, '0');
          
          data['duration'] = hStr == '00' ? '$mStr:$sStr' : '$hStr:$mStr:$sStr';
          break;
        case ContentType.pdf:
          data['chapter_id'] = widget.parentId;
          if (finalFileUrl != null) data['file_path'] = finalFileUrl;
          // ✅ تمرير الهاش ليتم حفظه في قاعدة البيانات
          if (finalFileHash != null) data['content_hash'] = finalFileHash; 
          if (!isEditing) data['notifyStudents'] = _notifyStudents;
          break;
      }

      String dbType = '';
      switch (widget.contentType) {
        case ContentType.course: dbType = 'courses'; break;
        case ContentType.subject: dbType = 'subjects'; break;
        case ContentType.chapter: dbType = 'chapters'; break;
        case ContentType.video: dbType = 'videos'; break;
        case ContentType.pdf: dbType = 'pdfs'; break;
      }

      // 3. الحفظ في السيرفر (والذي سيستدعي content.js)
      await _teacherService.manageContent(
        action: isEditing ? 'update' : 'create',
        type: dbType,
        data: data,
      );

      // 4. تحديث الكاش المحلي
      await _updateLocalCache();

      // 5. التحديث المركزي
      await Future.delayed(const Duration(seconds: 1));
      await AppState().reloadAppInit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isEditing ? AppLocalizations.of(context)!.updatedSuccessfullyMessage : AppLocalizations.of(context)!.createdSuccessfullyMessage), backgroundColor: AppColors.success),
        );
        Navigator.pop(context, true);
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.contentSaveErrorWithDetails(e.toString().replaceAll('Exception:', ''))), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // 🎬 رفع فيديو كملف مباشرة إلى Bunny Stream (قابل للاستئناف)
  // ============================================================
  Future<void> _submitVideoUpload() async {
    if (_videoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.pleaseSelectVideoFileFirstWarning), backgroundColor: AppColors.error),
      );
      return;
    }

    // إن كانت هناك حالة خطأ سابقة لنفس الملف، الاستئناف يكمل من نفس النقطة
    // تلقائياً داخل الخدمة (لا حاجة لإعادة الرفع من الصفر) — لذا نُتابع بنفس
    // الاستدعاء العادي لـ startUpload في كل الحالات.
    // ✅ عند التعديل: نمرر replaceVideoId (نفس id الفيديو الحالي) حتى يقوم
    // السيرفر بتحديث نفس السجل بدلاً من إنشاء فيديو جديد — هذا ما يجعل
    // استبدال فيديو Bunny يعمل فعلياً من شاشة التعديل (وليس فقط عند الإنشاء).
    await _bunnyUploadService.startUpload(
      file: _videoFile!,
      chapterId: widget.parentId!,
      title: _titleController.text.isNotEmpty ? _titleController.text : _videoFileName!,
      notifyStudents: _notifyStudents,
      durationSeconds: _extractedDurationSeconds,
      replaceVideoId: isEditing ? widget.initialData!['id']?.toString() : null,
      onComplete: (result) async {
        await _updateLocalCache();
        await Future.delayed(const Duration(seconds: 1));
        await AppState().reloadAppInit();

        if (mounted) {
          final durationPending = result['durationPending'] == true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(durationPending
                  ? AppLocalizations.of(context)!.videoUploadedDurationPendingMessage
                  : AppLocalizations.of(context)!.videoUploadedSuccessMessage),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.pop(context, true);
        }
      },
      onError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error), backgroundColor: AppColors.error),
          );
        }
      },
    );
  }

  // يستأنف رفعاً متوقفاً بسبب خطأ (مثل انقطاع الاتصال) لنفس الملف الحالي
  Future<void> _resumeVideoUpload() async {
    if (_videoFile == null) return;
    await _submitVideoUpload();
  }

  Future<void> _cancelVideoUpload() async {
    await _bunnyUploadService.cancel(file: _videoFile);
    if (mounted) {
      setState(() {
        _hasResumableSession = false;
      });
    }
  }

  Future<void> _deleteItem() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        title: Text(AppLocalizations.of(context)!.confirmDelete, style: TextStyle(color: AppColors.textPrimary)),
        content: Text(AppLocalizations.of(context)!.confirmDeleteItemMessage, style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(context)!.cancel, style: TextStyle(color: AppColors.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(AppLocalizations.of(context)!.delete, style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      String dbType = '';
      switch (widget.contentType) {
        case ContentType.course: dbType = 'courses'; break;
        case ContentType.subject: dbType = 'subjects'; break;
        case ContentType.chapter: dbType = 'chapters'; break;
        case ContentType.video: dbType = 'videos'; break;
        case ContentType.pdf: dbType = 'pdfs'; break;
      }

      await _teacherService.manageContent(
        action: 'delete',
        type: dbType,
        data: {'id': widget.initialData!['id']},
      );

      await _updateLocalCache();

      await Future.delayed(const Duration(seconds: 1));
      await AppState().reloadAppInit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.deletedSuccessfullyMessage), backgroundColor: AppColors.success));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.deleteFailedWithDetails(e.toString())), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool get _isVideoUploadBusy => widget.contentType == ContentType.video &&
      _videoSourceMode == VideoSourceMode.upload &&
      [
        BunnyUploadStatus.requesting,
        BunnyUploadStatus.uploading,
        BunnyUploadStatus.paused,
        BunnyUploadStatus.confirming,
      ].contains(_bunnyStatus);

  String _bunnyStatusLabel() {
    switch (_bunnyStatus) {
      case BunnyUploadStatus.requesting:
        return AppLocalizations.of(context)!.preparingUploadSessionStatus;
      case BunnyUploadStatus.uploading:
        return AppLocalizations.of(context)!.uploadingVideoProgressStatus((_bunnyProgress * 100).toInt().toString());
      case BunnyUploadStatus.paused:
        return AppLocalizations.of(context)!.connectionLostWaitingStatus;
      case BunnyUploadStatus.confirming:
        return AppLocalizations.of(context)!.savingVideoDataStatus;
      default:
        return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    String titleText = '';
    switch (widget.contentType) {
      case ContentType.course: titleText = isEditing ? AppLocalizations.of(context)!.editCourseTitle : AppLocalizations.of(context)!.newCourseTitle; break;
      case ContentType.subject: titleText = isEditing ? AppLocalizations.of(context)!.editSubjectTitle : AppLocalizations.of(context)!.newSubjectTitle; break;
      case ContentType.chapter: titleText = isEditing ? AppLocalizations.of(context)!.editChapterTitle : AppLocalizations.of(context)!.newChapterTitle; break;
      case ContentType.video: titleText = isEditing ? AppLocalizations.of(context)!.editVideoTitle : AppLocalizations.of(context)!.newVideoTitle; break;
      case ContentType.pdf: titleText = isEditing ? AppLocalizations.of(context)!.editPdfTitle : AppLocalizations.of(context)!.newPdfTitle; break;
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(titleText, style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        leading: BackButton(color: AppColors.accentYellow),
        actions: [
          if (isEditing)
            IconButton(
              icon: Icon(Icons.delete_outline, color: AppColors.error),
              tooltip: AppLocalizations.of(context)!.delete,
              onPressed: (_isLoading || _isVideoUploadBusy) ? null : _deleteItem,
            ),
        ],
      ),
      body: (_isLoading || _isVideoUploadBusy)
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isVideoUploadBusy) ...[
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: _bunnyStatus == BunnyUploadStatus.uploading
                            ? _bunnyProgress
                            : null,
                        color: _bunnyStatus == BunnyUploadStatus.paused
                            ? AppColors.error
                            : AppColors.accentYellow,
                        strokeWidth: 6,
                        backgroundColor: AppColors.textSecondary.withOpacity(0.1),
                      ),
                      if (_bunnyStatus == BunnyUploadStatus.uploading)
                        Text(
                          "${(_bunnyProgress * 100).toInt()}%",
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      if (_bunnyStatus == BunnyUploadStatus.paused)
                        Icon(Icons.wifi_off, color: AppColors.error),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _bunnyStatusLabel(),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextButton.icon(
                    onPressed: _cancelVideoUpload,
                    icon: Icon(Icons.close, color: AppColors.error),
                    label: Text(AppLocalizations.of(context)!.cancelUploadAction, style: TextStyle(color: AppColors.error)),
                  ),
                ] else if (_uploadProgress > 0 && _uploadProgress < 1.0) ...[
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: _uploadProgress, 
                        color: AppColors.accentYellow,
                        strokeWidth: 6,
                        backgroundColor: AppColors.textSecondary.withOpacity(0.1),
                      ),
                      Text(
                        "${(_uploadProgress * 100).toInt()}%",
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(AppLocalizations.of(context)!.uploadingFileStatus, style: TextStyle(color: AppColors.textSecondary)),
                ] else ...[
                  CircularProgressIndicator(color: AppColors.accentYellow),
                  const SizedBox(height: 16),
                  Text(AppLocalizations.of(context)!.savingDataStatus, style: TextStyle(color: AppColors.textSecondary)),
                ]
              ],
            ),
          )
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  CustomTextField(
                    label: AppLocalizations.of(context)!.titleNameLabel,
                    controller: _titleController,
                    hintText: AppLocalizations.of(context)!.enterTitleHereHint,
                    prefixIcon: Icons.title,
                    validator: (val) => val!.isEmpty ? AppLocalizations.of(context)!.requiredField : null,
                  ),
                  const SizedBox(height: 16),

                  if (widget.contentType == ContentType.course) ...[
                    CustomTextField(
                      label: AppLocalizations.of(context)!.descriptionFieldLabel,
                      controller: _descController,
                      hintText: AppLocalizations.of(context)!.enterDescriptionHint,
                      prefixIcon: Icons.description,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (widget.contentType == ContentType.course || widget.contentType == ContentType.subject) ...[
                    CustomTextField(
                      label: AppLocalizations.of(context)!.priceEgpFieldLabel,
                      controller: _priceController,
                      hintText: AppLocalizations.of(context)!.zeroPointZeroHint,
                      prefixIcon: Icons.attach_money,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (widget.contentType == ContentType.video) ...[
                    // ✅ مفتاح اختيار مصدر الفيديو: رابط يوتيوب أو رفع ملف —
                    // متاح أيضاً أثناء التعديل: التبديل لرفع ملف يستبدل
                    // الفيديو الحالي فعلياً (نفس الـ id يبقى كما هو للطلاب).
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _videoSourceMode = VideoSourceMode.youtube),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _videoSourceMode == VideoSourceMode.youtube
                                      ? AppColors.accentYellow
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  AppLocalizations.of(context)!.youtubeLinkTabLabel,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _videoSourceMode == VideoSourceMode.youtube
                                        ? AppColors.backgroundPrimary
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _videoSourceMode = VideoSourceMode.upload),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _videoSourceMode == VideoSourceMode.upload
                                      ? AppColors.accentYellow
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  AppLocalizations.of(context)!.uploadVideoFileTabLabel,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _videoSourceMode == VideoSourceMode.upload
                                        ? AppColors.backgroundPrimary
                                        : AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (isEditing && _videoSourceMode == VideoSourceMode.upload) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.accentYellow.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.accentYellow.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: AppColors.accentYellow, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                AppLocalizations.of(context)!.newFileReplaceWarning,
                                style: TextStyle(color: AppColors.accentYellow, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (_videoSourceMode == VideoSourceMode.youtube) ...[
                      CustomTextField(
                        label: AppLocalizations.of(context)!.youtubeVideoLinkLabel,
                        controller: _urlController,
                        hintText: "https://youtu.be/...",
                        prefixIcon: Icons.video_library,
                      ),
                      const SizedBox(height: 16),

                      // ✅ واجهة الوقت (ساعات : دقائق : ثواني) الأنيقة
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(AppLocalizations.of(context)!.actualVideoDurationLabel, style: TextStyle(color: AppColors.accentYellow, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildTimeField(AppLocalizations.of(context)!.hoursLabel, _hoursController),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text(":", style: TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                            _buildTimeField(AppLocalizations.of(context)!.minutesLabel, _minutesController),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text(":", style: TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                            _buildTimeField(AppLocalizations.of(context)!.secondsLabel, _secondsController),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(AppLocalizations.of(context)!.pasteYoutubeLinkHint,
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary.withOpacity(0.6))),
                    ] else ...[
                      // ============================================================
                      // 🎬 رفع ملف فيديو مباشرةً (قابل للاستئناف بعد انقطاع الاتصال)
                      // ============================================================
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.video_file, color: AppColors.accentOrange, size: 30),
                          title: Text(
                            _videoFileName ?? AppLocalizations.of(context)!.noFileSelectedVideo,
                            style: TextStyle(
                              color: _videoFileName == null ? AppColors.textSecondary : AppColors.textPrimary,
                              fontWeight: _videoFileName == null ? FontWeight.normal : FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            _videoFileName == null
                                ? AppLocalizations.of(context)!.tapToSelectVideoFile
                                : _isExtractingDuration
                                    ? AppLocalizations.of(context)!.extractingVideoDurationStatus
                                    : "${(_videoFileSize / (1024 * 1024)).toStringAsFixed(1)} MB",
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                          ),
                          trailing: Icon(Icons.upload_file, color: AppColors.accentYellow),
                          onTap: _pickVideoFile,
                        ),
                      ),

                      if (_hasResumableSession) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.accentYellow.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.accentYellow.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.history, color: AppColors.accentYellow, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  AppLocalizations.of(context)!.resumableUploadFoundMessage,
                                  style: TextStyle(color: AppColors.accentYellow, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (_bunnyStatus == BunnyUploadStatus.error && _bunnyError != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.error.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(_bunnyError!, style: TextStyle(color: AppColors.error, fontSize: 12)),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: _resumeVideoUpload,
                                icon: const Icon(Icons.refresh, size: 18),
                                label: Text(AppLocalizations.of(context)!.resumeUploadAction),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accentYellow,
                                  foregroundColor: AppColors.backgroundPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context)!.uploadPauseResumeInfoMessage,
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary.withOpacity(0.6)),
                      ),

                      if (_videoFileName != null) ...[
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(AppLocalizations.of(context)!.videoDurationAutoExtractedLabel,
                              style: TextStyle(color: AppColors.accentYellow, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundSecondary,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildTimeField(AppLocalizations.of(context)!.hoursLabel, _hoursController),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Text(":", style: TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                              _buildTimeField(AppLocalizations.of(context)!.minutesLabel, _minutesController),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 10),
                                child: Text(":", style: TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                              _buildTimeField(AppLocalizations.of(context)!.secondsLabel, _secondsController),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ],


                  if (widget.contentType == ContentType.pdf) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.picture_as_pdf, color: AppColors.accentOrange, size: 30),
                        title: Text(
                          _selectedFileName ?? AppLocalizations.of(context)!.noPdfFileSelected,
                          style: TextStyle(
                            color: _selectedFileName == null ? AppColors.textSecondary : AppColors.textPrimary,
                            fontWeight: _selectedFileName == null ? FontWeight.normal : FontWeight.bold,
                            fontSize: 14
                          ),
                        ),
                        subtitle: Text(AppLocalizations.of(context)!.tapToSelectPdfLabel, style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        trailing: Icon(Icons.upload_file, color: AppColors.accentYellow),
                        onTap: _pickPdfFile,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // ✅ إضافة زر التنبيه بالإشعارات عند إنشاء فيديو أو PDF جديد فقط
                  if (!isEditing && (widget.contentType == ContentType.video || widget.contentType == ContentType.pdf)) ...[
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
                      ),
                      child: SwitchListTile(
                        title: Text(AppLocalizations.of(context)!.sendNotificationToStudentsLabel, style: TextStyle(color: AppColors.accentYellow)),
                        subtitle: Text(AppLocalizations.of(context)!.notifySubscribedStudentsSubtitle, style: TextStyle(color: AppColors.textSecondary)),
                        value: _notifyStudents,
                        activeColor: AppColors.accentYellow,
                        onChanged: (val) => setState(() => _notifyStudents = val),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  const SizedBox(height: 32),

                  ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: AppColors.accentYellow,
                      foregroundColor: AppColors.backgroundPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      isEditing
                          ? AppLocalizations.of(context)!.saveChangesUpperAction
                          : (widget.contentType == ContentType.video &&
                                  _videoSourceMode == VideoSourceMode.upload)
                              ? (_hasResumableSession ? AppLocalizations.of(context)!.resumeAndUploadVideoAction : AppLocalizations.of(context)!.uploadVideoAction)
                              : AppLocalizations.of(context)!.createUpperAction,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                    ),
                  ),

                  if (isEditing) ...[
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _deleteItem,
                      icon: Icon(Icons.delete, color: AppColors.error),
                      label: Text(AppLocalizations.of(context)!.deletePermanentlyUpperAction, style: TextStyle(color: AppColors.error)),
                    ),
                  ],
                ],
              ),
            ),
          ),
    );
  }
}
