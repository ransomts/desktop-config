#!/usr/bin/env python3
"""Fake hyprctl for hypr-scripts-test, plus helpers the other stubs use.

State lives in $FAKE_HYPR (a temp dir): clients.json, monitors.json, activeworkspace.json,
cursorpos, locked. Every call that changes something (dispatch, eval, notify, keyword) is appended
to $CALLS as one line "hyprctl ARGS"; queries go to $FAKE_HYPR/queries.

  fakehypr.py hyprctl ARGS...              behave like hyprctl (HYPRCTL_FAIL=1: fail everything)
  fakehypr.py add-client CLASS TITLE WS    add a mapped window (WS: workspace name, e.g. 3 or special:x)

Dispatches understood (0.57 Lua syntax), the rest only recorded:
  hl.dsp.workspace.toggle_special("x")     focused monitor shows special:x, or hides it if showing
  hl.dsp.window.move({ workspace = "special:x", window = "title:^T$" | "class:^C$" ... })
"""
import json, os, re, sys

D = os.environ["FAKE_HYPR"]
CALLS = os.environ["CALLS"]


def load(name, default):
    try:
        with open(os.path.join(D, name)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def save(name, data):
    tmp = os.path.join(D, f".{name}.{os.getpid()}")
    with open(tmp, "w") as f:
        json.dump(data, f, indent=4)
    os.replace(tmp, os.path.join(D, name))


def out(data):
    print(json.dumps(data, indent=4))


def ws_obj(name):
    if name.startswith("special:"):
        return {"id": -98, "name": name}
    return {"id": int(name), "name": name}


def matches(c, sel):
    kind, _, pat = sel.partition(":")
    field = {"title": "title", "class": "class", "address": "address"}.get(kind)
    if not field:
        return False
    if kind == "address":
        return c["address"] == pat
    return re.search(pat, c[field]) is not None


def hyprctl(args):
    log = CALLS if args and args[0] in ("dispatch", "eval", "notify", "keyword") else os.path.join(D, "queries")
    with open(log, "a") as f:
        f.write("hyprctl " + " ".join(args) + "\n")
    if os.environ.get("HYPRCTL_FAIL"):
        print("couldn't connect to the Hyprland socket", file=sys.stderr)
        return 1
    words = [a for a in args if a != "-j"]
    cmd = words[0] if words else ""
    if cmd == "clients":
        out(load("clients.json", []))
    elif cmd == "monitors":
        mons = load("monitors.json", [])
        if "all" not in words:
            mons = [m for m in mons if not m.get("disabled")]
        out(mons)
    elif cmd == "activeworkspace":
        out(load("activeworkspace.json", {"id": 1, "name": "1"}))
    elif cmd == "cursorpos":
        print(open(os.path.join(D, "cursorpos")).read().strip())
    elif cmd == "locked":
        try:
            print(open(os.path.join(D, "locked")).read().strip())
        except OSError:
            print("false")
    elif cmd == "dispatch":
        expr = " ".join(words[1:])
        m = re.search(r'hl\.dsp\.workspace\.toggle_special\("([^"]*)"\)', expr)
        if m:
            mons = load("monitors.json", [])
            for mon in mons:
                if mon.get("focused"):
                    want = "special:" + m.group(1)
                    sw = mon.setdefault("specialWorkspace", {"name": ""})
                    sw["name"] = "" if sw.get("name") == want else want
            save("monitors.json", mons)
        m = re.search(r'hl\.dsp\.window\.move\(\{ *workspace = "([^"]*)", *window = "([^"]*)"', expr)
        if m:
            cl = load("clients.json", [])
            for c in cl:
                if matches(c, m.group(2)):
                    c["workspace"] = ws_obj(m.group(1))
            save("clients.json", cl)
        print("ok")
    elif cmd in ("eval", "notify", "keyword"):
        print("ok")
    else:
        print(f"fake hyprctl: unknown {args}", file=sys.stderr)
        return 2
    return 0


def add_client(cls, title, ws):
    cl = load("clients.json", [])
    cl.append({"address": f"0xadd{len(cl)}", "mapped": True, "class": cls, "title": title,
               "workspace": ws_obj(ws), "focusHistoryID": len(cl)})
    save("clients.json", cl)
    return 0


if __name__ == "__main__":
    if sys.argv[1] == "hyprctl":
        sys.exit(hyprctl(sys.argv[2:]))
    if sys.argv[1] == "add-client":
        sys.exit(add_client(*sys.argv[2:5]))
    sys.exit(2)
