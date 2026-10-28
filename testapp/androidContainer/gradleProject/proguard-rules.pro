# R8 rules for the release build (build.gradle.kts; the harness default, SCUI_ANDROID_RELEASE=0 for debug).
#
# Swift reaches Java through JNI by class and member name, which R8 cannot see,
# so anything Swift names must keep its name and members. That is all of our own
# Kotlin, swift-java's Java side and anything else that is not AndroidX, Material
# or Kotlin's runtime; and of AndroidX and Material, the classes AndroidBackend's
# Swift names directly (checked 2026-10-24 against AndroidKit's @JavaClass names:
# Chip, MaterialButtonToggleGroup, ListAdapter, Variant, plus FragmentActivity).
# The rest of AndroidX and Material is reached through our Kotlin, which R8 reads.
#
# R8 的規則，用於 release 建置。Swift 透過 JNI 以類別與成員名稱取用 Java,R8 看不到，所以 Swift 指名的一切都必須保留名稱與成員：
# 我們自己的全部 Kotlin、swift-java 的 Java 端，以及 AndroidX、Material、Kotlin runtime 以外的一切；AndroidX 與 Material
# 之中，則是 AndroidBackend 的 Swift 直接指名的類別(2026-10-24 對照 AndroidKit 的 @JavaClass 名稱確認)。其餘的 AndroidX 與
# Material 經由我們的 Kotlin 取用，R8 讀得到。

-keep class !androidx.**,!com.google.android.material.**,!kotlin.**,!kotlinx.**,** { *; }
-keep class com.google.android.material.chip.Chip { *; }
-keep class com.google.android.material.button.MaterialButtonToggleGroup { *; }
-keep class com.google.android.material.color.utilities.Variant { *; }
-keep class androidx.recyclerview.widget.ListAdapter { *; }
-keep class androidx.fragment.app.FragmentActivity { *; }
-keepclasseswithmembernames class * { native <methods>; }
-dontwarn **
