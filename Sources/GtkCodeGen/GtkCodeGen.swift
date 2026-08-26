import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

struct CommandLineArguments {
    var girFile: URL
    var outputDirectory: URL
    var cGtkImport: String
}

@main
struct GtkCodeGen {
    static let cTypeReplacements: [String: String] = [
        "const char*": "String",
        "const gchar*": "String",
        "char*": "String",
        "gchar*": "String",
        "gboolean": "Bool",
        "gdouble": "Double",
        "guint": "UInt",
        "gint": "Int",
        "gfloat": "Float",
        "double": "Double",
        "GIcon*": "OpaquePointer",
        "GdkPixbuf*": "OpaquePointer",
        "GdkPaintable*": "OpaquePointer",
        "GtkSelectionModel*": "OpaquePointer?",
        "GtkListItemFactory*": "OpaquePointer?",
        "GtkTextTagTable*": "OpaquePointer?",
        "int": "Int",
    ]

    static let cTypesManuallyConverted: [String: String] = [
        "guint": "guint",
        "int": "CInt",
    ]

    /// Problematic signals which are excluded from the generated Swift
    /// wrappers for now.
    ///
    /// `format-value` is problematic because it expects you to return a
    /// string and then attempts to free the string when it's finished with
    /// it, leading to a crash if the signal doesn't return a valid string
    /// pointer (which it won't because our signal handlers never return
    /// values with the current implementation).
    ///
    /// `populate-popup` was disabled because it crashed Gtk3 on Rocky
    /// Linux 8 whenever a user right clicked an Entry. Gtk3 support has since
    /// been dropped, so that reason no longer applies, but the signal is still
    /// unused and re-enabling it has not been tested against Gtk4.
    ///
    /// `select-all` and `unselect-all` are problematic because they
    /// clash with the methods of the same name that actually perform the
    /// actions. Will have to implement some better signal naming to avoid
    /// this issue if these ever need to be reintroduced.
    static let excludedSignals: [String] = [
        "format-value",
        "populate-popup",
        "notify::mnemonic-widget",
        "select-all",
        "unselect-all",
    ]

    static let excludedInterfaces: [String] = [
        "Orientable",
        "TreeModel",
        "PrintOperationPreview",
        "ColorChooser",
    ]

    /// Replacements applied to types which don't have the `ctype` attribute.
    static let typeNameReplacements: [String: String] = [
        "Gdk.Event": "GdkEvent",
        "Gdk.EventSequence": "OpaquePointer",
        "Gdk.GLContext": "OpaquePointer",
        "Gdk.Paintable": "OpaquePointer",
        "Gdk.Clipboard": "OpaquePointer",
        "Gdk.ModifierType": "GdkModifierType",
        "Pango.EllipsizeMode": "EllipsizeMode",
    ]

    static let interfaces: [String] = [
        "Gio.ListModel"
    ]

    static let unshorteningMap: [String: String] = [
        "char": "character",
        "str": "string",
    ]

    static let excludedConstructors: [String] = [
        "gtk_image_new_from_pixbuf",
        "gtk_picture_new_for_pixbuf",
    ]

    static func main() throws {
        let arguments = parseCommandLineArguments()
        let data = try loadGIRFileContents(arguments.girFile)
        let gir = try decodeGIR(data)

        try? FileManager.default.removeItem(at: arguments.outputDirectory)
        try FileManager.default.createDirectory(
            at: arguments.outputDirectory,
            withIntermediateDirectories: true
        )

        try generateSources(
            for: gir,
            to: arguments.outputDirectory,
            cGtkImport: arguments.cGtkImport
        )
    }

