import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'models.dart';
import 'widgets/collage_layout.dart';
import 'widgets/doodle.dart';
import 'widgets/frames.dart';
import 'widgets/instant_print.dart';

/// A complete edit checkpoint. Photo bytes are immutable and shared; growing
/// pen paths are copied so later drawing cannot mutate undo or saved drafts.
class EditorDocument {
  final EditorMode mode;
  final List<Uint8List?> photos;
  final List<PhotoFit> fits;
  final List<FilmStock> films;
  final List<String> filters, captions;
  final List<StickerData> stickers;
  final List<Stroke> strokes;
  final List<List<Stroke>> handwriting;
  final Uint8List? subject;
  final String templateKey, bubble;
  final String? stripCaption;
  final int format, pattern, backdrop;
  /// 拍立得拼貼: how many prints show, and how they lie.
  final int count;
  final CollageArrangement arrangement;

  /// Photo windows a piece of [mode] keeps: a collage holds up to six prints.
  static int cellsOf(EditorMode mode) => switch (mode) {
        EditorMode.sticker => 1,
        EditorMode.fourCut => 4,
        EditorMode.polaroid => 6,
      };

  /// Captions a collage's prints start with.
  static const collageCaptions = ['good day', '今天好開心', 'sunny!', '我們 ♡', 'little joy', '小確幸'];

  /// Lists from before collages held six prints, filled up with defaults.
  static List<T> _pad<T>(List<T> list, int length, T Function(int) fill) =>
      [...list.take(length), for (var i = list.length; i < length; i++) fill(i)];

  EditorDocument(
      {required this.mode,
      required List<Uint8List?> photos,
      required List<PhotoFit> fits,
      required List<FilmStock> films,
      required List<String> filters,
      required List<String> captions,
      required List<StickerData> stickers,
      required List<Stroke> strokes,
      required List<List<Stroke>> handwriting,
      required this.templateKey,
      required this.format,
      required this.pattern,
      required this.backdrop,
      required this.bubble,
      this.stripCaption,
      this.subject,
      this.count = 4,
      this.arrangement = CollageArrangement.scatter})
      : photos = List.unmodifiable(_pad(photos, cellsOf(mode), (_) => null)),
        fits = List.unmodifiable(_pad(fits, cellsOf(mode), (_) => const PhotoFit())),
        films = List.unmodifiable(_pad(films, max(4, cellsOf(mode)), (_) => FilmStock.white)),
        filters = List.unmodifiable(_pad(filters, cellsOf(mode), (_) => '')),
        captions = List.unmodifiable(_pad(captions, max(4, cellsOf(mode)), (i) => collageCaptions[i])),
        stickers = List.unmodifiable(stickers),
        strokes = copyStrokes(strokes),
        handwriting = [for (final lines in handwriting) copyStrokes(lines)];

  /// A fresh four-cuts piece with these photos, as the editor starts one
  /// (its starting caption, pattern and backdrop).
  factory EditorDocument.start(EditorMode mode, {required List<Uint8List> photos, required List<String> filters, int template = 0}) => EditorDocument(
        mode: mode,
        photos: [for (var i = 0; i < 4; i++) i < photos.length ? photos[i] : null],
        fits: List.filled(4, const PhotoFit()),
        films: List.filled(4, FilmStock.white),
        filters: [for (var i = 0; i < 4; i++) i < filters.length ? filters[i] : ''], // '': the first filter
        captions: collageCaptions,
        stickers: const [],
        strokes: const [],
        handwriting: const [],
        templateKey: keyForTemplate(template),
        format: 3,
        pattern: 0,
        backdrop: 1,
        bubble: 'DREAM',
      );

  static List<Stroke> copyStrokes(List<Stroke> strokes) => [
        for (final s in strokes)
          Stroke(
              points: List.of(s.points),
              color: s.color,
              width: s.width,
              style: s.style)
      ];

  static String keyForTemplate(int index) => index < stripTemplates.length
      ? 'builtin:${stripTemplates[index].name}'
      : 'custom:${customTemplates[index - stripTemplates.length].id}';

