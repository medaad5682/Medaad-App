import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/storage_service.dart'; // ✅ استيراد خدمة التخزين
import 'privacy_policy_screen.dart';
import 'terms_conditions_screen.dart';
import '../../l10n/generated/app_localizations.dart';

class DevInfoScreen extends StatefulWidget {
  const DevInfoScreen({super.key});

  @override
  State<DevInfoScreen> createState() => _DevInfoScreenState();
}

class _DevInfoScreenState extends State<DevInfoScreen> {
  String? whatsappLink;
  String? telegramLink;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContactInfo();
  }

  // ✅ تحميل بيانات التواصل المخزنة (التي تم جلبها من السيرفر)
  Future<void> _loadContactInfo() async {
    final info = await StorageService.getContactInfo();
    if (mounted) {
      setState(() {
        whatsappLink = info['whatsapp'];
        telegramLink = info['telegram'];
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                      ),
                      child: Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow, size: 20),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    AppLocalizations.of(context)!.appInformation.toUpperCase(),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    // App Info Card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 100, 
                            height: 100,
                            margin: const EdgeInsets.only(bottom: 16),
                            child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
                          ),
                          
                          Text(
                            "مــــــداد",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            AppLocalizations.of(context)!.craftedWithPassion,
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 32),
                          
                          // ✅ أزرار التواصل الديناميكية (تظهر فقط إذا توفرت الروابط)
                          if (isLoading)
                             const CircularProgressIndicator(strokeWidth: 2)
                          else
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (whatsappLink != null && whatsappLink!.isNotEmpty)
                                  _buildSocialBtn(
                                    icon: LucideIcons.messageCircle, // أيقونة واتساب
                                    url: whatsappLink!, 
                                  ),
                                
                                if ((whatsappLink != null && whatsappLink!.isNotEmpty) && 
                                    (telegramLink != null && telegramLink!.isNotEmpty))
                                  const SizedBox(width: 24),

                                if (telegramLink != null && telegramLink!.isNotEmpty)
                                  _buildSocialBtn(
                                    icon: LucideIcons.send, // أيقونة تليجرام
                                    url: telegramLink!, 
                                  ),
                              ],
                            )
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Legal & Docs
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 12),
                        child: Text(AppLocalizations.of(context)!.legalAndDocs.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 2.0)),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          _buildDocItem(
                            context: context,
                            icon: LucideIcons.shield, 
                            title: AppLocalizations.of(context)!.privacyPolicy,
                            onTap: () {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()));
                            }
                          ),
                          const Divider(height: 1, color: Colors.white10),
                          _buildDocItem(
                            context: context,
                            icon: LucideIcons.fileText, 
                            title: AppLocalizations.of(context)!.termsAndConditions,
                            onTap: () {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsConditionsScreen()));
                            }
                          ),
                          const Divider(height: 1, color: Colors.white10),
                          // ✅ زر الدعم الفني يستخدم رابط الواتساب الديناميكي
                          _buildDocItem(
                            context: context,
                            icon: LucideIcons.phone, 
                            title: AppLocalizations.of(context)!.contactSupport,
                            onTap: () async {
                              if (whatsappLink != null && whatsappLink!.isNotEmpty) {
                                final Uri uri = Uri.parse(whatsappLink!);
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(AppLocalizations.of(context)!.supportContactNotAvailable), backgroundColor: AppColors.error),
                                );
                              }
                            }
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Developers Info
                    Text(
                      AppLocalizations.of(context)!.developedBy.toUpperCase(),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 2.0),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "A7MeD & 5@LiD   WaLiD",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.accentYellow),
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialBtn({required IconData icon, required String url}) {
    return GestureDetector(
      onTap: () async {
        final Uri uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.backgroundPrimary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.05)),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
        child: Icon(icon, color: AppColors.accentYellow, size: 24),
      ),
    );
  }

  Widget _buildDocItem({required BuildContext context, required IconData icon, required String title, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap, 
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.backgroundPrimary,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                ),
                child: Icon(icon, color: AppColors.accentYellow, size: 18),
              ),
              const SizedBox(width: 16),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Icon(LucideIcons.chevronRight, color: AppColors.textSecondary, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
