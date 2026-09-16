@_spi(Backends) import SwiftCrossUI
import AndroidKit
import SwiftJava
import Foundation

extension AndroidKit.SharedPreferences {
    // The generated binding isn't marked `throws` and doesn't have the correct optionality.
    @JavaMethod
    func getString(key: String, defaultValue: JavaString?) throws -> JavaString?
}

// swiftlint:disable force_try
public struct SharedPreferencesAppStorageProvider: AppStorageProvider {
    /// `nonisolated(unsafe)` because `SharedPreferences` is a Java object handle
    /// and cannot be `Sendable`, while `AppStorageProvider` is.
    ///
    /// **What makes the assertion true is Android's own guarantee, not this
    /// annotation.** `SharedPreferences` is documented as thread-safe: a single
    /// instance is shared per name per process and its readers and writers are
    /// synchronised inside the framework. So the handle crossing a thread is
    /// exactly what the API is built for.
    ///
    /// The one thing it does NOT cover is a second process, which the docs also
    /// say: `MODE_MULTI_PROCESS` is deprecated and unreliable. This provider
    /// opens with `MODE_PRIVATE`, so there is no second process to race with.
    ///
    /// 標為 `nonisolated(unsafe)`,因為 `SharedPreferences` 是一個 Java 物件 handle、不可能是
    /// `Sendable`,而 `AppStorageProvider` 是。
    ///
    /// **讓這個斷言為真的是 Android 自己的保證,不是這個標註。** `SharedPreferences` 的文件載明它是
    /// thread-safe 的:同一個行程內、同一個名稱只有單一實例,而它的讀者與寫者在框架內部就已同步。
    /// 因此「這個 handle 跨越執行緒」正是這個 API 被設計來做的事。
    ///
    /// 它**唯一**不涵蓋的是第二個行程,而文件同樣說了這件事:`MODE_MULTI_PROCESS` 已被棄用且不可靠。
    /// 本 provider 以 `MODE_PRIVATE` 開啟,因此不存在可與之競爭的第二個行程。
    private nonisolated(unsafe) let sharedPreferences: AndroidKit.SharedPreferences
    private let encoder = Foundation.JSONEncoder()
    private let decoder = Foundation.JSONDecoder()

    init(activity: AndroidKit.Activity) {
        let contextClass = try! JavaClass<AndroidKit.Context>()
        sharedPreferences = activity.getSharedPreferences("AppStorage", contextClass.MODE_PRIVATE)!
    }

    public func persistValue<Value: Codable>(_ value: Value, forKey key: String) throws {
        let data = try encoder.encode(value)
        let jsonString = String(data: data, encoding: .utf8)

        let editor = sharedPreferences.edit()!
        // Some methods on Editor return the editor again, so that you can
        // chain multiple put* or remove calls. We don't need that, and the
        // Swift bindings aren't marked @discardableResult.
        if let jsonString {
            _ = editor.putString(key, jsonString)
        } else {
            _ = editor.remove(key)
        }
        editor.apply()
    }

    public func retrieveValue<Value: Codable>(
        ofType type: Value.Type,
        forKey key: String
    ) -> Value? {
        var jsonString: String
        do {
            guard
                let javaString = try sharedPreferences.getString(key: key, defaultValue: nil)
            else {
                return nil
            }
            jsonString = javaString.toString()
        } catch {
            log("Exception thrown by sharedPreferences.getString: \(error)")
            return nil
        }

        let data = Data(jsonString.utf8)

        return try? decoder.decode(type, from: data)
    }
}
