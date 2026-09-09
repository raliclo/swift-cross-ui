#!/bin/sh
#
# Fails when a submodule's working tree is not at the commit this repository
# recorded for it.
#
# `git submodule status` marks that with a leading `+` and exits 0. Nothing else
# reports it: the build compiles whatever is on disk, so a submodule sitting at
# an older commit produces a working binary that is missing whatever the newer
# commit added.
#
# **This has already happened once, on 2026-09-09, and it was silent.** The
# Windows checkout carried `Vendor/swift-bundler` at `53a55d1` while its own HEAD
# recorded `922ba2a`. `5a990fd5`, which moved the pointer to the fork carrying
# the Android `<service>` patch, WAS an ancestor of that HEAD -- three merge
# commits later, one of them had resolved the gitlink back to the other side's
# older value. A gitlink conflict does not present as a conflict; git picks one.
#
# The consequence there was an Android manifest with no `<service>`, so
# `windowLevel(.floating)` windows disappeared when their activity stopped, with
# no build failure and nothing naming the cause.
#
# 當某個 submodule 的工作目錄不在本倉庫為它所記錄的 commit 上時,失敗。
#
# `git submodule status` 會以開頭的 `+` 標示這件事,然後以 0 結束。沒有別的東西會回報它:建置編譯的是
# 磁碟上的東西,因此一個停在較舊 commit 的 submodule,會產出一個「可以運作、但缺了較新 commit 所加入
# 之物」的二進位檔。
#
# **這已經發生過一次,在 2026-09-09,而且是靜默的。** Windows 的 checkout 讓 `Vendor/swift-bundler`
# 停在 `53a55d1`,而它自己的 HEAD 記錄的是 `922ba2a`。把指標移到「帶有 Android `<service>` patch 的
# fork」的那個 `5a990fd5`,**確實**是該 HEAD 的祖先——三個 merge commit 之後,其中一個把 gitlink 解回了
# 另一側較舊的值。gitlink 的衝突不會以衝突的形式出現;git 會自己挑一個。
#
# 在那裡造成的後果,是一個沒有 `<service>` 的 Android manifest,於是 `windowLevel(.floating)` 的視窗
# 會在其 activity 停止時消失,沒有建置失敗,也沒有任何東西指出成因。

cd "$(dirname "$0")"/../ || exit 1

status=$(git submodule status --cached 2>/dev/null)
stale=$(git submodule status 2>/dev/null | grep '^+' || true)

if [ -n "$stale" ]; then
    echo "check_submodules: a submodule is NOT at the commit this repository records." >&2
    echo "check_submodules: 有 submodule 不在本倉庫所記錄的 commit 上。" >&2
    echo "$stale" | while IFS= read -r line; do
        echo "  $line" >&2
    done
    echo >&2
    echo "  Fix:  git submodule update --init --recursive" >&2
    echo "  修法:git submodule update --init --recursive" >&2
    exit 1
fi

# Nothing to say when everything matches. A gate that prints on success trains
# people to ignore its output, and this one is meant to be read.
# 一切相符時不輸出任何訊息。一個成功時也會印東西的守衛,會訓練人們忽略它的輸出,而這一個是要被讀的。
exit 0
