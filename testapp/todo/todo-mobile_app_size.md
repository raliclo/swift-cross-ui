# 行動平台的 app 體積 / Mobile app size

初次整理：2026-09-06
量測平台：macOS 主機、Android emulator `swift-cross-ui-api36`(API 36、arm64-v8a、
1080×2400 px、density 2.625)、iOS Simulator

---

## 一句話 / In one line

**這棵樹的 Android APK 比 iOS `.app` 大 12.9 倍,而業界的通則說的是反過來。**

Android is 12.9× larger than iOS here, and the widely-quoted rule says the
opposite. The rule is not wrong; it does not apply to a Swift toolkit on
Android, and the reason is one line of `otool` output.

---

## 那個通則,以及它為什麼對我們不成立

網路上常見的說法(Reddit r/Android、itnerd.blog 等)是:

> 同一支 app,iOS 的下載與安裝體積通常是 Android 的 2 到 3.5 倍。
> iOS 平均 35–40 MB 基本檔案、安裝後 50–150 MB;Android 壓縮下載平均 12–15 MB。

那個說法有三個成立的理由,而**我們一個也沒有**:

| 該通則倚賴的前提 | 我們的情況 |
| --- | --- |
| iOS 要帶 asset catalog 的 @2x/@3x 圖 | 測試 app 幾乎沒有資產 |
| Android 有 split APK / dynamic delivery,12–15 MB 是「切開後的下載量」 | 我們出單一 universal APK,沒有切 |
| 比較的兩邊都是原生 app,各自使用平台的 runtime | 我們把一整套**非原生**的 runtime 搬上 Android |

The rule compares two native apps each using its platform's own runtime. We
carry a foreign runtime onto one of them.

---

## 實測 / Measured

| | 大小 | 樣本 | 全距 |
| --- | ---: | --- | ---: |
| iOS `.app` | **8.5 MB** | 47 支 | 8.5 – 8.7 MB |
| Android APK | **109.9 MB** | 35 支(2026-09-05 重建) | 109.9 – 110.0 MB |

兩邊的離散度都近乎零,所以這不是抽樣造成的。

磁碟上另有 10 個舊 APK,平均 191.2 MB——那些是本週優化之前的,**不可拿來比較**。

---

## 那 109.9 MB 去了哪裡

拆 `P39.apk`:

| | | |
| ---: | --- | --- |
| **67.8 MB** | Swift / Foundation runtime | **iOS 一個位元組都不帶** |
| 30.5 MB | app 自己的 library | 靜態連入 SwiftCrossUI、AndroidBackend、SwiftJava、libwebp |
| 11.6 MB | 其餘 | 資源、dex、簽章 |
| **109.9 MB** | | |

而 iOS 那支 8.5 MB 的執行檔連的是:

```
/System/Library/Frameworks/Foundation.framework/Foundation
/usr/lib/swift/libswiftCore.dylib
```

`P39-ios.app` **連 `Frameworks/` 目錄都沒有**。Swift 自 5.0 起 ABI 穩定,runtime 內建於
iOS;Android 沒有系統層的 Swift,因此每一支 app 都得自己扛 libswiftCore、
FoundationEssentials、FoundationNetworking、SwiftJava、dispatch,以及 ICU 的 38 MB。

**那 67.8 MB 就是「這是一個 Swift 跨平台工具組」的全部代價。** 一支原生 Kotlin app 不付,
一支 Swift iOS app 也不付。

That 67.8 MB is the entire cost of being a Swift toolkit on Android. A native
Kotlin app does not pay it and a Swift iOS app does not pay it.

---

## 已經拿掉的 / What has already come off

212 → 110 MB,少 48%。四項都是預設行為。

| | APK | 拿掉了什麼 |
| --- | ---: | --- |
| 起點 | 212 MB | |
| 剝除 `.swift_ast` | 169 MB | 43 MB 除錯 metadata,見 `testapp/patches/` |
| 不再把 SwiftSyntax 連進 Android | 154 MB | 15 MB 編譯期函式庫,`Package.swift` 條件化 |
| 改以 release 建置 | 126 MB | 28 MB;Android 曾是此處唯一不用 release 的平台 |
| 匯出符號表只留 31 個 | **110 MB** | 16 MB;151,047 → 32 個動態符號,`testapp/android-exports.map` |

