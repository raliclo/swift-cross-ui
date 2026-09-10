# measure/ — 兩支一次性的量測工具,留下來是為了讓結論可以被重跑

這裡的東西**不是測試**,它們不會通過或失敗;它們產生數字。放在樹裡的理由只有一個:
一個沒有辦法重新導出的量測,與一個猜測讀起來一模一樣。

Neither of these is a test. They produce numbers, and they live here because a
measurement nobody can re-derive reads exactly like a guess.

## `real_mouse_latency.swift` — P28 的那兩條未量路徑

```sh
swiftc -O -o /tmp/realmouse testapp/test_support/measure/real_mouse_latency.swift
/tmp/realmouse /tmp/p28.log "$PWD/testapp/output/P28"
```

它啟動 P28、用 accessibility API 找到那顆按鈕、以 `CGEvent.post(tap: .cghidEventTap)`
送出**真正的**滑鼠事件,再從 P28 自己寫的 `click at uptime` 那一行讀回抵達時間。兩端都用
`ProcessInfo.systemUptime`,那是機器層級的時鐘,因此不需要對齊任何東西。

**它需要 Accessibility 授權。** `AXIsProcessTrusted()` 為 false 時,`CGEvent.post` 會
**靜默地**送出 0 個事件——那正是 `AppKitSynthesiser` 的檔頭所記錄的量測,也正是「這條路徑
合成不出來」這個說法的由來。2026-09-10 在已授權的機器上重量,它會送達。

## `ax_dump.swift` — 列出一支 app 的每一顆 AXButton 叫什麼名字

```sh
swiftc -O -o /tmp/axdump testapp/test_support/measure/ax_dump.swift
/tmp/axdump "$PWD/testapp/output/P34"
```

它就是抓到「每一個 `AXButton` 的 title 與 desc 都是空的」那一支。修好之後,同一支工具會
印出 `desc='Show +100'`——**同一個量測、修前修後各跑一次**,而不是換一個更容易通過的量測。

It is the tool that caught every `AXButton` having an empty title and
description, and the same tool prints the labels afterwards -- the same
measurement before and after, not an easier one after.
