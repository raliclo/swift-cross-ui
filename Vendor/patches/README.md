# Vendor/patches

Changes this repository needs in a vendored submodule, kept as files because
there is nowhere to commit them.

## Why a patch and not a commit

`Vendor/swift-bundler` points at `moreSwift/swift-bundler`, which is upstream and
not a fork we can push to. So a change we make there has no commit to point the
gitlink at: it can only exist as an uncommitted diff in one working tree.

That is how `swift-bundler-android-service.patch` spent five days. It was found
on 2026-09-09 by a downstream consumer's session, which had scoped a
reproducibility check to `git status --porcelain` and noticed that
`Vendor/swift-bundler` never came back clean. From the parent repository
`git diff --stat` reports zero lines for a submodule -- it is one pointer -- so
the 117 lines were invisible to every check that ran here.

**A clean clone of this repository loses Android floating windows, and nothing
reports it.** Not a build failure: the manifest simply has no `<service>`, the
overlay is owned by the activity, and it disappears when the activity stops.

## The patch

`swift-bundler-android-service.patch` adds `<service>` support to the Android
manifest. `windowLevel(.floating)` on Android is a `TYPE_APPLICATION_OVERLAY`,
and an overlay owned by an activity is hidden the moment that activity stops --
measured 2026-09-04 with `dumpsys` reporting `Surface: shown=false
mLastHidden=true` while the view was still VISIBLE.

Apply it with the submodule at the commit the gitlink names:

    git -C Vendor/swift-bundler apply ../patches/swift-bundler-android-service.patch

It last applied cleanly onto `53a55d1`, which is 9 commits after the tree it was
written against; upstream's changes to `APKBundler.swift` are at lines 387-505
and this patch's are at 269 and 1032, so they have not collided yet.

## This is a holding measure

The durable fixes are to fork `swift-bundler` under a remote we can push to and
point the submodule there, or to get the change upstream. Both are decisions
about what this repository's dependency IS, which is why neither was taken
unilaterally. Until one of them happens, re-check this file whenever the gitlink
moves.

# Vendor/patches

本倉庫在某個 vendored submodule 中所需要的改動,以檔案形式保存,因為那些改動無處可提交。

## 為什麼是 patch 而不是 commit

`Vendor/swift-bundler` 指向 `moreSwift/swift-bundler`,那是上游,不是我們推得上去的 fork。因此我們
在那裡所做的改動沒有任何 commit 可供 gitlink 指向:它只能以「某一個工作目錄中未提交的 diff」存在。

`swift-bundler-android-service.patch` 就這樣度過了五天。它於 2026-09-09 被一個下游使用者的 session
發現——對方把一項可重現性檢查的範圍設為 `git status --porcelain`,並注意到 `Vendor/swift-bundler`
從來沒有乾淨過。從母倉庫執行 `git diff --stat` 對一個 submodule 只會回報零行——它是一個指標——
因此那 117 行對此處執行過的每一項檢查都是隱形的。

**一份乾淨的 clone 會失去 Android 的浮動視窗,而且沒有任何東西會回報。** 那不是建置失敗:manifest
裡只是沒有 `<service>`,overlay 由 activity 擁有,而它會在該 activity 停止時消失。

## 這份 patch

`swift-bundler-android-service.patch` 為 Android manifest 加上 `<service>` 支援。
`windowLevel(.floating)` 在 Android 上是 `TYPE_APPLICATION_OVERLAY`,而由 activity 擁有的 overlay
會在該 activity 停止的瞬間被隱藏——2026-09-04 以 `dumpsys` 量測,view 仍為 VISIBLE 而
`Surface: shown=false mLastHidden=true`。

在 submodule 位於 gitlink 所指的 commit 時套用:

    git -C Vendor/swift-bundler apply ../patches/swift-bundler-android-service.patch

它最後一次乾淨地套用在 `53a55d1` 上,那比它當初所依據的樹晚了 9 個 commit;上游對
`APKBundler.swift` 的改動位於第 387-505 行,而本 patch 的位於第 269 與 1032 行,因此兩者尚未相撞。

## 這只是權宜之計

真正durable 的做法有兩個:把 `swift-bundler` fork 到一個我們推得上去的 remote 並改指過去,或是把該
改動送進上游。兩者都是「本倉庫的相依究竟是什麼」的決定,這正是兩者都沒有被單方面採取的原因。在其中
之一發生之前,每當 gitlink 移動時都要重新檢查本檔案。
