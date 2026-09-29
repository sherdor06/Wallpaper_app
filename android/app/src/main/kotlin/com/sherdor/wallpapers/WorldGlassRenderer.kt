package com.sherdor.wallpapers

import android.graphics.*
import kotlin.math.*

/** Foreground glass; same seed, paths and analytic lifetimes as world_glass.dart. */
internal class WorldGlassRenderer {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val lensPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val trail = Path()

    fun render(canvas: Canvas, height: Float, time: Double, weather: String,
               intensity: Float, image: Bitmap, imageRect: RectF, filter: ColorFilter?) {
        if (intensity <= 0f || (weather != "rain" && weather != "snow")) return
        lensPaint.colorFilter = filter
        val snowing = weather == "snow"
        val count = ((if (snowing) 28 else 40) * intensity).roundToInt()
        for (i in 0 until count) {
            val p = particles[i]
            val duration = if (snowing) 11 + p[3] * 9 else 9 + p[3] * 8
            val life = (time / duration + p[4]) % 1
            val opacity = smooth(life / .035) * (1 - smooth((life - .86) / .14))
            val anchorX = 12 + p[0] * 376
            val anchorY = 12 + p[1] * (height - 36)
            if (snowing) {
                val landing = 1 - smooth(life / .12)
                val melt = smooth((life - .52) / .35)
                val x = anchorX - landing * (8 + p[2] * 10)
                val y = anchorY - landing * 17 + melt * melt * 12
                val radius = (3 + p[2] * 3.8) * (1 - melt * .68)
                if (melt > 0) drop(canvas, image, imageRect, x, y,
                    1.2 + p[2] * 1.6, 1.5 + p[2] * 2.1, opacity * melt * .8)
                canvas.save(); canvas.translate(x.toFloat(), y.toFloat())
                canvas.rotate((p[4] * 360).toFloat()); canvas.scale(radius.toFloat(), radius.toFloat())
                paint.style = Paint.Style.FILL; paint.shader = softIceShader
                paint.color = rgba(255, 255, 255, opacity * (1 - melt) * .6)
                canvas.drawCircle(0f, 0f, 1.2f, paint)
                paint.shader = null; paint.color = rgba(235, 244, 252, opacity * (1 - melt) * .78)
                canvas.drawPath(snow, paint); canvas.restore()
            } else {
                val slide = ((life - .48) / .52).coerceIn(0.0, 1.0)
                val travel = slide * slide * (65 + p[3] * 150)
                val x = anchorX + sin(slide * 7 + p[4] * 6) * slide * 2
                val y = anchorY + travel
                val radius = (1.6 + p[2] * 3) * (.82 + .18 * smooth(life / .48))
                if (travel > 2) {
                    trail.reset(); trail.moveTo(anchorX.toFloat(), anchorY.toFloat())
                    trail.cubicTo((anchorX + 1).toFloat(), (anchorY + travel * .35).toFloat(),
                        (x - 1).toFloat(), (y - travel * .2).toFloat(), x.toFloat(), y.toFloat())
                    paint.shader = null; paint.style = Paint.Style.STROKE; paint.strokeCap = Paint.Cap.ROUND
                    paint.strokeWidth = (radius * .7).toFloat(); paint.color = rgba(18, 30, 42, opacity * .16)
                    canvas.drawPath(trail, paint)
                    paint.strokeWidth = .55f; paint.color = rgba(215, 231, 247, opacity * .24)
                    canvas.drawPath(trail, paint)
                }
                drop(canvas, image, imageRect, x, y, radius, radius * (1.2 + slide * .85), opacity)
            }
        }
        if (!snowing) {
            for (i in 40 until 40 + (32 * intensity).roundToInt()) {
                val p = particles[i]
                val opacity = .4 + .18 * sin(time * .24 + p[4] * 6)
                drop(canvas, image, imageRect, 8 + p[0] * 384, 8 + p[1] * (height - 16),
                    .6 + p[2], .8 + p[2], opacity)
            }
        }
    }

