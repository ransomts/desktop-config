"""Keyboard-resize check in the nested Hyprland: for each pointer spot, focus the window
there and press Super+Ctrl+Right/Left/Down/Up, reporting whether each made it wider /
narrower / taller / shorter (or left it alone)."""
import json, os, subprocess, sys, time

SP = os.path.dirname(os.path.abspath(__file__))
SIG = open(os.path.join(SP, "nested.sig")).read().strip()
WL = open(os.path.join(SP, "nested.wl")).read().strip()
ENV = dict(os.environ, WAYLAND_DISPLAY=WL)


def h(*a):
    return subprocess.run(["hyprctl", "-i", SIG, *a], capture_output=True, text=True).stdout


def mon():
    m = json.loads(h("monitors", "-j"))[0]
    return int(m["width"] / m["scale"]), int(m["height"] / m["scale"])


def ptr(x, y):
    w, hh = mon()
    subprocess.run([os.path.join(SP, "vptr/vptr"), str(w), str(hh), "m", str(x), str(y), "s", "200"], env=ENV)
    time.sleep(0.3)


def kb(*a):
    subprocess.run([os.path.join(SP, "vkbd/vkbd"), *map(str, a)], env=ENV)
    time.sleep(0.5)


def size():
    return json.loads(h("activewindow", "-j"))["size"]


KEYS = [(106, "wider", 0, 1), (105, "narrower", 0, -1), (108, "taller", 1, 1), (103, "shorter", 1, -1)]


def check(label, x, y):
    ptr(x, y)
    start = size()
    out = []
    for code, name, axis, sign in KEYS:
        b = size()
        kb("d", 125, "d", 29, "t", code, "u", 29, "u", 125)
        a = size()
        d = a[axis] - b[axis]
        verdict = "ok" if d * sign > 0 else ("still" if d == 0 else "WRONG")
        out.append(f"{name}:{verdict}({d:+d})")
    print(f"{label:14} {start}  " + "  ".join(out))




def lua(code):
    h("eval", code)
    time.sleep(1.3)


def all_windows(layout_lua):
    lua(layout_lua)
    cs = sorted(json.loads(h("clients", "-j")), key=lambda c: (c["at"][0], c["at"][1]))
    print("--", layout_lua)
    for i, c in enumerate(cs):
        x, y = c["at"]
        w, hh = c["size"]
        check(f"w{i}@{x},{y}", x + w // 2, y + hh // 2)
    lua("Layouts.reset()")


if __name__ == "__main__":
    if sys.argv[1:2] == ["--layouts"]:
        for L in sys.argv[2:]:
            all_windows(L)
    else:
        for spec in sys.argv[1:]:
            label, x, y = spec.split(":")
            check(label, int(x), int(y))
