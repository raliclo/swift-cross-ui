# WSLg: X11, not Wayland, and what WSLg's window manager lacks

Written 2026-10-24 from `testapp/test_support/test_common.zsh` (`run_wsl`),
`testapp/install_tool_wsl.zsh`, and commits fcaa7320, 17de4a29, 661c0ee3,
de5a981c and dd04fd54.

## What

WSLg runs a Wayland compositor (Weston) with XWayland beside it
(`DISPLAY=:0`, `WAYLAND_DISPLAY=wayland-0`). A GTK 4 app left alone becomes a
Wayland client with no X window. Wayland does not let one client drive
another, so xdotool (XTEST) sees nothing. Every WSL launch from `test.zsh`
therefore sets `GDK_BACKEND=x11 GTK_CSD=1` (since 2026-10-22, fcaa7320; before
that only replays did, so captures and replays showed different windows).

## Why GTK_CSD=1

Under X11 without it, WSLg draws a light server-side frame with three buttons;
under Wayland GTK draws a dark header bar with only a close button. `GTK_CSD=1`
makes GTK draw its own dark header bar under X11, the same bar GTK draws on
Windows. The bar sits inside the X window, so GtkBackend reports its height
(`ActionFileReplay.clientContentOffset`, about 39 pt) and the replay adds it to
`client` rows only. Action-file coordinates are measured without CSD:
`measure_wsl.zsh` and `drive_xdotool.zsh` keep server-side decorations on
purpose.

## Window-manager gaps and their workarounds

- No `_NET_WM_STATE_ABOVE` (`xprop -root _NET_SUPPORTED`, 2026-10-21), and
  Wayland lets no client raise itself. `.floating` is implemented through the
  Windows side instead: `GtkBackend+WSLTopmost.swift` runs `powershell.exe`
  over WSL interop, finds the Windows window WSLg draws for the GTK window by
  its title `"<title> (<distro>)"` with `EnumWindows`/`GetWindowText`
  (`FindWindow` never matched), and calls `SetWindowPos(HWND_TOPMOST)`. P37:
  exstyle 0x80108 (`WS_EX_TOPMOST`) where it read 0x80100 (661c0ee3).
- `xdotool windowactivate --sync` waits for the window manager, and WSLg's
  never answers: replays hung silently. `XdotoolSynthesiser` activates without
  `--sync` and waits at most a second. `xdotool search --pid P --name N` ORs its
  conditions unless given `--all` (17de4a29).
- The X server sends Mod4 for Super, but GDK maps Mod4 to SUPER only when the
  keymap puts a Super key there; under WSLg it does not. `GtkHeldSuperKey`
  (`GtkBackend+SuperKey.swift`) tracks Super/Meta presses per window so hover
  reports `.command` (P88, de5a981c).
- GTK menus rebuilt their buttons between opening and the first key, so Down,
  Up and Return acted on a stale item. `GtkMenuKeyboardStart`
  (`GtkBackend+MenuKeyboard.swift`) selects the current first/last item and
  activates through its action (P19-keyboard, dd04fd54).
- Sheets and full-screen covers are separate X11 windows: a `focus` row
  re-pins the replay to them, and a capture of the main window does not show
  them (P1, P49, 2026-10-20).

## How to apply

- A result under Wayland is not evidence about X11, and the reverse: a GTK
  file chooser that would not close was seen on the Wayland path and did not
  reproduce under XWayland.
- Launching an app by hand to compare with a test run: use the same
  `GDK_BACKEND=x11 GTK_CSD=1`.
- Window sizing and minimum sizes under WSLg are not those of a desktop Linux
  session; state "WSLg only" when that is all that was checked.

## Limits

- Touch: whether WSLg forwards touch to X11 clients is unverified (queue.md
  row 4, 2026-10-23).
- XDND drag and drop cannot be synthesised with xdotool, and the distro has
  no file manager to drag from (testapp/gtk-test-plan-findings.md).

---

# WSLg:用 X11 而非 Wayland,以及 WSLg 視窗管理員缺少的功能

2026-10-24 依 `testapp/test_support/test_common.zsh`(`run_wsl`)、`testapp/install_tool_wsl.zsh` 以及 fcaa7320、
17de4a29、661c0ee3、de5a981c、dd04fd54 寫成。

