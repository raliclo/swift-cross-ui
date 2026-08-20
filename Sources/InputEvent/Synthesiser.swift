import Foundation

/// Where the window is, in screen coordinates, and how big.
///
/// Supplied by the caller because this module does not know about windows. It
/// takes numbers and posts events; keeping it that way is what lets it be
/// tested without a running application.
public struct WindowGeometry: Equatable, Sendable {
    /// Top-left of the window frame, decorations included, in screen points.
    public var frameOrigin: (x: Double, y: Double)

    /// Top-left of the client area, in screen points. On a platform using
    /// client-side decorations this can equal ``frameOrigin``.
    public var clientOrigin: (x: Double, y: Double)

    /// Physical pixels per logical point. Action files are written in points so
    /// they survive being replayed at a different display scale; the conversion
    /// happens here, at the last moment.
    public var scale: Double

    public init(
        frameOrigin: (x: Double, y: Double),
        clientOrigin: (x: Double, y: Double),
        scale: Double = 1
    ) {
        self.frameOrigin = frameOrigin
        self.clientOrigin = clientOrigin
        self.scale = scale
    }

    public static func == (a: WindowGeometry, b: WindowGeometry) -> Bool {
        a.frameOrigin == b.frameOrigin && a.clientOrigin == b.clientOrigin && a.scale == b.scale
    }

    /// Converts a window-relative point to physical screen pixels.
    public func screenPosition(of point: Point) -> (x: Int, y: Int) {
        let origin = point.origin == .frame ? frameOrigin : clientOrigin
        return (
            x: Int(((origin.x + point.x) * scale).rounded()),
            y: Int(((origin.y + point.y) * scale).rounded())
        )
    }
}

/// Posts input events to the system.
///
/// Both implementations are system-wide: `SendInput` posts to the foreground
/// window and XTEST to the X server's focus. Neither targets a chosen window,
/// which is why the caller presents its window before replaying anything.
@MainActor
public protocol Synthesiser {
    func perform(_ action: InputAction, in geometry: WindowGeometry) throws

    /// The platform's double-click interval, in microseconds.
    ///
    /// Read rather than hard-coded. Neither `SendInput` nor XTEST bundles
    /// clicks -- both need two press-release pairs inside this interval -- and
    /// the interval differs between platforms and with the user's settings. A
    /// fixed gap would produce a double click on one machine and two single
    /// clicks on another from the same file.
    var doubleClickInterval: Int { get }
}

extension Synthesiser {
    /// Replays a whole file.
    ///
    /// Stops at the first failure rather than continuing. A synthesiser that
    /// carries on after a failed action produces a run whose later steps acted
    /// on a state the file does not describe, and the screenshot at the end
    /// looks like a product defect.
    public func replay(_ actions: [InputAction], in geometry: WindowGeometry) throws {
        for action in actions {
            try perform(action, in: geometry)
        }
    }

    /// Two press-release pairs inside the platform's interval, shared by both
    /// implementations so they cannot drift apart on the one behaviour they are
    /// most likely to disagree about.
    public func performDoubleClick(
        _ button: MouseButton,
        at point: Point?,
        in geometry: WindowGeometry
    ) throws {
        try perform(.mouseDown(button, at: point), in: geometry)
        try perform(.mouseUp(button, at: point), in: geometry)
        // Half the interval: comfortably inside it, and far enough from the
        // boundary that a scheduling hiccup does not turn the pair into two
        // single clicks.
        try perform(.sleep(microseconds: doubleClickInterval / 2), in: geometry)
        try perform(.mouseDown(button, at: point), in: geometry)
        try perform(.mouseUp(button, at: point), in: geometry)
    }
}

public enum SynthesiserError: Error, CustomStringConvertible {
    case toolMissing(String)
    case toolFailed(String, status: Int32)
    case unsupported(String)

    public var description: String {
        switch self {
            case .toolMissing(let name):
                "\(name) is not on PATH"
            case .toolFailed(let name, let status):
                "\(name) exited with status \(status)"
            case .unsupported(let what):
                "\(what) is not supported on this platform"
        }
    }
}
