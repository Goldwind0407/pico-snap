package com.goldwind.picosnap

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 去背用的主體分割（ML Kit）
        SubjectSegmenterChannel.register(flutterEngine.dartExecutor.binaryMessenger, applicationContext)
        // 縮時影片編碼
        VideoEncoderChannel.register(flutterEngine.dartExecutor.binaryMessenger)
    }
}
