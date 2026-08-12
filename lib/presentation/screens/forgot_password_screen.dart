import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/api_constants.dart';
import '../../core/services/api_client.dart';
import '../../l10n/generated/app_localizations.dart';
import 'package:Medaad/presentation/widgets/directional_icon.dart';
import 'reset_password_screen.dart';

/// First step of the "forgot password" flow.
/// The user identifies their account with ANY ONE of username / phone /
/// email. The backend looks up the matching account and sends the OTP to
/// that account's own registered email (never to whatever was typed here),
/// then this screen hands off to ResetPasswordScreen with the masked email.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _identifierController = TextEditingController();
  final _identifierFocus = FocusNode();

  final String _baseUrl = ApiConstants.baseUrl;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("Entered Forgot Password Screen");
    _identifierFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _identifierFocus.dispose();
    super.dispose();
  }

  Future<void> _handleSendCode() async {
    setState(() => _errorMessage = null);

    final identifier = _identifierController.text.trim();

    if (identifier.isEmpty) {
      setState(() =>
          _errorMessage = AppLocalizations.of(context)!.forgotPasswordAllFieldsRequired);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await ApiClient.instance.post(
        '$_baseUrl/api/auth/send-otp',
        data: {
          'purpose': 'reset_password',
          'identifier': identifier,
        },
        options: Options(validateStatus: (status) => status! < 500),
      );

      final data = response.data;

      if (response.statusCode == 200 && data['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.otpSentMessage),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ResetPasswordScreen(
                identifier: identifier,
                email: data['email'] ?? '',
                maskedEmail: data['maskedEmail'] ?? '',
              ),
            ),
          );
        }
      } else {
        setState(() => _errorMessage = data['message'] ??
            AppLocalizations.of(context)!.forgotPasswordNoMatch);
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack);
      setState(() => _errorMessage = AppLocalizations.of(context)!.connectionError);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // Back Button
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundSecondary,
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(
                        color: AppColors.textSecondary.withOpacity(0.1)),
                  ),
                  child: DirectionalFlip(
                      child: Icon(LucideIcons.arrowLeft,
                          color: AppColors.accentYellow, size: 20)),
                ),
              ),

              // Header
              Text(
                AppLocalizations.of(context)!.forgotPasswordTitle,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppLocalizations.of(context)!.forgotPasswordSubtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 32),

              // Error Display
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.alertCircle,
                          color: AppColors.error, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style:
                              TextStyle(color: AppColors.error, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              // --- Form Field ---

              _buildInputLabel(AppLocalizations.of(context)!.identifierLabel),
              const SizedBox(height: 4),
              _buildTextField(
                controller: _identifierController,
                focusNode: _identifierFocus,
                hint: AppLocalizations.of(context)!.identifierHint,
                icon: LucideIcons.user,
              ),
              const SizedBox(height: 32),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleSendCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentYellow,
                    foregroundColor: AppColors.backgroundPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 10,
                  ),
                  child: _isLoading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.backgroundPrimary))
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              AppLocalizations.of(context)!.sendCodeButton,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(width: 12),
                            DirectionalFlip(
                                child: Icon(LucideIcons.arrowRight, size: 18)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 20),

              Center(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text(
                    AppLocalizations.of(context)!.backToLogin,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: AppColors.accentYellow,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required IconData icon,
    TextInputType inputType = TextInputType.text,
  }) {
    final isActive = controller.text.isNotEmpty || focusNode.hasFocus;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: focusNode.hasFocus
              ? AppColors.accentYellow.withOpacity(0.5)
              : AppColors.textSecondary.withOpacity(0.1),
        ),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: inputType,
        style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
        cursorColor: AppColors.accentYellow,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          prefixIcon: Icon(
            icon,
            size: 18,
            color: isActive ? AppColors.accentYellow : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
