#!/usr/bin/env python3
"""Tests for bin/input-settings with the fake hyprctl (usage: cli_test.py INPUT_SETTINGS TESTS_DIR).
Prints ITEST PASS/FAIL lines and a final 'ITEST RESULT pass N fail M'."""
import json, os, re, subprocess, sys, tempfile, shutil

BIN, TESTS = sys.argv[1], sys.argv[2]
passed = failed = 0


def check(what, ok, detail=""):
    global passed, failed
    if ok: passed += 1
    else: failed += 1
    print("ITEST %s %s%s" % ("PASS" if ok else "FAIL", what, "" if ok or detail == "" else "   [%s]" % detail))


class Env:
    def __init__(self):
        self.d = tempfile.mkdtemp()
        self.env = dict(os.environ, FAKE_STATE=self.d, FAKE_FIXTURES=os.path.join(TESTS, "fixtures"),
                        HYPRCTL=os.path.join(TESTS, "hyprctl"), INPUT_SETTINGS_FILE=os.path.join(self.d, "cfg", "input.json"))
    def run(self, *a, **kw):
        env = dict(self.env, **kw)
        r = subprocess.run([BIN, *a], capture_output=True, text=True, env=env)
        return r.returncode, r.stdout, r.stderr
    def evals(self):
        try: return open(os.path.join(self.d, "evals")).read().splitlines()
        except FileNotFoundError: return []
    def saved(self):
        try: return json.load(open(self.env["INPUT_SETTINGS_FILE"]))
        except FileNotFoundError: return None
    def opts(self): return json.load(open(os.path.join(self.d, "opts.json")))


# ---- get parses real getoption captures ----
e = Env()
rc, out, err = e.run("get")
g = json.loads(out)
v = g["values"]
check("get exits 0 and is JSON", rc == 0 and "values" in g, err)
check("get: int option (repeat_rate 25, repeat_delay 600)", v["repeat_rate"] == 25 and v["repeat_delay"] == 600)
check("get: float option (sensitivity 0.0, scroll_factor 1.0)", v["sensitivity"] == 0.0 and v["scroll_factor"] == 1.0)
check("get: bool option (touchpad natural scroll true, numlock false)", v["touchpad.natural_scroll"] is True and v["numlock_by_default"] is False)
check("get: [[EMPTY]] accel profile reads adaptive", v["accel_profile"] == "adaptive")
check("get: kb_variant 'dvorak,' reads first layout dvorak", v["first_layout"] == "dvorak")
check("get: follow_mouse int", v["follow_mouse"] == 1)
check("get: every supported key present", all(k in v for k in json.loads(e.run("keys")[1])), str(sorted(v)))
names = [(d["name"], d["kind"]) for d in g["devices"]]
check("get: devices keep Hyprland's names", ("at-translated-set-2-keyboard", "keyboard") in names, str(names))
check("get: touchpad and its -mouse twin are both touchpads", ("elan0412:00-04f3:311d-touchpad", "touchpad") in names and ("elan0412:00-04f3:311d-mouse", "touchpad") in names)
check("get: buttons flagged system", [d.get("system") for d in g["devices"] if d["name"] == "power-button"] == [True] and [d.get("system") for d in g["devices"] if d["name"] == "at-translated-set-2-keyboard"] == [False])
check("get changes nothing", e.evals() == [] and e.saved() is None)
check("layout key is read-only text", g["layoutKey"] == "Super+Space")

# ---- set: validation, exact eval, record ----
cases = [
    ("sensitivity", "0.3", "hl.config({ input = { sensitivity = 0.3 } })", 0.3),
    ("accel_profile", "flat", 'hl.config({ input = { accel_profile = "flat" } })', "flat"),
    ("natural_scroll", "on", "hl.config({ input = { natural_scroll = true } })", True),
    ("scroll_factor", "2.5", "hl.config({ input = { scroll_factor = 2.5 } })", 2.5),
    ("follow_mouse", "2", "hl.config({ input = { follow_mouse = 2 } })", 2),
    ("repeat_rate", "40", "hl.config({ input = { repeat_rate = 40 } })", 40),
    ("repeat_delay", "300", "hl.config({ input = { repeat_delay = 300 } })", 300),
    ("numlock_by_default", "true", "hl.config({ input = { numlock_by_default = true } })", True),
    ("first_layout", "us", 'hl.config({ input = { kb_variant = ",dvorak" } })', "us"),
    ("touchpad.natural_scroll", "false", "hl.config({ input = { touchpad = { natural_scroll = false } } })", False),
    ("touchpad.scroll_factor", "0.5", "hl.config({ input = { touchpad = { scroll_factor = 0.5 } } })", 0.5),
    ("touchpad.tap_to_click", "0", "hl.config({ input = { touchpad = { tap_to_click = false } } })", False),
    ("touchpad.tap_and_drag", "no", "hl.config({ input = { touchpad = { tap_and_drag = false } } })", False),
    ("touchpad.disable_while_typing", "off", "hl.config({ input = { touchpad = { disable_while_typing = false } } })", False),
    ("touchpad.middle_button_emulation", "yes", "hl.config({ input = { touchpad = { middle_button_emulation = true } } })", True),
    ("touchpad.clickfinger_behavior", "1", "hl.config({ input = { touchpad = { clickfinger_behavior = true } } })", True),
]
e = Env()
for key, val, want, rec in cases:
    n = len(e.evals())
    rc, out, err = e.run("set", key, val)
    ev = e.evals()
    check("set %s %s: one eval, exact" % (key, val), rc == 0 and len(ev) == n + 1 and ev[-1] == want, "%s | %s" % (ev[-1:] , err))
    check("set %s recorded" % key, e.saved()["overrides"][key] == rec, str(e.saved()))
