# avd_host_io.zsh — lets an Android emulator take this Mac's keyboard and play sound.
# avd_host_io.zsh —— 讓 Android 模擬器接收這台 Mac 的鍵盤輸入並發出聲音。
#
#   source avd_host_io.zsh
#   avd_host_io <avd name>          hw.keyboard=yes and hw.audioOutput=yes in the AVD's config.ini;
#                                   returns 0 when it changed the file (it applies from the next boot)
#                                   在 AVD 的 config.ini 設 hw.keyboard=yes 與 hw.audioOutput=yes;
#                                   有改檔時回傳 0(下次開機生效)
#   ime_with_hard_keyboard <adb…>   keeps the on-screen keyboard showing while the host keyboard is attached
#                                   接著主機鍵盤時，螢幕鍵盤仍照常顯示
#
# Why / 為何:
# - hw.keyboard is an AVD setting with no emulator flag; with "no", typing on the Mac reaches nothing
#   (2026-10-23, swift-cross-ui-tablet36). Sound is the emulator's -no-audio flag, which no script
#   passes; hw.audioOutput is checked as well so the AVD itself has sound.
#   hw.keyboard 是 AVD 設定，沒有對應的啟動參數；設為 no 時在 Mac 上打字什麼都收不到(2026-10-23,
#   swift-cross-ui-tablet36)。聲音由 -no-audio 參數決定，沒有腳本傳它；這裡也檢查 hw.audioOutput,讓 AVD 本身有聲音。
# - With a hardware keyboard Android hides the on-screen keyboard, and the tests tap its keys, so
#   show_ime_with_hard_keyboard is set to 1.
#   有實體鍵盤時 Android 會隱藏螢幕鍵盤，而測試要點它的鍵，所以把 show_ime_with_hard_keyboard 設為 1。

avd_host_io() {
    setopt local_options extended_glob
    local name="$1" cfg="${ANDROID_AVD_HOME:-$HOME/.android/avd}/$1.avd/config.ini"
    local key i found changed=1
    local -a lines
    [[ -n "$name" && -f "$cfg" ]] || return 1
    for key in hw.keyboard hw.audioOutput; do
        lines=("${(@f)$(<"$cfg")}")
        found=0
        for (( i = 1; i <= ${#lines}; i++ )); do
            [[ "${lines[i]}" == ${key}[[:space:]]#=* ]] || continue
            found=1
            [[ "${lines[i]#*=}" == [[:space:]]#yes[[:space:]]# ]] && break
            csv2 --headers 0 -update "$i:1" "$key=yes" -i "$cfg" --in-place >/dev/null || return 1
            print "==> $name: $key=yes (was \"${lines[i]}\")"
            changed=0
            break
        done
        if (( ! found )); then
            csv2 --headers 0 -append "$key=yes" -i "$cfg" --in-place >/dev/null || return 1
            print "==> $name: $key=yes (added)"
            changed=0
        fi
    done
    return $changed
}

ime_with_hard_keyboard() {
    "$@" shell settings put secure show_ime_with_hard_keyboard 1 >/dev/null 2>&1 || true
}
