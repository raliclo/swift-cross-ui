#!/usr/bin/env python3
"""Compare an iPad menu-bar dump with the SwiftUI reference dump of the same mode.

    python3 testapp/test_support/compare_ipad_menu_dump.py REFERENCE.txt DUMP.txt

REFERENCE is one of testapp/reference/swiftui-commands/ipad/ipad-<mode>.txt, written by the
SwiftUI app beside it. DUMP is the "-menu:" lines UIKitBackend prints under --debug when the
menu bar is built (grep them out of p92-ios-stdout.log and strip the "-menu: " prefix).
The system builds the bar only once a key or the pointer arrives, so the run needs one.
Identifiers of unnamed inline menus, selectors and key equivalents are left out; the app names
are both written APP. Known and expected differences for P92: SwiftUI keeps an empty
importExport group when the app has none, and has no windowList or singleWindowList on iOS.
Neither shows a Format menu, even when the app fills textFormatting (the framework since 2026-10-20).

比對 iPad 選單列傾印與同一模式的 SwiftUI 基準傾印。系統要等到有按鍵或指標事件才會建立選單列，所以該次執行需要有一個。
無名 inline 選單的識別碼、selector 與快捷鍵不比;兩邊的 app 名稱都寫成 APP。P92 已知且預期的差異:app 沒有 importExport
群組時 SwiftUI 仍保留一個空的;SwiftUI 在 iOS 上沒有 windowList 與 singleWindowList。SwiftUI 也沒有 Format 選單(app 填了
textFormatting 也一樣，框架自 2026-10-20 起照做，所以這不再是差異)。
"""
import re,sys,difflib
def norm(path, app):
    t=open(path,encoding="utf8",errors="replace").read()
    if "=== end" in t:
        t=t[t.index("MENU '' "):t.index("=== end")]
    out=[]
    for raw in t.splitlines():
        if not raw.strip() or raw.startswith(("===","main menu")): continue
        depth=(len(raw)-len(raw.lstrip(" ")))//2
        s=raw.strip()
        s=re.sub(r"  <[^>]*>$","",s); s=re.sub(r"  \[key.*\]$","",s); s=re.sub(r"  \(action\)$","",s)
        m=re.match(r"(MENU|\(inline\)) '([^']*)' (?:id=)?(\S+)",s)
        if m:
            kind,title,ident=m.groups()
            ident=re.sub(r"dynamic\.[0-9A-F-]+","dynamic",ident)
            ident=re.sub(r"^(com\.apple\.swiftui|scui)\.synthesized","synthesized",ident)
            ident=re.sub(r".*command-menu.*","custom",ident)
            s=f"{kind} '{title}' {ident}"
        s=s.replace(app,"APP")
        out.append("  "*depth+s)
    return out
a=norm(sys.argv[1],"RefIOS"); b=norm(sys.argv[2],"debugTarget")
if a==b: print("same:",len(a),"lines")
else:
    d=list(difflib.unified_diff(a,b,"swiftui","p92",lineterm="",n=1)); print("\n".join(d[:70])); print("...",len(d),"diff lines")
