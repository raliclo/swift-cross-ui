import Foundation

/// A scene that gives each open document a window of its own.
///
/// ```swift
/// var body: some Scene {
///     DocumentGroup(newDocument: TextFile()) { document in
///         EditorView(document: document)
///     }
/// }
/// ```
///
/// The editor closure receives a `Binding`, so writing through it is what marks
/// the document changed -- there is no separate "mark dirty" call to forget.
///
/// **WHAT THIS DOES AND DOES NOT DO, said here rather than discovered.** It
/// opens one untitled document at launch, opens files through the platform's
/// open dialog, and writes them back through the save dialog. It does NOT yet
/// do: autosave, versions, the "unsaved changes" prompt on close, or reopening
/// the documents that were open last time. Those are each a decision about
/// behaviour rather than plumbing, and a scene that silently did half of them
/// would be worse than one that says which half it does.
///
/// 一個「讓每份開啟的文件各自擁有一個視窗」的 scene。
///
/// 那個編輯器 closure 收到的是一個 `Binding`,因此「透過它寫入」本身就是「文件被改動了」——不存在
/// 另一個「標記為已修改」的呼叫可以忘記。
///
/// **它做什麼、不做什麼,在此處說明,而不是留給人去發現。** 它會在啟動時開啟一份未命名文件、透過平台的
/// 開啟對話框開檔、並透過儲存對話框寫回。它**尚未**做:自動儲存、版本、關閉時的「尚未儲存」提示,
/// 以及「重新開啟上次開著的那些文件」。這些每一項都是關於**行為**的決定、而非管線問題;而一個
/// 「默默做了其中一半」的 scene,會比一個「說清楚自己做了哪一半」的更糟。
public struct DocumentGroup<Document: FileDocument, Content: View>: Scene {
    public typealias Node = DocumentGroupNode<Document, Content>

    var newDocument: () -> Document
    var editor: (Binding<Document>) -> Content

    /// Creates a document group.
    ///
    /// - Parameters:
    ///   - newDocument: An empty document, for "New". An `@autoclosure` so each
    ///     new window gets its own value rather than every window sharing the
    ///     one that was written at the call site.
    ///   - editor: The view for one document.
    public init(
        newDocument: @escaping @autoclosure () -> Document,
        @ViewBuilder editor: @escaping (Binding<Document>) -> Content
    ) {
        self.newDocument = newDocument
        self.editor = editor
    }
}

/// One open document: its value, where it came from, and its window.
///
/// A class because the window's content closure captures it and writes through
/// it. A struct would be copied into that closure and the edit would land in the
/// copy -- the document on screen would change and the one being saved would
/// not.
///
/// 一份開啟中的文件:它的值、它來自哪裡,以及它的視窗。
///
/// 使用 class,因為那個視窗的內容 closure 會捕捉它並透過它寫入。若是 struct,它會被複製進那個
/// closure,而編輯會落在那份副本上——螢幕上的文件會改變,而被儲存的那一份不會。
@MainActor
final class OpenDocument<Document: FileDocument> {
    var document: Document
    /// Where it was read from, or `nil` for an untitled document.
    /// 它是從哪裡讀進來的；未命名文件為 `nil`。
    var url: URL?

    init(document: Document, url: URL?) {
        self.document = document
        self.url = url
    }

    /// What the window is called: the file's name, or "Untitled".
    /// 這個視窗叫什麼：檔案的名字，或「Untitled」。
    var title: String {
        url?.lastPathComponent ?? "Untitled"
    }
}

/// A window that shows one document.
///
/// Internal, and a `WindowingScene` only so it can be handed to
/// ``WindowReference`` -- which is the piece that already knows how to build a
/// window, lay it out, apply chrome and tear it down. Writing a second one of
/// those for documents would be a copy that drifts.
///
/// 一個顯示單一文件的視窗。
///
/// 它是 internal 的，而之所以是 `WindowingScene`，只是為了能交給 ``WindowReference``——那才是已經
/// 懂得如何建立視窗、排版、套用外框並拆除它的那一塊。為文件另寫一份，等於複製一份出來讓它日後漂移。
struct DocumentWindowScene<Content: View>: WindowingScene {
    /// Required by `Scene` and never instantiated.
    ///
    /// This type never enters a scene graph: ``DocumentGroupNode`` builds and
    /// drives the `WindowReference`s itself, and this is only the value that
    /// reference is handed. `Scene` still demands a node type, so there is one,
    /// and it does nothing rather than pretending to.
    ///
    /// 由 `Scene` 要求，而且永遠不會被實例化。
    ///
    /// 這個型別從不進入 scene graph：``DocumentGroupNode`` 自己建立並驅動那些 `WindowReference`，
    /// 而此處只是交給該 reference 的那個值。`Scene` 仍然要求一個 node 型別，因此這裡有一個——
    /// 而它什麼都不做，而不是假裝在做什麼。
    typealias Node = DocumentWindowSceneNode<Content>

    var title: String
    var content: () -> Content
}

/// The node ``DocumentWindowScene`` names and nobody creates.
/// ``DocumentWindowScene`` 所指名、而沒有人會建立的那個節點。
final class DocumentWindowSceneNode<Content: View>: SceneGraphNode {
    typealias NodeScene = DocumentWindowScene<Content>

