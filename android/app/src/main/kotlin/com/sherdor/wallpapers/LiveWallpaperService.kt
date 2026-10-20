package com.sherdor.wallpapers

import android.media.MediaPlayer
import android.service.wallpaper.WallpaperService
import android.view.SurfaceHolder
import java.io.File

/** Loops the video MainActivity stored in [PREFS], muted, and pauses it while the wallpaper is hidden. */
class LiveWallpaperService : WallpaperService() {

    companion object {
        const val PREFS = "live_wallpaper"
        const val KEY_VIDEO_PATH = "video_path"
    }

    override fun onCreateEngine(): Engine = VideoEngine()

    inner class VideoEngine : Engine() {
        private var player: MediaPlayer? = null

        override fun onSurfaceCreated(holder: SurfaceHolder) {
            super.onSurfaceCreated(holder)
            startPlayer(holder)
        }

        private fun startPlayer(holder: SurfaceHolder) {
            val path = getSharedPreferences(PREFS, MODE_PRIVATE)
                .getString(KEY_VIDEO_PATH, null) ?: return
            if (!File(path).exists()) return

            releasePlayer()
            try {
                player = MediaPlayer().apply {
                    setSurface(holder.surface)
                    setDataSource(path)
                    isLooping = true
                    setVolume(0f, 0f)
                    setVideoScalingMode(MediaPlayer.VIDEO_SCALING_MODE_SCALE_TO_FIT_WITH_CROPPING)
                    setOnPreparedListener { it.start() }
                    prepareAsync()
                }
            } catch (_: Exception) {
                releasePlayer()
            }
        }

        override fun onVisibilityChanged(visible: Boolean) {
            val p = player ?: return
            try {
                if (visible) {
                    if (!p.isPlaying) p.start()
                } else {
                    if (p.isPlaying) p.pause()
                }
            } catch (_: IllegalStateException) {
                // Not prepared yet; onPrepared starts it.
            }
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            releasePlayer()
            super.onSurfaceDestroyed(holder)
        }

        override fun onDestroy() {
            releasePlayer()
            super.onDestroy()
        }

        private fun releasePlayer() {
            try {
                player?.release()
            } catch (_: Exception) {}
            player = null
        }
    }
}
