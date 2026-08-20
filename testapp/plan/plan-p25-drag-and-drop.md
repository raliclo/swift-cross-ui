# P25: drag and drop

Low priority, planned rather than started. Written down now because the research
that makes it tractable was done while answering a different question, and it
would otherwise be repeated.

低優先度，先規劃而不動工。此刻寫下，是因為使它變得可行的調查是在回答另一個問題時順帶完成的；
若不記錄，日後將重做一次。

## What is missing, and what is not

SwiftCrossUI has no drag-and-drop API. The only gesture a backend is asked for
is a tap, through `createTapGestureTarget`. So there is nothing above the
backends to exercise, and a P25 written today would have nothing to call.

The backends are not the problem. GTK 4 already implements both halves on both
platforms, and this was read from the vendored source rather than assumed:

| | |
|---|---|
| `gtk/gtkdroptarget.c`, `gtkdragsource.c` | the GTK-level API |
| `gdk/win32/gdkdrag-win32.c` | OLE: `DoDragDrop` on a dedicated DnD thread, `IDropSource` and `IDropTarget` |
| `gdk/win32/gdkdrop-win32.c` | also handles the older `WM_DROPFILES` shell path |
| `gdk/win32/gdkclipdrop-win32.c` | `CF_HDROP`, which is where file paths arrive |
| X11 | XDND, GTK's usual path on Linux |

So the work is a SwiftCrossUI feature and a GtkBackend conformance. It is not a
port and it is not new plumbing.

SwiftCrossUI 沒有 drag-and-drop API。backend 被要求提供的唯一手勢是點擊，透過
`createTapGestureTarget`。因此 backend 之上沒有任何東西可供操作，今天寫出來的 P25 也將無從呼叫。

問題不在 backend。GTK 4 在兩個平台上都已實作兩端，且以下是讀取所引入的原始碼所得，而非推測（如上表）。

因此所需的工作是「一個 SwiftCrossUI 功能」加上「GtkBackend 的實作」，既非移植，也非新建底層管線。

## Why this is not an InputEvent problem

`InputEvent` synthesises mouse and key events. Drag and drop is not made of
those.

At the operating system level it is a negotiation: a source announces the types
it can provide, a target accepts or refuses, and data is transferred. On Windows
the source drives it by calling `DoDragDrop`, which runs a modal loop inside the
source application — Explorer, when a file is dragged from a folder. Nothing
posted with `SendInput` enters that loop from outside.

So a file drop cannot be tested by pretending to drag. It has to be tested by
being the target: the app registers a drop target, and the test either performs
a real drag or invokes the drop path directly with a synthetic payload.

`InputEvent` 合成的是滑鼠與按鍵事件，而 drag and drop 並非由這些構成。

在作業系統層級，它是一場協商：來源宣告其可提供的型別，目標接受或拒絕，接著傳輸資料。在 Windows
上由來源呼叫 `DoDragDrop` 驅動，該呼叫會在來源應用程式內部執行一個 modal loop——當檔案自資料夾
被拖出時，那個來源就是 Explorer。以 `SendInput` 投遞的任何事件都無法從外部進入該迴圈。

因此檔案拖放無法藉由「假裝拖曳」來測試，只能以「成為目標」來測試：app 註冊一個 drop target，
而測試要嘛執行一次真實拖曳，要嘛直接以合成的酬載呼叫其 drop 路徑。

## Shape

1. `BackendFeatures.DragAndDrop` in SwiftCrossUI: register a widget as a drop
   target for a set of types, and report a drop with its payload.
   → verify: `DummyBackend` conforms and a unit test drives the protocol with no
   window.
2. GtkBackend conformance over `GtkDropTarget`.
   → verify: P25 accepts a file dropped by hand on Linux.
3. P25 itself, built around two drop areas.
   → verify: dropping a file names it; dropping something of an unoffered type
   is refused rather than silently ignored.
4. Windows, which should be the same code.
   → verify: the same drops behave the same way, through GTK's OLE path.

Build P25 on WSL first. Not for convenience -- Linux is where a real drag can be
performed and observed, and where XDND failures are visible in the log. Windows
comes second because if it differs, the difference is the finding.

