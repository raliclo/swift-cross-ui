// The Gradle half of every test app's APK, shared by all of them.
//
// Swift Bundler generated this project per app and deleted it before every
// bundle, so Gradle never reused anything and each app left ~1 GB behind. Here
// the project is one directory that stays: the Kotlin in
// Sources/AndroidBackend/Kotlin compiles once, and switching apps changes only
// what is passed in below and the libraries under src/main/jniLibs.
//
// What differs per app arrives as -P properties from testapp/package_android.zsh:
//   scuiApplicationId  dev.swiftcrossui.testapp.p12
//   scuiAppName        P12
//   scuiVersionCode    the repository's commit count, as Swift Bundler used, so
//                      an install over a bundler-built APK is not a downgrade
// and the SDK levels come from testapp/androidContainer/Bundler.android.toml,
// which stays the one place they are decided.
//
// The namespace is fixed. MainActivity therefore has one class name for every
// app, and the shim's JNI symbol with it; nothing in AndroidBackend reads the
// activity's package (checked 2026-10-05), only the application id differs.
//
// 每支測試 app APK 的 Gradle 那一半，由所有 app 共用。Swift Bundler 為每支 app 產生本專案，並在每次打包前
// 刪掉它，因此 Gradle 從未重用任何東西，每支 app 還各留下約 1 GB。這裡的專案是一個會留著的目錄:
// Sources/AndroidBackend/Kotlin 的 Kotlin 只編一次，換 app 時只改變下方傳入的值與 src/main/jniLibs 底下的
// 函式庫。每支 app 不同的部分由 testapp/package_android.zsh 以 -P 屬性傳入；SDK level 取自
// Bundler.android.toml,那裡仍是決定它們的唯一地方。namespace 固定，因此 MainActivity 與 shim 的 JNI 符號
// 對每支 app 都相同；AndroidBackend 不讀 activity 的 package(2026-10-05 查過),只有 application id 不同。
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
}

fun prop(name: String): String =
    (project.findProperty(name) as String?)
        ?: throw GradleException("missing -P$name; build through testapp/package_android.zsh")

android {
    namespace = "dev.swiftcrossui.testapp"
    compileSdk = prop("scuiCompileSdk").toInt()

    defaultConfig {
        applicationId = prop("scuiApplicationId")
        minSdk = prop("scuiMinSdk").toInt()
        targetSdk = prop("scuiTargetSdk").toInt()
        versionCode = prop("scuiVersionCode").toInt()
        versionName = "0.1.0"
        resValue("string", "app_name", prop("scuiAppName"))

        ndk {
            abiFilters.addAll(setOf("arm64-v8a"))
        }
    }

    sourceSets {
        getByName("main") {
            // AndroidBackend's Kotlin, synced in by package_android.zsh.
            // AndroidBackend 的 Kotlin,由 package_android.zsh 同步進來。
            java.srcDirs("src/main/kotlin")
        }
    }

    packaging {
        jniLibs {
            // The libraries are packaged as built; .swift_ast is removed by
            // package_android.zsh, and Gradle's own strip would take the rest
            // of the symbols that crash reports need.
            // 函式庫照建置結果打包;.swift_ast 由 package_android.zsh 移除，而 Gradle 自己的 strip
            // 會把當機報告需要的其餘符號也拿掉。
            keepDebugSymbols += "arm64-v8a/*.so"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(libs.appcompat)
    implementation(libs.material)
    implementation(libs.activity)
    implementation(libs.constraintlayout)
}
