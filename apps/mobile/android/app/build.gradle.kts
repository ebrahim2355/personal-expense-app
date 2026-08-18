import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("key.properties")
if (signingPropertiesFile.exists()) {
    signingPropertiesFile.inputStream().use(signingProperties::load)
}

fun signingValue(propertyName: String, environmentName: String): String? =
    System.getenv(environmentName)?.takeIf { it.isNotBlank() }
        ?: signingProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }

val releaseStoreFile = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")
val releaseStorePassword =
    signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
val releaseSigningValues = listOf(
    releaseStoreFile,
    releaseStorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
)
val releaseSigningConfigured = releaseSigningValues.all { it != null }
if (releaseSigningValues.any { it != null } && !releaseSigningConfigured) {
    error(
        "Release signing is partially configured. Set all four key.properties " +
            "values or ANDROID_KEYSTORE_PATH, ANDROID_KEYSTORE_PASSWORD, " +
            "ANDROID_KEY_ALIAS, and ANDROID_KEY_PASSWORD.",
    )
}

android {
    namespace = "com.sumonebrahim.houseexpenses"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications relies on library desugaring, and requires
        // it even for apps that never schedule a notification.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.sumonebrahim.houseexpenses"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Desugaring pushes the app past the single-dex method limit.
        multiDexEnabled = true
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            if (releaseSigningConfigured) {
                val configuredRelease = signingConfigs.create("configuredRelease")
                configuredRelease.storeFile = file(requireNotNull(releaseStoreFile))
                configuredRelease.storePassword = requireNotNull(releaseStorePassword)
                configuredRelease.keyAlias = requireNotNull(releaseKeyAlias)
                configuredRelease.keyPassword = requireNotNull(releaseKeyPassword)
                signingConfig = configuredRelease
            } else {
                // Never silently ship a release APK signed with the debug key.
                // Gradle emits an unsigned verification APK until credentials
                // are supplied through ignored local properties or the env.
                signingConfig = null
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Required by flutter_local_notifications; the version its own Gradle file pins.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
