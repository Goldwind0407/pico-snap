package com.goldwind.picosnap

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 縮時影片：把一張張 PNG 畫格用手機內建的 H.264 編碼器做成 MP4。
 *
 * Dart 那邊（lib/services/timelapse_recorder.dart）送來畫格路徑（同一張重複
 * 送就是停在那一格）、fps、寬高、輸出路徑；做好回傳輸出路徑，失敗回錯誤。
 */
object VideoEncoderChannel {
    private const val TIMEOUT_US = 10_000L

    fun register(messenger: BinaryMessenger) {
        val main = Handler(Looper.getMainLooper())
        MethodChannel(messenger, "picosnap/video").setMethodCallHandler { call, result ->
            if (call.method != "encode") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val frames = call.argument<List<String>>("frames")
            val out = call.argument<String>("out")
            val fps = call.argument<Int>("fps") ?: 12
            val w = call.argument<Int>("width")
            val h = call.argument<Int>("height")
            if (frames.isNullOrEmpty() || out == null || w == null || h == null) {
                result.error("args", "缺少參數", null)
                return@setMethodCallHandler
            }
            Thread {
                try {
                    encode(frames, out, fps, w, h)
                    main.post { result.success(out) }
                } catch (e: Exception) {
                    File(out).delete()
                    main.post { result.error("encode", e.toString(), null) }
                }
            }.start()
        }
    }

    private fun encode(frames: List<String>, out: String, fps: Int, w: Int, h: Int) {
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, w, h).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
            setInteger(MediaFormat.KEY_BIT_RATE, 4_000_000)
            setInteger(MediaFormat.KEY_FRAME_RATE, fps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }
        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        val muxer = MediaMuxer(out, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        var track = -1
        val info = MediaCodec.BufferInfo()

        /** 把編好的資料寫進 MP4。[end] 時一直等到編碼器說結束。 */
        fun drain(end: Boolean) {
            var idle = 0
            while (true) {
                val index = codec.dequeueOutputBuffer(info, TIMEOUT_US)
                when {
                    index == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                        if (!end) return
                        if (++idle > 500) throw IllegalStateException("編碼器沒有回應")
                    }
                    index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        track = muxer.addTrack(codec.outputFormat)
                        muxer.start()
                    }
                    index >= 0 -> {
                        val buffer = codec.getOutputBuffer(index)!!
                        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                        if (info.size > 0 && track >= 0) {
                            buffer.position(info.offset)
                            buffer.limit(info.offset + info.size)
                            muxer.writeSampleData(track, buffer, info)
                        }
                        codec.releaseOutputBuffer(index, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                    }
                }
            }
        }

        fun nextInput(): Int {
            while (true) {
                val index = codec.dequeueInputBuffer(TIMEOUT_US)
                if (index >= 0) return index
                drain(false)
            }
        }

        try {
            codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            codec.start()
            val argb = IntArray(w * h)
            var loaded: String? = null
            for ((i, path) in frames.withIndex()) {
                // 同一張重複出現（最後停住的成品）就不用重新讀
                if (path != loaded) {
                    val decoded = BitmapFactory.decodeFile(path) ?: throw IllegalArgumentException("讀不到畫格 $path")
                    val bitmap = if (decoded.width == w && decoded.height == h) decoded
                        else Bitmap.createScaledBitmap(decoded, w, h, true)
                    bitmap.getPixels(argb, 0, w, 0, 0, w, h)
                    loaded = path
                }
                val index = nextInput()
                fillYuv(codec.getInputImage(index)!!, argb, w, h)
                codec.queueInputBuffer(index, 0, w * h * 3 / 2, i * 1_000_000L / fps, 0)
                drain(false)
            }
            codec.queueInputBuffer(nextInput(), 0, 0, frames.size * 1_000_000L / fps, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
            drain(true)
        } finally {
            codec.stop()
            codec.release()
            if (track >= 0) muxer.stop()
            muxer.release()
        }
    }

    /** ARGB 像素轉成編碼器要的 YUV 4:2:0（BT.601），照各平面的間距寫。 */
    private fun fillYuv(image: Image, argb: IntArray, w: Int, h: Int) {
        val (yPlane, uPlane, vPlane) = image.planes
        val yBuf = yPlane.buffer
        for (row in 0 until h) {
            val base = row * yPlane.rowStride
            for (col in 0 until w) {
                val c = argb[row * w + col]
                val r = (c shr 16) and 0xFF
                val g = (c shr 8) and 0xFF
                val b = c and 0xFF
                yBuf.put(base + col * yPlane.pixelStride, (((66 * r + 129 * g + 25 * b + 128) shr 8) + 16).toByte())
            }
        }
        val uBuf = uPlane.buffer
        val vBuf = vPlane.buffer
        for (row in 0 until h / 2) {
            for (col in 0 until w / 2) {
                val c = argb[(row * 2) * w + col * 2]
                val r = (c shr 16) and 0xFF
                val g = (c shr 8) and 0xFF
                val b = c and 0xFF
                uBuf.put(row * uPlane.rowStride + col * uPlane.pixelStride, (((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128).toByte())
                vBuf.put(row * vPlane.rowStride + col * vPlane.pixelStride, (((112 * r - 94 * g - 18 * b + 128) shr 8) + 128).toByte())
            }
        }
    }
}