check("live table follows the evals (fake)", e.opts()["input:touchpad:tap_to_click"] is False and e.opts()["input:repeat_rate"] == 40)
rc, out, err = e.run("get")
check("get after set: shows new values and the saved list", json.loads(out)["values"]["first_layout"] == "us" and json.loads(out)["saved"]["repeat_rate"] == 40)

# ---- bad keys and values refused, nothing evaluated or recorded ----
e = Env()
bad = [("nope", "1"), ("sensitivity", "1.5"), ("sensitivity", "abc"), ("sensitivity", "nan"), ("repeat_rate", "0"), ("repeat_rate", "101"),
       ("repeat_rate", "2.5"), ("repeat_delay", "50"), ("accel_profile", "custom"), ("touchpad.tap_to_click", "maybe"),
       ("follow_mouse", "4"), ("first_layout", "qwerty"), ("scroll_factor", "0"), ("scroll_factor", "11"),
       ("device::sensitivity", "0"), ("device:x:speed", "1"), ("device:a b:sensitivity", "0"), ("device:x:sensitivity", "2"),
       ("device:x:layout", "colemak"), ("input.sensitivity", "0"), ("sensitivity", "0'); os.exit() --")]
for k, v in bad:
    rc, out, err = e.run("set", k, v)
    check("refused: set %s %s" % (k, v), rc == 1 and err.startswith("input-settings:"), "%d %s" % (rc, err))
check("nothing evaluated or saved by refusals", e.evals() == [] and e.saved() is None)
check("set with a missing value is a usage error", e.run("set", "sensitivity")[0] == 2)
check("unknown command is a usage error", e.run("explode")[0] == 2)
rc, out, err = e.run("set", "sensitivity", "0.1", FAKE_STATE=e.d)
os.makedirs(e.d, exist_ok=True); open(os.path.join(e.d, "fail"), "w").write("x")
rc, out, err = e.run("set", "repeat_rate", "50")
check("hyprctl failure: exit 1, message, not recorded", rc == 1 and "failed" in err and "repeat_rate" not in e.saved()["overrides"], err)
os.remove(os.path.join(e.d, "fail"))
rc, out, err = e.run("set", "repeat_rate", "50", HYPRCTL="/nonexistent/hyprctl")
check("no hyprctl at all: clean error", rc == 1 and "hyprctl" in err, err)

# ---- devices ----
e = Env()
mn = "zsa-technology-labs-moonlander-mark-i-keyboard"
rc, out, err = e.run("set", "device:%s:layout" % mn, "dvorak")
check("device layout eval", e.evals()[-1:] == ['hl.device({ name = "%s", kb_layout = "us", kb_variant = "dvorak", kb_options = "caps:ctrl_modifier" })' % mn], str(e.evals()))
rc, out, err = e.run("set", "device:elan0412:00-04f3:311d-mouse:sensitivity", "-0.4")
check("device name with colons parsed from the right", e.evals()[-1] == 'hl.device({ name = "elan0412:00-04f3:311d-mouse", sensitivity = -0.4 })', e.evals()[-1])
check("device recorded under devices", e.saved()["devices"][mn] == {"layout": "dvorak"} and e.saved()["devices"]["elan0412:00-04f3:311d-mouse"] == {"sensitivity": -0.4})
rc, out, err = e.run("set", "device:%s:sensitivity" % mn, "0.2")
check("both fields of one device go in one hl.device on apply", 'name = "%s", sensitivity = 0.2, kb_layout = "us"' % mn in e.run("lua")[1])

