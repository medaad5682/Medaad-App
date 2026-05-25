import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/constants/app_colors.dart'; 
import '../../../core/services/teacher_service.dart';
import '../../widgets/custom_text_field.dart';

class CreateExamScreen extends StatefulWidget {
  final String subjectId; // معرف المادة
  final String? examId;   // معرف الامتحان (اختياري - للتعديل)

  const CreateExamScreen({Key? key, required this.subjectId, this.examId}) : super(key: key);

  @override
  State<CreateExamScreen> createState() => _CreateExamScreenState();
}

class _CreateExamScreenState extends State<CreateExamScreen> {
  final _formKey = GlobalKey<FormState>();
  final TeacherService _teacherService = TeacherService();

  // بيانات الامتحان الأساسية
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
   
  bool _randomizeQuestions = true;
  bool _randomizeOptions = true; 
  
  // ✅ إضافة متغيرات الإعادة والإشعارات
  bool _allowRetake = false;
  bool _notifyStudents = false;
   
  DateTime? _startDate; 
  DateTime? _endDate;      
   
  List<QuestionModel> _questions = [];
  bool _isSubmitting = false;
  bool _isLoadingDetails = false;

  @override
  void initState() {
    super.initState();
    if (widget.examId != null) {
      _loadExamDetails();
    }
  }

