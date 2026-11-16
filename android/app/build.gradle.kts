import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: key.properties is git-ignored and per-machine, and the
// keystore itself lives outside the repo. When it is absent we fall back to the
// debug key rather than failing the build, so a fresh clone still compiles.
val keyPropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keyPropertiesFile.exists()

android {
    namespace = "com.myhanout"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.myhanout.myhanout"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resValue("string", "app_name", "myhanout")
    }

    flavorDimensions += "type"

    productFlavors {
        create("admin") {
            applicationId = "com.myhanout.admin"
            versionNameSuffix = "-admin"
            resValue("string", "app_name", "myhanoutadmin")
        }
        create("shopkeeper") {
            applicationId = "com.myhanout.myhanout"
            versionNameSuffix = "-pos"
            resValue("string", "app_name", "myhanout")
        }
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                val props = Properties()
                keyPropertiesFile.inputStream().use { props.load(it) }
                storeFile = file(props.getProperty("storeFile"))
                storePassword = props.getProperty("storePassword")
                keyAlias = props.getProperty("keyAlias")
                keyPassword = props.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (hasReleaseKey) "release" else "debug"
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
