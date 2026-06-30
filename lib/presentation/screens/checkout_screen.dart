import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import 'main_wrapper.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../l10n/generated/app_localizations.dart';
import 'package:Medaad/presentation/widgets/directional_icon.dart';

class CheckoutScreen extends StatefulWidget {
  final double amount;
  final Map<String, dynamic> paymentInfo;
  final List<Map<String, dynamic>> selectedItems;
  final int? teacherId;

  const CheckoutScreen({
    super.key,
    required this.amount,
    required this.paymentInfo,
    required this.selectedItems,
    this.teacherId,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _discountController =
      TextEditingController(); // 🆕 متحكم الخصم
  File? _receiptImage;
  bool _isUploading = false;

  bool _isLoadingPaymentData = false;
  late Map<String, dynamic> _currentPaymentInfo;

  // 🆕 متغيرات الخصم (Coupons)
  double? _discountedAmount;
  String? _appliedCode;
  bool _isCheckingDiscount = false;

  final String _baseUrl = ApiConstants.baseUrl;

  @override
  void initState() {
    super.initState();
    _currentPaymentInfo = widget.paymentInfo;
    _checkAndFetchPaymentInfo();
  }

  Future<void> _checkAndFetchPaymentInfo() async {
    final cash = _currentPaymentInfo['cash_numbers'] as List?;
    final instaNum = _currentPaymentInfo['instapay_numbers'] as List?;
    final instaLink = _currentPaymentInfo['instapay_links'] as List?;

    bool hasData = (cash != null && cash.isNotEmpty) ||
        (instaNum != null && instaNum.isNotEmpty) ||
        (instaLink != null && instaLink.isNotEmpty);

    if (hasData) return;

    if (widget.teacherId != null) {
      setState(() => _isLoadingPaymentData = true);
      try {
        debugPrint(
            "🛒 Checkout: Fetching payment info using Teacher ID: ${widget.teacherId}");

        final response = await ApiClient.instance.get(
          '$_baseUrl/api/public/get-payment-info',
          queryParameters: {'teacherId': widget.teacherId},
        );

        if (response.statusCode == 200 && response.data != null) {
          if (mounted) {
            setState(() {
              _currentPaymentInfo = response.data;
            });
          }
        }
      } catch (e) {
        debugPrint("Error fetching payment info by teacherId: $e");
      } finally {
        if (mounted) setState(() => _isLoadingPaymentData = false);
      }
      return;
    }

    if (widget.selectedItems.isNotEmpty) {
      setState(() => _isLoadingPaymentData = true);
      try {
        final firstItem = widget.selectedItems.first;
        Map<String, dynamic> queryParams = {};

        if (firstItem.containsKey('course_id') &&
            firstItem['course_id'] != null) {
          queryParams['subjectId'] = firstItem['id'];
        } else {
          queryParams['courseId'] = firstItem['id'];
        }

        final response = await ApiClient.instance.get(
          '$_baseUrl/api/public/get-payment-info',
          queryParameters: queryParams,
        );

        if (response.statusCode == 200 && response.data != null) {
          if (mounted) {
            setState(() {
              _currentPaymentInfo = response.data;
            });
          }
        }
      } catch (e) {
        debugPrint("Error fetching payment info by item: $e");
      } finally {
        if (mounted) setState(() => _isLoadingPaymentData = false);
      }
    }
  }

  // =================================================================
  // 🟢 دوال التحقق من كود الخصم (Coupons Logic)
  // =================================================================
  Future<void> _applyDiscountCode() async {
    if (_discountController.text.trim().isEmpty) return;

    setState(() => _isCheckingDiscount = true);
    FocusScope.of(context).unfocus(); // إخفاء لوحة المفاتيح

    try {
      // محاولة الحصول على رقم المدرس بأكثر من طريقة لضمان إرساله مع الكود
      int? tId = widget.teacherId;
      if (tId == null && _currentPaymentInfo['teacher_id'] != null) {
        tId = int.tryParse(_currentPaymentInfo['teacher_id'].toString());
      }

      final response = await ApiClient.instance.post(
        '$_baseUrl/api/student/validate-discount',
        data: {
          'code': _discountController.text.trim(),
          'teacher_id': tId,
          'selectedItems': widget.selectedItems, // ✅ إضافة السلة ليفحصها الباك إند
        },
      );
      
      if (response.statusCode == 200 && response.data['success']) {
        final discountData = response.data['discount'];

        double newTotal = widget.amount;

        // حساب السعر الجديد بناءً على نوع الخصم المرجّع من السيرفر
        if (discountData['discount_type'] == 'percentage') {
          double percent =
              double.parse(discountData['discount_value'].toString());
          newTotal = widget.amount - (widget.amount * (percent / 100));
        } else if (discountData['discount_type'] == 'fixed') {
          // ✅ تم التعديل: طرح قيمة الخصم من السعر الأساسي بدلاً من مساواته بها
          double fixedDiscount =
              double.parse(discountData['discount_value'].toString());
          newTotal = widget.amount - fixedDiscount;
        }

        // منع السعر من أن يصبح سالباً
        if (newTotal < 0) newTotal = 0;

        setState(() {
          _discountedAmount = newTotal;
          _appliedCode = _discountController.text.trim().toUpperCase();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!.discountCodeAppliedSuccess),
              backgroundColor: AppColors.success),
        );
      }
    } on DioException catch (e) {
      String msg = AppLocalizations.of(context)!.discountCodeInvalid;
      if (e.response != null &&
          e.response?.data != null &&
          e.response?.data['message'] != null) {
        msg = e.response?.data['message'];
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!.connectionError),
            backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _isCheckingDiscount = false);
    }
  }

