import Foundation

/// A type-erased list of data representing the content of a navigation stack.
///
/// If you are persisting a path using the `Codable` implementation, you must
/// not change type definitions in a non-backwards compatible way. Otherwise,
/// the path may fail to decode.
public struct NavigationPath {
    /// A storage class used so that we have control over exactly which changes
    /// are published (to avoid infinite loops).
    private class Storage {
        /// An entry that will be decoded next time it is used by a
        /// ``NavigationStack`` (we need to wait until we know what concrete
        /// entry types are available).
        struct EncodedEntry: Codable {
            var type: String
            var value: Data
        }

        /// The current path.
        ///
        /// If both this and ``encodedEntries`` are non-empty, the elements in
        /// `path` were added before the navigation path was even used to render
        /// a view. By design they come after the `encodedEntries` (because they
        /// can only be the result of appending and maybe popping).
        var path: [any Codable] = []
        /// Entries that will be decoded when this navigation path is first used
        /// by a ``NavigationStack``.
        ///
        /// It is not possible to decode the entries without first knowing what
        /// types the path can possibly contain (which only the
        /// ``NavigationStack`` will know).
        var encodedEntries: [EncodedEntry] = []
    }

    /// The path and any elements waiting to be decoded are stored in a class so
    /// that changes are triggered from within ``NavigationStack`` instead of
    /// ``NavigationPath`` when decoding the elements (which avoids an infinite
    /// loop of updates).
    private var storage = Storage()

    /// Indicates whether this path is empty.
    var isEmpty: Bool {
        storage.encodedEntries.isEmpty && storage.path.isEmpty
    }

    /// The number of elements in the path.
    var count: Int {
        storage.encodedEntries.count + storage.path.count
    }

    /// Creates an empty navigation path.
    /// A copy that does not share storage with this path.
    ///
    /// `Storage` is a class and nothing copies it on write, so `let saved =
    /// path` followed by `path.removeLast()` changes `saved` too. The undo of
    /// an interactive Back (NavigationBackNavigation.swift) needs the path as
    /// it was, so it takes this copy.
    ///
    /// 一份不與此路徑共用儲存的副本。`Storage` 是 class,而且沒有任何東西在寫入時複製它，因此 `let saved = path` 之後再
    /// `path.removeLast()`,`saved` 也會跟著改變。互動式返回的復原(NavigationBackNavigation.swift)需要原本的路徑，所以取這份副本。
    func independentCopy() -> NavigationPath {
        let copy = NavigationPath()
        copy.storage.path = storage.path
        copy.storage.encodedEntries = storage.encodedEntries
        return copy
    }

    public init() {}

    /// Appends a new value to the end of the path.
    ///
    /// - Parameter component: The component to append.
    public mutating func append(_ component: some Codable) {
        storage.path.append(component)
    }

    /// Removes values from the end of this path.
    ///
    /// - Precondition: `k >= 0`.
    ///
    /// - Parameter k: The number of elements to remove from the path.
    public mutating func removeLast(_ k: Int = 1) {
        precondition(k >= 0, "`k` must be greater than or equal to zero")
        if k < storage.path.count {
            storage.path.removeLast(k)
        } else if k < count {
            storage.encodedEntries.removeLast(k - storage.path.count)
            storage.path.removeAll()
        } else {
            removeAll()
        }
    }

    /// Removes all values from this path.
    public mutating func removeAll() {
        storage.path.removeAll()
        storage.encodedEntries.removeAll()
    }

    /// Gets the path's current entries.
    ///
    /// If the path was decoded from a stored representation and has not been
    /// used by a ``NavigationStack`` yet, the `destinationTypes` will be used
    /// to decode all elements in the path. Without knowing the
    /// `destinationTypes`, the entries cannot be decoded (after macOS 11 they
    /// can be decoded by using `_typeByName`, but we can't use that because of
    /// backwards compatibility).
    ///
    /// An entry that cannot be decoded -- its type is not among
    /// `destinationTypes`, or its data no longer decodes as that type, as after
    /// the type changed between versions of the app -- is dropped with a
    /// warning, together with every stored entry after it: those screens were
    /// pushed on top of it, and a stack with a hole in it would show a screen
    /// whose predecessor never existed. The entries decoded before it are kept.
    ///
    /// 取得路徑目前的項目。
    ///
    /// 無法解碼的項目——其型別不在 `destinationTypes` 之中，或其資料已無法解碼為該型別(例如該型別在 app 的
    /// 不同版本之間改變了)——會連同其後所有已儲存的項目一起被丟棄，並發出警告：那些畫面是疊在它之上的，
    /// 而一個中間有洞的堆疊會顯示一個「前一個畫面從未存在」的畫面。在它之前已解碼的項目會保留。
    ///
    /// - Parameter destinationTypes: The types to use to decode the entries.
    /// - Returns: The decoded entries.
    func path(destinationTypes: [any Codable.Type]) -> [any Codable] {
        guard !storage.encodedEntries.isEmpty else {
            return storage.path
        }

        var typesByName: [String: any Codable.Type] = [:]
        for destinationType in destinationTypes {
            typesByName[String(reflecting: destinationType)] = destinationType
        }

        var entries: [any Codable] = []
        for (i, entry) in storage.encodedEntries.enumerated() {
            guard let destinationType = typesByName[entry.type] else {
                logger.warning(
                    "dropping navigation path entries with no matching navigationDestination",
                    metadata: [
                        "type": "\(entry.type)",
                        "dropped": "\(storage.encodedEntries.count - i)",
                    ]
                )
                break
            }
            do {
                entries.append(try JSONDecoder().decode(destinationType, from: entry.value))
            } catch {
                logger.warning(
                    "dropping navigation path entries that failed to decode",
                    metadata: [
                        "type": "\(entry.type)",
                        "error": "\(error)",
                        "dropped": "\(storage.encodedEntries.count - i)",
                    ]
                )
                break
            }
        }

        storage.encodedEntries = []
        storage.path = entries + storage.path

        return storage.path
    }
}

extension NavigationPath: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let entries = try container.decode([Storage.EncodedEntry].self)
        guard !entries.isEmpty else {
            return
        }

        storage.encodedEntries = entries
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        // Combine any remaining encoded entries with the current decoded entries in the path.
        var entries = storage.encodedEntries
        entries += storage.path.map { entry in
            let type = String(reflecting: type(of: entry))
            let value: Data
            do {
                value = try JSONEncoder().encode(entry)
            } catch {
                fatalError("Failed to encode navigation path entry of type \(type)")
            }

            return Storage.EncodedEntry(
                type: type,
                value: value
            )
        }

        try container.encode(entries)
    }
}
