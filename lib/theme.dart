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
  content: Text('$feature：介面原型，功能之後再接入'),
  behavior: SnackBarBehavior.floating,
  backgroundColor: ink,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
));

/// Asks before deleting something; true when the user confirms.
Future<bool> confirmDelete(BuildContext context, String title, String message) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cream,
        title: Text(title, style: const TextStyle(fontSize: 18, color: ink, fontWeight: FontWeight.w900)),
        content: Text(message, style: const TextStyle(color: ink)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消', style: TextStyle(color: muted))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('刪除', style: TextStyle(color: coral, fontWeight: FontWeight.w800))),
        ],
      ),
    ) ==
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
