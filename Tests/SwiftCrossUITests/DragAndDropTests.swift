import Foundation
import Testing

import DummyBackend
@testable @_spi(Backends) import SwiftCrossUI

@Suite("Drag and drop (drop target)")
struct DragAndDropTests {
    let backend: DummyBackend
    let window: DummyBackend.Window
    let environment: EnvironmentValues

    @MainActor
    init() {
        backend = DummyBackend()
        window = backend.createWindow(withDefaultSize: nil, id: "window")
        environment = EnvironmentValues(backend: backend).with(\.window, window)
    }

    // A reference box so an @escaping handler can record into it from a value-type
    // view; the view graph copies the view, so a captured `var` would not do.
    final class Box<T> {
        var value: T
        init(_ value: T) { self.value = value }
    }

    @MainActor
    func dropTarget<V: View>(of view: V) -> DummyBackend.DropTarget {
        let node = ViewGraphNode(for: view, backend: backend, environment: environment)
        _ = node.computeLayout(proposedSize: ProposedViewSize(200, 200), environment: environment)
        _ = node.commit()
        guard let target = node.widget.firstWidget(ofType: DummyBackend.DropTarget.self) else {
            fatalError("onDrop did not produce a DropTarget")
        }
        return target
    }

    @MainActor
    @Test("An accepted type is delivered to the handler")
    func acceptedTypeIsDelivered() {
        let received = Box<[DropItem]>([])
        let view = Text("drop here").onDrop(of: [.fileURL]) { items in
            received.value = items
            return true
        }
        let target = dropTarget(of: view)

        let item = DropItem(
            type: .fileURL,
            data: Data("file:///tmp/example.txt\r\n".utf8)
        )
        let accepted = target.simulateDrop([item])

        #expect(accepted)
        #expect(received.value.count == 1)
        #expect(received.value.first?.url == URL(string: "file:///tmp/example.txt"))
    }

    @MainActor
    @Test("A type the target does not accept is refused, not swallowed")
    func unacceptedTypeIsRefused() {
        let fired = Box(false)
        let view = Text("drop here").onDrop(of: [.fileURL]) { _ in
            fired.value = true
            return true
        }
        let target = dropTarget(of: view)

        let item = DropItem(type: .plainText, data: Data("hello".utf8))
        let accepted = target.simulateDrop([item])

        #expect(!accepted)
        #expect(!fired.value, "the handler must not run for a refused type")
    }

    @MainActor
    @Test("The isTargeted binding tracks hover, before the drop")
    func isTargetedTracksHover() {
        let box = Box(false)
        let binding = Binding(get: { box.value }, set: { box.value = $0 })
        let view = Text("drop here").onDrop(of: [.fileURL], isTargeted: binding) { _ in true }
        let target = dropTarget(of: view)

        target.onHover?(true)
        #expect(box.value)
        target.onHover?(false)
        #expect(!box.value)
    }

    @MainActor
    @Test("The URL convenience form collects URLs and refuses an empty drop")
    func urlConvenienceForm() {
        let received = Box<[URL]>([])
        let view = Text("drop here").onDrop(of: [.fileURL]) { (urls: [URL]) in
            received.value = urls
            return true
        }
        let target = dropTarget(of: view)

        // Two files in one uri-list payload, with a comment line to skip.
        let payload = "#comment\r\nfile:///a.txt\r\nfile:///b.txt\r\n"
        let accepted = target.simulateDrop([DropItem(type: .fileURL, data: Data(payload.utf8))])
        #expect(accepted)
        #expect(received.value == [URL(string: "file:///a.txt")!, URL(string: "file:///b.txt")!])

        // A payload with no URL is refused even though its type is accepted.
        received.value = []
        let empty = target.simulateDrop([DropItem(type: .fileURL, data: Data())])
        #expect(!empty)
        #expect(received.value.isEmpty)
    }

    @Test("DropItem exposes text and urls without discarding the bytes")
    func dropItemAccessors() {
        let item = DropItem(type: .plainText, data: Data("plain".utf8))
        #expect(item.text == "plain")
        #expect(item.urls.isEmpty)

        let uriList = DropItem(
            type: .fileURL,
            data: Data("file:///x%20y.txt\r\n".utf8)
        )
        #expect(uriList.url == URL(string: "file:///x%20y.txt"))
    }
}
