package com.sherdor.wallpapers

import android.graphics.*
import android.os.Build
import kotlin.math.*

/** Twin of world_weather.dart: same seed, layers, colours and 400-unit coordinates. */
internal class WorldWeatherRenderer {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val cloudPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val tails = Array(3) { FloatArray(RAIN_COUNTS[it] * 4) }
    private val heads = Array(3) { FloatArray(RAIN_COUNTS[it] * 4) }
    private var texture: Bitmap? = null
    private var cloudShadow: ColorFilter = PorterDuffColorFilter(Color.WHITE, PorterDuff.Mode.MULTIPLY)
    private var cloudLight: ColorFilter = cloudShadow
    private var mistTint: ColorFilter = cloudShadow
    private var fogColor = Color.WHITE
    private var fogShader: Shader? = null
    private var fogHeight = 0f
    private var fogIntensity = 0f
    private val flakeShader = RadialGradient(0f, 0f, 1f,
        intArrayOf(0xFFF4F8FF.toInt(), 0xDDF4F8FF.toInt(), 0x00F4F8FF),
        floatArrayOf(0f, .45f, 1f), Shader.TileMode.CLAMP)
    private val bokehShader = RadialGradient(0f, 0f, 1f,
        intArrayOf(0xFFF4F8FF.toInt(), 0x80F4F8FF.toInt(), 0x00F4F8FF),
        floatArrayOf(0f, .6f, 1f), Shader.TileMode.CLAMP)

    fun setTexture(value: Bitmap) {
        texture?.recycle(); texture = value
        cloudPaint.shader = BitmapShader(value, Shader.TileMode.REPEAT, Shader.TileMode.CLAMP)
    }
    fun dispose() { cloudPaint.shader = null; texture?.recycle(); texture = null }

    fun setPalette(palette: String) {
        val tint = when (palette) {
            "blue" -> floatArrayOf(.88f, .96f, 1f)
            "lavender" -> floatArrayOf(.96f, .90f, 1f)
            "amber" -> floatArrayOf(1f, .94f, .82f)
            else -> floatArrayOf(1f, 1f, 1f)
        }
        fun tinted(r: Int, g: Int, b: Int) =
            Color.rgb((r * tint[0]).roundToInt(), (g * tint[1]).roundToInt(), (b * tint[2]).roundToInt())
        cloudShadow = PorterDuffColorFilter(tinted(70, 74, 98), PorterDuff.Mode.MULTIPLY)
        cloudLight = PorterDuffColorFilter(tinted(176, 170, 206), PorterDuff.Mode.MULTIPLY)
        mistTint = PorterDuffColorFilter(tinted(150, 150, 168), PorterDuff.Mode.MULTIPLY)
        fogColor = tinted(196, 198, 212)
        fogShader = null
    }

    fun render(canvas: Canvas, height: Float, time: Double, weather: String, intensity: Float) {
        if (intensity <= 0f) return
        when (weather) {
            "rain" -> { mist(canvas, height, time, intensity, .35f); rain(canvas, height, time, intensity) }
            "snow" -> { mist(canvas, height, time, intensity, .3f); snow(canvas, height, time, intensity) }
            "fog" -> { mist(canvas, height, time, intensity, 1f); groundFog(canvas, height, intensity) }
            "clouds" -> clouds(canvas, height, time, intensity)
        }
        blend(cloudPaint, null); cloudPaint.colorFilter = null
    }

    private fun band(canvas: Canvas, x: Float, y: Float, width: Float, bandHeight: Float) {
        val image = texture ?: return
        val scaleX = width / image.width
        canvas.save(); canvas.translate(x, y); canvas.scale(scaleX, bandHeight / image.height)
        canvas.drawRect(-x / scaleX, 0f, (400f - x) / scaleX, image.height.toFloat(), cloudPaint)
        canvas.restore()
    }

    private fun clouds(canvas: Canvas, height: Float, time: Double, intensity: Float) {
        if (texture == null) return
        for (layer in 0..1) {
            val width = 680f + layer * 160
            val bandHeight = height * (.40f + layer * .06f)
            val y = height * (-.14f + layer * .15f)
            val x = ((time * 5.0 * (layer + 1) + layer * 291) % width - width).toFloat()
            val depth = 1 - layer * .25f
            blend(cloudPaint, MULTIPLY); cloudPaint.colorFilter = cloudShadow
            cloudPaint.alpha = (255 * .55f * intensity * depth).roundToInt()
            band(canvas, x, y + bandHeight * .03f, width, bandHeight)
            blend(cloudPaint, SCREEN); cloudPaint.colorFilter = cloudLight
            cloudPaint.alpha = (255 * .42f * intensity * depth).roundToInt()
            band(canvas, x, y - bandHeight * .04f, width, bandHeight)
        }
    }

