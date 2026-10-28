import 'package:flutter/material.dart';

/// Samsung Notes-style settings section header:
/// 13px gray semibold with 14px horizontal margins.
class SettingsSubtitle extends StatelessWidget {
  const new({super.key, required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Padding(
      padding: const .only(top: 14, left: 14, right: 14, bottom: 4),
      child: Text(
        subtitle,
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 13,
          fontWeight: .w600,
        ),
      ),
    );
  }
}
