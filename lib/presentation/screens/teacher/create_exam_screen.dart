import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/constants/app_colors.dart'; 
import '../../../core/services/teacher_service.dart';
import '../../widgets/custom_text_field.dart';
import 'package:Medaad/l10n/generated/app_localizations.dart';

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
            final String qType = q['question_type'] == 'essay' ? 'essay' : 'mcq';

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
              questionType: qType,
              maxScore: (q['max_score'] is num) ? (q['max_score'] as num).toDouble() : 1,
              modelAnswer: q['model_answer']?.toString(),
            );
          }).toList();
        }
      });

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.failedLoadExamDetails(e.toString())), backgroundColor: AppColors.error));
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
            SnackBar(content: Text(AppLocalizations.of(context)!.startDateAfterEndError), backgroundColor: AppColors.error)
          );
        }
        return;
      }
      setState(() => _startDate = dateTime);
    } else {
      if (_startDate != null && dateTime.isBefore(_startDate!)) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.endDateBeforeStartError), backgroundColor: AppColors.error)
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
        title: Text(AppLocalizations.of(context)!.deleteExamTitle, style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
        content: Text(
          AppLocalizations.of(context)!.deleteExamConfirmMessage,
          style: TextStyle(color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context)!.cancel, style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(AppLocalizations.of(context)!.permanentDeleteAction, style: const TextStyle(color: Colors.white)),
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
          SnackBar(content: Text(AppLocalizations.of(context)!.examDeletedSuccessfully), backgroundColor: AppColors.success),
        );
        Navigator.pop(context, true); 
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.deleteFailedMessage(e.toString())), backgroundColor: AppColors.error),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.atLeastOneQuestionRequired), backgroundColor: AppColors.error));
      return;
    }
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.selectExamStartEndTime), backgroundColor: AppColors.error));
      return;
    }
    
    if (_startDate!.isAfter(_endDate!)) {
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.startTimeAfterEndError), backgroundColor: AppColors.error));
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

        if (q.isEssay) {
          processedQuestions.add({
            'text': q.text,
            'questionType': 'essay',
            'maxScore': q.maxScore,
            'modelAnswer': q.modelAnswer,
            'image': imageUrl,
          });
        } else {
          processedQuestions.add({
            'text': q.text,
            'questionType': 'mcq',
            'options': q.options,
            'correctIndex': q.correctOptionIndex,
            'image': imageUrl, 
          });
        }
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
            content: Text(widget.examId != null ? AppLocalizations.of(context)!.examUpdatedSuccessfully : AppLocalizations.of(context)!.examCreatedSuccessfully), 
            backgroundColor: AppColors.success
          )
        );
        Navigator.pop(context, true);
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.genericErrorOccurred(e.toString())), backgroundColor: AppColors.error));
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
        title: Text(widget.examId != null ? AppLocalizations.of(context)!.editExamTitle : AppLocalizations.of(context)!.createNewExamTitle, style: TextStyle(color: AppColors.textPrimary)),
        backgroundColor: AppColors.backgroundSecondary,
        iconTheme: IconThemeData(color: AppColors.accentYellow),
        actions: [
          if (widget.examId != null)
            IconButton(
              icon: Icon(Icons.delete_forever, color: AppColors.error),
              onPressed: _isSubmitting ? null : _deleteExam,
              tooltip: AppLocalizations.of(context)!.deleteExamTitle,
            )
        ],
      ),
      body: _isSubmitting
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: AppColors.accentYellow),
                const SizedBox(height: 20),
                Text(AppLocalizations.of(context)!.processingMessage, style: TextStyle(color: AppColors.textPrimary))
              ],
            ))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  CustomTextField(
                    label: AppLocalizations.of(context)!.examTitleLabel,
                    controller: _titleController,
                    hintText: AppLocalizations.of(context)!.examTitleHint,
                    prefixIcon: Icons.quiz,
                    validator: (val) => val!.isEmpty ? AppLocalizations.of(context)!.requiredField : null,
                  ),
                  const SizedBox(height: 15),
                  
                  CustomTextField(
                    label: AppLocalizations.of(context)!.durationMinutesLabel,
                    controller: _durationController,
                    hintText: AppLocalizations.of(context)!.durationHint,
                    prefixIcon: Icons.timer,
                    keyboardType: TextInputType.number,
                    validator: (val) => val!.isEmpty ? AppLocalizations.of(context)!.requiredField : null,
                  ),
                  const SizedBox(height: 15),

                  Card(
                    color: AppColors.backgroundSecondary,
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: Text(AppLocalizations.of(context)!.randomizeQuestionsTitle, style: TextStyle(color: AppColors.textPrimary)),
                          subtitle: Text(AppLocalizations.of(context)!.randomizeQuestionsSubtitle, style: TextStyle(color: AppColors.textSecondary)),
                          value: _randomizeQuestions,
                          activeColor: AppColors.accentYellow,
                          onChanged: (val) => setState(() => _randomizeQuestions = val),
                        ),
                        Divider(height: 1, color: AppColors.textSecondary.withOpacity(0.1)),
                        SwitchListTile(
                          title: Text(AppLocalizations.of(context)!.randomizeOptionsTitle, style: TextStyle(color: AppColors.textPrimary)),
                          subtitle: Text(AppLocalizations.of(context)!.randomizeOptionsSubtitle, style: TextStyle(color: AppColors.textSecondary)),
                          value: _randomizeOptions,
                          activeColor: AppColors.accentYellow,
                          onChanged: (val) => setState(() => _randomizeOptions = val),
                        ),
                        
                        // ✅ إضافة خيار السماح بإعادة الامتحان (التدريب)
                        Divider(height: 1, color: AppColors.textSecondary.withOpacity(0.1)),
                        SwitchListTile(
                          title: Text(AppLocalizations.of(context)!.allowRetakeTitle, style: TextStyle(color: AppColors.textPrimary)),
                          subtitle: Text(AppLocalizations.of(context)!.allowRetakeSubtitle, style: TextStyle(color: AppColors.textSecondary)),
                          value: _allowRetake,
                          activeColor: AppColors.accentYellow,
                          onChanged: (val) => setState(() => _allowRetake = val),
                        ),

                        // ✅ خيار إرسال الإشعار يظهر فقط في حالة إنشاء امتحان جديد
                        if (widget.examId == null) ...[
                          Divider(height: 1, color: AppColors.textSecondary.withOpacity(0.1)),
                          SwitchListTile(
                            title: Text(AppLocalizations.of(context)!.notifyStudentsTitle, style: TextStyle(color: AppColors.accentYellow)),
                            subtitle: Text(AppLocalizations.of(context)!.notifyStudentsSubtitle, style: TextStyle(color: AppColors.textSecondary)),
                            value: _notifyStudents,
                            activeColor: AppColors.accentYellow,
                            onChanged: (val) => setState(() => _notifyStudents = val),
                          ),
                        ],

                        Divider(thickness: 2, color: AppColors.textSecondary.withOpacity(0.1)),
                        ListTile(
                          leading: const Icon(Icons.calendar_today, color: Colors.blue),
                          title: Text(_startDate == null ? AppLocalizations.of(context)!.activationDateTimeLabel : AppLocalizations.of(context)!.startsAtLabel(_formatDate(_startDate!)), style: TextStyle(color: AppColors.textPrimary)),
                          subtitle: Text(AppLocalizations.of(context)!.tapToSetStart, style: TextStyle(color: AppColors.textSecondary)),
                          onTap: () => _pickDateTime(true),
                        ),
                        ListTile(
                          leading: Icon(Icons.event_busy, color: AppColors.error),
                          title: Text(_endDate == null ? AppLocalizations.of(context)!.closingDateTimeLabel : AppLocalizations.of(context)!.endsAtLabel(_formatDate(_endDate!)), style: TextStyle(color: AppColors.textPrimary)),
                          subtitle: Text(AppLocalizations.of(context)!.tapToSetEnd, style: TextStyle(color: AppColors.textSecondary)),
                          onTap: () => _pickDateTime(false),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(AppLocalizations.of(context)!.questionsCountLabel(_questions.length.toString()), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      ElevatedButton.icon(
                        onPressed: () => _openQuestionDialog(),
                        icon: const Icon(Icons.add),
                        label: Text(AppLocalizations.of(context)!.addQuestionAction),
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
                      child: Center(child: Text(AppLocalizations.of(context)!.noQuestionsAddedYet, style: TextStyle(color: AppColors.textSecondary))),
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
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(q.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textPrimary)),
                                ),
                                if (q.isEssay)
                                  Container(
                                    margin: const EdgeInsetsDirectional.only(end: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.accentBlue.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: AppColors.accentBlue.withOpacity(0.4)),
                                    ),
                                    child: Text(AppLocalizations.of(context)!.essayBadge, style: TextStyle(color: AppColors.accentBlue, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              q.isEssay
                                  ? AppLocalizations.of(context)!.essayQuestionSubtitle(
                                      q.maxScore.toStringAsFixed(q.maxScore.truncateToDouble() == q.maxScore ? 0 : 1),
                                      q.imageFile != null ? AppLocalizations.of(context)!.newImageStatus : (q.imageUrl != null ? AppLocalizations.of(context)!.savedImageStatus : AppLocalizations.of(context)!.textOnlyStatus))
                                  : AppLocalizations.of(context)!.mcqQuestionSubtitle(
                                      q.options.length.toString(),
                                      q.imageFile != null ? AppLocalizations.of(context)!.newImageStatus : (q.imageUrl != null ? AppLocalizations.of(context)!.savedImageStatus : AppLocalizations.of(context)!.textOnlyStatus)),
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
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
                      widget.examId != null ? AppLocalizations.of(context)!.saveChangesAction : AppLocalizations.of(context)!.saveAndPublishExamAction, 
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
  String questionType; // 'mcq' أو 'essay'
  double maxScore; // الدرجة العظمى (تُستخدم فقط للأسئلة المقالية)
  String? modelAnswer; // الإجابة النموذجية (تُستخدم فقط للأسئلة المقالية)

  QuestionModel({
    required this.text,
    required this.options,
    required this.correctOptionIndex,
    this.imageFile,
    this.imageUrl,
    this.questionType = 'mcq',
    this.maxScore = 1,
    this.modelAnswer,
  });

  bool get isEssay => questionType == 'essay';
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
  final TextEditingController _maxScoreController = TextEditingController(text: '1');
  final TextEditingController _modelAnswerController = TextEditingController();
   
  List<TextEditingController> _optionControllers = [];
   
  int _correctIndex = 0;
  File? _selectedImage;
  String? _existingImageUrl;
  String _questionType = 'mcq'; // 'mcq' أو 'essay'

  @override
  void initState() {
    super.initState();
    if (widget.initialQuestion != null) {
      _questionTextController.text = widget.initialQuestion!.text;
      _questionType = widget.initialQuestion!.questionType;
      _maxScoreController.text = _formatScore(widget.initialQuestion!.maxScore);
      _modelAnswerController.text = widget.initialQuestion!.modelAnswer ?? '';
      
      for (var option in widget.initialQuestion!.options) {
        _optionControllers.add(TextEditingController(text: option));
      }
      
      _correctIndex = widget.initialQuestion!.correctOptionIndex;
      _selectedImage = widget.initialQuestion!.imageFile;
      _existingImageUrl = widget.initialQuestion!.imageUrl;
    }

    if (_optionControllers.isEmpty) {
      _optionControllers = List.generate(4, (_) => TextEditingController());
    }
  }

  String _formatScore(double value) {
    return value.truncateToDouble() == value ? value.toInt().toString() : value.toString();
  }

  @override
  void dispose() {
    _questionTextController.dispose();
    _maxScoreController.dispose();
    _modelAnswerController.dispose();
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
        SnackBar(content: Text(AppLocalizations.of(context)!.minTwoOptionsRequired), backgroundColor: AppColors.error)
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

    if (_questionType == 'essay') {
      final maxScore = double.tryParse(_maxScoreController.text.trim());
      if (maxScore == null || maxScore <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.maxScoreRequiredForEssay), backgroundColor: AppColors.error)
        );
        return;
      }

      final newQuestion = QuestionModel(
        text: _questionTextController.text,
        options: const [],
        correctOptionIndex: 0,
        imageFile: _selectedImage,
        imageUrl: _existingImageUrl,
        questionType: 'essay',
        maxScore: maxScore,
        modelAnswer: _modelAnswerController.text.trim().isEmpty ? null : _modelAnswerController.text.trim(),
      );

      widget.onSave(newQuestion);
      Navigator.pop(context);
      return;
    }

    List<String> options = _optionControllers.map((c) => c.text.trim()).toList();
    
    if (options.any((o) => o.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.fillAllOptionsOrDelete), backgroundColor: AppColors.error)
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
      questionType: 'mcq',
      maxScore: 1,
    );

    widget.onSave(newQuestion);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.backgroundSecondary,
      title: Text(
          widget.initialQuestion == null ? AppLocalizations.of(context)!.newQuestionTitle : AppLocalizations.of(context)!.editQuestionTitle,
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
                    labelText: AppLocalizations.of(context)!.questionTextLabel,
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accentYellow)),
                  ),
                  maxLines: 2,
                  validator: (val) => val!.isEmpty ? AppLocalizations.of(context)!.requiredField : null,
                ),
                const SizedBox(height: 10),

                DropdownButtonFormField<String>(
                  value: _questionType,
                  dropdownColor: AppColors.backgroundSecondary,
                  style: TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.questionTypeLabel,
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accentYellow)),
                  ),
                  items: [
                    DropdownMenuItem(value: 'mcq', child: Text(AppLocalizations.of(context)!.mcqTypeOption)),
                    DropdownMenuItem(value: 'essay', child: Text(AppLocalizations.of(context)!.essayTypeOption)),
                  ],
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() => _questionType = val);
                  },
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedImage != null 
                            ? AppLocalizations.of(context)!.newImageSelectedStatus 
                            : (_existingImageUrl != null ? AppLocalizations.of(context)!.imageSavedPreviouslyStatus : AppLocalizations.of(context)!.noImageStatus),
                        style: TextStyle(
                          color: _selectedImage != null ? AppColors.success : AppColors.textSecondary,
                          fontWeight: _selectedImage != null ? FontWeight.bold : FontWeight.normal
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _pickImage,
                      icon: Icon(Icons.image, color: AppColors.accentYellow),
                      tooltip: AppLocalizations.of(context)!.uploadChangeImageTooltip,
                    ),
                    if (_selectedImage != null || _existingImageUrl != null)
                      IconButton(
                        icon: Icon(Icons.close, color: AppColors.error),
                        tooltip: AppLocalizations.of(context)!.deleteImageTooltip,
                        onPressed: () => setState(() {
                          _selectedImage = null;
                          _existingImageUrl = null;
                        }),
                      )
                  ],
                ),
                Divider(color: AppColors.textSecondary.withOpacity(0.1)),

                if (_questionType == 'essay') ...[
                  Text(AppLocalizations.of(context)!.maxScoreForQuestionLabel, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _maxScoreController,
                    style: TextStyle(color: AppColors.textPrimary),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.scoreLabel,
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accentYellow)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    AppLocalizations.of(context)!.essayInfoMessage,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Text(AppLocalizations.of(context)!.modelAnswerOptionalLabel, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _modelAnswerController,
                    style: TextStyle(color: AppColors.textPrimary),
                    maxLines: 4,
                    minLines: 3,
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context)!.modelAnswerHint,
                      hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accentYellow)),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppLocalizations.of(context)!.modelAnswerInfoMessage,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(AppLocalizations.of(context)!.optionsSelectCorrectLabel, style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      TextButton.icon(
                        onPressed: _addOption,
                        icon: Icon(Icons.add_circle, size: 18, color: AppColors.accentYellow),
                        label: Text(AppLocalizations.of(context)!.addOptionAction, style: TextStyle(color: AppColors.accentYellow)),
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
                                labelText: AppLocalizations.of(context)!.optionNumberLabel((index + 1).toString()),
                                labelStyle: TextStyle(color: AppColors.textSecondary),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.accentYellow)),
                              ),
                              validator: (val) => val!.isEmpty ? AppLocalizations.of(context)!.requiredField : null,
                            ),
                          ),
                          if (_optionControllers.length > 2)
                            IconButton(
                              icon: Icon(Icons.remove_circle, color: AppColors.error),
                              onPressed: () => _removeOption(index),
                              tooltip: AppLocalizations.of(context)!.deleteOptionTooltip,
                            ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.cancel, style: TextStyle(color: AppColors.textSecondary))),
        ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accentYellow),
            child: Text(AppLocalizations.of(context)!.saveQuestionAction, style: TextStyle(color: AppColors.backgroundPrimary, fontWeight: FontWeight.bold))
        ),
      ],
    );
  }
}
