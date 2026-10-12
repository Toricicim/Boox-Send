plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val releaseKeystore = System.getenv("BOOX_SEND_KEYSTORE")
val releaseKeystorePassword = System.getenv("BOOX_SEND_KEYSTORE_PASSWORD")
val releaseKeyAlias = System.getenv("BOOX_SEND_KEY_ALIAS")
val releaseKeyPassword = System.getenv("BOOX_SEND_KEY_PASSWORD")
val appVersion = "1.0.7"
val appVersionCode = 8
val updaterFixture = providers.gradleProperty("booxUpdaterFixture").orNull == "true"
check(!updaterFixture || (gradle.startParameter.taskNames.isNotEmpty() && gradle.startParameter.taskNames.all {
    it.substringAfterLast(':') in setOf("assembleDebug", "testDebugUnitTest", "clean")
})) {
    "Updater fixture builds are debug-only."
}

android {
    namespace = "com.aliumutaltas.booxsend"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.aliumutaltas.booxsend"
        minSdk = 31
        targetSdk = 35
        versionCode = appVersionCode + if (updaterFixture) 1 else 0
        versionName = if (updaterFixture) appVersion.split('.').let { "${it[0]}.${it[1]}.${it[2].toInt() + 1}" } else appVersion
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
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
    sourceSets.getByName("androidTest").assets.srcDir(layout.buildDirectory.dir("generated/updater-test-assets"))
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.documentfile:documentfile:1.0.1")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("junit:junit:4.13.2")
}
