#!/usr/bin/env python3
"""Tests for session-save, session-restore and session_lib: canned `hyprctl -j clients|monitors` JSON,
a fake hyprctl and a fake uwsm on PATH (they only record), a fake applications dir, a fake /proc.
Nothing real is read, nothing is started. Usage: script-test.py BIN_DIR"""
import json, os, shutil, subprocess, sys, tempfile

BIN = sys.argv[1]
passed = failed = 0
def check(what, ok, detail=""):
    global passed, failed
    if ok: passed += 1
    else: failed += 1
    print("SESSIONTEST %s %s%s" % ("PASS" if ok else "FAIL", what, "" if ok or detail == "" else "   [%s]" % (detail,)))
def case(name): print("SESSIONTEST case: " + name)

T = tempfile.mkdtemp(prefix="sesstest-")
FAKE = T + "/fake"; FB = T + "/fakebin"; APPS = T + "/apps"; PROC = T + "/proc"
STATE = T + "/state"; CONF = T + "/conf"; RT = T + "/rt"
for d in (FAKE, FB, APPS, PROC, STATE, CONF + "/shell", RT): os.makedirs(d)
SECRET = "SECRET-DOC-TITLE-Quarterly-Salaries"

open(FB + "/hyprctl", "w").write('''#!/usr/bin/env python3
import json, os, sys
F = os.environ["FAKE_DIR"]
a = sys.argv[1:]
if a[:1] == ["-j"] and a[1] in ("clients", "monitors"):
    sys.stdout.write(open(F + "/" + a[1] + ".json").read())
else:
    open(F + "/calls.log", "a").write("hyprctl " + " | ".join(a) + "\\n")
''')
open(FB + "/uwsm", "w").write('''#!/usr/bin/env python3
import json, os, sys
F = os.environ["FAKE_DIR"]
a = sys.argv[1:]
open(F + "/calls.log", "a").write("uwsm " + " ".join(a) + "\\n")
i = a.index("--")
prog = a[i + 1]
cls = "com.mitchellh.ghostty" if prog == "ghostty" else prog.replace(".desktop", "")
if os.path.exists(F + "/nospawn"): sys.exit(0)
cl = json.load(open(F + "/clients.json"))
n = len(cl) + 100
cl.append({"address": "0xnew%d" % n, "mapped": True, "class": cls, "title": "t", "pid": 9000 + n, "floating": False,
           "workspace": {"id": 11, "name": "11", "type": "normal"}, "monitor": 0, "size": [10, 10]})
json.dump(cl, open(F + "/clients.json", "w"))
''')
for f in ("hyprctl", "uwsm"): os.chmod(FB + "/" + f, 0o755)

def desktop(name, cls=None, disp=None):
    open(APPS + "/" + name + ".desktop", "w").write("[Desktop Entry]\nType=Application\nName=%s\nExec=x\n%s" % (disp or name, ("StartupWMClass=%s\n" % cls) if cls else ""))
desktop("firefox", disp="Firefox"); desktop("com.mitchellh.ghostty", "com.mitchellh.ghostty", "Ghostty")
desktop("org.gnome.Nautilus", None, "Files"); desktop("zathura", disp="Zathura")
desktop("some-launcher", "weird-class-name", "Odd")          # found through StartupWMClass, not the file name
desktop("emacs", disp="Emacs")

ENV = dict(os.environ, PATH=FB + ":" + os.environ["PATH"], FAKE_DIR=FAKE, SESSION_APP_DIRS=APPS, SESSION_PROC=PROC,
           XDG_STATE_HOME=STATE, XDG_CONFIG_HOME=CONF, XDG_RUNTIME_DIR=RT, SESSION_POLL_S="0.02", HOME=T)
def run(*a, env=None):
    return subprocess.run([sys.executable] + list(a), capture_output=True, text=True, env=dict(ENV, **(env or {})), timeout=60)
def save(*a, **k): return run(BIN + "/session-save", *a, **k)
def restore(*a, **k): return run(BIN + "/session-restore", *a, **k)
def setjson(name, data): json.dump(data, open(FAKE + "/" + name + ".json", "w"))
def calls(): return open(FAKE + "/calls.log").read().splitlines() if os.path.exists(FAKE + "/calls.log") else []
def clear_calls():
    if os.path.exists(FAKE + "/calls.log"): os.remove(FAKE + "/calls.log")
def last(): return json.load(open(STATE + "/session/last.json"))
def conf(d): json.dump(d, open(CONF + "/shell/session.json", "w"))

