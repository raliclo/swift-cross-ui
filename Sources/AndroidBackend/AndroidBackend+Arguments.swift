import AndroidApp
import AndroidContent
import Foundation
import SwiftJava

/// Command-line arguments for a platform that has no command line.
///
/// `entrypoint` used to call `main(0, argv)` with `argv[0] = nil`: no arguments
/// at all. Everything downstream reads `CommandLine.arguments`, so on Android
/// `--debug` was never seen, ``DebugFeatures/isEnabled`` was always false, and
/// `-actionfile` could not be delivered even though `test_android.zsh` accepted
/// the flag and every other platform honours it. The script parsed the flag and
/// dropped it, which is the shape of failure this file exists to remove: an
/// option that is accepted and does nothing.
///
/// An Android activity is started with an `Intent`, and an intent carries
/// extras. `adb shell am start ... --es scui_args "--debug -actionfile /sdcard/x.csv"`
/// puts a string there, and this turns that string into argv before `main` runs,
/// so nothing downstream needs to know Android is different.
///
/// **The split is on spaces and that is a real limit.** A path containing a
/// space cannot be passed this way. Quoting would need a parser here and an
/// escaping convention in the script, and the paths this carries are ones the
/// harness chose -- `/data/local/tmp/...` -- so the limit costs nothing today.
/// It is written down rather than left to be discovered.
///
/// 給一個沒有命令列的平台的命令列引數。
///
/// `entrypoint` 原本呼叫的是 `main(0, argv)`，且 `argv[0] = nil`：完全沒有任何引數。而下游的一切
/// 都讀取 `CommandLine.arguments`，因此在 Android 上 `--debug` 從未被看見、
/// ``DebugFeatures/isEnabled`` 恆為 false，而 `-actionfile` 即使 `test_android.zsh` 接受了該旗標、
/// 其他每個平台也都遵守它，仍然無法送達。該腳本解析了那個旗標然後丟掉——而「一個被接受卻什麼都不做
/// 的選項」，正是本檔存在所要消除的那種失敗形狀。
///
/// Android 的 activity 是由 `Intent` 啟動的，而 intent 可攜帶 extra。
/// `adb shell am start ... --es scui_args "--debug -actionfile /sdcard/x.csv"` 會在其中放進一個
/// 字串，本檔則在 `main` 執行之前把該字串轉成 argv，使下游完全不需要知道 Android 有何不同。
///
/// **以空白切分，而那是一個真實的限制。** 含有空白的路徑無法以此方式傳遞。要支援它就需要在此處寫一個
/// parser、並在腳本端訂一套跳脫規則；而本機制所承載的路徑是由 harness 自己選定的
/// ——`/data/local/tmp/...`——因此這個限制在今天不造成任何代價。此處寫明，而非留待日後被發現。
extension Activity {
    /// Not in AndroidKit's generated `Activity`, so it is bound here.
    /// AndroidKit 產生的 `Activity` 中沒有這個方法，因此在此處綁定。
    @JavaMethod
    func getIntent() -> Intent!
}

enum AndroidLaunchArguments {
    /// The intent extra the harness writes. Namespaced, because an extra key is
    /// global to the intent and a plain name like `args` would collide with
    /// anything else that had the same idea.
    /// harness 所寫入的 intent extra。加上命名空間，因為 extra 的鍵在 intent 中是全域的，
    /// 而 `args` 這種樸素名稱會與任何有相同想法的東西相撞。
    static let extraKey = "scui_args"

