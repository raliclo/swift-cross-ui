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
        // The parameter type is spelled out. `onDrop(of:isTargeted:perform:)` has
        // two overloads that differ only in the closure's parameter -- [DropItem]
        // and [URL] -- so a closure that names neither its parameter nor its type
        // matches both, and the call fails to compile with "ambiguous use of
        // onDrop". The tests either side of this one get away with it because
        // their bodies touch the parameter and inference has something to work
        // from; the two that ignore it entirely have to say which overload they
        // mean. That is a property of the API, not of the tests: any caller
        // writing `{ _ in true }` meets the same error.
        //
        // 此處明確寫出參數型別。`onDrop(of:isTargeted:perform:)` 有兩個多載，差異僅在 closure
        // 的參數為 [DropItem] 或 [URL]，因此既不具名參數也不標註型別的 closure 會同時符合兩者，
        // 呼叫端會以「ambiguous use of onDrop」編譯失敗。本檔其他測試之所以無此問題，是因為其
        // body 用到了該參數，型別推論有依據可循；完全不使用該參數的兩個測試則必須指明所要的多載。
        // 這是 API 本身的性質，而非測試的問題：任何寫下 `{ _ in true }` 的呼叫端都會遇到同樣的錯誤。
        let view = Text("drop here").onDrop(of: [.fileURL]) { (_: [DropItem]) in
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
        // Parameter type spelled out for the reason given in
        // `unacceptedTypeIsRefused` above: this test never touches the dropped
        // items, so nothing else tells the two overloads apart.
        // 標註參數型別的理由見上方 `unacceptedTypeIsRefused`：本測試從不觸及 dropped items，
        // 沒有其他線索可區分兩個多載。
        let view = Text("drop here")
            .onDrop(of: [.fileURL], isTargeted: binding) { (_: [DropItem]) in true }
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
