# Keep Flutter embedding + platform-channel entry points.
-keep class io.flutter.** { *; }

# Google Mobile Ads (google_mobile_ads ships consumer rules; this is a safety net).
-keep class com.google.android.gms.ads.** { *; }

# App's Kotlin classes invoked from the native side (MainActivity / LiveWallpaperService).
-keep class com.sherdor.wallpapers.** { *; }

# Firebase (Crashlytics/Analytics/Remote Config) — keep line info so obfuscated
# release crash reports stay readable after de-obfuscation.
-keepattributes SourceFile,LineNumberTable
-keep class com.google.firebase.** { *; }

# Flutter references Play Core (deferred components / split install) which this
# app doesn't bundle. We don't use deferred components, so silence R8's missing
# class errors for it.
-dontwarn com.google.android.play.core.**
