plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.shopkeeper"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.shopkeeper.shopkeeper"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resValue("string", "app_name", "myhanout")
    }

    flavorDimensions += "type"

    productFlavors {
        create("admin") {
            applicationId = "com.shopkeeper.admin"
            versionNameSuffix = "-admin"
            resValue("string", "app_name", "myhanoutadmin")
        }
        create("shopkeeper") {
            applicationId = "com.shopkeeper.shopkeeper"
            versionNameSuffix = "-pos"
            resValue("string", "app_name", "myhanout")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
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
