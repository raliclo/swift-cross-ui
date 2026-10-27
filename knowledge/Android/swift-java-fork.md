# swift-java comes from our fork

Since 76c8029a (2026-10-24).

## Where the Java bindings come from

```
AndroidBackend (this repo)
  └─ AndroidKit            moreSwift/AndroidKit 0.8.1 -- Swift bindings of the Android API
       ├─ SwiftJavaLang    stackotter/SwiftJavaLang 0.3.0 -- java.lang and the JDK classes
       ├─ SwiftKotlin      stackotter/SwiftKotlin 0.3.0 -- Kotlin's standard classes
       └─ swift-java       raliclo/swift-java, branch develop -- JNI calls, macros
```

AndroidBackend imports AndroidKit in 109 files: `View`, `ViewGroup`,
`LinearLayout`, `Activity` and `TextView` are the most used. None of the three
packages above swift-java can be dropped. They are bindings built on it, not
copies of it.

## The fork

- `https://github.com/raliclo/swift-java`, a fork of stackotter/swift-java (itself
  a fork of swiftlang/swift-java). Branch `develop` starts at stackotter's 0.5.1,
  e04c0ed6, the revision Package.resolved pinned before; the 0.5.1 tag is pushed
  too.
- Package.swift: `.package(url: "https://github.com/raliclo/swift-java", branch:
  "develop")`.
- To change it: work in a separate clone. Push to
  `git@github.com:raliclo/swift-java.git`; upstream is stackotter, with push
  DISABLED. Then run `swift package update swift-java` here so Package.resolved
  moves.

## Why a fork

Every swift-java call looks its method up by name: `dynamicJavaMethodCall` →
`javaMethodLookup` → JNI `GetMethodID`. That was 6.2% of P96's main thread
at launch (see density-cache.md). Caching the method IDs in swift-java speeds
up every AndroidKit binding with no change to AndroidKit, because AndroidKit is
compiled against our swift-java.

## The warning

AndroidKit, SwiftJavaLang and SwiftKotlin still name stackotter's URL. The
package identity, `swift-java`, is the same, so SwiftPM builds ours for all of
them. It warns `Conflicting identity for swift-java` once for each, and says
this may become an error in a future SwiftPM. If it does, fork those three too,
or use a SwiftPM mirror (`swift package config set-mirror`). A mirror needs a
config file on every machine.

Only Android builds resolve those three packages. On 2026-10-24 the
Windows-side targets (P10 on WinUI, Windows GTK and WSL GTK) built
76c8029a with rc=0 and no such warning.

## Upstream state, checked 2026-10-24

All four pins are the newest tags. AndroidKit's main has 3 commits past 0.8.1
from 2025-12 to 2026-01, and lacks 322 of 0.8.1's. SwiftJavaLang and SwiftKotlin
have nothing past 0.3.0. stackotter's swift-java has nothing past 0.5.1. There
is nothing newer to pull.

---

# swift-java 改用我們的 fork

自 76c8029a(2026-10-24)起。

## Java 綁定從哪裡來

AndroidBackend 依賴 AndroidKit(Android API 的 Swift 綁定),AndroidKit 再依賴 SwiftJavaLang(java.lang 與 JDK 類別)、
SwiftKotlin(Kotlin 標準類別)與 swift-java(JNI 呼叫、巨集)。AndroidBackend 有 109 個檔案 import AndroidKit,
最常用的是 `View`、`ViewGroup`、`LinearLayout`、`Activity`、`TextView`。swift-java 以上這三個套件都不能拿掉：它們是
建在 swift-java 之上的綁定，不是它的複本。

## fork

- `https://github.com/raliclo/swift-java`,fork 自 stackotter/swift-java(它又 fork 自 swiftlang/swift-java)。`develop`
  分支起點為 stackotter 的 0.5.1,e04c0ed6,也就是 Package.resolved 先前釘住的版本；0.5.1 tag 也已推上。
- Package.swift:`.package(url: "https://github.com/raliclo/swift-java", branch: "develop")`。
- 要修改時：在另一份 clone 裡進行，推到 `git@github.com:raliclo/swift-java.git`(upstream 為 stackotter,推送
  DISABLED),然後在這裡執行 `swift package update swift-java`,讓 Package.resolved 跟上。

## 為什麼要 fork

swift-java 每次呼叫都以名稱查找方法:`dynamicJavaMethodCall` → `javaMethodLookup` → JNI 的 `GetMethodID`。在 P96
啟動時佔主執行緒 6.2%(見 density-cache.md)。在 swift-java 裡快取方法 ID,會讓每一個 AndroidKit 綁定都變快，
而 AndroidKit 不必改，因為它是以我們的 swift-java 編譯的。

## 警告

AndroidKit、SwiftJavaLang、SwiftKotlin 仍指向 stackotter 的網址。套件識別 `swift-java` 相同，所以 SwiftPM 讓它們全都使用
我們的這一份，並各警告一次 `Conflicting identity for swift-java`,說明未來版本可能改為錯誤。若真的變成錯誤，就把這三個
也 fork,或改用 SwiftPM 的 mirror(`swift package config set-mirror`);mirror 需要每台機器各有一份設定檔。

只有 Android 建置會解析那三個套件。2026-10-24 Windows 端的目標(WinUI、Windows GTK、WSL GTK 上的 P10)
以 76c8029a 建置成功(rc=0),沒有出現這個警告。

## 上游狀況(2026-10-24 查)

四個釘住的都是最新 tag。AndroidKit 的主分支在 0.8.1 之外只有 2025-12 到 2026-01 的 3 個 commit,而且缺了 0.8.1 的
322 個;SwiftJavaLang 與 SwiftKotlin 在 0.3.0 之後沒有東西;stackotter 的 swift-java 在 0.5.1 之後也沒有。
沒有更新的版本可拉。
