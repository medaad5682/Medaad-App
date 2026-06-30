import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // ✅ إضافة المكتبة اللازمة لـ TextInputFormatter
import '../../core/constants/app_colors.dart';

class CustomTextField extends StatefulWidget {
  final String label;
  final String hintText;
  final IconData prefixIcon;
  final bool isPassword;
  final TextEditingController controller;
  final int maxLines;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters; // ✅ تمت الإضافة
  final bool readOnly; // ✅ إضافة خاصية القراءة فقط

  const CustomTextField({
    super.key,
    required this.label,
    required this.hintText,
    required this.prefixIcon,
    this.isPassword = false,
    required this.controller,
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.inputFormatters, // ✅ تمت الإضافة إلى البناء
    this.readOnly = false, // ✅ إعطاء قيمة افتراضية false
  });

  @override
  State<CustomTextField> createState() => _CustomTextFieldState();
}

class _CustomTextFieldState extends State<CustomTextField> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
          child: Text(
            widget.label.toUpperCase(),
            // 🔥 تم إزالة const هنا لأن AppColors.accentYellow متغير
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              color: AppColors.accentYellow,
            ),
          ),
        ),
        
        // Input Container
        Container(
          decoration: BoxDecoration(
            color: widget.readOnly // ✅ تبهيت لون الخلفية قليلاً إذا كان الحقل للقراءة فقط
                ? AppColors.backgroundSecondary.withOpacity(0.5) 
                : AppColors.backgroundSecondary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isFocused 
                  ? AppColors.accentYellow.withOpacity(0.5) 
                  : Colors.white.withOpacity(0.05),
            ),
          ),
          child: TextFormField(
            controller: widget.controller,
            obscureText: widget.isPassword,
            maxLines: widget.maxLines,
            keyboardType: widget.keyboardType,
            validator: widget.validator,
            inputFormatters: widget.inputFormatters, // ✅ تمرير الخاصية هنا
            readOnly: widget.readOnly, // ✅ تمرير الخاصية هنا لمنع التعديل
            // 🔥 تم إزالة const هنا
            style: TextStyle(
              color: widget.readOnly // ✅ تبهيت لون النص للإشارة إلى عدم إمكانية التعديل
                  ? AppColors.textSecondary 
                  : AppColors.textPrimary, 
              fontSize: 14
            ),
            cursorColor: AppColors.accentYellow,
            
            onTap: () {
              // ✅ تفعيل التركيز (Focus) فقط إذا كان الحقل ليس للقراءة فقط
              if (!widget.readOnly) {
                setState(() => _isFocused = true);
              }
            },
            onTapOutside: (_) {
              setState(() => _isFocused = false);
              FocusScope.of(context).unfocus();
            },
            
            decoration: InputDecoration(
              hintText: widget.hintText,
              // 🔥 تم إزالة const هنا
              hintStyle: TextStyle(color: AppColors.textSecondary),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              prefixIcon: Icon(
                widget.prefixIcon,
                size: 18,
                color: widget.controller.text.isNotEmpty || _isFocused
                    ? AppColors.accentYellow 
                    : AppColors.textSecondary,
              ),
            ),
            onChanged: (val) => setState(() {}),
          ),
        ),
      ],
    );
  }
}
