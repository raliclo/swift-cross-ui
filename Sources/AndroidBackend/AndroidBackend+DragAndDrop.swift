import AndroidKit
import Foundation
import SwiftJava

@_spi(Backends) import SwiftCrossUI

/// Receiving a drop on Android.
///
/// `createDropTarget(wrapping:)` is not overridden: the protocol's default
/// returns the child unwrapped, and here that is right rather than lazy --
/// Android's drag listener goes on any view, so there is nothing to wrap and no
/// extra level for the layout system to have to size.
///
/// What is emphatically not taken from the defaults is `updateDropTarget`,
/// whose default ignores the request. A backend that took both would conform,
/// stop crashing, and never receive anything. See `DropListener.kt`.
///
/// 在 Android 上接收 drop。
///
/// 此處未覆寫 `createDropTarget(wrapping:)`：該 protocol 的預設實作會原封不動地回傳子元件，而在
/// 此處那是正確的做法而非偷懶——Android 的 drag listener 可以掛在任何 view 上，因此沒有東西需要
/// 包裹，也不會多出一層要讓版面系統去決定尺寸。
///
/// 明確地**不**採用預設實作的是 `updateDropTarget`，其預設行為是忽略請求。一個兩者都採用預設的
/// backend 會宣稱符合 conformance、不再崩潰，然後什麼都收不到。見 `DropListener.kt`。
extension AndroidBackend: BackendFeatures.DragAndDrop {
    public func updateDropTarget(
        _ dropTarget: Widget,
        acceptedTypes: [DropType],
        environment: EnvironmentValues,
        onHover: @escaping (Bool) -> Void,
        onDrop: @escaping ([DropItem]) -> Bool
    ) {
        let listener = DropListener(Self.activity, environment: Self.env)

        // Before the listener is attached, because ACTION_DRAG_STARTED is
        // answered from this string and a target that answers false is not
        // offered the rest of the gesture.
        // 在附加此 listener 之前設定，因為 ACTION_DRAG_STARTED 是依據這個字串來回答的，而一個
        // 回答 false 的目標不會再被提供這次手勢的其餘部分。
        listener.setAcceptedTypes(
            acceptedTypes.map(\.identifier).joined(separator: "\n")
        )

        listener.setHoverAction(
            SwiftAction(environment: Self.env) {
                onHover(listener.isHovering())
            }
        )

        listener.setDropAction(
            SwiftAction(environment: Self.env) {
                // Two parallel newline-separated lists rather than one
                // structured payload, because the alternative is a JNI type
                // per field. `split(separator:omittingEmptySubsequences: false)`
                // so a dropped empty string keeps its place in the pairing.
                //
                // 使用兩份平行的、以換行分隔的清單，而非單一的結構化承載，因為另一種做法是為每個
                // 欄位建立一個 JNI 型別。使用
                // `split(separator:omittingEmptySubsequences: false)`，使一個被拖入的空字串仍能
                // 在配對中保有自己的位置。
                let types = listener.getDroppedTypes()
                    .split(separator: "\n", omittingEmptySubsequences: false)
                let values = listener.getDroppedValues()
                    .split(separator: "\n", omittingEmptySubsequences: false)

                let items = zip(types, values).map { type, value in
                    DropItem(
                        type: DropType(String(type)),
                        data: Data(String(value).utf8)
                    )
                }

                listener.setDropAccepted(onDrop(items))
            }
        )

        dropTarget.setOnDragListener(
            listener.as(AndroidView.View.OnDragListener.self)
        )
    }
}
