plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.mooncycle"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Release builds are signed with the upload key: on Codemagic from its
    // keystore settings (CM_KEYSTORE_* variables), on a PC from
    // android/key.properties, which is never committed. Without either, the
    // debug key is used, which Google Play rejects.
    val keyProperties = java.util.Properties().apply {
        val file = rootProject.file("key.properties")
        if (file.exists()) file.inputStream().use { load(it) }
    }
    val keystorePath = System.getenv("CM_KEYSTORE_PATH") ?: keyProperties.getProperty("storeFile")

    signingConfigs {
        if (keystorePath != null) {
            create("release") {
                storeFile = file(keystorePath)
                storePassword = System.getenv("CM_KEYSTORE_PASSWORD") ?: keyProperties.getProperty("storePassword")
                keyAlias = System.getenv("CM_KEY_ALIAS") ?: keyProperties.getProperty("keyAlias")
                keyPassword = System.getenv("CM_KEY_PASSWORD") ?: keyProperties.getProperty("keyPassword")
            }
        }
    }

    defaultConfig {
        // Permanent once the app is on Google Play. Matches the iOS bundle ID.
        applicationId = "com.ioncodex.mooncycle"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Health Connect and the notification scheduler both need API 26.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // The AppCompat themes in res/values*/styles.xml, which local_auth needs.
    implementation("androidx.appcompat:appcompat:1.7.0")
}
