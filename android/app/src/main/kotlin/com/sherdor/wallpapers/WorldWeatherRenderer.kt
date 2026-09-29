package com.sherdor.wallpapers

import android.graphics.*
import kotlin.math.*

/** Same seed, depth layers and 400-unit coordinates as world_weather.dart. */
internal class WorldWeatherRenderer {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val cloudPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val tails = Array(3) { FloatArray(64 * 4) }
    private val heads = Array(3) { FloatArray(64 * 4) }
    private var texture: Bitmap? = null
    private val flakeShader = RadialGradient(0f, 0f, 1f,
        intArrayOf(0xFFF4F8FF.toInt(), 0xDDF4F8FF.toInt(), 0x00F4F8FF),
        floatArrayOf(0f, .45f, 1f), Shader.TileMode.CLAMP)

    fun setTexture(value: Bitmap) {
        texture?.recycle(); texture = value
        cloudPaint.shader = BitmapShader(value, Shader.TileMode.REPEAT, Shader.TileMode.CLAMP)
    }
    fun dispose() { cloudPaint.shader = null; texture?.recycle(); texture = null }

    fun render(canvas: Canvas, height: Float, time: Double, weather: String, intensity: Float) {
        if (intensity <= 0f) return
        when (weather) {
            "rain" -> { clouds(canvas, height, time, intensity, true, .15f); rain(canvas, height, time, intensity) }
            "snow" -> { clouds(canvas, height, time, intensity, true, .12f); snow(canvas, height, time, intensity) }
            "fog" -> clouds(canvas, height, time, intensity, true, 1f)
            "clouds" -> clouds(canvas, height, time, intensity, false, 1f)
        }
    }

    private fun clouds(canvas: Canvas, height: Float, time: Double, intensity: Float, mist: Boolean, strength: Float) {
        val image = texture ?: return
        for (layer in 0..1) {
            val width = if (mist) 860f + layer * 180 else 680f + layer * 160
            val bandHeight = height * if (mist) .62f else .38f
            val y = height * if (mist) .12f + layer * .34f else -.13f + layer * .14f
            val x = ((time * (if (mist) 3.5 else 5.0) * (layer + 1) + layer * 291) % width - width).toFloat()
            cloudPaint.alpha = (255 * intensity * strength * (if (mist) .34f else .78f - layer * .16f)).roundToInt()
            val scaleX = width / image.width
            canvas.save(); canvas.translate(x, y); canvas.scale(scaleX, bandHeight / image.height)
            canvas.drawRect(-x / scaleX, 0f, (400f - x) / scaleX, image.height.toFloat(), cloudPaint)
            canvas.restore()
        }
    }

    private fun rain(canvas: Canvas, height: Float, time: Double, intensity: Float) {
        val slant = .16 + sin(time * .13) * .025
        paint.shader = null
        paint.strokeCap = Paint.Cap.ROUND
        for (layer in 0..2) {
            val count = (RAIN_COUNTS[layer] * intensity).roundToInt()
            val tail = tails[layer]; val head = heads[layer]
            for (i in 0 until count) {
                val p = particles[layer * 64 + i]
                val velocity = (140 + layer * 145) * (.8 + p[3] * .4)
                val y = (p[1] * (height + 120) + time * velocity) % (height + 120) - 60
                val x = (p[0] * 520 + time * velocity * .16) % 520 - 60
                val length = (9 + layer * 12) * (.7 + p[2] * .6)
                val index = i * 4
                tail[index] = (x - length * slant).toFloat()
                tail[index + 1] = (y - length).toFloat()
                tail[index + 2] = (x - length * slant * .25).toFloat()
                tail[index + 3] = (y - length * .25).toFloat()
                head[index] = tail[index + 2]; head[index + 1] = tail[index + 3]
                head[index + 2] = x.toFloat(); head[index + 3] = y.toFloat()
            }
            paint.strokeWidth = .4f + layer * .3f
            paint.color = Color.argb(((.13 + layer * .07) * 255).roundToInt(), 195, 215, 235)
            canvas.drawLines(tail, 0, count * 4, paint)
            paint.color = Color.argb(((.23 + layer * .12) * 255).roundToInt(), 220, 234, 248)
            canvas.drawLines(head, 0, count * 4, paint)
        }
    }

    private fun snow(canvas: Canvas, height: Float, time: Double, intensity: Float) {
        for (layer in 0..2) {
            val count = (SNOW_COUNTS[layer] * intensity).roundToInt()
            paint.shader = if (layer == 2) flakeShader else null
            paint.color = Color.argb(((.38 + layer * .22) * 255).roundToInt(), 239, 246, 255)
            for (i in 0 until count) {
                val p = particles[layer * 64 + i]
                val velocity = (12 + layer * 17) * (.7 + p[3] * .6)
                val sway = sin(time * (.45 + p[3] * .4) + p[4])
                // Kotlin's remainder can be negative; match Dart's modulo.
                val rawX = p[0] * 460 + time * (6 + layer * 5) + sway * (5 + layer * 4)
                val x = ((rawX % 460 + 460) % 460 - 30).toFloat()
                val y = ((p[1] * (height + 40) + time * velocity) % (height + 40) - 20).toFloat()
                val radius = ((.55 + layer * .75) * (.7 + p[2] * .8)).toFloat()
                if (layer == 2) {
                    canvas.save(); canvas.translate(x, y); canvas.scale(radius * 1.6f, radius * 1.35f)
                    canvas.drawCircle(0f, 0f, 1f, paint); canvas.restore()
                } else canvas.drawCircle(x, y, radius, paint)
            }
        }
        paint.shader = null
    }

    companion object {
        const val CLOUD_ASSET = "flutter_assets/assets/worlds/weather_clouds.png"
        private val RAIN_COUNTS = intArrayOf(64, 46, 24)
        private val SNOW_COUNTS = intArrayOf(64, 42, 22)
        private val particles = run {
            var seed = 38401L
            fun next(): Double { seed = seed * 16807 % 2147483647; return (seed - 1).toDouble() / 2147483646 }
            Array(192) { doubleArrayOf(next(), next(), next(), next(), next() * PI * 2) }
        }
    }
}
