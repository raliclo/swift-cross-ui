"""Pick the iOS runtime and device type for the test simulator, from `xcrun simctl list runtimes -j` on stdin.

    python3 -I pick_ios_runtime.py <wanted device type> <SDK version>

Prints three tab-separated fields: runtime identifier, device type, and a note (empty when the
wanted type was available). Exits 1 when no available iOS runtime exists.

The order, and why (2026-11-10, the xcode-27 CI image): the runtimes there were iOS 27.0, 27.1 and
two 27.2, and the 27.1 one hosted only an "iPhone Duo"; replays on that device all failed (exit 70)
while iPhone 16 on a 27.2 runtime had passed. So a runtime that supports the wanted type comes first,
the SDK's own version breaking ties, then the newest. Only when no runtime supports the type is another
device used, and the note says so. Device-specific runtimes (iOS-27-2-iPhone19-4) and unavailable
ones are never taken.

為測試模擬器挑 iOS runtime 與裝置型號，從 stdin 讀 `xcrun simctl list runtimes -j`。輸出三個以 tab 分隔的欄位：
runtime 識別碼、裝置型號、備註(要的型號可用時為空)。沒有可用的 iOS runtime 時以 1 結束。先取支援所要型號的
runtime(同版本以 SDK 版本優先，否則取最新);只有沒有任何 runtime 支援時才改用別的裝置，並在備註中說明。
只給特定裝置的 runtime 與不可用的 runtime 一律不取。2026-11-10 的 xcode-27 CI 映像上,27.1 runtime 只能裝
「iPhone Duo」,在其上的重放全部失敗，而 27.2 上的 iPhone 16 先前是通過的。
"""
import json
import re
import sys

wanted, sdk = sys.argv[1], sys.argv[2]


def key(version):
    return tuple(int(part) for part in re.findall(r"\d+", version))


runtimes = [
    r for r in json.load(sys.stdin)["runtimes"]
    if r.get("platform") == "iOS" and r.get("isAvailable")
    and re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-\d+(-\d+)*", r["identifier"])
]
if not runtimes:
    sys.exit(1)


def iphones(runtime):
    return [t["name"] for t in runtime.get("supportedDeviceTypes", []) if t.get("productFamily") == "iPhone"]


def best(candidates):
    same = [r for r in candidates if r["version"] == sdk]
    return max(same or candidates, key=lambda r: key(r["version"]))


hosting = [r for r in runtimes if wanted in iphones(r)]
if hosting:
    chosen = best(hosting)
    print(chosen["identifier"], wanted, "", sep="\t")
else:
    chosen = best(runtimes)
    names = iphones(chosen)
    plain = [n for n in names if re.fullmatch(r"iPhone \d+", n)]
    device = (plain or names or [wanted])[0]
    note = f"no available runtime supports {wanted}; using {device} (iOS {chosen['version']} supports: {', '.join(names) or 'none listed'})"
    print(chosen["identifier"], device, note, sep="\t")
