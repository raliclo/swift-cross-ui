import Foundation

/// An object that can be observed for changes.
///
/// The default implementation only publishes changes made to properties that
/// have been wrapped with the ``Published`` property wrapper. Even properties
/// that themselves conform to ``ObservableObject`` must be wrapped with the
/// ``Published`` property wrapper for clarity.
///
/// ```swift
/// class NestedState: ObservableObject {
///     // Both `startIndex` and `endIndex` will have their changes published to `NestedState`'s
///     // `didChange` publisher.
///     @Published
///     var startIndex = 0
///
///     @Published
///     var endIndex = 0
/// }
///
/// class CounterState: ObservableObject {
///     // Only changes to `count` will be published (it is the only property with `@Published`)
///     @Published
///     var count = 0
///
///     var otherCount = 0
///
///     // Even though `nested` is `ObservableObject`, its changes won't be
///     // published because if you could have observed properties without
///     // `@Published` things would get pretty messy and you'd always have to
///     // check the definition of the type of each property to know exactly
///     // what would and wouldn't cause updates.
///     var nested = NestedState()
/// }
/// ```
///
/// To use an observable object as part of a view's state, use the ``State`` property
/// wrapper. It'll detect that it's been given an observable and will forward any
/// observations published by the object's ``ObservableObject/didChange`` publisher.
///
/// ```swift
/// class CounterState: ObservableObject {
///     @Published var count = 0
/// }
///
/// struct CounterView: View {
///     @State var state = CounterState()
///
///     var body: some View {
///         HStack {
///             Button("-") {
///                 state.count -= 1
///             }
///             Text("Count: \(state.count)")
///             Button("+") {
///                 state.count += 1
///             }
///         }
///     }
/// }
/// ```
public protocol ObservableObject: AnyObject {
    /// A publisher which publishes changes made to the object. Only publishes changes made to
    /// ``Published`` properties by default.
    var didChange: Publisher { get }
}

extension ObservableObject {
    /// One publisher per object, built the first time it is asked for and
    /// returned on every later access.
    ///
    /// It is linked to every ``Published`` property the object has when it is
    /// built, and those links last as long as the object does. Building a new
    /// one per access would add a link to every `@Published` property each
    /// time -- and `@ObservedObject` reads it on every update of its parent --
    /// so the links would grow without bound.
    ///
    /// 每個物件一個 publisher：第一次被要求時建立，之後每次存取都回傳同一個。
    ///
    /// 建立時它會連到該物件的每一個 ``Published`` 屬性，而那些連結與物件同壽。若每次存取都建一個新的，
    /// 每次都會在每個 `@Published` 屬性上多加一條連結——而 `@ObservedObject` 在父層每次更新時都會讀它
    /// ——連結於是無止境地增長。
    public var didChange: Publisher {
        ObservableObjectPublishers.publisher(for: self)
    }
}

/// The publishers ``ObservableObject``'s default `didChange` hands out, one
/// per live object.
///
/// Keyed by `ObjectIdentifier` and holding the object weakly: an identifier
/// can be reused once its object is freed, so an entry counts only while its
/// object is still the same instance, and entries whose object is gone are
/// pruned as the table grows. A lock guards the table because an object can
/// be observed from any thread.
///
/// ``ObservableObject`` 預設的 `didChange` 所發出的 publisher,每個存活物件一個。
///
/// 以 `ObjectIdentifier` 為鍵、以弱參照持有物件:物件被釋放後識別碼可能被重用，因此只有在其物件仍是同一個
/// 實例時，條目才算數;物件已不在的條目會隨著表增長而被清掉。以鎖保護這張表，因為物件可以從任何執行緒被觀察。
enum ObservableObjectPublishers {
    private final class Entry {
        weak var object: AnyObject?
        let publisher: Publisher

        init(object: AnyObject, publisher: Publisher) {
            self.object = object
            self.publisher = publisher
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var entries: [ObjectIdentifier: Entry] = [:]
    /// The size at which dead entries are next pruned.
    /// 下一次清掉失效條目時的大小。
    nonisolated(unsafe) private static var pruneThreshold = 64

    static func publisher(for object: some ObservableObject) -> Publisher {
        let id = ObjectIdentifier(object)
        if let existing = lookUp(id, object) {
            return existing
        }
        // Built outside the lock: reading the properties' publishers runs
        // code this table does not control.
        // 在鎖外建立：讀取各屬性的 publisher 會執行這張表所無法掌控的程式碼。
        let built = makePublisher(for: object)
        lock.lock()
        defer { lock.unlock() }
        if let entry = entries[id], entry.object === object {
            return entry.publisher
        }
        entries[id] = Entry(object: object, publisher: built)
        if entries.count >= pruneThreshold {
            entries = entries.filter { $0.value.object != nil }
            pruneThreshold = max(64, entries.count * 2)
        }
        return built
    }

    /// How many objects have a publisher, for tests.
    /// 有 publisher 的物件數，供測試使用。
    static var liveCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.values.count { $0.object != nil }
    }

    private static func lookUp(_ id: ObjectIdentifier, _ object: AnyObject) -> Publisher? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[id], entry.object === object else {
            return nil
        }
        return entry.publisher
    }

    private static func makePublisher(for object: some ObservableObject) -> Publisher {
        let publisher = Publisher()
            .tag(with: String(describing: type(of: object)))

        var mirror: Mirror? = Mirror(reflecting: object)
        while let aClass = mirror {
            for (_, property) in aClass.children {
                guard
                    property is PublishedMarkerProtocol,
                    let property = property as? ObservableObject
                else {
                    continue
                }

                let cancellable = publisher.link(toUpstream: property.didChange)
                cancellable.defuse()
            }
            mirror = aClass.superclassMirror
        }
        return publisher
    }
}

protocol OptionalObservableObject {
    var didChange: Publisher? { get }
}

extension Optional: OptionalObservableObject where Wrapped: ObservableObject {
    var didChange: SwiftCrossUI.Publisher? {
        switch self {
            case .some(let object):
                object.didChange
            case .none:
                nil
        }
    }
}

@available(*, deprecated, message: "Replace Observable with ObservableObject")
public typealias Observable = ObservableObject

/// Automatically observes all public noncomputed variables with public getter and setter
@attached(memberAttribute)
@attached(extension, conformances: ObservableObject)
public macro ObservableObject() =
    #externalMacro(
        module: "SwiftCrossUIMacrosPlugin",
        type: "ObservableObjectMacro"
    )

/// Apply to a member inside your `@ObservableObject` class to opt out of observation
// This macro is just used as a flag for `@ObservableObject` to ignore a specific property
@attached(accessor)
public macro ObservationIgnored() =
    #externalMacro(
        module: "SwiftCrossUIMacrosPlugin",
        type: "ObservationIgnoredMacro"
    )