    private fun mist(canvas: Canvas, height: Float, time: Double, intensity: Float, strength: Float) {
        if (texture == null) return
        blend(cloudPaint, SCREEN); cloudPaint.colorFilter = mistTint
        for (layer in 0..1) {
            val width = 860f + layer * 180
            val x = ((time * 3.5 * (layer + 1) + layer * 291) % width - width).toFloat()
            cloudPaint.alpha = (255 * .42f * intensity * strength * (1 - layer * .2f)).roundToInt()
            band(canvas, x, height * (.18f + layer * .32f), width, height * .62f)
        }
    }

    private fun groundFog(canvas: Canvas, height: Float, intensity: Float) {
        if (fogShader == null || fogHeight != height || fogIntensity != intensity) {
            fogHeight = height; fogIntensity = intensity
            val alpha = (255 * .42f * intensity).roundToInt()
            fogShader = LinearGradient(0f, height * .42f, 0f, height,
                fogColor and 0x00FFFFFF, (fogColor and 0x00FFFFFF) or (alpha shl 24), Shader.TileMode.CLAMP)
        }
        paint.shader = fogShader; paint.color = Color.WHITE
        canvas.drawRect(0f, 0f, 400f, height, paint); paint.shader = null
    }

    private fun rain(canvas: Canvas, height: Float, time: Double, intensity: Float) {
        val wind = .10 + sin(time * .23) * .05 + sin(time * .61 + 1.3) * .03
        paint.shader = null
        paint.strokeCap = Paint.Cap.ROUND
        for (layer in 0..2) {
            val count = (RAIN_COUNTS[layer] * intensity).roundToInt()
            val tail = tails[layer]; val head = heads[layer]
            val slant = wind * RAIN_WIND[layer]
            for (i in 0 until count) {
                val p = particles[layer * LAYER_SLOTS + i]
                val velocity = RAIN_SPEED[layer] * (.85 + p[3] * .3)
                val y = (p[1] * (height + 160) + time * velocity) % (height + 160) - 80
                val x = (p[0] * 520 + time * velocity * slant) % 520 - 60
                val length = RAIN_LENGTH[layer] * (.75 + p[2] * .5)
                val index = i * 4
                tail[index] = (x - length * slant).toFloat()
                tail[index + 1] = (y - length).toFloat()
                tail[index + 2] = (x - length * slant * .3).toFloat()
                tail[index + 3] = (y - length * .3).toFloat()
                head[index] = tail[index + 2]; head[index + 1] = tail[index + 3]
                head[index + 2] = x.toFloat(); head[index + 3] = y.toFloat()
            }
            paint.strokeWidth = RAIN_WIDTH[layer]
            paint.color = Color.argb((RAIN_TAIL_ALPHA[layer] * 255).roundToInt(), 190, 205, 225)
            canvas.drawLines(tail, 0, count * 4, paint)
            paint.color = Color.argb((RAIN_HEAD_ALPHA[layer] * 255).roundToInt(), 225, 235, 248)
            canvas.drawLines(head, 0, count * 4, paint)
        }
    }

    private fun snow(canvas: Canvas, height: Float, time: Double, intensity: Float) {
        for (layer in 0..3) {
            val count = (SNOW_COUNTS[layer] * intensity).roundToInt()
            paint.shader = when (layer) { 0 -> null; 3 -> bokehShader; else -> flakeShader }
            for (i in 0 until count) {
                val p = particles[layer * LAYER_SLOTS + i]
                paint.color = Color.argb((SNOW_ALPHA[layer] * (.6 + p[2] * .4) * 255).roundToInt(), 239, 246, 255)
                val radius = SNOW_RADIUS[layer] * (.7 + p[2] * .6)
                val fall = SNOW_FALL[layer] * (.7 + p[3] * .6)
                val rate = .35 + p[3] * .35
                val sway = sin(time * rate + p[4]) + sin(time * rate * 2.3 + p[4] * 1.7) * .4
                val span = 400 + radius * 2 + 60
                // Kotlin's remainder can be negative; match Dart's modulo.
                val rawX = p[0] * span + time * SNOW_WIND[layer] + sway * SNOW_SWAY[layer]
                val x = ((rawX % span + span) % span - radius - 30).toFloat()
                val drop = height + radius * 2 + 40
                val y = ((p[1] * drop + time * fall) % drop - radius - 20).toFloat()
                if (layer == 0) canvas.drawCircle(x, y, radius.toFloat(), paint)
                else {
                    canvas.save(); canvas.translate(x, y)
                    canvas.scale((radius * 1.3).toFloat(), (radius * 1.55).toFloat())
                    canvas.drawCircle(0f, 0f, 1f, paint); canvas.restore()
                }
            }
        }
        paint.shader = null
    }

