package com.sherdor.wallpapers

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.WallpaperManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "wallpaper.channel/setter"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val worldWallpaper by lazy { WorldWallpaperController(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createPushChannel()
    }

    /**
     * One engine for the whole process. On Android 12+ a new wallpaper changes the
     * system colours and the activity is recreated; with its own engine it lost the
     * Dart state and the reply to setWallpaper.
     */
    override fun provideFlutterEngine(context: Context): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        return cache.get(ENGINE_ID)
            ?: FlutterEngine(context.applicationContext).also { cache.put(ENGINE_ID, it) }
    }

    override fun onDestroy() {
        super.onDestroy()
        if (isFinishing) {
            FlutterEngineCache.getInstance().get(ENGINE_ID)?.destroy()
            FlutterEngineCache.getInstance().remove(ENGINE_ID)
        }
    }

    /** FCM's default channel (see the manifest). High importance lets a push drop down over the screen. */
    private fun createPushChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            getString(R.string.push_channel_id),
            getString(R.string.push_channel_name),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply { description = getString(R.string.push_channel_description) }
        getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setWallpaper" -> handleSetWallpaper(call, result)
                    "saveImageToGallery" -> handleSaveToGallery(call, result)
                    "setLiveWallpaper" -> handleSetLiveWallpaper(call, result)
                    "setWorldWallpaper" -> worldWallpaper.open(call, result)
                    "needsGalleryPermission" -> result.success(Build.VERSION.SDK_INT < 29)
                    "isEmulator" -> result.success(isEmulator())
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Used by the system live wallpaper preview")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == WorldWallpaperController.REQUEST) worldWallpaper.onResult(resultCode)
    }

    private fun handleSetWallpaper(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val screen = call.argument<String>("screen")
        if (path.isNullOrEmpty()) {
            result.error("ARG_ERROR", "path is null", null)
            return
        }

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

    private fun handleSetLiveWallpaper(call: MethodCall, result: MethodChannel.Result) {
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

    /** Copies the image into Pictures/Wallpapers. Below Android 10 the Dart side asks for storage first. */
    private fun handleSaveToGallery(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrEmpty()) {
            result.error("ARG_ERROR", "path is null", null)
            return
        }

        Thread {
            val resolver = applicationContext.contentResolver
            var uri: Uri? = null
            try {
                val src = File(path)
                val (extension, mime) = when (src.extension.lowercase()) {
                    "png" -> "png" to "image/png"
                    "webp" -> "webp" to "image/webp"
                    else -> "jpg" to "image/jpeg"
                }
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, "wallpaper_${System.currentTimeMillis()}.$extension")
                    put(MediaStore.Images.Media.MIME_TYPE, mime)
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

                val target = resolver.insert(collection, values)
                    ?: throw IllegalStateException("MediaStore insert failed")
                uri = target
                val out = resolver.openOutputStream(target)
                    ?: throw IllegalStateException("MediaStore stream failed")
                out.use { src.inputStream().use { input -> input.copyTo(it) } }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    values.clear()
                    values.put(MediaStore.Images.Media.IS_PENDING, 0)
                    resolver.update(target, values, null, null)
                }

                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                // Leave no half-written entry in the gallery.
                uri?.let { runCatching { resolver.delete(it, null, null) } }
                mainHandler.post { result.error("SAVE_FAIL", e.message, null) }
            }
        }.start()
    }

    private fun applyBitmap(wm: WallpaperManager, bmp: Bitmap, screen: String?) {
        when (screen) {
            "home" -> wm.setBitmap(bmp, null, true, WallpaperManager.FLAG_SYSTEM)
            "lock" -> wm.setBitmap(bmp, null, true, WallpaperManager.FLAG_LOCK)
            else -> {
                // Two calls, not one with both flags: the lock screen keeps its
                // own copy, so a later home-only apply leaves it alone.
                wm.setBitmap(bmp, null, true, WallpaperManager.FLAG_SYSTEM)
                wm.setBitmap(bmp, null, true, WallpaperManager.FLAG_LOCK)
            }
        }
    }

    /** Decodes at the smallest power-of-two size that still covers the screen, so 4K cannot run out of memory. */
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
        var sampleSize = 1
        if (reqW <= 0 || reqH <= 0) return sampleSize
        while (options.outWidth / (sampleSize * 2) >= reqW &&
            options.outHeight / (sampleSize * 2) >= reqH
        ) {
            sampleSize *= 2
        }
        return sampleSize
    }

    // Asked only by debug builds: AdService shows stand-ins on an emulator.
    private fun isEmulator(): Boolean {
        val fp = Build.FINGERPRINT.lowercase()
        val hw = Build.HARDWARE.lowercase()
        val model = Build.MODEL.lowercase()
        return fp.startsWith("generic") || fp.contains("emulator") ||
            hw.contains("goldfish") || hw.contains("ranchu") ||
            model.contains("emulator") || model.contains("android sdk built for") ||
            Build.PRODUCT.lowercase().contains("sdk_gphone")
    }

    private companion object {
        const val ENGINE_ID = "main"
    }
}
