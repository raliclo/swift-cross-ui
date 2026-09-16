import AndroidKit
import SwiftJava

@JavaClass(
    "dev.swiftcrossui.androidbackend.TableContainer",
    extends: AndroidKit.ViewGroup.self
)
class TableContainer: JavaObject {
    @JavaMethod
    @_nonoverride convenience init(
        _ activity: Activity?,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod
    func clearHeaders()

    @JavaMethod
    func addHeader(_ view: AndroidKit.View?)

    @JavaMethod
    func clearCells()

    @JavaMethod
    func addCell(_ view: AndroidKit.View?)

    @JavaMethod
    func addRowHeight(_ height: Int32)

    @JavaMethod
    func setHeaderHeight(_ height: Int32)

    // MARK: Row selection (#125)

    /// -1 for nothing selected. `TableContainer.kt` says why the boundary
    /// carries a sentinel rather than a boxed `Integer`.
    /// -1 代表沒有選取。為何這個邊界帶的是一個哨兵值而非裝箱的 `Integer`,見 `TableContainer.kt`。
    @JavaMethod
    func setSelectedRow(_ row: Int32)

    @JavaMethod
    func getTappedRow() -> Int32

    @JavaMethod
    func setSelectionAction(_ action: SwiftAction?)
}