def cl(addr, cls, ws, mon=0, title="t", pid=1, floating=False, size=(800, 600), mapped=True, wtype="normal"):
    return {"address": addr, "mapped": mapped, "class": cls, "title": title, "pid": pid, "floating": floating, "size": list(size),
            "monitor": mon, "workspace": {"id": ws, "name": str(ws) if ws > 0 else "special:x", "type": wtype}}

# fake /proc: ghostty 100 has one shell (101) in /home/p/proj; ghostty 200 two shells with different dirs; 300 two with the same
os.makedirs("/".join([T, "work", "proj"])); os.makedirs(T + "/work/other")
def fake_proc(pid, ppid, cwd=None):
    os.makedirs("%s/%d" % (PROC, pid), exist_ok=True)
    open("%s/%d/stat" % (PROC, pid), "w").write("%d (a b) S %d 1 1 0\n" % (pid, ppid))
    if cwd: os.symlink(cwd, "%s/%d/cwd" % (PROC, pid))
fake_proc(100, 1); fake_proc(101, 100, T + "/work/proj")
fake_proc(200, 1); fake_proc(201, 200, T + "/work/proj"); fake_proc(202, 200, T + "/work/other")
fake_proc(300, 1); fake_proc(301, 300, T + "/work/proj"); fake_proc(302, 300, T + "/work/proj")

# ---------------------------------------------------------------- save
case("save: what is kept and what is left out")
# two monitors listed right-to-left: ids 5 (x=1920) and 7 (x=0): slot 1 is the LEFT one, id 7
setjson("monitors", [{"id": 5, "name": "DP-9", "x": 1920, "y": 0}, {"id": 7, "name": "DP-2", "x": 0, "y": 840}])
setjson("clients", [
    cl("0x1", "firefox", 11, mon=7, title=SECRET),
    cl("0x2", "org.gnome.Nautilus", 22, mon=5, title="Home " + SECRET, floating=True, size=(900, 700)),
    cl("0x3", "com.mitchellh.ghostty", 31, mon=7, pid=100, title="ghostty " + SECRET),
    cl("0x4", "org.tsr.ncmpcpp", -99, mon=7, wtype="special"),
    cl("0x5", "zathura", 11, mon=7, title="Open File"),                       # file dialog by its title
    cl("0x6", "mystery-app", 11, mon=7),                                        # no .desktop file
    cl("0x7", "quickshell", 11, mon=7), cl("0x8", "zathura", 5, mon=7),         # helper; plain workspace 5
    cl("0x9", "zathura", 12, mon=5, mapped=False),
    cl("0xa", "weird-class-name", 12, mon=5),                                   # via StartupWMClass
    cl("0xb", "xdg-desktop-portal-gtk", 11, mon=7),
    cl("0xc", "Zathura", 41, mon=5, title="doc"),                               # class case differs from the file name
])
r = save("--print")
check("--print exits 0", r.returncode == 0, r.stderr)
doc = json.loads(r.stdout)
E = {(e["app"], e["desktop"], e["slot"]): e for e in doc["entries"]}
check("kept exactly the 5 real windows", len(doc["entries"]) == 5, json.dumps(doc["entries"]))
check("firefox on desktop 1 slot 1 (leftmost monitor is id 7)", ("firefox", 1, 1) in E)
check("nautilus on desktop 2 slot 2 (monitor id 5 is second by x)", ("org.gnome.Nautilus", 2, 2) in E)
check("floating window keeps its size", E[("org.gnome.Nautilus", 2, 2)].get("floating") and E[("org.gnome.Nautilus", 2, 2)].get("size") == [900, 700])
check("tiled window has no size", "size" not in E[("firefox", 1, 1)])
check("StartupWMClass resolves", ("some-launcher", 1, 2) in E)
check("class resolves case-insensitively to the file stem", ("zathura", 4, 2) in E)
check("special workspace, dialog, unknown, helper, plain workspace, unmapped, portal all left out",
      not any(e["app"] in ("mystery-app", "quickshell", "xdg-desktop-portal-gtk") for e in doc["entries"]) and len(doc["entries"]) == 5)
