import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:saber/components/settings/settings_row.dart';
import 'package:saber/components/theming/uni_icon.dart';
import 'package:saber/pages/home/settings.dart';
import 'package:stow/stow.dart';

class SettingsSwitch extends StatefulWidget {
  const new({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconBuilder,
    required this.pref,
    this.afterChange,
  }) : assert(
         icon == null || iconBuilder == null,
         'Cannot set both icon and iconBuilder',
       );

  final String title;
  final String? subtitle;
  final Object? icon;
  final Object? Function(bool)? iconBuilder;

  final Stow<dynamic, bool, dynamic> pref;
  final ValueChanged<bool>? afterChange;

  @override
  State<SettingsSwitch> createState() => _SettingsSwitchState();
}

class _SettingsSwitchState extends State<SettingsSwitch> {
  @override
  void initState() {
    widget.pref.addListener(onChanged);
    super.initState();
  }

  void onChanged() {
    widget.afterChange?.call(widget.pref.value);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    var icon = widget.icon;
    icon ??= widget.iconBuilder?.call(widget.pref.value);
    icon ??= Icons.settings;

    final colorScheme = ColorScheme.of(context);

    return SettingsRow(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.pref.value = !widget.pref.value,
        onLongPress: () {
          SettingsPage.showResetDialog(
            context: context,
            pref: widget.pref,
            prefTitle: widget.title,
          );
        },
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 100),
              child: UniIcon(icon, key: ValueKey(icon)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                mainAxisSize: .min,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontStyle:
                          widget.pref.value != widget.pref.defaultValue
                          ? FontStyle.italic
                          : null,
                    ),
                  ),
                  if (widget.subtitle != null &&
                      widget.subtitle!.isNotEmpty)
                    Text(
                      widget.subtitle!,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            CupertinoSwitch(
              value: widget.pref.value,
              onChanged: (bool value) {
                widget.pref.value = value;
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.pref.removeListener(onChanged);
    super.dispose();
  }
}