  // دالة لإزالة الكود المُطبّق
  void _removeDiscount() {
    setState(() {
      _discountedAmount = null;
      _appliedCode = null;
      _discountController.clear();
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _receiptImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!.couldNotLaunchLink),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(AppLocalizations.of(context)!.copiedToClipboard),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _submitOrder() async {
    if (_receiptImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!.pleaseUploadReceiptImage),
            backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      String fileName = _receiptImage!.path.split('/').last;

      // ✅ تجهيز البيانات لإرسالها
      Map<String, dynamic> formMap = {
        'receiptFile': await MultipartFile.fromFile(_receiptImage!.path,
            filename: fileName),
        'user_note': _noteController.text,
        'selectedItems': jsonEncode(widget.selectedItems),
      };

      // ✅ إضافة الكود للطلب إذا كان موجوداً
      if (_appliedCode != null) {
        formMap['discount_code'] = _appliedCode;
      }

      FormData formData = FormData.fromMap(formMap);

      final response = await ApiClient.instance.post(
        '$_baseUrl/api/student/request-course',
        data: formData,
        options: Options(
          validateStatus: (status) => status! < 500, // ✅ الحفاظ على validateStatus
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.backgroundSecondary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Column(
                children: [
                  Icon(LucideIcons.checkCircle,
                      color: AppColors.success, size: 48),
                  const SizedBox(height: 16),
                  Text(AppLocalizations.of(context)!.requestSentTitle,
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ],
              ),
              content: Text(
                AppLocalizations.of(context)!.requestReceivedMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const MainWrapper()),
                      (route) => false,
                    );
                  },
                  child: Text(AppLocalizations.of(context)!.ok,
                      style: TextStyle(
                          color: AppColors.accentYellow,
                          fontWeight: FontWeight.bold)),
                )
              ],
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text(response.data['error'] ?? AppLocalizations.of(context)!.failedToSendRequest),
                backgroundColor: AppColors.error),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!.connectionError),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List cashNumbers =
        (_currentPaymentInfo['cash_numbers'] as List?) ?? [];
    final List instapayNumbers =
        (_currentPaymentInfo['instapay_numbers'] as List?) ?? [];
    final List instapayLinks =
        (_currentPaymentInfo['instapay_links'] as List?) ?? [];

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
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DirectionalFlip(child: Icon(LucideIcons.arrowLeft,
                          color: AppColors.accentYellow, size: 20)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    AppLocalizations.of(context)!.checkoutTitle,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),