---

## 已經試過而**不採用**的 / Tried and rejected

**`-Osize`。** 實測 P44:`.text` 21.59 → 19.61 MB,但 `.eh_frame` 3.72 → 4.34、
`.eh_frame_hdr` 1.06 → 1.30——`-Osize` 內聯得少,更多相異的 frame 需要更多 unwind 表,把將近
一半的收益吃回去。淨值 APK 109.9 → 108.6 MB,**1.2%**,而代價是整個框架每一行程式碼的速度。
已於 `81e9b6fb` 還原。

若日後有人重提,數字在這裡,不必再量一次。

---

## 還可以動的 / What is left

**30.5 MB 那塊(app 自己的 library)。** 目前組成:`.text` 21.59 MB、`.eh_frame` 3.72 MB、
`.rodata` 1.49 MB、`.data` 1.44 MB。未嘗試的方向:

- **`--gc-sections` 配合 `-ffunction-sections`** — 未試。Swift 的 metadata 與 protocol
  conformance 是靠 section 註冊的,粗率地 GC 掉 section 會壞掉;需要保留 `swift5_*` 各段。
- **`--icf=safe`(identical code folding)** — 未試。泛型特化會產生大量相同的程式碼,這正是
  ICF 的目標。
- **拆掉 ImageFormats / libwebp** — **已查證:它被連進 45 支中的每一支,而只有 3 支需要它。**

  `compile.zsh:643` 掃描的是每一支 `P*.swift`(manifest 刻意列出全部,以保持建置計畫在各次呼叫
  之間逐位元組相同),因此只要 P3 或 P6 存在,`needs_image_formats` 就是 1;接著
  `compile.zsh:719` 把 `ImageFormats` 這個 product 加進**共用的** `testAppDependencies`,而
  每一個 executableTarget 都使用那份清單。

  證據:`P44.swift` 沒有 `import ImageFormats`,而 `libP44.so` 與 `libP3.so` 的 webp 字串常數
  數量完全相同(96 個 `WebP`、264 個 `VP8`、56 個 `libwebp`),兩者都恰好 30.5 MB。實際 import
  ImageFormats 的只有 P3、P6、P6-v2。

  **注意查證方式。** 第一次是用 `llvm-nm libP44.so | grep DecodeWebP`,得到 0,看起來像是「沒有
  連進去」。那什麼都沒證明——該 library 的符號表已被剝除,`llvm-nm` 在整個檔案裡只看得到 **1 個**
  符號。改以字串常數查才得到真正的答案。

  修法:讓每個 target 各自持有依賴清單,只有 P3/P6/P6-v2 拿到 ImageFormats,而不是共用一份
  `testAppDependencies`。manifest 仍然列出全部 app,因此建置計畫的穩定性不受影響——它每次產生的
  內容依然是決定性的。

  **省下多少尚未量測**,需要一次對照建置。

**67.8 MB 那塊在 Android 上沒有出路。**

- ICU 的 38 MB 已用 `readelf` 證明是 `libFoundation.so` 的硬性 `NEEDED`,拿不掉。
- 其餘是 Swift runtime 本身。除非 Android 出現系統級的 Swift(不存在),或改用
  Embedded Swift(不支援 Foundation,也就不支援本工具組)。

**下載量的另一條路:split APK。** 目前只出 arm64-v8a 一種 ABI,所以按 ABI 切省不到。若日後
加上 armeabi-v7a 或 x86_64,則**必須**切,否則 APK 會直接翻倍。

---

## 讀這一頁時要注意的 / Caveats

**iOS 的數字量的是 Simulator 的 `.app`,不是裝置上的 `.ipa`。** 兩者不完全相同——`.ipa` 會經過
App Store 的加密與 thinning——但關鍵結論不受影響:`otool -L` 顯示它連的是 `/usr/lib/swift/`,
而那在裝置上與在模擬器上同樣成立。若要一個裝置端的數字,需要一次真機建置,本機目前做不到。

The iOS figure is a Simulator `.app`, not a device `.ipa`. The conclusion does
not depend on that: `otool -L` shows it linking `/usr/lib/swift/`, which is true
on device as well.

**APK 的數字只涵蓋 arm64-v8a。**
