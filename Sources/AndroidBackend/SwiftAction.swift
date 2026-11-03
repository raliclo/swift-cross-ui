import SwiftJava

/// A Java class that allows us to pass Swift `() -> Void` closures to Java code.
@JavaClass("dev.swiftcrossui.androidbackend.SwiftAction")
open class SwiftAction: JavaObject {
    @JavaMethod
    @_nonoverride public convenience init(
        closureObject: SwiftObject?,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod
    open func getClosureObject() -> SwiftObject?
}

@JavaImplementation("dev.swiftcrossui.androidbackend.SwiftAction")
extension SwiftAction {
    @JavaMethod
    public func callSwift() {
        guard let object = getClosureObject() else {
            log("Warning: SwiftAction wasn't holding a closure at all")
            return
        }

        let value = object.value()
        guard let action = value as? () -> Void else {
            log(
                "Warning: SwiftAction wasn't holding an action closure; got \(type(of: value))"
            )
            return
        }

        action()
    }
}

extension SwiftAction {
    convenience init(environment: JNIEnvironment? = nil, action: @escaping () -> Void) {
        let object = SwiftObject(action, environment: environment)
        self.init(closureObject: object, environment: environment)
    }
}

/// A `java.lang.ref.WeakReference`, for an action that has to reach back to the
/// view it is installed on.
///
/// The view holds its `SwiftAction`, and a closure that captured the view's
/// Swift wrapper would hold a JNI global reference to the view: Java's
/// collector cannot see through Swift's reference count, so the view, the
/// action and the closure would keep one another alive for the rest of the
/// process. A Swift `weak` does not help -- each wrapper is made for one call
/// and released straight away -- so the weak link has to be on the Java side.
/// Resolve it with `get()?.as(...)`; `nil` means the view has been collected.
///
/// 一個 `java.lang.ref.WeakReference`,給必須回頭找到「自己被裝在哪個 view 上」的 action 用。
///
/// view 持有它的 `SwiftAction`,而捕捉了該 view 之 Swift 包裝物件的 closure 會持有指向該 view 的 JNI
/// 全域參照:Java 的回收器看不穿 Swift 的參照計數，於是 view、action 與 closure 會互相讓對方一直活到
/// 行程結束。Swift 的 `weak` 沒有幫助——每個包裝物件都是為一次呼叫而建、隨即釋放——所以弱連結必須在 Java
/// 那一側。以 `get()?.as(...)` 取用;`nil` 代表 view 已被回收。
@JavaClass("java.lang.ref.WeakReference")
class JavaWeakReference: JavaObject {
    @JavaMethod
    @_nonoverride convenience init(
        _ referent: JavaObject?,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod
    func get() -> JavaObject?
}