    static func generateSources(
        for gir: GIR,
        to directory: URL,
        cGtkImport: String
    ) throws {
        let allowListedClasses = [
            "Button",
            "Entry",
            "Label",
            "Range",
            "Scale",
            "Image",
            "Switch",
            "Spinner",
            "ProgressBar",
            "FileChooserNative",
            "NativeDialog",
            "GestureClick",
            "GestureSingle",
            "Gesture",
            "EventController",
            "GestureLongPress",
            "GLArea",
            "DrawingArea",
            "CheckButton",
            "Calendar",
            "SpinButton",
        ]
        let gtk4AllowListedClasses = [
            "Picture",
            "DropDown",
            "Popover",
            "ListBox",
            "EventControllerMotion",
            "EventControllerKey",
        ]

        for class_ in gir.namespace.classes {
            guard
                allowListedClasses.contains(class_.name)
                || (gir.namespace.version == "4.0"
                    && gtk4AllowListedClasses.contains(class_.name))
            else {
                continue
            }
            let source = generateClass(
                class_,
                namespace: gir.namespace,
                cGtkImport: cGtkImport
            )
            try save(source.description, to: directory, declName: class_.name)
        }

        for enumeration in gir.namespace.enumerations {
            // Enums that aren't available in base 4.10 shouldn't be generated.
            guard enumeration.version == nil else {
                continue
            }

            // The 'License' enum has a case that doesn't seem to exist in some Gtk versions
            guard enumeration.name != "License" else {
                continue
            }

            let source = generateEnum(enumeration, namespace: gir.namespace, cGtkImport: cGtkImport)
            try save(source.description, to: directory, declName: enumeration.name)
        }

        for interface in gir.namespace.interfaces {
            guard !excludedInterfaces.contains(interface.name) else {
                continue
            }

            // Skip interfaces which were added since 4.0
            guard interface.version == nil else {
                continue
            }
            let source = generateProtocol(
                interface,
                namespace: gir.namespace,
                cGtkImport: cGtkImport
            )
            try save(source.description, to: directory, declName: interface.name)
        }
    }

    static func generateProtocol(
        _ interface: Interface,
        namespace: Namespace,
        cGtkImport: String
    ) -> String {
        var properties: [DeclSyntax] = []
        for property in interface.properties where property.version == nil {
            if let syntax = generateProperty(
                property,
                namespace: namespace,
                classLike: interface,
                forProtocol: true
            ) {
                properties.append(syntax)
            }
        }

        var signalProperties: [DeclSyntax] = []
        for signal in interface.signals {
            guard !excludedSignals.contains(signal.name) else {
                continue
            }

            signalProperties.append(
                generateSignalHandlerProperty(
                    signal,
                    className: "Self",
                    forProtocol: true,
                    namespace: namespace
                )
            )
        }

        let source = SourceFileSyntax(
            """
            import \(raw: cGtkImport)

            \(raw: docComment(interface.doc))
            public protocol \(raw: interface.name): GObjectRepresentable {
                \(raw: properties.map(\.description).joined(separator: "\n\n"))

                \(raw: signalProperties.map(\.description).joined(separator: "\n\n"))
            }
            """
        )
        return source.description
    }

    static func generateEnum(
        _ enumeration: Enumeration,
        namespace: Namespace,
        cGtkImport: String
    ) -> String {
        // Filter out deprecated members and members which were introduced after 4.0
        let members = enumeration.members.filter { member in
            guard
                member.version == nil,
                member.docDeprecated == nil
            else {
                return false
            }
            // Can cause problems with gtk versions older than 4.20.0
            guard
                !(member.cIdentifier == "GTK_PAD_ACTION_DIAL"
                    && enumeration.name == "PadActionType")
            else {
                return false
            }

            if let doc = member.doc {
                // Why they gotta be inconsistent like that 💀
                return !doc.contains("Since: ") && !doc.contains("Since ")
            } else {
                return true
            }
        }

        var cases: [DeclSyntax] = []
        for case_ in members {
            let name = convertCIdentifier(case_.name)
            cases.append(
                DeclSyntax(
                    """
                    \(raw: docComment(case_.doc))
                    case \(raw: name)
                    """
                )
            )
        }

        var toGtkConversionSwitchCases: [SwitchCaseSyntax] = []
        for case_ in members {
            let name = convertCIdentifier(case_.name)
            toGtkConversionSwitchCases.append(
                SwitchCaseSyntax(
                    """
                    case .\(raw: name):
                        return \(raw: case_.cIdentifier)
                    """
                )
            )
        }

        var fromGtkConversionSwitchCases: [SwitchCaseSyntax] = []
        for case_ in members {
            let name = convertCIdentifier(case_.name)
            fromGtkConversionSwitchCases.append(
                SwitchCaseSyntax(
                    """
                    case \(raw: case_.cIdentifier):
                        self = .\(raw: name)
                    """
                )
            )
        }

        // In some earlier versions of Gtk 3, G_TYPE_ENUM is abstract and can't be used
        // as a catch-all type for enum values when setting GObject properties, so we
        // have to dynamically fetch the type for the enum instead of letting it default
        // to G_TYPE_ENUM.
        let typeIdentifier = convertCamelCasingToSnake(enumeration.cType)
        let typeProperty = """
            public static var type: GType {
                \(typeIdentifier)_get_type()
            }
            """

        let source = SourceFileSyntax(
            """
            import \(raw: cGtkImport)

            \(raw: docComment(enumeration.doc))
            public enum \(raw: enumeration.name): GValueRepresentableEnum {
                public typealias GtkEnum = \(raw: enumeration.cType)

                \(raw: cases.map(\.description).joined(separator: "\n"))

                \(raw: typeProperty)

                public init(from gtkEnum: \(raw: enumeration.cType)) {
                    switch gtkEnum {
                        \(
                            raw: fromGtkConversionSwitchCases.map(\.description).joined(
                                separator: "\n"
                            )
                        )
                        default:
                            fatalError("Unsupported \(raw: enumeration
                .cType) enum value: \\(gtkEnum.rawValue)")
                    }
                }

                public func toGtk() -> \(raw: enumeration.cType) {
                    switch self {
                        \(raw: toGtkConversionSwitchCases.map(\.description)
                .joined(separator: "\n"))
                    }
                }
            }
            """
        )
        return source.description
    }