check("stderr says what was left out", "special" in r.stderr and "dialog" in r.stderr and "unknown" in r.stderr, r.stderr)
check("terminal with a single shell child saves its cwd", E[("com.mitchellh.ghostty", 3, 1)].get("cwd") == T + "/work/proj", json.dumps(E[("com.mitchellh.ghostty", 3, 1)]))
check("print wrote no file", not os.path.exists(STATE + "/session/last.json"))
check("titles not in --print output", SECRET not in r.stdout and "Open File" not in r.stdout)
check("monitor swap: same windows, monitors listed the other way round give the same slots",
      (setjson("monitors", [{"id": 7, "name": "DP-2", "x": 0, "y": 840}, {"id": 5, "name": "DP-9", "x": 1920, "y": 0}]) or True)
      and json.loads(save("--print").stdout)["entries"] == doc["entries"])
setjson("monitors", [{"id": 5, "name": "DP-9", "x": 0, "y": 0}, {"id": 7, "name": "DP-2", "x": 1920, "y": 0}])
d2 = json.loads(save("--print").stdout)
check("a different arrangement gives different slots (id 5 is now slot 1)", ("firefox", 1, 2) in {(e["app"], e["desktop"], e["slot"]) for e in d2["entries"]})
setjson("monitors", [{"id": 5, "name": "DP-9", "x": 1920, "y": 0}, {"id": 7, "name": "DP-2", "x": 0, "y": 840}])

case("save: terminal working directories")
def term(pid, extra=()):
    setjson("clients", [cl("0xt%d" % pid, "com.mitchellh.ghostty", 11, mon=7, pid=pid)] + list(extra))
term(200)
check("two shells with different cwds: unknown (null)", json.loads(save("--print").stdout)["entries"][0]["cwd"] is None)
term(300)
check("two shells with the same cwd: known", json.loads(save("--print").stdout)["entries"][0]["cwd"] == T + "/work/proj")
term(999)
check("no shell found: null", json.loads(save("--print").stdout)["entries"][0]["cwd"] is None)
setjson("clients", [cl("0xt1", "com.mitchellh.ghostty", 11, mon=7, pid=100), cl("0xt2", "com.mitchellh.ghostty", 12, mon=5, pid=100)])
e2 = json.loads(save("--print").stdout)["entries"]
check("two windows of one process: one entry each, cwd shared when unambiguous", len(e2) == 2 and all(e["cwd"] == T + "/work/proj" for e in e2))
setjson("clients", [cl("0x1", "firefox", 11, mon=7)])
check("non-terminals have no cwd key", "cwd" not in json.loads(save("--print").stdout)["entries"][0])

case("save: files")
setjson("clients", [cl("0x1", "firefox", 11, mon=7, title=SECRET), cl("0x2", "org.gnome.Nautilus", 22, mon=5, title=SECRET),
                    cl("0x3", "com.mitchellh.ghostty", 31, mon=7, pid=100, title=SECRET)])
r = save()
check("save writes last.json", r.returncode == 0 and len(last()["entries"]) == 3, r.stderr)
raw = open(STATE + "/session/last.json").read()
check("titles never reach the file", SECRET not in raw and "title" not in raw and "address" not in raw and "pid" not in raw)
check("no prev.json the first time", not os.path.exists(STATE + "/session/prev.json"))
stamp = last()["saved"]
r = save()
check("unchanged session: file untouched", last()["saved"] == stamp and not os.path.exists(STATE + "/session/prev.json"))
setjson("clients", [cl("0x1", "firefox", 11, mon=7), cl("0x2", "org.gnome.Nautilus", 22, mon=5)])
save()
check("a change keeps the previous file as prev.json", len(json.load(open(STATE + "/session/prev.json"))["entries"]) == 3 and len(last()["entries"]) == 2)
setjson("clients", [cl("0x4", "org.tsr.ncmpcpp", -99, wtype="special")])
r = save()
check("an empty result does not replace a saved session", len(last()["entries"]) == 2 and "kept" in r.stderr)
save("--force")
check("--force does", last()["entries"] == [])
setjson("clients", [cl("0x1", "firefox", 11, mon=7)])
r = subprocess.run([sys.executable, BIN + "/session-save"], env=dict(ENV, PATH="/nonexistent:" + os.path.dirname(sys.executable)), capture_output=True, text=True)
check("no hyprctl: fails, file kept", r.returncode == 1 and last()["entries"] == [])
conf({"enabled": False})
os.remove(STATE + "/session/last.json")
save("--if-enabled")
check("--if-enabled does nothing while disabled", not os.path.exists(STATE + "/session/last.json"))
conf({"enabled": True})
save("--if-enabled")
check("--if-enabled saves when enabled", os.path.exists(STATE + "/session/last.json"))

