import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
// ✅ إضافة استيراد Firebase App Check
import 'package:firebase_app_check/firebase_app_check.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/teacher_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/constants/api_constants.dart';
import 'package:Medaad/l10n/generated/app_localizations.dart';

class StudentRequestsScreen extends StatefulWidget {
  const StudentRequestsScreen({Key? key}) : super(key: key);

  @override
  State<StudentRequestsScreen> createState() => _StudentRequestsScreenState();
}

class _StudentRequestsScreenState extends State<StudentRequestsScreen>
    with SingleTickerProviderStateMixin {
  final TeacherService _teacherService = TeacherService();

  // متغيرات التبويبات والصفحات
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isFetchingMore = false;
  bool _hasMoreData = true;
  int _currentPage = 1;
  String _currentStatus = 'pending'; // pending, approved, rejected
  List<dynamic> _requests = [];

  // بيانات المصادقة للصور
  String? _token;
  String? _deviceId;
  String? _appCheckToken; // ✅ متغير جديد لتخزين توكن الحماية
  final String _appSecret = const String.fromEnvironment('APP_SECRET');

  final String _baseUrl = ApiConstants.baseUrl;
  String get _receiptProxyUrl =>
      "$_baseUrl/api/admin/file-proxy?type=receipts&filename=";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabSelection);

    // مراقب التمرير لجلب المزيد من البيانات عند الوصول للأسفل
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 100) {
        _loadMoreRequests();
      }
    });

    _initialLoad();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) return;

    String newStatus;
    switch (_tabController.index) {
      case 0:
        newStatus = 'pending';
        break;
      case 1:
        newStatus = 'approved';
        break;
      case 2:
        newStatus = 'rejected';
        break;
      default:
        newStatus = 'pending';
    }

    if (newStatus != _currentStatus) {
      setState(() {
        _currentStatus = newStatus;
        _isLoading = true;
      });
      _refreshRequests(); // تصفير وإعادة تحميل
    }
  }

  Future<void> _initialLoad() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      var box = await StorageService.openBox('auth_box');
      _token = box.get('jwt_token');
      _deviceId = box.get('device_id');

      // ✅ جلب توكن App Check لاستخدامه في تحميل الصور
      try {
        _appCheckToken = await FirebaseAppCheck.instance.getToken();
      } catch (e) {
        debugPrint("App Check Error: $e");
      }

      debugPrint("Auth Loaded: DeviceID=$_deviceId");

      await _loadRequestsData(isRefresh: true);
    } catch (e) {
      debugPrint("Error in initial load: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!.errorLoadingDataWithDetails(e.toString())),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _loadRequestsData({bool isRefresh = false}) async {
    if (isRefresh) {
      _currentPage = 1;
      _hasMoreData = true;
    }

    if (!_hasMoreData) return;

    try {
      // نستخدم الدالة المحدثة التي تدعم الحالة والصفحة
      // يتم حقن الهيدرز تلقائياً عبر ApiClient داخل TeacherService
      final data = await _teacherService.getRequests(
          status: _currentStatus, page: _currentPage);

      if (mounted) {
        setState(() {
          if (isRefresh) {
            _requests = data;
          } else {
            _requests.addAll(data);
          }

          // إذا كانت البيانات العائدة أقل من 10، معناه وصلنا للنهاية
          _hasMoreData = data.length >= 10;
          _isLoading = false;
          _isFetchingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isFetchingMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!.failedToFetchDataWithDetails(e.toString())),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _loadMoreRequests() async {
    if (_isFetchingMore || !_hasMoreData || _isLoading) return;

    setState(() => _isFetchingMore = true);
    _currentPage++;
    await _loadRequestsData(isRefresh: false);
  }

  Future<void> _refreshRequests() async {
    await _loadRequestsData(isRefresh: true);
  }

  Future<void> _handleDecision(String requestId, bool approve) async {
    String? rejectionReason;

    if (!approve) {
      rejectionReason = await showDialog<String>(
        context: context,
        builder: (ctx) {
          String reason = "";
          return AlertDialog(
            backgroundColor: AppColors.backgroundSecondary,
            title: Text(AppLocalizations.of(context)!.rejectionReasonDialogTitle,
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            content: TextField(
              onChanged: (val) => reason = val,
              style: TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.rejectionReasonHint,
                hintStyle: TextStyle(color: AppColors.textSecondary),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: AppColors.backgroundPrimary,
              ),
              maxLines: 3,
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(AppLocalizations.of(context)!.cancel,
                      style: TextStyle(color: AppColors.textSecondary))),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, reason),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(AppLocalizations.of(context)!.confirmRejectionAction,
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      );

      if (rejectionReason == null) return;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!.processingActionMessage),
            duration: const Duration(seconds: 1)),
      );

      await _teacherService.handleRequest(requestId, approve,
          reason: rejectionReason);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(approve ? Icons.check_circle : Icons.cancel,
                    color: Colors.white),
                const SizedBox(width: 8),
                Text(approve ? AppLocalizations.of(context)!.studentApprovedSuccessMessage : AppLocalizations.of(context)!.requestRejectedMessage),
              ],
            ),
            backgroundColor: approve ? AppColors.success : AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
      _refreshRequests();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!.operationFailedWithDetails(e.toString())),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _showFullImage(String url) {
    if (_deviceId == null || _token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(AppLocalizations.of(context)!.authDataNotReadyError),
            backgroundColor: AppColors.error),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CachedNetworkImage(
                  imageUrl: url,
                  httpHeaders: {
                    'Authorization': 'Bearer $_token',
                    'x-device-id': _deviceId!,
                    'x-app-secret': _appSecret,
                    // ✅ إضافة توكن الحماية هنا
                    if (_appCheckToken != null) 'X-Firebase-AppCheck': _appCheckToken!,
                  },
                  placeholder: (context, url) => Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accentYellow)),
                  errorWidget: (context, url, error) => Container(
                    color: AppColors.backgroundSecondary,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image_rounded,
                            color: AppColors.error, size: 50),
                        const SizedBox(height: 8),
                        Text(AppLocalizations.of(context)!.imageLoadFailedCheckConnection,
                            style: TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.subscriptionRequestsTitle,
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.backgroundSecondary,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.accentYellow),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.accentYellow,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.accentYellow,
          tabs: [
            Tab(text: AppLocalizations.of(context)!.tabPending),
            Tab(text: AppLocalizations.of(context)!.tabApproved),
            Tab(text: AppLocalizations.of(context)!.tabRejected),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshRequests,
        color: AppColors.accentYellow,
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(color: AppColors.accentYellow))
            : _requests.isEmpty
                ? SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: MediaQuery.of(context).size.height * 0.7,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox_rounded,
                                size: 80,
                                color:
                                    AppColors.textSecondary.withOpacity(0.3)),
                            const SizedBox(height: 16),
                            Text(AppLocalizations.of(context)!.noRequestsInListMessage,
                                style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 18)),
                          ],
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                    itemCount: _requests.length + (_isFetchingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _requests.length) {
                        return Center(
                            child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(
                              color: AppColors.accentYellow),
                        ));
                      }
                      return _buildRequestCard(_requests[index]);
                    },
                  ),
      ),
    );
  }

  Widget _buildRequestCard(dynamic req) {
    final String? filename = req['payment_file_path'];
    final bool hasImage = filename != null && filename.isNotEmpty;
    final String imageUrl = hasImage ? "$_receiptProxyUrl$filename" : "";

    final String? userNote = req['user_note'];
    final bool hasNote = userNote != null && userNote.trim().isNotEmpty;

    // منطق حساب السعر الفعلي والمخصوم
    final num originalPrice = req['total_price'] ?? 0;
    final num? actualPaidPrice = req['actual_paid_price'];
    final bool hasDiscount =
        actualPaidPrice != null && actualPaidPrice < originalPrice;

    String dateStr = req['created_at'] ?? "";
    if (dateStr.length > 10) dateStr = dateStr.substring(0, 10);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // ================== القسم العلوي (الصورة والبيانات) ==================
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () {
                    if (hasImage) _showFullImage(imageUrl);
                  },
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppColors.textSecondary.withOpacity(0.1)),
                      color: AppColors.backgroundPrimary,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: hasImage
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              httpHeaders: {
                                'Authorization': 'Bearer $_token',
                                'x-device-id': _deviceId ?? '',
                                'x-app-secret': _appSecret,
                                // ✅ إضافة توكن الحماية هنا
                                if (_appCheckToken != null) 'X-Firebase-AppCheck': _appCheckToken!,
                              },
                              fit: BoxFit.cover,
                              placeholder: (c, u) => Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.accentYellow)),
                              errorWidget: (c, u, e) => Icon(
                                  Icons.broken_image_rounded,
                                  color: AppColors.textSecondary),
                            )
                          : Icon(Icons.receipt_long_rounded,
                              color: AppColors.textSecondary, size: 35),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              req['user_name'] ?? AppLocalizations.of(context)!.unknownNameFallback,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: AppColors.textPrimary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: AppColors.backgroundPrimary,
                                borderRadius: BorderRadius.circular(8)),
                            child: Text(dateStr,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary)),
                          )
                        ],
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                          Icons.phone_android_rounded, req['phone'] ?? '---'),
                      const SizedBox(height: 4),
                      _buildInfoRow(Icons.alternate_email_rounded,
                          req['user_username'] ?? '---'),
                    ],
                  ),
                ),
              ],
            ),

            Divider(
                height: 24, color: AppColors.textSecondary.withOpacity(0.1)),

            // ================== التفاصيل والسعر والملاحظة ==================
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      // صندوق تفاصيل الكورس
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: AppColors.backgroundPrimary.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.accentBlue.withOpacity(0.3))),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.shopping_cart_outlined,
                                    size: 16, color: AppColors.accentBlue),
                                const SizedBox(width: 6),
                                Text(AppLocalizations.of(context)!.requestedContentLabel,
                                    style: TextStyle(
                                        color: AppColors.accentBlue,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              req['course_title'] ?? AppLocalizations.of(context)!.notSpecifiedFallback,
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  height: 1.3),
                            ),
                          ],
                        ),
                      ),

                      if (hasNote) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.amber.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.edit_note_rounded,
                                      size: 16, color: Colors.amber),
                                  const SizedBox(width: 6),
                                  Text(AppLocalizations.of(context)!.studentNoteLabel,
                                      style: TextStyle(
                                          color: Colors.amber,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                userNote,
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    height: 1.3),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // عرض سبب الرفض إن وجد
                      if (_currentStatus == 'rejected' &&
                          req['rejection_reason'] != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.error.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline_rounded,
                                      size: 16, color: AppColors.error),
                                  const SizedBox(width: 6),
                                  Text(AppLocalizations.of(context)!.rejectionReasonLabel,
                                      style: TextStyle(
                                          color: AppColors.error,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                req['rejection_reason'],
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    height: 1.3),
                              ),
                            ],
                          ),
                        ),
                      ]
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // ✅ صندوق السعر مع عرض الخصم والخط المشطوب
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                        color: AppColors.backgroundPrimary.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: hasDiscount
                                ? Colors.amber.withOpacity(0.5)
                                : AppColors.success.withOpacity(0.3))),
                    child: Column(
                      children: [
                        Text(AppLocalizations.of(context)!.totalLabel,
                            style: TextStyle(
                                color: hasDiscount
                                    ? Colors.amber
                                    : AppColors.success,
                                fontSize: 11)),
                        const SizedBox(height: 4),

                        // السعر القديم المشطوب (يظهر فقط إذا كان هناك خصم)
                        if (hasDiscount)
                          Text(AppLocalizations.of(context)!.priceEgp(originalPrice.toString()),
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor: AppColors.error,
                                  decorationThickness: 2)),

                        // السعر النهائي (سواء بخصم أو بدون)
                        Text(
                            hasDiscount ? "$actualPaidPrice" : "$originalPrice",
                            style: TextStyle(
                                color: hasDiscount
                                    ? Colors.amber
                                    : AppColors.success,
                                fontWeight: FontWeight.bold,
                                fontSize: 18)),
                        Text(AppLocalizations.of(context)!.egpCurrencyLabel,
                            style: TextStyle(
                                color: hasDiscount
                                    ? Colors.amber
                                    : AppColors.success,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // ================== الأزرار (تظهر فقط في حالة قيد الانتظار) ==================
            if (_currentStatus == 'pending') ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _handleDecision(req['id'].toString(), false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(
                            color: AppColors.error.withOpacity(0.5),
                            width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 20),
                      label: Text(AppLocalizations.of(context)!.rejectRequestAction,
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _handleDecision(req['id'].toString(), true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.check_circle_outline_rounded,
                          size: 20),
                      label: Text(AppLocalizations.of(context)!.acceptAndActivateAction,
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