先於 WSL 上建置 P25。這並非為了方便——Linux 是能夠實際執行並觀察一次真實拖曳的環境，XDND 的失敗
也會顯示在日誌中。Windows 排在其後，因為若兩者有差異，該差異本身就是發現。

## The drop areas

Two of them, because one cannot show a refusal.

**The accepting area.** A bordered rectangle, large enough to be an easy target,
that offers file types. It reports four things, each as its own line, because
merging them hides which stage failed:

```
state    idle | hovering | accepted | refused
received the payload, verbatim, as the backend delivered it
type     the type the payload arrived as
count    how many items
```

`received` is printed verbatim and not tidied up. Windows delivers a path
through `CF_HDROP` and X11 delivers a `text/uri-list`; one is `C:\x\y.txt` and
the other is `file:///x/y.txt`. Normalising them in the app would hide exactly
the difference this app exists to show.

**The refusing area.** The same size and appearance, offering a type nothing
will be dragged as. It exists to answer a question the accepting area cannot: is
a refusal visible? A drop zone that silently swallows what it cannot handle and
one that rejects it look identical until they are put side by side.

Both areas change appearance on hover, before the button is released, so the
feedback stage is observable separately from the drop stage. A backend that only
reacts after the release is usable but wrong, and that is invisible without
somewhere to look.

兩個放置區，因為單一個區域無法呈現「拒絕」。

**接受區**：一個有邊框的矩形，大到容易命中，並宣告接受檔案型別。它以四行分別回報 state、
received、type、count——合併顯示會掩蓋是哪一個階段失敗。

`received` 原樣印出，不作整理。Windows 透過 `CF_HDROP` 傳遞路徑，X11 傳遞 `text/uri-list`；
一個是 `C:\x\y.txt`，另一個是 `file:///x/y.txt`。在 app 中將兩者正規化，正好會掩蓋這支 app 存在
所要呈現的差異。

**拒絕區**：外觀與大小相同，但宣告接受一種不會被拖入的型別。它回答接受區無法回答的問題：拒絕
是否可見？一個「默默吞掉無法處理之物」的放置區，與一個「明確拒絕」的放置區，在並排之前看起來
完全相同。

兩個區域都會在按鍵放開之前、於游標懸停時改變外觀，使「回饋階段」能與「放置階段」分開觀察。
一個僅在放開後才反應的 backend 雖可使用但並不正確，而少了可供對照之處，這一點便無從察覺。

## What P25 should test

The questions worth asking are the ones where the two platforms have room to
disagree, not whether a drop arrives at all.

- Does the drop zone report the same payload for the same file? Windows delivers
  paths through `CF_HDROP`; X11 delivers `text/uri-list`. One is a path, the
  other is a URI, and an app that treats them as interchangeable is wrong on one
  platform.
- Is a refused type refused visibly, or does the drop appear to succeed?
- Does dragging over the zone give feedback before the release, or only after?
- Do multiple files arrive as multiple items or as one string?

值得詢問的，是兩個平台有分歧空間的問題，而非「拖放到底會不會抵達」。其中最關鍵者：Windows 透過
`CF_HDROP` 傳遞路徑，X11 傳遞的則是 `text/uri-list`——一個是路徑、一個是 URI，若某個 app 將兩者
視為可互換，它在其中一個平台上必然是錯的。

## Not yet decided

Whether SwiftCrossUI should model a payload as typed data or as a list of URLs.
URLs cover the file case, which is the one anybody asks for first, and they are
the wrong shape for dragging a colour or a piece of text between views. Deciding
this before step 1 matters more than the rest of the plan, because it is the
part that cannot be changed later without changing every call site.

尚未決定：SwiftCrossUI 應將酬載建模為具型別的資料，還是一份 URL 清單。URL 足以涵蓋檔案的情境，
而那也是所有人最先提出的需求；但對於在視圖之間拖曳顏色或一段文字而言，URL 的形狀並不正確。
在步驟 1 之前決定此事，比本計畫其餘部分更為重要，因為它是日後若要更動、就必須連同每一個呼叫端
一併更動的部分。
