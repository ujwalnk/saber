# Samsung Notes (One UI) Design Spec for Saber Clone

Reference: `~/workspace/notes-apk/web/src/styles.css` (dark-mode-first Samsung Notes clone).
Target: Samsung Galaxy Tab S6 Lite. Dark theme is primary; keep light theme working.

## Design tokens

### Colors (dark)
- App background: `#000000`
- Sidebar/drawer: `#3A3A3C`
- Selected pill / selection: `#4E4E50`
- Panels/dialogs: `#2D2D2F`
- Toolbar: `#252525`
- Text primary: `#FFFFFF`, secondary `#9A9A9A`, icons `#E8E8E8`
- Separators: `#3F3F41`
- Accent (existing brand): orange `0xFFFF6B35` — keep for FAB/selection highlights where the
  reference uses red `#FF3B30`. Use orange sparingly: FAB icon, active pen indicator, slider fills.
- Gold for pen-panel selection ring: `#C7B022` (optional; orange also fine)

### Colors (light)
- App background: `#F6F6F6`
- Sidebar: `#EAEAEA`, pill `#DFDFDF`, text `#404040`
- Toolbar: `#F2F2F4`, selected tool `#E2E2E4`

### Shape
- Sidebar container: rounded on the outer-right side only — `BorderRadius.only(
  topRight: Radius.circular(24), bottomRight: Radius.circular(24))`
- Nav items: full-width rows, `BorderRadius.circular(12)`
- Note cards: thumbnail `BorderRadius.circular(18)`, soft shadow
- Floating panels (pen/color/size/selection): `BorderRadius.circular(20)`, elevation/shadow
- Dialogs: `BorderRadius.circular(20)`
- Toolbar buttons: circles (`BorderRadius.circular(32)`), 48x48
- Settings rows: `BorderRadius.circular(14)`, 14px padding, 8px vertical gap
- Toggles: iOS-style (52x30, 15px radius)

### Typography
- Library title: 30px, bold, left aligned
- Sidebar header: 19px, bold
- Editor title: 19px, bold
- Card title: 14px, semibold, centered; card date 12px gray centered
- Section headers (settings): 13px, gray, semibold

### Spacing
- Sidebar: 300px expanded / 76px rail; 14px outer padding, 12px inner; item gap 2px;
  item padding 11px vertical / 14px horizontal
- Card grid: 18px row gap / 14px column gap; bottom padding 110px (room for FAB)
- FAB: 62px circle, 22px right / 26px bottom margins

## Component specs

### 1. Sidebar (`vertical_navbar.dart`)
- Container: sidebar color, rounded right corners (24px), NO left rounding, NO border.
- Header "Notes" 19px bold at top (already present — keep).
- Nav items: full-width InkWell rows: icon (24px) + 14px gap + label (15px) + optional count (13px gray).
  Selected: pill background `#4E4E50` + bold label. Unselected: transparent.
  Corner radius 12px. Vertical padding 11px, horizontal 14px. Gap between items 2px.
- Keep the expand/collapse chevron behavior and the FileTree below.
- Rail (collapsed) mode: 76px wide, icons centered, hide labels.

### 2. Home library (`recent_notes.dart`, `browse.dart`, note preview cards)
- Title "Notes" 30px bold at top-left of content area.
- Cards: grid with 18/14 gaps. Each card: thumbnail with 18px radius + subtle shadow,
  title 14px semibold centered below, date 12px gray centered below title.
- Keep all existing interactions (tap to open, long-press menus, selection mode).
- FAB: keep position; make it 62px circle. Icon stays orange.

### 3. Editor (`editor.dart` top bar, `toolbar.dart`)
- Top bar: flat (no elevation), title 19px bold, 44px circular icon buttons.
- Bottom toolbar: floating rounded bar. Reference uses a LEFT vertical toolbar (62px wide,
  `#252525`, tools are 48px circles, selected tool gets `#4E4E50` circle). Saber currently
  uses a bottom toolbar — convert it to a floating rounded-bottom bar:
  `BorderRadius.circular(24)`, margin 12px from edges, toolbar color, subtle shadow,
  48px circular tool buttons with 8px gaps, selected = pill circle.
- Keep EVERY tool: pen, pencil, highlighter, eraser, lasso/select, laser, text, shapes,
  image, undo, redo, zoom controls. Nothing may be removed or hidden behind extra taps
  beyond what Saber already does.

### 4. Floating panels (`pen_modal.dart`, `color_bar.dart`, `size_picker.dart`,
    `selection_bar.dart`, `export_bar.dart`, `editor_bottom_sheet.dart`)
- All panels: `BorderRadius.circular(20)`, panel color `#2D2D2F`, shadow
  `BoxShadow(color: black54, blurRadius: 22, offset: (0, 6))`, padding 10-14px.
- Pen panel: rows of pen-type buttons (40x56, 10px radius); selected pen gets
  2px orange ring. Size slider with orange fill. Color dots: 26-34px circles,
  selected = white border ring.
- Selection bar: pill with 14px radius, text buttons 13px, 9-12px padding.
- Export/settings sheets: 20px top radius when bottom sheet.

### 5. Settings (`settings.dart`)
- Section headers: 13px gray semibold, 14px horizontal margins.
- Rows: sidebar-color background, 14px radius, 14px padding, 8px gaps, 15px text.
- Toggles: iOS-style switch.

## Rules
- NEVER remove or hide a Saber feature. Every tool, menu item, and setting stays reachable.
- Keep all existing behavior/animations; only change colors, shapes, spacing, typography.
- Dark theme is the priority; light theme must not break (use Theme.of(context) colors).
- After editing, run `flutter analyze` on changed files and fix all errors (warnings ok).
- Do NOT change package names, app id, file paths, or any non-UI logic.
