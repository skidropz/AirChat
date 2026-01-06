plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
}

android {
    namespace = "com.example.skychatlocal"
    compileSdk {
        version = release(36)
    }

    defaultConfig {
        applicationId = "com.skidropz.airchat"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = "11"
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.material)
    implementation(libs.androidx.activity)
    implementation(libs.androidx.constraintlayout)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    // Biblioteci standard Android
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
    implementation("androidx.constraintlayout:constraintlayout:2.1.4")
    dependencies {
        // Varianta corectă pentru Kotlin DSL (.kts)
        implementation("androidx.core:core-splashscreen:1.0.1")
        dependencies {
            implementation("com.google.android.gms:play-services-nearby:19.0.0")
        }
    }

    // --- ADĂUGĂM ACESTE LINII PENTRU SERVER ---
    // NanoHTTPD Core (pentru a servi HTML/CSS)
    implementation("org.nanohttpd:nanohttpd:2.3.1")
    // NanoHTTPD WebSocket (pentru chat în timp real)
    implementation("org.nanohttpd:nanohttpd-websocket:2.3.1")
    implementation("com.google.zxing:core:3.5.1")

}