# Symbol mapping table v1 — todo #86 step 1 / 符號對照表 v1 — todo #86 第 1 步

**Verified 2026-09-07.** Every number below carries the command that re-derives it.
Re-run those commands before relying on any figure in this document.

**驗證日期 2026-09-07。** 以下每一個數字都附有可重新推導它的指令。
在引用本文件任何數字之前，請先重跑那些指令。

---

## THE ANSWER / 結論

**36 symbols can fill all five mandatory columns.**

**36 個符號可以填滿全部五個必填欄位。**

Of the 73 Android `ic_*` drawables used as the candidate set: 36 kept, 9 collapsed
as duplicates of a kept row, 28 dropped for a column that could not be established.
`36 + 9 + 28 = 73`.

在作為候選集的 73 個 Android `ic_*` drawable 中：保留 36 個、9 個因與已保留的列重複而
合併、28 個因某一欄無法確立而剔除。`36 + 9 + 28 = 73`。

### The premise was wrong in an important way / 前提有一處重要的錯誤

The task brief named Android's 73 drawables as "the binding constraint". They are
not. **The freedesktop Icon Naming Specification is the binding constraint:** 21 of
the 28 drops are caused by the `gtkIconName` column, against 5 for `sfSymbol` and 5
for `segoeGlyph` (drops counted once per defeating column, so these overlap on the
4 candidates defeated by more than one column). The freedesktop spec has 288 names
and was frozen in the mid-2000s; it has no name for *edit*, *view*, *crop*, *more*,
*share*, *upload*, *today*, *slideshow*, *compass* or *directions*.

任務說明將 Android 的 73 個 drawable 稱為「約束條件」。並非如此。**真正的約束條件是
freedesktop Icon Naming Specification**：28 個剔除中有 21 個肇因於 `gtkIconName` 欄，
而 `sfSymbol` 欄為 5 個、`segoeGlyph` 欄為 5 個（剔除按「造成剔除的欄」計次，因此在被
一欄以上擊敗的 4 個候選上會重複計算）。freedesktop 規格共 288 個名稱、定稿於 2000 年代
中期，其中沒有 *edit*、*view*、*crop*、*more*、*share*、*upload*、*today*、
*slideshow*、*compass*、*directions* 這些名稱。

**Consequence for step 2 / 對第 2 步的影響:** before the table is frozen, verify the
GTK column against a real installed Adwaita theme (`gtk_icon_theme_has_icon`, or
`/usr/share/icons/Adwaita/index.theme`) rather than against the naming spec alone.
Adwaita ships many `*-symbolic` names that the spec never standardised, and several
of the 21 spec-defeated candidates would likely survive that check. This document
deliberately does **not** assert those names, because no in-repo or fetched evidence
for them was obtained.

**在凍結本表之前**，應以實際安裝的 Adwaita 主題（`gtk_icon_theme_has_icon`，或
`/usr/share/icons/Adwaita/index.theme`）而非僅以命名規格來驗證 GTK 欄。Adwaita 提供
許多規格從未標準化的 `*-symbolic` 名稱，被規格擊敗的那 21 個候選中應有數個可通過該檢查。
本文件刻意**不**斷言那些名稱，因為並未取得任何倉庫內或已擷取的證據。

---

## Regeneration commands / 重新產生指令

Run from the repository root. `$TMP` is any scratch directory.

自倉庫根目錄執行。`$TMP` 為任一暫存目錄。

