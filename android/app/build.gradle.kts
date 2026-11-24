import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing details live in android/key.properties, which is never
// committed. Without that file (a fresh clone, CI) release builds fall back
// to the debug key so they still build and install.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "com.nischalpandey.noctune"
    // permission_handler_android compiles against SDK 37, newer than Flutter's default.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.nischalpandey.noctune"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter (2000 for arm64-v8a). For universal APK builds
        // (where split-per-abi is not set), add 2000 automatically when versionCode < 1000
        // so universal and arm64-v8a APKs always share the exact same versionCode and can
        // be installed interchangeably on all devices without version-downgrade errors.
        val rawVersionCode = flutter.versionCode
        val isSplitPerAbi = project.findProperty("split-per-abi")?.toString()?.toBoolean() == true
        versionCode = if (!isSplitPerAbi && rawVersionCode < 1000) {
            2000 + rawVersionCode
        } else {
            rawVersionCode
        }
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("org.mozilla:rhino:1.7.15")
}
