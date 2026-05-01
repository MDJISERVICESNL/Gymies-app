pluginManagement {
    val flutterSdkPath =
        run {
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
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    id("com.google.gms.google-services") version "4.4.4" apply false
    id("com.google.firebase.crashlytics") version "3.0.3" apply false
}

include(":app")

// Fix voor plugins zonder namespace (vereist door AGP 8+)
// + JVM target fix (Java 1.8 vs Kotlin 17 mismatch in plugins)
gradle.beforeProject {
    if (project.name != "app" && project.buildFile.exists()) {
        project.afterEvaluate {
            if (project.plugins.hasPlugin("com.android.library")) {
                val android = project.extensions.findByName("android")
                if (android is com.android.build.gradle.LibraryExtension) {
                    // Namespace fix
                    if (android.namespace.isNullOrEmpty()) {
                        val manifest = project.file("src/main/AndroidManifest.xml")
                        if (manifest.exists()) {
                            val pkg = Regex("package=\"([^\"]+)\"").find(manifest.readText())?.groupValues?.get(1)
                            if (pkg != null) {
                                android.namespace = pkg
                            }
                        }
                    }
                    // JVM + Java version fix — forceer Java 17 voor alle plugins
                    android.compileOptions {
                        sourceCompatibility = JavaVersion.VERSION_17
                        targetCompatibility = JavaVersion.VERSION_17
                    }
                }
            }
            // Kotlin JVM target + language version fix
            project.tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
                    languageVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_1_8)
                }
            }
        }
    }
}
