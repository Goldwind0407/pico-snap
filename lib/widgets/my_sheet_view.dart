import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';
import 'frames.dart';
import 'sticker_motion.dart';

/// One of the user's sticker sheets drawn like the generated ones: grey
/// backing paper with the stickers laid out on it. [onTap] gets the sticker
/// tapped; [selected] stickers get a coral ring.
class MySheetView extends StatelessWidget {
  final MySheet sheet;
  final ValueChanged<String>? onTap, onLongPress;
  final Set<String> selected;
  final bool peelOnTap;
  /// Stickers per row.
  final int columns;
  const MySheetView({super.key, required this.sheet, this.onTap, this.onLongPress, this.selected = const {}, this.columns = 4, this.peelOnTap = false});

  static const paper = Color(0xFF9E9E9E);

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: paper,
      borderRadius: BorderRadius.circular(10),
      boxShadow: [BoxShadow(color: ink.withValues(alpha: .18), blurRadius: 10, offset: const Offset(0, 4))],
    ),
    padding: const EdgeInsets.all(10),
    child: sheet.stickers.isEmpty
      ? const SizedBox(height: 70, child: Center(child: Text('還沒有貼紙', style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w700))))
      : GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: columns, mainAxisSpacing: 6, crossAxisSpacing: 6,
          children: [
            for (final id in sheet.stickers)
              if (peelOnTap && onTap != null)
                PeelableSticker(
                  key: ValueKey(id),
                  onPick: () => onTap!(id),
                  child: Padding(padding: const EdgeInsets.all(6.5), child: FittedBox(child: StickerVisual(id, size: 96))),
                )
              else GestureDetector(
                onTap: onTap == null ? null : () => onTap!(id),
                onLongPress: onLongPress == null ? null : () => onLongPress!(id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: selected.contains(id) ? Colors.white.withValues(alpha: .28) : Colors.transparent,
                    border: Border.all(color: selected.contains(id) ? coral : Colors.transparent, width: 2.5),
                  ),
                  child: Stack(children: [
                    Positioned.fill(child: FittedBox(child: StickerVisual(id, size: 96))),
                    if (selected.contains(id))
                      const Positioned(right: 0, top: 0, child: Icon(CupertinoIcons.checkmark_circle_fill, color: coral, size: 20)),
                  ]),
                ),
              ),
          ],
        ),
  );
}