  // --- جلب تفاصيل الامتحان للتعديل ---
  Future<void> _loadExamDetails() async {
    setState(() => _isLoadingDetails = true);
    try {
      final data = await _teacherService.getExamDetails(widget.examId!);
      
      setState(() {
        _titleController.text = data['title'] ?? '';
        _durationController.text = (data['duration_minutes'] ?? 0).toString();
        _randomizeQuestions = data['randomizeQuestions'] ?? true;
        _randomizeOptions = data['randomizeOptions'] ?? true;
        
        // ✅ جلب إعداد سماحية الإعادة من السيرفر
        _allowRetake = data['allow_retake'] ?? false;
        
        if (data['start_time'] != null) {
          _startDate = DateTime.parse(data['start_time']).toLocal();
        }
        if (data['end_time'] != null) {
          _endDate = DateTime.parse(data['end_time']).toLocal();
        }

        if (data['questions'] != null) {
          _questions = (data['questions'] as List).map((q) {
            int correctIndex = 0;
            List<String> options = [];
            
            if (q['options'] != null) {
              var sortedOptions = List.from(q['options']);
              sortedOptions.sort((a, b) => (a['sort_order'] ?? 0).compareTo(b['sort_order'] ?? 0));

              for (int i = 0; i < sortedOptions.length; i++) {
                var opt = sortedOptions[i];
                options.add(opt['option_text']);
                if (opt['is_correct'] == true) {
                  correctIndex = i;
                }
              }
            }

            return QuestionModel(
              text: q['question_text'],
              options: options,
              correctOptionIndex: correctIndex,
              imageUrl: q['image_file_id'],
            );
          }).toList();
        }
      });

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("فشل تحميل بيانات الامتحان: $e"), backgroundColor: AppColors.error));
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isLoadingDetails = false);
    }
  }

  // --- دوال اختيار الوقت والتاريخ ---
  Future<void> _pickDateTime(bool isStart) async {
    final now = DateTime.now();
    
    DateTime initialDate;
    if (isStart) {
      initialDate = _startDate ?? now;
    } else {
      initialDate = _endDate ?? (_startDate ?? now);
    }

    final firstDate = isStart ? DateTime(2023) : (_startDate ?? DateTime(2023));

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(firstDate) ? firstDate : initialDate,
      firstDate: firstDate,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(primary: AppColors.accentYellow),
          ),
          child: child!,
        );
      },
    );
    
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(primary: AppColors.accentYellow),
          ),
          child: child!,
        );
      },
    );

    if (time == null) return;

    final dateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    
    if (isStart) {
      if (_endDate != null && dateTime.isAfter(_endDate!)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("تاريخ البدء لا يمكن أن يكون بعد تاريخ الانتهاء!"), backgroundColor: AppColors.error)
          );
        }
        return;
      }
      setState(() => _startDate = dateTime);
    } else {
      if (_startDate != null && dateTime.isBefore(_startDate!)) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("تاريخ الانتهاء لا يمكن أن يكون قبل تاريخ البدء!"), backgroundColor: AppColors.error)
          );
        }
        return;
      }
      setState(() => _endDate = dateTime);
    }
  }

  // --- دالة إضافة/تعديل سؤال ---
  void _openQuestionDialog({QuestionModel? existingQuestion, int? index}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => QuestionDialog(
        initialQuestion: existingQuestion,
        onSave: (question) {
          setState(() {
            if (index != null) {
              _questions[index] = question;
            } else {
              _questions.add(question);
            }
          });
        },
      ),
    );
  }

  // --- حذف الامتحان ---
  Future<void> _deleteExam() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundSecondary,
        title: Text("حذف الامتحان", style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
        content: Text(
          "هل أنت متأكد من حذف هذا الامتحان؟\n\n"
          "⚠️ تحذير: سيتم حذف جميع الأسئلة وجميع نتائج الطلاب المرتبطة بهذا الامتحان بشكل نهائي.",
          style: TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("إلغاء", style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text("حذف نهائي", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSubmitting = true);

    try {
      await _teacherService.deleteExam(widget.examId!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("تم حذف الامتحان بنجاح"), backgroundColor: AppColors.success),
        );
        Navigator.pop(context, true); 
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("فشل الحذف: $e"), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // --- الحفظ والإرسال ---
  Future<void> _submitExam() async {
    if (!_formKey.currentState!.validate()) return;
    if (_questions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("يجب إضافة سؤال واحد على الأقل"), backgroundColor: AppColors.error));
      return;
    }
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("يرجى تحديد وقت بداية ونهاية الامتحان"), backgroundColor: AppColors.error));
      return;
    }
    
    if (_startDate!.isAfter(_endDate!)) {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: وقت البداية بعد وقت النهاية!"), backgroundColor: AppColors.error));
       return;
    }

    setState(() => _isSubmitting = true);

    try {
      List<Map<String, dynamic>> processedQuestions = [];
      
      for (var q in _questions) {
        String? imageUrl = q.imageUrl;
        
        if (q.imageFile != null) {
          final uploadResult = await _teacherService.uploadFile(q.imageFile!);
imageUrl = uploadResult['url']; // استخراج الرابط فقط
        }

        processedQuestions.add({
          'text': q.text,
          'options': q.options,
          'correctIndex': q.correctOptionIndex,
          'image': imageUrl, 
        });
      }

      // ✅ بناء كائن البيانات للإرسال
      final examData = {
        'title': _titleController.text,
        'subjectId': widget.subjectId,
        'duration': int.parse(_durationController.text),
        'randomizeQuestions': _randomizeQuestions, 
        'randomizeOptions': _randomizeOptions,     
        'allow_retake': _allowRetake, // ✅ إرسال إعداد السماح بالتدريب
        'notifyStudents': _notifyStudents, // ✅ إرسال إعداد الإشعارات
        'start_time': _startDate!.toIso8601String(), 
        'end_time': _endDate!.toIso8601String(),
        'questions': processedQuestions,
      };

      if (widget.examId != null) {
        examData['examId'] = widget.examId!;
      }

      await _teacherService.createExam(examData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.examId != null ? "تم تحديث الامتحان بنجاح" : "تم إنشاء الامتحان بنجاح"), 
            backgroundColor: AppColors.success
          )
        );
        Navigator.pop(context, true);
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("حدث خطأ: $e"), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingDetails) {
      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        body: Center(child: CircularProgressIndicator(color: AppColors.accentYellow)),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: Text(widget.examId != null ? "تعديل الامتحان" : "إنشاء امتحان جديد", style: TextStyle(color: AppColors.textPrimary)),
        backgroundColor: AppColors.backgroundSecondary,
        iconTheme: IconThemeData(color: AppColors.accentYellow),
        actions: [
          if (widget.examId != null)
            IconButton(
              icon: Icon(Icons.delete_forever, color: AppColors.error),
              onPressed: _isSubmitting ? null : _deleteExam,
              tooltip: "حذف الامتحان",
            )
        ],
      ),
      body: _isSubmitting
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: AppColors.accentYellow),
                const SizedBox(height: 20),
                Text("جاري التنفيذ...", style: TextStyle(color: AppColors.textPrimary))
              ],
            ))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  CustomTextField(
                    label: "عنوان الامتحان",
                    controller: _titleController,
                    hintText: "مثال: امتحان شامل الفصل الأول",
                    prefixIcon: Icons.quiz,
                    validator: (val) => val!.isEmpty ? "مطلوب" : null,
                  ),
                  const SizedBox(height: 15),
                  
                  CustomTextField(
                    label: "المدة (دقائق)",
                    controller: _durationController,
                    hintText: "أدخل مدة الامتحان",
                    prefixIcon: Icons.timer,
                    keyboardType: TextInputType.number,
                    validator: (val) => val!.isEmpty ? "مطلوب" : null,
                  ),
                  const SizedBox(height: 15),

                  Card(
                    color: AppColors.backgroundSecondary,
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: Text("ترتيب أسئلة عشوائي", style: TextStyle(color: AppColors.textPrimary)),
                          subtitle: Text("يظهر لكل طالب ترتيب أسئلة مختلف", style: TextStyle(color: AppColors.textSecondary)),
                          value: _randomizeQuestions,
                          activeColor: AppColors.accentYellow,
                          onChanged: (val) => setState(() => _randomizeQuestions = val),
                        ),
                        Divider(height: 1, color: AppColors.textSecondary.withOpacity(0.1)),
                        SwitchListTile(
                          title: Text("ترتيب اختيارات عشوائي", style: TextStyle(color: AppColors.textPrimary)),
                          subtitle: Text("تغيير أماكن الإجابات داخل كل سؤال", style: TextStyle(color: AppColors.textSecondary)),
                          value: _randomizeOptions,
                          activeColor: AppColors.accentYellow,
                          onChanged: (val) => setState(() => _randomizeOptions = val),
                        ),
                        
                        // ✅ إضافة خيار السماح بإعادة الامتحان (التدريب)
                        Divider(height: 1, color: AppColors.textSecondary.withOpacity(0.1)),
                        SwitchListTile(
                          title: Text("السماح بإعادة الامتحان (تدريب)", style: TextStyle(color: AppColors.textPrimary)),
                          subtitle: Text("يمكن للطالب إعادة الامتحان دون التأثير على درجته الأولى", style: TextStyle(color: AppColors.textSecondary)),
                          value: _allowRetake,
                          activeColor: AppColors.accentYellow,
                          onChanged: (val) => setState(() => _allowRetake = val),
                        ),

                        // ✅ خيار إرسال الإشعار يظهر فقط في حالة إنشاء امتحان جديد
                        if (widget.examId == null) ...[
                          Divider(height: 1, color: AppColors.textSecondary.withOpacity(0.1)),
                          SwitchListTile(
                            title: Text("إرسال إشعار للطلاب", style: TextStyle(color: AppColors.accentYellow)),
                            subtitle: Text("تنبيه الطلاب المشتركين بإضافة هذا الامتحان", style: TextStyle(color: AppColors.textSecondary)),
                            value: _notifyStudents,
                            activeColor: AppColors.accentYellow,
                            onChanged: (val) => setState(() => _notifyStudents = val),
                          ),
                        ],

                        Divider(thickness: 2, color: AppColors.textSecondary.withOpacity(0.1)),
                        ListTile(
                          leading: const Icon(Icons.calendar_today, color: Colors.blue),
                          title: Text(_startDate == null ? "تاريخ ووقت التفعيل (البداية)" : "يبدأ: ${_formatDate(_startDate!)}", style: TextStyle(color: AppColors.textPrimary)),
                          subtitle: Text("اضغط لتحديد البداية", style: TextStyle(color: AppColors.textSecondary)),
                          onTap: () => _pickDateTime(true),
                        ),
                        ListTile(
                          leading: Icon(Icons.event_busy, color: AppColors.error),
                          title: Text(_endDate == null ? "تاريخ ووقت الإغلاق (النهاية)" : "ينتهي: ${_formatDate(_endDate!)}", style: TextStyle(color: AppColors.textPrimary)),
                          subtitle: Text("اضغط لتحديد النهاية", style: TextStyle(color: AppColors.textSecondary)),
                          onTap: () => _pickDateTime(false),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("الأسئلة (${_questions.length})", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      ElevatedButton.icon(
                        onPressed: () => _openQuestionDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text("إضافة سؤال"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentYellow,
                          foregroundColor: AppColors.backgroundPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  if (_questions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(child: Text("لم تتم إضافة أسئلة بعد", style: TextStyle(color: AppColors.textSecondary))),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _questions.length,
                      itemBuilder: (context, index) {
                        final q = _questions[index];
                        return Card(
                          color: AppColors.backgroundSecondary,
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: CircleAvatar(
                                backgroundColor: AppColors.accentYellow,
                                child: Text("${index + 1}", style: TextStyle(color: AppColors.backgroundPrimary))
                            ),
                            title: Text(q.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textPrimary)),
                            subtitle: Text("${q.options.length} اختيارات • ${q.imageFile != null ? "صورة جديدة" : (q.imageUrl != null ? "صورة محفوظة" : "نص فقط")}", style: TextStyle(color: AppColors.textSecondary)),
                            trailing: IconButton(
                              icon: Icon(Icons.delete, color: AppColors.error),
                              onPressed: () => setState(() => _questions.removeAt(index)),
                            ),
                            onTap: () => _openQuestionDialog(existingQuestion: q, index: index),
                          ),
                        );
                      },
                    ),

                  const SizedBox(height: 30),
                  ElevatedButton(
                    onPressed: _submitExam,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      backgroundColor: AppColors.accentYellow,
                    ),
                    child: Text(
                      widget.examId != null ? "حفظ التعديلات" : "حفظ ونشر الامتحان", 
                      style: TextStyle(fontSize: 18, color: AppColors.backgroundPrimary, fontWeight: FontWeight.bold)
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  String _formatDate(DateTime d) {
    return "${d.year}-${d.month}-${d.day} ${d.hour}:${d.minute.toString().padLeft(2, '0')}";
  }
}

// ==========================================================
// 🧩 مودل السؤال
// ==========================================================
class QuestionModel {
  String text;
  List<String> options;
  int correctOptionIndex;
  File? imageFile;
  String? imageUrl;

  QuestionModel({
    required this.text,
    required this.options,
    required this.correctOptionIndex,
    this.imageFile,
    this.imageUrl,
  });
}

// ==========================================================
// 💬 نافذة إضافة/تعديل السؤال (ديناميكية)
// ==========================================================
class QuestionDialog extends StatefulWidget {
  final QuestionModel? initialQuestion;
  final Function(QuestionModel) onSave;

  const QuestionDialog({Key? key, this.initialQuestion, required this.onSave}) : super(key: key);

  @override
  State<QuestionDialog> createState() => _QuestionDialogState();
}

class _QuestionDialogState extends State<QuestionDialog> {
  final _qFormKey = GlobalKey<FormState>();
  final TextEditingController _questionTextController = TextEditingController();
   
  List<TextEditingController> _optionControllers = [];
   
  int _correctIndex = 0;
  File? _selectedImage;
  String? _existingImageUrl;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuestion != null) {
      _questionTextController.text = widget.initialQuestion!.text;
      
      for (var option in widget.initialQuestion!.options) {
        _optionControllers.add(TextEditingController(text: option));
      }
      
      _correctIndex = widget.initialQuestion!.correctOptionIndex;
      _selectedImage = widget.initialQuestion!.imageFile;
      _existingImageUrl = widget.initialQuestion!.imageUrl;
    } else {
      _optionControllers = List.generate(4, (_) => TextEditingController());
    }
  }

  @override
  void dispose() {
    _questionTextController.dispose();
    for (var c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image, 
    );

    if (result != null) {
      setState(() {
        _selectedImage = File(result.files.single.path!);
      });
    }
  }

  void _addOption() {
    setState(() {
      _optionControllers.add(TextEditingController());
    });
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("يجب أن يحتوي السؤال على خيارين على الأقل"), backgroundColor: AppColors.error)
      );
      return;
    }

    setState(() {
      _optionControllers[index].dispose();
      _optionControllers.removeAt(index);
      
      if (_correctIndex == index) {
        _correctIndex = 0;
      } else if (_correctIndex > index) {
        _correctIndex--;
      }
    });
  }

  void _save() {
    if (!_qFormKey.currentState!.validate()) return;

    List<String> options = _optionControllers.map((c) => c.text.trim()).toList();
    
    if (options.any((o) => o.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("يرجى ملء جميع حقول الخيارات أو حذف الفارغ منها"), backgroundColor: AppColors.error)
      );
      return;
    }

    if (_correctIndex >= options.length) {
      _correctIndex = 0;
    }

    final newQuestion = QuestionModel(
      text: _questionTextController.text,
      options: options,
      correctOptionIndex: _correctIndex,
      imageFile: _selectedImage,
      imageUrl: _existingImageUrl, 
    );

    widget.onSave(newQuestion);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.backgroundSecondary,
      title: Text(
          widget.initialQuestion == null ? "سؤال جديد" : "تعديل السؤال",
          style: TextStyle(color: AppColors.textPrimary)
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Form(
            key: _qFormKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _questionTextController,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: "نص السؤال",
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accentYellow)),
                  ),
                  maxLines: 2,
                  validator: (val) => val!.isEmpty ? "مطلوب" : null,
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedImage != null 
                            ? "تم اختيار صورة جديدة" 
                            : (_existingImageUrl != null ? "صورة محفوظة مسبقاً" : "لا توجد صورة"),
                        style: TextStyle(
                          color: _selectedImage != null ? AppColors.success : AppColors.textSecondary,
                          fontWeight: _selectedImage != null ? FontWeight.bold : FontWeight.normal
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _pickImage,
                      icon: Icon(Icons.image, color: AppColors.accentYellow),
                      tooltip: "رفع/تغيير صورة",
                    ),
                    if (_selectedImage != null || _existingImageUrl != null)
                      IconButton(
                        icon: Icon(Icons.close, color: AppColors.error),
                        tooltip: "حذف الصورة",
                        onPressed: () => setState(() {
                          _selectedImage = null;
                          _existingImageUrl = null;
                        }),
                      )
                  ],
                ),
                Divider(color: AppColors.textSecondary.withOpacity(0.1)),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("الخيارات (حدد الصحيحة):", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    TextButton.icon(
                      onPressed: _addOption,
                      icon: Icon(Icons.add_circle, size: 18, color: AppColors.accentYellow),
                      label: Text("إضافة خيار", style: TextStyle(color: AppColors.accentYellow)),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                
                ...List.generate(_optionControllers.length, (index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Row(
                      children: [
                        Radio<int>(
                          value: index,
                          groupValue: _correctIndex,
                          activeColor: AppColors.success,
                          onChanged: (val) => setState(() => _correctIndex = val!),
                        ),
                        Expanded(
                          child: TextFormField(
                            controller: _optionControllers[index],
                            style: TextStyle(color: AppColors.textPrimary),
                            decoration: InputDecoration(
                              labelText: "الخيار ${index + 1}",
                              labelStyle: TextStyle(color: AppColors.textSecondary),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accentYellow)),
                            ),
                            validator: (val) => val!.isEmpty ? "مطلوب" : null,
                          ),
                        ),
                        if (_optionControllers.length > 2)
                          IconButton(
                            icon: Icon(Icons.remove_circle, color: AppColors.error),
                            onPressed: () => _removeOption(index),
                            tooltip: "حذف الخيار",
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text("إلغاء", style: TextStyle(color: AppColors.textSecondary))),
        ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentYellow),
            child: Text("حفظ السؤال", style: TextStyle(color: AppColors.backgroundPrimary, fontWeight: FontWeight.bold))
        ),
      ],
    );
  }
}