    /// argv for `main`, with the executable name first.
    ///
    /// `argv[0]` is conventionally the program, and code that skips it -- as
    /// argument parsers do -- would otherwise eat the first real flag.
    ///
    /// 給 `main` 的 argv，第一項為執行檔名稱。
    ///
    /// `argv[0]` 依慣例是程式本身，而會跳過它的程式碼——引數解析器就是如此——否則會吃掉第一個
    /// 真正的旗標。
    static func read(from activity: Activity?) -> [String] {
        var arguments = ["SwiftCrossUIApp"]

        guard
            let activity,
            let intent = activity.getIntent(),
            let raw = intent.getStringExtra(extraKey) as String?,
            !raw.isEmpty
        else {
            return arguments
        }

        arguments.append(contentsOf: raw.split(separator: " ").map(String.init))

        // Logged unconditionally, because "did the flag arrive" is exactly the
        // question this file exists to answer and it cannot be asked any other
        // way: an Android app has no console, and a flag that failed to arrive
        // looks identical to a flag that arrived and did nothing. `adb shell am
        // start` will happily mangle the extra -- an unquoted value is
        // re-split by the device's shell, and `am` then reads `-actionfile` as
        // `-a ctionfile` -- and the only evidence is this line.
        //
        // 無條件記錄，因為「那個旗標到底有沒有送達」正是本檔存在所要回答的問題，而它沒有別的方式
        // 可問：Android app 沒有主控台，而「沒送達的旗標」與「送達了卻什麼都沒做的旗標」看起來
        // 完全一樣。`adb shell am start` 很樂意把那個 extra 弄壞——未加引號的值會被裝置端的 shell
        // 重新斷詞，接著 `am` 就把 `-actionfile` 讀成 `-a ctionfile`——而唯一的證據就是這一行。
        // Assigned, not just handed to `main`.
        //
        // `CommandLine.arguments` does not come from the argv `main` was called
        // with. On Android the Swift runtime captures argc/argv at real process
        // entry -- the JVM's, whose command line is the package name -- and
        // `main` here is called later, from JNI, with an argv this file built.
        // So passing argv alone left `CommandLine.arguments` reading
        // "dev.swiftcrossui.testapp.p12" and every flag invisible. Measured:
        // the launch-argument line below printed the flags, the replay never
        // started, and the built library contained the replay code all along.
        //
        // `CommandLine.arguments` is a stored `static var` in the standard
        // library, so it can be replaced. argv is still passed to `main` for
        // anything that reads argv directly.
        //
        // 直接指派，而不只是交給 `main`。
        //
        // `CommandLine.arguments` 並非來自呼叫 `main` 時所帶的 argv。在 Android 上，Swift runtime
        // 是在「真正的行程進入點」捕捉 argc/argv 的——也就是 JVM 的，其命令列是套件名稱——而此處的
        // `main` 是稍後由 JNI 呼叫、帶著本檔所建構的 argv。因此只傳 argv 會讓
        // `CommandLine.arguments` 讀到 "dev.swiftcrossui.testapp.p12"，所有旗標都不可見。實測：
        // 下方那行 launch argument 印出了旗標、重放卻從未開始，而已建置的函式庫自始就含有重放程式碼。
        //
        // `CommandLine.arguments` 在標準函式庫中是一個已儲存的 `static var`，因此可以被取代。argv
        // 仍然會傳給 `main`，供任何直接讀取 argv 的東西使用。
        CommandLine.arguments = arguments

        log("launch arguments: \(arguments.dropFirst().joined(separator: " "))")
        log("CommandLine.arguments: \(CommandLine.arguments.joined(separator: " "))")

        return arguments
    }

    /// Hands the strings to `main` as a C `argv`.
    ///
    /// Deliberately never freed. `main` does not return until the process ends,
    /// and `CommandLine.arguments` reads through this pointer for the life of
    /// the app, so freeing it would be freeing something still in use.
    ///
    /// 以 C 的 `argv` 形式把這些字串交給 `main`。
    ///
    /// 刻意不釋放。`main` 在行程結束前不會返回，而 `CommandLine.arguments` 在 app 的整個生命週期中
    /// 都透過這個指標讀取，因此釋放它等於釋放一個仍在使用中的東西。
    static func withArgv<Result>(
        _ arguments: [String],
        _ body: (Int32, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Result
    ) -> Result {
        let argv = UnsafeMutableBufferPointer<UnsafeMutablePointer<CChar>?>.allocate(
            capacity: arguments.count + 1
        )
        for (index, argument) in arguments.enumerated() {
            argv[index] = strdup(argument)
        }
        argv[arguments.count] = nil
        return body(Int32(arguments.count), argv.baseAddress)
    }
}