    static func docComment(_ doc: String?) -> String {
        // TODO: Parse comment format to replace image includes, links, and similar
        doc?
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .enumerated()
            .map {
                $0.offset == 0
                    ? $0.element.prefix(1).capitalized + $0.element.dropFirst() : $0.element
            }
            .map { "/// \($0)" }
            .joined(separator: "\n") ?? ""
    }

    static func generateClass(_ class_: Class, namespace: Namespace, cGtkImport: String) -> String {
        var initializers: [DeclSyntax] = []
        for constructor in class_.constructors {
            guard
                constructor.deprecated != 1
                || constructor.cIdentifier == "gtk_dialog_new"
                || constructor.cIdentifier == "gtk_file_chooser_native_new"
            else {
                continue
            }

            guard !excludedConstructors.contains(constructor.cIdentifier) else {
                continue
            }

            let excludedParameterTypes: [String] = [
                "GListModel*",
                "GFile*",
                "cairo_surface_t*",
                "GdkPixbufAnimation*",
            ]
            if let type = constructor.parameters?.parameters.first?.type?.cType,
               excludedParameterTypes.contains(type)
            {
                continue
            }

            // We just silently skip initializers that require features we don't support.
            guard let initializer = generateInitializer(constructor) else {
                continue
            }

            initializers.append(initializer)
        }

        var properties: [DeclSyntax] = []
        for (classLike, property) in class_.getAllImplemented(\.properties, namespace: namespace) {
            guard
                property.version == nil || property.version == "3.2" || property.version == "2.6",
                property.name != "child",
                let decl = generateProperty(
                    property,
                    namespace: namespace,
                    classLike: classLike,
                    forProtocol: false
                )
            else {
                continue
            }
            properties.append(decl)
        }

        // TODO: Refactor so that notify::property signal handlers aren't just hacked into the
        //   signal handler generation code so jankily. Ideally we should decouple the signal generation
        //   code from the GIR types a bit more so that we can synthesize signals without having to
        //   create fake GIR entries.
        var seenProperties: Set<String> = []
        var signals = class_.getAllImplemented(\.signals, namespace: namespace)
        for (classLike, property) in class_.getAllImplemented(\.properties, namespace: namespace) {
            // Sometimes there are duplicates (presumably with different values of `when`),
            // so we only generate the first occurence.
            guard !seenProperties.contains(property.name) else {
                continue
            }
            seenProperties.insert(property.name)

            signals.append(
                (
                    classLike,
                    Signal(
                        name: "notify::\(property.name)",
                        when: "before",
                        returnValue: ReturnValue(
                            nullable: false,
                            doc: "",
                            type: property.type
                        ),
                        parameters: Parameters(parameters: [
                            Parameter(
                                nullable: false,
                                name: "object",
                                transferOwnership: "",
                                doc: "",
                                type: GIRType.init(name: "OpaquePointer", cType: "OpaquePointer")
                            )
                        ])
                    )
                )
            )
        }

        signals = signals.filter { (_, signal) in
            !excludedSignals.contains(signal.name)
        }

        for (_, signal) in signals {
            properties.append(
                generateSignalHandlerProperty(
                    signal,
                    className: class_.name,
                    forProtocol: false,
                    namespace: namespace
                )
            )
        }

        var conformances: [String] = []
        if let parent = class_.parent {
            if parent == "GObject.Object" {
                conformances.append("GObject")
            } else {
                conformances.append(parent)
            }
        }

        for conformance in class_.getImplementedInterfaces(
            namespace: namespace,
            excludeInherited: true
        ) {
            conformances.append(conformance.name)
        }

        let conformanceString: String
        if conformances.isEmpty {
            conformanceString = ""
        } else {
            conformanceString = ": \(conformances.joined(separator: ", "))"
        }

        var inheritanceChain = [class_.name]
        var parent = class_.getParentClass(namespace: namespace)
        while let currentParent = parent {
            inheritanceChain.append(currentParent.name)
            parent = currentParent.getParentClass(namespace: namespace)
        }

        var methods: [DeclSyntax] = []
        if !signals.isEmpty {
            methods.append(
                generateSignalRegistrationMethod(
                    signals.map { signal in
                        signal.1
                    },
                    namespace: namespace
                )
            )
        }

        let source = SourceFileSyntax(
            """
            import \(raw: cGtkImport)

            \(raw: docComment(class_.doc))
            open class \(raw: class_.name)\(raw: conformanceString) {
                \(raw: initializers.map(\.description).joined(separator: "\n\n"))

                \(raw: methods.map(\.description).joined(separator: "\n\n"))

                \(raw: properties.map(\.description).joined(separator: "\n\n"))
            }
            """
        )
        return source.description
    }

