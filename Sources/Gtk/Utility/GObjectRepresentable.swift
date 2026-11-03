import CGtk

public protocol GObjectRepresentable {
    var gobjectPointer: UnsafeMutablePointer<CGtk.GObject> { get }
}

extension GObjectRepresentable {
    public func setProperty<V: GValueRepresentable>(named name: String, newValue: V) {
        var v = GValue()
        let value = g_value_init(&v, V.type)!
        newValue.apply(to: value)
        g_object_set_property(gobjectPointer, name, value)
        // `g_object_set_property` copies what it keeps; the value's own string
        // copy or object reference is released here.
        // `g_object_set_property` 會複製它要保留的內容;value 自己的字串複本或物件參考在這裡釋放。
        g_value_unset(value)
    }

    /// If this returned an optional at runtime and crashed; it is because the
    /// underlying value was nil while `V` was not `Optional<GValueRepresentable>`.
    /// Change to optional at caller site. eg:
    /// ```diff
    /// -@GObjectProperty(named: "optional-value") var value: String
    /// +@GObjectProperty(named: "optional-value") var value: String?
    /// ```
    public func getProperty<V: GValueRepresentable>(named name: String) -> V {
        var v = GValue()
        let value = g_value_init(&v, V.type)!
        g_object_get_property(gobjectPointer, name, value)
        // Unset after `V` is built: the value owns a copy of a string and a
        // reference to an object, both released here. `String(cString:)` has
        // already copied the bytes; an `OpaquePointer` comes back borrowed, kept
        // alive by the object that holds the property, not by this call.
        // 在建出 `V` 之後才 unset:value 擁有字串的一份複本與物件的一個參考，兩者都在這裡釋放。
        // `String(cString:)` 已經複製了位元組;`OpaquePointer` 回傳的是借用的指標，由持有該屬性的物件
        // 保持存活，而不是由這次呼叫。
        defer { g_value_unset(value) }
        return V(value)!
    }
}
