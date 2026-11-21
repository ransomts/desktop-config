#!/usr/bin/env python3
"""Tests for bin/shell-health against fake systemctl, findmnt and gsettings on PATH and made-up
state files in a temporary HOME.  Usage: script-test.py PATH-TO-shell-health.  Prints
PASS/FAIL lines; exit 1 on a failure.  Nothing of the real machine is read."""
import json, os, shutil, subprocess, sys, tempfile, time

SH = sys.argv[1]
NOW = 1794664800                      # 2026-11-14 09:00 EST
MIN, H, D = 60, 3600, 86400
passed = failed = 0


def check(what, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
    print(("PASS " if ok else "FAIL ") + what + ("" if ok or not detail else "   [%s]" % detail))


FAKE_SYSTEMCTL = r'''#!/usr/bin/env python3
import os, sys, time
fake = os.environ["FAKE"]
a = sys.argv[1:]
if os.path.exists(fake + "/hang"):
    time.sleep(30)
if "show" in a:
    units = a[a.index("show") + 1:]
    units = [u for u in units if not u.startswith("-") and "," not in u]
    for u in units:
        p = "%s/units/%s" % (fake, u)
        if os.path.exists(p):
            sys.stdout.write(open(p).read() + "\n")
        else:
            sys.stdout.write("Id=%s\nLoadState=not-found\nActiveState=inactive\n\n" % u)
elif "list-units" in a:
    p = fake + "/failed"
    if os.path.exists(p):
        sys.stdout.write(open(p).read())
'''
FAKE_DOCKER = r'''#!/usr/bin/env python3
import os, sys, time
fake = os.environ["FAKE"]
if os.path.exists(fake + "/docker-hang"):
    time.sleep(30)
p = fake + "/docker"
if os.path.exists(p):
    sys.stdout.write(open(p).read())
'''
FAKE_FINDMNT = r'''#!/usr/bin/env python3
import os, sys
fake = os.environ["FAKE"]
target = sys.argv[-1]
for line in open(fake + "/mounts").read().splitlines() if os.path.exists(fake + "/mounts") else []:
    if line.split()[0] == target:
        print(line); sys.exit(0)
sys.exit(1)
'''
FAKE_GSETTINGS = r'''#!/usr/bin/env python3
import json, os, sys
fake = os.environ["FAKE"]
prof = "cosmic" if "cosmic" in os.environ.get("DCONF_PROFILE", "") else "default"
p = "%s/gs-%s.json" % (fake, prof)
if not os.path.exists(p):
    sys.exit(1)
d = json.load(open(p))
key = sys.argv[3]
print(d.get(key, "''"))
'''


class Env:
    def __init__(self):
        self.root = tempfile.mkdtemp(prefix="healthtest-")
        self.fake = self.root + "/fake"
        self.home = self.root + "/home"
        self.state = self.home + "/state"
        self.run_dir = self.root + "/run"
        for d in (self.fake + "/units", self.fake + "/bin", self.state, self.run_dir, self.fake + "/net"):
            os.makedirs(d)
        for name, body in (("systemctl", FAKE_SYSTEMCTL), ("findmnt", FAKE_FINDMNT), ("gsettings", FAKE_GSETTINGS), ("docker", FAKE_DOCKER)):
            p = "%s/bin/%s" % (self.fake, name)
            open(p, "w").write(body)
            os.chmod(p, 0o755)
        open(self.fake + "/route", "w").write("Iface\tDestination\tGateway\tFlags\nwlp0\t00000000\t0100A8C0\t0003\n")
        open(self.fake + "/net/tcp", "w").write("  sl  local_address rem_address   st\n   0: 00000000:0477 00000000:0000 0A\n   1: 00000000:0438 00000000:0000 0A\n")
        open(self.fake + "/net/tcp6", "w").write("  sl  local_address rem_address   st\n")
        self.healthy()
        self.config(None)
        self.disks({})
        self.updates([])

    def config(self, d):
        p = self.root + "/health.json"
        if d is None:
            if os.path.exists(p):
                os.remove(p)
        else:
            json.dump(d, open(p, "w"))

    def disks(self, table):
        json.dump(table, open(self.root + "/disks.json", "w"))

    def updates(self, rows):
        """a stand-in updates-check that prints these rows (the real one has its own tests)"""
        p = self.root + "/updates-fake"
        open(p, "w").write("#!/usr/bin/env python3\nimport json\nprint(json.dumps({'rows': %r}))\n" % (rows,))

    def unit(self, name, load="loaded", active="active", result="success", status="0", fstate="enabled",
             enter=None, trigger=None, restarts="0"):
        enter = "@%d" % enter if enter else ""
        trigger = "@%d" % trigger if trigger else ""
        open("%s/units/%s" % (self.fake, name), "w").write(
            "Id=%s\nLoadState=%s\nActiveState=%s\nSubState=x\nResult=%s\nExecMainStatus=%s\nUnitFileState=%s\n"
            "NRestarts=%s\nActiveEnterTimestamp=%s\nLastTriggerUSec=%s\nExecMainExitTimestamp=\n"
            % (name, load, active, result, status, fstate, restarts, enter, trigger))

    def docker(self, rows):
        open(self.fake + "/docker", "w").write(rows.replace("\\n", "\n"))

    def rm_unit(self, name):
        os.remove("%s/units/%s" % (self.fake, name))

    def streak(self, d, failures, age, reason=""):
        os.makedirs("%s/%s" % (self.state, d), exist_ok=True)
        p = "%s/%s/failures" % (self.state, d)
        open(p, "w").write("%d\n" % failures)
        os.utime(p, (NOW - age, NOW - age))
        open("%s/%s/reason" % (self.state, d), "w").write(reason + "\n")

    def backup(self, path, name, age, is_dir=False):
        os.makedirs(path, exist_ok=True)
        p = os.path.join(path, name)
        (os.makedirs(p, exist_ok=True) if is_dir else open(p, "w").write("x"))
        os.utime(p, (NOW - age, NOW - age))

    def gs(self, profile, last="", periodic="true", period="7"):
        json.dump({"last-backup": "'%s'" % last, "periodic": periodic, "periodic-period": period},
                  open("%s/gs-%s.json" % (self.fake, profile), "w"))

    def ms(self, state, detail="", since_age=0):
        os.makedirs(self.state + "/microsoft", exist_ok=True)
        json.dump({"state": state, "detail": detail, "checked": NOW - 600, "since": NOW - since_age},
                  open(self.state + "/microsoft/health.json", "w"))

    def healthy(self):
        for t, s, trig in (("pull-mail", 1, 60), ("pull-calendars", 1, 300), ("push-roam", 1, 200),
                           ("calibre-db-backup", 0, 2 * D), ("matrix-backup", 0, 2 * D)):
            self.unit(t + ".timer", trigger=NOW - trig, enter=NOW - D)
            self.unit(t + ".service", active="inactive", enter=None)
        self.streak("pull-mail", 0, 60)
        self.streak("pull-calendars", 0, 5 * MIN)
        self.streak("push-roam", 0, 4 * MIN)
        self.backup(self.home + "/.local/share/calibre-db-backups", "metadata-2026-11-08.db", 2 * D)
        self.backup(self.home + "/backups/matrix", "2026-11-08", 2 * D, True)
        self.unit("davmail.service", enter=NOW - 5 * H)
        self.unit("onedrive.service", enter=NOW - 3 * H)
        self.unit("onedrive-restart.timer", enter=NOW - D)
        self.unit("onedrive-restart.service", active="inactive")
        self.unit("rclone-box.service", enter=NOW - 5 * H)
        self.unit("qs-socket-watch.service", enter=NOW - 20 * H)
        self.unit("mpd.service", enter=NOW - 20 * H)
        self.unit("teams-refresh.timer", trigger=NOW - 2 * H, enter=NOW - D)
        self.unit("teams-refresh.service", active="inactive")
        os.makedirs(self.fake + "/archive", exist_ok=True)
        open(self.fake + "/archive-dev", "w").write("")
        self.docker("synapse running healthy 2026-11-14T08:00:00Z\nmautrix-teams running healthy x\nmautrix-gmessages running none x\n")
        open(self.fake + "/mounts", "w").write("%s/Box fuse.rclone\n" % self.run_dir)
        self.gs("default", "", "true", "7")
        self.gs("cosmic", "2026-11-12T15:17:55.379354Z", "true", "7")
        self.ms("ok")
        open(self.fake + "/net/tcp", "w").write("  sl  local_address rem_address   st\n   0: 00000000:0477 00000000:0000 0A\n   1: 00000000:0438 00000000:0000 0A\n")
        for f in ("failed", "hang", "docker-hang"):
            if os.path.exists(self.fake + "/" + f):
                os.remove(self.fake + "/" + f)
        shutil.rmtree(self.state + "/shell-health", ignore_errors=True)

    def run(self, *args, now=NOW, online=True, timeout=8, extra=None):
        env = dict(os.environ, HOME=self.home, SHELL_HEALTH_CONFIG=self.root + "/health.json", SHELL_HEALTH_DISKS=self.root + "/disks.json",
                   SHELL_HEALTH_UPDATES=self.root + "/updates-fake", XDG_STATE_HOME=self.state, XDG_RUNTIME_DIR=self.run_dir, FAKE=self.fake,
                   PATH=self.fake + "/bin:" + os.environ["PATH"], SHELL_HEALTH_NOW=str(now),
                   SHELL_HEALTH_ROUTE=self.fake + ("/route" if online else "/noroute"), SHELL_HEALTH_NETDIR=self.fake + "/net",
                   XDG_CURRENT_DESKTOP="Hyprland", SHELL_HEALTH_WAKE="0",
                   SHELL_HEALTH_CONFIRM="0", SHELL_HEALTH_CONNECTIVITY="full",
                   SHELL_HEALTH_ARCHIVE_DEV=self.fake + "/archive-dev", SHELL_HEALTH_ARCHIVE_DIR=self.fake + "/archive")
        env.update(extra or {})
        t = time.time()
        p = subprocess.run([sys.executable, "-I", SH] + list(args), capture_output=True, text=True, env=env, timeout=timeout)
        self.took = time.time() - t
        self.err = p.stderr
        return p.stdout

    def jobs(self, *args, **kw):
        out = self.run(*args, **kw)
        try:
            d = json.loads(out)
        except ValueError:
            check("valid JSON", False, out[:200] + self.err[:300])
            return {"worst": "?", "jobs": []}, {}
        return d, {j["id"]: j for j in d["jobs"]}


def states(j, *ids):
    return ", ".join("%s=%s" % (i, j.get(i, {}).get("state")) for i in ids)


e = Env()

print("case: everything healthy")
d, j = e.jobs()
ids = ["pull-mail", "pull-calendars", "push-roam", "calibre-backup", "matrix-backup", "davmail", "onedrive", "rclone-box", "dejadup", "microsoft", "qs-socket-watch"]
check("worst is ok", d["worst"] == "ok", d["worst"])
check("all eleven jobs ok", all(j.get(i, {}).get("state") == "ok" for i in ids), states(j, *ids))
keys = {"id", "name", "state", "since", "why", "unit", "log", "run"}
check("every job has the documented keys", all(set(x) == keys for x in d["jobs"]), str([set(x) ^ keys for x in d["jobs"] if set(x) != keys]))
check("since is ISO time with an offset", j["pull-mail"]["since"][:4] == "2026" and j["pull-mail"]["since"][-6] in "+-", j["pull-mail"]["since"])
check("log and run commands present", "journalctl --user -u pull-mail.service" in j["pull-mail"]["log"] and j["pull-mail"]["run"] == "systemctl --user start pull-mail.service")
check("faster than 3 s", e.took < 3, e.took)
check("the latest Deja Dup backup of the two profiles is used", "2 days ago" in j["dejadup"]["why"], j["dejadup"]["why"])
check("rclone-box ok because findmnt shows it", j["rclone-box"]["state"] == "ok", j["rclone-box"]["why"])

print("case: failed")
e.healthy()
e.streak("pull-mail", 3, 60, "davmail-down")
e.unit("push-roam.service", active="failed", result="exit-code", status="1")
e.unit("davmail.service", active="inactive")
e.unit("onedrive.service", active="failed", result="exit-code", status="78")
d, j = e.jobs()
check("worst is failed", d["worst"] == "failed")
check("mail: three failed runs in a row", j["pull-mail"]["state"] == "failed" and "3 runs" in j["pull-mail"]["why"] and "DavMail is not running" in j["pull-mail"]["why"], j["pull-mail"]["why"])
check("mail: since is the last run that worked (unknown without a record: shown as the last trigger)", "since" in j["pull-mail"])
check("push-roam: failed unit", j["push-roam"]["state"] == "failed" and "exit 1" in j["push-roam"]["why"], j["push-roam"]["why"])
check("davmail stopped", j["davmail"]["state"] == "failed" and j["davmail"]["run"] == "systemctl --user restart davmail.service")
check("onedrive exit 78 says resync", j["onedrive"]["state"] == "failed" and "resync" in j["onedrive"]["why"], j["onedrive"]["why"])
check("failed ones come first in the list", [x["state"] for x in d["jobs"]][:4] == ["failed"] * 4, str([x["state"] for x in d["jobs"]]))
e.streak("pull-mail", 1, 60)
d, j = e.jobs()
check("one failing run is not a failure (the script's own threshold): healing, says how many more", j["pull-mail"]["state"] == "healing" and "1 more before it counts" in j["pull-mail"]["why"], j["pull-mail"]["why"])

print("case: stale")
e.healthy()
e.streak("pull-calendars", 0, 2 * H)
e.backup(e.home + "/.local/share/calibre-db-backups", "metadata-2026-10-01.db", 44 * D)
os.remove(e.home + "/.local/share/calibre-db-backups/metadata-2026-11-08.db")
e.gs("cosmic", "2026-10-01T00:00:00Z")
d, j = e.jobs()
check("calendar: two hours since a run is stale", j["pull-calendars"]["state"] == "stale" and "2 h ago" in j["pull-calendars"]["why"], j["pull-calendars"]["why"])
check("calibre: weekly backup 44 days old is stale", j["calibre-backup"]["state"] == "stale", j["calibre-backup"]["why"])
check("deja dup: six weeks old is stale", j["dejadup"]["state"] == "stale", j["dejadup"]["why"])
check("worst is stale", d["worst"] == "stale", d["worst"])
check("a weekly job 10 days late is still fine", (e.backup(e.home + "/.local/share/calibre-db-backups", "metadata-new.db", 10 * D) or True) and e.jobs()[1]["calibre-backup"]["state"] == "ok")
e.healthy()
e.streak("pull-calendars", 3, 60)
check("calendar: 3 failures in a row is stale (the unit itself stays green until 6)", e.jobs()[1]["pull-calendars"]["state"] == "stale")
e.streak("pull-calendars", 6, 60)
check("calendar: 6 in a row is failed", e.jobs()[1]["pull-calendars"]["state"] == "failed")
e.healthy()
e.streak("pull-calendars", 1, 60, "microsoft-down")
j = e.jobs()[1]
check("calendar: Microsoft down is named, stale not failed", j["pull-calendars"]["state"] == "stale" and "Microsoft 365" in j["pull-calendars"]["why"], j["pull-calendars"]["why"])

print("case: healing after start-up or wake")
e.healthy()
for t in ("pull-mail", "pull-calendars", "push-roam"):
    e.streak(t, 0, 9 * H)
e.unit("push-roam.timer", trigger=NOW - 9 * H, enter=NOW - 2 * MIN)
open(e.fake + "/units/push-roam.timer", "a").write("NextElapseUSecRealtime=@%d\n" % (NOW + 3 * MIN))
woke = {"SHELL_HEALTH_WAKE": str(NOW - 2 * MIN)}
d, j = e.jobs(extra=woke)
check("nine hours off, woke 2 min ago: healing, not stale", states(j, "pull-mail", "pull-calendars", "push-roam") == "pull-mail=healing, pull-calendars=healing, push-roam=healing", states(j, "pull-mail", "pull-calendars", "push-roam"))
check("healing is left out of worst", d["worst"] == "ok", d["worst"])
check("says it waits for the first run, when it is due, and when it last worked", "first run since start-up" in j["push-roam"]["why"] and "in 3 min" in j["push-roam"]["why"] and "9 h ago" in j["push-roam"]["why"], j["push-roam"]["why"])
check("healing sorts between stale and ok", [x["state"] for x in d["jobs"]][:3] == ["healing"] * 3, str([x["state"] for x in d["jobs"]]))
check("the weekly backups are not affected by a wake", j["matrix-backup"]["state"] == "ok")
d, j = e.jobs(extra={"SHELL_HEALTH_WAKE": str(NOW - 20 * MIN)})
check("woke 20 min ago, mail (limit 15 min) never ran since: stale, counted from the wake", j["pull-mail"]["state"] == "stale" and "since start-up or wake 20 min ago" in j["pull-mail"]["why"], j["pull-mail"]["why"])
check("... calendar (limit 30 min) still healing", j["pull-calendars"]["state"] == "healing", j["pull-calendars"]["why"])
e.streak("pull-mail", 0, 60)
check("ran after the wake: ok", e.jobs(extra=woke)[1]["pull-mail"]["state"] == "ok")
e.streak("pull-calendars", 0, 20 * MIN)
d, j = e.jobs(extra=woke)
check("ran just before the wake and not overdue: ok, and its time is the real one", j["pull-calendars"]["state"] == "ok" and "20 min ago" in j["pull-calendars"]["why"] and "backed up 2 days ago" in j["matrix-backup"]["why"], j["pull-calendars"]["why"] + " / " + j["matrix-backup"]["why"])
e.streak("pull-calendars", 0, 9 * H)
e.unit("pull-calendars.service", active="activating")
check("a timer job running right now after a wake says so", "running now" in e.jobs(extra=woke)[1]["pull-calendars"]["why"])
print("case: wake read from the journal (sleep.target loses its timestamps once collected)")
e.healthy()
for t in ("pull-calendars", "push-roam"):
    e.streak(t, 0, 2 * H)
open(e.fake + "/stat", "w").write("cpu 1 2 3\nbtime %d\n" % (NOW - 9 * H))
open(e.fake + "/bin/journalctl", "w").write("#!/bin/sh\necho \"%d.4628 host systemd[1]: Finished systemd-suspend.service - System Suspend.\"\n" % (NOW - 2 * MIN))
os.chmod(e.fake + "/bin/journalctl", 0o755)
real = {"SHELL_HEALTH_WAKE": "", "SHELL_HEALTH_PROCSTAT": e.fake + "/stat"}
d, j = e.jobs(extra=real)
check("asleep 2 h, resumed 2 min ago per the journal: healing, not stale", states(j, "pull-calendars", "push-roam") == "pull-calendars=healing, push-roam=healing", states(j, "pull-calendars", "push-roam"))
open(e.fake + "/bin/journalctl", "w").write("#!/bin/sh\n")
d, j = e.jobs(extra=real)
check("no resume this boot: graded from boot (9 h ago), so 2 h overdue is stale", j["pull-calendars"]["state"] == "stale", j["pull-calendars"]["why"])
os.remove(e.fake + "/bin/journalctl")

print("case: failures in the first minutes after a wake")
e.healthy()
e.streak("pull-mail", 2, 30)
w3 = {"SHELL_HEALTH_WAKE": str(NOW - 3 * MIN)}
j = e.jobs(extra=w3)[1]
check("2 failures (mail's limit), both since a wake 3 min ago: healing", j["pull-mail"]["state"] == "healing" and "since waking" in j["pull-mail"]["why"], j["pull-mail"]["why"])
e.unit("pull-mail.service", active="failed", result="exit-code", status="1")
check("... even with the unit itself failed", e.jobs(extra=w3)[1]["pull-mail"]["state"] == "healing")
check("woke 6 min ago: the grace is over, failed", e.jobs(extra={"SHELL_HEALTH_WAKE": str(NOW - 6 * MIN)})[1]["pull-mail"]["state"] == "failed")
e.healthy()
e.streak("pull-mail", 2, 5 * MIN)
check("last failure before the wake: no grace, failed", e.jobs(extra=w3)[1]["pull-mail"]["state"] == "failed")
e.streak("matrix-backup", 0, 1)
e.unit("matrix-backup.service", active="failed", result="exit-code", status="1")
check("a job off the network gets no wake grace", e.jobs(extra=w3)[1]["matrix-backup"]["state"] == "failed")

e.healthy()
e.unit("davmail.service", active="activating", restarts="1", enter=NOW - 10)
check("a service restarting (under 3 restarts) is healing", e.jobs()[1]["davmail"]["state"] == "healing")
e.unit("davmail.service", enter=NOW - 20)
open(e.fake + "/net/tcp", "w").write("  sl  local_address rem_address   st\n")
check("davmail just started, port not up yet: healing", e.jobs()[1]["davmail"]["state"] == "healing")

print("case: off")
e.healthy()
for u in ("calibre-db-backup.timer", "calibre-db-backup.service", "matrix-backup.timer", "matrix-backup.service", "qs-socket-watch.service"):
    e.rm_unit(u)
e.gs("cosmic", "", "false")
e.gs("default", "", "false")
d, j = e.jobs()
check("missing units are off", states(j, "calibre-backup", "matrix-backup", "qs-socket-watch") == "calibre-backup=off, matrix-backup=off, qs-socket-watch=off", states(j, "calibre-backup", "matrix-backup", "qs-socket-watch"))
check("backups switched off in Deja Dup: off", j["dejadup"]["state"] == "off", j["dejadup"]["state"])
check("off is left out of worst", d["worst"] == "ok", d["worst"])
check("off jobs sort last", [x["state"] for x in d["jobs"]][-4:] == ["off"] * 4, str([x["state"] for x in d["jobs"]]))
e.healthy()
e.unit("qs-socket-watch.service", active="inactive")
check("watchdog inactive under Hyprland is failed", e.jobs()[1]["qs-socket-watch"]["state"] == "failed")

print("case: mounts and ports")
e.healthy()
open(e.fake + "/mounts", "w").write("")
j = e.jobs()[1]
check("rclone-box running but not mounted: failed", j["rclone-box"]["state"] == "failed" and "mount is gone" in j["rclone-box"]["why"], j["rclone-box"]["why"])
e.healthy()
open(e.fake + "/net/tcp", "w").write("  sl  local_address rem_address   st\n")
j = e.jobs()[1]
check("davmail running but nothing on 1143: failed", j["davmail"]["state"] == "failed" and "1143" in j["davmail"]["why"], j["davmail"]["why"])

print("case: Microsoft record and other failed units")
e.healthy()
e.ms("down", "no reply after 30s", 3 * H)
j = e.jobs()[1]
check("ms down: failed with the detail", j["microsoft"]["state"] == "failed" and "no reply" in j["microsoft"]["why"], j["microsoft"]["why"])
e.ms("auth")
check("ms auth: failed, says how to sign in", "login" in e.jobs()[1]["microsoft"]["why"])
e.ms("offline")
check("ms offline: not a failure", e.jobs()[1]["microsoft"]["state"] == "ok")
e.ms("down", "token error: no reply (Temporary failure in name resolution)", 2 * MIN)
j = e.jobs(extra=w3)[1]
check("ms down only since a wake 3 min ago: healing, not failed", j["microsoft"]["state"] == "healing" and "since waking" in j["microsoft"]["why"], j["microsoft"]["why"])
e.ms("down", "no reply", 3 * MIN + 20)
check("... down from a few seconds before the logged wake: still healing", e.jobs(extra=w3)[1]["microsoft"]["state"] == "healing")
e.ms("down", "no reply", 8 * MIN)
check("ms down since well before the wake: failed", e.jobs(extra=w3)[1]["microsoft"]["state"] == "failed")
e.ms("down", "no reply", 5 * MIN)
check("ms down since a wake 6 min ago: the grace is over, failed", e.jobs(extra={"SHELL_HEALTH_WAKE": str(NOW - 6 * MIN)})[1]["microsoft"]["state"] == "failed")
e.healthy()
open(e.fake + "/failed", "w").write("fumon-thing.service loaded failed failed Something\npull-mail.service loaded failed failed Run mbsync\n")
d, j = e.jobs()
check("an unknown failed unit becomes a job, amber not red", j.get("unit:fumon-thing.service", {}).get("state") == "stale", str(j.get("unit:fumon-thing.service")))
check("a known failed unit is not listed twice", "unit:pull-mail.service" not in j)

print("case: offline")
e.healthy()
e.streak("pull-mail", 0, 2 * H)
d, j = e.jobs(online=False)
check("offline, first look: grace (healing), not red", j["pull-mail"]["state"] == "healing" and "offline" in j["pull-mail"]["why"], j["pull-mail"]["why"])
check("offline: worst stays ok", d["worst"] == "ok", d["worst"])
check("offline: an ok job says so too", "offline" in j["push-roam"]["why"], j["push-roam"]["why"])
check("offline: the local backups are untouched by it", j["matrix-backup"]["state"] == "ok" and "offline" not in j["matrix-backup"]["why"])
d, j = e.jobs(online=False, now=NOW + 10 * MIN)
check("offline 10 minutes: still in grace", j["pull-mail"]["state"] == "healing")
d, j = e.jobs(online=False, now=NOW + 50 * MIN)
check("offline 50 minutes: counts, and says why", j["pull-mail"]["state"] == "stale" and "offline for 50 min" in j["pull-mail"]["why"], j["pull-mail"]["why"])
d, j = e.jobs(online=True, now=NOW + 51 * MIN)
check("back online: judged on its own again", j["pull-mail"]["state"] == "stale" and "offline" not in j["pull-mail"]["why"], j["pull-mail"]["why"])
e.healthy()
e.streak("pull-calendars", 6, 60)
check("offline: a failing calendar sync also waits", e.jobs(online=False)[1]["pull-calendars"]["state"] == "healing")

print("case: since, options and limits")
e.healthy()
e.jobs()
e.streak("pull-mail", 4, 60)
j = e.jobs(now=NOW + 2 * MIN)[1]
check("a failing job's since is the last time it was seen working", j["pull-mail"]["since"] != "" and j["pull-mail"]["state"] == "failed", j["pull-mail"]["since"])
d, j = e.jobs("--only", "davmail")
check("--only gives one job", [x["id"] for x in d["jobs"]] == ["davmail"], str(d["jobs"]))
out = e.run("--text")
check("--text is a table with worst on top", out.startswith("worst: ") and "Mail sync" in out and "DavMail" in out, out[:200])
check("--json is the default and parses", json.loads(e.run("--json"))["worst"] in ("ok", "stale", "failed"))
check("bad option exits 2", subprocess.run([sys.executable, SH, "--nope"], capture_output=True).returncode == 2)
e.healthy()
open(e.fake + "/hang", "w").write("")
t = time.time()
d, j = e.jobs()
check("a hanging systemctl does not hang it (under 3.2 s)", e.took < 3.2 and d["worst"] in ("ok", "stale", "failed"), e.took)
check("its only write is shell-health/seen.json under the state dir", sorted(os.listdir(e.state + "/shell-health")) == ["seen.json"] and not os.path.exists(e.home + "/.local/state"), str(os.listdir(e.state + "/shell-health")))


print("case: new jobs (Teams refresh, mpd, the music card, Matrix via a fake docker)")
e.healthy()
d, j = e.jobs()
check("teams-refresh, mpd, archive and matrix are ok when healthy", states(j, "teams-refresh", "mpd", "archive", "matrix") == "teams-refresh=ok, mpd=ok, archive=ok, matrix=ok", states(j, "teams-refresh", "mpd", "archive", "matrix"))
e.unit("teams-refresh.service", active="failed", result="exit-code", status="1")
check("teams-refresh failed: failed", e.jobs()[1]["teams-refresh"]["state"] == "failed")
e.healthy()
e.unit("mpd.service", active="inactive")
check("mpd not running: failed", e.jobs()[1]["mpd"]["state"] == "failed")
e.healthy()
os.remove(e.fake + "/archive-dev")
j = e.jobs()[1]
check("music card missing: stale, says to reseat it", j["archive"]["state"] == "stale" and "reseat" in j["archive"]["why"], j["archive"]["why"])
shutil.rmtree(e.fake + "/archive")
check("no /mnt/archive at all: off", e.jobs()[1]["archive"]["state"] == "off")
e.healthy()
e.docker("synapse running unhealthy x\n")
check("synapse unhealthy: failed", e.jobs()[1]["matrix"]["state"] == "failed")

print("case: confirmation (a job is bad on two looks before it is raised)")
c100 = {"SHELL_HEALTH_CONFIRM": "100"}
e.healthy()
e.jobs(extra=c100)
e.unit("davmail.service", active="failed", result="exit-code", status="1")
d, j = e.jobs(extra=c100, now=NOW + 2 * MIN)
check("first bad look: healing, checking again", j["davmail"]["state"] == "healing" and "checking again" in j["davmail"]["why"] and d["worst"] == "ok", j["davmail"]["why"])
d, j = e.jobs(extra=c100, now=NOW + 4 * MIN)
check("second look 2 min later: failed", j["davmail"]["state"] == "failed" and d["worst"] == "failed", j["davmail"]["why"])
e.unit("davmail.service", enter=NOW - 5 * H)
check("working again: ok", e.jobs(extra=c100, now=NOW + 6 * MIN)[1]["davmail"]["state"] == "ok")
e.unit("davmail.service", active="failed", result="exit-code", status="1")
check("fails again later: confirmation starts over", e.jobs(extra=c100, now=NOW + 8 * MIN)[1]["davmail"]["state"] == "healing")
e.healthy()
e.jobs(extra=c100)
open(e.fake + "/failed", "w").write("some-thing.service loaded failed failed Something\n")
check("an unknown failed unit is confirmed too", e.jobs(extra=c100, now=NOW + 2 * MIN)[1]["unit:some-thing.service"]["state"] == "healing")

print("case: online means usable, not just a route")
for c in ("portal", "limited", "none"):
    e.healthy()
    e.streak("pull-mail", 0, 2 * H)
    j = e.jobs(extra={"SHELL_HEALTH_CONNECTIVITY": c})[1]
    check("route but connectivity %s: offline grace" % c, j["pull-mail"]["state"] == "healing" and "offline" in j["pull-mail"]["why"], j["pull-mail"]["why"])
e.healthy()
e.streak("pull-mail", 0, 2 * H)
check("NetworkManager unsure (unknown): the route decides", e.jobs(extra={"SHELL_HEALTH_CONNECTIVITY": "unknown"})[1]["pull-mail"]["state"] == "stale")

print("case: the wake grace for every network job")
e.healthy()
open(e.fake + "/mounts", "w").write("")
j = e.jobs(extra=w3)[1]
check("Box mount gone, first seen since a wake 3 min ago: healing", j["rclone-box"]["state"] == "healing" and "since waking" in j["rclone-box"]["why"], j["rclone-box"]["why"])
e.healthy()
open(e.fake + "/mounts", "w").write("")
e.jobs(now=NOW - 10 * MIN)
check("already gone before the wake: no grace, failed", e.jobs(extra=w3)[1]["rclone-box"]["state"] == "failed")
e.healthy()
e.docker("synapse running healthy x\nmautrix-teams running unhealthy x\n")
check("a bridge unhealthy right after a wake: healing", e.jobs(extra=w3)[1]["matrix"]["state"] == "healing")
e.healthy()
e.unit("mpd.service", active="inactive")
check("a local job (mpd) gets no wake grace", e.jobs(extra=w3)[1]["mpd"]["state"] == "failed")

print("case: unknown is never green")
e.healthy()
e.jobs()
e.unit("davmail.service", active="failed", result="exit-code", status="1")
e.jobs(now=NOW + 2 * MIN)
open(e.fake + "/hang", "w").write("")
d, j = e.jobs(now=NOW + 4 * MIN)
check("systemd too slow: the last known state stays, and says so", j["davmail"]["state"] == "failed" and "could not check just now" in j["davmail"]["why"] and d["worst"] == "failed", j["davmail"]["why"])
check("... and nothing turns off", all(j[i]["state"] != "off" for i in ("pull-mail", "onedrive", "rclone-box", "mpd", "teams-refresh")), states(j, "pull-mail", "onedrive", "rclone-box", "mpd", "teams-refresh"))
e.healthy()
open(e.fake + "/hang", "w").write("")
j = e.jobs()[1]
check("systemd too slow with nothing known yet: healing, could not check yet", j["davmail"]["state"] == "healing" and "could not check yet" in j["davmail"]["why"], j["davmail"]["why"])
e.healthy()
e.jobs()
open(e.fake + "/docker-hang", "w").write("")
j = e.jobs(now=NOW + 2 * MIN)[1]
check("Docker too slow: Matrix keeps its last state, not off", j["matrix"]["state"] == "ok" and "could not check" in j["matrix"]["why"], j["matrix"]["why"])

print("case: restarts are counted over the last hour")
e.healthy()
e.unit("davmail.service", enter=NOW - 5 * D, restarts="5")
j = e.jobs()[1]
check("5 restarts over its lifetime, none known recent: ok", j["davmail"]["state"] == "ok" and "restarted" not in j["davmail"]["why"], j["davmail"]["why"])
check("an hour later, still 5: ok", e.jobs(now=NOW + 61 * MIN)[1]["davmail"]["state"] == "ok")
e.unit("davmail.service", enter=NOW - 5 * D, restarts="9")
j = e.jobs(now=NOW + 62 * MIN)[1]
check("4 more within the hour: stale, says how many", j["davmail"]["state"] == "stale" and "4 times in the last hour" in j["davmail"]["why"], j["davmail"]["why"])
check("two hours on, no new ones: ok again", e.jobs(now=NOW + 3 * H)[1]["davmail"]["state"] == "ok")
e.unit("davmail.service", enter=NOW - 10, restarts="0")
check("counter back to 0 (started afresh): ok", e.jobs(now=NOW + 3 * H + MIN)[1]["davmail"]["state"] == "ok")

print("case: failed units worth no light")
e.healthy()
open(e.fake + "/failed", "w").write("dbus-:1.1-org.freedesktop.Notifications@3.service loaded failed failed x\ndesktop-test.service loaded failed failed x\nfumon-thing.service loaded failed failed x\n")
j = e.jobs()[1]
check("D-Bus activation units and desktop-test are left out", not any(k.startswith("unit:dbus-") or k == "unit:desktop-test.service" for k in j), str([k for k in j if k.startswith("unit:")]))
e.config({"ignoreUnits": ["fumon*"]})
check("health.json ignoreUnits adds globs", "unit:fumon-thing.service" not in e.jobs()[1])
e.config(None)

print("case: repairs a job made by itself")
e.healthy()
os.makedirs(e.state + "/pull-mail", exist_ok=True)
open(e.state + "/pull-mail/davmail-restarted", "w").write("%d\n0\n" % (NOW - 10 * MIN))
j = e.jobs()[1]
check("mail says DavMail was restarted and it worked", j["pull-mail"]["state"] == "ok" and "restarted DavMail itself 10 min ago, which fixed it" in j["pull-mail"]["why"], j["pull-mail"]["why"])
open(e.state + "/pull-mail/davmail-restarted", "w").write("%d\n1\n" % (NOW - 10 * MIN))
check("... or that it did not help", "did not help" in e.jobs()[1]["pull-mail"]["why"])
open(e.state + "/pull-mail/davmail-restarted", "w").write("%d\n0\n" % (NOW - 7 * H))
check("after 6 hours it is no longer mentioned", "DavMail" not in e.jobs()[1]["pull-mail"]["why"])

print("case: replay of the 2026-11-20 wake (polls every 2 min, real confirmation)")
# 08:00:16 the journal logs the wake; resumed jobs had already run at 08:00:11 with no DNS.
W = NOW
real = {"SHELL_HEALTH_CONFIRM": "100", "SHELL_HEALTH_WAKE": str(W)}
e.healthy()
e.jobs(now=W - 8 * H, extra=real)                     # healthy the evening before
e.ms("down", "token error: no reply (Temporary failure in name resolution)", 0)
e.streak("pull-mail", 0, 8 * H)                       # the cut-off run was not counted
e.streak("pull-calendars", 0, 8 * H)
e.streak("push-roam", 0, 8 * H)
open(e.fake + "/mounts", "w").write("")                # Box remounting
seen_bad = []
for k, conn in ((1, "limited"), (3, "full"), (5, "full")):
    at = W + k * MIN
    json.dump({"state": "down", "detail": "no reply (name resolution)", "checked": at - 30, "since": W - 5}, open(e.state + "/microsoft/health.json", "w"))
    if k == 5:
        e.ms("ok")
        open(e.fake + "/mounts", "w").write("%s/Box fuse.rclone\n" % e.run_dir)
        e.streak("pull-mail", 0, 30); e.streak("pull-calendars", 0, 60); e.streak("push-roam", 0, 60)
    d, j = e.jobs(now=at, extra=dict(real, SHELL_HEALTH_CONNECTIVITY=conn))
    seen_bad += ["%d min: %s" % (k, x["id"]) for x in d["jobs"] if x["state"] in ("stale", "failed")]
check("no red or amber at any poll while the laptop wakes", not seen_bad, str(seen_bad))
check("everything ok once the network is back", d["worst"] == "ok", states(j, "microsoft", "rclone-box", "pull-mail"))
e.healthy()
e.jobs(now=W - 8 * H, extra=real)
for k in (1, 3, 5, 7):
    json.dump({"state": "down", "detail": "Graph 503", "checked": W + k * MIN - 30, "since": W - 5}, open(e.state + "/microsoft/health.json", "w"))
    d, j = e.jobs(now=W + k * MIN, extra=real)
check("a real Microsoft outage that outlasts the wake is still raised", j["microsoft"]["state"] == "failed", j["microsoft"]["why"])

GB = 10 ** 9
MB = 10 ** 6


def notes(j):
    return {k: v for k, v in j.items() if v.get("state") == "notice"}


print("case: notices - updates")
e.healthy()
d, j = e.jobs()
check("no notices when nothing is waiting, and no attention", notes(j) == {} and d["attention"] == 0 and d["hidden"] == [], str(notes(j)))
e.updates([dict(id="apt", name="x", count=12, detail="12 package updates; lists from 2 days ago", cmd="sudo apt upgrade", security=0, listsAgeDays=2),
           dict(id="flatpak", name="x", count=3, detail="3 app or runtime updates (1 user and 2 system)", cmd="flatpak update"),
           dict(id="nix", name="Nix profile", count=0, detail="profile generation 6, changed 2 days ago", cmd="nix profile list")])
d, j = e.jobs()
n = notes(j)
check("plain updates are notices with kind, count, detail and cmd", n["apt"]["kind"] == "notice" and n["apt"]["count"] == 12 and n["apt"]["cmd"] == "sudo apt upgrade" and n["apt"]["detail"].startswith("12 package"), str(n.get("apt")))
check("flatpak notice present, nix (count 0) left out", "flatpak" in n and "nix" not in n, str(list(n)))
check("12 plain updates are not actionable: no attention", d["attention"] == 0 and not n["apt"]["actionable"] and not n["apt"]["say"])
check("notices never change worst", d["worst"] == "ok", d["worst"])
check("notices come after the jobs", d["jobs"][-1]["state"] == "notice" and all(x["state"] != "notice" for x in d["jobs"][:-2]), str([x["state"] for x in d["jobs"]]))
check("job rows keep the documented keys", all(set(x) == keys for x in d["jobs"] if x["state"] != "notice"))
e.updates([dict(id="apt", name="x", count=4, detail="4 package updates (1 security)", cmd="sudo apt upgrade", security=1, listsAgeDays=1)])
d, j = e.jobs()
check("a security update is actionable", j["apt"]["actionable"] and d["attention"] == 1 and d["worst"] == "ok", str(j.get("apt")))
e.updates([dict(id="apt", name="x", count=51, detail="51", cmd="c", security=0, listsAgeDays=1)])
check("more than updatesNag (50) is actionable", e.jobs()[1]["apt"]["actionable"])
e.updates([dict(id="apt", name="x", count=50, detail="50", cmd="c", security=0, listsAgeDays=1)])
check("exactly 50 is not", not e.jobs()[1]["apt"]["actionable"])
e.config({"updatesNag": 10})
e.updates([dict(id="apt", name="x", count=11, detail="11", cmd="c", security=0, listsAgeDays=1)])
check("updatesNag comes from health.json", e.jobs()[1]["apt"]["actionable"])
e.config(None)
e.updates([dict(id="apt", name="x", count=0, detail="no package updates listed; the lists are 20 days old", cmd="sudo apt update && sudo apt upgrade", security=0, listsAgeDays=20)])
d, j = e.jobs()
check("lists older than 14 days: actionable even with a count of 0", j["apt"]["actionable"] and d["attention"] == 1, str(j.get("apt")))
e.updates([dict(id="apt", name="x", count=0, detail="old", cmd="c", security=0, listsAgeDays=13)])
check("13-day-old lists with nothing waiting: no row", "apt" not in e.jobs()[1])
e.updates([dict(id="firmware", name="x", count=1, detail="UEFI dbx", cmd="fwupdmgr update")])
d, j = e.jobs()
check("firmware is a plain notice", j["firmware"]["group"] == "firmware" and not j["firmware"]["actionable"] and d["attention"] == 0)
e.updates([dict(id="reboot", name="x", count=1, detail="kernel 7.2.16 is installed, 7.2.15 is running", cmd="reboot")])
d, j = e.jobs()
check("a pending restart is actionable and may be said", j["reboot"]["actionable"] and j["reboot"]["say"] and j["reboot"]["name"] == "Restart needed" and d["worst"] == "ok", str(j.get("reboot")))
e.config({"notices": {"reboot": False, "updates": False, "firmware": True, "disk": True}})
e.updates([dict(id="reboot", name="x", count=1, detail="d", cmd="c"), dict(id="apt", name="x", count=9, detail="d", cmd="c", security=2, listsAgeDays=1),
           dict(id="firmware", name="x", count=1, detail="d", cmd="c")])
d, j = e.jobs()
check("switches per kind: reboot and updates off, firmware on", sorted(notes(j)) == ["firmware"], str(sorted(notes(j))))
e.config(None)
e.updates([])
os.remove(e.root + "/updates-fake")
d, j = e.jobs()
check("a missing updates-check is just no notices", notes(j) == {} and d["worst"] == "ok")
e.updates([])
e.config({"hidden": []})
for bad in ("{not json", "[1,2]", '{"updatesNag": "many", "notices": 5, "hidden": "x"}'):
    open(e.root + "/health.json", "w").write(bad)
    check("a broken health.json falls back to the defaults: %s" % bad[:12], e.jobs()[0]["worst"] == "ok")
e.config(None)

print("case: notices - disk")
e.healthy()
e.disks({
    "/": dict(fstype="ext4", total=220 * GB, free=41 * GB),
    "/boot/efi": dict(fstype="vfat", total=511 * MB, free=61 * MB),
    "/mnt/data": dict(fstype="ext4", total=916 * GB, free=111 * GB),
    "/mnt/archive": dict(fstype="ext4", total=448 * GB, free=76 * GB),
    "/run/user/1000/Box": dict(fstype="fuse.rclone", total=8 * 10 ** 18, free=0),
    "/dev/shm": dict(fstype="tmpfs", total=10 * GB, free=0), "/snap/core/1": dict(fstype="squashfs", total=GB, free=0),
    "/mnt/nas": dict(fstype="nfs4", total=GB, free=0), "/var/lib/docker/overlay2/x/merged": dict(fstype="overlay", total=GB, free=0)})
d, j = e.jobs()
check("healthy disks (ESP with 61 MB free is fine) make no rows; tmpfs, squashfs, FUSE, nfs, overlay are never asked", notes(j) == {} and d["attention"] == 0, str(list(notes(j))))
e.disks({"/": dict(fstype="ext4", total=220 * GB, free=15 * GB)})
check("15 GB of 220 free (6.8%) is under 10%: warn", "disk:/" in e.jobs()[1])
e.disks({"/": dict(fstype="ext4", total=220 * GB, free=30 * GB)})
check("30 GB of 220 free (13.6%) is fine", "disk:/" not in e.jobs()[1])
e.disks({"/mnt/archive": dict(fstype="ext4", total=448 * GB, free=4 * GB)})
d, j = e.jobs()
check("under 5 GB free warns even at 1%; reading, cmd, actionable, say", j["disk:/mnt/archive"]["actionable"] and j["disk:/mnt/archive"]["say"] and "4.0 GB free of 448.0 GB (1%)" in j["disk:/mnt/archive"]["why"]
      and j["disk:/mnt/archive"]["cmd"].startswith("df -h /mnt/archive") and j["disk:/mnt/archive"]["name"] == "Low disk space: /mnt/archive", str(j.get("disk:/mnt/archive")))
check("low disk is never amber or red", d["worst"] == "ok" and d["attention"] == 1)
e.disks({"/boot/efi": dict(fstype="vfat", total=511 * MB, free=19 * MB)})
check("ESP under 20 MB warns", "disk:/boot/efi" in e.jobs()[1])
e.disks({"/boot/efi": dict(fstype="vfat", total=511 * MB, free=20 * MB)})
check("ESP at 20 MB does not", "disk:/boot/efi" not in e.jobs()[1])
e.config({"diskPercent": 2, "diskGB": 1, "espMB": 50})
e.disks({"/": dict(fstype="ext4", total=220 * GB, free=15 * GB), "/boot/efi": dict(fstype="vfat", total=511 * MB, free=40 * MB)})
d, j = e.jobs()
check("thresholds come from health.json", "disk:/" not in j and "disk:/boot/efi" in j, str(list(notes(j))))
e.config({"notices": {"disk": False}})
check("the disk switch turns the rows off", notes(e.jobs()[1]) == {})
e.config(None)
e.disks({"/": dict(fstype="ext4", total=220 * GB, free=1 * GB, dev="a"), "/home": dict(fstype="ext4", total=220 * GB, free=1 * GB, dev="a")})
check("two mounts of one device are one row", len(notes(e.jobs()[1])) == 1)
open(e.root + "/disks.json", "w").write("{bad")
check("a broken table is no rows", notes(e.jobs()[1]) == {})
os.remove(e.root + "/disks.json")
real = e.run(extra={"SHELL_HEALTH_DISKS": ""})
check("the real statvfs path runs and lists no tmpfs or FUSE (mountinfo read for real)", all(x["id"].startswith("disk:") is False or x["id"].split(":", 1)[1] in ("/", "/home", "/boot", "/boot/efi") or x["id"].startswith("disk:/mnt/") or x["id"].startswith("disk:/media/")
      for x in json.loads(real)["jobs"] if x["state"] == "notice"), real[:300])
e.disks({})

print("case: hidden jobs and notices")
e.healthy()
e.streak("pull-mail", 4, 60)
e.updates([dict(id="reboot", name="x", count=1, detail="d", cmd="c")])
d, j = e.jobs()
check("before hiding: failing job, worst failed, restart notice", d["worst"] == "failed" and "pull-mail" in j and "reboot" in j)
e.config({"hidden": ["pull-mail", "reboot", "nope"]})
d, j = e.jobs()
check("hidden job leaves the list and worst", "pull-mail" not in j and d["worst"] == "ok", d["worst"])
check("hidden notice leaves the list and attention", "reboot" not in j and d["attention"] == 0)
check("hidden reports id and name (so settings can offer them back), unknown ids dropped", sorted(h["id"] for h in d["hidden"]) == ["pull-mail", "reboot"] and
      [h["name"] for h in d["hidden"] if h["id"] == "pull-mail"] == ["Mail sync"], str(d["hidden"]))
check("--only a hidden id gives nothing", e.jobs("--only", "pull-mail")[0]["jobs"] == [])
check("--text leaves it out", "Mail sync" not in e.run("--text"))
e.config({"hidden": ["davmail"]})
d, j = e.jobs()
check("hiding an ok job leaves the others alone", "davmail" not in j and d["worst"] == "failed" and "pull-mail" in j)
e.config(None)
e.streak("pull-mail", 0, 60)
text = e.run("--text")
e.updates([dict(id="apt", name="x", count=4, detail="4 package updates (1 security)", cmd="c", security=1, listsAgeDays=1)])
text = e.run("--text")
check("--text lists notices as NOTICE", "NOTICE" in text and "worth a look" in text, text[-300:])
e.updates([])

shutil.rmtree(e.root, ignore_errors=True)
print("SCRIPT RESULT pass %d fail %d" % (passed, failed))
sys.exit(1 if failed else 0)