    static func save(_ source: String, to directory: URL, declName: String) throws {
        let file = directory.appendingPathComponent("\(declName).swift")
        let alteredSource = """
            // This file was generated by GtkCodeGen. Do not edit it directly. Edit
            // Sources/GtkCodeGen instead, or move this source file out of the
            // Generated directory and remove it from the GtkCodeGen class allow list.

            // swiftformat:options --allow-partial-wrapping true
            \(source)
            """
        try alteredSource.write(to: file, atomically: false, encoding: .utf8)
    }

    /// The Swift type a signal's handler should return, or `nil` for the void
    /// signals, which are most of them.
    ///
    /// Emitting `-> Void` for a signal that returns a value -- which is all this
    /// generator used to do -- means GTK reads whatever the ABI left behind, so a
    /// `gboolean` handler can never report "handled, stop propagating". That is
    /// issue #594; see `ReturningSignalBox0` in the Gtk target.
    ///
    /// signal 的處理常式應回傳的 Swift 型別；對多數的 void signal 則為 `nil`。
    ///
    /// 對「有回傳值」的 signal 輸出 `-> Void`——那正是本產生器過去的唯一行為——會使 GTK 讀到 ABI
    /// 遺留的內容，因此 `gboolean` 的處理常式永遠無法回報「已處理、停止傳播」。此即 issue #594；
    /// 參見 Gtk target 中的 `ReturningSignalBox0`。
    static func signalReturnType(_ signal: Signal, namespace: Namespace) -> String? {
        // `notify::` signals are synthesised from properties by this generator
        // (see the TODO about that hack), and the Signal they are handed carries
        // the *property's* type in returnValue rather than a signal return type.
        // They all return void, so reading that field would turn every property
        // notification into a bogus returning signal.
        //
        // `notify::` signal 是本產生器由屬性合成的（見關於該 hack 的 TODO），其 Signal 的
        // returnValue 帶的是*屬性*的型別，而非 signal 的回傳型別。它們全都回傳 void，因此讀取該
        // 欄位會使每一個屬性通知都變成錯誤的 returning signal。
        guard !signal.name.hasPrefix("notify::") else { return nil }

        return signal.returnValue.type.flatMap { girType -> String? in
            let type = swiftType(girType, namespace: namespace)
            // GIR's `none` comes through as `void` (lowercase, the C spelling)
            // as well as `Void`; neither is a return type worth emitting.
            // GIR 的 `none` 會以 `void`（小寫，即 C 的寫法）或 `Void` 的形式出現，兩者皆非值得
            // 輸出的回傳型別。
            guard type != "Void", type != "void" else { return nil }

            // Only types with an obvious "no answer" value, because a signal
            // that returns something has to return it even when the app set no
            // handler. `false` and `0` are what GTK saw before any of this
            // existed, so they change nothing for an unhandled signal. A pointer
            // return (GLArea's `create-context`) has no such value -- null would
            // be a claim, not an absence -- so it keeps the void form it always
            // had rather than inventing an answer.
            //
            // 僅限具有明確「無答案」值的型別，因為有回傳值的 signal 即使 app 未設定處理常式也必須
            // 回傳一個值。`false` 與 `0` 正是此機制存在之前 GTK 所讀到的內容，因此對未處理的 signal
            // 而言毫無改變。回傳指標者（GLArea 的 `create-context`）沒有這樣的值——null 是一種
            // 主張而非「沒有答案」——因此維持它原本就有的 void 形式，而不憑空給出一個答案。
            let hasUnhandledValue = ["Bool", "Int", "UInt", "Int32", "UInt32"].contains(type)
            return hasUnhandledValue ? type : nil
        }
    }

