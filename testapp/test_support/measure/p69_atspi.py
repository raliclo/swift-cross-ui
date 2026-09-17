"""Read P69 through the external AT-SPI bus, not its in-process probe."""
import json
import sys
import pyatspi

pid = int(sys.argv[1])
desktop = pyatspi.Registry.getDesktop(0)
apps = [app for app in desktop if app.get_process_id() == pid]
if len(apps) != 1:
    raise SystemExit(f"Expected one AT-SPI application for PID {pid}, found {len(apps)}")

nodes = []

def walk(node, depth=0):
    if depth > 60:
        raise RuntimeError("AT-SPI tree exceeds traversal limit")
    row = {"role": node.getRoleName(), "name": node.name,
           "description": node.description, "attributes": node.getAttributes()}
    try:
        row["value_text"] = node.queryValue().text
    except (NotImplementedError, AttributeError):
        pass
    nodes.append(row)
    for child in node:
        if child is not None:
            walk(child, depth + 1)

walk(apps[0])
print(json.dumps(nodes, ensure_ascii=False, indent=2))
checks = {
    "label": any(n["role"] == "button" and n["name"] == "Close"
                 and n["description"] == "" for n in nodes),
    "no_original_label": not any(n["name"] == "X" for n in nodes),
    "hint": any(n["name"] == "Delete" and
                n["description"] == "Removes the file permanently" for n in nodes),
    "value": any(n["name"] == "Volume" and
                 (n.get("value_text") == "40 percent" or
                  "valuetext:40 percent" in n["attributes"]) for n in nodes),
    "hidden": not any(n["name"] == "decorative" for n in nodes),
}
print(json.dumps({"checks": checks}))
raise SystemExit(0 if all(checks.values()) else 1)
