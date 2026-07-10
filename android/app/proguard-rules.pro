# Keep Flutter embedding + platform-channel entry points.
-keep class io.flutter.** { *; }

# Google Mobile Ads (google_mobile_ads ships consumer rules; this is a safety net).
-keep class com.google.android.gms.ads.** { *; }

# App's Kotlin classes invoked from the native side (MainActivity / LiveWallpaperService).
-keep class com.sherdor.wallpapers.** { *; }
