#!/usr/bin/env python3
# display-layout against canned `hyprctl -j monitors all` output and a fake hyprctl that records
# every call (bin/displays-test runs this). Nothing here reaches the real Hyprland: HYPRCTL points
# at tests/displays/fake-hyprctl, every path is in a temporary directory.
#   cli-test.py DISPLAY_LAYOUT TESTS_DIR WORK_DIR [-v]
# Lines: "PASS name" / "FAIL name   [detail]"; "SENT ..." shows the exact hyprctl calls.
import json, os, re, shutil, subprocess, sys, time

tool, tests, work = sys.argv[1:4]
verbose = "-v" in sys.argv
fixtures = os.path.join(tests, "fixtures")
fake = os.path.join(tests, "fake-hyprctl")
passed = failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print("PASS " + name)
    else:
        failed += 1
        print("FAIL " + name + ("   [%s]" % detail if detail != "" else ""))


class Env:
    """One fixture in its own directory: fake monitors, call log, runtime dir, config files."""
    n = 0

    def __init__(self, fixture, **extra):
        Env.n += 1
        self.d = os.path.join(work, "cli%02d-%s" % (Env.n, fixture))
        os.makedirs(self.d)
        os.makedirs(os.path.join(self.d, "run"), mode=0o700)
        self.mon = os.path.join(self.d, "monitors.json")
        shutil.copy(os.path.join(fixtures, fixture + ".json"), self.mon)
        self.log = os.path.join(self.d, "calls")
        self.env = dict(os.environ)
        self.env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
        self.env.update({"HYPRCTL": fake, "FAKE_MONITORS": self.mon, "FAKE_LOG": self.log,
                         "XDG_RUNTIME_DIR": os.path.join(self.d, "run"),
                         "DISPLAY_LAYOUT_SAVED": os.path.join(self.d, "displays.json"),
                         "DISPLAY_LAYOUT_LUA": os.path.join(self.d, "monitors.lua"),
                         "DISPLAY_LAYOUT_WATCHDOG": "0", "DISPLAY_LAYOUT_VERIFY": "0",
                         "HYPRLAND_INSTANCE_SIGNATURE": "test-instance"})
        self.env.update(extra)

    def run(self, *args, **env):
        e = dict(self.env)
        for k, v in env.items():
            if v is None:
                e.pop(k, None)
            else:
                e[k] = v
        p = subprocess.run([tool] + list(args), capture_output=True, text=True, env=e, timeout=60)
        try:
            o = json.loads(p.stdout)
        except ValueError:
            o = p.stdout
        if verbose:
            print("   $ display-layout %s -> %d %s %s" % (" ".join(args), p.returncode, p.stdout.strip()[:300], p.stderr.strip()[:300]))
        return p.returncode, o

    def current(self):
        return self.run("current")[1]

    def layout(self, edit=None, name="edit.json"):
        cur = self.current()
        lay = {"primary": "", "monitors": [{k: m[k] for k in ("description", "mode", "x", "y", "scale", "transform")}
                                           for m in cur["monitors"] if not m["disabled"]]}
        if edit:
            edit(lay["monitors"])
        path = os.path.join(self.d, name)
        json.dump(lay, open(path, "w"))
        return path

    def calls(self):
        return open(self.log).read().splitlines() if os.path.exists(self.log) else []

    def evals(self):
        return [c[len("eval | "):] for c in self.calls() if c.startswith("eval | ")]

    def clear(self):
        if os.path.exists(self.log):
            os.unlink(self.log)

    def state(self):
        return json.load(open(self.mon))

    def by(self, desc_part, mons=None):
        return next(m for m in (mons or self.state()) if desc_part in m["description"])

    def rollback(self):
        return os.path.join(self.d, "run", "display-layout", "rollback.json")

    def presenting(self, on=True):
        p = os.path.join(self.d, "run", "presenting")
        if on:
            open(p, "w").close()
        elif os.path.exists(p):
            os.unlink(p)


def find(mons, part):
    return next(m for m in mons if part in m["description"])


def stub_fields():
    try:
        s = open("/usr/share/hypr/stubs/hl.meta.lua").read()
    except OSError:
        return None
    m = re.search(r"---@class HL\.MonitorSpec\n((?:---@field .*\n)+)", s)
    return set(re.findall(r"---@field (\w+)\??", m.group(1))) if m else None


