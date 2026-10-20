import Foundation
@_spi(Backends) import SwiftCrossUI
import UWP
import WinAppSDK
import WinSDK
@preconcurrency import WindowsFoundation

/// The URL a second launch carries, delivered to the instance already running.
///
/// `onLaunched` sees only this process's own launch, so a URL sent to a running
/// app started a second window instead and the first never heard of it: P78 read
/// "received 1" at best, where macOS reads 2 (2026-10-20). Every launch registers
/// with `AppInstance` under a key made from the executable's path; the first one
/// owns it. A later launch that carries a URL hands its activation to the owner
/// and exits. A launch without one starts its own instance as before -- desktop
/// apps on Windows may run twice, and that is not changed here.
///
/// 第二次啟動所帶的 URL,交給已在執行的實例。
///
/// `onLaunched` 只看得到本行程自己的啟動，因此送給執行中 app 的 URL 反而開了第二個視窗，第一個從未得知:P78
/// 最多讀到「received 1」,而 macOS 讀到 2(2026-10-20)。每次啟動都以執行檔路徑做成的 key 向 `AppInstance`
/// 註冊，第一個成為擁有者。之後帶 URL 的啟動把它的 activation 交給擁有者並結束；不帶 URL 的啟動照舊開自己的實例
/// ——Windows 上的桌面 app 可以執行兩份，這裡不改變這一點。
extension WinUIApplication {
    nonisolated(unsafe) private static var registeredInstance: AppInstance?
    nonisolated(unsafe) private static var activatedCleanup: EventCleanup?

    /// Called before `Application.start`. Returns true when this launch was
    /// handed to the running instance and the process should exit.
    /// 在 `Application.start` 之前呼叫。此次啟動已交給執行中的實例、行程應結束時回傳 true。
    static func redirectToRunningInstance() -> Bool {
        let path = (Bundle.main.executablePath ?? CommandLine.arguments.first ?? "app").lowercased()
        let key = "scui:" + path.map { $0.isLetter || $0.isNumber || $0 == "." ? $0 : "_" }
        guard let instance = AppInstance.findOrRegisterForKey(key) else { return false }
        if instance.isCurrent {
            registeredInstance = instance
            return false
        }
        guard url(inCommandLine: CommandLine.arguments.dropFirst().joined(separator: " ")) != nil,
            let arguments = try? AppInstance.getCurrent()?.getActivatedEventArgs(),
            let action = try? instance.redirectActivationToAsync(arguments)
        else { return false }
        // Waited for here: the owner reads the activation from this process, and
        // exiting first loses it. / 在此等待：擁有者是從本行程讀取 activation,先結束就會遺失。
        let done = CreateEventW(nil, true, false, nil)
        action.completed = { _, _ in SetEvent(done) }
        WaitForSingleObject(done, 5000)
        CloseHandle(done)
        logger.info("WinUIApplication: handed the launch URL to the running instance")
        return true
    }

    /// Called on the UI thread once it has a dispatcher queue: from then on a
    /// redirected launch's URL reaches `receive(_:)` there.
    /// 在 UI 執行緒有了 dispatcher queue 之後呼叫：此後被轉送之啟動的 URL 會在那裡到達 `receive(_:)`。
    static func listenForRedirectedLaunches() {
        guard let instance = registeredInstance, activatedCleanup == nil,
            let queue = WinAppSDK.DispatcherQueue.getForCurrentThread()
        else { return }
        activatedCleanup = instance.activated.addHandler { _, arguments in
            guard let arguments, arguments.kind == .launch else { return }
            guard let launch = arguments.data as? AnyILaunchActivatedEventArgs else {
                logger.warning("WinUIApplication: a redirected launch carried no launch arguments")
                return
            }
            guard let url = url(inCommandLine: launch.arguments) else { return }
            _ = try? queue.tryEnqueue(.normal) {
                receive(url)
            }
        }
    }

    /// The first argument that is a URL with a scheme of two letters or more, so
    /// `C:\x` stays a path. / 第一個 scheme 至少兩個字母的 URL 引數，因此 `C:\x` 仍是路徑。
    static func url(inCommandLine commandLine: String) -> URL? {
        for token in commandLine.split(separator: " ") {
            let argument = token.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if !argument.hasPrefix("-"), let url = URL(string: argument),
                let scheme = url.scheme, scheme.count > 1
            {
                return url
            }
        }
        return nil
    }
}