  int get templateIndex {
    final builtin =
        stripTemplates.indexWhere((t) => 'builtin:${t.name}' == templateKey);
    if (builtin >= 0) return builtin;
    final custom =
        customTemplates.indexWhere((t) => 'custom:${t.id}' == templateKey);
    return custom < 0 ? 0 : stripTemplates.length + custom;
  }

  static Map<String, Object?> _stroke(Stroke s) => {
        'points': [
          for (final p in s.points) [p.dx, p.dy]
        ],
        'color': s.color.toARGB32(),
        'width': s.width,
        'style': s.style.name,
      };

  /// Binary assets live alongside this JSON, and are only written once.
  Map<String, Object?> toJson(List<String?> photoFiles, String? subjectFile) =>
      {
        'version': 1,
        'mode': mode.name,
        'photos': photoFiles,
        'subject': subjectFile,
        'fits': [
          for (final f in fits) [f.scale, f.align.x, f.align.y]
        ],
        'films': [for (final f in films) f.name],
        'filters': filters,
        'captions': captions,
        'template': templateKey,
        'format': format,
        'pattern': pattern,
        'backdrop': backdrop,
        'count': count,
        'arrangement': arrangement.name,
        'bubble': bubble,
        'stripCaption': stripCaption,
        'stickers': [
          for (final s in stickers)
            {
              'sticker': s.sticker,
              'x': s.center.dx,
              'y': s.center.dy,
              'scale': s.scale,
              'rotation': s.rotation,
              'flipped': s.flipped,
            }
        ],
        'strokes': strokes.map(_stroke).toList(),
        'handwriting': [
          for (final lines in handwriting) lines.map(_stroke).toList()
        ],
      };

  factory EditorDocument.fromJson(
      Map<String, dynamic> json, List<Uint8List?> photos, Uint8List? subject) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported draft version');
    }
    final mode = EditorMode.values.byName(json['mode'] as String);
    // A collage from before six prints has four of everything.
    final cells = EditorDocument.cellsOf(mode);
    final ok = {cells, if (mode == EditorMode.polaroid) 4};
    final perPrint = {max(4, cells), 4};
    if (!ok.contains(photos.length) ||
        !ok.contains((json['fits'] as List).length) ||
        !ok.contains((json['filters'] as List).length) ||
        !perPrint.contains((json['films'] as List).length) ||
        !perPrint.contains((json['captions'] as List).length)) {
      throw const FormatException('Invalid draft cells');
    }
    List<Stroke> lines(List values) => [
          for (final raw in values)
            Stroke(
                points: [
                  for (final p in raw['points'] as List)
                    Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())
                ],
                color: Color(raw['color'] as int),
                width: (raw['width'] as num).toDouble(),
                style: PenStyle.values.byName(raw['style'] as String))
        ];
    return EditorDocument(
      mode: mode,
      photos: photos,
      subject: subject,
      fits: [
        for (final f in json['fits'] as List)
          PhotoFit((f[0] as num).toDouble(),
              Alignment((f[1] as num).toDouble(), (f[2] as num).toDouble()))
      ],
      films: [
        for (final f in json['films'] as List)
          FilmStock.values.byName(f as String)
      ],
      filters: (json['filters'] as List).cast<String>(),
      captions: (json['captions'] as List).cast<String>(),
      templateKey: json['template'] as String,
      format: (json['format'] as int).clamp(0, formats.length - 1),
      pattern: (json['pattern'] as int).clamp(0, ginghamPatterns.length - 1),
      backdrop: (json['backdrop'] as int).clamp(0, backdrops.length - 1),
      count: ((json['count'] as int?) ?? 4).clamp(1, cells),
      arrangement: CollageArrangement.values.asNameMap()[json['arrangement']] ?? CollageArrangement.scatter,
      bubble: json['bubble'] as String,
      stripCaption: json['stripCaption'] as String?,
      stickers: [
        for (final s in json['stickers'] as List)
          StickerData(
              sticker: s['sticker'] as String,
              center: Offset(
                  (s['x'] as num).toDouble(), (s['y'] as num).toDouble()),
              scale: (s['scale'] as num).toDouble(),
              rotation: (s['rotation'] as num).toDouble(),
              flipped: s['flipped'] as bool)
      ],
      strokes: lines(json['strokes'] as List),
      handwriting: [
        for (final s in json['handwriting'] as List) lines(s as List)
      ],
    );
  }
}