    init<Backend: BaseAppBackend>(
        from scene: DocumentWindowScene<Content>,
        backend: Backend,
        environment: EnvironmentValues
    ) {}

    func updateNode(
        _ newScene: DocumentWindowScene<Content>?,
        environment: EnvironmentValues
    ) -> SceneNodeUpdateResult {
        .leafScene()
    }

    func update<Backend: BaseAppBackend>(
        backend: Backend,
        environment: EnvironmentValues
    ) {}
}

/// The ``SceneGraphNode`` corresponding to a ``DocumentGroup``.
public final class DocumentGroupNode<Document: FileDocument, Content: View>: SceneGraphNode {
    public typealias NodeScene = DocumentGroup<Document, Content>

    private var scene: DocumentGroup<Document, Content>
    private var documents: [UUID: OpenDocument<Document>] = [:]
    private var windows: [UUID: WindowReference<DocumentWindowScene<Content>>] = [:]

    public init<Backend: BaseAppBackend>(
        from scene: DocumentGroup<Document, Content>,
        backend: Backend,
        environment: EnvironmentValues
    ) {
        self.scene = scene

        let openOnAppLaunch =
            switch environment.defaultLaunchBehavior {
                case .automatic, .presented: true
                case .suppressed: false
            }

        if openOnAppLaunch {
            open(document: scene.newDocument(), at: nil, backend: backend, environment: environment)
        }
    }

    public func updateNode(
        _ newScene: NodeScene?,
        environment: EnvironmentValues
    ) -> SceneNodeUpdateResult {
        if let newScene {
            self.scene = newScene
        }

        return .leafScene()
    }

    public func update<Backend: BaseAppBackend>(
        backend: Backend,
        environment: EnvironmentValues
    ) {
        // Installed on every update rather than once, for the reason
        // `SettingsNode` records: the closures capture `scene`, and `scene` is
        // replaced whenever the app's body is recomputed.
        // 每次更新都重新安裝，而非只安裝一次，理由與 `SettingsNode` 所記載的相同：這些 closure 捕捉了
        // `scene`，而 `scene` 會在 app 的 body 被重新計算時被替換。
        let registry = environment.documentRegistry
        registry.newDocument = { [weak self] in
            guard let self else { return }
            self.open(
                document: self.scene.newDocument(),
                at: nil,
                backend: backend,
                environment: environment
            )
        }
        registry.openDocument = { [weak self] url in
            guard let self else { return }
            do {
                let data = try Data(contentsOf: url)
                let document = try Document(data: data)
                self.open(document: document, at: url, backend: backend, environment: environment)
            } catch {
                // Reported rather than swallowed. A file that is not what it
                // claims to be is ordinary, and an open that silently does
                // nothing is indistinguishable from a menu item that is broken.
                // 回報而非吞掉。「一個檔案並不是它所宣稱的東西」是常態，而一次「靜默地什麼都沒做」的
                // 開啟，與一個壞掉的選單項目無從分辨。
                logger.warning(
                    "could not open document",
                    metadata: ["url": "\(url.path)", "error": "\(error)"]
                )
            }
        }

        for (id, window) in windows {
            window.update(
                windowScene(for: id, backend: backend, environment: environment),
                backend: backend,
                environment: environment
            )
        }
    }

    /// The readable content types, for whoever presents the open dialog.
    /// 可讀取的內容型別，供呈現開啟對話框的一方使用。
    static var readableContentTypes: [ContentType] { Document.readableContentTypes }

    private func windowScene<Backend: BaseAppBackend>(
        for id: UUID,
        backend: Backend,
        environment: EnvironmentValues
    ) -> DocumentWindowScene<Content> {
        let editor = scene.editor
        return DocumentWindowScene(
            title: documents[id]?.title ?? "Untitled",
            content: { [weak self] in
                editor(
                    Binding(
                        get: { self?.documents[id]?.document ?? Document() },
                        set: { newValue in
                            self?.documents[id]?.document = newValue
                        }
                    )
                )
            }
        )
    }

    private func open<Backend: BaseAppBackend>(
        document: Document,
        at url: URL?,
        backend: Backend,
        environment: EnvironmentValues
    ) {
        let id = UUID()
        documents[id] = OpenDocument(document: document, url: url)

        let reference = WindowReference(
            scene: windowScene(for: id, backend: backend, environment: environment),
            backend: backend,
            environment: environment,
            onClose: { [weak self] in
                self?.windows[id] = nil
                self?.documents[id] = nil
            },
            // The id a backend restores a window's frame by. Per DOCUMENT rather
            // than per document group: two open files should not fight over one
            // remembered frame, and a file reopened later lands where it was.
            // backend 用來還原視窗框的 id。以**文件**為單位而非以 document group 為單位：兩個開啟的
            // 檔案不該爭奪同一個被記住的框，而一個稍後重新開啟的檔案應該落在它原來的位置。
            id: url?.path ?? "swiftcrossui.document.\(id.uuidString)"
        )
        windows[id] = reference
        reference.update(nil, backend: backend, environment: environment)
    }
}
