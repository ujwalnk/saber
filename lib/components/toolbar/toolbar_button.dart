import 'package:flutter/material.dart';

/// Samsung Notes (One UI) style toolbar button: a 48x48 circle.
/// The selected tool gets a pill-colored circle; unselected tools are
/// transparent with a flat icon color. Adapts to light/dark via Theme.
class ToolbarIconButton extends StatelessWidget {
  const new({
    super.key,
    this.tooltip,
    this.selected = false,
    this.enabled = true,
    required this.onPressed,
    required this.padding,
    required this.child,
  });

  final String? tooltip;
  final bool selected;
  final bool enabled;
  final VoidCallback? onPressed;

  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final bool isDark = Theme.brightnessOf(context) == .dark;

    // One UI tokens: selected pill #4E4E50 (dark) / #E2E2E4 (light),
    // icon color #E8E8E8 (dark) / #3A3A3C (light).
    final Color selectedBg = isDark
        ? const Color(0xFF4E4E50)
        : const Color(0xFFE2E2E4);
    final Color iconColor = isDark
        ? const Color(0xFFE8E8E8)
        : const Color(0xFF3A3A3C);

    final buttonStyle = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return Colors.transparent;
        if (states.contains(WidgetState.selected)) return selectedBg;
        return Colors.transparent;
      }),
      iconColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colorScheme.onSurface.withValues(alpha: 0.4);
        }
        return iconColor;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colorScheme.onSurface.withValues(alpha: 0.4);
        }
        return iconColor;
      }),
      iconSize: const WidgetStatePropertyAll(20),
      fixedSize: const WidgetStatePropertyAll(Size(48, 48)),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const WidgetStatePropertyAll(CircleBorder()),
    );

    return Padding(
      padding: padding,
      child: IconButton(
        style: buttonStyle,
        onPressed: (enabled) ? onPressed : null,
        tooltip: tooltip,
        isSelected: selected,
        icon: child,
      ),
    );
  }
}
