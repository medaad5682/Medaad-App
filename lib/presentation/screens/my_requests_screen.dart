import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../l10n/generated/app_localizations.dart';

class MyRequestsScreen extends StatefulWidget {
  const MyRequestsScreen({super.key});

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  bool _loading = true;
  List<dynamic> _requests = [];
  final String _baseUrl = ApiConstants.baseUrl;

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    try {
      // ✅ تم الاعتماد على ApiClient دون الحاجة لجلب التوكن أو تمرير الهيدرز يدوياً
      final res = await ApiClient.instance.get(
        '$_baseUrl/api/student/my-requests',
      );

      if (mounted) {
        setState(() {
          _requests = res.data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
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
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: Icon(LucideIcons.arrowLeft,
                          color: AppColors.accentYellow, size: 20),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.myRequestsTitle,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppLocalizations.of(context)!.trackYourOrdersLabel,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // --- List ---
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                          color: AppColors.accentYellow))
                  : _requests.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.inbox,
                                  size: 48,
                                  color:
                                      AppColors.textSecondary.withOpacity(0.2)),
                              const SizedBox(height: 16),
                              Text(
                                AppLocalizations.of(context)!.noRequestsFound,
                                style: TextStyle(
                                  color:
                                      AppColors.textSecondary.withOpacity(0.5),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: _requests.length,
                          itemBuilder: (context, index) {
                            return _buildRequestCard(_requests[index]);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
    String status = req['status'] ?? 'pending';
    Color statusColor;
    IconData statusIcon;

    String statusLabel;

    switch (status) {
      case 'approved':
        statusColor = AppColors.success;
        statusIcon = LucideIcons.checkCircle;
        statusLabel = AppLocalizations.of(context)!.requestStatusApproved;
        break;
      case 'rejected':
        statusColor = AppColors.error;
        statusIcon = LucideIcons.xCircle;
        statusLabel = AppLocalizations.of(context)!.requestStatusRejected;
        break;
      default:
        statusColor = AppColors.accentYellow;
        statusIcon = LucideIcons.clock;
        statusLabel = AppLocalizations.of(context)!.requestStatusPending;
    }

    // ✅ استخراج الملاحظة
    final String? userNote = req['user_note'];
    final bool hasNote = userNote != null && userNote.trim().isNotEmpty;

    // ✅ استخراج الأسعار وتحديد وجود خصم
    final num originalPrice = req['total_price'] ?? 0;
    final num? actualPaidPrice = req['actual_paid_price'];
    final bool hasDiscount = req['has_discount'] == true ||
        (actualPaidPrice != null && actualPaidPrice < originalPrice);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.backgroundPrimary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text("#${req['id']}",
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
              Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 14),
                  const SizedBox(width: 6),
                  Text(statusLabel,
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            req['course_title'] ?? AppLocalizations.of(context)!.unknownItemFallback,
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // ✅ عرض السعر مع الخصم إذا وجد
          if (hasDiscount)
            Row(
              children: [
                Text(
                  AppLocalizations.of(context)!.priceEgp(originalPrice.toString()),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: AppColors.error,
                    decorationThickness: 2,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context)!.priceEgp(actualPaidPrice.toString()),
                  style: TextStyle(
                      color: AppColors.accentYellow,
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                ),
              ],
            )
          else
            Text(
              AppLocalizations.of(context)!.priceEgp(originalPrice.toString()),
              style: TextStyle(
                  color: AppColors.accentYellow,
                  fontSize: 14,
                  fontWeight: FontWeight.bold),
            ),

          // ✅ عرض الملاحظة هنا
          if (hasNote)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.fileText, size: 12, color: Colors.amber),
                      const SizedBox(width: 4),
                      Text(
                        AppLocalizations.of(context)!.yourNoteLabel,
                        style: TextStyle(
                            color: Colors.amber,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    userNote,
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.4),
                  ),
                ],
              ),
            ),

          if (status == 'rejected' && req['rejection_reason'] != null)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withOpacity(0.2)),
              ),
              child: Text(
                AppLocalizations.of(context)!.rejectionReasonLabel(req['rejection_reason'].toString()),
                style: TextStyle(color: AppColors.error, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}