    static func generateSignalRegistrationMethod(
        _ signals: [Signal],
        namespace: Namespace
    ) -> DeclSyntax {
        var exprs: [String] = []

        for (signalIndex, signal) in signals.enumerated() {
            let parameterCount = signal.parameters?.parameters.count ?? 0

            let parameterTypes = (signal.parameters?.parameters ?? []).map { parameter in
                guard let girType = parameter.type else {
                    fatalError(
                        "Missing c type for parameter '\(parameter.name)' of signal '\(signal.name)'"
                    )
                }
                var type = swiftType(girType, namespace: namespace)
                if type == "String" {
                    type = "UnsafePointer<CChar>"
                } else if type == "GtkListBoxRow" {
                    // [NOTE:1]
                    // Just a hardcoded hack for now. Not sure how else we're
                    // meant to know that the row-selected and row-activated
                    // signals on ListBox take their parameters as pointers
                    // instead of raw structs (without looking into the C code).
                    // We could probably look through all classes and if we find
                    // one matching the parameter type assume it's a pointer?
                    type = "UnsafeMutablePointer<\(type)>\(parameter.nullable == true ? "?" : "")"
                }
                return type
            }
            let name = convertDelimitedCasingToCamel(
                signal.name.replacingOccurrences(of: "::", with: "-"),
                delimiter: "-"
            )

            let parameters = parameterTypes.enumerated().map { (index, type) in
                "param\(index): \(type)"
            }.joined(separator: ", ")

            let extraArguments = (0..<parameterCount).map { index in
                "param\(index)"
            }
            let arguments = (["self"] + extraArguments).joined(separator: ", ")

            // Signals that return a value get a handler that actually returns
            // it. Emitting `-> Void` for these -- which is all the generator used
            // to do -- meant GTK read whatever the ABI left behind, so a
            // `gboolean` handler could never report "handled, stop propagating".
            // That is issue #594; see ReturningSignalBox0 in the Gtk target.
            //
            // Only where a returning box exists for the arity (0-3, which covers
            // every returning signal in the allow-listed classes). Anything else
            // keeps the void form, which is no worse than before.
            //
            // 有回傳值的 signal 會取得真正回傳該值的處理常式。過去產生器一律輸出 `-> Void`，
            // 使 GTK 讀到 ABI 遺留的內容，因此 `gboolean` 的處理常式永遠無法回報「已處理、停止
            // 傳播」。此即 issue #594；參見 Gtk target 中的 ReturningSignalBox0。
            //
            // 僅在該 arity 存在對應的 returning box 時採用（0-3，已涵蓋 allow-list 類別中每一個
            // 有回傳值的 signal）。其餘情況維持 void 形式，不會比先前更差。
            let returnType = signalReturnType(signal, namespace: namespace)
            let returnsValue = returnType != nil && parameterCount <= 3

            let closure: ExprSyntax
            if let returnType, returnsValue {
                // A signal that returns a value has to produce one even when the
                // app set no handler. `false`/zero is the "not handled, carry on"
                // answer for every returning signal here, and matches what GTK
                // saw before this existed.
                //
                // 有回傳值的 signal 即使 app 未設定處理常式也必須產生一個值。對此處每一個有回傳值
                // 的 signal 而言，`false`／零即代表「未處理，請繼續」，也與此機制存在之前 GTK 所
                // 讀到的結果一致。
                let fallback = returnType == "Bool" ? "false" : "0"
                closure = ExprSyntax(
                    """
                    { [weak self] (\(raw: parameters)) -> \(raw: returnType) in
                        guard let self, let handler = self.\(raw: name) else { return \(
                            raw: fallback
                        ) }
                        return handler(\(raw: arguments))
                    }
                    """
                )
            } else {
                closure = ExprSyntax(
                    """
                    { [weak self] (\(raw: parameters)) in
                        guard let self else { return }
                        self.\(raw: name)?(\(raw: arguments))
                    }
                    """
                )
            }
            let expr: ExprSyntax
            if returnsValue, let returnType {
                let typeParameters = parameterTypes.joined(separator: ", ")
                let boxTypeParameters =
                    (parameterTypes + [returnType]).joined(separator: ", ")
                let cParameters =
                    (["UnsafeMutableRawPointer"] + parameterTypes
                        + ["UnsafeMutableRawPointer"]).joined(separator: ", ")
                let values = (1...max(parameterCount, 1)).prefix(parameterCount)
                    .map { "value\($0)" }
                let cArguments = (["_"] + values + ["data"]).joined(separator: ", ")
                let runArguments = (["data"] + values).joined(separator: ", ")
                _ = typeParameters
                exprs.append(
                    DeclSyntax(
                        """
                        let handler\(raw: signalIndex): @convention(c) (
                            \(raw: cParameters)
                        ) -> \(raw: returnType) = { \(raw: cArguments) in
                            ReturningSignalBox\(raw: parameterCount)<\(
                                raw: boxTypeParameters
                            )>.run(\(raw: runArguments))
                        }
                        """
                    ).description
                )
                expr = ExprSyntax(
                    """
                    addReturningSignal(name: \(literal: signal.name), handler: gCallback(handler\(
                        raw: signalIndex
                    ))) \(raw: closure)
                    """
                )
                exprs.append(expr.description)
                continue
            }
            if parameterCount == 0 {
                expr = ExprSyntax(
                    """
                    addSignal(name: \(literal: signal.name)) \(raw: closure)
                    """
                )
            } else {
                let typeParameters = parameterTypes.joined(separator: ", ")

                let arguments = (1...parameterCount).map { "value\($0)" }.joined(separator: ", ")
                exprs.append(
                    DeclSyntax(
                        """
                        let handler\(raw: signalIndex): @convention(c) (
                            UnsafeMutableRawPointer, \(raw: typeParameters), UnsafeMutableRawPointer
                        ) -> Void = { _, \(raw: arguments), data in
                            SignalBox\(raw: parameterCount)<\(raw: typeParameters)>.run(data, \(
                                raw: arguments
                            ))
                        }
                        """
                    ).description
                )
                expr = ExprSyntax(
                    """
                    addSignal(name: \(literal: signal.name), handler: gCallback(handler\(
                        raw: signalIndex
                    ))) \(raw: closure)
                    """
                )
            }
            exprs.append(expr.description)
        }

        let methodName = "registerSignals"

        return DeclSyntax(
            """
            open override func \(raw: methodName)() {
                super.\(raw: methodName)()

                \(raw: exprs.joined(separator: "\n\n"))
            }
            """
        )
    }