def lua_ok(text, where):
    """Syntax with luac -p (or lua -e), then each hl.monitor's fields against the stub."""
    path = os.path.join(work, "check-%d.lua" % time.time_ns())
    open(path, "w").write(text)
    luac = shutil.which("luac")
    if luac:
        p = subprocess.run([luac, "-p", path], capture_output=True, text=True)
        check(where + ": luac -p", p.returncode == 0, p.stderr.strip())
    elif shutil.which("lua"):
        p = subprocess.run(["lua", "-e", "assert(loadfile(%r))" % path], capture_output=True, text=True)
        check(where + ": lua loadfile", p.returncode == 0, p.stderr.strip())
    calls = re.findall(r"^hl\.monitor\(\{ (.*) \}\)", text, re.M)
    fields = stub_fields()
    for c in calls:
        keys = re.findall(r'(\w+) = (?:"(?:[^"\\]|\\.)*"|[-0-9.]+)', c)
        rebuilt = ", ".join(re.findall(r'\w+ = (?:"(?:[^"\\]|\\.)*"|[-0-9.]+)', c))
        if rebuilt != c:
            check(where + ": hl.monitor is plain key = value", False, c)
        if fields is not None:
            bad = [k for k in keys if k not in fields]
            if bad:
                check(where + ": fields are in HL.MonitorSpec", False, bad)
        if "disabled" in keys or "mirror" in keys:
            check(where + ": never disabled or mirror", False, c)
    check(where + ": %d hl.monitor lines, fields in the stub%s" % (len(calls), "" if fields is not None else " (stub not found: regex only)"), len(calls) > 0)
    return calls


def show(label, lines):
    for l in lines:
        print("SENT %s: hyprctl eval '%s'" % (label, l))


# ---------------------------------------------------------------- (a) laptop only
print("case: (a) laptop only")
e = Env("laptop")
code, cur = e.run("current")
ms = cur["monitors"]
check("one monitor", code == 0 and len(ms) == 1, ms)
lap = ms[0]
check("laptop keyed by its name eDP-1", lap["output"] == "eDP-1", lap["output"])
check("live mode keeps its exact refresh", lap["mode"] == "1920x1080@60.049", lap["mode"])
check("the other mode is offered", "1920x1080@48.04" in lap["modes"] and len(lap["modes"]) == 2, lap["modes"])
check("scales whole-pixel only", lap["scales"][lap["mode"]][:5] == [1.0, 1.2, 1.25, 1.333333, 1.5], lap["scales"][lap["mode"]])
check("focused, workspace known", lap["focused"] and lap["workspace"] == 11)
code, v = e.run("validate", e.layout())
check("laptop alone validates", code == 0 and v["ok"], v)
code, lua = e.run("lua", e.layout())
calls = lua_ok(lua, "laptop lua")
check("one rule, as hyprland.lua writes it", calls == ['output = "eDP-1", mode = "1920x1080@60.049", position = "6440x840", scale = 1, transform = 0'], calls)
code, o = e.run("apply", e.layout(lambda ms: ms[0].update(scale=1.25)))
check("apply the laptop's scale: one eval", code == 0 and len(e.evals()) == 1 and "scale = 1.25" in e.evals()[0], e.evals())
show("laptop scale 1.25", e.evals())
e.clear()
code, o = e.run("revert")
check("revert: one eval back to scale 1", code == 0 and e.evals() == ['hl.monitor({ output = "eDP-1", mode = "1920x1080@60.049", position = "6440x840", scale = 1, transform = 0 })'], e.evals())
show("laptop revert", e.evals())

# ---------------------------------------------------------------- (b) the four-screen desk
print("case: (b) the four-screen desk")
e = Env("desk")
code, cur = e.run("current")
ms = cur["monitors"]
check("four monitors, left to right", [m["label"] for m in ms] == ["DELL P2425HE", "DELL P2214H", "S34J55x", "Laptop"], [m["label"] for m in ms])
check("desk monitors keyed by desc:", all(m["output"].startswith("desc:") for m in ms[:3]) and ms[3]["output"] == "eDP-1", [m["output"] for m in ms])
p = find(ms, "P2214H")
check("portrait Dell: transform 1, logical 1080x1920", p["transform"] == 1 and (p["logicalWidth"], p["logicalHeight"]) == (1080, 1920), p)
s = find(ms, "S34J55x")
check("Samsung mode exact (59.973), its modes listed", s["mode"] == "3440x1440@59.973" and "2560x1440@59.95" in s["modes"], s["modes"])
check("Samsung scales", s["scales"][s["mode"]] == [1.0, 1.25, 1.333333, 1.6, 1.666667, 2.0, 2.5], s["scales"][s["mode"]])
check("focused one marked", [m["focused"] for m in ms] == [False, False, True, False])
code, v = e.run("validate", e.layout())
check("desk as it is validates, no warnings", code == 0 and v["ok"] and not v["warnings"], v)
code, lua = e.run("lua", e.layout())
calls = lua_ok(lua, "desk lua")
want = ['output = "desc:Dell Inc. DELL P2425HE 8BY1H14", mode = "1920x1080@60", position = "0x840", scale = 1, transform = 0',
        'output = "desc:Dell Inc. DELL P2214H KW14V59N39RB", mode = "1920x1080@60", position = "1920x0", scale = 1, transform = 1',
        'output = "desc:Samsung Electric Company S34J55x H4LR305255", mode = "3440x1440@59.973", position = "3000x480", scale = 1, transform = 0',
        'output = "eDP-1", mode = "1920x1080@60.049", position = "6440x840", scale = 1, transform = 0']