# ---- lua and apply ----
e = Env()
check("lua with nothing saved prints nothing, apply evals nothing", e.run("lua")[1] == "" and e.run("apply")[0] == 0 and e.evals() == [])
e.run("set", "touchpad.tap_to_click", "false"); e.run("set", "sensitivity", "0.3"); e.run("set", "first_layout", "us"); e.run("set", "repeat_rate", "35")
e.run("set", "device:kens:sensitivity", "-0.2")
lua = e.run("lua")[1].strip()
want = 'hl.config({ input = { sensitivity = 0.3, repeat_rate = 35, kb_variant = ",dvorak", touchpad = { tap_to_click = false } } }); hl.device({ name = "kens", sensitivity = -0.2 })'
check("lua: everything saved, one line", lua == want, lua)
n = len(e.evals())
rc = e.run("apply")[0]
check("apply: ONE eval carrying everything", rc == 0 and len(e.evals()) == n + 1 and e.evals()[-1] == lua, e.evals()[-1])
# the Lua uses only option names the Hyprland stub knows
stub = open("/usr/share/hypr/stubs/hl.meta.lua").read() if os.path.exists("/usr/share/hypr/stubs/hl.meta.lua") else ""
if stub:
    known_cfg = set(re.findall(r'---\| "input\.([a-z_0-9.]+)"', stub))
    dev = re.search(r"---@class HL\.DeviceSpec(.*?)local __HL_DeviceSpec", stub, re.S).group(1)
    known_dev = set(re.findall(r"---@field (\w+)\??[ :]", dev))
    for k in json.loads(e.run("keys")[1]):
        pass
    allsaved = Env()
    for key, val, *_ in cases: allsaved.run("set", key, val)
    for name, field in (("sensitivity", "0.1"), ("layout", "dvorak")): allsaved.run("set", "device:d:" + name, field)
    s = allsaved.run("lua")[1]
    cfg = re.search(r"hl\.config\(\{ input = (.*?) \}\); hl\.device", s).group(1) + " }"
    flat = []
    def walk(t, pre):
        for m in re.finditer(r"(\w+) = (\{|[^,}]+)", t):
            pass
    # names: every identifier before '=' inside the input table, with nesting from the braces
    path, names_seen = [], set()
    for tok in re.finditer(r"(\w+) = \{|(\w+) = |\}", cfg):
        if tok.group(1): path.append(tok.group(1))
        elif tok.group(2): names_seen.add(".".join(path[:] + [tok.group(2)]))
        else:
            if path: path.pop()
    bad = [n for n in names_seen if n not in known_cfg]
    check("lua: every generated input option exists in the Hyprland stub", not bad and len(names_seen) >= 15, "unknown %s / %d names" % (bad, len(names_seen)))
    dfields = set(re.findall(r"(\w+) = ", re.search(r"hl\.device\(\{ (.*?) \}\)", s).group(1)))
    check("lua: every hl.device field exists in the stub's DeviceSpec", dfields <= known_dev and "name" in dfields, str(dfields - known_dev))
else:
    check("stub present for the name check (skipped: no /usr/share/hypr/stubs)", True)

# ---- reset ----
e = Env()
e.run("set", "repeat_rate", "40"); e.run("set", "touchpad.tap_to_click", "false"); e.run("set", "device:kens:sensitivity", "0.5")
rc, out, err = e.run("reset", "repeat_rate")
check("reset KEY applies the hyprland.lua value and forgets it", e.evals()[-1] == "hl.config({ input = { repeat_rate = 25 } })" and "repeat_rate" not in e.saved()["overrides"], e.evals()[-1])
check("reset KEY keeps the others", e.saved()["overrides"] == {"touchpad.tap_to_click": False})
rc, out, err = e.run("reset", "device:kens:sensitivity")
check("reset device field", e.evals()[-1] == 'hl.device({ name = "kens", sensitivity = 0.0 })' and e.saved()["devices"] == {}, e.evals()[-1])
e.run("set", "device:kens:sensitivity", "0.5")
n = len(e.evals())
rc, out, err = e.run("reset", "all")
check("reset all: one eval, defaults for every saved key", rc == 0 and len(e.evals()) == n + 1 and e.evals()[-1] == 'hl.config({ input = { touchpad = { tap_to_click = true } } }); hl.device({ name = "kens", sensitivity = 0.0 })', e.evals()[-1])
check("reset all empties the file's overrides and devices", e.saved()["overrides"] == {} and e.saved()["devices"] == {})
n = len(e.evals()); e.run("reset", "all")
check("reset all with nothing saved evals nothing", len(e.evals()) == n)
check("reset of an unknown key refused", e.run("reset", "bogus")[0] == 1)

# ---- the file ----
e = Env()
os.makedirs(os.path.dirname(e.env["INPUT_SETTINGS_FILE"]))
open(e.env["INPUT_SETTINGS_FILE"], "w").write('{"note": "mine", "overrides": {"repeat_rate": 33, "bogus": 1}}')
e.run("set", "repeat_delay", "500")
s = e.saved()
check("unknown top-level keys kept, other overrides kept", s["note"] == "mine" and s["overrides"]["repeat_rate"] == 33 and s["overrides"]["repeat_delay"] == 500)
check("apply skips unknown saved keys", "bogus" not in e.run("lua")[1] and "repeat_rate = 33" in e.run("lua")[1])
open(e.env["INPUT_SETTINGS_FILE"], "w").write("{not json")
rc, out, err = e.run("set", "repeat_rate", "40")
check("a broken file is never overwritten", rc == 1 and open(e.env["INPUT_SETTINGS_FILE"]).read() == "{not json", err)

print("ITEST RESULT pass %d fail %d" % (passed, failed))
sys.exit(1 if failed else 0)