    private fun drop(canvas: Canvas, image: Bitmap, imageRect: RectF,
                     x: Double, y: Double, rx: Double, ry: Double, opacity: Double) {
        if (opacity < .005) return
        val scaleX = image.width / imageRect.width()
        val scaleY = image.height / imageRect.height()
        val sourceWidth = rx * 2 * scaleX / 1.65
        val sourceHeight = ry * 2 * scaleY / 1.65
        val sourceX = (x - imageRect.left - rx * .18) * scaleX - sourceWidth / 2
        val sourceY = (y - imageRect.top - ry * .22) * scaleY - sourceHeight / 2
        canvas.save(); canvas.translate(x.toFloat(), y.toFloat()); canvas.scale(rx.toFloat(), ry.toFloat())
        canvas.save(); canvas.clipPath(bead)
        // Float-precision crop, constrained to the bead, no offscreen layer.
        canvas.translate(-1f, -1f)
        canvas.scale((2 / sourceWidth).toFloat(), (2 / sourceHeight).toFloat())
        canvas.translate(-sourceX.toFloat(), -sourceY.toFloat())
        lensPaint.alpha = (opacity * .88 * 255).roundToInt()
        canvas.drawBitmap(image, 0f, 0f, lensPaint); canvas.restore()
        paint.style = Paint.Style.FILL; paint.shader = waterShader
        paint.color = rgba(255, 255, 255, opacity); canvas.drawPath(bead, paint)
        paint.shader = null; paint.style = Paint.Style.STROKE; paint.strokeWidth = .1f
        paint.color = rgba(10, 20, 31, opacity * .4); canvas.drawPath(bead, paint)
        paint.strokeCap = Paint.Cap.ROUND; paint.strokeWidth = .12f
        paint.color = rgba(237, 247, 255, opacity * .65); canvas.drawPath(highlight, paint)
        paint.strokeWidth = .09f; paint.color = rgba(214, 235, 252, opacity * .5)
        canvas.drawPath(caustic, paint); canvas.restore()
    }

    companion object {
        private fun smooth(value: Double): Double {
            val v = value.coerceIn(0.0, 1.0)
            return v * v * (3 - 2 * v)
        }
        private fun rgba(r: Int, g: Int, b: Int, a: Double) = Color.argb((a * 255).roundToInt(), r, g, b)
        private val particles = run {
            var seed = 81731L
            fun next(): Double { seed = seed * 16807 % 2147483647; return (seed - 1).toDouble() / 2147483646 }
            Array(72) { doubleArrayOf(next(), next(), next(), next(), next()) }
        }
        private val bead = Path().apply {
            moveTo(0f, -1f); cubicTo(.52f, -.98f, .78f, -.48f, .9f, .12f)
            cubicTo(1.02f, .77f, .52f, 1f, 0f, 1f); cubicTo(-.58f, 1f, -1f, .64f, -.84f, .07f)
            cubicTo(-.68f, -.5f, -.47f, -.94f, 0f, -1f); close()
        }
        private val highlight = Path().apply {
            moveTo(-.57f, -.15f); cubicTo(-.52f, -.61f, -.22f, -.8f, .12f, -.77f)
        }
        private val caustic = Path().apply {
            moveTo(-.45f, .69f); quadTo(.14f, .98f, .59f, .51f)
        }
        private val snow = Path().apply {
            addOval(RectF(-.4f, -.4f, .4f, .4f), Path.Direction.CW)
            addOval(RectF(-.77f, -.2f, -.13f, .44f), Path.Direction.CW)
            addOval(RectF(-.14f, -.69f, .54f, -.01f), Path.Direction.CW)
            addOval(RectF(.22f, -.12f, .78f, .44f), Path.Direction.CW)
            addOval(RectF(-.52f, -.64f, 0f, -.12f), Path.Direction.CW)
            addOval(RectF(-.16f, .19f, .46f, .81f), Path.Direction.CW)
            addOval(RectF(-.64f, .27f, -.22f, .69f), Path.Direction.CW)
        }
        private val waterShader = RadialGradient(-.3f, -.4f, 1.6f,
            intArrayOf(0x18FFFFFF, 0x07121C29, 0x65101927), floatArrayOf(0f, .55f, 1f), Shader.TileMode.CLAMP)
        private val softIceShader = RadialGradient(0f, 0f, 1.2f,
            intArrayOf(0x9CE6EFF8.toInt(), 0x00E6EFF8), null, Shader.TileMode.CLAMP)
    }
}
