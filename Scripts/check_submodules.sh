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

# `status` is NOT used as a variable name here, and the reason is not style.
#
# This line was `status=$(git submodule status --cached)`, whose value was then
# never read -- dead already. Under `/bin/sh` that is harmless and the script
# exits 0. Under zsh it is fatal: `status` is a READ-ONLY parameter there, so
# the assignment fails with `read-only variable: status` and the guard never
# runs. This project writes its scripts in zsh, so a guard that only works under
# one interpreter is a guard that will one day be invoked by the other.
#
# zsh has a family of these -- `path`, `status`, `options`, `argv`, `cdpath`,
# `fpath`, `manpath`, `watch` -- and `status` is one of the kinder ones because
# it errors. `path=(...)` silently replaces PATH.
#
# 此處**不**以 `status` 作為變數名，理由不是風格。
#
# 這一行原本是 `status=$(git submodule status --cached)`，而該值之後從未被讀取——它本來就是死碼。
# 在 `/bin/sh` 下那無害，腳本以 0 結束；在 zsh 下卻是致命的：`status` 在那裡是**唯讀**參數，該指派會以
# `read-only variable: status` 失敗，於是這個守衛根本不會執行。本專案以 zsh 撰寫腳本，因此「只在某一個
# 直譯器下能用的守衛」，總有一天會被另一個叫到。
#
# zsh 有一整族這樣的名字——`path`、`status`、`options`、`argv`、`cdpath`、`fpath`、`manpath`、`watch`
# ——而 `status` 算是比較仁慈的一個，因為它至少會報錯。`path=(...)` 會**靜默地**取代掉 PATH。
stale=$(git submodule status 2>/dev/null | grep '^+' || true)

if [ -n "$stale" ]; then
    echo "check_submodules: a submodule is NOT at the commit this repository records." >&2
    echo "check_submodules: 有 submodule 不在本倉庫所記錄的 commit 上。" >&2
    echo "$stale" | while IFS= read -r line; do
        echo "  $line" >&2
    done
    echo >&2
    echo "  Two different faults look identical here, and the fixes are opposite." >&2
    echo "  此處有兩種截然不同的故障看起來一模一樣,而它們的修法是相反的。" >&2
    echo >&2
    echo "  A) The CHECKOUT is stale -- you have not run submodule update since" >&2
    echo "     the gitlink moved." >&2
    echo "         git submodule update --init --recursive" >&2
    echo "  A)**checkout** 過時——gitlink 移動之後你沒有跑過 submodule update。" >&2
    echo >&2
    echo "  B) The GITLINK is stale -- a merge resolved it back to an older" >&2
    echo "     value while your checkout is the newer one. Running update would" >&2
    echo "     DISCARD the newer submodule commit." >&2
    echo "         git add <path>   # record what is checked out" >&2
    echo "  B)**gitlink** 過時——某次合併把它解回了較舊的值,而你的 checkout 才是較新的那個。" >&2
    echo "     此時去跑 update 會**丟棄**那個較新的 submodule commit。" >&2
    echo >&2
    echo "  Tell them apart by asking which commit is newer, not by which is" >&2
    echo "  recorded:  git -C <path> log --oneline -1 <each sha>" >&2
    echo "  分辨方式是問「哪一個 commit 較新」,而不是問「哪一個被記錄著」。" >&2
    echo >&2
    echo "  B is not hypothetical: it happened on the first real merge after this" >&2
    echo "  script was written, and the first draft of this message recommended A." >&2
    echo "  B 不是假設:它就發生在本腳本寫成之後的第一次真實合併,而本訊息的初稿建議的是 A。" >&2
    exit 1
fi

# Nothing to say when everything matches. A gate that prints on success trains
# people to ignore its output, and this one is meant to be read.
# 一切相符時不輸出任何訊息。一個成功時也會印東西的守衛,會訓練人們忽略它的輸出,而這一個是要被讀的。
exit 0
