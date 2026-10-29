import 'package:flutter/material.dart';

/// Samsung Notes-style floating panel container:
/// rounded corners, dark panel color, soft drop shadow.
class SamsungPanel extends StatelessWidget {
  const new({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 20,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// Corner radius, defaults to 20 (selection bar uses 14).
  final double borderRadius;

  /// Panel background color: a tinted surface from the app's color scheme.
  static Color panelColorOf(BuildContext context) {
    return ColorScheme.of(context).surfaceContainerHigh;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SamsungPanel.panelColorOf(context),
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 22,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}
