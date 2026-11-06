import 'package:flutter/painting.dart';

import 'models.dart';
import 'widgets/collage_layout.dart';
import 'widgets/instant_print.dart';
import 'widgets/page_texture.dart';

/// A built-in background picture for 拍立得拼貼 (`assets/backdrops/`).
class SceneBackdrop {
  final String id, label;
  const SceneBackdrop(this.id, this.label);

  String get asset => 'assets/backdrops/$id.jpg';

  /// Small enough for the pickers' thumbnails.
  ImageProvider get thumb => ResizeImage(AssetImage(asset), width: 200);
}

/// The background pictures, in the 背景 tab's order. Drafts keep the id.
const sceneBackdrops = [
  SceneBackdrop('rainbow_sky', '彩虹天空'),
  SceneBackdrop('cream_paper', '奶油紙'),
  SceneBackdrop('school_hallway', '校園走廊'),
  SceneBackdrop('pastel_paper', '粉彩紙'),
  SceneBackdrop('wildflowers', '野花'),
  SceneBackdrop('window_light', '窗邊'),
  SceneBackdrop('town_street', '小鎮街道'),
];

SceneBackdrop? sceneBackdrop(String? id) => sceneBackdrops.where((s) => s.id == id).firstOrNull;

/// A ready-made 拍立得拼貼: a background picture, where the prints lie and
/// on which film, the paper bits around them and the look over the page.
/// The user's photos go into it; everything stays movable.
class CollageTemplate {
  final String name, backdrop;
  /// One per print: where it lies on a 9:16 page.
  final List<PrintPlace> places;
  final List<FilmStock> films;
  final List<String> captions;
  final List<StickerData> stickers;
  final PageTexture texture;
  final double strength;
  const CollageTemplate({required this.name, required this.backdrop, required this.places, required this.films,
    required this.captions, this.stickers = const [], this.texture = PageTexture.none, this.strength = .6});

  SceneBackdrop get scene => sceneBackdrop(backdrop)!;
}

PrintPlace _at(double x, double y, double width, double angle) => (center: Offset(x, y), width: width, angle: angle);

StickerData _deco(String id, double x, double y, double scale, double rotation) =>
    StickerData(sticker: id, center: Offset(x, y), scale: scale, rotation: rotation);

const _w = FilmStock.white, _b = FilmStock.black;

/// The templates, all 9:16 (a phone's story).
final collageTemplates = [
  CollageTemplate(
    name: '彩虹天空', backdrop: 'rainbow_sky',
    places: [_at(.32, .25, .44, -.08), _at(.68, .5, .44, .06), _at(.33, .765, .44, -.04)],
    films: [_w, _w, _w], captions: ['sunny day', '彩虹出現了', 'with you ♡'],
    stickers: [_deco('deco:tag:3', .74, .2, 1.1, .15), _deco('deco:note:0', .78, .84, .9, .1)],
    texture: PageTexture.warm, strength: .35,
  ),
  CollageTemplate(
    name: '奶油紙', backdrop: 'cream_paper',
    places: [_at(.28, .27, .42, -.05), _at(.72, .31, .42, .05), _at(.29, .64, .42, .04), _at(.71, .68, .42, -.06)],
    films: [_w, FilmStock.stars, _w, FilmStock.smile], captions: ['今天的我們', 'good day', '小確幸', '♡'],
    stickers: [_deco('deco:torn:0', .5, .08, 1.6, -.05), _deco('deco:note:1', .8, .9, .85, -.08)],
    texture: PageTexture.paper, strength: .5,
  ),
  CollageTemplate(
    name: '校園走廊', backdrop: 'school_hallway',
    places: [_at(.62, .26, .44, .03), _at(.33, .5, .44, -.04), _at(.67, .75, .44, .02)],
    films: [_w, _w, _w], captions: ['放學後', 'best friends', '青春 ♡'],
    stickers: [_deco('deco:torn:0', .84, .17, 1.2, 1.45), _deco('deco:note:1', .17, .64, .75, -.12), _deco('deco:gridTape:2', .2, .4, 1.1, -.5)],
    texture: PageTexture.grain, strength: .55,
  ),
  CollageTemplate(
    name: '粉彩紙', backdrop: 'pastel_paper',
    places: [_at(.33, .24, .44, -.07), _at(.69, .4, .44, .06), _at(.31, .6, .44, -.05), _at(.67, .78, .44, .07)],
    films: [FilmStock.stars, _w, FilmStock.stars, _w], captions: ['dreamy', '粉紅泡泡', 'sweet', '♡'],
    stickers: [_deco('deco:tag:0', .76, .1, 1, .2), _deco('deco:note:3', .2, .88, .8, .08)],
  ),
  CollageTemplate(
    name: '野花', backdrop: 'wildflowers',
    places: [_at(.38, .33, .56, -.06), _at(.62, .68, .56, .05)],
    films: [_b, _b], captions: ['花開的季節', 'slow days'],
    stickers: [_deco('deco:torn:1', .78, .12, 1.2, .1), _deco('deco:tag:5', .24, .9, 1, -.1)],
    texture: PageTexture.faded, strength: .55,
  ),
  CollageTemplate(
    name: '窗邊', backdrop: 'window_light',
    places: [_at(.42, .32, .6, -.03), _at(.58, .7, .6, .04)],
    films: [_b, _w], captions: ['在路上', 'golden hour'],
    stickers: [_deco('deco:note:5', .82, .1, .8, .12)],
    texture: PageTexture.leak, strength: .55,
  ),
  CollageTemplate(
    name: '小鎮街道', backdrop: 'town_street',
    places: [_at(.3, .42, .44, -.06), _at(.7, .58, .44, .05), _at(.34, .78, .44, .03)],
    films: [_w, _w, _w], captions: ['旅行日記', '散步中', 'see you'],
    stickers: [_deco('deco:tag:3', .74, .3, 1.1, .12), _deco('deco:stripeTape:3', .6, .93, 1.2, -.08)],
    texture: PageTexture.grain, strength: .4,
  ),
];