## 是什麼

WSLg 執行一個 Wayland compositor(Weston),旁邊有 XWayland(`DISPLAY=:0`、`WAYLAND_DISPLAY=wayland-0`)。放任
不管的 GTK 4 app 會成為 Wayland client,沒有 X window。Wayland 不允許一個 client 驅動另一個，所以 xdotool(XTEST)
什麼也看不到。因此 `test.zsh` 的每一次 WSL 啟動都設定 `GDK_BACKEND=x11 GTK_CSD=1`(自 2026-10-22,fcaa7320;
在那之前只有重放才設，於是擷取與重放呈現的是不同的視窗)。

## 為什麼要 GTK_CSD=1

X11 下不設時,WSLg 畫的是淺色、三顆鈕的伺服器端框;Wayland 下 GTK 畫的是只有關閉鈕的深色 header bar。
`GTK_CSD=1` 讓 GTK 在 X11 下也畫自己的深色 header bar,與 Windows 上相同。標題列在 X window 之內，所以 GtkBackend
回報它的高度(`ActionFileReplay.clientContentOffset`,約 39 pt),重放只把它加到 `client` 列上。動作檔座標是在
不加 CSD 時量的:`measure_wsl.zsh` 與 `drive_xdotool.zsh` 刻意保留伺服器端裝飾。

## 視窗管理員的缺口與繞法

- 沒有 `_NET_WM_STATE_ABOVE`(`xprop -root _NET_SUPPORTED`,2026-10-21),Wayland 也不讓 client 把自己提到最上層。
  `.floating` 改從 Windows 那一側實作:`GtkBackend+WSLTopmost.swift` 經 WSL interop 執行 `powershell.exe`,用
  `EnumWindows`/`GetWindowText` 依標題 `"<title> (<distro>)"` 找到 WSLg 為該 GTK 視窗畫的 Windows 視窗
  (`FindWindow` 從未命中),再呼叫 `SetWindowPos(HWND_TOPMOST)`。P37:exstyle 由 0x80100 變為 0x80108
  (`WS_EX_TOPMOST`)(661c0ee3)。
- `xdotool windowactivate --sync` 會等視窗管理員回應，而 WSLg 的永遠不回：重放無聲地卡住。`XdotoolSynthesiser`
  改為不加 `--sync`,最多等一秒。`xdotool search --pid P --name N` 不加 `--all` 時條件是 OR(17de4a29)。
- X server 對 Super 送出 Mod4,但只有 keymap 把 Super 鍵放在 Mod4 上時 GDK 才把它當成 SUPER;WSLg 下沒有。
  `GtkHeldSuperKey`(`GtkBackend+SuperKey.swift`)逐視窗追蹤 Super/Meta 的按下與放開，讓 hover 回報 `.command`
  (P88,de5a981c)。
- GTK 選單在開啟與第一個按鍵之間重建了按鈕,Down、Up、Return 作用在過期的項目上。`GtkMenuKeyboardStart`
  (`GtkBackend+MenuKeyboard.swift`)改選目前的第一或最後一項，並經由其 action 觸發(P19-keyboard,dd04fd54)。
- sheet 與全螢幕 cover 是獨立的 X11 視窗:`focus` 列會讓重放改釘到它們上面，主視窗的擷取看不到它們
  (P1、P49,2026-10-20)。

## 怎麼用

- Wayland 下的結果不能當作 X11 的證據，反之亦然：曾有「GTK 檔案選擇器關不掉」出現在 Wayland 路徑上，在
  XWayland 下完全無法重現。
- 手動啟動 app 與測試結果比較時，用同樣的 `GDK_BACKEND=x11 GTK_CSD=1`。
- WSLg 下的視窗大小與最小尺寸不等於桌面 Linux 工作階段；只在 WSLg 檢查過時要註明「僅 WSLg」。

## 限制

- 觸控:WSLg 是否把觸控轉給 X11 client,尚未驗證(queue.md 第 4 列,2026-10-23)。
- XDND 拖放無法用 xdotool 合成，發行版也沒有可拖出檔案的檔案管理員(testapp/gtk-test-plan-findings.md)。
