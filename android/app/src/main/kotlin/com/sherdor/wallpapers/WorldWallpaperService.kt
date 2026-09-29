package com.sherdor.wallpapers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.database.ContentObserver
import android.graphics.*
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Settings
import android.service.wallpaper.WallpaperService
import android.view.SurfaceHolder
import org.json.JSONObject
import java.util.concurrent.Executors
import kotlin.math.*

/** A lightweight renderer. No Flutter engine, ad SDK or network runs here. */
class WorldWallpaperService : WallpaperService() {
    override fun onCreateEngine(): Engine = WorldEngine()

    inner class WorldEngine : Engine(), SharedPreferences.OnSharedPreferenceChangeListener {
        private val handler = Handler(Looper.getMainLooper())
        private val decoder = Executors.newSingleThreadExecutor()
        private val prefs = getSharedPreferences(WorldWallpaperStore.PREFS, MODE_PRIVATE)
        private val power by lazy { getSystemService(POWER_SERVICE) as PowerManager }
        private val weatherRenderer = WorldWeatherRenderer()
        private val glassRenderer = WorldGlassRenderer()
        private val glassImageRect = RectF()
        private val imagePaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        private val destination = RectF()
        private var bitmap: Bitmap? = null
        private var recipe = JSONObject()
        private var surfaceReady = false
        private var shown = false
        private var destroyed = false
        private var generation = 0
        private var last = 0L
        private var time = 0.0
        private var weather = "rain"
        private var throughGlass = false
        private var intensity = .62f
        private var speed = .35f
        private var drift = .4f
        private var zoom = 1.055f
        private var focalX = .5f
        private var focalY = .5f
        private var motion = true
        private var systemMotion = true
        private var powerSaving = false
        private val draw = Runnable { drawFrame() }
        private val motionObserver = object : ContentObserver(handler) {
            override fun onChange(selfChange: Boolean) {
                readSystemMotion()
                schedule()
            }
        }
        private val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                powerSaving = power.isPowerSaveMode
                schedule()
            }
        }
        override fun onCreate(holder: SurfaceHolder) {
            super.onCreate(holder)
            prefs.registerOnSharedPreferenceChangeListener(this)
            powerSaving = power.isPowerSaveMode
            val filter = IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED)
            if (Build.VERSION.SDK_INT >= 33) registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            else { @Suppress("DEPRECATION") registerReceiver(receiver, filter) }
            setOffsetNotificationsEnabled(false)
            contentResolver.registerContentObserver(
                Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE),
                false, motionObserver)
            readSystemMotion()
            load()
        }
        private fun readSystemMotion() {
            systemMotion = Settings.Global.getFloat(contentResolver,
                Settings.Global.ANIMATOR_DURATION_SCALE, 1f) != 0f
        }
        override fun onSharedPreferenceChanged(shared: SharedPreferences?, key: String?) {
            if (key == if (isPreview) WorldWallpaperStore.PENDING else WorldWallpaperStore.ACTIVE) load()
        }
        private fun load() {
            val raw = prefs.getString(if(isPreview) WorldWallpaperStore.PENDING else WorldWallpaperStore.ACTIVE, null) ?: return
            val token = ++generation
            decoder.execute {
                var decoded: Bitmap? = null
                var clouds: Bitmap? = null
                try {
                    val data = JSONObject(raw)
                    val path = data.getString("path")
                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                    BitmapFactory.decodeFile(path, bounds)
                    var sample = 1
                    while(max(bounds.outWidth, bounds.outHeight)/sample > 2304) sample *= 2
                    decoded = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply {
                        inSampleSize=sample; inPreferredConfig=Bitmap.Config.ARGB_8888
                    }) ?: throw IllegalStateException("Image decode failed")
                    clouds = assets.open(WorldWeatherRenderer.CLOUD_ASSET).use {
                        BitmapFactory.decodeStream(it)
                    } ?: throw IllegalStateException("Cloud texture decode failed")
                    val loadedClouds = clouds
                    val loaded = decoded
                    handler.post {
                        if(destroyed || token != generation) { loaded.recycle(); loadedClouds.recycle() }
                        else {
                            bitmap?.recycle(); bitmap=loaded
                            weatherRenderer.setTexture(loadedClouds)
                            recipe=data.getJSONObject("settings"); configure(); schedule()
                        }
                    }
                } catch (_: Exception) { decoded?.recycle(); clouds?.recycle() }
            }
        }
        private fun value(key: String, fallback: Float, min: Float=0f, max: Float=1f): Float {
            val v=recipe.optDouble(key, fallback.toDouble()).toFloat()
            return if(v.isFinite()) v.coerceIn(min,max) else fallback
        }
        private fun configure() {
            weather=recipe.optString("weather","rain"); intensity=value("intensity",.62f)
            throughGlass = recipe.optString("weatherView", "openAir") == "window"
            speed=value("speed",.35f);drift=value("drift",.4f);zoom=value("zoom",1.055f,1.04f,1.6f)
            focalX=value("focalX",.5f);focalY=value("focalY",.5f);motion=recipe.optBoolean("motion",true)
            if (!motion) time = 0.0
            val rgb=when(recipe.optString("palette","lavender")) {
                "blue" -> floatArrayOf(.85f,.98f,1.10f)
                "lavender" -> floatArrayOf(1.06f,.91f,1.15f)
                "amber" -> floatArrayOf(1.15f,1.01f,.8f)
                else -> floatArrayOf(1f,1f,1f)
            }
            val brightness=.65f+value("glow",.55f)*.65f
            imagePaint.colorFilter=ColorMatrixColorFilter(floatArrayOf(
                rgb[0]*brightness,0f,0f,0f,0f, 0f,rgb[1]*brightness,0f,0f,0f,
                0f,0f,rgb[2]*brightness,0f,0f, 0f,0f,0f,1f,0f))
        }
        override fun onVisibilityChanged(visible: Boolean) { shown=visible; schedule() }
        override fun onSurfaceCreated(holder: SurfaceHolder) { super.onSurfaceCreated(holder);surfaceReady=true;schedule() }
        override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) { super.onSurfaceChanged(holder,format,width,height);surfaceReady=true;schedule() }
        override fun onSurfaceRedrawNeeded(holder: SurfaceHolder) { super.onSurfaceRedrawNeeded(holder);schedule() }
        override fun onSurfaceDestroyed(holder: SurfaceHolder) { surfaceReady=false;handler.removeCallbacks(draw);super.onSurfaceDestroyed(holder) }

        private fun schedule() {
            handler.removeCallbacks(draw); last=SystemClock.uptimeMillis()
            if(!destroyed && shown && surfaceReady) handler.post(draw)
        }
        private fun drawFrame() {
            if(destroyed || !shown || !surfaceReady) return
            val animated = motion && systemMotion && !powerSaving &&
                (drift > 0f || weather != "clear" && intensity > 0f)
            val now=SystemClock.uptimeMillis()
            if(animated) time+=min((now-last)/1000.0,.1)*(.3+speed/.7)
            last=now
            var canvas: Canvas?=null
            try {
                canvas=if(Build.VERSION.SDK_INT>=26) surfaceHolder.lockHardwareCanvas() else surfaceHolder.lockCanvas()
                if(canvas != null) render(canvas)
            } catch (_: IllegalArgumentException) {
                // The system can remove the surface between its callback and lock.
            } catch (_: IllegalStateException) {
            } finally { if(canvas!=null) runCatching { surfaceHolder.unlockCanvasAndPost(canvas) } }
            if(animated) handler.postDelayed(draw, max(1L, 33L - (SystemClock.uptimeMillis() - now)))
        }
        private fun render(canvas: Canvas) {
            canvas.drawColor(Color.rgb(11,17,32))
            val image=bitmap ?: return
            val width=canvas.width.toFloat();val height=canvas.height.toFloat();val unit=width/400f
            val cover=max(width/image.width,height/image.height)*zoom
            val w=image.width*cover;val h=image.height*cover
            val x=(-(w-width)*focalX+sin(time*.105).toFloat()*3f*unit*drift).coerceIn(width-w,0f)
            destination.set(x,-(h-height)*focalY,x+w,-(h-height)*focalY+h)
            canvas.drawBitmap(image,null,destination,imagePaint)
            canvas.save();canvas.scale(unit,unit)
            weatherRenderer.render(canvas, height/unit, time, weather, intensity)
            if (throughGlass) {
                glassImageRect.set(destination.left/unit, destination.top/unit,
                    destination.right/unit, destination.bottom/unit)
                glassRenderer.render(canvas, height/unit, time, weather, intensity,
                    image, glassImageRect, imagePaint.colorFilter)
            }
            canvas.restore()
        }
        override fun onDestroy() {
            destroyed=true;generation++;handler.removeCallbacks(draw)
            prefs.unregisterOnSharedPreferenceChangeListener(this)
            contentResolver.unregisterContentObserver(motionObserver)
            runCatching { unregisterReceiver(receiver) }
            decoder.shutdownNow();bitmap?.recycle();bitmap=null
            weatherRenderer.dispose()
            super.onDestroy()
        }
    }
}
