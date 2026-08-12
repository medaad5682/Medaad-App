import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/api_constants.dart';
import '../../core/services/api_client.dart';
import '../../l10n/generated/app_localizations.dart';
import 'login_screen.dart';
import 'package:Medaad/presentation/widgets/directional_icon.dart';

/// Second step of the "forgot password" flow.
/// Confirms the OTP that ForgotPasswordScreen already emailed, then sets a
/// new password using the resulting one-time verifyToken.
class ResetPasswordScreen extends StatefulWidget {
  final String identifier;
  final String email;
  final String maskedEmail;

  const ResetPasswordScreen({
    super.key,
    required this.identifier,
    required this.email,
    required this.maskedEmail,
  });

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final String _baseUrl = ApiConstants.baseUrl;
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _codeFocus = FocusNode();
  final _passFocus = FocusNode();
  final _confirmPassFocus = FocusNode();

  bool _isSubmitting = false;
  bool _isResending = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  Timer? _resendTimer;
  int _resendSecondsLeft = 60;

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("Entered Reset Password Screen");
    for (var node in [_codeFocus, _passFocus, _confirmPassFocus]) {
      node.addListener(() => setState(() {}));
    }
    _startResendCooldown();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _codeFocus.dispose();
    _passFocus.dispose();
    _confirmPassFocus.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    setState(() => _resendSecondsLeft = 60);
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendSecondsLeft <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendSecondsLeft = 0);
      } else {
        if (mounted) setState(() => _resendSecondsLeft--);
      }
    });
  }

  Future<void> _handleResend() async {
    if (_resendSecondsLeft > 0 || _isResending) return;

    setState(() {
      _isResending = true;
      _errorMessage = null;
    });

    try {
      // reset_password OTP requests are re-resolved by identifier each
      // time (single field: username, phone, or email) — we reuse the
      // same identifier the user typed on the previous screen.
      final response = await ApiClient.instance.post(
        '$_baseUrl/api/auth/send-otp',
        data: {
          'purpose': 'reset_password',
          'identifier': widget.identifier,
        },
        options: Options(validateStatus: (status) => status! < 500),
      );

      final data = response.data;

      if (response.statusCode == 200 && data['success'] == true) {
        if (mounted) {
          _startResendCooldown();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.otpSentMessage),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else {
        setState(() => _errorMessage =
            data['message'] ?? AppLocalizations.of(context)!.otpSendFailedDefault);
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack);
      setState(() => _errorMessage = AppLocalizations.of(context)!.connectionError);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  Future<void> _handleReset() async {
    setState(() => _errorMessage = null);

    final code = _codeController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (code.length != 6) {
      setState(() => _errorMessage = AppLocalizations.of(context)!.otpCodeRequired);
      return;
    }
    if (password.length < 6) {
      setState(() =>
          _errorMessage = AppLocalizations.of(context)!.registerPasswordTooShort);
      return;
    }
    if (password != confirmPassword) {
      setState(() =>
          _errorMessage = AppLocalizations.of(context)!.registerPasswordMismatch);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // Step 1: confirm the OTP code and obtain a one-time verifyToken
      final verifyResponse = await ApiClient.instance.post(
        '$_baseUrl/api/auth/verify-otp',
        data: {
          'email': widget.email,
          'code': code,
          'purpose': 'reset_password',
        },
        options: Options(validateStatus: (status) => status! < 500),
      );

      final verifyData = verifyResponse.data;

      if (!(verifyResponse.statusCode == 200 && verifyData['success'] == true)) {
        setState(() => _errorMessage =
            verifyData['message'] ?? AppLocalizations.of(context)!.otpVerifyFailedDefault);
        return;
      }

      final verifyToken = verifyData['verifyToken'];

      // Step 2: finish resetting the password now that the code is confirmed
      final resetResponse = await ApiClient.instance.post(
        '$_baseUrl/api/auth/reset-password',
        data: {
          'email': widget.email,
          'verifyToken': verifyToken,
          'newPassword': password,
        },
        options: Options(validateStatus: (status) => status! < 500),
      );

      final resetData = resetResponse.data;

      if (resetResponse.statusCode == 200 && resetData['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.resetPasswordSuccessMessage),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );
        }
      } else {
        setState(() => _errorMessage = resetData['message'] ??
            AppLocalizations.of(context)!.resetPasswordFailedDefault);
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack);
      setState(() => _errorMessage = AppLocalizations.of(context)!.connectionError);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
                '${AppLocalizations.of(context)!.resetOtpSubtitle}\n${widget.maskedEmail}',
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

              // Code Field
              Container(
                decoration: BoxDecoration(
                  color: AppColors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _codeFocus.hasFocus
                        ? AppColors.accentYellow.withOpacity(0.5)
                        : AppColors.textSecondary.withOpacity(0.1),
                  ),
                ),
                child: TextField(
                  controller: _codeController,
                  focusNode: _codeFocus,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
                  cursorColor: AppColors.accentYellow,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '••••••',
                    hintStyle:
                        TextStyle(color: AppColors.textSecondary.withOpacity(0.3)),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Resend row
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.otpDidntReceive,
                      style:
                          TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: (_resendSecondsLeft > 0 || _isResending)
                          ? null
                          : _handleResend,
                      child: Text(
                        _resendSecondsLeft > 0
                            ? AppLocalizations.of(context)!
                                .otpResendIn(_resendSecondsLeft)
                            : AppLocalizations.of(context)!.otpResendButton,
                        style: TextStyle(
                          color: _resendSecondsLeft > 0
                              ? AppColors.textSecondary.withOpacity(0.5)
                              : AppColors.accentYellow,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          decoration: _resendSecondsLeft > 0
                              ? TextDecoration.none
                              : TextDecoration.underline,
                          decorationColor: AppColors.accentYellow,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _buildInputLabel(AppLocalizations.of(context)!.newPasswordLabel),
              const SizedBox(height: 4),
              _buildPasswordField(
                controller: _passwordController,
                focusNode: _passFocus,
                obscureText: _obscurePassword,
                onToggleObscure: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
              const SizedBox(height: 16),

              _buildInputLabel(AppLocalizations.of(context)!.confirmNewPasswordLabel),
              const SizedBox(height: 4),
              _buildPasswordField(
                controller: _confirmPasswordController,
                focusNode: _confirmPassFocus,
                obscureText: _obscureConfirmPassword,
                onToggleObscure: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
              const SizedBox(height: 32),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _handleReset,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentYellow,
                    foregroundColor: AppColors.backgroundPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 10,
                  ),
                  child: _isSubmitting
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
                              AppLocalizations.of(context)!.resetPasswordButton,
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

  Widget _buildPasswordField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required bool obscureText,
    required VoidCallback onToggleObscure,
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
        obscureText: obscureText,
        style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
        cursorColor: AppColors.accentYellow,
        decoration: InputDecoration(
          hintText: "••••••",
          hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          prefixIcon: Icon(
            LucideIcons.lock,
            size: 18,
            color: isActive ? AppColors.accentYellow : AppColors.textSecondary,
          ),
          suffixIcon: IconButton(
            onPressed: onToggleObscure,
            icon: Icon(
              obscureText ? LucideIcons.eye : LucideIcons.eyeOff,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
