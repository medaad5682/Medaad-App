import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import '../../core/constants/app_colors.dart';
import 'login_screen.dart';
import '../../core/constants/api_constants.dart';
import '../../core/services/api_client.dart';
import '../../l10n/generated/app_localizations.dart';
import 'package:Medaad/presentation/widgets/directional_icon.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // Controllers
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Focus Nodes
  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _userFocus = FocusNode();
  final _passFocus = FocusNode();
  final _confirmPassFocus = FocusNode();

  final String _baseUrl = ApiConstants.baseUrl;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    FirebaseCrashlytics.instance.log("Entered Register Screen");
    // تحديث الواجهة عند تغيير التركيز
    for (var node in [
      _nameFocus,
      _phoneFocus,
      _userFocus,
      _passFocus,
      _confirmPassFocus
    ]) {
      node.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    _confirmPassFocus.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    setState(() => _errorMessage = null);

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    // Validation
    if (name.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = AppLocalizations.of(context)!.registerAllFieldsRequired);
      return;
    }

    final usernameRegex = RegExp(r'^[a-zA-Z0-9]+$');
    if (!usernameRegex.hasMatch(username)) {
      setState(() =>
          _errorMessage = AppLocalizations.of(context)!.registerUsernameInvalid);
      return;
    }

    final phoneRegex = RegExp(r'^01[0-9]{9}$');
    if (phone.isNotEmpty && !phoneRegex.hasMatch(phone)) {
      setState(() =>
          _errorMessage = AppLocalizations.of(context)!.registerPhoneInvalid);
      return;
    }

    if (password.length < 6) {
      setState(() => _errorMessage = AppLocalizations.of(context)!.registerPasswordTooShort);
      return;
    }

    if (password != confirmPassword) {
      setState(() => _errorMessage = AppLocalizations.of(context)!.registerPasswordMismatch);
      return;
    }

    // Call API
    setState(() => _isLoading = true);

    try {
      // ✅ الاعتماد على ApiClient بالكامل دون الحاجة لإرسال الهيدرز أو توكن AppCheck يدوياً
      final response = await ApiClient.instance.post(
        '$_baseUrl/api/auth/signup',
        data: {
          'firstName': name,
          'username': username,
          'phone': phone.isEmpty ? null : phone,
          'password': password,
        },
        options: Options(
          validateStatus: (status) => status! < 500,
        ),
      );

      final data = response.data;

      if (response.statusCode == 200 && data['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.registerSuccessMessage),
              backgroundColor: AppColors.success,
            ),
          );
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
      } else {
        setState(
            () => _errorMessage = data['message'] ?? AppLocalizations.of(context)!.registerFailedDefault);
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
                  child: DirectionalFlip(child: Icon(LucideIcons.arrowLeft,
                      color: AppColors.accentYellow, size: 20)),
                ),
              ),

              // Header
              Text(
                AppLocalizations.of(context)!.createAccount,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppLocalizations.of(context)!.registerSubtitle,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accentYellow,
                  letterSpacing: 2.0,
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

              // --- Form Fields ---

              _buildInputLabel(AppLocalizations.of(context)!.fullNameLabel),
              const SizedBox(height: 4),
              _buildTextField(
                controller: _nameController,
                focusNode: _nameFocus,
                hint: AppLocalizations.of(context)!.fullNameHint,
                icon: LucideIcons.user,
              ),
              const SizedBox(height: 16),

              _buildInputLabel(AppLocalizations.of(context)!.phoneNumberOptionalLabel),
              const SizedBox(height: 4),
              _buildTextField(
                controller: _phoneController,
                focusNode: _phoneFocus,
                hint: AppLocalizations.of(context)!.phoneNumberHint,
                icon: LucideIcons.phone,
                inputType: TextInputType.phone,
              ),
              const SizedBox(height: 16),

              _buildInputLabel(AppLocalizations.of(context)!.usernameEnglishOnlyLabel),
              const SizedBox(height: 4),
              _buildTextField(
                controller: _usernameController,
                focusNode: _userFocus,
                hint: AppLocalizations.of(context)!.usernameHint,
                icon: LucideIcons.atSign,
              ),
              const SizedBox(height: 16),

              _buildInputLabel(AppLocalizations.of(context)!.passwordLabel),
              const SizedBox(height: 4),
              _buildTextField(
                controller: _passwordController,
                focusNode: _passFocus,
                hint: "••••••",
                icon: LucideIcons.lock,
                isPassword: true,
              ),
              const SizedBox(height: 16),

              _buildInputLabel(AppLocalizations.of(context)!.confirmPasswordLabel),
              const SizedBox(height: 4),
              _buildTextField(
                controller: _confirmPasswordController,
                focusNode: _confirmPassFocus,
                hint: "••••••",
                icon: LucideIcons.lock,
                isPassword: true,
              ),
              const SizedBox(height: 32),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleRegister,
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
                              AppLocalizations.of(context)!.createAccount,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(width: 12),
                            DirectionalFlip(child: Icon(LucideIcons.arrowRight, size: 18)),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 32),

              // Footer
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.alreadyHaveAccount,
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const LoginScreen()),
                        );
                      },
                      child: Text(
                        AppLocalizations.of(context)!.signIn,
                        style: TextStyle(
                          color: AppColors.accentYellow,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.accentYellow,
                        ),
                      ),
                    ),
                  ],
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
    bool isPassword = false,
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
        obscureText: isPassword,
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
