"""List a GTK app's accessible elements with their centres in window coordinates.

The WSLg counterpart of uia_rects.c: GTK under WSLg exposes nothing to UIA, but
it answers on the AT-SPI bus. Each line is role, name and the centre of the
element's extents in WINDOW coordinates, the numbers an `origin=frame` action
file row wants once measure_wsl.zsh has applied the calibration it states.

uia_rects.c 的 WSLg 版本:WSLg 下的 GTK 不提供任何東西給 UIA,但會在 AT-SPI bus 上回應。每一行是角色、
名稱，以及元素範圍的中心點(視窗座標);經 measure_wsl.zsh 套用其註明的校正後，就是 `origin=frame`
動作檔列要的數字。

    python3 atspi_rects.py <pid>
"""
import sys
import pyatspi

pid = int(sys.argv[1])
desktop = pyatspi.Registry.getDesktop(0)
apps = [app for app in desktop if app.get_process_id() == pid]
if len(apps) != 1:
    raise SystemExit(f"Expected one AT-SPI application for PID {pid}, found {len(apps)}")


def walk(node, depth=0):
    if depth > 60:
        raise RuntimeError("AT-SPI tree exceeds traversal limit")
    try:
        ext = node.queryComponent().getExtents(pyatspi.WINDOW_COORDS)
        where = f"centre={ext.x + ext.width // 2},{ext.y + ext.height // 2} size={ext.width}x{ext.height}"
    except (NotImplementedError, AttributeError):
        where = "no extents"
    print(f"{'  ' * depth}{node.getRoleName()} '{(node.name or '')[:60]}' {where}")
    for child in node:
        if child is not None:
            walk(child, depth + 1)


walk(apps[0])
