import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

// ==========================================================================
// RELEASE SIGNING — Loads key.properties (NOT committed to Git)
// Falls back to debug keystore if missing → builds don't fail locally
// ==========================================================================
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.souljalazian.lotus_player"

    // ======================================================================
    // SDK & COMPILER CONFIG
    // ======================================================================
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
        disable += "InvalidPackage"
    }

    defaultConfig {
        applicationId = "com.souljalazian.lotus_player"
        minSdk = 27
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ======================================================================
    // SIGNING CONFIGURATIONS
    // ======================================================================
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    // ======================================================================
    // BUILD TYPES
    // ======================================================================
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            // Use real keystore when available; debug only as local fallback
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }

        debug {
            isMinifyEnabled = false
            isShrinkResources = false
            isDebuggable = true
        }
    }

    packaging {
        resources {
            excludes += listOf(
                "/META-INF/{AL2.0,LGPL2.1}",
                "/META-INF/DEPENDENCIES",
                "/META-INF/LICENSE",
                "/META-INF/LICENSE.txt",
                "/META-INF/license.txt",
                "/META-INF/NOTICE",
                "/META-INF/NOTICE.txt",
                "/META-INF/notice.txt"
            )
        }
    }
}

// ==========================================================================
// DEPENDENCY RESOLUTION — Force consistent Android Core versions
// ==========================================================================
configurations.all {
    resolutionStrategy {
        force("androidx.core:core:1.19.1")
        force("androidx.core:core-ktx:1.19.1")
    }
}

// ==========================================================================
// DEPENDENCIES
// ==========================================================================
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    implementation("androidx.core:core-ktx:1.19.1")
    implementation("androidx.media:media:1.8.0")
    implementation("net.jthink:jaudiotagger:3.0.1")
    implementation("androidx.core:core-splashscreen:1.2.0")

    // Firebase — BOM manages versions automatically
    implementation(platform("com.google.firebase:firebase-bom:35.2.0"))
    implementation("com.google.firebase:firebase-analytics")

    // Media3 — consistent version across all modules
    val media3Version = "1.11.1"
    implementation("androidx.media3:media3-session:$media3Version")
    implementation("androidx.media3:media3-exoplayer:$media3Version")
    implementation("androidx.media3:media3-common:$media3Version")
    implementation("androidx.media3:media3-ui:$media3Version")
}

// ==========================================================================
// KOTLIN COMPILER — Match Java 17 target
// ==========================================================================
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}