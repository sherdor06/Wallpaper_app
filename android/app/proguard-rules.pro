# Keep Flutter embedding + platform-channel entry points.
-keep class io.flutter.** { *; }

# AppLovin MAX + mediated networks. The SDKs ship their own consumer rules, so
# nothing needs keeping here — but AppLovin's bundled Open Measurement library
# calls into Amazon's PrivacyPass attestation, which only exists when the Amazon
# adapter is included. It isn't, and those call sites are unreachable, so R8's
# missing-class errors are silenced rather than pulling in an unused SDK.
-dontwarn com.amazon.privacypass.**

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
