import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../theme.dart';

/// Consistent page hierarchy for the user's collections.
class StudioHeader extends StatelessWidget {
  final String title, eyebrow, subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;
  final EdgeInsets padding;
  const StudioHeader({super.key, required this.title, required this.eyebrow,
    required this.subtitle, this.onBack, this.trailing, this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 18)});

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(eyebrow, style: const TextStyle(fontSize: 10, letterSpacing: 2.2, color: actionCoral, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Row(children: [
        if (onBack != null) ...[
          IconButton(tooltip: '返回', onPressed: onBack, icon: const Icon(CupertinoIcons.back)),
          const SizedBox(width: 4),
        ],
        Expanded(child: Text(title, style: const TextStyle(fontSize: 26, height: 1.25, color: ink, fontWeight: FontWeight.w800))),
        if (trailing != null) trailing!,
      ]),
      const SizedBox(height: 8),
      Text(subtitle, style: const TextStyle(fontSize: 12, height: 1.5, color: muted)),
    ]),
  );
}

/// A small tactile response shared by cards and navigation; keyboard and
/// accessibility activation still use InkWell's normal button semantics.
class StudioPress extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final bool? selected;
  const StudioPress({super.key, required this.child, required this.onTap, this.radius = 20, this.selected});

  @override
  State<StudioPress> createState() => _StudioPressState();
}

class _StudioPressState extends State<StudioPress> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => Semantics(selected: widget.selected, child: AnimatedScale(
    scale: _pressed && widget.onTap != null ? .975 : 1,
    duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 120),
    curve: Curves.easeOutCubic,
    child: Material(color: Colors.transparent, child: InkWell(
      onTap: widget.onTap,
      onHighlightChanged: (value) { if (mounted) setState(() => _pressed = value); },
      borderRadius: BorderRadius.circular(widget.radius),
      splashColor: coral.withValues(alpha: .08), highlightColor: Colors.transparent,
      child: widget.child,
    )),
  ));
}
