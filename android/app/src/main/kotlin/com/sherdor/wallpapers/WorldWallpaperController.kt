package com.sherdor.wallpapers

import android.app.Activity
import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File

/** Staging is separate from the active world: cancelling the picker is a no-op. */
object WorldWallpaperStore {
    const val PREFS = "wavely_worlds"
    const val ACTIVE = "active"
    const val PENDING = "pending"

    fun finish(context: Context, accepted: Boolean) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val pending = prefs.getString(PENDING, null) ?: return
        val old = prefs.getString(ACTIVE, null)
        val editor = prefs.edit().remove(PENDING)
        if (accepted) editor.putString(ACTIVE, pending)
        if (!editor.commit()) throw IllegalStateException("Could not save wallpaper settings")
        val unused = if (accepted) old else pending
        if (unused != null && unused != prefs.getString(ACTIVE, null)) {
            runCatching { File(JSONObject(unused).getString("path")).delete() }
        }
    }
}

class WorldWallpaperController(private val activity: Activity) {
    companion object { const val REQUEST = 9472 }
    private var result: MethodChannel.Result? = null

    fun open(call: MethodCall, response: MethodChannel.Result) {
        if (result != null) { response.error("BUSY", "A wallpaper preview is already open", null); return }
        val path = call.argument<String>("path")
        val settings = call.argument<Map<String, Any>>("settings")
        if (path == null || settings == null) { response.error("ARG_ERROR", "Missing world", null); return }
        result = response
        Thread {
            var target: File? = null
            try {
                val source = File(path).canonicalFile
                val privateRoot = File(activity.applicationInfo.dataDir).canonicalPath + File.separator
                require(source.path.startsWith(privateRoot) && source.isFile && source.length() <= 40L*1024*1024) { "Invalid world image" }
                val directory = File(activity.filesDir, "world_wallpaper").apply { mkdirs() }
                target = File(directory, "scene_${System.nanoTime()}.image")
                source.copyTo(target, overwrite = false)
                val preferences = activity.getSharedPreferences(WorldWallpaperStore.PREFS, Context.MODE_PRIVATE)
                // Clean a stale, unconfirmed preview from a previous process.
                WorldWallpaperStore.finish(activity, false)
                val data = JSONObject().put("path", target.path).put("settings", JSONObject(settings))
                check(preferences.edit().putString(WorldWallpaperStore.PENDING, data.toString()).commit())
                activity.runOnUiThread {
                    try {
                        check(!activity.isFinishing && !activity.isDestroyed) { "Wallpaper screen closed" }
                        val intent = Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER).apply {
                            putExtra(WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT,
                                ComponentName(activity, WorldWallpaperService::class.java))
                        }
                        @Suppress("DEPRECATION")
                        activity.startActivityForResult(intent, REQUEST)
                    } catch (e: Exception) {
                        runCatching { WorldWallpaperStore.finish(activity, false) }
                        result?.error("PREVIEW_FAILED", e.message, null); result = null
                    }
                }
            } catch (e: Exception) {
                target?.delete()
                activity.runOnUiThread { result?.error("WORLD_FAILED", e.message, null); result = null }
            }
        }.start()
    }

    fun onResult(code: Int) {
        try {
            val accepted = code == Activity.RESULT_OK
            WorldWallpaperStore.finish(activity, accepted)
            result?.success(accepted)
        } catch (e: Exception) { result?.error("WORLD_FAILED", e.message, null) }
        finally { result = null }
    }
}
