package com.sherdor.wallpapers

import android.app.WallpaperManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.math.max

class MainActivity : FlutterActivity() {
    private val CHANNEL = "wallpaper.channel/setter"
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setWallpaper" -> handleSetWallpaper(call, result)
                    "saveImageToGallery" -> handleSaveToGallery(call, result)
                    "setLiveWallpaper" -> handleSetLiveWallpaper(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleSetWallpaper(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        val path = call.argument<String>("path")
        val screen = call.argument<String>("screen") // "home" | "lock" | "both"
        if (path.isNullOrEmpty()) {
            result.error("ARG_ERROR", "path is null", null)
            return
        }

        // Optimizatsiya: og'ir ish (4K dekod + setBitmap) UI ip'ida emas, fonda bajariladi.
        Thread {
            try {
                val metrics = resources.displayMetrics
                val bmp = decodeSampledBitmap(path, metrics.widthPixels, metrics.heightPixels)
                    ?: throw IllegalStateException("Bitmap decode failed")

                val wm = WallpaperManager.getInstance(applicationContext)
                applyBitmap(wm, bmp, screen)
                bmp.recycle()

                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post { result.error("SET_FAIL", e.message, null) }
            }
        }.start()
    }

    /**
     * Jonli wallpaper: yuklab olingan video yo'lini saqlaydi va tizimning
     * live-wallpaper preview'ini ochadi (foydalanuvchi u yerda "Set wallpaper" bosadi).
     */
    private fun handleSetLiveWallpaper(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        val path = call.argument<String>("path")
        if (path.isNullOrEmpty() || !File(path).exists()) {
            result.error("ARG_ERROR", "video path is missing", null)
            return
        }
        getSharedPreferences(LiveWallpaperService.PREFS, MODE_PRIVATE)
            .edit()
            .putString(LiveWallpaperService.KEY_VIDEO_PATH, path)
            .apply()
        try {
            val intent = Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER).apply {
                putExtra(
                    WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT,
                    ComponentName(this@MainActivity, LiveWallpaperService::class.java),
                )
            }
            startActivity(intent)
            result.success(true)
        } catch (e: Exception) {
            result.error("PICKER_FAIL", e.message, null)
        }
    }

    /**
     * Yuklab olingan rasmni qurilma galereyasiga (Pictures/Wallpapers) saqlaydi.
     * Android 10+ (API 29+) da MediaStore RELATIVE_PATH ishlatiladi — runtime ruxsat
     * shart emas. Og'ir I/O fonda bajariladi.
     */
    private fun handleSaveToGallery(
        call: io.flutter.plugin.common.MethodCall,
        result: MethodChannel.Result,
    ) {
        val path = call.argument<String>("path")
        if (path.isNullOrEmpty()) {
            result.error("ARG_ERROR", "path is null", null)
            return
        }

        Thread {
            try {
                val src = File(path)
                val name = "wallpaper_${System.currentTimeMillis()}.jpg"
                val resolver = applicationContext.contentResolver

                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, name)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        put(
                            MediaStore.Images.Media.RELATIVE_PATH,
                            "${Environment.DIRECTORY_PICTURES}/Wallpapers",
                        )
                        put(MediaStore.Images.Media.IS_PENDING, 1)
                    }
                }

                val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                } else {
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                }

                val uri = resolver.insert(collection, values)
                    ?: throw IllegalStateException("MediaStore insert failed")
                resolver.openOutputStream(uri).use { out ->
                    src.inputStream().use { input -> input.copyTo(out!!) }
                }

                // Android 10+ da faylni "tayyor" deb belgilash.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    values.clear()
                    values.put(MediaStore.Images.Media.IS_PENDING, 0)
                    resolver.update(uri, values, null, null)
                }

                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post { result.error("SAVE_FAIL", e.message, null) }
            }
        }.start()
    }

    private fun applyBitmap(wm: WallpaperManager, bmp: Bitmap, screen: String?) {
        // FLAG_SYSTEM / FLAG_LOCK API 24+ da ishlaydi. Eski versiyalarda oddiy setBitmap.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            when (screen) {
                "home" -> wm.setBitmap(bmp, null, true, WallpaperManager.FLAG_SYSTEM)
                "lock" -> wm.setBitmap(bmp, null, true, WallpaperManager.FLAG_LOCK)
                else -> {
                    wm.setBitmap(bmp, null, true, WallpaperManager.FLAG_SYSTEM)
                    wm.setBitmap(bmp, null, true, WallpaperManager.FLAG_LOCK)
                }
            }
        } else {
            wm.setBitmap(bmp)
        }
    }

    /**
     * Rasmni xotirani tejagan holda dekod qiladi: avval faqat o'lchamini o'qiydi,
     * keyin ekranga mos `inSampleSize` bilan kichraytirib yuklaydi. Bu 4K rasmlarda
     * OutOfMemory'ning oldini oladi.
     */
    private fun decodeSampledBitmap(path: String, reqWidth: Int, reqHeight: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)

        val options = BitmapFactory.Options().apply {
            inSampleSize = calculateInSampleSize(bounds, reqWidth, reqHeight)
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        return BitmapFactory.decodeFile(path, options)
    }

    private fun calculateInSampleSize(options: BitmapFactory.Options, reqW: Int, reqH: Int): Int {
        val height = options.outHeight
        val width = options.outWidth
        var inSampleSize = 1
        if (reqW <= 0 || reqH <= 0) return inSampleSize
        if (height > reqH || width > reqW) {
            val halfH = height / 2
            val halfW = width / 2
            while ((halfH / inSampleSize) >= reqH && (halfW / inSampleSize) >= reqW) {
                inSampleSize *= 2
            }
        }
        return max(1, inSampleSize)
    }
}
