pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    // NOTE: keep KGP declared for now — firebase_analytics/remote_config and
    // package_info_plus still apply it; without this pin an old Kotlin resolves
    // and the build fails. Migrate to Built-in Kotlin once those plugins do.
    // 2.3.x or newer is required, not just preferred: Android Studio now bundles
    // JDK 25, and every Kotlin before 2.3.0 crashes on startup trying to parse
    // that version string -- `IllegalArgumentException: 25.0.2` out of
    // JavaVersion.parse, with Gradle reporting the bare number as the whole
    // error (JetBrains KT-83610). Do not lower this while the toolchain is on
    // JDK 25.
    id("org.jetbrains.kotlin.android") version "2.3.21" apply false
    // Firebase Gradle plugins (applied in app/build.gradle).
    id("com.google.gms.google-services") version "4.4.2" apply false
    id("com.google.firebase.crashlytics") version "3.0.3" apply false
}

include(":app")
