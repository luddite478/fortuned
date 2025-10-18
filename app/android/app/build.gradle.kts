plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.fortuned"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    externalNativeBuild {
        cmake {
            path = file("../../native/CMakeLists.txt")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    // Define flavor dimensions
    flavorDimensions.add("environment")

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.fortuned"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        minSdk = 26
        
        ndk {
            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64"))
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    productFlavors {
        create("prod") {
            dimension = "environment"
            manifestPlaceholders["appHost"] = "4tnd.link"
        }
        create("stage") {
            dimension = "environment"
            manifestPlaceholders["appHost"] = "devtest.4tnd.link"
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDir("../../native")
        }
    }
}

flutter {
    source = "../.."
}
