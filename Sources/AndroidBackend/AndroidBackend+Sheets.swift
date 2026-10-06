import AndroidKit
@_spi(Backends) import SwiftCrossUI

extension AndroidBackend: BackendFeatures.Sheets {
    public typealias Sheet = CustomSheet

    public func createSheet(content: Widget) -> CustomSheet {
        CustomSheet(content, environment: Self.env)
    }

    public func size(ofSheet sheet: CustomSheet) -> SIMD2<Int> {
        if let content = sheet.getContent() {
            let width = helpers.getSafeWindowWidth(Self.activity)
            let widthMeasureSpec = (width & 0x3FFFFFFF) | 0x40000000
            content.measure(widthMeasureSpec, 0x3FFFFFFF)
            let density = content.getResources().getDisplayMetrics().density
            let height = Float(content.getMeasuredHeight()) / density
            return SIMD2(Int(width), Int(height.rounded(.up)))
        } else {
            return .zero
        }
    }

    public func presentSheet(_ sheet: CustomSheet, window: Window, parentSheet: CustomSheet?) {
        let fragmentManager =
            parentSheet?.getChildFragmentManager() ?? Self.activity.as(FragmentActivity.self)!
                .getSupportFragmentManager()
        sheet.show(fragmentManager, "CustomSheet")
    }

    public func dismissSheet(_ sheet: CustomSheet, window: Window, parentSheet: CustomSheet?) {
        sheet.dismiss()
    }

    public func updateSheet(
        _ sheet: CustomSheet,
        window: Window,
        environment: EnvironmentValues,
        size: SIMD2<Int>,
        onDismiss: @escaping () -> Void,
        cornerRadius: Double?,
        detents: [PresentationDetent],
        dragIndicatorVisibility: Visibility,
        backgroundColor: SwiftCrossUI.Color.Resolved?,
        interactiveDismissDisabled: Bool
    ) {
        // Corner radius, detents and the drag indicator: see CustomSheet.kt.
        // 圓角、detents 與拖曳指示器：見 CustomSheet.kt。

        sheet.setOnDismissListener(SwiftAction(environment: Self.env, action: onDismiss))

        let backgroundColorInt =
            if let backgroundColor {
                backgroundColor.asColorInt()
            } else {
                switch environment.colorScheme {
                    case .dark:
                        // The default sheet background color in dark mode is a grayish color, not
                        // black, but there doesn't seem to be a publicly-exposed resource ID for it
                        // either. This was color-picked from an emulator.
                        Int32(bitPattern: 0xff25232b)
                    case .light:
                        // white
                        Int32(bitPattern: 0xffffffff)
                }
            }

        // Heights in dp, as the rest of this backend measures. `.medium` is half
        // the window and `.large` all of it, as on UIKit. Material has three
        // resting states, so more than three detents become the smallest, the
        // largest and the one nearest their middle.
        // 以 dp 表示的高度，與本 backend 其他地方相同。`.medium` 是視窗的一半,`.large` 是整個，與 UIKit 相同。
        // Material 只有三個停靠狀態，因此超過三個 detent 時取最小、最大，以及最接近兩者中間的那一個。
        let windowHeight = Double(helpers.getSafeWindowHeight(Self.activity))
        var heights = Array(
            Set(
                detents.map { detent -> Double in
                    switch detent {
                        case .medium: windowHeight / 2
                        case .large: windowHeight
                        case .fraction(let fraction): windowHeight * fraction
                        case .height(let height): height
                    }
                }
                .map { min(max($0, 0), windowHeight) }
            )
        ).sorted()
        if heights.count > 3 {
            let middle = (heights.first! + heights.last!) / 2
            let nearest = heights.dropFirst().dropLast().min { abs($0 - middle) < abs($1 - middle) }!
            heights = [heights.first!, nearest, heights.last!]
        }
        func detent(_ index: Int) -> Float {
            index < heights.count ? Float(heights[index]) : -1
        }

        // `.automatic` shows the handle when there is more than one detent to
        // drag between, the rule UIKitBackend follows.
        // `.automatic`:有一個以上的 detent 可拖曳時才顯示把手，與 UIKitBackend 的規則相同。
        let showsDragHandle =
            switch dragIndicatorVisibility {
                case .visible: true
                case .hidden: false
                case .automatic: heights.count > 1
            }

        sheet.update(
            !interactiveDismissDisabled,
            backgroundColorInt,
            cornerRadius.map { Float($0) } ?? -1,
            detent(0),
            detent(1),
            detent(2),
            showsDragHandle
        )
    }
}