check("desk lua = the rules in hyprland.lua, same order", calls == want, calls)
check("lua sets DisplayLayout.rules for the laptop table", 'DisplayLayout.rules["eDP-1"] = { mode = "1920x1080@60.049", position = "6440x840", scale = 1, transform = 0 }' in lua)

print("case: validation")
cases = [
    ("overlap", lambda ms: find(ms, "AU Opt").update(x=6000), "overlap"),
    ("gap strands a screen", lambda ms: find(ms, "AU Opt").update(x=6500), "does not touch"),
    ("corner only is a gap", lambda ms: find(ms, "AU Opt").update(x=6440, y=1920), "does not touch"),
    ("bad mode", lambda ms: find(ms, "P2425HE").update(mode="1920x1080@144"), "not one this monitor offers"),
    ("not a mode", lambda ms: find(ms, "P2425HE").update(mode="big"), "WIDTHxHEIGHT"),
    ("off the pixel grid", lambda ms: find(ms, "AU Opt").update(y=840.5), "logical pixel grid"),
    ("transform out of range", lambda ms: find(ms, "AU Opt").update(transform=9), "transform"),
    ("listed twice", lambda ms: ms.append(dict(ms[0])), "twice"),
]
for name, f, word in cases:
    code, v = e.run("validate", e.layout(f))
    check("refused: " + name, code == 1 and not v["ok"] and any(word in x for x in v["errors"]), v)
code, v = e.run("validate", e.layout(lambda ms: find(ms, "AU Opt").update(scale=1.3, x=6440)))
check("fractional scale: a warning naming good ones", code == 0 and any("1.3" in w and "1.25" in w for w in v["warnings"]), v)
code, v = e.run("validate", e.layout(lambda ms: find(ms, "AU Opt").update(y=1900)))
check("a sliver of shared edge: a warning", code == 0 and any("less than 64" in w for w in v["warnings"]), v)
code, v = e.run("validate", e.layout(lambda ms: ms.pop()))      # the laptop left out: still counted where it is
check("a screen left out still takes its room", code == 0 and v["ok"], v)
code, v = e.run("validate", e.layout(lambda ms: (ms.pop(), find(ms, "S34J55x").update(x=4000))))
check("...and is stranded by a move of another", code == 1 and any("Laptop" in x for x in v["errors"]), v)

print("case: apply / keep / revert (desk)")
orig = e.state()
e.clear()
code, o = e.run("apply", e.layout(lambda ms: find(ms, "AU Opt").update(y=860)))
ev = e.evals()
check("apply: exactly one eval, for the laptop", code == 0 and len(ev) == 1 and 'output = "eDP-1"' in ev[0], ev)
check("apply: position, scale, transform, mode only", ev and re.findall(r"(\w+) = ", ev[0]) == ["output", "mode", "position", "scale", "transform"], ev)
check("apply: no disabled, mirror, reload, dispatch", not any(re.search(r"disabled|mirror|reload|dispatch|keyword|output create", c) for c in e.calls()), e.calls())
check("apply: only reads and evals reach hyprctl", all(c.startswith("eval | ") or c.startswith("-j | monitors") for c in e.calls()), e.calls())
show("move the laptop 20 px down", ev)
check("rollback written first, with the instance", os.path.exists(e.rollback()) and json.load(open(e.rollback()))["instance"] == "test-instance")
check("live state changed", e.by("AU Opt")["y"] == 860)
check("other monitors untouched", [m for m in e.state() if "AU Opt" not in m["description"]] == [m for m in orig if "AU Opt" not in m["description"]])
e.clear()
code, o = e.run("apply", e.layout(lambda ms: (find(ms, "AU Opt").update(y=880), find(ms, "S34J55x").update(mode="2560x1440@59.95"),
                                                 find(ms, "AU Opt").update(x=5560))))
