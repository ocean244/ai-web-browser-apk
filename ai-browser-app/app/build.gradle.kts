plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val keystorePath = System.getenv("ANDROID_KEYSTORE_PATH")
val storePasswordEnv = System.getenv("ANDROID_STORE_PASSWORD")
val keyAliasEnv = System.getenv("ANDROID_KEY_ALIAS")
val keyPasswordEnv = System.getenv("ANDROID_KEY_PASSWORD")

android {
    namespace = "com.aibrowser.core"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.aibrowser.core"
        minSdk = 26
        targetSdk = 35
        versionCode = 4
        versionName = "4.0.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        if (!keystorePath.isNullOrBlank() && !storePasswordEnv.isNullOrBlank() && !keyAliasEnv.isNullOrBlank() && !keyPasswordEnv.isNullOrBlank()) {
            create("release") {
                storeFile = file(keystorePath)
                storePassword = storePasswordEnv
                keyAlias = keyAliasEnv
                keyPassword = keyPasswordEnv
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
        debug {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.constraintlayout:constraintlayout:2.2.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    testImplementation("junit:junit:4.13.2")
}
