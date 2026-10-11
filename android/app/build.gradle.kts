plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

fun loadKeystoreProperties(): Map<String, String> {
    val props = mutableMapOf<String, String>()
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        file.forEachLine { line ->
            val idx = line.indexOf('=')
            if (idx > 0) {
                props[line.substring(0, idx).trim()] = line.substring(idx + 1).trim()
            }
        }
    }
    return props
}

android {
    namespace = "com.example.university_point_locator"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.university_point_locator"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keystoreProps = loadKeystoreProperties()
            val storeFileProp = keystoreProps["storeFile"]
            if (storeFileProp != null) {
                storeFile = file(storeFileProp)
                storePassword = keystoreProps["storePassword"]
                keyAlias = keystoreProps["keyAlias"]
                keyPassword = keystoreProps["keyPassword"]
            }
        }
    }

    buildTypes {
        release {
            // Never fall back to the debug key: a debug-signed release build
            // is rejected by Play, and a wrong signing lineage is permanent.
            // Without key.properties the sign task now fails loudly - and
            // this warning names the real cause first. Debug builds keep
            // using the debug config and are unaffected.
            if (loadKeystoreProperties()["storeFile"] == null) {
                logger.warn(
                    "key.properties/storeFile is missing: assembleRelease " +
                    "will fail until the upload keystore is configured."
                )
            }
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        // Kotlin 2.3.x removed the legacy android.kotlinOptions { jvmTarget = "17" }
        // string setter (now a hard compile error); this is the supported DSL and
        // keeps bytecode aligned with compileOptions' Java 17 above.
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
