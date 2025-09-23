package com.example.sherdorapp.wallpaper_app_first

import android.app.WallpaperManager
import android.graphics.BitmapFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "wallpaper.channel/setter"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setWallpaper" -> {
                        val path = call.argument<String>("path")
                        val screen = call.argument<String>("screen") // "home" | "lock" | "both"
                        if (path.isNullOrEmpty()) {
                            result.error("ARG_ERROR", "path is null", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val bmp = BitmapFactory.decodeFile(File(path).absolutePath)
                            val wm = WallpaperManager.getInstance(applicationContext)
                            when (screen) {
                                "home" -> wm.setBitmap(bmp, null, true, WallpaperManager.FLAG_SYSTEM)
                                "lock" -> wm.setBitmap(bmp, null, true, WallpaperManager.FLAG_LOCK)
                                else -> {
                                    wm.setBitmap(bmp) // ikkalasiga ham urinish
                                    try { wm.setBitmap(bmp, null, true, WallpaperManager.FLAG_LOCK) } catch (_: Exception) {}
                                }
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SET_FAIL", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
