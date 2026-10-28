import 'package:flutter/material.dart';

/// Samsung Notes-style settings row container:
/// sidebar-colored background, 14px radius, 14px padding, 8px vertical gaps.
class SettingsRow extends StatelessWidget {
  const new({super.key, required this.child});

  final Widget child;

  /// Row background color, theme-aware.
  static Color rowColorOf(BuildContext context) {
    return Theme.brightnessOf(context) == .dark
        ? const Color(0xFF3A3A3C)
        : const Color(0xFFEAEAEA);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const .all(14),
        decoration: BoxDecoration(
          color: SettingsRow.rowColorOf(context),
          borderRadius: .circular(14),
        ),
        child: child,
      ),
    );
  }
}
