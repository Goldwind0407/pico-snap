import 'package:flutter/material.dart';

import '../theme.dart';
import 'doodle.dart';

const _handColors = [ink, Colors.white, coral, Color(0xFFFF8FB1), Color(0xFF86BBD8), Color(0xFF8B5E3C)];

/// 細、粗：佔寫字區寬度的比例。
const _handWidths = [.012, .022];

/// A bottom sheet with a big copy of a print's bottom border to write on with
/// a finger. [aspect] is the border's width / height, [paper] its colour.
/// Returns the strokes when the user is done, null if they back out.
Future<List<Stroke>?> showHandwritingPad(BuildContext context, {
  required List<Stroke> initial, required double aspect, required Color paper, required Color pen,
}) => showModalBottomSheet<List<Stroke>>(
  context: context,
  isScrollControlled: true,
  backgroundColor: cream,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
  builder: (_) => _HandwritingPad(initial: initial, aspect: aspect, paper: paper, pen: pen),
);

class _HandwritingPad extends StatefulWidget {
  final List<Stroke> initial;
  final double aspect;
  final Color paper, pen;
  const _HandwritingPad({required this.initial, required this.aspect, required this.paper, required this.pen});

  @override
  State<_HandwritingPad> createState() => _HandwritingPadState();
}

class _HandwritingPadState extends State<_HandwritingPad> {
  late final _strokes = [...widget.initial];
  late Color _color = widget.pen;
  var _width = 0;
  var _version = 0;

  void _start(Offset at, Size size) => setState(() {
    _strokes.add(Stroke(points: [normalise(at, size)], color: _color, width: _handWidths[_width], style: PenStyle.pen));
    _version++;
  });

  void _move(Offset at, Size size) {
    final p = normalise(at, size), last = _strokes.last.points;
    if (((p - last.last).distance * size.width) < 1.2) return;
    setState(() {
      last.add(p);
      _version++;
    });
  }

  @override
  Widget build(BuildContext context) => SafeArea(child: Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('在相片下方手寫', style: TextStyle(fontSize: 18, color: ink, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      Text('用手指寫字或畫畫', style: hand(18, color: muted)),
      const SizedBox(height: 12),
      AspectRatio(
        aspectRatio: widget.aspect,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: widget.paper, borderRadius: BorderRadius.circular(6), border: Border.all(color: line, width: 1.4),
            boxShadow: [BoxShadow(color: ink.withValues(alpha: .08), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Stack(fit: StackFit.expand, children: [
            CustomPaint(painter: DoodlePainter(_strokes, _version)),
            DoodleInput(onStart: _start, onMove: _move, onEnd: () {}),
          ])),
        ),
      ),
      const SizedBox(height: 14),
      Row(children: [
        for (final c in _handColors)
          Padding(padding: const EdgeInsets.only(right: 8), child: GestureDetector(
            onTap: () => setState(() => _color = c),
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: c, shape: BoxShape.circle,
                border: Border.all(color: _color == c ? coral : line, width: _color == c ? 3 : 1.4),
              ),
            ),
          )),
        const Spacer(),
        for (final (i, label) in ['細', '粗'].indexed)
          Padding(padding: const EdgeInsets.only(left: 6), child: ChoiceChip(
            label: Text(label), selected: _width == i, onSelected: (_) => setState(() => _width = i),
            selectedColor: blush, showCheckmark: false,
          )),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        IconButton(
          tooltip: '復原', icon: const Icon(Icons.undo_rounded),
          onPressed: _strokes.isEmpty ? null : () => setState(() {
            _strokes.removeLast();
            _version++;
          }),
        ),
        TextButton(
          onPressed: _strokes.isEmpty ? null : () => setState(() {
            _strokes.clear();
            _version++;
          }),
          child: const Text('全部清掉'),
        ),
        const Spacer(),
        FilledButton(
          onPressed: () => Navigator.pop(context, _strokes),
          style: FilledButton.styleFrom(backgroundColor: coral, padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12)),
          child: const Text('寫好了', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      ]),
    ]),
  ));
}
