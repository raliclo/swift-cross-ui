/// What a drag reports.
///
/// **Three points and no velocity.** SwiftUI's value also carries
/// `predictedEndTranslation`, which every platform computes differently from a
/// velocity none of them expose the same way; a field that means something
/// slightly different on each of five backends is worse than one that is absent.
///
/// 一次拖曳所回報的東西。
///
/// **三個點，沒有速度。** SwiftUI 的值還帶著 `predictedEndTranslation`，而那是每個平台各自從「它們
/// 揭露方式都不同的速度」算出來的;一個「在五個 backend 上各自略有不同意義」的欄位，比一個不存在的
/// 欄位更糟。
public struct DragGestureValue: Equatable, Sendable {
    /// Where the drag began, in the gesture target's own coordinates.
    /// 拖曳開始之處，以手勢目標自身的座標表示。
    public var startLocation: SIMD2<Double>

    /// Where the pointer is now, in the same coordinates.
    /// 指標現在的位置，同一套座標。
    public var location: SIMD2<Double>

    /// `location - startLocation`, which is the number nearly every caller
    /// actually wants.
    /// 即 `location - startLocation`——那才是幾乎每個呼叫端真正想要的數字。
    public var translation: SIMD2<Double> {
        location - startLocation
    }

    public init(startLocation: SIMD2<Double>, location: SIMD2<Double>) {
        self.startLocation = startLocation
        self.location = location
    }
}

/// What a magnify reports.
///
/// `1.0` means unchanged, `2.0` means twice the size, and it is CUMULATIVE from
/// the start of the gesture rather than per event. Per-event deltas are what
/// two of the five platforms hand over natively, and a caller who multiplies
/// them together to get the total ends up with a different number on each -- so
/// the accumulation happens in the backends, once, where the platform's own
/// semantics are known.
///
/// 一次縮放所回報的東西。
///
/// `1.0` 表示未改變、`2.0` 表示兩倍大，而且它是**自手勢開始起的累計值**，不是逐事件的差量。五個平台
/// 中有兩個原生交出的是逐事件差量，而一個「把它們相乘以取得總量」的呼叫端，在每個平台上會得到不同的
/// 數字——因此累計這件事發生在各個 backend 內部、只做一次，在那裡才知道該平台自身的語意。
public struct MagnifyGestureValue: Equatable, Sendable {
    public var magnification: Double

    public init(magnification: Double) {
        self.magnification = magnification
    }
}

/// What a rotate reports, in radians, cumulative from the start of the gesture.
///
/// Radians rather than an `Angle` type, because this package has no `Angle` and
/// inventing one for a single field would be a bigger decision than this is.
/// Positive is clockwise on every backend -- the platforms disagree about that,
/// and each implementation says which way it had to flip.
///
/// 一次旋轉所回報的東西，單位為弧度，自手勢開始起累計。
///
/// 使用弧度而非某個 `Angle` 型別，因為本套件沒有 `Angle`，而為了單一個欄位發明一個，會是一個比這件事
/// 本身更大的決定。在**每一個** backend 上正值都代表順時針——各平台在這件事上並不一致，而每一份實作
/// 都會說明它必須翻轉的是哪一邊。
public struct RotateGestureValue: Equatable, Sendable {
    public var radians: Double

    public init(radians: Double) {
        self.radians = radians
    }
}

extension BackendFeatures {
    /// A one-finger drag, or a mouse press-and-move.
    ///
    /// **Three protocols rather than one, matching ``TapGestures`` and
    /// ``HoverGestures``.** A single `ContinuousGestures` would make a backend
    /// that can drag but not rotate unable to declare that, and Android is
    /// exactly that case until a rotation detector is written by hand: Android
    /// ships `GestureDetector` and `ScaleGestureDetector` and has no rotation
    /// equivalent at all.
    ///
    /// 一指拖曳，或滑鼠按住並移動。
    ///
    /// **三個協定而非一個，與 ``TapGestures``、``HoverGestures`` 一致。** 單一個
    /// `ContinuousGestures` 會讓「能拖曳但不能旋轉」的 backend 無從表達;而 Android 正是那種情況——
    /// 直到有人手寫一個旋轉偵測器為止:Android 提供 `GestureDetector` 與 `ScaleGestureDetector`，
    /// 而完全沒有旋轉的對應物。
    @MainActor
    public protocol DragGestures: Core {
        func createDragGestureTarget(wrapping child: Widget) -> Widget

        func updateDragGestureTarget(
            _ target: Widget,
            environment: EnvironmentValues,
            onChange: @escaping (DragGestureValue) -> Void,
            onEnd: @escaping (DragGestureValue) -> Void
        )
    }

    /// A pinch, or a trackpad magnify.
    /// 一次捏合，或觸控板上的縮放。
    @MainActor
    public protocol MagnifyGestures: Core {
        func createMagnifyGestureTarget(wrapping child: Widget) -> Widget

        func updateMagnifyGestureTarget(
            _ target: Widget,
            environment: EnvironmentValues,
            onChange: @escaping (MagnifyGestureValue) -> Void,
            onEnd: @escaping (MagnifyGestureValue) -> Void
        )
    }

    /// A two-finger rotation.
    /// 兩指旋轉。
    @MainActor
    public protocol RotateGestures: Core {
        func createRotateGestureTarget(wrapping child: Widget) -> Widget

        func updateRotateGestureTarget(
            _ target: Widget,
            environment: EnvironmentValues,
            onChange: @escaping (RotateGestureValue) -> Void,
            onEnd: @escaping (RotateGestureValue) -> Void
        )
    }
}
