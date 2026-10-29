import 'package:flutter/material.dart';

import '../filters.dart';
import '../theme.dart';

/// Every filter as a small preview of [image], so you see the look before
/// picking it.
class FilterThumbs extends StatelessWidget {
  final ImageProvider image;
  final String selected;
  final ValueChanged<PhotoFilter> onPick;
  final EdgeInsets padding;
  const FilterThumbs({super.key, required this.image, required this.selected, required this.onPick, this.padding = const EdgeInsets.symmetric(horizontal: 16)});

  @override
  Widget build(BuildContext context) => ListView.separated(
    scrollDirection: Axis.horizontal,
    padding: padding,
    itemCount: photoFilters.length,
    separatorBuilder: (_, __) => const SizedBox(width: 8),
    itemBuilder: (_, i) {
      final f = photoFilters[i];
      final on = f.id == selected;
      return GestureDetector(
        onTap: () => onPick(f),
        child: Column(children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: on ? coral : Colors.transparent, width: 2.5)),
            padding: const EdgeInsets.all(2),
            child: ClipRRect(borderRadius: BorderRadius.circular(9), child: FilterEffects(filter: f, child: Image(image: filtered(image, f, maxSide: 180), fit: BoxFit.cover, width: 60, height: 60, gaplessPlayback: true))),
          ),
          const SizedBox(height: 4),
          Text(f.name, style: TextStyle(fontSize: 11, color: on ? ink : muted, fontWeight: on ? FontWeight.w900 : FontWeight.w600)),
        ]),
      );
    },
  );
}