    static func generateSignalHandlerProperty(
        _ signal: Signal,
        className: String,
        forProtocol: Bool,
        namespace: Namespace
    ) -> DeclSyntax {
        let parameterTypes = (signal.parameters?.parameters ?? []).map { parameter in
            guard let girType = parameter.type else {
                fatalError(
                    "Missing c type for parameter '\(parameter.name)' of signal '\(signal.name)'"
                )
            }
            var type = swiftType(girType, namespace: namespace)
            if type == "String" {
                type = "UnsafePointer<CChar>"
            } else if type == "GtkListBoxRow" {
                // See [NOTE:1]
                type = "UnsafeMutablePointer<\(type)>\(parameter.nullable == true ? "?" : "")"
            }
            return type
        }
        let parameters = ([className] + parameterTypes).joined(separator: ", ")

        let name = convertDelimitedCasingToCamel(
            signal.name.replacingOccurrences(of: "::", with: "-"),
            delimiter: "-"
        )
        var prefix = ""
        var suffix = ""
        if forProtocol {
            suffix = " { get set }"
        } else {
            prefix = "public "
        }
        // The handler's return type mirrors the signal's, so a caller can answer
        // a `gboolean` signal with "handled, stop propagating" -- see issue #594
        // and ReturningSignalBox0. Kept in step with the arities the registration
        // side can emit a returning handler for.
        //
        // 處理常式的回傳型別與 signal 一致，使呼叫端能對 `gboolean` signal 回答「已處理、停止
        // 傳播」——見 issue #594 與 ReturningSignalBox0。與註冊端能輸出 returning 處理常式的
        // arity 保持一致。
        let parameterCount = signal.parameters?.parameters.count ?? 0
        let returnType = signalReturnType(signal, namespace: namespace)
        let handlerReturnType = (parameterCount <= 3 ? returnType : nil) ?? "Void"

        return DeclSyntax(
            """
            \(raw: docComment(signal.doc))
            \(raw: prefix)var \(raw: name): ((\(raw: parameters)) -> \(raw: handlerReturnType))?\(
                raw: suffix
            )
            """
        )
    }

