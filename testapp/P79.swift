import DefaultBackend
import Foundation
import SwiftCrossUI

#if canImport(AndroidBackend)
    import AndroidBackend
    import AndroidKit
    import SwiftJava
#endif

// P79: is an AndroidViewRepresentable dismantled when it leaves the view graph?
//
// The number was checked: `ls testapp` gives P0..P78.
//
// **Both counts on screen, make and dismantle.** A dismantle that never runs
// and one that runs for every update both leave a plausible single number;
// only the pair says which. Show, hide, show, hide must read "made 2,
// dismantled 2". Dismantling runs when the node is released, a moment after
// the hide, so "refresh" re-reads the counts. Written 2026-10-06, when
// `dismantleAndroidView` was added; UIKit and AppKit have had their
// counterparts all along, so this app is Android's.
//
// P79:AndroidViewRepresentable 離開 view graph 時有沒有被 dismantle?編號查過:`ls testapp` 給出 P0..P78。
// **畫面同時顯示 make 與 dismantle 兩個計數。** 從不執行的 dismantle 與每次更新都執行的 dismantle,單看一個數字
// 都說得通；只有兩者並列才看得出是哪一種。顯示、隱藏、顯示、隱藏之後必須是「made 2, dismantled 2」。dismantle
// 在節點被釋放時執行，比隱藏晚一點，因此用「refresh」重新讀取計數。2026-10-06 撰寫，當時加入了
// `dismantleAndroidView`;UIKit 與 AppKit 一直都有對應的方法，所以這支 app 是給 Android 的。

enum P79Counts {
    nonisolated(unsafe) static var made = 0
    nonisolated(unsafe) static var dismantled = 0
}

@main
@HotReloadable
struct P79DismantleApp: App {
    var body: some Scene {
        WindowGroup("P79 representable dismantle") {
            #hotReloadable {
                P79RootView()
            }
        }
        .defaultSize(width: 560, height: 360)
    }
}

struct P79RootView: SwiftCrossUI.View {
    @State var shown = false
    @State var tick = 0

    var body: some SwiftCrossUI.View {
        VStack(alignment: .leading, spacing: 10) {
            Text("P79: representable dismantle")
                .font(.system(size: 18))
            Text("backend -> \(String(describing: DefaultBackend.self))")
            // `tick` is read so that "refresh" re-renders this line.
            // 讀取 `tick`,讓「refresh」重新繪製這一行。
            Text("made \(P79Counts.made), dismantled \(P79Counts.dismantled)  (\(tick))")
            HStack(spacing: 8) {
                Button(shown ? "hide" : "show") { shown.toggle() }
                Button("refresh") { tick += 1 }
            }
            #if canImport(AndroidBackend)
                if shown {
                    P79NativeLabel()
                }
            #else
                Text("Android only: UIKit and AppKit have dismantleUIView / dismantleNSView.")
            #endif
            Text("Expected after show, hide, show, hide, refresh: made 2, dismantled 2.")
            Text("預期：顯示、隱藏、顯示、隱藏、refresh 之後:made 2, dismantled 2。")
        }
        .padding(16)
    }
}

#if canImport(AndroidBackend)
    struct P79NativeLabel: AndroidViewRepresentable {
        func makeAndroidView(context: Self.Context) -> TextView {
            P79Counts.made += 1
            let view = TextView(
                context.environment.androidActivity,
                environment: context.environment.jniEnv
            )
            view.setText(
                JavaString("a native TextView", environment: context.environment.jniEnv)
                    .as(CharSequence.self)
            )
            return view
        }

        func updateAndroidView(_ view: TextView, context: Self.Context) {}

        static func dismantleAndroidView(_ view: TextView, coordinator: Void) {
            P79Counts.dismantled += 1
        }
    }
#endif
