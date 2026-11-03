# patches

Changes this tree needs in code it does not own, kept as patches because the
tree that owns them is not one this fork can push to.

| patch | applies to | why it is a patch |
| --- | --- | --- |
| `gtk4-pkgconfig-relocate.patch` | a Homebrew gtk4 `.pc` file | rewritten per machine, not per checkout |

Android APKs are packaged by `testapp/package_android.zsh`, which writes the
`<service>` element `windowLevel(.floating)` needs and strips `.swift_ast` from
the packaged library (`SCUI_KEEP_SWIFT_AST=1` keeps it). Swift Bundler is not
used, so no patch for it is kept here.

# patches

本樹需要、但不屬於本樹所有的程式碼變更，以 patch 形式保存，因為擁有它們的那棵樹無法從這裡推送。

| patch | 套用對象 | 為何是 patch |
| --- | --- | --- |
| `gtk4-pkgconfig-relocate.patch` | Homebrew gtk4 的一個 `.pc` 檔 | 每台機器各自改寫，而不是每個 checkout |

Android APK 由 `testapp/package_android.zsh` 打包：它寫入 `windowLevel(.floating)` 需要的 `<service>` 元素，
並從打包的 library 中剝除 `.swift_ast`(`SCUI_KEEP_SWIFT_AST=1` 會保留)。不使用 Swift Bundler，因此這裡不保留它的 patch。