    static func generateProperty(
        _ property: Property,
        namespace: Namespace,
        classLike: any ClassLike,
        forProtocol: Bool
    ) -> DeclSyntax? {
        guard let getterName = property.getter else {
            return nil
        }

        guard let girType = property.type else {
            fatalError("Missing type for '\(classLike.name).\(property.name)'")
        }

        var type = swiftType(girType, namespace: namespace)
        let getterFunction = "\(namespace.cSymbolPrefix)_\(classLike.cSymbolPrefix)_\(getterName)"

        guard
            let method = classLike.methods.first(where: { method in
                method.cIdentifier == getterFunction
            })
        else {
            print(property)
            fatalError("'\(classLike.name)' is missing method matching '\(getterFunction)'")
        }

        // TODO: Handle this conversion more cleanly
        if type.hasPrefix("Gtk") {
            type = String(type.dropFirst(3))
        }

        if !cTypeReplacements.values.contains(type)
            && !typeNameReplacements.values.contains(type)
            && !namespace.enumerations.contains(where: { $0.name == type })
            && type != "OpaquePointer"
        {
            print("Skipping \(property.name) with type \(type)")
            // TODO: Handle more types
            return nil
        }

        if method.returnValue?.nullable == true {
            type += "?"
        }

        // TODO: Figure out why DropDown.selected doesn't work as a UInt (Gtk complains that
        //   the property doesn't hold a UInt, implying that the docs are wrong??)
        if classLike.name == "DropDown" && property.name == "selected" {
            type = "Int"
        }

        guard !type.contains(".") else {
            // TODO: Handle namespaced types
            return nil
        }

        var prefix = ""
        var suffix = ""
        if forProtocol {
            suffix = " { get set }"
        } else {
            let literal = StringLiteralExprSyntax(content: property.name).description
            prefix = "@GObjectProperty(named: \(literal)) public "
        }

        return DeclSyntax(
            """
            \(raw: docComment(property.doc))
            \(raw: prefix)var \(raw: convertPropertyName(property.name)): \(raw: type)\(raw: suffix)
            """
        )
    }

    static func swiftType(_ type: GIRType, namespace: Namespace) -> String {
        if let cType = type.cType {
            return convertCType(cType)
        } else if let name = type.name {
            if interfaces.contains(name) {
                return "OpaquePointer"
            } else if let replacement = typeNameReplacements[name] {
                return replacement
            } else {
                return namespace.cIdentifierPrefix + name
            }
        } else {
            fatalError("Type has no valid name")
        }
    }

    static func generateInitializer(_ constructor: Constructor) -> DeclSyntax? {
        guard
            let parameters = generateParameters(
                constructor.parameters,
                constructorName: constructor.name
            )
        else {
            return nil
        }

        return DeclSyntax(
            """
            \(raw: docComment(constructor.doc))
            public convenience init(\(raw: parameters)) {
                self.init(
                    \(raw: constructor
                .cIdentifier)(\(raw: generateArguments(constructor.parameters)))
                )
            }
            """
        )
    }

    static func generateParameters(
        _ parameters: Parameters?,
        constructorName: String? = nil
    ) -> String? {
        guard var parameters = parameters?.parameters, !parameters.isEmpty else {
            return ""
        }

        // We don't support wrapping variadic functions (sounds like a political statement).
        guard
            !parameters.contains(where: { parameter in
                parameter.name == "..."
            })
        else {
            return nil
        }

        for (i, parameter) in parameters.enumerated() {
            parameters[i].name = convertCIdentifier(parameter.name)
        }

        // TODO: Fix for `gtk_scale_new_with_range`
        // Add a label to the first parameter name based on the constructor name if possible (to
        // avoid ambiguity between certain initializers). E.g. `gtk_button_new_with_label` and
        // `gtk_button_new_with_mnemonic` both call their first parameter `label` which would be
        // ambiguous in Swift.
        if let constructorName, constructorName.contains("_with_") {
            let label = convertCIdentifier(
                String(constructorName.components(separatedBy: "_with_")[1])
            )
            let parameterName = parameters[0].name
            if label != parameterName {
                parameters[0].name = "\(label) \(parameterName)"
            }
        }

        return
            parameters
                .map { parameter in
                    if let type = parameter.type?.cType {
                        return "\(parameter.name): \(convertCType(type))"
                    } else if let arrayElementType = parameter.array?.type.cType {
                        return "\(parameter.name): [\(convertCType(arrayElementType))]"
                    } else {
                        fatalError("Missing type for '\(parameter.name)'")
                    }
                }
                .joined(separator: ", ")
    }

