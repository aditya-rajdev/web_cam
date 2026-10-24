package com.example.untitled3

import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.phonecam/camera"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForegroundService" -> {
                    val intent = Intent(this, StreamingForegroundService::class.java).apply {
                        action = StreamingForegroundService.ACTION_START
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopForegroundService" -> {
                    val intent = Intent(this, StreamingForegroundService::class.java).apply {
                        action = StreamingForegroundService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(true)
                }
                "openDeveloperSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val intent = Intent(Settings.ACTION_SETTINGS)
                            startActivity(intent)
                            result.success(true)
                        } catch (e2: Exception) {
                            result.error("INTENT_FAILED", "Could not open settings", null)
                        }
                    }
                }
                "compressYuvToJpeg" -> {
                    val yPlane = call.argument<ByteArray>("yPlane")
                    val uPlane = call.argument<ByteArray>("uPlane")
                    val vPlane = call.argument<ByteArray>("vPlane")
                    val yRowStride = call.argument<Int>("yRowStride") ?: 0
                    val uvRowStride = call.argument<Int>("uvRowStride") ?: 0
                    val uvPixelStride = call.argument<Int>("uvPixelStride") ?: 0
                    val width = call.argument<Int>("width") ?: 0
                    val height = call.argument<Int>("height") ?: 0
                    val quality = call.argument<Int>("quality") ?: 80

                    if (yPlane != null && uPlane != null && vPlane != null) {
                        val jpegBytes = YuvToJpegConverter.convertYuvToJpeg(
                            yPlane, uPlane, vPlane, yRowStride, uvRowStride, uvPixelStride, width, height, quality
                        )
                        if (jpegBytes != null) {
                            result.success(jpegBytes)
                        } else {
                            result.error("CONVERSION_FAILED", "YUV to JPEG conversion failed", null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "Missing YUV plane arguments", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
