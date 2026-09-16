import AndroidContent
import AndroidKit
import SwiftJava

/// A delegate that is notified of the activity's lifecycle changes.
///
/// Since it's (currently) not possible to use a custom subclass of `FragmentActivity` in
/// SwiftCrossUI apps, this allows you to act on lifecycle events instead. All methods have default
/// implementations that do nothing.
///
/// - Important: Due to the different mechanisms Jetpack provides for installing listeners, some of
/// these methods are called within the corresponding activity methods, while others are called
/// shortly after the corresponding activity methods.
///
/// Methods called during the corresponding activity method are:
/// - ``onCreate(of:env:)``
/// - ``onConfigurationChanged(for:to:env:)``
/// - ``onNewIntent(for:intent:env:)``
///
/// Methods called after the corresponding activity method are:
/// - ``onStart(of:env:)``
/// - ``onResume(of:env:)``
/// - ``onPause(of:env:)``
/// - ``onStop(of:env:)``
/// - ``onDestroy(of:env:)``
public protocol ActivityDelegate { // swiftlint:disable:this class_delegate_protocol
    func onCreate(of activity: FragmentActivity, env: JNIEnvironment?)
    func onStart(of activity: FragmentActivity, env: JNIEnvironment?)
    func onResume(of activity: FragmentActivity, env: JNIEnvironment?)
    func onPause(of activity: FragmentActivity, env: JNIEnvironment?)
    func onStop(of activity: FragmentActivity, env: JNIEnvironment?)
    func onDestroy(of activity: FragmentActivity, env: JNIEnvironment?)

    func onConfigurationChanged(
        for activity: FragmentActivity,
        to configuration: AndroidKit.Configuration,
        env: JNIEnvironment?
    )
    func onNewIntent(
        for activity: FragmentActivity,
        intent: AndroidKit.Intent,
        env: JNIEnvironment?
    )
}

extension ActivityDelegate {
    public func onCreate(of _: FragmentActivity, env _: JNIEnvironment?) {}
    public func onStart(of _: FragmentActivity, env _: JNIEnvironment?) {}
    public func onResume(of _: FragmentActivity, env _: JNIEnvironment?) {}
    public func onPause(of _: FragmentActivity, env _: JNIEnvironment?) {}
    public func onStop(of _: FragmentActivity, env _: JNIEnvironment?) {}
    public func onDestroy(of _: FragmentActivity, env _: JNIEnvironment?) {}

    public func onConfigurationChanged(
        for _: FragmentActivity,
        to _: AndroidKit.Configuration,
        env _: JNIEnvironment?
    ) {}
    public func onNewIntent(
        for _: FragmentActivity,
        intent _: AndroidKit.Intent,
        env _: JNIEnvironment?
    ) {}
}

/// Retroactive `Sendable` for the two AndroidKit types the JNI entry points
/// receive.
///
/// **Retroactive is the accurate word and the reason to be careful**: these
/// belong to AndroidKit, and if it ever declares its own conformance these
/// lines become a duplicate-conformance error. That is a build failure, which
/// is the failure mode to want -- it is loud, and it means the annotation is no
/// longer needed.
///
/// They are here for the same reason ``ActivityListener`` needs it: swift-java's
/// `@JavaMethod` expansion sends every parameter across an isolation boundary,
/// and `Intent` and `Configuration` are Java handles. Both arrive on the Android
/// main thread from the framework and are read inside
/// `MainActor.assumeIsolated` a line later.
///
/// 為兩個「JNI 進入點會收到」的 AndroidKit 型別做追溯性的 `Sendable` 宣告。
///
/// **「追溯性」這個詞是精準的,也正是要小心的理由**:這兩個型別屬於 AndroidKit,而若它日後自行宣告
/// 了同樣的 conformance,這幾行就會變成「重複 conformance」的錯誤。那是一次建置失敗——而那正是我們
/// 想要的失敗方式:它很大聲,而且它代表這個標註已經不再需要了。
///
/// 它們在此的理由與 ``ActivityListener`` 需要它的理由相同:swift-java 的 `@JavaMethod` 展開會把
/// **每一個參數**送過一個隔離邊界,而 `Intent` 與 `Configuration` 都是 Java handle。兩者都是由框架
/// 在 Android 主執行緒上送達的,並在下一行就進入 `MainActor.assumeIsolated` 被讀取。
///
/// **They must sit ABOVE the `@JavaClass` attribute below, not between it and
/// the class it decorates.** Placed in between, that attribute -- an extension
/// macro -- attaches to the first extension instead, and the compiler says
/// `'extension' macro cannot be attached to extension`. The message is exact
/// and reads like a complaint about these lines; it is a complaint about where
/// they are.
/// **它們必須放在下方 `@JavaClass` 屬性的**上面**,而不是夾在那個屬性與它所修飾的類別之間。** 夾在
/// 中間時,那個屬性——一個 extension macro——會改為附著到第一個 extension 上,而編譯器會說
/// `'extension' macro cannot be attached to extension`。那句訊息是精準的,而且讀起來像是在抱怨這幾行
/// 本身;它抱怨的是它們**放在哪裡**。
extension AndroidContent.Intent: @unchecked Sendable {}
extension AndroidContent.Configuration: @unchecked Sendable {}

