#!/bin/sh
#
# Says whether this working tree currently compiles, in one line, for anyone
# building against it by local path.
#
# **Why this exists.** A downstream consumer depends on this checkout by
# filesystem path, not by a pinned commit, so its dependency is the WORKING
# TREE. Adding a requirement to a backend protocol breaks that tree from the
# moment the declaration lands until the last conformance does -- on 2026-09-09
# that was about forty minutes for `BackendFeatures.ScrollContainers`, and the
# consumer discovered it as a compile error rather than as a message.
#
# Writing the conformances first and committing them together fixes it for every
# PUSHED commit. It does not fix the working tree, and the difference is easy to
# miss because git is satisfied either way.
#
# The remedy agreed with that consumer is a message before a long window and
# another when it closes. A remembered promise is the weakest kind, so this
# script answers the question the message is about, and answers it from the
# compiler rather than from intent:
#
#     sh Scripts/announce_window.sh
#     OPEN: the working tree does not compile (Scripts/test.sh fails)
#
# Run it before saying the window is closed. "I think I finished" and "the tree
# compiles" are different claims and only the second one is checkable.
#
# 以一行說明：這個工作目錄目前編不編得過——供任何以 local path 建置於其上的人使用。
#
# **它為何存在。** 一個下游使用者是以檔案系統路徑、而非以釘住的 commit 相依於本 checkout，因此它的
# 相依對象是這個**工作目錄**。往某個 backend protocol 加入一條 requirement，會從宣告落地的那一刻起、
# 到最後一個 conformance 完成為止，一直讓那個目錄壞著——2026-09-09 那次 `BackendFeatures.ScrollContainers`
# 大約壞了四十分鐘，而那位使用者是以編譯錯誤、而不是以一則訊息發現它的。
#
# 「先寫 conformance、再一起提交」修好的是每一個**推出去的** commit。它並沒有修好工作目錄，而這個差別
# 很容易被略過，因為 git 兩種情況都不會有意見。
#
# 與那位使用者議定的補救方式，是「長空窗之前發一則訊息、關閉時再發一則」。而一個靠記憶維持的承諾是最
# 脆弱的一種，因此本腳本回答那則訊息所講的那個問題，而且是由編譯器回答、不是由意圖回答。
#
# 在宣布空窗已關閉之前先跑它。「我想我做完了」與「這棵樹編得過」是兩個不同的主張，而只有後者可被檢查。

cd "$(dirname "$0")"/../ || exit 1

if sh Scripts/test.sh >/dev/null 2>&1; then
    echo "CLOSED: the working tree compiles and the tests pass"
    echo "CLOSED：工作目錄編得過，測試也通過"
    exit 0
fi

echo "OPEN: the working tree does not compile (Scripts/test.sh fails)"
echo "OPEN：工作目錄編不過（Scripts/test.sh 失敗）"
echo
echo "  Anyone building against this checkout by local path will fail, and the"
echo "  failure will look like theirs. Tell them before they find it."
echo "  任何以 local path 建置於本 checkout 之上的人都會失敗，而那個失敗看起來會像是他們自己的。"
echo "  在他們自己撞到之前告訴他們。"
exit 1
