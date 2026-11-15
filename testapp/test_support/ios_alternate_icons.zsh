# ios_add_alternate_icons <bundle.app> <app name>
#
# Declares testapp/icons/<app name>/*.png as alternate app icons of an iOS bundle:
# each PNG is copied in as <name>.png, <name>@2x.png and <name>@3x.png, and listed
# under CFBundleIcons > CFBundleAlternateIcons > <name> in its Info.plist. iOS
# switches only to icons declared at build time (setAlternateIconName returned
# error 3328 and supportsAlternateIcons was false without them, 2026-11-15), so
# this is how Scene.windowIcon(_:) reaches iOS: UIKitBackend maps a PNG URL to the
# alternate icon of the same file name. No such directory, no change.
#
# 把 testapp/icons/<app 名稱>/*.png 宣告為 iOS bundle 的替代 App 圖示：每個 PNG 以 <名稱>.png、<名稱>@2x.png、
# <名稱>@3x.png 複製進去，並列在 Info.plist 的 CFBundleIcons > CFBundleAlternateIcons > <名稱> 之下。iOS 只會
# 切換到建置時宣告過的圖示(沒有宣告時 setAlternateIconName 回傳錯誤 3328、supportsAlternateIcons 為 false,
# 2026-11-15),這就是 Scene.windowIcon(_:) 抵達 iOS 的方式:UIKitBackend 把 PNG 的 URL 對應到同檔名的替代圖示。
# 沒有這個目錄就不做任何變更。

ios_alternate_icons_root="${0:A:h:h}/icons"

ios_add_alternate_icons() {
    local bundle="$1" app="$2" png name
    local -a pngs names
    pngs=("$ios_alternate_icons_root/$app"/*.png(N))
    (( ${#pngs} )) || return 0
    local plist="$bundle/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIcons dict" "$plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :CFBundleIcons:CFBundleAlternateIcons dict" "$plist" 2>/dev/null || true
    for png in "${pngs[@]}"; do
        name="${png:t:r}"
        cp "$png" "$bundle/$name.png"
        cp "$png" "$bundle/$name@2x.png"
        cp "$png" "$bundle/$name@3x.png"
        /usr/libexec/PlistBuddy \
            -c "Delete :CFBundleIcons:CFBundleAlternateIcons:$name" \
            "$plist" 2>/dev/null || true
        /usr/libexec/PlistBuddy \
            -c "Add :CFBundleIcons:CFBundleAlternateIcons:$name dict" \
            -c "Add :CFBundleIcons:CFBundleAlternateIcons:$name:CFBundleIconFiles array" \
            -c "Add :CFBundleIcons:CFBundleAlternateIcons:$name:CFBundleIconFiles:0 string $name" \
            "$plist" >/dev/null
        names+=("$name")
    done
    print "==> iOS alternate icons for $app: ${names[*]}"
}
