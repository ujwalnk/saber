import 'package:flutter/material.dart';
import 'package:saber/components/settings/settings_row.dart';

class SettingsButton extends StatelessWidget {
  const new({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.onPressed,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return SettingsRow(
      child: InkWell(
        borderRadius: .circular(14),
        onTap: onPressed,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: AnimatedSwitcher(
            duration: const Duration(milliseconds: 100),
            child: Icon(icon, key: ValueKey(icon)),
          ),
          title: Text(title, style: const TextStyle(fontSize: 15)),
          subtitle: subtitle != null && subtitle!.isNotEmpty
              ? Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
