import 'package:flutter/material.dart';

import '../filters.dart';
import '../lut_files.dart';
import '../theme.dart';
import 'studio_chrome.dart';

/// Every filter as a small preview of [image], so you see the look before
/// picking it.
class FilterThumbs extends StatelessWidget {
  final ImageProvider image;
  final String selected;
  final ValueChanged<PhotoFilter> onPick;
  final EdgeInsets padding;
  const FilterThumbs({super.key, required this.image, required this.selected, required this.onPick, this.padding = const EdgeInsets.symmetric(horizontal: 16)});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: LutFiles.changes,
    builder: (_, version, child) => ListView.separated(
    scrollDirection: Axis.horizontal,
    padding: padding,
    itemCount: photoFilters.length,
    separatorBuilder: (_, __) => const SizedBox(width: 8),
    itemBuilder: (_, i) {
      final f = photoFilters[i];
      final on = f.id == selected;
      return StudioPress(
        onTap: () => onPick(f),
        selected: on, radius: 14,
        child: SizedBox(width: 68, child: Column(children: [
          AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 180),
            width: 64, height: 64,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: on ? actionCoral : line, width: on ? 2 : 1)),
            padding: const EdgeInsets.all(2),
            child: ClipRRect(borderRadius: BorderRadius.circular(9), child: FilterEffects(filter: f, child: Image(image: filtered(image, f, maxSide: 180), fit: BoxFit.cover, width: 60, height: 60, gaplessPlayback: true))),
          ),
          const SizedBox(height: 4),
          Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: on ? actionCoral : muted, fontWeight: on ? FontWeight.w800 : FontWeight.w500)),
        ])),
      );
    },
  ));
}