# ---------------------------------------------------------------- restore
case("restore --list / skip lists / already running")
os.remove(CONF + "/shell/session.json")
saved = [
    {"app": "firefox", "class": "firefox", "desktop": 1, "slot": 1, "floating": False},
    {"app": "emacs", "class": "emacs", "desktop": 1, "slot": 2, "floating": False},
    {"app": "org.gnome.Nautilus", "class": "org.gnome.Nautilus", "desktop": 2, "slot": 2, "floating": True, "size": [900, 700]},
    {"app": "com.mitchellh.ghostty", "class": "com.mitchellh.ghostty", "desktop": 3, "slot": 1, "floating": False, "cwd": T + "/work/proj"},
    {"app": "com.mitchellh.ghostty", "class": "com.mitchellh.ghostty", "desktop": 3, "slot": 1, "floating": False, "cwd": None},
    {"app": "zathura", "class": "zathura", "desktop": 4, "slot": 3, "floating": False},
]
os.makedirs(STATE + "/session", exist_ok=True)
json.dump({"version": 1, "saved": "2026-11-13T17:00:00-0500", "monitors": 2, "entries": saved}, open(STATE + "/session/last.json", "w"))
setjson("monitors", [{"id": 7, "name": "DP-2", "x": 0, "y": 0}, {"id": 5, "name": "DP-9", "x": 1920, "y": 0}])
setjson("clients", [])
r = restore("--list")
check("default skip list: firefox and emacs not reopened", "skip" in r.stdout and r.stdout.count("reopen ") == 4 and "[skip list]" in r.stdout, r.stdout)
check("--list shows desktop, slot, name, floating, directory", "desktop 3 slot 1" in r.stdout and "Ghostty" in r.stdout and "(floating)" in r.stdout and T + "/work/proj" in r.stdout, r.stdout)
check("--count counts reopenable windows", restore("--count").stdout.strip() == "4")
setjson("clients", [cl("0x1", "com.mitchellh.ghostty", 11), cl("0x2", "zathura", 11)])
r = restore("--list")
check("an app with as many windows open as were saved is skipped", "[already running]" in r.stdout and r.stdout.count("reopen ") == 2, r.stdout)
check("an app with fewer open: only the rest is opened (2 saved, 1 open, 1 reopened)", "Ghostty" in r.stdout.split("skip")[0] or r.stdout.count("Ghostty") == 2, r.stdout)
conf({"skip": ["zathura"], "allow": []})
r = restore("--list")
check("a config skip list replaces the default (firefox is reopened now)", "reopen  desktop 1 slot 1" in r.stdout and "Firefox" in r.stdout.split("skip")[0], r.stdout)
conf({"allow": ["org.gnome.Nautilus", "zathura"], "skip": []})
setjson("clients", [])
r = restore("--list")
check("allow list: only those", r.stdout.count("reopen ") == 2 and "[not on the allow list]" in r.stdout, r.stdout)
conf({"skip": ["NAUTILUS"]}); r = restore("--list")
check("skip matches the last part of the id, case-insensitively", any("Files" in l and "[skip list]" in l for l in r.stdout.splitlines()), r.stdout)
os.remove(CONF + "/shell/session.json")

case("restore --dry-run: exact commands")
setjson("clients", [])
r = restore("--dry-run", env={"HOME": T})
lines = r.stdout.splitlines()
nauti = [l for l in lines if "Nautilus" in l]
check("move mode launches through uwsm app with the desktop id", "uwsm app -- org.gnome.Nautilus.desktop" in lines, r.stdout)
check("move mode: the move command for slot 2 on desktop 2 = workspace 22 (slot 3 folds to 2 with two monitors)",
      any(l.startswith("hyprctl eval") and "workspace = 22," in l and "hl.get_window(" in l and "follow = false" in l for l in lines), r.stdout)
check("terminal reopens in its directory", "uwsm app -- ghostty --gtk-single-instance=true --working-directory=" + T + "/work/proj" in lines, r.stdout)
check("terminal with unknown cwd opens plain", "uwsm app -- com.mitchellh.ghostty.desktop" in lines, r.stdout)
check("dry run starts nothing", calls() == [])
conf({"mode": "exec"})
r = restore("--dry-run")
check("exec mode: exact hl.exec_cmd form with workspace N silent",
      "hyprctl eval 'hl.exec_cmd(\"uwsm app -- zathura.desktop\", { workspace = \"42 silent\" })'" in r.stdout.splitlines(), r.stdout)