            Expanded(
              child: _isLoadingPaymentData
                  ? Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accentYellow))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ✅ مربع المبلغ مع إظهار السعر المشطوب إن وُجد
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: AppColors.backgroundSecondary,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.05)),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.2),
                                    blurRadius: 10)
                              ],
                            ),
                            child: Column(
                              children: [
                                Text(AppLocalizations.of(context)!.totalAmountLabel,
                                    style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 10,
                                        letterSpacing: 2.0,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),
                                if (_discountedAmount != null) ...[
                                  // عرض السعر القديم مشطوباً
                                  Text(AppLocalizations.of(context)!.priceEgp(widget.amount.toString()),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.error,
                                        decoration: TextDecoration.lineThrough,
                                      )),
                                  const SizedBox(height: 4),
                                  // عرض السعر الجديد
                                  Text(
                                      AppLocalizations.of(context)!.priceEgp(_discountedAmount!.toStringAsFixed(0)),
                                      style: TextStyle(
                                          fontSize: 42,
                                          fontWeight: FontWeight.w900,
                                          color: AppColors.success)),
                                ] else ...[
                                  Text(AppLocalizations.of(context)!.priceEgp(widget.amount.toString()),
                                      style: TextStyle(
                                          fontSize: 36,
                                          fontWeight: FontWeight.w900,
                                          color: AppColors.accentYellow)),
                                ]
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),

                          // 🆕 إدخال كود الخصم (Discount Code Input)
                          Text(AppLocalizations.of(context)!.discountCodeLabel,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textSecondary,
                                  letterSpacing: 1.5)),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 55,
                                  decoration: BoxDecoration(
                                    color: AppColors.backgroundSecondary,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: _appliedCode != null
                                            ? AppColors.success
                                            : Colors.white.withOpacity(0.05)),
                                  ),
                                  child: TextField(
                                    controller: _discountController,
                                    enabled: _appliedCode ==
                                        null, // إقفال الحقل إذا تم تطبيق كود بالفعل
                                    style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.bold),
                                    decoration: InputDecoration(
                                      hintText: AppLocalizations.of(context)!.enterCodeHint,
                                      hintStyle: TextStyle(
                                          color: AppColors.textSecondary
                                              .withOpacity(0.5)),
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 16),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              if (_appliedCode != null)
                                // زر حذف الكود بعد تطبيقه
                                InkWell(
                                  onTap: _removeDiscount,
                                  child: Container(
                                    height: 55,
                                    width: 55,
                                    decoration: BoxDecoration(
                                      color: AppColors.error.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border:
                                          Border.all(color: AppColors.error),
                                    ),
                                    child: Icon(LucideIcons.trash2,
                                        color: AppColors.error),
                                  ),
                                )
                              else
                                // زر التفعيل
                                InkWell(
                                  onTap: _isCheckingDiscount
                                      ? null
                                      : _applyDiscountCode,
                                  child: Container(
                                    height: 55,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.accentYellow,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: _isCheckingDiscount
                                        ? SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                color:
                                                    AppColors.backgroundPrimary,
                                                strokeWidth: 2))
                                        : Text(AppLocalizations.of(context)!.applyButton,
                                            style: TextStyle(
                                                color:
                                                    AppColors.backgroundPrimary,
                                                fontWeight: FontWeight.bold)),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 32),

                          // 1. Cash Numbers Section
                          if (cashNumbers.isNotEmpty) ...[
                            Text(AppLocalizations.of(context)!.cashWalletsLabel,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textSecondary,
                                    letterSpacing: 1.5)),
                            const SizedBox(height: 10),
                            ...cashNumbers.map((num) => _buildCopyableCard(
                                AppLocalizations.of(context)!.walletNumberLabel,
                                num.toString(),
                                Icons.account_balance_wallet)),
                            const SizedBox(height: 24),
                          ],

                          // 2. InstaPay Numbers Section
                          if (instapayNumbers.isNotEmpty) ...[
                            Text(AppLocalizations.of(context)!.instapayNumbersLabel,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textSecondary,
                                    letterSpacing: 1.5)),
                            const SizedBox(height: 10),
                            ...instapayNumbers.map((num) => _buildCopyableCard(
                                AppLocalizations.of(context)!.instapayPhoneLabel,
                                num.toString(),
                                Icons.phone_iphone)),
                            const SizedBox(height: 24),
                          ],

                          // 3. InstaPay Links Section
                          if (instapayLinks.isNotEmpty) ...[
                            Text(AppLocalizations.of(context)!.instapayLinksLabel,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textSecondary,
                                    letterSpacing: 1.5)),
                            const SizedBox(height: 10),
                            ...instapayLinks
                                .map((link) => _buildLinkCard(link.toString())),
                            const SizedBox(height: 24),
                          ],

                          // 4. رسالة في حال عدم وجود أي طرق دفع
                          if (cashNumbers.isEmpty &&
                              instapayNumbers.isEmpty &&
                              instapayLinks.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              margin: const EdgeInsets.only(bottom: 24),
                              decoration: BoxDecoration(
                                  color: AppColors.error.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: AppColors.error.withOpacity(0.3))),
                              child: Column(
                                children: [
                                  Icon(LucideIcons.alertCircle,
                                      color: AppColors.error, size: 30),
                                  const SizedBox(height: 10),
                                  Text(AppLocalizations.of(context)!.paymentMethodsUnavailable,
                                      style: TextStyle(
                                          color: AppColors.error,
                                          fontWeight: FontWeight.bold)),
                                  Text(
                                      AppLocalizations.of(context)!.contactSupportOrRetryLater,
                                      style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12)),
                                ],
                              ),
                            ),

                          // Receipt Upload
                          Text(AppLocalizations.of(context)!.uploadReceiptLabel,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textSecondary,
                                  letterSpacing: 1.5)),
                          const SizedBox(height: 16),
                          GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              height: 180,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: AppColors.backgroundSecondary,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _receiptImage != null
                                      ? AppColors.accentYellow
                                      : Colors.white.withOpacity(0.1),
                                  style: BorderStyle.solid,
                                  width: 2,
                                ),
                                image: _receiptImage != null
                                    ? DecorationImage(
                                        image: FileImage(_receiptImage!),
                                        fit: BoxFit.cover)
                                    : null,
                              ),
                              child: _receiptImage == null
                                  ? Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(LucideIcons.uploadCloud,
                                            color: AppColors.accentYellow,
                                            size: 40),
                                        const SizedBox(height: 12),
                                        Text(AppLocalizations.of(context)!.tapToUploadScreenshot,
                                            style: TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 12)),
                                      ],
                                    )
                                  : Container(
                                      alignment: Alignment.topRight,
                                      padding: const EdgeInsets.all(12),
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle),
                                        child: const Icon(LucideIcons.edit2,
                                            color: Colors.white, size: 16),
                                      ),
                                    ),
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Notes
                          Text(AppLocalizations.of(context)!.notesOptionalLabel,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textSecondary,
                                  letterSpacing: 1.5)),
                          const SizedBox(height: 16),
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.backgroundSecondary,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.05)),
                            ),
                            child: TextField(
                              controller: _noteController,
                              style: TextStyle(color: AppColors.textPrimary),
                              maxLines: 3,
                              decoration: InputDecoration(
                                hintText: AppLocalizations.of(context)!.addNotesHint,
                                hintStyle: TextStyle(
                                    color: AppColors.textSecondary
                                        .withOpacity(0.5)),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.all(20),
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
            ),

            // Confirm Button
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_isUploading || _isLoadingPaymentData)
                      ? null
                      : _submitOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentYellow,
                    foregroundColor: AppColors.backgroundPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _isUploading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: AppColors.backgroundPrimary,
                              strokeWidth: 2))
                      : Text(AppLocalizations.of(context)!.confirmPaymentButton,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              letterSpacing: 1.0)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCopyableCard(String title, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.backgroundPrimary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.accentYellow, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0)),
                const SizedBox(height: 4),
                SelectableText(value,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace')),
              ],
            ),
          ),
          IconButton(
            icon: Icon(LucideIcons.copy,
                size: 18, color: AppColors.textSecondary),
            onPressed: () => _copyToClipboard(value),
            tooltip: AppLocalizations.of(context)!.copyTooltip,
          )
        ],
      ),
    );
  }

  Widget _buildLinkCard(String link) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.backgroundPrimary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(LucideIcons.link,
                    color: AppColors.accentYellow, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  link,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(LucideIcons.copy,
                    size: 18, color: AppColors.textSecondary),
                onPressed: () => _copyToClipboard(link),
              )
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () =>
                  _launchURL(link.startsWith('http') ? link : 'https://$link'),
              icon: const Icon(LucideIcons.externalLink, size: 14),
              label: Text(AppLocalizations.of(context)!.openLinkInstapayButton,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accentYellow,
                side:
                    BorderSide(color: AppColors.accentYellow.withOpacity(0.3)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