@JavaClass("dev.swiftcrossui.androidbackend.ActivityListener")

/// `@unchecked Sendable` so `@JavaMethod` can expand under Swift 6.
///
/// **The requirement comes from the macro, not from this class.** swift-java
/// expands `@JavaMethod` inside a `@JavaImplementation` extension into the JNI
/// entry point Java calls, and that generated code sends `self` across an
/// isolation boundary -- nine errors, all of them in the expansion rather than
/// in anything written here. A `JavaObject` is a handle and can never be
/// `Sendable` on its own.
///
/// **Why the assertion holds for THIS class.** Every method below is an Android
/// activity lifecycle callback, and Android calls those on the main thread --
/// that is the contract `Activity` is documented under, not an observation. And
/// each one immediately enters `MainActor.assumeIsolated`, so the handle is
/// touched on exactly one thread either way. A JNI call arriving on some other
/// thread would already have been a bug before this annotation existed.
///
/// It is on this class alone. The other five `@JavaImplementation` types in
/// this module compile without it, which is the check that keeps the annotation
/// from spreading on habit.
///
/// 標為 `@unchecked Sendable`,好讓 `@JavaMethod` 能在 Swift 6 底下展開。
///
/// **這個要求來自那個巨集,不是來自這個類別。** swift-java 會把 `@JavaImplementation` extension 裡的
/// `@JavaMethod` 展開成「Java 會呼叫的那個 JNI 進入點」,而那段產生出來的程式碼會把 `self` 送過一個
/// 隔離邊界——九個錯誤,全都在展開的程式碼裡,而不在此處手寫的任何東西上。一個 `JavaObject` 是一個
/// handle,它自己永遠不可能是 `Sendable`。
///
/// **為何這個斷言對**這個**類別成立。** 底下每一個方法都是 Android 的 activity 生命週期回呼,而
/// Android 是在主執行緒上呼叫它們的——那是 `Activity` 所依據的**文件契約**,不是一項觀察。而且每一個
/// 方法都立刻進入 `MainActor.assumeIsolated`,因此無論如何,那個 handle 都只會被單一執行緒碰到。
/// 一個從其他執行緒抵達的 JNI 呼叫,在這個標註存在之前就已經是一個 bug 了。
///
/// 它只加在這一個類別上。本模組中另外五個 `@JavaImplementation` 型別不需要它就編得過,而那正是
/// 「阻止這個標註因習慣而擴散」的那道檢查。
class ActivityListener: JavaObject, @unchecked Sendable {
    @JavaMethod
    convenience init(
        _ activity: FragmentActivity?,
        _ delegate: SwiftObject?,
        environment: JNIEnvironment? = nil
    )

    @JavaMethod
    func getActivity() -> FragmentActivity!

    @JavaMethod
    func getDelegate() -> SwiftObject!
}

extension ActivityListener {
    func getCastedDelegate() -> any ActivityDelegate {
        getDelegate().value() as! any ActivityDelegate
    }
}

@JavaImplementation("dev.swiftcrossui.androidbackend.ActivityListener")
extension ActivityListener {
    @JavaMethod
    func onStart() {
        MainActor.assumeIsolated {
            getCastedDelegate().onStart(of: getActivity(), env: AndroidBackend.env)
        }
    }

    @JavaMethod
    func onResume() {
        MainActor.assumeIsolated {
            getCastedDelegate().onResume(of: getActivity(), env: AndroidBackend.env)
        }
    }

    @JavaMethod
    func onPause() {
        MainActor.assumeIsolated {
            getCastedDelegate().onPause(of: getActivity(), env: AndroidBackend.env)
        }
    }

    @JavaMethod
    func onStop() {
        MainActor.assumeIsolated {
            getCastedDelegate().onStop(of: getActivity(), env: AndroidBackend.env)
        }
    }

    @JavaMethod
    func onDestroy() {
        MainActor.assumeIsolated {
            getCastedDelegate().onDestroy(of: getActivity(), env: AndroidBackend.env)
        }
    }

    @JavaMethod
    func onNewIntent(_ intent: AndroidKit.Intent?) {
        MainActor.assumeIsolated {
            getCastedDelegate().onNewIntent(
                for: getActivity(),
                intent: intent!,
                env: AndroidBackend.env
            )
        }
    }

    @JavaMethod
    func onConfigurationChanged(_ configuration: AndroidKit.Configuration?) {
        MainActor.assumeIsolated {
            getCastedDelegate().onConfigurationChanged(
                for: getActivity(),
                to: configuration!,
                env: AndroidBackend.env
            )
        }
    }
}
