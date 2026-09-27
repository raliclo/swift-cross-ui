#!/usr/bin/env zsh
set -euo pipefail
support_dir="${0:a:h}"
export TEST_APP="P17-DOE"
# **This script did not exist until 2026-09-27**, though P17-DOE had a macOS and
# an iOS action file. Nothing noticed, because the sweep cut file names at the
# first dash and ran those files against P17 instead -- see sweep_apple.zsh's
# app_of. Title copied from P17-DOE.swift's WindowGroup. No marker, for the
# reason test_P45.zsh gives.
# **這支腳本在 2026-09-27 之前不存在**,雖然 P17-DOE 有 macOS 與 iOS 動作檔。沒有任何東西察覺,因為
# sweep 在第一個破折號處切開檔名,把那些檔案拿去對 P17 執行——見 sweep_apple.zsh 的 app_of。標題照抄自
# P17-DOE.swift 的 WindowGroup。不設 marker,理由見 test_P45.zsh。
export TEST_TITLE="P17-DOE clipping directions"
export TEST_TARGET="both"
exec zsh "$support_dir/test_common.zsh" "$@"
