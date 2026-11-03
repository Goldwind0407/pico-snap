import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

const cream = Color(0xFFFFFAF4);
const paperCard = Color(0xFFF8F2EA);
const ink = Color(0xFF4A3632);
const outline = Color(0xFF5E4843);
const muted = Color(0xFFAA9891);
const coral = Color(0xFFF47C6E);
const line = Color(0xFFEDE2D7);

const blush = Color(0xFFFFDCD8);
const blushLine = Color(0xFFF0AAA3);
const lilac = Color(0xFFEADFF5);
const lilacLine = Color(0xFFCDB8E6);
const butter = Color(0xFFFFF0C2);
const butterLine = Color(0xFFE9D28C);
const sage = Color(0xFFC6D4BB);
const sky = Color(0xFFC8DDEA);

/// Handwritten accent text.
TextStyle hand(double size, {Color color = ink}) =>
    TextStyle(fontFamily: 'Caveat', fontSize: size, color: color, fontWeight: FontWeight.w600, height: 1.1);

void showSoonToast(BuildContext context, String feature) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
  content: Text('$feature：即將推出，敬請期待 ♡'),
  behavior: SnackBarBehavior.floating,
  backgroundColor: ink,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
));

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
