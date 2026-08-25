import Foundation

/// A content type a drop target accepts, and that a dropped item arrives as.
///
/// Identified by a content-type string. On Linux and Windows these map to
/// GDK content formats, which understand MIME types directly; the string is the
/// MIME type, so `.fileURL` is `text/uri-list` and `.plainText` is
/// `text/plain`. A backend is free to map the string onto whatever its toolkit
/// actually negotiates over.
public struct DropType: Sendable, Hashable {
    /// The content-type string, e.g. `text/uri-list`.
    public var identifier: String

    public init(_ identifier: String) {
        self.identifier = identifier
    }

    /// One or more files, delivered as URLs. `text/uri-list` on GDK.
    public static let fileURL = DropType("text/uri-list")

    /// Plain UTF-8 text.
    public static let plainText = DropType("text/plain")
}

/// A single payload delivered to a drop target.
///
/// The bytes are handed over verbatim, as the backend received them from the
/// platform. This is deliberate: the same file arrives as a `file://` URI in a
/// `text/uri-list` on Linux and as a path through `CF_HDROP` on Windows, and
/// normalising the two here would hide exactly the difference an app may need to
/// see. The convenience accessors (``url``/``urls``/``text``) interpret the
/// bytes for the common cases without discarding them.
public struct DropItem: Sendable {
    /// The type the payload arrived as.
    public var type: DropType
    /// The payload, verbatim.
    public var data: Data

    public init(type: DropType, data: Data) {
        self.type = type
        self.data = data
    }

    /// The payload decoded as UTF-8 text, or `nil` if it is not valid UTF-8.
    public var text: String? {
        String(data: data, encoding: .utf8)
    }

    /// Every URL in the payload, parsed as an RFC 2483 `text/uri-list`.
    ///
    /// Lines are separated by CRLF; blank lines and lines beginning with `#`
    /// (comments) are skipped. Returns an empty array when the payload is not
    /// text or holds no parseable URL, so a caller can treat "no files" and
    /// "wrong type" alike.
    ///
    /// The split is on ``Character/isNewline``, not on `"\r"`/`"\n"` compared
    /// individually: Swift treats a `"\r\n"` pair as a single grapheme cluster,
    /// so a character-by-character test for `"\r"` or `"\n"` never matches it and
    /// the CRLF ends up inside the URL as `%0D%0A`. `isNewline` matches the pair.
    ///
    /// Only URIs with a scheme are kept. `URL(string:)` accepts a bare word like
    /// `plain` as a relative URL, so without this a plain-text payload would come
    /// back as a list of nonsense URLs; a `text/uri-list` entry is an absolute
    /// URI by definition (RFC 2483).
    public var urls: [URL] {
        guard let text else { return [] }
        return text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .compactMap { URL(string: $0) }
            .filter { $0.scheme != nil }
    }

    /// The first URL in the payload, for the single-file case. See ``urls``.
    public var url: URL? {
        urls.first
    }
}

extension BackendFeatures {
    /// Backend methods for accepting dropped content.
    ///
    /// Used by ``View/onDrop(of:isTargeted:perform:)``.
    ///
    /// Only the drop (target) side is modelled. The drag *source* side -- making
    /// a view draggable out of the app -- is a separate feature and is not part
    /// of this protocol; adding it here later would not disturb targets.
    ///
    /// A backend that cannot accept drops conforms with the no-op defaults
    /// below. The consequence is a drop that never fires, which matches how the
    /// same view behaves on a platform without the capability; there is no safer
    /// fallback to pick.
    @MainActor
    public protocol DragAndDrop: Core {
        /// Wraps a view in a widget that can receive drops.
        ///
        /// The accepted types and handlers are set later by
        /// ``updateDropTarget(_:acceptedTypes:environment:onHover:onDrop:)``,
        /// following the usual create/update split -- an empty target accepts
        /// nothing until it is updated.
        ///
        /// - Parameter child: The child to wrap.
        /// - Returns: A widget that can receive drops.
        func createDropTarget(wrapping child: Widget) -> Widget

        /// Sets a drop target's accepted types and its handlers.
        ///
        /// - Parameters:
        ///   - dropTarget: The target to update.
        ///   - acceptedTypes: The types the target will accept. A drag offering
        ///     none of these must be refused, not silently swallowed.
        ///   - environment: The current environment.
        ///   - onHover: Called with `true` when a drag the target accepts enters
        ///     it, and `false` when such a drag leaves or the drop completes.
        ///     This is the feedback stage, and it must be reported before the
        ///     drop so that a backend which only reacts on release is
        ///     distinguishable from one that reacts on hover.
        ///   - onDrop: Called with the dropped items when a drop lands. Returns
        ///     whether the drop was accepted. Must not be called for a drag the
        ///     target refused.
        func updateDropTarget(
            _ dropTarget: Widget,
            acceptedTypes: [DropType],
            environment: EnvironmentValues,
            onHover: @escaping (Bool) -> Void,
            onDrop: @escaping ([DropItem]) -> Bool
        )
    }
}

extension BackendFeatures.DragAndDrop {
    /// Does not wrap the child. A default so that a backend can conform without
    /// accepting drops; the target simply never fires.
    public func createDropTarget(wrapping child: Widget) -> Widget {
        child
    }

    /// Ignores the request. See ``createDropTarget(wrapping:)``.
    public func updateDropTarget(
        _ dropTarget: Widget,
        acceptedTypes: [DropType],
        environment: EnvironmentValues,
        onHover: @escaping (Bool) -> Void,
        onDrop: @escaping ([DropItem]) -> Bool
    ) {}
}
