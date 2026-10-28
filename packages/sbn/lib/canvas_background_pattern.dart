enum CanvasBackgroundPattern(
  /// The pattern name used for serialization.
  /// Do not display this to the user: instead use [localizedName].
  final String name, {

  /// Whether this pattern has elements along the page edges that may need to be
  /// clipped.
  final bool requiresClipping = false,
}) {
  /// No background pattern
  none(''),

  /// College ruled paper (ltr): horizontal lines with one
  /// vertical line along the left margin
  collegeLtr('college'),

  /// College ruled paper (rtl): horizontal lines with one
  /// vertical line along the right margin
  collegeRtl('college-rtl'),

  /// Horizontal lines. This is the same as college ruled paper
  /// but without the vertical line
  lined('lined'),

  /// A grid of squares
  grid('grid', requiresClipping: true),

  /// A grid of dots. This is the same as "grid" except it has dots on the
  /// corners instead of the whole square border.
  dots('dots', requiresClipping: true),

  /// Music staffs
  staffs('staffs'),

  /// Music tablature
  ///
  /// Like staffs but with 6 lines instead of 5 (and 5 spaces instead of 4).
  tablature('tablature'),

  /// Cornell notes
  cornell('cornell'),

  /// Horizontal lines with wider spacing than [lined]
  wideRuled('wide-ruled'),

  /// Horizontal lines with narrower spacing than [lined]
  narrowRuled('narrow-ruled'),

  /// A grid of larger squares than [grid]
  largeGrid('large-grid', requiresClipping: true),

  /// A grid of smaller squares than [grid]
  smallGrid('small-grid', requiresClipping: true),

  /// A grid of dots with wider spacing than [dots]
  largeDots('large-dots', requiresClipping: true),

  /// A grid of dots with narrower spacing than [dots]
  smallDots('small-dots', requiresClipping: true),

  /// A grid of dots with alternating rows offset by half a spacing
  /// (isometric style)
  isometricDots('isometric-dots', requiresClipping: true),

  /// French Seyes ruling: grid squares with an extra horizontal
  /// interline through each square
  seyesRuled('seyes-ruled', requiresClipping: true),

  /// Plus-sign crosses at grid intersections instead of full lines
  crossGrid('cross-grid', requiresClipping: true),

  /// Dashed horizontal lines
  dashedLines('dashed-lines'),

  /// Horizontal lines with a checkbox square at the left margin
  /// of each line
  checklist('checklist');

  static CanvasBackgroundPattern fromName(String? name) {
    return values.firstWhere(
      (pattern) => pattern.name == name,
      orElse: () => CanvasBackgroundPattern.none,
    );
  }
}
