import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:gal/gal.dart';

/// 把做好的作品存到手機相簿。
///
/// Flutter 沒有內建寫入系統相簿的 API，一定要靠外掛（這裡用 gal），
/// 它會處理 Android 各版本（13 以上走 MediaStore 不用權限、以下要
/// WRITE_EXTERNAL_STORAGE）與 iOS 相簿權限的差異。
class PhotoSaveService {
  PhotoSaveService._();

  static const _album = 'PICO SNAP';

  /// 把 [key] 那個 RepaintBoundary 裡畫的東西存進相簿，最長邊大約
  /// [longSide] 像素。透明的地方補成 [background]，不然相簿裡會變成黑色。
  /// 那個東西一定要整個在畫面上，被切掉的部分截不到。
  /// 成功回傳 null，失敗回傳可以直接顯示給使用者的訊息。
  static Future<String?> saveBoundary(
    GlobalKey key, {
    double longSide = 3000,
    Color background = const Color(0xFFFFFFFF),
  }) async {
    if (kIsWeb) return '網頁版不能存到相簿，請用手機 App';
    final ui.Image shot;
    try {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final size = boundary.size;
      final ratio = (longSide / (size.width > size.height ? size.width : size.height)).clamp(1.0, 12.0);
      shot = await boundary.toImage(pixelRatio: ratio);
    } catch (e) {
      debugPrint('[SAVE] 截圖失敗: $e');
      return '產生圖片失敗，請再試一次';
    }
    final recorder = ui.PictureRecorder();
    final w = shot.width.toDouble(), h = shot.height.toDouble();
    ui.Canvas(recorder)
      ..drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = background)
      ..drawImage(shot, Offset.zero, Paint());
    final flat = await recorder.endRecording().toImage(shot.width, shot.height);
    shot.dispose();
    final data = await flat.toByteData(format: ui.ImageByteFormat.png);
    flat.dispose();
    if (data == null) return '產生圖片失敗，請再試一次';
    return saveBytes(data.buffer.asUint8List());
  }

  /// 成功回傳 null，失敗回傳可以直接顯示給使用者的訊息。
  static Future<String?> saveBytes(Uint8List bytes) async {
    try {
      final denied = await _ensureAccess();
      if (denied != null) return denied;
      await Gal.putImageBytes(bytes, album: _album);
      return null;
    } on GalException catch (e) {
      return _message(e);
    } catch (e) {
      debugPrint('[SAVE] 存圖片失敗: $e');
      return '存到相簿失敗：$e';
    }
  }

  /// 沒有相簿權限就先要一次。Android 13+ 通常直接回 true。
  /// 有權限回傳 null，沒有的話回傳要顯示的訊息。
  static Future<String?> _ensureAccess() async {
    if (await Gal.hasAccess()) return null;
    final granted = await Gal.requestAccess();
    return granted ? null : '沒有相簿權限，請到系統設定開啟後再試';
  }

  static String _message(GalException e) {
    debugPrint('[SAVE] GalException: ${e.type}');
    switch (e.type) {
      case GalExceptionType.accessDenied:
        return '沒有相簿權限，請到系統設定開啟後再試';
      case GalExceptionType.notEnoughSpace:
        return '手機儲存空間不足';
      case GalExceptionType.notSupportedFormat:
        return '不支援的照片格式';
      default:
        return '存到相簿失敗，請再試一次';
    }
  }
}
