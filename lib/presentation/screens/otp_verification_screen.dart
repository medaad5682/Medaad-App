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

/// Shown right after the user submits the register form.
/// Confirms the OTP that was already emailed by RegisterScreen, then
/// finishes account creation with the resulting one-time verifyToken.
class OtpVerificationScreen extends StatefulWidget {
  final String email;
  final Map<String, dynamic> registrationData; // firstName, username, phone, password

  const OtpVerificationScreen({
    super.key,
    required this.email,
    required this.registrationData,
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final String _baseUrl = ApiConstants.baseUrl;
  final _codeController = TextEditingController();
  final _codeFocus = FocusNode();

  bool _isVerifying = false;
  bool _isResending = false;
  String? _errorMessage;

  Timer? _resendTimer;
  int _resendSecondsLeft = 60;

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("Entered OTP Verification Screen");
    _codeFocus.addListener(() => setState(() {}));
    _startResendCooldown();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _codeController.dispose();
    _codeFocus.dispose();
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
      final response = await ApiClient.instance.post(
        '$_baseUrl/api/auth/send-otp',
        data: {
          'email': widget.email,
          'purpose': 'signup',
          'username': widget.registrationData['username'],
          'phone': widget.registrationData['phone'],
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

  Future<void> _handleVerify() async {
    setState(() => _errorMessage = null);

    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = AppLocalizations.of(context)!.otpCodeRequired);
      return;
    }

    setState(() => _isVerifying = true);

    try {
      // Step 1: confirm the OTP code and obtain a one-time verifyToken
      final verifyResponse = await ApiClient.instance.post(
        '$_baseUrl/api/auth/verify-otp',
        data: {'email': widget.email, 'code': code, 'purpose': 'signup'},
        options: Options(validateStatus: (status) => status! < 500),
      );

      final verifyData = verifyResponse.data;

      if (!(verifyResponse.statusCode == 200 && verifyData['success'] == true)) {
        setState(() => _errorMessage =
            verifyData['message'] ?? AppLocalizations.of(context)!.otpVerifyFailedDefault);
        return;
      }

      final verifyToken = verifyData['verifyToken'];

      // Step 2: finish creating the account now that the email is confirmed
      final signupResponse = await ApiClient.instance.post(
        '$_baseUrl/api/auth/signup',
        data: {
          ...widget.registrationData,
          'email': widget.email,
          'verifyToken': verifyToken,
        },
        options: Options(validateStatus: (status) => status! < 500),
      );

      final signupData = signupResponse.data;

      if (signupResponse.statusCode == 200 && signupData['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.registerSuccessMessage),
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
        setState(() => _errorMessage =
            signupData['message'] ?? AppLocalizations.of(context)!.registerFailedDefault);
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack);
      setState(() => _errorMessage = AppLocalizations.of(context)!.connectionError);
    } finally {
      if (mounted) setState(() => _isVerifying = false);
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
                AppLocalizations.of(context)!.otpTitle,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${AppLocalizations.of(context)!.otpSubtitle}\n${widget.email}',
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
              const SizedBox(height: 24),

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
              const SizedBox(height: 32),

              // Verify Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isVerifying ? null : _handleVerify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentYellow,
                    foregroundColor: AppColors.backgroundPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 10,
                  ),
                  child: _isVerifying
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
                              AppLocalizations.of(context)!.otpVerifyButton,
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

              // Change email
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text(
                    AppLocalizations.of(context)!.otpChangeEmail,
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
}
