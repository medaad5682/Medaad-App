import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/services/teacher_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/services/app_state.dart'; // ✅ ضروري لتحديث الحالة العامة
import '../../widgets/custom_text_field.dart';
import '../../../core/constants/app_colors.dart';

enum ContentType { course, subject, chapter, video, pdf }

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

  bool get isEditing => widget.initialData != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      _titleController.text = widget.initialData!['title'] ?? '';
      _descController.text = widget.initialData!['description'] ?? '';
      
      // ✅ التحقق من مفتاح السعر بجميع احتمالاته (price أو fullPrice)
      var priceValue = widget.initialData!['price'] ?? widget.initialData!['fullPrice'];
      _priceController.text = priceValue?.toString() ?? '';

      if (widget.contentType == ContentType.video) {
        _urlController.text = widget.initialData!['youtube_video_id'] ?? '';
        
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

    // ✅ التحقق الإجباري من الوقت قبل بدء التحميل للفيديو
    if (widget.contentType == ContentType.video) {
      int hVal = int.tryParse(_hoursController.text) ?? 0;
      int mVal = int.tryParse(_minutesController.text) ?? 0;
      int sVal = int.tryParse(_secondsController.text) ?? 0;

      if (hVal == 0 && mVal == 0 && sVal == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text("⚠️ يرجى إدخال مدة الفيديو الفعلية (لا يمكن تركها أصفاراً)"), backgroundColor: AppColors.error),
        );
        return;
      }
      if (mVal > 59 || sVal > 59) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text("⚠️ الدقائق والثواني يجب ألا تتجاوز 59"), backgroundColor: AppColors.error),
        );
        return;
      }
    }

    if (widget.contentType == ContentType.pdf && !isEditing && _selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text("Please select a PDF file"), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _uploadProgress = 0.0;
    });

    try {
      String? finalFileUrl = _uploadedFileUrl;

      // 1. رفع الملف
      if (widget.contentType == ContentType.pdf && _selectedFile != null) {
        finalFileUrl = await _teacherService.uploadFile(
          _selectedFile!,
          onProgress: (sent, total) {
            setState(() {
              _uploadProgress = sent / total;
            });
          },
        );
      }

      setState(() => _uploadProgress = 0.0);

      // 2. تحضير البيانات
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
          String? videoId = _extractYoutubeId(_urlController.text);
          if (videoId == null) throw Exception("رابط الفيديو غير صحيح");
          data['youtube_video_id'] = videoId;
          if (!isEditing) data['notifyStudents'] = _notifyStudents;

          // ✅ تجميع الوقت وتنسيقه وإرساله
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

      // 3. الحفظ في السيرفر
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
          SnackBar(content: Text(isEditing ? "Updated Successfully" : "Created Successfully"), backgroundColor: AppColors.success),
        );
        Navigator.pop(context, true);
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.toString().replaceAll('Exception:', '')}"), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteItem() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        title: Text("Confirm Delete", style: TextStyle(color: AppColors.textPrimary)),
        content: Text("Are you sure you want to delete this item? This cannot be undone.", style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("Cancel", style: TextStyle(color: AppColors.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text("Deleted Successfully"), backgroundColor: AppColors.success));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Delete Failed: $e"), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String titleText = '';
    switch (widget.contentType) {
      case ContentType.course: titleText = isEditing ? "Edit Course" : "New Course"; break;
      case ContentType.subject: titleText = isEditing ? "Edit Subject" : "New Subject"; break;
      case ContentType.chapter: titleText = isEditing ? "Edit Chapter" : "New Chapter"; break;
      case ContentType.video: titleText = isEditing ? "Edit Video" : "New Video"; break;
      case ContentType.pdf: titleText = isEditing ? "Edit PDF" : "New PDF"; break;
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
              tooltip: "Delete",
              onPressed: _isLoading ? null : _deleteItem,
            ),
        ],
      ),
      body: _isLoading
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_uploadProgress > 0 && _uploadProgress < 1.0) ...[
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
                  Text("Uploading File...", style: TextStyle(color: AppColors.textSecondary)),
                ] else ...[
                  CircularProgressIndicator(color: AppColors.accentYellow),
                  const SizedBox(height: 16),
                  Text("Saving Data...", style: TextStyle(color: AppColors.textSecondary)),
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
                    label: "Title / Name",
                    controller: _titleController,
                    hintText: "Enter title here",
                    prefixIcon: Icons.title,
                    validator: (val) => val!.isEmpty ? "Required" : null,
                  ),
                  const SizedBox(height: 16),

                  if (widget.contentType == ContentType.course) ...[
                    CustomTextField(
                      label: "Description",
                      controller: _descController,
                      hintText: "Enter description",
                      prefixIcon: Icons.description,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (widget.contentType == ContentType.course || widget.contentType == ContentType.subject) ...[
                    CustomTextField(
                      label: "Price (EGP)",
                      controller: _priceController,
                      hintText: "0.0",
                      prefixIcon: Icons.attach_money,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (widget.contentType == ContentType.video) ...[
                    CustomTextField(
                      label: "رابط فيديو يوتيوب",
                      controller: _urlController,
                      hintText: "https://youtu.be/...",
                      prefixIcon: Icons.video_library,
                    ),
                    const SizedBox(height: 16),
                    
                    // ✅ واجهة الوقت (ساعات : دقائق : ثواني) الأنيقة
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text("مدة الفيديو الفعلية ⏱️", style: TextStyle(color: AppColors.accentYellow, fontWeight: FontWeight.bold)),
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
                          _buildTimeField("ساعات", _hoursController),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Text(":", style: TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                          _buildTimeField("دقائق", _minutesController),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Text(":", style: TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                          _buildTimeField("ثواني", _secondsController),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text("الصق رابط يوتيوب كاملاً وحدد مدته لتظهر للطلاب",
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary.withOpacity(0.6))),
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
                          _selectedFileName ?? "No file selected",
                          style: TextStyle(
                            color: _selectedFileName == null ? AppColors.textSecondary : AppColors.textPrimary,
                            fontWeight: _selectedFileName == null ? FontWeight.normal : FontWeight.bold,
                            fontSize: 14
                          ),
                        ),
                        subtitle: Text("Tap to select PDF", style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
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
                        title: Text("إرسال إشعار للطلاب", style: TextStyle(color: AppColors.accentYellow)),
                        subtitle: Text("تنبيه الطلاب المشتركين بإضافة هذا المحتوى", style: TextStyle(color: AppColors.textSecondary)),
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
                      isEditing ? "SAVE CHANGES" : "CREATE",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                    ),
                  ),

                  if (isEditing) ...[
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: _deleteItem,
                      icon: Icon(Icons.delete, color: AppColors.error),
                      label: Text("DELETE PERMANENTLY", style: TextStyle(color: AppColors.error)),
                    ),
                  ],
                ],
              ),
            ),
          ),
    );
  }
}
