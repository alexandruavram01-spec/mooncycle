import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release builds are signed with the upload key: on Codemagic from its
// keystore settings (CM_KEYSTORE_* variables), on a PC from
// android/key.properties, which is never committed. Without either, the
// debug key is used, which Google Play rejects. Read here, outside the
// android block, where `java.util` would not resolve.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) FileInputStream(file).use { load(it) }
}
val keystorePath: String? =
    System.getenv("CM_KEYSTORE_PATH") ?: keyProperties.getProperty("storeFile")

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

    signingConfigs {
        keystorePath?.let { path ->
            create("release") {
                storeFile = file(path)
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
        // The notification scheduler needs API 26.
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
