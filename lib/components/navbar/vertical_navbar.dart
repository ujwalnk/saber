import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:saber/components/files/file_tree.dart';
import 'package:saber/components/theming/adaptive_icon.dart';
import 'package:saber/data/routes.dart';

/// Samsung One UI style sidebar: #3A3A3C container with 24px rounding on the
/// right side only, full-width pill nav rows, 300px expanded / 76px rail.
class const VerticalNavbar({
  super.key,
  final int selectedIndex = 0,
  final ValueChanged<int>? onDestinationSelected,
}) extends HookWidget {
  static const _expandedWidth = 300.0;
  static const _railWidth = 76.0;

  @override
  Widget build(BuildContext context) {
    final expandAnimationController = useAnimationController(
      duration: const Duration(milliseconds: 200),
    );
    final expandAnimation = expandAnimationController.drive(
      CurveTween(curve: Curves.easeInOut),
    );

    final isFullyCollapsed = useListenableSelector(
      expandAnimation,
      () => expandAnimation.value <= 0,
    );
    final hasBeenExpanded = useRef(false);
    hasBeenExpanded.value |= !isFullyCollapsed;

    final theme = Theme.of(context);
    final isDark = theme.colorScheme.brightness == .dark;
    final sidebarColor = isDark
        ? const Color(0xFF3A3A3C)
        : const Color(0xFFEAEAEA);
    final labelColor = isDark ? Colors.white : const Color(0xFF404040);

    final routes = HomeRoutes.routes;

    return AnimatedBuilder(
      animation: expandAnimation,
      builder: (context, child) {
        final width =
            _railWidth + (_expandedWidth - _railWidth) * expandAnimation.value;
        return SizedBox(width: width, child: child);
      },
      child: Semantics(
        container: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: sidebarColor,
            borderRadius: const .only(
              topRight: .circular(24),
              bottomRight: .circular(24),
            ),
          ),
          child: Padding(
              padding: const .symmetric(horizontal: 12, vertical: 14),
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  const SizedBox(height: kToolbarHeight - 2),
                  Align(
                    alignment: isFullyCollapsed ? .center : .centerLeft,
                    child: TextButton(
                      onPressed: () {
                        if (expandAnimationController.isForwardOrCompleted) {
                          expandAnimationController.reverse();
                        } else {
                          expandAnimationController.forward();
                        }
                      },
                      child: RotationTransition(
                        turns: expandAnimation.drive(
                          Tween(begin: 0, end: 0.5),
                        ),
                        child: const AdaptiveIcon(
                          icon: Icons.chevron_right,
                          cupertinoIcon: CupertinoIcons.chevron_right,
                        ),
                      ),
                    ),
                  ),
                  // Samsung-style sidebar header
                  SizeTransition(
                    sizeFactor: expandAnimation,
                    axis: .horizontal,
                    child: Padding(
                      padding: const .directional(start: 8, bottom: 8),
                      child: Text(
                        'Notes',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: .bold,
                          color: labelColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Column(
                    crossAxisAlignment: .stretch,
                    spacing: 2,
                    children: [
                      for (int i = 0; i < routes.length; ++i)
                        _RouteTile(
                          route: routes[i],
                          selected: i == selectedIndex,
                          onTap: () => onDestinationSelected?.call(i),
                          expandAnimation: expandAnimation,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SizeTransition(
                      sizeFactor: expandAnimation.drive(
                        // Extra easing to hide FileTree loading
                        CurveTween(curve: Curves.easeIn),
                      ),
                      axis: .horizontal,
                      alignment: .topStart,
                      child: SizedBox(
                        width: _expandedWidth - 24,
                        child: hasBeenExpanded.value
                            ? Offstage(
                                offstage: isFullyCollapsed,
                                child: const FileTree(),
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }
}

class const _RouteTile({
  required final HomeRoute route,
  required final bool selected,
  required final VoidCallback onTap,
  required final Animation<double> expandAnimation,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.colorScheme.brightness == .dark;
    final pillColor = isDark
        ? const Color(0xFF4E4E50)
        : const Color(0xFFDFDFDF);
    final labelColor = isDark ? Colors.white : const Color(0xFF404040);
    final iconColor = isDark
        ? const Color(0xFFE8E8E8)
        : const Color(0xFF3A3A3C);

    return Semantics(
      label: route.destination.label,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: .circular(12),
          child: Ink(
            decoration: BoxDecoration(
              color: selected ? pillColor : Colors.transparent,
              borderRadius: .circular(12),
            ),
            child: Padding(
              padding: const .symmetric(vertical: 11, horizontal: 14),
              child: Row(
                children: [
                  IconTheme.merge(
                    data: IconThemeData(color: iconColor, size: 24),
                    child: route.destination.icon,
                  ),
                  ExcludeSemantics(
                    // semantics redundant with tile label above
                    child: SizeTransition(
                      sizeFactor: expandAnimation,
                      axis: .horizontal,
                      child: Padding(
                        padding: const .directional(start: 14),
                        child: Text(
                          route.destination.label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: selected ? .bold : .normal,
                            color: labelColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
