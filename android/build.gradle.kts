import com.android.build.api.dsl.ApplicationExtension
import com.android.build.api.dsl.LibraryExtension

// ==============================================================================
// LOTUS PLAYER — ROOT GRADLE CONFIGURATION
// ==============================================================================

plugins {
    id("com.google.gms.google-services") version "4.6.0" apply false
}

// ==============================================================================
// CENTRALIZED BUILD DIRECTORY
// ==============================================================================
val newBuildDir = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

tasks.register<Delete>("clean") {
    description = "Deletes the root build directory."
    delete(rootProject.layout.buildDirectory)
}

// ==============================================================================
// SUBPROJECT CONFIGURATION
// ==============================================================================
subprojects {
    // 1. Redirect each subproject's build output
    val subprojectBuildDir = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(subprojectBuildDir)

    // 2. Enforce compileSdk = 37 across all Android modules
    afterEvaluate {
        extensions.findByType(ApplicationExtension::class.java)?.compileSdk = 37
        extensions.findByType(LibraryExtension::class.java)?.compileSdk = 37
    }

    // 3. Force consistent AndroidX Core versions
    configurations.all {
        resolutionStrategy {
            force("androidx.core:core:1.19.1")
            force("androidx.core:core-ktx:1.19.1")
        }
    }

    // Suppress third-party deprecation warnings
    tasks.withType<JavaCompile>().configureEach {
        options.compilerArgs.add("-Xlint:-deprecation")
    }
}