check("exec mode: floating window carries float and size",
      "hyprctl eval 'hl.exec_cmd(\"uwsm app -- org.gnome.Nautilus.desktop\", { workspace = \"22 silent\", float = true, size = \"900 700\" })'" in r.stdout.splitlines(), r.stdout)
check("exec mode: terminal gets its own process (no single instance)", "--gtk-single-instance=false" in r.stdout)
conf({"terminalsRestoreCwd": False})
check("terminalsRestoreCwd false: no --working-directory", "--working-directory" not in restore("--dry-run").stdout)
setjson("monitors", [{"id": 7, "name": "DP-2", "x": 0, "y": 0}])
conf({"mode": "exec"})
r = restore("--dry-run")
check("one monitor now: slot 3 folds to slot 1 (desktop 4 -> workspace 41)", '"41 silent"' in r.stdout, r.stdout)
os.remove(CONF + "/shell/session.json")

case("restore for real against the fakes (move mode)")
clear_calls(); setjson("monitors", [{"id": 7, "name": "DP-2", "x": 0, "y": 0}, {"id": 5, "name": "DP-9", "x": 1920, "y": 0}]); setjson("clients", [])
conf({"delayMs": 0, "timeoutS": 2})
r = restore()
c = calls()
check("exits 0", r.returncode == 0, r.stderr)
check("launches the four reopenable windows, none of the skipped", [x for x in c if x.startswith("uwsm")].__len__() == 4 and not any("firefox" in x or "emacs" in x for x in c), "\n".join(c))
moves = [x for x in c if x.startswith("hyprctl eval")]
check("each launched window is moved to its workspace", len(moves) == 4 and any("workspace = 22," in m for m in moves) and any("workspace = 42," in m for m in moves) and sum("workspace = 31," in m for m in moves) == 2, "\n".join(moves))
check("moves target the new windows' addresses", all('address:0xnew' in m for m in moves))
clear_calls(); setjson("clients", []); open(FAKE + "/nospawn", "w").close()
r = restore()
check("a window that never appears is logged and nothing is moved", "no new window" in r.stderr and not [x for x in calls() if x.startswith("hyprctl")], r.stderr)
os.remove(FAKE + "/nospawn")
os.remove(CONF + "/shell/session.json")

case("login marker and offer")
r = restore("--status"); st = json.loads(r.stdout)
check("status: disabled by default, 4 reopenable, summary", st["enabled"] is False and st["count"] == 4 and "ghostty x2" in st["summary"], r.stdout)
r = json.loads(restore("--login-check").stdout)
check("disabled: no offer, but the login is marked", r["offer"] is False and os.path.exists(RT + "/session-login"), r)
restore("--set-enabled", "true")
check("--set-enabled writes the config", json.load(open(CONF + "/shell/session.json"))["enabled"] is True)
r = json.loads(restore("--login-check").stdout)
check("enabling mid-session does not offer (same login)", r["offer"] is False and r.get("why") == "not a new login", r)
os.remove(RT + "/session-login")
r = json.loads(restore("--login-check").stdout)
check("new login, enabled, windows saved: offer with count and summary", r["offer"] is True and r["count"] == 4 and "zathura" in r["summary"], r)
r = json.loads(restore("--login-check").stdout)
check("a shell reload (marker present) does not offer again", r["offer"] is False, r)
os.remove(RT + "/session-login")
json.dump({"version": 1, "saved": "x", "monitors": 1, "entries": [saved[0], saved[1]]}, open(STATE + "/session/last.json", "w"))
r = json.loads(restore("--login-check").stdout)
check("only skipped apps saved: nothing to offer", r["offer"] is False and r.get("why") == "nothing to reopen", r)
os.remove(RT + "/session-login"); os.remove(STATE + "/session/last.json")
check("nothing saved: no offer", json.loads(restore("--login-check").stdout)["offer"] is False)
os.remove(RT + "/session-login")
r = subprocess.run([sys.executable, BIN + "/session-restore", "--login-check"], env={k: v for k, v in ENV.items() if k != "XDG_RUNTIME_DIR"}, capture_output=True, text=True)
check("no runtime dir: no offer", json.loads(r.stdout)["offer"] is False)
restore("--set-enabled", "false")
cfg = json.load(open(CONF + "/shell/session.json"))
check("--set-enabled keeps the other keys", cfg["enabled"] is False and "skip" in cfg and "mode" in cfg)

print("SESSIONTEST RESULT pass %d fail %d" % (passed, failed))
shutil.rmtree(T, ignore_errors=True)
sys.exit(1 if failed else 0)
