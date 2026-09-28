import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase (Google Services) — reads android/app/google-services.json.
    id("com.google.gms.google-services")
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}

// Release signing. Kept in android/key.properties, which is gitignored along
// with the keystore itself: the signing key must never enter version control.
// Losing it means Play will not accept another update, so keep a backup
// somewhere other than the build machine.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
// Signing only matters when a release artifact is being produced. Validating
// unconditionally would stop `flutter run` on a machine whose key.properties is
// absent or not yet filled in.
val isReleaseBuild = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true) || it.contains("bundle", ignoreCase = true)
}
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.adimove.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.adimove.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] =
            localProperties.getProperty("google.maps.apiKey")
                ?: System.getenv("GOOGLE_MAPS_API_KEY")
                ?: ""
    }

    signingConfigs {
        // Only created when key.properties is present. Declaring it
        // unconditionally would run the validation below on every build,
        // including debug ones on a machine that has no signing key.
        if (hasReleaseKeystore) {
            create("release") {
                val storeFilePath = keystoreProperties.getProperty("storeFile")
                val loadedKeyAlias = keystoreProperties.getProperty("keyAlias")
                val loadedKeyPassword = keystoreProperties.getProperty("keyPassword")
                val loadedStorePassword = keystoreProperties.getProperty("storePassword")

                val filled = listOf(storeFilePath, loadedKeyAlias, loadedKeyPassword, loadedStorePassword)
                    .all { !it.isNullOrBlank() && it != "REPLACE_ME" }

                if (isReleaseBuild && !filled) {
                    throw GradleException(
                        "android/key.properties is incomplete: storeFile, keyAlias, keyPassword and " +
                        "storePassword must all be set (no REPLACE_ME left). Without them this release " +
                        "would be signed with the debug key, which Play rejects."
                    )
                }

                if (filled) {
                    // An absolute path (keystore kept outside the repo) is used
                    // as given; anything else resolves against android/.
                    val resolved = File(storeFilePath).let {
                        if (it.isAbsolute) it else rootProject.file(storeFilePath)
                    }
                    if (isReleaseBuild && !resolved.exists()) {
                        throw GradleException("key.properties: no keystore found at ${resolved.absolutePath}")
                    }
                    if (resolved.exists()) {
                        storeFile = resolved
                        keyAlias = loadedKeyAlias
                        keyPassword = loadedKeyPassword
                        storePassword = loadedStorePassword
                    }
                }
            }
        }
    }

    buildTypes {
        release {
            // Falls back to the debug key when no keystore is present, so
            // `flutter run --release` still works on a machine that has no
            // signing key. Play refuses a debug-signed upload, so a release
            // build for the store must have android/key.properties in place --
            // check the banner printed by the `verifyReleaseSigning` task below.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Core library desugaring — required by flutter_local_notifications.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// A debug-signed bundle is rejected by Play, but only after upload. Say so at
// build time instead of finding out in the console.
tasks.register("verifyReleaseSigning") {
    doLast {
        if (!hasReleaseKeystore) {
            throw GradleException(
                "No android/key.properties found: this release would be signed with the debug key, " +
                "which Play rejects. See android/key.properties.example."
            )
        }
    }
}