ev = e.evals()
check("second apply: two evals (Samsung, laptop), the Dells untouched", code == 0 and len(ev) == 2 and "S34J55x" in ev[0] and "eDP-1" in ev[1], ev)
show("Samsung to 2560x1440 + laptop follows", ev)
e.clear()
code, o = e.run("revert", HYPRLAND_INSTANCE_SIGNATURE=None)          # as from a TTY: no instance in the environment
ev = e.evals()
check("revert goes back to before the FIRST apply", code == 0 and e.state() == orig, [(m["name"], m["x"], m["y"], m["width"]) for m in e.state()])
check("revert: only the two that differ", len(ev) == 2 and not any("DELL" in x for x in ev), ev)
check("revert from a TTY reaches the instance in the rollback", set(open(e.log + ".instance").read().split()) == {"test-instance"})
show("revert", ev)
check("rollback gone after revert", not os.path.exists(e.rollback()))
e.clear()
code, o = e.run("apply", e.layout())
check("unchanged layout: nothing sent, no rollback", code == 0 and o["sent"] == [] and not e.evals() and not os.path.exists(e.rollback()), o)
code, o = e.run("apply", e.layout(lambda ms: find(ms, "AU Opt").update(y=860)))
code, k = e.run("keep")
check("keep drops the rollback", code == 0 and k["kept"] and not os.path.exists(e.rollback()))
e.clear()
code, r = e.run("revert")
check("revert after keep: nothing", code == 0 and r["sent"] == [] and not e.evals(), r)

print("case: refusals")
e = Env("desk")
e.presenting(True)
code, o = e.run("apply", e.layout(lambda ms: find(ms, "AU Opt").update(y=860)))
check("refused while presenting, nothing sent", code == 1 and "presenting" in o["error"] and not e.evals() and not os.path.exists(e.rollback()), o)
e.presenting(False)
code, o = e.run("apply", e.layout(lambda ms: ms.append({"description": "Seiko Epson Corporation EPSON PJ", "mode": "1920x1200@60", "x": 8360, "y": 840, "scale": 1, "transform": 0})))
check("refused: a monitor in the file is not connected", code == 1 and "not connected" in o["error"] and not e.evals(), o)
code, o = e.run("apply", e.layout(lambda ms: find(ms, "AU Opt").update(x=6000)))
check("refused: overlap", code == 1 and "overlap" in o["error"] and not e.evals(), o)
st = e.state(); find(st, "AU Opt")["disabled"] = True; json.dump(st, open(e.mon, "w"))
lay = e.layout(); l2 = json.load(open(lay))
l2["monitors"].append({"description": "AU Optronics 0x683D", "mode": "1920x1080@60.049", "x": 6440, "y": 900, "scale": 1, "transform": 0})
json.dump(l2, open(lay, "w"))
code, o = e.run("apply", lay)
check("refused: a screen that is off is never turned on", code == 1 and "is off" in o["error"] and not e.evals(), o)
e = Env("projector")
st = e.state(); st[1]["mirrorOf"] = "eDP-1"; json.dump(st, open(e.mon, "w"))
code, o = e.run("apply", e.layout(lambda ms: ms[0].update(y=900)))
check("refused while a screen mirrors", code == 1 and "mirrors" in o["error"] and not e.evals(), o)
e = Env("desk")
st = e.state(); st[1]["activeWorkspace"] = {"id": -1, "name": ""}; json.dump(st, open(e.mon, "w"))
code, o = e.run("apply", e.layout(lambda ms: find(ms, "AU Opt").update(y=860)))
check("refused while a screen has no workspace", code == 1 and "no workspace" in o["error"] and not e.evals(), o)
e = Env("desk", FAKE_FAIL="eval2")
code, o = e.run("apply", e.layout(lambda ms: (find(ms, "S34J55x").update(y=500), find(ms, "AU Opt").update(y=860))))
ev = e.evals()
check("an eval fails part-way: the ones sent are put back", code == 1 and len(ev) == 3 and "3000x500" in ev[0] and "3000x480" in ev[2] and e.by("S34J55x")["y"] == 480, ev)

print("case: (c) projector attached")
e = Env("projector")
code, cur = e.run("current")
ms = cur["monitors"]
pj = find(ms, "EPSON")
check("projector keyed by desc:", pj["output"] == "desc:Seiko Epson Corporation EPSON PJ" and pj["mode"] == "1920x1200@60", pj)
code, v = e.run("validate", e.layout())
check("laptop + projector at 8360x840 validates", code == 0 and v["ok"], v)
code, lua = e.run("lua", e.layout())
lua_ok(lua, "projector lua")
code, o = e.run("apply", e.layout(lambda ms: find(ms, "EPSON").update(mode="1280x800@60", scale=1)))
check("projector mode change: one eval", code == 0 and len(e.evals()) == 1 and "1280x800@60" in e.evals()[0], e.evals())
show("projector to 1280x800", e.evals())
e.run("revert")

