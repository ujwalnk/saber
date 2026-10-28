import 'package:saber/i18n/strings.g.dart';
import 'package:sbn/canvas_background_pattern.dart';

extension CanvasBackgroundPatternLocalized on CanvasBackgroundPattern {
  String get localizedName => switch (this) {
    .none => t.editor.menu.bgPatterns.none,
    .collegeLtr => t.editor.menu.bgPatterns.college,
    .collegeRtl => t.editor.menu.bgPatterns.collegeRtl,
    .lined => t.editor.menu.bgPatterns.lined,
    .grid => t.editor.menu.bgPatterns.grid,
    .dots => t.editor.menu.bgPatterns.dots,
    .staffs => t.editor.menu.bgPatterns.staffs,
    .tablature => t.editor.menu.bgPatterns.tablature,
    .cornell => t.editor.menu.bgPatterns.cornell,
    .wideRuled => t.editor.menu.bgPatterns.wideRuled,
    .narrowRuled => t.editor.menu.bgPatterns.narrowRuled,
    .largeGrid => t.editor.menu.bgPatterns.largeGrid,
    .smallGrid => t.editor.menu.bgPatterns.smallGrid,
    .largeDots => t.editor.menu.bgPatterns.largeDots,
    .smallDots => t.editor.menu.bgPatterns.smallDots,
    .isometricDots => t.editor.menu.bgPatterns.isometricDots,
    .seyesRuled => t.editor.menu.bgPatterns.seyesRuled,
    .crossGrid => t.editor.menu.bgPatterns.crossGrid,
    .dashedLines => t.editor.menu.bgPatterns.dashedLines,
    .checklist => t.editor.menu.bgPatterns.checklist,
  };
}