    static func generateArguments(_ parameters: Parameters?) -> String {
        return parameters?.parameters.map { parameter in
            let name = convertCIdentifier(parameter.name)
            var argument = name

            // TODO: Handle nested pointer arrays more generally
            if parameter.array?.type.cType == "char*" {
                argument = """
                    \(argument)
                        .map({ UnsafePointer($0.unsafeUTF8Copy().baseAddress) })
                        .unsafeCopy()
                        .baseAddress!
                    """
            } else if
                let type = parameter.type?.cType,
                let destinationType = cTypesManuallyConverted[type]
            {
                return "\(destinationType)(\(argument))"
            }

            return argument
        }
        .joined(separator: ", ") ?? ""
    }

    static func convertCIdentifier(_ identifier: String) -> String {
        let keywords = ["true", "false", "default", "switch", "import", "private", "class", "in"]
        if keywords.contains(identifier) {
            return "\(identifier)_"
        }
        var identifier = identifier
        if identifier.starts(with: "0") {
            identifier = "zero_" + identifier.dropFirst()
        }
        return convertDelimitedCasingToCamel(identifier, delimiter: "_")
    }

    static func convertPropertyName(_ name: String) -> String {
        return convertDelimitedCasingToCamel(name, delimiter: "-", unshorten: true)
    }

    static func convertDelimitedCasingToCamel(
        _ identifier: String,
        delimiter: Character,
        unshorten: Bool = false
    ) -> String {
        var parts = identifier.split(separator: delimiter).map(String.init)
        for (i, part) in parts.enumerated() {
            if let replacement = unshorteningMap[part] {
                parts[i] = replacement
            }
        }
        let first = parts.removeFirst()
        return first + parts.map(\.capitalized).joined()
    }

    static func convertCamelCasingToSnake(_ identifier: String) -> String {
        var words: [[Character]] = []
        var word: [Character] = []
        for character in identifier {
            if character.isUppercase {
                if !word.isEmpty {
                    words.append(word)
                }
                word = [Character](character.lowercased())
            } else {
                word.append(character)
            }
        }
        if !word.isEmpty {
            words.append(word)
        }
        var characters: [Character] = []
        var previousWasSingleLetter = false
        for (i, word) in words.enumerated() {
            if i == 0 {
                characters.append(contentsOf: word)
            } else if previousWasSingleLetter && word.count == 1 {
                characters.append(contentsOf: word)
            } else {
                characters.append("_")
                characters.append(contentsOf: word)
            }

            if word.count == 1 {
                previousWasSingleLetter = true
            }
        }
        return String(characters)
    }

    static func convertCType(_ cType: String) -> String {
        if let replacement = cTypeReplacements[cType] {
            return replacement
        }

        var type = cType
        if type.last == "*" {
            let pointeeType = convertCType(String(type.dropLast()))
            type = "UnsafeMutablePointer<\(pointeeType)>!"
        }
        return type
    }

    static func parseCommandLineArguments() -> CommandLineArguments {
        let arguments = ProcessInfo.processInfo.arguments

        let helpRequested = arguments.contains("--help") || arguments.contains("-h")
        let invalid = arguments.count != 4 && !helpRequested
        if invalid || helpRequested {
            print("Usage: ./GtkCodeGen gtk_gir_file output_dir cgtk_import")
            Foundation.exit(invalid ? 1 : 0)
        }

        return CommandLineArguments(
            girFile: URL(fileURLWithPath: arguments[1]),
            outputDirectory: URL(fileURLWithPath: arguments[2]),
            cGtkImport: arguments[3]
        )
    }

    static func loadGIRFileContents(_ file: URL) throws -> Data {
        return try Data(contentsOf: file)
    }
}
