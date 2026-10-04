// One Gradle project for every test app. testapp/package_android.zsh copies
// this directory into testapp/.compile-work-android/gradleProject and builds it
// there, passing the app in as -P properties. See build.gradle.kts.
// 所有測試 app 共用的一個 Gradle 專案。testapp/package_android.zsh 把本目錄複製到
// testapp/.compile-work-android/gradleProject 並在那裡建置，app 以 -P 屬性傳入。見 build.gradle.kts。
pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "TestApps"
