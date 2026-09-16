import AndroidKit
import SwiftCrossUI

extension AndroidBackend: BackendFeatures.GraphicsAdapters {
    /// The one GPU an Android device has, named from its System-on-Chip.
    ///
    /// **Android exposes no way to choose a GPU, and this reports one adapter
    /// rather than none.** Reporting an empty list would make
    /// `GraphicsAdapterSelection.systemDefault` resolve to `.software` with the
    /// reason "no graphics adapter is available", and that sentence would be
    /// false on every Android device ever made.
    ///
    /// **The name is the SoC, not the GPU, and that is a deliberate retreat.**
    /// The GPU's own name comes from `glGetString(GL_RENDERER)`, which needs a
    /// current EGL context; making one here means `eglInitialize` and
    /// `eglTerminate` on `EGL_DEFAULT_DISPLAY`, which is the display the app is
    /// already rendering through. Terminating it is a documented way to break
    /// other users of the same display, and this machine cannot run Android to
    /// find out whether it does. "Qualcomm SM8350" instead of "Adreno 660" is a
    /// worse name; a black window is a worse bug.
    ///
    /// If someone with a device wants the real name, the shape is a Kotlin
    /// helper that creates a pbuffer surface on its OWN display connection and
    /// never terminates the default one. It belongs next to the other helpers in
    /// `Sources/AndroidBackend/Kotlin/`.
    ///
    /// **COMPILES HERE, since 2026-09-11.** It did not for a while, and the reason
    /// was never this file: the host toolchain was Swift 6.4 while the installed
    /// Android SDK was 6.3.3, so every Android build failed with module-format
    /// errors naming files nobody here wrote. `testapp/compile.zsh` now finds a
    /// matching toolchain and says which one it picked.
    ///
    /// Compiling is not running. Nothing in this file has been executed on a
    /// device or an emulator, and the checks below are still the checks.
    ///
    /// **自 2026-09-11 起，此處編得過。** 它曾有一段時間編不過，而理由從來不在這個檔案:主機的
    /// toolchain 是 Swift 6.4，而安裝的 Android SDK 是 6.3.3，因此每一次 Android 建置都以
    /// 「module 格式」錯誤失敗，指名的是一些此處沒有人寫過的檔案。`testapp/compile.zsh` 現在會找出
    /// 相符的 toolchain，並說出它選了哪一個。
    ///
    /// 編得過不等於跑得起來。本檔中沒有任何東西曾在裝置或模擬器上執行過，而下方那些要查的項目，
    /// 依然要查。
    ///
    ///
    /// 一台 Android 裝置所擁有的那一張 GPU，以它的 System-on-Chip 命名。
    ///
    /// **Android 沒有提供任何選擇 GPU 的方式，而此處回報一張、而不是零張。** 回報空清單會讓
    /// `GraphicsAdapterSelection.systemDefault` 解析為 `.software`，理由是「沒有可用的繪圖介面卡」
    /// ——而那句話對史上每一台 Android 裝置都是假的。
    ///
    /// **這個名字是 SoC、不是 GPU，而那是一次刻意的退讓。** GPU 自己的名字來自
    /// `glGetString(GL_RENDERER)`，那需要一個當前的 EGL context;在此處造一個，意味著要對
    /// `EGL_DEFAULT_DISPLAY` 呼叫 `eglInitialize` 與 `eglTerminate`——而那正是這個 app 正在用來算繪的
    /// 那個 display。終止它是「弄壞同一個 display 的其他使用者」的一種有記載的方式，而這台機器跑不了
    /// Android 來查明它會不會。「Qualcomm SM8350」而不是「Adreno 660」是比較差的名字;一個全黑的視窗
    /// 是比較嚴重的缺陷。
    ///
    /// 若有裝置的人想要真正的名字，形狀是一個 Kotlin 輔助類別:它在**自己的** display 連線上建立一個
    /// pbuffer surface，並且永不終止那個預設的。它該放在 `Sources/AndroidBackend/Kotlin/` 裡，與其他
    /// 輔助類別為鄰。
    ///
    public var availableAdapters: [GraphicsAdapter] {
        let build = try? JavaClass<AndroidKit.Build>()
        let name: String
        if let build, !build.SOC_MODEL.isEmpty, build.SOC_MODEL != "unknown" {
            let maker = build.SOC_MANUFACTURER
            name =
                maker.isEmpty || maker == "unknown"
                ? build.SOC_MODEL : "\(maker) \(build.SOC_MODEL)"
        } else if let build, !build.HARDWARE.isEmpty {
            // `SOC_MODEL` is API 31, and "unknown" on a device that predates it.
            // `HARDWARE` has been there since API 1 and is what an emulator
            // reports too, so a stale device still gets a name rather than a
            // blank.
            // `SOC_MODEL` 是 API 31 才有的，在早於它的裝置上會是「unknown」。`HARDWARE` 自 API 1
            // 就存在，模擬器回報的也是它——因此一台舊裝置仍然拿得到名字，而不是一片空白。
            name = build.HARDWARE
        } else {
            name = "unknown GPU"
        }
        return [GraphicsAdapter(name: name, isRemovable: false, isLowPower: false)]
    }

    /// Nothing to apply: there is one GPU and no API to point at it.
    ///
    /// `.software` is answered with `unavailable` rather than `applied`, because
    /// Android has no software rendering path a caller can ask for -- the
    /// hardware compositor draws every window. Answering `applied` would be the
    /// shape this tree keeps catching: a true-looking outcome for a request that
    /// changed nothing.
    ///
    /// 沒有東西可以套用:只有一張 GPU，而且沒有任何 API 能指名它。
    ///
    /// 對 `.software` 的回答是 `unavailable` 而非 `applied`，因為 Android 沒有呼叫端要得到的軟體算繪
    /// 路徑——每一個視窗都由硬體合成器繪製。回答 `applied` 會是這棵樹一再抓到的那個形狀:一個對
    /// 「什麼都沒有改變的要求」看起來為真的結果。
    public func applyAdapter(
        _ resolution: GraphicsAdapterResolution
    ) -> BackendFeatures.AdapterOutcome {
        guard resolution.adapter != nil else {
            return .unavailable(
                reason:
                    "Android composites every window on the GPU; there is no software path"
            )
        }
        return .alreadyActive
    }

    /// Never fires: a phone's GPU cannot be unplugged.
    /// 永遠不會觸發:一支手機的 GPU 拔不掉。
    public var adapterRemoved: (() -> Void)? {
        get { nil }
        set {}
    }
}