print("case: watchdog")
e = Env("desk", DISPLAY_LAYOUT_WATCHDOG="1")
code, o = e.run("apply", e.layout(lambda ms: find(ms, "AU Opt").update(y=860)))
check("watchdog started", code == 0 and o.get("watchdog"), o)
time.sleep(2.5)
check("nobody answered: reverted by itself", e.by("AU Opt")["y"] == 840 and not os.path.exists(e.rollback()), e.by("AU Opt")["y"])
e = Env("desk", DISPLAY_LAYOUT_WATCHDOG="1.5")
e.run("apply", e.layout(lambda ms: find(ms, "AU Opt").update(y=860)))
e.run("keep")
time.sleep(2.5)
check("kept: the watchdog leaves it", e.by("AU Opt")["y"] == 860)

print("case: save")
e = Env("desk", DISPLAY_LAYOUT_VERIFY=os.environ.get("DISPLAYS_TEST_VERIFY", "1"))
json.dump({"version": 1, "primary": "", "mine": 1, "monitors": [{"description": "Seiko Epson Corporation EPSON PJ", "output": "desc:Seiko Epson Corporation EPSON PJ",
                                                     "label": "EPSON PJ", "mode": "1920x1200@60", "x": 8360, "y": 840, "scale": 1, "transform": 0}]},
          open(e.env["DISPLAY_LAYOUT_SAVED"], "w"))
lay = e.layout(lambda ms: find(ms, "AU Opt").update(y=860))
l2 = json.load(open(lay)); l2["primary"] = "AU Optronics 0x683D"; json.dump(l2, open(lay, "w"))
code, o = e.run("save", lay)
check("save writes both files", code == 0 and o["ok"] and os.path.exists(e.env["DISPLAY_LAYOUT_LUA"]), o)
check("checked by " + str(o.get("checked") if isinstance(o, dict) else "?"), isinstance(o, dict) and o.get("checked") in ("Hyprland", "luac", "none"))
lua = open(e.env["DISPLAY_LAYOUT_LUA"]).read()
calls = lua_ok(lua, "saved monitors.lua")
check("saved lua: 5 rules (4 desk + the projector kept from before)", len(calls) == 5 and any("EPSON" in c for c in calls), calls)
check("saved lua: the new laptop position", 'output = "eDP-1", mode = "1920x1080@60.049", position = "6440x860"' in lua)
check("saved lua: primary", 'DisplayLayout = { primary = "eDP-1", rules = {} }' in lua)
js = json.load(open(e.env["DISPLAY_LAYOUT_SAVED"]))
check("displays.json keeps unknown keys and the projector", js.get("mine") == 1 and len(js["monitors"]) == 5 and js["primary"] == "AU Optronics 0x683D", js)
check("save never talks to Hyprland", not e.evals())
before = lua
code, o = e.run("save", e.layout(lambda ms: find(ms, "AU Opt").update(x=6000)))
check("save refuses an invalid layout, files untouched", code == 1 and open(e.env["DISPLAY_LAYOUT_LUA"]).read() == before, o)
code, o = e.run("save", e.layout())
check("second save keeps a .bak", code == 0 and os.path.exists(e.env["DISPLAY_LAYOUT_LUA"] + ".bak"))
if shutil.which("Hyprland") and os.environ.get("DISPLAYS_TEST_VERIFY", "1") != "0":
    bad = os.path.join(e.d, "bad.lua")
    open(bad, "w").write('hl.monitor({ output = "x", bogus = 1 })\n')
    sys.path.insert(0, os.path.dirname(tool))
    env = dict(e.env, DISPLAY_LAYOUT_VERIFY="1")
    p = subprocess.run([sys.executable, "-B", "-c", "import importlib.machinery, sys; m = importlib.machinery.SourceFileLoader('dl', sys.argv[1]).load_module(); "
                        "\ntry:\n    m.check_lua(sys.argv[2]); print('accepted')\nexcept m.Refused as x:\n    print('refused', x)", tool, bad],
                       capture_output=True, text=True, env=env)
    check("Hyprland --verify-config catches a bad field", p.stdout.startswith("refused") and "bogus" in p.stdout, p.stdout + p.stderr)

print("RESULT pass %d fail %d" % (passed, failed))
sys.exit(1 if failed else 0)
