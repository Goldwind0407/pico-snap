import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

const cream = Color(0xFFFBF8F3);
const paperCard = Color(0xFFF2ECE4);
const ink = Color(0xFF3E322E);
const outline = Color(0xFF5E4843);
const muted = Color(0xFF806E65);
const coral = Color(0xFFF47C6E);
const actionCoral = Color(0xFFB45446);
const line = Color(0xFFE8DFD5);

const blush = Color(0xFFFFDCD8);
const blushLine = Color(0xFFF0AAA3);
const lilac = Color(0xFFEADFF5);
const lilacLine = Color(0xFFCDB8E6);
const butter = Color(0xFFFFF0C2);
const butterLine = Color(0xFFE9D28C);
const sage = Color(0xFFC6D4BB);
const sky = Color(0xFFC8DDEA);
const appFontFallback = ['PingFang TC', 'Microsoft JhengHei', 'Noto Sans TC'];

/// Shared UI surfaces and type. Photo artwork keeps its own frame styling.
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: actionCoral).copyWith(
    primary: actionCoral, onPrimary: Colors.white,
    secondary: const Color(0xFF60715D), surface: cream, onSurface: ink,
    onSurfaceVariant: muted, outline: muted, outlineVariant: line,
    surfaceContainerHighest: paperCard,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: 'Nunito',
    fontFamilyFallback: appFontFallback);
  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  return base.copyWith(
    scaffoldBackgroundColor: cream,
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink).copyWith(
      headlineSmall: base.textTheme.headlineSmall?.copyWith(fontSize: 25, height: 1.25, fontWeight: FontWeight.w800, color: ink),
      titleLarge: base.textTheme.titleLarge?.copyWith(fontSize: 21, height: 1.3, fontWeight: FontWeight.w800, color: ink),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.4, color: ink),
    ),
    appBarTheme: const AppBarTheme(backgroundColor: cream, foregroundColor: ink,
      elevation: 0, scrolledUnderElevation: 0, centerTitle: false),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      backgroundColor: actionCoral, foregroundColor: Colors.white, elevation: 0,
      minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      textStyle: const TextStyle(fontFamily: 'Nunito', fontFamilyFallback: appFontFallback, fontSize: 14, fontWeight: FontWeight.w800), shape: buttonShape)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      foregroundColor: ink, minimumSize: const Size(44, 44), side: const BorderSide(color: line), shape: buttonShape)),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: actionCoral,
      textStyle: const TextStyle(fontFamily: 'Nunito', fontFamilyFallback: appFontFallback, fontWeight: FontWeight.w800), shape: buttonShape)),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: ink,
      minimumSize: const Size(44, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent, modalBarrierColor: Color(0x663E322E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      clipBehavior: Clip.antiAlias),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: Colors.white, hintStyle: const TextStyle(color: muted, fontWeight: FontWeight.w500),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: actionCoral, width: 1.5))),
    dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 24),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: actionCoral, linearTrackColor: paperCard),
    sliderTheme: base.sliderTheme.copyWith(activeTrackColor: actionCoral, thumbColor: actionCoral,
      inactiveTrackColor: line, overlayColor: coral.withValues(alpha: .12), trackHeight: 3),
    chipTheme: base.chipTheme.copyWith(backgroundColor: Colors.white, selectedColor: blush,
      side: const BorderSide(color: line), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: ink,
      elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    tooltipTheme: TooltipThemeData(decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(10)),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12)),
  );
}

BoxDecoration studioSurface({double radius = 24, Color color = Colors.white}) => BoxDecoration(
  color: color, borderRadius: BorderRadius.circular(radius), border: Border.all(color: line),
  boxShadow: const [BoxShadow(color: Color(0x073E322E), blurRadius: 22, offset: Offset(0, 8))],
);

/// Handwritten accent text.
/// Handwriting: Caveat, and 辰宇落雁體 for Chinese.
TextStyle hand(double size, {Color color = ink}) =>
    TextStyle(fontFamily: 'Caveat', fontFamilyFallback: const ['ChenYuluoyan'], fontSize: size, color: color, fontWeight: FontWeight.w600, height: 1.1);