    companion object {
        const val CLOUD_ASSET = "flutter_assets/assets/worlds/weather_clouds.png"
        private const val LAYER_SLOTS = 320
        private val RAIN_COUNTS = intArrayOf(300, 140, 44)
        private val RAIN_SPEED = doubleArrayOf(300.0, 460.0, 640.0)
        private val RAIN_LENGTH = doubleArrayOf(12.0, 20.0, 34.0)
        private val RAIN_WIDTH = floatArrayOf(.4f, .65f, 1.2f)
        private val RAIN_TAIL_ALPHA = doubleArrayOf(.10, .16, .11)
        private val RAIN_HEAD_ALPHA = doubleArrayOf(.22, .34, .22)
        private val RAIN_WIND = doubleArrayOf(.8, 1.0, 1.25)
        private val SNOW_COUNTS = intArrayOf(260, 130, 44, 10)
        private val SNOW_FALL = doubleArrayOf(12.0, 22.0, 36.0, 48.0)
        private val SNOW_RADIUS = doubleArrayOf(.75, 1.4, 2.6, 8.0)
        private val SNOW_ALPHA = doubleArrayOf(.6, .8, .9, .24)
        private val SNOW_SWAY = doubleArrayOf(3.0, 6.0, 10.0, 16.0)
        private val SNOW_WIND = doubleArrayOf(5.0, 9.0, 14.0, 20.0)
        private const val MULTIPLY = 1
        private const val SCREEN = 2

        private val particles = run {
            var seed = 38401L
            fun next(): Double { seed = seed * 16807 % 2147483647; return (seed - 1).toDouble() / 2147483646 }
            Array(LAYER_SLOTS * 4) { doubleArrayOf(next(), next(), next(), next(), next() * PI * 2) }
        }

        // PorterDuff.Mode.MULTIPLY as a transfer mode clears what the cloud does
        // not cover; the separable multiply exists from Android 10. Below that the
        // cloud shadow is a plain translucent layer, close enough on a dark sky.
        private fun blend(paint: Paint, mode: Int?) {
            if (Build.VERSION.SDK_INT >= 29) {
                paint.blendMode = when (mode) {
                    MULTIPLY -> BlendMode.MULTIPLY; SCREEN -> BlendMode.SCREEN; else -> null
                }
            } else {
                paint.xfermode = if (mode == SCREEN) PorterDuffXfermode(PorterDuff.Mode.SCREEN) else null
            }
        }

        /** world_weather.dart `grade`: the weather's light on the scene, after the palette. */
        fun grade(weather: String, intensity: Float, palette: FloatArray): FloatArray {
            val k = if (weather == "clear") 0f else intensity
            val (saturation, gain, lift) = when (weather) {
                "rain" -> Triple(1 - .30f * k, 1 - .16f * k, 8 * k)
                "snow" -> Triple(1 - .35f * k, 1 - .04f * k, 22 * k)
                "fog" -> Triple(1 - .40f * k, 1 - .28f * k, 40 * k)
                "clouds" -> Triple(1 - .22f * k, 1 - .12f * k, 4 * k)
                else -> Triple(1f, 1f, 0f)
            }
            val tint = when (weather) {
                "rain" -> floatArrayOf(.96f, .99f, 1.05f)
                "snow" -> floatArrayOf(.97f, 1f, 1.06f)
                "fog" -> floatArrayOf(1f, 1f, 1.02f)
                "clouds" -> floatArrayOf(.98f, .99f, 1.02f)
                else -> floatArrayOf(1f, 1f, 1f)
            }
            val luma = floatArrayOf(.2126f, .7152f, .0722f)
            val matrix = FloatArray(20)
            for (row in 0..2) {
                val scale = gain * (1 + (tint[row] - 1) * k)
                for (column in 0..2) {
                    val mix = (1 - saturation) * luma[column] + if (row == column) saturation else 0f
                    matrix[row * 5 + column] = scale * mix * palette[column]
                }
                matrix[row * 5 + 4] = lift
            }
            matrix[18] = 1f
            return matrix
        }
    }
}