| Number in this doc | Value | Command that re-derives it |
| --- | --- | --- |
| Android `ic_*` drawables | 73 | `grep -cE 'public var ic_[a-z_0-9]+' .build/checkouts/AndroidKit/Sources/AndroidR/R+drawable.swift` |
| Android `JavaStaticField` entries (all drawables) | 174 | `grep -c 'JavaStaticField' .build/checkouts/AndroidKit/Sources/AndroidR/R+drawable.swift` |
| Android drawable names (the list itself) | — | `grep -oE 'public var ic_[a-z_0-9]+' .build/checkouts/AndroidKit/Sources/AndroidR/R+drawable.swift` |
| Segoe Fluent Icons glyph/name pairs | 1533 | `curl -sSL -o $TMP/segoe.md https://raw.githubusercontent.com/MicrosoftDocs/windows-dev-docs/docs/hub/apps/design/iconography/segoe-fluent-icons-font.md && grep -oE '\| [0-9a-fA-F]{4} \| :::no-loc text="[^"]+"' $TMP/segoe.md \| wc -l` |
| Look up one Segoe glyph | — | `grep -oE '\| [0-9a-fA-F]{4} \| :::no-loc text="NAME"' $TMP/segoe.md` |
| freedesktop standard icon names | 288 | `curl -sSL -o $TMP/fd.html http://specifications.freedesktop.org/icon-naming/latest/ && grep -oE '<tr><td>[a-z0-9][a-z0-9-]*</td><td>' $TMP/fd.html \| sort -u \| wc -l` |
| SF Symbols 1.0 names (iOS 13 floor) | 1626 | `curl -sSL -o $TMP/sf10.swift 'https://raw.githubusercontent.com/SFSafeSymbols/SFSafeSymbols/stable/Sources/SFSafeSymbols/Symbols/SFSymbol%2B1.0.swift' && grep -oE 'rawValue: "[^"]+"' $TMP/sf10.swift \| sort -u \| wc -l` |
| Symbols filling all five columns | 36 | Count the rows of the table in [Section 3](#3-the-table--對照表) below. |
| Candidates collapsed as duplicates | 9 | Count the rows of [Section 4](#4-collapsed-duplicates--合併的重複項) below. |
| Candidates dropped | 28 | Count the rows of [Section 5](#5-dropped-candidates--被剔除的候選) below. |

---

## 1. Sources fetched / 已擷取的來源

Every value in the table below was verified against a file actually downloaded to
disk and grepped byte-exactly. Nothing here is written from memory.

下表中每一個值都是對照實際下載到磁碟並以位元組精確 grep 過的檔案驗證而來。此處沒有任何
內容出自記憶。

| Column | Source | URL |
| --- | --- | --- |
| `sfSymbol` | SFSafeSymbols `SFSymbol+1.0.swift` — generated from Apple's `name_availability.plist` in `CoreGlyphs.bundle`; the whole file is under one `@available(iOS 13.0, macOS 11.0, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)` | `https://raw.githubusercontent.com/SFSafeSymbols/SFSafeSymbols/stable/Sources/SFSafeSymbols/Symbols/SFSymbol%2B1.0.swift` |
| `sfSymbol` (repo cross-check) | Existing usage proving `UIImage(systemName:)` is live | `Sources/UIKitBackend/UIKitBackend+Checkbox.swift:41`, `Sources/UIKitBackend/UIKitBackend+Picker.swift:205-211` |
| `gtkIconName` | freedesktop Icon Naming Specification, latest | `http://specifications.freedesktop.org/icon-naming/latest/` (the `https://specifications.freedesktop.org/icon-naming-spec/latest/` URL 301-redirects here) |
| `gtkIconName` (repo cross-check) | `Gtk.Image(iconName:)` binding; runtime existence check `gtk_icon_theme_has_icon` | `Sources/Gtk/Generated/Image.swift:90-94` and `:262`; `Sources/GtkCodeGen/GirFiles/Gtk-4.0.gir:78648` |
| `segoeGlyph` | Microsoft's own docs **source markdown** for the Segoe Fluent Icons list | `https://raw.githubusercontent.com/MicrosoftDocs/windows-dev-docs/docs/hub/apps/design/iconography/segoe-fluent-icons-font.md` |
| `segoeGlyph` (rendered page) | Same content, rendered | `https://learn.microsoft.com/en-us/windows/apps/design/style/segoe-fluent-icons-font` |
| `androidDrawable` | In-repo, checked-out dependency | `.build/checkouts/AndroidKit/Sources/AndroidR/R+drawable.swift` |

### Why the raw markdown, not the summarised page / 為何採用原始 markdown 而非摘要頁面

The rendered Learn page was first read through a summarising fetch. That summary was
then **audited against the raw markdown**, which stores each glyph as a literal table
row of the form:

```
| :::image type="content" border="false" source="images/segoe-fluent-icons/e710.png" alt-text="Screenshot of Add."::: | e710 | :::no-loc text="Add"::: |
```

All 55 code points cross-checked came back identical, so the summary happened to be
correct — but that was verified, not assumed. The raw file is the citation of record
because it can be grepped and re-checked without a model in the loop.

先以摘要式擷取讀取了已渲染的 Learn 頁面，隨後**以原始 markdown 稽核該摘要**，該檔以上方
形式的字面表格列儲存每個字符。交叉核對的 55 個碼位全部一致，因此該摘要恰好正確——但這是
驗證出來的，不是假定的。原始檔案才是正式引用來源，因為它可以在沒有模型介入的情況下被
grep 與重新檢查。

The freedesktop list was audited the same way: 55 spot checks against
`grep -oE '<tr><td>[a-z0-9][a-z0-9-]*</td><td>' fd.html`, all 55 present.

freedesktop 清單也以同樣方式稽核：對 288 個名稱做了 55 次抽檢，55 個全數存在。

---

## 2. Acceptance rules applied / 採用的收錄規則

A row is kept only if all five columns are established. The rules that decided the
marginal cases, stated so the next reader can disagree with them explicitly:

只有五欄全部確立，該列才會保留。以下是決定邊界案例的規則，明確寫出以便下一位讀者能提出
異議：

1. **A name must be grep-present in its authoritative dataset.** No name is written
   from memory. / **名稱必須在其權威資料集中被 grep 到。** 不憑記憶書寫任何名稱。
2. **The freedesktop context must match the symbol's role.** Names in the *Emblems*
   and *Applications* contexts are overlay badges and launcher artwork, not action
   icons, and are rejected even though they exist. This is what drops `edit`
   (only `accessories-text-editor`, Applications), `share` (only `emblem-shared`,
   Emblems) and `gallery` (only `emblem-photos`, Emblems).
   / **freedesktop 的 context 必須與符號角色相符。** *Emblems* 與 *Applications*
   context 中的名稱是覆蓋標記與啟動器圖像，而非動作圖示，即使存在也予以拒絕。
3. **`MimeTypes` context is accepted for document-kind symbols** — `x-office-calendar`
   is the conventional calendar icon across desktops. / **`MimeTypes` context 對文件
   類符號可接受**。
4. **One row per symbol, not per Android drawable.** Where several drawables mean the
   same thing, they collapse to one row and the extras are listed in Section 4.
   / **每個符號一列，而非每個 Android drawable 一列。**
5. **No column may be blank.** A candidate missing any column is dropped, never
   guessed. / **任何一欄都不得留空。** 缺任一欄的候選一律剔除，絕不臆測。

### SF Symbols availability floor / SF Symbols 可用性下限

Every `sfSymbol` below comes from `SFSymbol+1.0.swift`, whose entire extension is
gated on `@available(iOS 13.0, macOS 11.0, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)`.
That is the lowest floor Apple offers and needs no `#available` branch of the kind
already present at `Sources/UIKitBackend/UIKitBackend+Picker.swift:205-210`.

下方每一個 `sfSymbol` 均取自 `SFSymbol+1.0.swift`，其整個 extension 皆受
`@available(iOS 13.0, macOS 11.0, tvOS 13.0, watchOS 6.0, visionOS 1.0, *)` 約束。
這是 Apple 提供的最低下限，不需要 `UIKitBackend+Picker.swift:205-210` 那種
`#available` 分支。

**Four of the chosen names are deprecated aliases.** They still resolve at runtime
via the raw-string `UIImage(systemName:)` path, and they are the only spelling
available at the iOS 13 floor, so they are used deliberately. Their modern
replacements raise the floor and must not be adopted without an `#available` branch.

**所選名稱中有四個是已棄用的別名。** 它們透過原始字串的 `UIImage(systemName:)` 路徑在
執行期仍可解析，且是 iOS 13 下限下唯一可用的拼法，因此為刻意採用。其現代替代名稱會提高
下限，未加 `#available` 分支前不得採用。

| Name used (iOS 13) | Deprecated at | Modern replacement | Floor of replacement |
| --- | --- | --- | --- |
| `mic` | iOS 18.0 / macOS 15.0 | `microphone` | iOS 18.0 |
| `speaker.3` | iOS 14.0 / macOS 11.0 | `speaker.wave.3` | iOS 14.0 |
| `battery.25` | iOS 17.0 / macOS 14.0 | `battery.25percent` | iOS 17.0 |
| `arrow.2.circlepath` | iOS 14.0 / macOS 11.0 | `arrow.triangle.2.circlepath` | iOS 14.0 |

Regeneration: `grep -B8 'rawValue: "mic")' $TMP/sf10.swift`

---

## 3. The table / 對照表

36 rows. Every cell verified present in the source named in Section 1.
`segoeGlyph` is given as the documented glyph name followed by its code point; the
code point is the value to put in a `Glyph="&#x….;"` / `TextBlock.Text` with
`FontFamily("Segoe Fluent Icons")`.

36 列。每一個儲存格都已驗證存在於第 1 節所列的來源中。`segoeGlyph` 以文件中的字符名稱
後接其碼位表示；碼位即為要放進 `Glyph="&#x….;"` / 搭配
`FontFamily("Segoe Fluent Icons")` 的 `TextBlock.Text` 的值。

| # | symbol | `sfSymbol` | `gtkIconName` | `segoeGlyph` | `androidDrawable` | `textFallback` |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | add | `plus` | `list-add` | `Add` U+E710 | `ic_input_add` | `+` |
| 2 | delete | `trash` | `edit-delete` | `Delete` U+E74D | `ic_delete` | `Delete` |
| 3 | warning | `exclamationmark.triangle` | `dialog-warning` | `Warning` U+E7BA | `ic_dialog_alert` | `!` |
| 4 | info | `info.circle` | `dialog-information` | `Info` U+E946 | `ic_dialog_info` | `i` |
| 5 | phone | `phone` | `phone` | `Phone` U+E717 | `ic_dialog_dialer` | `Phone` |
| 6 | mail | `envelope` | `mail-message-new` | `Mail` U+E715 | `ic_dialog_email` | `Mail` |
| 7 | map | `map` | `find-location` | `MapPin` U+E707 | `ic_dialog_map` | `Map` |
| 8 | search | `magnifyingglass` | `system-search` | `Search` U+E721 | `ic_menu_search` | `Search` |
| 9 | lock | `lock` | `system-lock-screen` | `Lock` U+E72E | `ic_lock_idle_lock` | `Lock` |
| 10 | batteryLow | `battery.25` | `battery-low` | `Battery1` U+E851 | `ic_lock_idle_low_battery` | `Battery` |
| 11 | power | `power` | `system-shutdown` | `PowerButton` U+E7E8 | `ic_lock_power_off` | `Power` |
| 12 | mute | `speaker.slash` | `audio-volume-muted` | `Mute` U+E74F | `ic_lock_silent_mode` | `Mute` |
| 13 | volume | `speaker.3` | `audio-volume-high` | `Volume` U+E767 | `ic_lock_silent_mode_off` | `Volume` |
| 14 | microphone | `mic` | `audio-input-microphone` | `Microphone` U+E720 | `ic_btn_speak_now` | `Mic` |
| 15 | fastForward | `forward` | `media-seek-forward` | `FastForward` U+EB9D | `ic_media_ff` | `>>` |
| 16 | next | `forward.end` | `media-skip-forward` | `Next` U+E893 | `ic_media_next` | `>\|` |
| 17 | pause | `pause` | `media-playback-pause` | `Pause` U+E769 | `ic_media_pause` | `\|\|` |
| 18 | play | `play` | `media-playback-start` | `Play` U+E768 | `ic_media_play` | `>` |
| 19 | previous | `backward.end` | `media-skip-backward` | `Previous` U+E892 | `ic_media_previous` | `\|<` |
| 20 | rewind | `backward` | `media-seek-backward` | `Rewind` U+EB9E | `ic_media_rew` | `<<` |
| 21 | camera | `camera` | `camera-photo` | `Camera` U+E722 | `ic_menu_camera` | `Camera` |
| 22 | cancel | `xmark` | `window-close` | `Cancel` U+E711 | `ic_menu_close_clear_cancel` | `X` |
| 23 | help | `questionmark.circle` | `help-contents` | `Help` U+E897 | `ic_menu_help` | `?` |
| 24 | calendar | `calendar` | `x-office-calendar` | `Calendar` U+E787 | `ic_menu_my_calendar` | `Calendar` |
| 25 | settings | `gear` | `preferences-system` | `Settings` U+E713 | `ic_menu_preferences` | `Settings` |
| 26 | recent | `clock` | `document-open-recent` | `Recent` U+E823 | `ic_menu_recent_history` | `Recent` |
| 27 | revert | `arrow.uturn.left` | `document-revert` | `Undo` U+E7A7 | `ic_menu_revert` | `Undo` |
| 28 | rotate | `rotate.right` | `object-rotate-right` | `Rotate` U+E7AD | `ic_menu_rotate` | `Rotate` |
| 29 | save | `square.and.arrow.down` | `document-save` | `Save` U+E74E | `ic_menu_save` | `Save` |
| 30 | send | `paperplane` | `document-send` | `Send` U+E724 | `ic_menu_send` | `Send` |
| 31 | sort | `arrow.up.arrow.down` | `view-sort-ascending` | `Sort` U+E8CB | `ic_menu_sort_alphabetically` | `Sort` |
| 32 | zoomIn | `plus.magnifyingglass` | `zoom-in` | `ZoomIn` U+E8A3 | `ic_menu_zoom` | `Zoom` |
| 33 | clear | `xmark.circle` | `edit-clear` | `Clear` U+E894 | `ic_notification_clear_all` | `Clear` |
| 34 | reminder | `bell` | `appointment-soon` | `Reminder` U+EB50 | `ic_popup_reminder` | `Reminder` |
| 35 | sync | `arrow.2.circlepath` | `sync-synchronizing` | `Sync` U+E895 | `ic_popup_sync` | `Sync` |
| 36 | secure | `lock.shield` | `security-high` | `Shield` U+EA18 | `ic_secure` | `Secure` |

### Verify any row of this table / 驗證本表任一列

```sh
# sfSymbol present at the iOS 13 floor / sfSymbol 存在於 iOS 13 下限
grep -qx 'plus' $TMP/sf10_names.txt && printf 'OK\n'

# gtkIconName present in the naming spec / gtkIconName 存在於命名規格中
grep -qx 'list-add' $TMP/fd_names.txt && printf 'OK\n'

# segoeGlyph name -> code point / segoeGlyph 名稱 -> 碼位
grep -oE '\| [0-9a-fA-F]{4} \| :::no-loc text="Add"' $TMP/segoe.md

# androidDrawable present / androidDrawable 存在
# Anchor on ': Int32'. A bare substring match is wrong here: 'ic_lock_silent_mode'
# would also match 'ic_lock_silent_mode_off'. Anchoring on '$' is also wrong --
# the line is "  public var ic_input_add: Int32", so '$' never matches and every
# name reports MISS. Both mistakes were made while producing this document.
# 必須以 ': Int32' 定錨。單純的子字串比對會誤中 'ic_lock_silent_mode_off'；
# 而以 '$' 定錨則永遠不匹配，會讓每個名稱都回報 MISS。撰寫本文件時兩種錯誤都犯過。
grep -qF 'public var ic_input_add: Int32' .build/checkouts/AndroidKit/Sources/AndroidR/R+drawable.swift && printf 'OK\n'
```

Android's runtime existence check is `Resources.getIdentifier`, which returns `0`
for a missing name. GTK's is `gtk_icon_theme_has_icon`
(`Sources/GtkCodeGen/GirFiles/Gtk-4.0.gir:78648`).

Android 的執行期存在性檢查是 `Resources.getIdentifier`，名稱不存在時回傳 `0`。
GTK 的則是 `gtk_icon_theme_has_icon`。

---

## 4. Collapsed duplicates / 合併的重複項

9 Android drawables that mean the same thing as a row already in the table. They are
not losses; they are alternative `androidDrawable` values for an existing row.

9 個與表中既有列意義相同的 Android drawable。它們並非損失，而是既有列的替代
`androidDrawable` 值。

| Android drawable | Collapses into row |
| --- | --- |
| `ic_input_get` | 8 search |
| `ic_search_category_default` | 8 search |
| `ic_menu_add` | 1 add |
| `ic_menu_delete` | 2 delete |
| `ic_menu_info_details` | 4 info |
| `ic_menu_call` | 5 phone |
| `ic_menu_mapmode` | 7 map |
| `ic_lock_lock` | 9 lock |
| `ic_menu_manage` | 25 settings |

---

## 5. Dropped candidates / 被剔除的候選

28 candidates, each with the column that defeated it. Where two or three columns
failed, all are listed.

28 個候選，各自附上擊敗它的欄位。若有兩欄或三欄失敗，則全部列出。

| Android drawable | Defeated by | Evidence |
| --- | --- | --- |
| `ic_input_delete` | `gtkIconName` | Spec has no backspace name; `edit-clear` is already row 33. `grep -i backspace $TMP/fd_names.txt` → empty |
| `ic_lock_idle_alarm` | `gtkIconName`, `segoeGlyph` | Spec has no alarm/clock/timer name. Segoe has no `Alarm` and no `Timer`: `grep -iP '\t[A-Za-z0-9]*Alarm[A-Za-z0-9]*$' $TMP/segoe_pairs.tsv` → empty |
| `ic_lock_idle_charging` | `sfSymbol` | SF Symbols 1.0 battery family is exactly `battery.0`, `battery.25`, `battery.100`; no charging variant. `grep '^battery' $TMP/sf10_names.txt` |
| `ic_menu_agenda` | `gtkIconName` | No generic list name. `grep -i list $TMP/fd_names.txt` → only `list-add`, `list-remove`, `media-playlist-repeat`, `media-playlist-shuffle` |
| `ic_menu_always_landscape_portrait` | `gtkIconName` | No orientation name. `grep -iE 'orient|landscape|portrait' $TMP/fd_names.txt` → empty |
| `ic_menu_compass` | `gtkIconName` | `grep -i compass $TMP/fd_names.txt` → empty |
| `ic_menu_crop` | `gtkIconName` | `grep -ix crop $TMP/fd_names.txt` → empty. **Note the trap:** `grep -i crop` appears to hit, but the only match is `audio-input-mi`**`crop`**`hone` |
| `ic_menu_day` | `gtkIconName` | `grep -i day $TMP/fd_names.txt` → empty |
| `ic_menu_directions` | `gtkIconName` | `grep -i direction $TMP/fd_names.txt` → only `format-text-direction-ltr`/`-rtl` |
| `ic_menu_edit` | `gtkIconName` | Only `accessories-text-editor`, an *Applications*-context launcher icon (rule 2). No `document-edit` in the spec |
| `ic_menu_gallery` | `gtkIconName` | Only `emblem-photos`, an *Emblems*-context overlay (rule 2) |
| `ic_menu_month` | `gtkIconName`, `segoeGlyph` | Spec: no month name. Segoe: `grep -iP '\t[A-Za-z0-9]*Month[A-Za-z0-9]*$'` → empty (`CalendarDay` and `CalendarWeek` exist, `CalendarMonth` does not) |
| `ic_menu_more` | `gtkIconName` | No overflow/ellipsis name in the spec |
| `ic_menu_mylocation` | `gtkIconName` | The one location name, `find-location`, is already row 7 |
| `ic_menu_myplaces` | `gtkIconName` | Only `user-bookmarks`, a *Places*-context bookmark folder — not a place marker |
| `ic_menu_report_image` | `gtkIconName`, `segoeGlyph` | Spec: no report name. Segoe: `grep -iP '\tReport$'` → empty |
| `ic_menu_set_as` | `sfSymbol` | No wallpaper / set-as symbol in SF 1.0. (`preferences-desktop-wallpaper` and Segoe `Personalize` U+E771 both exist — the SF column is what defeats it) |
| `ic_menu_share` | `gtkIconName` | Only `emblem-shared`, an *Emblems*-context overlay (rule 2) |
| `ic_menu_slideshow` | `gtkIconName` | `grep -i slide $TMP/fd_names.txt` → empty. (Segoe `Slideshow` U+E786 exists) |
| `ic_menu_sort_by_size` | `segoeGlyph` | Segoe has exactly one sort glyph, `Sort` U+E8CB, already row 31; no descending variant. (`view-sort-descending` exists in the spec) |
| `ic_menu_today` | `gtkIconName` | Spec has no today name. (Segoe `GotoToday` U+E8D1 exists) |
| `ic_menu_upload` | `gtkIconName` | Spec has no upload/send-to name. (Segoe `Upload` U+E898 exists) |
| `ic_menu_upload_you_tube` | `sfSymbol`, `gtkIconName`, `segoeGlyph` | Vendor-specific; no cross-platform equivalent in any of the three sets |
| `ic_menu_view` | `gtkIconName` | No generic view name; only `view-fullscreen`, `view-refresh`, `view-restore`, `view-sort-ascending`, `view-sort-descending` |
| `ic_menu_week` | `gtkIconName` | `grep -i week $TMP/fd_names.txt` → empty. (Segoe `CalendarWeek` U+E8C0 exists) |
| `ic_notification_overlay` | `sfSymbol`, `gtkIconName`, `segoeGlyph` | An AOSP compositing artefact, not a user-facing symbol; no equivalent in any set |
| `ic_partial_secure` | `segoeGlyph` | Segoe has no partial/medium-security glyph. (`security-medium` exists in the spec) |
| `ic_popup_disk_full` | `sfSymbol` | SF Symbols 1.0 has **no** drive or disk symbol at all: `grep -E 'drive\|disk\|disc' $TMP/sf10_names.txt` → empty. (`drive-harddisk` and Segoe `HardDrive` U+EDA2 both exist) |

### Drops by defeating column / 依擊敗欄位統計剔除數

Counted once per defeating column, so the total exceeds 28 by the 4 candidates that
lost more than one column.

按「造成剔除的欄」計次，因此總數比 28 多出 4——那是失去一欄以上的候選數。

| Column | Drops it caused |
| --- | --- |
| `gtkIconName` | 21 |
| `sfSymbol` | 5 |
| `segoeGlyph` | 5 |
| `androidDrawable` | 0 (it is the candidate set) |
| `textFallback` | 0 (always expressible) |

---

## 6. Left uncertain / 尚未確定之處

Recorded rather than resolved. Each is a real risk to the table, not a formality.

以下為記錄而非已解決的事項。每一項都是本表的實際風險，而非形式。

1. **No glyph was rendered.** Existence of a name in a list is not proof that the
   picture is the one intended. Every `segoeGlyph` code point is confirmed against
   Microsoft's own docs source, and every `gtkIconName` against the spec, but nothing
   in this document was drawn on a screen. A visual pass over all 36 on at least
   GTK and WinUI belongs in a later step.
   / **未渲染任何字符。** 名稱存在於清單中，並不證明圖形就是所要的那一個。
2. **`Segoe Fluent Icons` is not present on Windows 10 by default.** Microsoft's page
   states it ships with Windows 11 but must be downloaded separately for Windows 10.
   The WinUI backend needs a fallback path when the family is absent, or every glyph
   becomes a blank box with no error — the exact silent-failure class this repo's
   rules exist to stop. `textFallback` is the intended answer; it must actually be
   wired up. / **Windows 10 預設不含 `Segoe Fluent Icons`。** WinUI backend 需要字型
   缺失時的退路，否則每個字符都會變成空白方框且不報錯。
3. **The GTK column is judged against the naming spec, not a live theme.** As stated
   at the top, this is the single largest source of avoidable drops. `edit`, `view`,
   `more`, `share`, `crop`, `upload`, `today`, `slideshow`, `compass` and
   `directions` would very plausibly resolve against Adwaita's `*-symbolic` names.
   Verifying with `gtk_icon_theme_has_icon` could raise 36 substantially. It was not
   done here because no Adwaita theme index was available to grep, and asserting
   those names from memory is precisely what these rules forbid.
   / **GTK 欄是對照命名規格而非實際主題判定的。** 這是可避免之剔除的最大來源。
4. **Four SF names are deprecated aliases** (Section 2). They resolve today through
   the raw-string API. If a future step moves to a typed symbol enum, they will need
   `#available` branches. / **四個 SF 名稱是已棄用的別名。**
5. **Three freedesktop choices are semantically adjacent rather than exact**, and are
   the rows most likely to be revised: row 6 `mail` → `mail-message-new` (spec's
   envelope is "compose new message"); row 7 `map` → `find-location` (an action, not
   a map); row 25 `settings` → `preferences-system` (a *Categories*-context icon).
   / **三個 freedesktop 選擇僅為語意相近而非精確對應**，是最可能被修訂的列。
6. **Row 27 `revert` uses Segoe `Undo`.** Segoe has no `Revert` glyph
   (`grep -iP '\tRevert$'` → empty). Undo and revert are distinct operations; if the
   API ever exposes both, this row collides.
   / **第 27 列 `revert` 使用 Segoe 的 `Undo`。** Segoe 沒有 `Revert` 字符。
7. **`AndroidKit` is a checked-out dependency under `.build/`, not tracked source.**
   The 73-name count is only stable for the currently resolved version. A dependency
   bump can change it silently. / **`AndroidKit` 是 `.build/` 下的簽出相依套件，而非
   受版控的原始碼。** 73 這個數字僅對目前解析到的版本成立。

---

## 7. What this unblocks / 本步驟解除的阻塞

- `Sources/SwiftCrossUI/Views/Image.swift:11-14` — `Source` is `.url` or `.image`
  only; a `.symbol` case is what the table's row identity feeds.
- `Sources/SwiftCrossUI/Views/Label.swift:6-20` — the doc comment there states that
  `Label(_:systemImage:)` is deliberately absent and commits: *"The initialiser
  arrives with the symbol API, in the same change."* The 36 rows are that API's
  domain.

No Swift was written in this step, per the task's instruction.

依任務指示，本步驟未撰寫任何 Swift 程式碼。
