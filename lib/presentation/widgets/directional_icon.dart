import 'package:flutter/material.dart';

/// Mirrors [child] horizontally whenever the ambient [Directionality] is
/// right-to-left (e.g. Arabic).
///
/// Several icons in this app — back arrows, forward arrows, and chevrons —
/// are drawn pointing in a fixed physical direction (e.g. "←"). Those icons
/// need to visually flip in an RTL layout so a "back" arrow still points
/// toward the start of the reading direction (→ in Arabic) instead of
/// always pointing left regardless of locale.
///
/// Usage:
/// ```dart
/// DirectionalFlip(
///   child: Icon(LucideIcons.arrowLeft, color: AppColors.accentYellow, size: 20),
/// )
/// ```
class DirectionalFlip extends StatelessWidget {
  final Widget child;

  const DirectionalFlip({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return Transform.flip(flipX: isRtl, child: child);
  }
}
