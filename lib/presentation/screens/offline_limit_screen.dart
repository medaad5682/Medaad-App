import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/offline_access_guard.dart';
import '../../l10n/generated/app_localizations.dart';
import 'splash_screen.dart';

// ============================================================
// 🔒 شاشة "انتهى حد الدخول بدون إنترنت"
// ============================================================
// تظهر بدل MainWrapper حين يُستنفد حد الدخول أوفلاين
// (OfflineAccessGuard.maxOfflineEntries). لا تُحمَّل أي بيانات مخبأة ولا
// يُعرض أي محتوى محمَّل. زر "إعادة المحاولة" يعيد تشغيل SplashScreen؛ فإن
// نجح طلب get-app-init-data يُصفَّر العدّاد وتُنظَّف التحميلات الملغاة
// تلقائياً ويدخل المستخدم بشكل طبيعي، وإلا يعود لهذه الشاشة دون احتساب.
class OfflineLimitScreen extends StatefulWidget {
  const OfflineLimitScreen({super.key});

  @override
  State<OfflineLimitScreen> createState() => _OfflineLimitScreenState();
}

class _OfflineLimitScreenState extends State<OfflineLimitScreen> {
  bool _checking = false;

  Future<void> _retry() async {
    if (_checking) return;
    setState(() => _checking = true);

    bool hasNetwork = true;
    try {
      final results = await Connectivity()
          .checkConnectivity()
          .timeout(const Duration(seconds: 3));
      hasNetwork = results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      // تعذّر فحص الاتصال نفسه: نترك SplashScreen تحاول فعلياً بدل منع المستخدم.
      hasNetwork = true;
    }

    if (!mounted) return;

    if (!hasNetwork) {
      setState(() => _checking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context)!.offlineLimitStillOffline),
          backgroundColor: Colors.grey,
        ),
      );
      return;
    }

    // إعادة تشغيل مسار الإقلاع الكامل (يحاول get-app-init-data من جديد).
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SplashScreen()),
      (route) => false,
    );
  }

  // كارت شرح النظام: يُعرَض فيه n = OfflineAccessGuard.maxOfflineEntries
  Widget _buildHowItWorksCard(AppLocalizations l10n) {
    const int n = OfflineAccessGuard.maxOfflineEntries;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.textSecondary.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.info, size: 16, color: AppColors.accentYellow),
              const SizedBox(width: 8),
              Text(
                l10n.offlineLimitHowTitle,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accentYellow,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildRule(1, l10n.offlineLimitRule1(n)),
          _buildRule(2, l10n.offlineLimitRule2),
          _buildRule(3, l10n.offlineLimitRule3(n)),
        ],
      ),
    );
  }

  Widget _buildRule(int number, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accentYellow.withOpacity(0.15),
            ),
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.accentYellow,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.error.withOpacity(0.12),
                      ),
                      child: Icon(
                        LucideIcons.wifiOff,
                        size: 44,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    l10n.offlineLimitTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.offlineLimitBody(
                        OfflineAccessGuard.maxOfflineEntries),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildHowItWorksCard(l10n),
                  const SizedBox(height: 28),
                  ElevatedButton(
                    onPressed: _checking ? null : _retry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentYellow,
                      foregroundColor: AppColors.backgroundPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      elevation: 10,
                      shadowColor: AppColors.accentYellow.withOpacity(0.2),
                    ),
                    child: _checking
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.backgroundPrimary,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(LucideIcons.refreshCw, size: 18),
                              const SizedBox(width: 10),
                              Text(
                                l10n.retry,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
