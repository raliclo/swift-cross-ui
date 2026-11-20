import Foundation

/// General context required by all subcommands. Loads SCUI and SwiftUI, and
/// performs analysis.
struct Context {
    static let swiftUICoreInterfacePath = "MacOSX.sdk/System/Library/Frameworks/SwiftUICore.framework/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface"

    static let swiftUIInterfacePath = "MacOSX.sdk/System/Library/Frameworks/SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface"

    static let swiftCrossUIInterfacePath = ".build/debug/SwiftCrossUI.build/SwiftCrossUI.swiftinterface"
    /// Where swiftbuild writes the same interface, per architecture.
    /// swiftbuild 寫出同一個介面的位置，依架構而異。
    static let swiftBuildInterfacePaths = ["arm64", "x86_64"].map {
        ".build/out/Intermediates.noindex/swift-cross-ui.build/Debug/SwiftCrossUI-t.build/Objects-normal/\($0)/SwiftCrossUI.swiftinterface"
    }

    let swiftCrossUIAnalysis: Analyzer.Result
    let swiftUIAnalysis: Analyzer.Result
    let diff: Differ.Diff

    static func load(_ arguments: CommonArguments) throws -> Context {
        let swiftCrossUICheckout = arguments.swiftCrossUICheckout
            ?? URL.currentDirectory

        let developerDirectory: URL
        if let location = arguments.developerDirectory {
            developerDirectory = location
        } else {
            do {
                developerDirectory = try getDefaultDeveloperDirectory()
            } catch {
                throw GeneralError(
                    """
                    Failed to get default developer directory using \
                    'xcode-select --print-path'. Please provide the path to \
                    your active developer directory manually using \
                    '--developer-dir'. Cause: \(error.localizedDescription)
                    """
                )
            }
        }

        // If the developer directory points to a CommandLineTools installation
        // then the SDKs that we require are at a different location.
        let sdksDirectory: URL
        let cltSDKsDirectory = developerDirectory / "SDKs"
        if cltSDKsDirectory.exists() {
            sdksDirectory = cltSDKsDirectory
        } else {
            sdksDirectory = developerDirectory / "Platforms/MacOSX.platform/Developer/SDKs"
        }

        // Build SwiftCrossUI to prepare the required swiftinterface file
        let scuiInterfaceFile = try prepareSwiftCrossUISwiftInterface(
            checkout: swiftCrossUICheckout
        )

        // Load and analyze SwiftCrossUI swiftinterface
        let swiftCrossUI = try InterfaceLoader.loadInterface(
            scuiInterfaceFile,
            moduleName: "SwiftCrossUI"
        )
        let scuiResult = Analyzer.analyze(interfaces: [swiftCrossUI])

        // Load and analyze SwiftUI & SwiftUICore swiftinterfaces (as one)
        let swiftUICore = try InterfaceLoader.loadInterface(
            sdksDirectory / swiftUICoreInterfacePath,
            moduleName: "SwiftUICore"
        )
        let swiftUI = try InterfaceLoader.loadInterface(
            sdksDirectory / swiftUIInterfacePath,
            moduleName: "SwiftUI"
        )
        let swiftUIResult = Analyzer.analyze(interfaces: [swiftUICore, swiftUI])

        // Diff the two libraries
        let diff = Differ.diff(
            swiftCrossUIAnalysis: scuiResult,
            swiftUIAnalysis: swiftUIResult
        )

        return Context(
            swiftCrossUIAnalysis: scuiResult,
            swiftUIAnalysis: swiftUIResult,
            diff: diff
        )
    }

    /// Builds SwiftCrossUI with special arguments to produce the
    /// swiftinterface file that we need for our analyses.
    private static func prepareSwiftCrossUISwiftInterface(
        checkout swiftCrossUICheckout: URL
    ) throws -> URL {
        // Prepare a SwiftCrossUI swiftinterface
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "swift", "build",
            "--target", "SwiftCrossUI",
            "-Xswiftc", "-emit-module-interface"
        ]
        process.currentDirectoryPath = swiftCrossUICheckout.path
        do {
            try process.run()
        } catch {
            throw GeneralError(
                """
                Failed to build SwiftCrossUI swiftinterface: failed to launch \
                process: \(error.localizedDescription)
                """
            )
        }
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw GeneralError(
                """
                Failed to build SwiftCrossUI swiftinterface: non-zero exit \
                status '\(process.terminationStatus)'
                """
            )
        }

        // SwiftPM's native build system writes the interface to
        // `swiftCrossUIInterfacePath`; swiftbuild writes it under `.build/out`. The
        // newest of those is the one this build made, and an older one is stale.
        // SwiftPM 原生建置系統把介面寫到 `swiftCrossUIInterfacePath`;swiftbuild 則寫到 `.build/out`
        // 底下。其中最新的那一個才是這次建置產生的，較舊的已過時。
        let candidates = ([swiftCrossUIInterfacePath] + swiftBuildInterfacePaths).map {
            swiftCrossUICheckout / $0
        }
        let newest = candidates.compactMap { url -> (URL, Date)? in
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes?[.modificationDate] as? Date).map { (url, $0) }
        }.max { $0.1 < $1.1 }
        guard let (interface, _) = newest else {
            throw GeneralError(
                "Built SwiftCrossUI, but found no swiftinterface at any of: \(candidates.map(\.path))"
            )
        }
        return interface
    }

    /// Gets the user's default developer directory by running
    /// 'xcode-select --print-path'.
    private static func getDefaultDeveloperDirectory() throws -> URL {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "xcode-select", "--print-path"
        ]
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw GeneralError("non-zero exit status")
        }
        let pathData = pipe.fileHandleForReading.availableData
        guard let path = String(data: pathData, encoding: .utf8) else {
            throw GeneralError("process produced non-utf8 output")
        }
        let cleanedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: cleanedPath)
    }
}
