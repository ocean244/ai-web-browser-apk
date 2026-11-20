import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) load(f.inputStream())
}

android {
    namespace = "pl.tomaszewski.aiweb"
    compileSdk = 34

    defaultConfig {
        applicationId = "pl.tomaszewski.aiweb"
        minSdk = 26
        targetSdk = 34
        versionCode = 2
        versionName = "1.1.0-release"
    }

    signingConfigs {
        create("release") {
            val envStoreFile = System.getenv("RELEASE_STORE_FILE")
            val storePath = if (!envStoreFile.isNullOrBlank()) envStoreFile
            else localProps.getProperty("RELEASE_STORE_FILE", "keystore/release.jks")
            storeFile = file(storePath)

            storePassword = System.getenv("RELEASE_STORE_PASSWORD")
                ?.takeIf { it.isNotBlank() }
                ?: localProps.getProperty("RELEASE_STORE_PASSWORD", "AIWebRelease2026!")

            keyAlias = System.getenv("RELEASE_KEY_ALIAS")
                ?.takeIf { it.isNotBlank() }
                ?: localProps.getProperty("RELEASE_KEY_ALIAS", "aiweb_release_key")

            keyPassword = System.getenv("RELEASE_KEY_PASSWORD")
                ?.takeIf { it.isNotBlank() }
                ?: localProps.getProperty("RELEASE_KEY_PASSWORD", "AIWebRelease2026!")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.webkit:webkit:1.11.0")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}
