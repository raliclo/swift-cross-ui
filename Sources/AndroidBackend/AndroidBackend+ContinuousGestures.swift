import AndroidKit
import SwiftCrossUI

extension AndroidBackend: BackendFeatures.DragGestures,
    BackendFeatures.MagnifyGestures,
    BackendFeatures.RotateGestures
{
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
    public func createDragGestureTarget(wrapping child: Widget) -> Widget {
        container(wrapping: child, kind: 0)
    }

    public func updateDragGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (DragGestureValue) -> Void,
        onEnd: @escaping (DragGestureValue) -> Void
    ) {
        let target = target.as(ContinuousGestureContainer.self)!
        let value = { @MainActor in
            DragGestureValue(
                startLocation: SIMD2(Double(target.getStartX()), Double(target.getStartY())),
                location: SIMD2(Double(target.getCurrentX()), Double(target.getCurrentY()))
            )
        }
        target.setOnChange(
            environment.isEnabled
                ? SwiftAction(action: { MainActor.assumeIsolated { onChange(value()) } }) : nil
        )
        target.setOnEnd(
            environment.isEnabled
                ? SwiftAction(action: { MainActor.assumeIsolated { onEnd(value()) } }) : nil
        )
    }

    public func createMagnifyGestureTarget(wrapping child: Widget) -> Widget {
        container(wrapping: child, kind: 1)
    }

    public func updateMagnifyGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (MagnifyGestureValue) -> Void,
        onEnd: @escaping (MagnifyGestureValue) -> Void
    ) {
        let target = target.as(ContinuousGestureContainer.self)!
        let value = { @MainActor in
            MagnifyGestureValue(magnification: Double(target.getMagnification()))
        }
        target.setOnChange(
            environment.isEnabled
                ? SwiftAction(action: { MainActor.assumeIsolated { onChange(value()) } }) : nil
        )
        target.setOnEnd(
            environment.isEnabled
                ? SwiftAction(action: { MainActor.assumeIsolated { onEnd(value()) } }) : nil
        )
    }

    public func createRotateGestureTarget(wrapping child: Widget) -> Widget {
        container(wrapping: child, kind: 2)
    }

    public func updateRotateGestureTarget(
        _ target: Widget,
        environment: EnvironmentValues,
        onChange: @escaping (RotateGestureValue) -> Void,
        onEnd: @escaping (RotateGestureValue) -> Void
    ) {
        let target = target.as(ContinuousGestureContainer.self)!
        let value = { @MainActor in RotateGestureValue(radians: Double(target.getRadians())) }
        target.setOnChange(
            environment.isEnabled
                ? SwiftAction(action: { MainActor.assumeIsolated { onChange(value()) } }) : nil
        )
        target.setOnEnd(
            environment.isEnabled
                ? SwiftAction(action: { MainActor.assumeIsolated { onEnd(value()) } }) : nil
        )
    }

    private func container(wrapping child: Widget, kind: Int32) -> Widget {
        let container = ContinuousGestureContainer(
            context: Self.activity,
            kind: kind
        )
        container.addView(child)
        return container.as(AndroidKit.View.self)!
    }
}
