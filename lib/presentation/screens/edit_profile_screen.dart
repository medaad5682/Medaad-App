import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/app_state.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/api_client.dart';
import '../../core/services/teacher_service.dart';
import '../widgets/custom_text_field.dart';
import '../../core/constants/api_constants.dart';
import '../../l10n/generated/app_localizations.dart';
import 'package:Medaad/presentation/widgets/directional_icon.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  // الحقول الأساسية
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _usernameController;

  // حقول المدرس الإضافية
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _specialtyController = TextEditingController();
  final TextEditingController _whatsappController = TextEditingController();

  // قوائم التحكم لبيانات الدفع
  List<TextEditingController> _cashNumberControllers = [];
  List<TextEditingController> _instapayNumberControllers = [];
  List<TextEditingController> _instapayLinkControllers = [];

  File? _selectedImage;
  String? _currentImageUrl;

  bool _isLoading = false;
  bool _isTeacher = false;

  final TeacherService _teacherService = TeacherService();
  final String _baseUrl = ApiConstants.baseUrl;

  @override
  void initState() {
    super.initState();
    // 1. تهيئة المتحكمات بقيم فارغة مبدئياً لتجنب الأخطاء
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _usernameController = TextEditingController();

    // 2. بدء عملية التحقق من الدور وتحميل البيانات
    _checkRoleAndLoad();
  }

  // دالة لفحص الدور ثم استدعاء التحميل المناسب
  Future<void> _checkRoleAndLoad() async {
    var box = await StorageService.openBox('auth_box');
    if (mounted) {
      setState(() {
        _isTeacher = box.get('role') == 'teacher';
      });
      _loadUserData();
    }
  }

  // ✅ الدالة الأساسية لجلب البيانات (من السيرفر للمدرس، أو محلياً للطالب)
  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);

    try {
      if (_isTeacher) {
        // أ) محاولة جلب البيانات الأحدث من السيرفر
        final data = await _teacherService.getTeacherProfile();

        // ب) تحديث الحقول النصية
        _nameController.text = data['name'] ?? "";
        _phoneController.text = data['phone'] ?? "";
        _usernameController.text = data['username'] ?? "";

        _bioController.text = data['bio'] ?? "";
        _specialtyController.text = data['specialty'] ?? "";
        _whatsappController.text = data['whatsapp_number'] ?? "";

        if (data['profile_image'] != null) {
          _currentImageUrl = data['profile_image'];
        }

        // ج) تعبئة قوائم الدفع الديناميكية
        final paymentDetails = data['payment_details'] ?? {};
        _populateListControllers(
            _cashNumberControllers, paymentDetails['cash_numbers']);
        _populateListControllers(
            _instapayNumberControllers, paymentDetails['instapay_numbers']);
        _populateListControllers(
            _instapayLinkControllers, paymentDetails['instapay_links']);
      } else {
        // للطالب: الاعتماد على البيانات المحلية + AppState
        await _loadFromCacheFallback();
      }
    } catch (e) {
      debugPrint("Error loading profile from API: $e");
      // في حال الفشل (أوفلاين)، نلجأ للكاش
      await _loadFromCacheFallback();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(AppLocalizations.of(context)!.couldNotFetchLatestData),
            backgroundColor: Colors.orange));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ✅ دالة مساعدة لتحويل مصفوفة البيانات إلى TextControllers
  void _populateListControllers(
      List<TextEditingController> controllersList, dynamic dataList) {
    // تنظيف القديم
    for (var c in controllersList) c.dispose();
    controllersList.clear();

    if (dataList != null && dataList is List) {
      for (var item in dataList) {
        if (item.toString().trim().isNotEmpty) {
          controllersList.add(TextEditingController(text: item.toString()));
        }
      }
    }

    // إضافة حقل فارغ افتراضي إذا كانت القائمة فارغة
    if (controllersList.isEmpty) {
      controllersList.add(TextEditingController());
    }
  }

  // ✅ دالة التحميل من الكاش (الاحتياطية + AppState) المعدلة
  Future<void> _loadFromCacheFallback() async {
    var box = await StorageService.openBox('auth_box');

    // ✅ التعديل: محاولة جلب البيانات من AppState أولاً (حيث توجد بيانات init-data)
    final userData = AppState().userData;

    // الأولية لـ AppState، ثم Hive، ثم قيمة فارغة
    _nameController.text = userData?['first_name'] ??
        userData?['name'] ??
        box.get('first_name') ??
        "";

    // ✅ هنا الإصلاح الأساسي لرقم الهاتف
    _phoneController.text = userData?['phone'] ?? box.get('phone') ?? "";

    _usernameController.text =
        userData?['username'] ?? box.get('username') ?? "";

    if (_isTeacher) {
      // للمدرسين أيضاً نستخدم نفس المنطق للبيانات الإضافية
      _bioController.text = userData?['bio'] ?? box.get('bio') ?? "";
      _specialtyController.text =
          userData?['specialty'] ?? box.get('specialty') ?? "";
      _whatsappController.text =
          userData?['whatsapp_number'] ?? box.get('whatsapp_number') ?? "";

      _currentImageUrl = userData?['profile_image'] ?? box.get('profile_image');

      _populateListControllers(
          _cashNumberControllers, box.get('cash_numbers', defaultValue: []));
      _populateListControllers(_instapayNumberControllers,
          box.get('instapay_numbers', defaultValue: []));
      _populateListControllers(_instapayLinkControllers,
          box.get('instapay_links', defaultValue: []));
    }
  }

  void _addController(List<TextEditingController> list) {
    setState(() => list.add(TextEditingController()));
  }

  void _removeController(List<TextEditingController> list, int index) {
    setState(() {
      list[index].dispose();
      list.removeAt(index);
    });
  }

  Future<void> _pickImage() async {
    if (!_isTeacher) return;
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) setState(() => _selectedImage = File(image.path));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _specialtyController.dispose();
    _whatsappController.dispose();
    for (var c in _cashNumberControllers) c.dispose();
    for (var c in _instapayNumberControllers) c.dispose();
    for (var c in _instapayLinkControllers) c.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      var box = await StorageService.openBox('auth_box');

      List<String> cashList = _cashNumberControllers
          .map((c) => c.text.trim())
          .where((text) => text.isNotEmpty)
          .toList();
      List<String> instaNumList = _instapayNumberControllers
          .map((c) => c.text.trim())
          .where((text) => text.isNotEmpty)
          .toList();
      List<String> instaLinkList = _instapayLinkControllers
          .map((c) => c.text.trim())
          .where((text) => text.isNotEmpty)
          .toList();

      Map<String, dynamic> dataToSend = {
        'firstName': _nameController.text,
        'phone': _phoneController.text,
        'username': _usernameController.text,
      };

      if (_isTeacher) {
        dataToSend['bio'] = _bioController.text;
        dataToSend['specialty'] = _specialtyController.text;
        dataToSend['whatsappNumber'] = _whatsappController.text;
        dataToSend['cashNumbersList'] = cashList;
        dataToSend['instapayNumbersList'] = instaNumList;
        dataToSend['instapayLinksList'] = instaLinkList;

        if (_selectedImage != null) {
          String newImageUrl =
              await _teacherService.uploadProfileImage(_selectedImage!);
          dataToSend['profileImage'] = newImageUrl;
          _currentImageUrl = newImageUrl;
        }
      }

      String endpoint = _isTeacher
          ? '$_baseUrl/api/teacher/update-profile'
          : '$_baseUrl/api/student/update-profile';

      // الاعتماد على ApiClient دون الحاجة لإرسال الهيدرز يدوياً
      final res = await ApiClient.instance.post(
        endpoint,
        data: dataToSend,
      );

      if (res.statusCode == 200 && res.data['success'] == true) {
        if (AppState().userData != null) {
          AppState().userData!['first_name'] = _nameController.text;
          AppState().userData!['username'] = _usernameController.text;
          AppState().userData!['phone'] = _phoneController.text;
          if (_isTeacher && dataToSend.containsKey('profileImage')) {
            AppState().userData!['profile_image'] = dataToSend['profileImage'];
          }
        }

        // تحديث الكاش المحلي
        await box.put('first_name', _nameController.text);
        await box.put('username', _usernameController.text);
        await box.put('phone', _phoneController.text);

        if (_isTeacher) {
          await box.put('bio', _bioController.text);
          await box.put('specialty', _specialtyController.text);
          await box.put('whatsapp_number', _whatsappController.text);
          // حفظ القوائم في Hive أيضاً لكي تظهر في ProfileScreen إذا كان يقرأ من Hive
          await box.put('cash_numbers', cashList);
          await box.put('instapay_numbers', instaNumList);
          await box.put('instapay_links', instaLinkList);

          if (dataToSend.containsKey('profileImage'))
            await box.put('profile_image', dataToSend['profileImage']);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context)!.profileUpdatedSuccess),
              backgroundColor: AppColors.success));
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = AppLocalizations.of(context)!.failedToUpdateProfile;
        if (e is DioException) {
          errorMsg = e.response?.data['message'] ??
              e.response?.data['error'] ??
              errorMsg;
        }
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(errorMsg), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // --- Header ---
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
                        border:
                            Border.all(color: Colors.white.withOpacity(0.05)),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 4)
                        ],
                      ),
                      child: DirectionalFlip(child: Icon(LucideIcons.arrowLeft,
                          color: AppColors.accentYellow, size: 20)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    AppLocalizations.of(context)!.editProfileTitle,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5),
                  ),
                ],
              ),
            ),

            // --- Form Fields ---
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isTeacher) ...[
                        Center(
                          child: GestureDetector(
                            onTap: _pickImage,
                            child: Stack(
                              children: [
                                Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    color: AppColors.backgroundSecondary,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: AppColors.accentYellow,
                                        width: 2),
                                    image: _selectedImage != null
                                        ? DecorationImage(
                                            image: FileImage(_selectedImage!),
                                            fit: BoxFit.cover)
                                        : (_currentImageUrl != null &&
                                                _currentImageUrl!.isNotEmpty
                                            ? DecorationImage(
                                                image: NetworkImage(
                                                    _currentImageUrl!),
                                                fit: BoxFit.cover)
                                            : null),
                                  ),
                                  child: (_selectedImage == null &&
                                          (_currentImageUrl == null ||
                                              _currentImageUrl!.isEmpty))
                                      ? const Icon(Icons.person,
                                          size: 50, color: Colors.grey)
                                      : null,
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                        color: AppColors.accentYellow,
                                        shape: BoxShape.circle),
                                    child: const Icon(Icons.camera_alt,
                                        size: 16, color: Colors.black),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Center(
                            child: Text(AppLocalizations.of(context)!.tapToChangePhoto,
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 10))),
                        const SizedBox(height: 20),
                      ],
                      CustomTextField(
                        label: AppLocalizations.of(context)!.fullNameLabel,
                        controller: _nameController,
                        hintText: AppLocalizations.of(context)!.editFullNameHint,
                        prefixIcon: LucideIcons.user,
                        validator: (value) => value == null || value.isEmpty
                            ? AppLocalizations.of(context)!.nameRequiredValidation
                            : null,
                      ),
                      const SizedBox(height: 20),
                      CustomTextField(
                        label: AppLocalizations.of(context)!.phoneNumberLabel,
                        controller: _phoneController,
                        hintText: AppLocalizations.of(context)!.phoneNumberHint,
                        prefixIcon: LucideIcons.phone,
                        keyboardType: TextInputType.phone,
                        readOnly: true, // ✅ تمت الإضافة هنا لمنع التعديل
                        validator: (value) {
                          if (value == null || value.isEmpty) return null;
                          return value.length < 11
                              ? AppLocalizations.of(context)!.invalidPhoneNumberValidation
                              : null;
                        },
                      ),
                      const SizedBox(height: 20),
                      CustomTextField(
                        label: AppLocalizations.of(context)!.usernameLabel,
                        controller: _usernameController,
                        hintText: AppLocalizations.of(context)!.usernameEnglishNumbersOnlyHint,
                        prefixIcon: LucideIcons.atSign,
                        readOnly: true, // ✅ تمت الإضافة هنا لمنع التعديل
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[a-zA-Z0-9]')),
                        ],
                        validator: (value) {
                          if (value == null || value.isEmpty)
                            return AppLocalizations.of(context)!.usernameRequiredValidation;
                          if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(value)) {
                            return AppLocalizations.of(context)!.usernameInvalidCharsValidation;
                          }
                          return null;
                        },
                      ),
                      if (_isTeacher) ...[
                        const SizedBox(height: 20),
                        const Divider(color: Colors.white10),
                        const SizedBox(height: 10),
                        Text(AppLocalizations.of(context)!.teacherInfoLabel,
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5)),
                        const SizedBox(height: 15),
                        CustomTextField(
                          label: AppLocalizations.of(context)!.specialtyJobTitleLabel,
                          controller: _specialtyController,
                          hintText: AppLocalizations.of(context)!.specialtyHint,
                          prefixIcon: LucideIcons.briefcase,
                        ),
                        const SizedBox(height: 20),
                        CustomTextField(
                          label: AppLocalizations.of(context)!.whatsappNumberLabel,
                          controller: _whatsappController,
                          hintText: AppLocalizations.of(context)!.whatsappNumberHint,
                          prefixIcon: LucideIcons.messageCircle,
                          keyboardType: TextInputType.phone,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                              top: 6, left: 8, bottom: 20),
                          // ✅ تم التعديل هنا: استخدام AppColors.textSecondary بدلاً من Colors.white38
                          child: Text(
                              AppLocalizations.of(context)!.whatsappNumberNotice,
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11)),
                        ),
                        CustomTextField(
                          label: AppLocalizations.of(context)!.bioAboutMeLabel,
                          controller: _bioController,
                          hintText: AppLocalizations.of(context)!.bioHint,
                          prefixIcon: LucideIcons.fileText,
                          keyboardType: TextInputType.multiline,
                          maxLines: 3,
                        ),
                        const SizedBox(height: 30),
                        const Divider(color: Colors.white10),
                        const SizedBox(height: 10),
                        Text(AppLocalizations.of(context)!.paymentMethodsLabel,
                            style: TextStyle(
                                color: AppColors.accentYellow,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5)),
                        const SizedBox(height: 20),
                        _buildDynamicList(
                          title: AppLocalizations.of(context)!.cashWalletNumbersTitle,
                          controllers: _cashNumberControllers,
                          hint: AppLocalizations.of(context)!.enterWalletNumberHint,
                          onAdd: () => _addController(_cashNumberControllers),
                          onRemove: (idx) =>
                              _removeController(_cashNumberControllers, idx),
                          icon: Icons.account_balance_wallet,
                          isNumeric: true,
                        ),
                        const SizedBox(height: 24),
                        _buildDynamicList(
                          title: AppLocalizations.of(context)!.instapayNumbersTitle,
                          controllers: _instapayNumberControllers,
                          hint: AppLocalizations.of(context)!.enterInstapayPhoneHint,
                          onAdd: () =>
                              _addController(_instapayNumberControllers),
                          onRemove: (idx) => _removeController(
                              _instapayNumberControllers, idx),
                          icon: Icons.phone_iphone,
                          isNumeric: true,
                        ),
                        const SizedBox(height: 24),
                        _buildDynamicList(
                          title: AppLocalizations.of(context)!.instapayLinksUsernamesTitle,
                          controllers: _instapayLinkControllers,
                          hint: AppLocalizations.of(context)!.instapayLinkHint,
                          onAdd: () => _addController(_instapayLinkControllers),
                          onRemove: (idx) =>
                              _removeController(_instapayLinkControllers, idx),
                          icon: LucideIcons.link,
                          isNumeric: false,
                        ),
                        const SizedBox(height: 40),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveChanges,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentYellow,
                    foregroundColor: AppColors.backgroundPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    elevation: 10,
                    shadowColor: AppColors.accentYellow.withOpacity(0.2),
                  ),
                  child: _isLoading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: AppColors.backgroundPrimary))
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(LucideIcons.save, size: 18),
                            const SizedBox(width: 12),
                            Text(AppLocalizations.of(context)!.saveChangesButton,
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    letterSpacing: 1.0)),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicList({
    required String title,
    required List<TextEditingController> controllers,
    required String hint,
    required VoidCallback onAdd,
    required Function(int) onRemove,
    required IconData icon,
    bool isNumeric = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
            InkWell(
              onTap: onAdd,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: AppColors.accentOrange.withOpacity(0.2),
                    shape: BoxShape.circle),
                child: const Icon(Icons.add,
                    color: AppColors.accentOrange, size: 18),
              ),
            )
          ],
        ),
        const SizedBox(height: 10),
        ...List.generate(controllers.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: CustomTextField(
                    label: "",
                    controller: controllers[index],
                    hintText: hint,
                    prefixIcon: icon,
                    keyboardType:
                        isNumeric ? TextInputType.number : TextInputType.text,
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: () => onRemove(index),
                  child: const Icon(Icons.remove_circle_outline,
                      color: AppColors.error, size: 24),
                ),
              ],
            ),
          );
        }),
        if (controllers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(AppLocalizations.of(context)!.clickPlusToAddHint,
                style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 12,
                    fontStyle: FontStyle.italic)),
          ),
      ],
    );
  }
}
