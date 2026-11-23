import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';

/// شاشة التنبيه الأمني عند اكتشاف تسجيل الشاشة/الصوت.
///
/// مشتركة بين كل المشغّلات (MediaKit / Native / YouTube) بحيث:
///  • تتأقلم مع الوضع الأفقي (landscape) — المحتوى داخل SafeArea +
///    SingleChildScrollView فلا يمكن أن يخرج الزر خارج الشاشة أبداً
///    (السبب الأصلي للمشكلة: Column طويل بدون scroll كان يتجاوز ارتفاع
///    الشاشة الأفقية فيختفي زر الإغلاق ويضطر المستخدم لإعادة فتح التطبيق).
///  • فيها زر «إعادة المحاولة» يعيد فحص حالة التسجيل ويكمل التشغيل لو انتهى
///    (مثلاً بعد انتهاء مكالمة هاتفية أو تسجيل صوتي في واتساب).
///  • فيها زر «إغلاق المشغّل» للخروج الآمن.
class RecordingAlertOverlay extends StatelessWidget {
  /// يُنفَّذ عند الضغط على «إعادة المحاولة».
  final VoidCallback onRetry;

  /// يُنفَّذ عند الضغط على «إغلاق المشغّل».
  final VoidCallback onClose;

  /// true أثناء فحص الحالة بعد الضغط على إعادة المحاولة.
  final bool isChecking;

  /// إظهار صندوق «التحذير الأخير» (يُستخدم في مشغّل MediaKit).
  final bool showFinalWarning;

  const RecordingAlertOverlay({
    super.key,
    required this.onRetry,
    required this.onClose,
    this.isChecking = false,
    this.showFinalWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Material(
      color: Colors.red.shade900,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool compact = constraints.maxHeight < 520;
            final double iconSize = compact ? 44 : 80;
            final double titleSize = compact ? 20 : 28;
            final double msgSize = compact ? 13 : 16;
            final double gap = compact ? 8 : 16;

            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: 24, vertical: compact ? 8 : 16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.block, color: Colors.white, size: iconSize),
                          SizedBox(height: gap),
                          Text(
                            l10n.securityAlertTitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: titleSize,
                              fontWeight: FontWeight.bold,
                              letterSpacing: compact ? 1.0 : 2.0,
                            ),
                          ),
                          SizedBox(height: gap / 2),
                          Text(
                            l10n.screenRecordingDetectedMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white70, fontSize: msgSize),
                          ),
                          if (showFinalWarning) ...[
                            SizedBox(height: gap),
                            Container(
                              padding: EdgeInsets.all(compact ? 10 : 16),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: Colors.yellow, width: 2),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    l10n.finalWarningTitle,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.yellow,
                                        fontSize: compact ? 15 : 20,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  SizedBox(height: compact ? 4 : 8),
                                  Text(
                                    l10n.contentRecordingViolationMessage,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: compact ? 12 : 14),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          SizedBox(height: gap * 1.5),
                          // الأزرار جنب بعض (Wrap) عشان تاخد ارتفاع سطر واحد
                          // فقط في الوضع الأفقي، وتنزل تحت بعض لو العرض ضيّق.
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              ElevatedButton.icon(
                                onPressed: isChecking ? null : onRetry,
                                icon: isChecking
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.red.shade900,
                                        ),
                                      )
                                    : const Icon(Icons.refresh, size: 20),
                                label: Text(
                                  l10n.retry,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.red.shade900,
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: compact ? 8 : 12),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: onClose,
                                icon: const Icon(Icons.close, size: 20),
                                label: Text(
                                  l10n.closePlayer,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(
                                      color: Colors.white, width: 1.5),
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: compact ? 8 : 12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
