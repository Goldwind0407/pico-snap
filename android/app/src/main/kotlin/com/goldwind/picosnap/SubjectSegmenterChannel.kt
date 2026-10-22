package com.goldwind.picosnap

import android.content.Context
import android.graphics.Bitmap
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import kotlin.math.roundToInt

/**
 * 去背的第一步：用 ML Kit 主體分割（Google Play 服務裡的模型，免費、離線，
 * 人、動物、物品都切得出來）找出照片裡的前景。
 *
 * Dart 那邊（lib/cutout/subject_segmenter.dart）送來 RGBA 像素，這裡回傳
 * 每個像素是前景的信心（0~255，寬×高）；沒有前景、模型還沒下載好、或出錯回 null，
 * Dart 那邊就退回 GrabCut。
 */
object SubjectSegmenterChannel {
    fun register(messenger: BinaryMessenger, context: Context) {
        val segmenter = SubjectSegmentation.getClient(
            SubjectSegmenterOptions.Builder()
                .enableForegroundConfidenceMask()
                .build()
        )
        MethodChannel(messenger, "picosnap/subject").setMethodCallHandler { call, result ->
            if (call.method != "foreground") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            // 沒有 Google Play 服務（例如中國販售的手機）的話，ML Kit 的請求不會
            // 失敗、而是一直卡著，要空等到 Dart 那邊逾時。先檢查，沒有就馬上說不能用。
            if (GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(context)
                != ConnectionResult.SUCCESS
            ) {
                result.success(null)
                return@setMethodCallHandler
            }
            val rgba = call.argument<ByteArray>("rgba")
            val w = call.argument<Int>("width")
            val h = call.argument<Int>("height")
            if (rgba == null || w == null || h == null || rgba.size != w * h * 4) {
                result.success(null)
                return@setMethodCallHandler
            }
            val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            // ARGB_8888 在記憶體裡就是 R、G、B、A 的順序，可以直接拷
            bitmap.copyPixelsFromBuffer(ByteBuffer.wrap(rgba))
            segmenter.process(InputImage.fromBitmap(bitmap, 0))
                .addOnSuccessListener { r ->
                    val fg = r.foregroundConfidenceMask
                    if (fg == null) {
                        result.success(null)
                        return@addOnSuccessListener
                    }
                    fg.rewind()
                    val out = ByteArray(w * h)
                    var i = 0
                    while (i < out.size && fg.hasRemaining()) {
                        out[i] = (fg.get().coerceIn(0f, 1f) * 255f).roundToInt().toByte()
                        i++
                    }
                    result.success(out)
                }
                .addOnFailureListener { result.success(null) }
        }
    }
}
