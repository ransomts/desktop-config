#!/usr/bin/env python3
"""Tests for bin/updates-check against fake apt, flatpak and fwupdmgr on a private PATH and
made-up lists, kernels and caches in a temporary HOME.  Usage: updates-test.py PATH-TO-updates-check.
Prints PASS/FAIL lines; exit 1 on a failure.  The real machine is never read."""
import json, os, shutil, subprocess, sys, tempfile, time

UC = sys.argv[1]
NOW = 1794664800
D = 86400
passed = failed = 0


def check(what, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
    print(("PASS " if ok else "FAIL ") + what + ("" if ok or not detail else "   [%s]" % detail))


APT = r'''#!/usr/bin/env python3
import os, sys, time
f = os.environ["FAKE"]
if os.path.exists(f + "/apt-hang"):
    time.sleep(60)
if os.path.exists(f + "/apt-fail"):
    sys.exit(100)
sys.stderr.write("\nWARNING: apt does not have a stable CLI interface. Use with caution in scripts.\n\n")
print("Listing...")
if os.path.exists(f + "/apt-out"):
    sys.stdout.write(open(f + "/apt-out").read())
open(f + "/apt-calls", "a").write(" ".join(sys.argv[1:]) + "\n")
'''
FLATPAK = r'''#!/usr/bin/env python3
import os, sys, time
f = os.environ["FAKE"]
scope = "user" if "--user" in sys.argv else "system"
open(f + "/flatpak-calls", "a").write(scope + "\n")
if os.path.exists(f + "/flatpak-hang-" + scope):
    time.sleep(60)
if os.path.exists(f + "/flatpak-fail-" + scope):
    sys.exit(1)
p = f + "/flatpak-" + scope
if os.path.exists(p):
    sys.stdout.write(open(p).read())
'''
FWUPD = r'''#!/usr/bin/env python3
import os, sys, time
f = os.environ["FAKE"]
if os.path.exists(f + "/fwupd-hang"):
    time.sleep(60)
p = f + "/fwupd-out"
if os.path.exists(p):
    sys.stdout.write(open(p).read())
    sys.exit(0)
sys.stdout.write('{"Devices" : []}\n')
'''


class Env:
    def __init__(self):
        self.root = tempfile.mkdtemp(prefix="updatestest-")
        self.fake = self.root + "/fake"
        self.home = self.root + "/home"
        for d in (self.fake + "/bin", self.home, self.root + "/lists", self.root + "/periodic", self.root + "/boot", self.root + "/cache"):
            os.makedirs(d)
        for n, body in (("apt", APT), ("flatpak", FLATPAK), ("fwupdmgr", FWUPD)):
            self.install(n, body)
        open(self.root + "/route", "w").write("Iface\tDestination\tGateway\tFlags\nwlp0\t00000000\t0100A8C0\t0003\n")
        open(self.root + "/dpkg-status", "w").write("x")
        os.utime(self.root + "/dpkg-status", (NOW - 10 * D, NOW - 10 * D))
        self.reset()

    def install(self, n, body):
        p = "%s/bin/%s" % (self.fake, n)
        open(p, "w").write(body)
        os.chmod(p, 0o755)

    def reset(self):
        for n in os.listdir(self.fake):
            if n != "bin":
                os.remove(os.path.join(self.fake, n))
        for n in os.listdir(self.root + "/lists"):
            os.remove(self.root + "/lists/" + n)
        for n in os.listdir(self.root + "/boot"):
            os.remove(self.root + "/boot/" + n)
        shutil.rmtree(self.root + "/cache", ignore_errors=True)
        for p in ("/reboot-required", "/reboot-required.pkgs", "/periodic/update-success-stamp"):
            if os.path.exists(self.root + p):
                os.remove(self.root + p)
        self.lists(1 * 3600)
        open(self.root + "/boot/vmlinuz-7.2.15-76070215-generic", "w").write("")
        self.write("route", None)

    def write(self, name, text):
        p = self.fake + "/" + name if name != "route" else self.root + "/route"
        if text is None:
            if name == "route":
                open(p, "w").write("Iface\tDestination\tGateway\tFlags\nwlp0\t00000000\t0100A8C0\t0003\n")
            elif os.path.exists(p):
                os.remove(p)
        else:
            open(p, "w").write(text)

    def lists(self, age):
        p = self.root + "/lists/apt.pop-os.org_release_dists_noble_InRelease"
        open(p, "w").write("x")
        os.utime(p, (NOW - age, NOW - age))

    def run(self, *args, extra=None, path=None, timeout=60):
        env = dict(os.environ, HOME=self.home, XDG_CACHE_HOME=self.root + "/cache", XDG_STATE_HOME=self.home + "/state", FAKE=self.fake,
                   PATH=path if path is not None else self.fake + "/bin:" + os.environ["PATH"],
                   UPDATES_CHECK_NOW=str(NOW), UPDATES_CHECK_TIMEOUT="2", UPDATES_CHECK_ROUTE=self.root + "/route",
                   UPDATES_CHECK_LISTS=self.root + "/lists", UPDATES_CHECK_PERIODIC=self.root + "/periodic",
                   UPDATES_CHECK_REBOOT_FILE=self.root + "/reboot-required", UPDATES_CHECK_BOOT_DIR=self.root + "/boot",
                   UPDATES_CHECK_KERNEL="7.2.15-76070215-generic", UPDATES_CHECK_DPKG_STATUS=self.root + "/dpkg-status",
                   UPDATES_CHECK_FLATPAK_STAMPS=self.root + "/flatpak-changed",
                   UPDATES_CHECK_BOOT_ID="boot-1", UPDATES_CHECK_NIX_PROFILE=self.root + "/no-nix")
        env.update(extra or {})
        t = time.time()
        p = subprocess.run([sys.executable, "-I", UC] + list(args), capture_output=True, text=True, env=env, timeout=timeout)
        self.took = time.time() - t
        self.err = p.stderr
        self.rc = p.returncode
        return p.stdout

    def look(self, *args, **kw):
        out = self.run("--refresh", *args, **kw)
        try:
            d = json.loads(out)
        except ValueError:
            check("valid JSON", False, out[:200] + self.err[:300])
            return {"rows": [], "skipped": []}, {}
        return d, {r["id"]: r for r in d["rows"]}

    def calls(self, name):
        p = self.fake + "/" + name
        return open(p).read().splitlines() if os.path.exists(p) else []


APT_LINES = ("libfoo1/noble-updates 1.2 amd64 [upgradable from: 1.1]\n"
             "openssl/noble-updates,noble-security 3.0.13 amd64 [upgradable from: 3.0.12]\n"
             "bash/noble-security 5.2 amd64 [upgradable from: 5.1]\n"
             "vim/noble-updates 9.1 amd64 [upgradable from: 9.0]\n")
KEYS = {"id", "name", "count", "detail", "cmd"}

e = Env()

print("case: nothing waiting")
d, r = e.look()
check("no rows at all, nothing skipped", d["rows"] == [] and d["skipped"] == [], str(d))
check("apt was asked to list, never to update", e.calls("apt-calls") == ["list --upgradable"], str(e.calls("apt-calls")))
check("--text says so", "nothing waiting" in e.run("--text"), e.run("--text"))

print("case: apt updates")
e.write("apt-out", APT_LINES)
d, r = e.look()
a = r["apt"]
check("four updates, two of them security (suite names ending in -security)", a["count"] == 4 and a["security"] == 2, str(a))
check("row has id, name, count, detail, cmd", KEYS <= set(a), str(set(a)))
check("detail says counts and security and the lists' age", "4 package updates (2 security)" in a["detail"] and "lists from today" in a["detail"], a["detail"])
check("cmd is what the person would run, plain apt upgrade while the lists are fresh", a["cmd"] == "sudo apt upgrade", a["cmd"])
check("the warning line on stderr and the Listing... line are not counted", a["count"] == 4)
e.write("apt-out", "".join("p%d/noble-updates 1 amd64 [upgradable from: 0]\n" % i for i in range(60)))
check("60 plain updates, none security", e.look()[1]["apt"]["count"] == 60 and e.look()[1]["apt"]["security"] == 0)

print("case: stale lists")
e.write("apt-out", APT_LINES)
e.lists(5 * D)
a = e.look()[1]["apt"]
check("lists 5 days old: the detail says so", "the lists are 5 days old" in a["detail"] and a["listsAgeDays"] == 5.0, a["detail"])
check("and the cmd refreshes them first", a["cmd"] == "sudo apt update && sudo apt upgrade", a["cmd"])
e.write("apt-out", None)
e.lists(20 * D)
d, r = e.look()
check("nothing listed but lists 20 days old: a row with count 0 that warns", r["apt"]["count"] == 0 and r["apt"]["listsAgeDays"] == 20.0 and "20 days old" in r["apt"]["detail"], str(r.get("apt")))
e.lists(2 * D)
check("lists 2 days old with nothing listed: no row", "apt" not in e.look()[1])
e.reset()
open(e.root + "/periodic/update-success-stamp", "w").write("")
os.utime(e.root + "/periodic/update-success-stamp", (NOW - 30 * D, NOW - 30 * D))
e.write("apt-out", APT_LINES)
check("the periodic stamp counts when it is newer than the lists", e.look()[1]["apt"]["listsAgeDays"] <= 1.0, str(e.look()[1]["apt"]))
shutil.rmtree(e.root + "/lists")
os.makedirs(e.root + "/lists")
os.remove(e.root + "/periodic/update-success-stamp")
a = e.look()[1]["apt"]
check("no lists and no stamp: age unknown, not invented", a["listsAgeDays"] is None and "days old" not in a["detail"], str(a))

print("case: flatpak")
e.reset()
e.write("flatpak-user", "org.freecad.FreeCAD\n")
e.write("flatpak-system", "com.slack.Slack\norg.DolphinEmu.dolphin-emu\norg.DolphinEmu.dolphin-emu\n")
d, r = e.look()
check("user and system installs are counted (duplicate lines once)", r["flatpak"]["count"] == 3 and "1 user and 2 system" in r["flatpak"]["detail"], str(r.get("flatpak")))
check("cmd is flatpak update", r["flatpak"]["cmd"] == "flatpak update")
check("both installs were asked", sorted(e.calls("flatpak-calls")) == ["system", "user"], str(e.calls("flatpak-calls")))
e.write("flatpak-user", "")
check("only system updates: only system named", e.look()[1]["flatpak"]["detail"].endswith("(2 system)"))
e.write("route", "Iface\tDestination\tGateway\tFlags\n")
os.remove(e.fake + "/flatpak-calls")
d, r = e.look()
check("offline: skipped quietly, flatpak never run", "flatpak" not in r and d["skipped"] == ["flatpak: offline"] and e.calls("flatpak-calls") == [], str(d["skipped"]))
e.write("route", None)
e.write("flatpak-user", "x.Y.Z\n")
open(e.fake + "/flatpak-hang-system", "w").write("")
d, r = e.look()
check("a hanging system call times out (2 s here); the user one still counts", e.took < 6 and r["flatpak"]["count"] == 1, e.took)
check("and says it was skipped", "flatpak system: timed out" in d["skipped"], str(d["skipped"]))
os.remove(e.fake + "/flatpak-hang-system")
open(e.fake + "/flatpak-fail-user", "w").write("")
e.write("flatpak-system", "a.b.C\n")
d, r = e.look()
check("a failing call is skipped, the other counts", r["flatpak"]["count"] == 1 and "flatpak user: failed" in d["skipped"], str(d))

print("case: firmware")
e.reset()
e.write("fwupd-out", json.dumps({"Devices": [{"Name": "UEFI dbx", "Releases": [{"Version": "1"}]}, {"Name": "Webcam", "Releases": []},
                                              {"Name": "NVMe SSD", "Releases": [{"Version": "2"}, {"Version": "3"}]}]}))
r = e.look()[1]
check("devices with releases are counted", r["firmware"]["count"] == 2 and "UEFI dbx" in r["firmware"]["detail"] and "Webcam" not in r["firmware"]["detail"], str(r.get("firmware")))
check("cmd shows then applies", r["firmware"]["cmd"] == "fwupdmgr get-updates; fwupdmgr update")
e.write("fwupd-out", "No updatable devices\n")
d, r = e.look()
check("plain text (nothing to update): no row, no complaint", "firmware" not in r and d["skipped"] == [], str(d))
open(e.fake + "/fwupd-hang", "w").write("")
d, r = e.look()
check("a hanging fwupdmgr is skipped", "firmware" not in r and "firmware: timed out" in d["skipped"], str(d["skipped"]))

print("case: missing tools")
e.reset()
d, r = e.look(path="/nonexistent")
check("no apt, flatpak or fwupd: no rows, each noted as skipped, no crash", d["rows"] == [] and sorted(d["skipped"]) == ["apt: not installed", "firmware: fwupd not installed", "flatpak: not installed"], str(d))
e.write("apt-fail", "")
d, r = e.look()
check("apt failing is skipped, not zero", "apt: failed" in d["skipped"] and "apt" not in r, str(d["skipped"]))
os.remove(e.fake + "/apt-fail")
open(e.fake + "/apt-hang", "w").write("")
t = time.time()
d, r = e.look()
check("a hanging apt times out and the run is still bounded (about 2 s)", "apt: timed out" in d["skipped"] and e.took < 8, e.took)
os.remove(e.fake + "/apt-hang")

print("case: nix profile")
e.reset()
os.makedirs(e.root + "/nixstate")
os.symlink("profile-6-link", e.root + "/nixstate/profile")
os.utime(e.root + "/nixstate/profile", (NOW - 2 * D, NOW - 2 * D), follow_symlinks=False)
r = e.look(extra={"UPDATES_CHECK_NIX_PROFILE": e.root + "/nixstate/profile"})[1]
check("nix: exists, count 0, generation and when it changed, cmd only lists", r["nix"]["count"] == 0 and r["nix"]["generation"] == 6 and "changed 2 days ago" in r["nix"]["detail"] and r["nix"]["cmd"] == "nix profile list", str(r.get("nix")))

print("case: reboot")
e.reset()
check("no reboot row when nothing is pending", "reboot" not in json.loads(e.run("--refresh")) ["rows"].__repr__())
open(e.root + "/reboot-required", "w").write("*** System restart required ***\n")
open(e.root + "/reboot-required.pkgs", "w").write("linux-image-7.2.16\nlibc6\n")
r = e.look()[1]
check("reboot-required file: a row naming the packages", r["reboot"]["count"] == 1 and "linux-image-7.2.16" in r["reboot"]["detail"], str(r.get("reboot")))
check("its cmd asks before rebooting", "systemctl reboot" in r["reboot"]["cmd"] and "read" in r["reboot"]["cmd"], r["reboot"]["cmd"])
os.remove(e.root + "/reboot-required")
os.remove(e.root + "/reboot-required.pkgs")
open(e.root + "/boot/vmlinuz-7.2.16-76070216-generic", "w").write("")
r = e.look()[1]
check("newer kernel installed than running: a row says both", "7.2.16-76070216-generic is installed, 7.2.15-76070215-generic is running" in r["reboot"]["detail"], str(r.get("reboot")))
open(e.root + "/boot/vmlinuz-7.2.9-76070209-generic", "w").write("")
check("7.2.16 beats 7.2.9 (numeric, not text, order)", "7.2.16-76070216" in e.look()[1]["reboot"]["detail"])
os.remove(e.root + "/boot/vmlinuz-7.2.16-76070216-generic")
os.remove(e.root + "/boot/vmlinuz-7.2.9-76070209-generic")
check("running the newest: none", "reboot" not in e.look()[1])
open(e.root + "/boot/vmlinuz-7.2.6-76070206-generic", "w").write("")
check("an older kernel left in /boot is not a reason", "reboot" not in e.look()[1])

print("case: cache")
e.reset()
e.write("apt-out", APT_LINES)
out = json.loads(e.run())
check("first plain run looks (no cache) and writes the cache", len(out["rows"]) == 1 and os.path.exists(e.root + "/cache/updates-check/cache.json"), str(out))
e.write("apt-out", None)
os.remove(e.fake + "/apt-calls")
out = json.loads(e.run(extra={"UPDATES_CHECK_NOW": str(NOW + 5 * 3600)}))
check("under 6 hours: the cache is used, nothing is run", out["rows"][0]["count"] == 4 and e.calls("apt-calls") == [], str(out))
out = json.loads(e.run(extra={"UPDATES_CHECK_NOW": str(NOW + 7 * 3600)}))
check("over 6 hours: looked at again", [x for x in out["rows"] if x["id"] == "apt"] == [] and e.calls("apt-calls") == ["list --upgradable"], str(out))
e.write("apt-out", APT_LINES)
e.run("--refresh", "--quiet")
os.remove(e.fake + "/apt-calls")
e.run(extra={"UPDATES_CHECK_BOOT_ID": "boot-2"})
check("a new boot invalidates the cache", e.calls("apt-calls") == ["list --upgradable"])
os.remove(e.fake + "/apt-calls")
e.run()
os.remove(e.fake + "/apt-calls") if os.path.exists(e.fake + "/apt-calls") else None
os.utime(e.root + "/dpkg-status", (NOW + 60, NOW + 60))
e.run(extra={"UPDATES_CHECK_NOW": str(NOW + 120)})
check("a changed package database (an upgrade was run) invalidates it", e.calls("apt-calls") == ["list --upgradable"], str(e.calls("apt-calls")))
os.utime(e.root + "/dpkg-status", (NOW - 10 * D, NOW - 10 * D))
e.run("--refresh", "--quiet")
os.remove(e.fake + "/apt-calls")
open(e.root + "/flatpak-changed", "w").write("")
os.utime(e.root + "/flatpak-changed", (NOW + 60, NOW + 60))
e.run(extra={"UPDATES_CHECK_NOW": str(NOW + 120)})
check("a Flatpak deploy since the last look invalidates it", e.calls("apt-calls") == ["list --upgradable"], str(e.calls("apt-calls")))
os.remove(e.root + "/flatpak-changed")
e.run("--refresh", "--quiet")
os.remove(e.fake + "/apt-calls")
out = json.loads(e.run("--cached"))
check("--cached prints the cache and does not wait or run apt itself", out["rows"][0]["count"] == 4 and e.took < 2, e.took)
open(e.root + "/reboot-required", "w").write("x")
out = json.loads(e.run("--cached"))
check("the reboot row is always live, even from the cache", any(x["id"] == "reboot" for x in out["rows"]))
os.remove(e.root + "/reboot-required")
out = json.loads(e.run("--cached", extra={"UPDATES_CHECK_NOW": str(NOW + 7 * 3600)}))
time.sleep(1.5)
check("--cached on an old cache still answers at once, and a background refresh then ran", out["rows"][0]["count"] == 4 and e.calls("apt-calls") == ["list --upgradable"], str(e.calls("apt-calls")))
shutil.rmtree(e.root + "/cache")
out = json.loads(e.run("--cached"))
check("--cached with no cache: empty answer at once", out["rows"] == [])
time.sleep(1.5); os.makedirs(e.root + "/cache/updates-check", exist_ok=True)
open(e.root + "/cache/updates-check/cache.json", "w").write("{broken")
check("a broken cache is ignored", json.loads(e.run())["rows"][0]["count"] == 4)
check("a bad option exits 2", subprocess.run([sys.executable, UC, "--nope"], capture_output=True).returncode == 2)
check("it only writes under its cache directory", sorted(os.listdir(e.root + "/cache")) == ["updates-check"] and not os.path.exists(e.home + "/.cache") and not os.path.exists(e.home + "/state"))

shutil.rmtree(e.root, ignore_errors=True)
print("UPDATES RESULT pass %d fail %d" % (passed, failed))
sys.exit(1 if failed else 0)