/// Asks before deleting something; true when the user confirms.
Future<bool> confirmDelete(BuildContext context, String title, String message, {String delete = '刪除'}) async =>
    await showGlassDialog<bool>(context, (context) => GlassDialog(
      title: title, message: message,
      actions: [
        GlassAction('取消', () => Navigator.pop(context, false)),
        GlassAction(delete, () => Navigator.pop(context, true), danger: true),
      ],
    )) ==
    true;

/// A short floating message at the bottom of the screen; [above] lifts it
/// over controls it would otherwise cover.
void showMessage(BuildContext context, String text, {bool error = false, double above = 0}) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
  content: Text(text),
  behavior: SnackBarBehavior.floating,
  margin: EdgeInsets.fromLTRB(16, 0, 16, 16 + above),
  backgroundColor: error ? const Color(0xFFB4483C) : ink,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
));

/// Asks before leaving a page with unsaved work; true when the user leaves.
Future<bool> confirmLeave(BuildContext context, String message, {String stay = '繼續編輯'}) async =>
    await showGlassDialog<bool>(context, (context) => GlassDialog(
      title: '要離開嗎？', message: message,
      actions: [
        GlassAction(stay, () => Navigator.pop(context, false)),
        GlassAction('離開', () => Navigator.pop(context, true), danger: true),
      ],
    )) ==
    true;

/// Shows [builder]'s dialog over a dimmed screen, growing in a touch.
Future<T?> showGlassDialog<T>(BuildContext context, WidgetBuilder builder) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: true,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierColor: Colors.black.withValues(alpha: .38),
  transitionDuration: const Duration(milliseconds: 200),
  pageBuilder: (context, _, __) => builder(context),
  transitionBuilder: (context, animation, _, child) {
    final t = Curves.easeOutCubic.transform(animation.value);
    return Opacity(opacity: animation.value, child: Transform.scale(scale: .94 + .06 * t, child: child));
  },
);

/// A button in a [GlassDialog]; [danger] ones (delete, leave) are red.
class GlassAction {
  final String label;
  final VoidCallback onTap;
  final bool danger;
  const GlassAction(this.label, this.onTap, {this.danger = false});
}

/// Frosted glass: the screen shows through blurred and darkened, a big
/// rounded card with a fine light edge, white title, grey message and pill
/// buttons side by side. [child] goes between the message and the buttons.
class GlassDialog extends StatelessWidget {
  final String title;
  final String? message;
  final Widget? child;
  final List<GlassAction> actions;
  const GlassDialog({super.key, required this.title, this.message, this.child, required this.actions});

  static const danger = Color(0xFFFF8A8A);
  static const subtle = Color(0xB3FFFFFF);

  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 28),
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Material(
      type: MaterialType.transparency,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
            decoration: BoxDecoration(
              color: const Color(0xFF5A524D).withValues(alpha: .78),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: Colors.white.withValues(alpha: .22)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 19, height: 1.3, color: Colors.white, fontWeight: FontWeight.w800)),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(message!, style: const TextStyle(fontSize: 15, height: 1.45, color: subtle, fontWeight: FontWeight.w600)),
              ],
              if (child != null) ...[const SizedBox(height: 16), child!],
              const SizedBox(height: 22),
              Row(children: [
                for (final (i, a) in actions.indexed) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: _pill(a)),
                ],
              ]),
            ]),
          ),
        ),
      ),
    )),
  ));

  Widget _pill(GlassAction a) => Material(
    color: Colors.white.withValues(alpha: .14),
    shape: const StadiumBorder(),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: a.onTap,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        child: Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 16, color: a.danger ? danger : Colors.white, fontWeight: FontWeight.w800)),
      ),
    ),
  );
}

/// Buttons and controls at most [maxWidth] wide, centred: on a wide screen
/// (a foldable opened, a tablet) they don't stretch from edge to edge.
class Narrow extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const Narrow({super.key, required this.child, this.maxWidth = 560});

  @override
  Widget build(BuildContext context) => Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child));
}
