plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val releaseKeystore = System.getenv("BOOX_SEND_KEYSTORE")
val releaseKeystorePassword = System.getenv("BOOX_SEND_KEYSTORE_PASSWORD")
val releaseKeyAlias = System.getenv("BOOX_SEND_KEY_ALIAS")
val releaseKeyPassword = System.getenv("BOOX_SEND_KEY_PASSWORD")

android {
    namespace = "com.aliumutaltas.booxsend"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.aliumutaltas.booxsend"
        minSdk = 31
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
    }

    signingConfigs {
        if (
            !releaseKeystore.isNullOrBlank() &&
            !releaseKeystorePassword.isNullOrBlank() &&
            !releaseKeyAlias.isNullOrBlank() &&
            !releaseKeyPassword.isNullOrBlank()
        ) {
            create("releaseFromEnvironment") {
                storeFile = file(releaseKeystore)
                storePassword = releaseKeystorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfigs.findByName("releaseFromEnvironment")?.let { signingConfig = it }
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.documentfile:documentfile:1.0.1")
    testImplementation("junit:junit:4.13.2")
}
