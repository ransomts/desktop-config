#!/usr/bin/python3 -I
"""data-test harness: runs one PART of the data-test suite (see ~/.local/bin/data-test).

    harness.py PART        PART: dashboard shellstatus shelllog teams gameday petscore
                                 keystats mousestats cursorshake droppreview keybind

Environment (set by data-test): DT_BIN (scripts under test), DT_DIR (this part's temporary
directory: stubs read their answers from it and log to DT_DIR/calls.log), DT_FIX (fixtures),
HOME / XDG_* (temporary). Prints PASS/FAIL lines only. Scripts are imported or run in this
process with urllib, sockets, select, time and evdev replaced, or run as subprocesses against
the stubs first on PATH; nothing here reaches the network, Hyprland or a real device.
"""
import contextlib, datetime as _dt, importlib.machinery, importlib.util, io, json, os, re, runpy
import shutil, signal, socket, subprocess, sys, threading, time, traceback, types
import urllib.request

BIN = os.environ["DT_BIN"]
D = os.environ["DT_DIR"]
FIX = os.environ["DT_FIX"]
HOME = os.environ["HOME"]
os.makedirs(D, exist_ok=True)
time.tzset()

# Safety net: no name resolution except loopback, whatever the code under test tries.
_real_gai = socket.getaddrinfo
def _gai(host, *a, **k):
    if host not in ("127.0.0.1", "localhost", "::1"):
        raise OSError("data-test: no network (%s)" % host)
    return _real_gai(host, *a, **k)
socket.getaddrinfo = _gai


def check(name, cond, detail=""):
    if cond:
        print("PASS " + name, flush=True)
    else:
        print("FAIL %s   [%s]" % (name, " ".join(str(detail).split())[:400]), flush=True)
    return bool(cond)


def case(title):
    print("case: " + title, flush=True)


def wfile(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(data if isinstance(data, str) else json.dumps(data))


def calls():
    try:
        return open(os.path.join(D, "calls.log")).read().splitlines()
    except OSError:
        return []


def clear_calls():
    open(os.path.join(D, "calls.log"), "w").close()


def jparse(text):
    try:
        return json.loads(text)
    except ValueError:
        return None


def load(name, argv=("--data-test-no-command",)):
    """Import a script as a module. A module-level sys.exit (usage) is swallowed."""
    path = os.path.join(BIN, name)
    loader = importlib.machinery.SourceFileLoader("dt_" + re.sub(r"\W", "_", name), path)
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    old = sys.argv
    sys.argv = [path, *argv]
    try:
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            try:
                loader.exec_module(mod)
            except SystemExit:
                pass
    finally:
        sys.argv = old
    return mod


def run_inproc(name, argv=(), stdout=None):
    """Run a script as __main__ in this process: (stdout, exit code or "crash", stderr)."""
    path = os.path.join(BIN, name)
    out, err, code = stdout or io.StringIO(), io.StringIO(), 0
    old = sys.argv
    sys.argv = [path, *argv]
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                runpy.run_path(path, run_name="__main__")
            except SystemExit as e:
                code = e.code if isinstance(e.code, int) else (0 if e.code is None else 1)
            except BaseException:
                traceback.print_exc()
                code = "crash"
    finally:
        sys.argv = old
    return (out.getvalue() if hasattr(out, "getvalue") else ""), code, err.getvalue()


def run(argv, env=None, timeout=60):
    e = dict(os.environ)
    e.update(env or {})
    return subprocess.run(argv, capture_output=True, text=True, timeout=timeout, env=e)


class Net:
    """Stands in for urllib.request.urlopen: routes are URL substrings -> bytes, JSON or an exception."""
    def __init__(self):
        self.routes, self.calls = {}, []

    def __call__(self, url, timeout=None, **kw):
        u = url if isinstance(url, str) else url.full_url
        self.calls.append(u)
        for k, v in self.routes.items():
            if k in u:
                if isinstance(v, BaseException):
                    raise v
                return io.BytesIO(v if isinstance(v, bytes) else json.dumps(v).encode())
        raise OSError("data-test: network down (%s)" % u)


# =====================================================================================
def part_dashboard():
    net = Net()
    urllib.request.urlopen = net
    cache = os.path.join(os.environ["XDG_CACHE_HOME"], "dashboard-weather.json")

    case("dashboard-data sys")
    out, code, err = run_inproc("dashboard-data", ["sys"])
    s = jparse(out)
    check("sys: one JSON object, exit 0", isinstance(s, dict) and code == 0, out + err)
    s = s if isinstance(s, dict) else {}
    need = {"cpu", "mem", "mem_gb", "mem_total_gb", "temp", "load", "uptime", "disks"}
    check("sys: every field Dashboard.qml and PetSay.qml read", need <= set(s), sorted(s))
    check("sys: cpu and mem are fractions 0..1",
          all(isinstance(s.get(k), (int, float)) and 0 <= s[k] <= 1 for k in ("cpu", "mem")), s)
    disks = s.get("disks") or []
    check("sys: disks are {name, used 0..1, free_gb}, System first",
          disks and disks[0].get("name") == "System" and all(
              {"name", "used", "free_gb"} <= set(d) and 0 <= d["used"] <= 1 for d in disks), disks)
    check("sys: uptime reads like '3h 12m' or '2d 4h'", re.fullmatch(r"\d+(h \d+m|d \d+h)", str(s.get("uptime"))), s.get("uptime"))
    out, code, _ = run_inproc("dashboard-data", [])
    check("no argument means sys", code == 0 and need <= set(jparse(out) or {}), out)
    out, code, _ = run_inproc("dashboard-data", ["bogus"])
    check("unknown argument: usage, exit non-zero, nothing on stdout", code not in (0, "crash") and out == "", (code, out))

    mod = load("dashboard-data")
    mod.DISKS = [("System", "/"), ("Gone", "/nonexistent-data-test/x")]
    check("a disk that is not mounted is left out, not an error", [d["name"] for d in mod.sys_state()["disks"]] == ["System"])
    real_read = mod.read
    for secs, want in (("93784.5 1", "1d 2h"), ("3700.2 1", "1h 1m"), ("59 1", "0h 0m")):
        mod.read = lambda p, d="", v=secs: v if p == "/proc/uptime" else real_read(p, d)
        got = mod.sys_state()["uptime"]
        check("uptime %s s -> %s" % (secs.split()[0], want), got == want, got)
    mod.read = lambda p, d="": "acpitz\n" if p.endswith("/type") else real_read(p, d)
    check("no x86_pkg_temp zone: temp 0", mod.sys_state()["temp"] == 0)
    mod.read = real_read

    case("dashboard-data weather")
    om = {"current": {"temperature_2m": 61.6, "apparent_temperature": 59.2, "weather_code": 2, "wind_speed_10m": 7.4,
                      "relative_humidity_2m": 55.0, "is_day": 0},
          "daily": {"time": ["2026-11-18", "2026-11-19", "2026-11-20", "2026-11-21"], "weather_code": [2, 61, 0, 95],
                    "temperature_2m_max": [64.4, 58.0, 55.2, 70.0], "temperature_2m_min": [40.2, 44.0, 38.0, 50.0],
                    "precipitation_probability_max": [None, 80, 0, 60],
                    "sunrise": ["2026-11-18T07:05", "2026-11-19T07:06", "2026-11-20T07:07", "2026-11-21T07:08"],
                    "sunset": ["2026-11-18T17:22", "2026-11-19T17:21", "2026-11-20T17:21", "2026-11-21T17:20"]}}
    net.routes = {"api.open-meteo.com": om}
    w = mod.weather()
    want = {"ok": True, "temp": 62, "feels": 59, "words": "Partly cloudy", "glyph": mod.PARTLY_N, "wind": 7, "humidity": 55,
            "sunrise": "07:05", "sunset": "17:22"}
    check("weather: the fields the dashboard shows, rounded; night glyph after dark",
          all(w.get(k) == v for k, v in want.items()), {k: w.get(k) for k in want})
    days = w.get("days") or []
    check("weather: four days, Today then weekday names", [d.get("name") for d in days] == ["Today", "Thu", "Fri", "Sat"], days)
    check("weather: day fields hi/lo/rain/words/glyph (rain null -> 0)",
          days and days[0]["rain"] == 0 and days[1]["words"] == "Rain" and days[1]["hi"] == 58 and days[3]["words"] == "Thunderstorm"
          and all({"name", "glyph", "words", "hi", "lo", "rain"} <= set(d) for d in days), days)
    check("weather: the request is for Clemson in fahrenheit", net.calls and "latitude=34.68" in net.calls[-1] and "fahrenheit" in net.calls[-1], net.calls)
    check("weather: answer cached", jparse(open(cache).read()) == w if os.path.exists(cache) else False)
    n = len(net.calls)
    net.routes = {}
    w2 = mod.weather()
    check("weather: a cache under 20 minutes old is used, nothing fetched", w2 == w and len(net.calls) == n, (len(net.calls), n))
    old = time.time() - 30 * 60
    os.utime(cache, (old, old))
    w3 = mod.weather()
    check("weather: old cache + network down -> last answer marked stale", w3.get("ok") is True and w3.get("stale") is True and w3.get("temp") == 62, w3)
    os.utime(cache, (old, old))
    net.routes = {"api.open-meteo.com": b"<html>502 Bad Gateway</html>"}
    w4 = mod.weather()
    check("weather: garbage from the API + old cache -> stale cache", w4.get("stale") is True, w4)
    os.remove(cache)
    check("weather: garbage and no cache -> {ok: false}", mod.weather() == {"ok": False})
    net.routes = {}
    check("weather: network down and no cache -> {ok: false}", mod.weather() == {"ok": False})
    net.routes = {"api.open-meteo.com": {"daily": om["daily"]}}
    check("weather: answer missing 'current' -> {ok: false}", mod.weather() == {"ok": False})
    wfile(cache, "{not json")
    net.routes = {"api.open-meteo.com": dict(om, current=dict(om["current"], weather_code=1234, is_day=1))}
    w5 = mod.weather()
    check("weather: a corrupt cache is ignored and refetched; unknown code -> no words, cloud glyph",
          w5.get("ok") is True and w5.get("words") == "" and w5.get("glyph") == mod.CLOUD, w5)
    net.routes = {"api.open-meteo.com": om}
    os.remove(cache)
    net.routes = {"api.open-meteo.com": dict(om, current=dict(om["current"], is_day=1))}
    check("weather: daytime glyph by day", mod.weather().get("glyph") == mod.PARTLY)
    net.routes = {"api.open-meteo.com": om}

    case("dashboard-data mail")
    clem = "".join('2026-11-18 09:0%d\t"Doe, Jane" <jane%d@clemson.edu>\tSubject %d\twith a tab\n' % (i, i, i) for i in range(8))
    clem += "a line without tabs\n"
    wfile(D + "/mu/clemson.txt", clem)
    wfile(D + "/mu/personal.txt", "2026-11-17 20:00\t<shop@example.com>\tYour order\n")
    clear_calls()
    m = mod.mail()
    check("mail: unread per inbox, in order", m.get("boxes") == [{"name": "Clemson", "unread": 8}, {"name": "Personal", "unread": 1}], m.get("boxes"))
    lat = m.get("latest") or []
    check("mail: at most 6 latest per inbox", [x["box"] for x in lat].count("Clemson") == 6 and [x["box"] for x in lat].count("Personal") == 1, len(lat))
    check("mail: sender name without the address, subject keeps its tab",
          lat and lat[0] == {"box": "Clemson", "date": "2026-11-18 09:00", "from": "Doe, Jane", "subject": "Subject 0\twith a tab"}, lat[:1])
    check("mail: a sender with no name keeps the address", lat and lat[-1]["from"] == "<shop@example.com>", lat[-1:])
    mus = [c for c in calls() if c.startswith("mu ")]
    check("mail: asks mu for unread, untrashed, per INBOX",
          len(mus) == 2 and all("flag:unread AND NOT flag:trashed" in c for c in mus) and "/work/INBOX" in mus[0], mus)
    wfile(D + "/mu/fail", "")
    m = mod.mail()
    check("mail: mu failing -> zero counts, no latest", m == {"boxes": [{"name": "Clemson", "unread": 0}, {"name": "Personal", "unread": 0}], "latest": []}, m)
    os.remove(D + "/mu/fail")
    real_which = shutil.which
    shutil.which = lambda *a, **k: None
    try:
        m = mod.mail()
    finally:
        shutil.which = real_which
    check("mail: no mu at all -> empty boxes and latest (the dashboard says 'No mail index')", m == {"boxes": [], "latest": []}, m)

    case("dashboard-data tomorrow")
    tool = HOME + "/.local/bin/agenda-day"
    wfile(tool, '#!/bin/sh\necho "$1" >> "%s/agenda.log"\n/bin/cat "%s/agenda.json"\n' % (D, D))
    os.chmod(tool, 0o755)
    ev = [{"start": "09:00", "end": "10:00", "title": "CPSC 1010", "allday": False}]
    wfile(D + "/agenda.json", ev)
    day = _dt.date.today() + _dt.timedelta(days=1)
    t = mod.tomorrow()
    check("tomorrow: weekday name and agenda-day's events", t == {"name": day.strftime("%A"), "events": ev}, t)
    check("tomorrow: agenda-day asked for tomorrow's date", open(D + "/agenda.log").read().split()[-1:] == [day.isoformat()])
    wfile(D + "/agenda.json", "Traceback (most recent call last):\n")
    check("tomorrow: garbage from agenda-day -> no events", mod.tomorrow() == {"name": day.strftime("%A"), "events": []})
    os.remove(tool)
    check("tomorrow: no agenda-day -> no events", mod.tomorrow() == {"name": day.strftime("%A"), "events": []})

    case("dashboard-data feeds (whole output)")
    def shape(f):
        try:
            w, m, t = f["weather"], f["mail"], f["tomorrow"]
            return (isinstance(w.get("ok"), bool) and isinstance(m["boxes"], list) and isinstance(m["latest"], list)
                    and all(isinstance(b["name"], str) and isinstance(b["unread"], int) for b in m["boxes"])
                    and isinstance(t["name"], str) and isinstance(t["events"], list))
        except (KeyError, TypeError, AttributeError):
            return False
    wfile(tool, '#!/bin/sh\n/bin/cat "%s/agenda.json"\n' % D)
    os.chmod(tool, 0o755)
    wfile(D + "/agenda.json", ev)
    net.routes = {"api.open-meteo.com": om}
    out, code, err = run_inproc("dashboard-data", ["feeds"])
    f = jparse(out)
    check("feeds: everything working -> weather, mail, tomorrow in the dashboard's shape",
          code == 0 and f and shape(f) and f["weather"]["ok"] and f["mail"]["boxes"][0]["unread"] == 8, out[:200] + err)
    os.remove(cache)
    net.routes = {"api.open-meteo.com": b"\x00garbage"}
    wfile(D + "/mu/fail", "")
    wfile(D + "/agenda.json", "nope")
    out, code, err = run_inproc("dashboard-data", ["feeds"])
    f = jparse(out)
    check("feeds: garbage weather, failing mu, garbage agenda -> still valid JSON, same shape",
          code == 0 and f and shape(f) and f["weather"] == {"ok": False}, out[:200] + err)
    os.remove(D + "/mu/fail")


# =====================================================================================
def part_shellstatus():
    def ss(what, **env):
        r = run([sys.executable, os.path.join(BIN, "shell-status"), what], env)
        return r, jparse(r.stdout)

    def ok3(o):
        return isinstance(o, dict) and set(o) == {"text", "tooltip", "class"} and all(isinstance(v, str) for v in o.values())

    mu = HOME + "/.local/bin/mu"
    os.makedirs(os.path.dirname(mu), exist_ok=True)
    shutil.copy(os.path.join(os.environ["DT_STUBS"], "mu"), mu)

    case("shell-status clock")
    wfile(D + "/dconf/plain", "'Grading: lab 5 <b> & co'\n")
    r, o = ss("clock")
    check("clock: one {text, tooltip, class} object, exit 0", ok3(o) and r.returncode == 0, r.stdout + r.stderr)
    o = o or {}
    check("clock running: text ends with the clock, class on", o.get("text", "").endswith(" Grading: lab 5 <b> & co") and o.get("class") == "on", o)
    check("clock tooltip escapes & and <", "Grading: lab 5 &lt;b> &amp; co" in o.get("tooltip", ""), o.get("tooltip"))
    wfile(D + "/dconf/plain", "'" + "x" * 60 + "'")
    r, o = ss("clock")
    t = (o or {}).get("text", "")
    check("a long clock is cut to 48 characters with an ellipsis", t.endswith("x" * 47 + "…") and "x" * 48 not in t, t)
    wfile(D + "/dconf/plain", "'No active clock'")
    wfile(D + "/dconf/cosmic", "'Meeting prep'")
    clear_calls()
    r, o = ss("clock")
    check("clock only in the COSMIC dconf profile is found too", (o or {}).get("text", "").endswith("Meeting prep"), o)
    check("both profiles asked", any("profile=/usr/share/dconf/profile/cosmic" in c for c in calls()), calls())
    os.remove(D + "/dconf/cosmic")
    r, o = ss("clock")
    check("'No active clock' everywhere: empty text (pill hidden)", o == {"text": "", "tooltip": "", "class": ""}, o)
    wfile(D + "/dconf/fail", "")
    r, o = ss("clock")
    check("dconf failing: empty, still valid JSON", o == {"text": "", "tooltip": "", "class": ""} and r.returncode == 0, r.stdout)
    os.remove(D + "/dconf/fail")

    case("shell-status mail")
    wfile(D + "/mu/clemson.txt", "/m/1\n/m/2\n\n/m/3\n")
    wfile(D + "/mu/personal.txt", "")
    r, o = ss("mail")
    check("mail: total in the text, class on", ok3(o) and o["text"].endswith(" 3") and o["class"] == "on", r.stdout)
    check("mail tooltip names only inboxes with mail", o and "Clemson 3" in o["tooltip"] and "Personal" not in o["tooltip"], o)
    wfile(D + "/mu/clemson.txt", "")
    r, o = ss("mail")
    check("no unread: empty", o == {"text": "", "tooltip": "", "class": ""}, r.stdout)
    os.remove(mu)
    r, o = ss("mail")
    check("no mu at all: empty, valid JSON, exit 0", o == {"text": "", "tooltip": "", "class": ""} and r.returncode == 0, r.stdout + r.stderr)

    case("shell-status tailscale")
    ts = {"BackendState": "Running", "ExitNodeStatus": None, "Peer": {"k1": {"ID": "n1", "HostName": "homeserver"}}}
    wfile(D + "/tailscale.json", ts)
    r, o = ss("tailscale")
    check("running, no exit node: class on, no text (bar hides it)", ok3(o) and o["class"] == "on" and o["text"] == "", r.stdout)
    wfile(D + "/tailscale.json", dict(ts, ExitNodeStatus={"ID": "n1"}))
    r, o = ss("tailscale")
    check("exit node in use: its host name", o and o["text"] == "homeserver" and "all traffic through homeserver" in o["tooltip"], o)
    wfile(D + "/tailscale.json", dict(ts, ExitNodeStatus={"ID": "gone"}))
    r, o = ss("tailscale")
    check("exit node not among the peers: 'exit node'", o and o["text"] == "exit node", o)
    wfile(D + "/tailscale.json", dict(ts, BackendState="Stopped"))
    r, o = ss("tailscale")
    check("stopped: class off", o and o["class"] == "off" and o["text"] == "", o)
    wfile(D + "/tailscale.json", "not json {")
    r, o = ss("tailscale")
    check("garbage from tailscale: off, valid JSON", ok3(o) and o["class"] == "off", r.stdout + r.stderr)
    os.remove(D + "/tailscale.json")
    r, o = ss("tailscale")
    check("tailscale failing: off, valid JSON", ok3(o) and o["class"] == "off" and r.returncode == 0, r.stdout + r.stderr)

    case("shell-status night")
    for val, want in (("4500", ("4500", "on")), ("6000", ("6000", "off")), ("5899.6", ("5899", "on"))):
        wfile(D + "/hypr/hyprsunset", val + "\n")
        r, o = ss("night")
        check("hyprsunset %s -> text %s class %s" % (val, *want), ok3(o) and (o["text"], o["class"]) == want, r.stdout)
    wfile(D + "/hypr/hyprsunset", "couldn't connect to hyprsunset\n")
    r, o = ss("night")
    check("hyprsunset not running: off, valid JSON", o == {"text": "", "tooltip": "", "class": "off"}, r.stdout)
    os.remove(D + "/hypr/hyprsunset")
    r, o = ss("night")
    check("hyprctl failing: off, valid JSON", o == {"text": "", "tooltip": "", "class": "off"}, r.stdout)

    case("shell-status usage")
    r, _ = ss("bogus")
    check("unknown source: usage on stderr, exit non-zero, nothing on stdout", r.returncode != 0 and r.stdout == "" and "shell-status" in r.stderr, (r.returncode, r.stdout))


# =====================================================================================
def part_shelllog():
    mod = load("shell-log")
    sent = []
    mod.journal_send = lambda fields: sent.append(dict(fields))
    state = os.environ["XDG_STATE_HOME"]
    arch = os.path.join(state, "shell-messages.jsonl")

    def last():
        try:
            return json.loads(open(arch).read().splitlines()[-1])
        except (OSError, IndexError, ValueError):
            return None

    case("shell-log notification")
    rc = mod.main(["shell-log", "notification", "New message", "Hi\nthere", "app=Element", "outcome=shown", "urgency=critical", "transient=no"])
    f = sent[-1] if sent else {}
    check("exit 0", rc == 0, rc)
    check("journal: identifier, one-line MESSAGE with the app", f.get("SYSLOG_IDENTIFIER") == "notification" and f.get("MESSAGE") == "[Element] New message: Hi there", f)
    check("journal: critical -> priority 4 (warning)", f.get("PRIORITY") == "4", f.get("PRIORITY"))
    check("journal: MSG_TITLE, MSG_BODY and one MSG_ field per key",
          f.get("MSG_TITLE") == "New message" and f.get("MSG_BODY") == "Hi\nthere" and f.get("MSG_APP") == "Element"
          and f.get("MSG_OUTCOME") == "shown" and f.get("MSG_TRANSIENT") == "no", f)
    e = last() or {}
    check("archive: one JSON line with kind, title, body and the keys",
          e.get("kind") == "notification" and e.get("title") == "New message" and e.get("body") == "Hi\nthere" and e.get("app") == "Element"
          and re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d{4}", e.get("at", "")), e)
    check("archive is private (0600)", os.stat(arch).st_mode & 0o777 == 0o600, oct(os.stat(arch).st_mode))
    mod.main(["shell-log", "notification", "Plain", "", "app=", "urgency=normal"])
    check("empty body and app: MESSAGE is just the title, priority 5", sent[-1]["MESSAGE"] == "Plain" and sent[-1]["PRIORITY"] == "5", sent[-1])
    mod.main(["shell-log", "notification", "", ""])
    check("nothing at all: MESSAGE '(empty)'", sent[-1]["MESSAGE"] == "(empty)", sent[-1])
    # Notif.qml always passes the body as the 4th argument: a body that looks like key=value is still the body
    mod.main(["shell-log", "notification", "CI", "build=green", "app=Gitea", "urgency=low"])
    check("a body of the form word=value stays the body (Notif.qml passes it positionally)",
          sent[-1].get("MSG_BODY") == "build=green" and sent[-1].get("PRIORITY") == "6", {k: sent[-1].get(k) for k in ("MSG_BODY", "MSG_BUILD", "PRIORITY")})

    case("shell-log island")
    mod.main(["shell-log", "island", "Wi-Fi", "", "source=net"])
    f = sent[-1]
    check("island (as Island.qml calls it): source field, empty body, priority 6",
          f["SYSLOG_IDENTIFIER"] == "island" and f["MSG_BODY"] == "" and f["MSG_SOURCE"] == "net" and f["PRIORITY"] == "6", f)
    mod.main(["shell-log", "island", "T", "B", "bad-key=x", "title=override"])
    e = last()
    check("keys that are not identifiers are dropped; a key never overwrites title/body/kind in the archive",
          "MSG_BAD-KEY" not in sent[-1] and e["title"] == "T" and e["kind"] == "island", (sent[-1], e))
    check("an extra never overwrites MSG_TITLE/MSG_BODY in the journal", sent[-1]["MSG_TITLE"] == "T" and sent[-1]["MSG_BODY"] == "B", sent[-1])
    mod.main(["shell-log", "island", "T", "body=x"])
    check("the 4th argument is always the body, even when it looks like key=value", sent[-1]["MSG_BODY"] == "body=x" and "MSG_BODY=" not in str(sent[-1]), sent[-1])

    case("shell-log usage and failures")
    n = len(sent)
    with contextlib.redirect_stderr(io.StringIO()):
        rc1 = mod.main(["shell-log", "bogus", "x"])
        rc2 = mod.main(["shell-log", "notification"])
    check("unknown kind or no title: exit 2, nothing recorded", rc1 == 2 and rc2 == 2 and len(sent) == n, (rc1, rc2))
    def boom(fields):
        raise OSError("no journal")
    mod.journal_send = boom
    os.environ["XDG_STATE_HOME"] = "/nonexistent-data-test/state"
    try:
        rc = mod.main(["shell-log", "notification", "x"])
    except Exception as ex:
        rc = repr(ex)
    os.environ["XDG_STATE_HOME"] = state
    check("no journal and no writable archive: still exit 0, no exception", rc == 0, rc)

    class FakeDgram:
        got = []
        def __init__(self, *a): pass
        def __enter__(self): return self
        def __exit__(self, *a): return False
        def sendto(self, data, addr): FakeDgram.got.append((data, addr))
    real = mod.socket.socket
    mod.socket.socket = FakeDgram
    try:
        load("shell-log").journal_send({"MESSAGE": "one", "MSG_BODY": "two\nlines"})
    finally:
        mod.socket.socket = real
    data, addr = FakeDgram.got[-1] if FakeDgram.got else (b"", "")
    check("journal wire format: KEY=value, multi-line values length-prefixed, to the journal socket",
          addr == "/run/systemd/journal/socket" and data == b"MESSAGE=one\nMSG_BODY\n" + (9).to_bytes(8, "little") + b"two\nlines\n", data)


# =====================================================================================
def part_teams():
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    from urllib.parse import urlparse, parse_qs, unquote

    class Srv:
        reqs, syncs, profiles = [], [], {"@bob:localhost": "Bob Builder"}
    class H(BaseHTTPRequestHandler):
        def do_GET(self):
            u = urlparse(self.path)
            Srv.reqs.append((u.path, parse_qs(u.query), self.headers.get("Authorization")))
            if u.path.endswith("/sync"):
                status, body = Srv.syncs.pop(0) if Srv.syncs else (200, {"next_batch": "sN"})
            elif "/profile/" in u.path:
                who = unquote(u.path.rsplit("/", 1)[1])
                status, body = (200, {"displayname": Srv.profiles[who]}) if who in Srv.profiles else (404, {"errcode": "M_NOT_FOUND"})
            else:
                status, body = 404, {}
            data = body if isinstance(body, bytes) else json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        def log_message(self, *a):
            pass
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    port = httpd.server_address[1]

    sessions = HOME + "/.emacs.d/var/ement-sessions.el"
    wfile(sessions, '(("@someone:localhost" . #s(ement-session :user #s(ement-user :id "@someone:localhost") :token "WRONG"))\n'
                    ' (#1="@user:localhost" . #s(ement-session :user #s(ement-user :id #1#) :server #s(ement-server)\n'
                    '   :token "TOK-123" :transaction-id 5)))\n')
    mod = load("teams-unread")
    mod.HOMESERVER = "http://127.0.0.1:%d" % port
    mod.SESSIONS = sessions
    check("the state file lives in the (temporary) runtime directory", mod.STATE == os.path.join(os.environ["XDG_RUNTIME_DIR"], "teams-unread.json"), mod.STATE)

    def bridge(proto="msteams"):
        return {"type": "m.bridge", "state_key": "x", "content": {"protocol": {"id": proto}}}
    def msg(sender, body, ts, kind="m.text"):
        return {"type": "m.room.message", "sender": sender, "origin_server_ts": ts, "content": {"msgtype": kind, "body": body}}
    def room(state=(), timeline=(), count=None, hl=0, heroes=None):
        r = {"state": {"events": list(state)}, "timeline": {"events": list(timeline)}}
        if count is not None:
            r["unread_notifications"] = {"notification_count": count, "highlight_count": hl}
        if heroes:
            r["summary"] = {"m.heroes": heroes}
        return r
    first = {"next_batch": "s1", "rooms": {"join": {
        "!a:localhost": room([bridge(), {"type": "m.room.name", "state_key": "", "content": {"name": "Project <X> & Co"}},
                              {"type": "m.room.member", "state_key": "@alice:localhost", "content": {"displayname": "Alice"}}],
                             [msg("@alice:localhost", "hello\nworld", 1000)], count=2, hl=1),
        "!dm:localhost": room([bridge()], [msg("@bob:localhost", "pic.png", 2000, "m.image")], count=1, heroes=["@bob:localhost"]),
        "!m:localhost": room([bridge("signal")], [msg("@x:localhost", "not teams", 3000)], count=5),
        "!z:localhost": room([bridge()], [msg("@y:localhost", "read", 500)], count=0),
        "!me:localhost": room([bridge(), {"type": "m.room.name", "state_key": "", "content": {"name": "DM: Notes"}}],
                              [msg("@user:localhost", "my own", 4000)], count=1)}}}

    case("teams-unread status")
    Srv.reqs.clear(); Srv.syncs[:] = [(200, first)]
    o = mod.status()
    check("unread Teams chats: {text, tooltip, class, rooms}", isinstance(o, dict) and {"text", "tooltip", "class", "rooms"} <= set(o), o)
    o = o or {"rooms": [], "text": "", "class": "", "tooltip": ""}
    check("text is the total over Teams chats only (other bridges and read chats left out)", o["text"].endswith(" 4"), o["text"])
    check("a mention makes the class 'mention'", o["class"] == "mention", o["class"])
    rooms = o["rooms"]
    check("rooms: newest first, with id/name/count/mentions/preview/ts",
          [r["id"] for r in rooms] == ["!dm:localhost", "!a:localhost", "!me:localhost"]
          and all({"id", "name", "count", "mentions", "preview", "ts"} <= set(r) for r in rooms), rooms)
    by = {r["id"]: r for r in rooms}
    check("a DM is named after the other person (profile lookup)", by.get("!dm:localhost", {}).get("name") == "Bob Builder", by.get("!dm:localhost"))
    check("a picture previews as [picture]; the sender is not repeated in a DM", by.get("!dm:localhost", {}).get("preview") == "[picture]", by.get("!dm:localhost"))
    check("group chat preview: sender name and one-line body", by.get("!a:localhost", {}).get("preview") == "Alice: hello world", by.get("!a:localhost"))
    check("'DM: ' prefix dropped from a name", by.get("!me:localhost", {}).get("name") == "Notes", by.get("!me:localhost"))
    check("tooltip: totals and the mention count", o["tooltip"].startswith("<b>Teams</b>: 4 unread in 3 chats, 1 mentioning you"), o["tooltip"][:80])
    check("tooltip escapes room names", "Project &lt;X&gt; &amp; Co (2)" in o["tooltip"], o["tooltip"])
    sync = [r for r in Srv.reqs if r[0].endswith("/sync")]
    check("first run: one filtered initial sync with the saved token, timeout 0, no since",
          len(sync) == 1 and sync[0][2] == "Bearer TOK-123" and sync[0][1].get("timeout") == ["0"] and "since" not in sync[0][1]
          and json.loads(sync[0][1]["filter"][0]) == mod.FILTER, sync)
    check("JSON out is what the bar parses", jparse(json.dumps(o, ensure_ascii=False)) == o)

    Srv.reqs.clear()
    Srv.syncs[:] = [(200, {"next_batch": "s2", "rooms": {"join": {"!a:localhost": room(count=0)}, "leave": {"!me:localhost": {}}}})]
    o = mod.status() or {}
    sync = [r for r in Srv.reqs if r[0].endswith("/sync")]
    check("next run: incremental sync from the saved position", sync and sync[0][1].get("since") == ["s1"], sync)
    check("a chat read elsewhere and a chat left drop out; no mention -> class unread",
          o.get("text", "").endswith(" 1") and o.get("class") == "unread" and [r["id"] for r in o.get("rooms", [])] == ["!dm:localhost"], o)
    check("the name looked up once is remembered (no second profile request)", not any("/profile/" in r[0] for r in Srv.reqs), Srv.reqs)

    Srv.syncs[:] = [(200, b"<html>bad gateway</html>")]
    o = mod.status()
    check("garbage from Synapse with chats unread before -> '? ' stale pill, valid JSON",
          isinstance(o, dict) and o["class"] == "stale" and o["text"].endswith("?") and o["rooms"] == [] and "can't reach" in o["tooltip"], o)
    Srv.syncs[:] = [(500, {"errcode": "M_UNKNOWN"})]
    o = mod.status()
    check("HTTP 500 -> stale too", isinstance(o, dict) and o["class"] == "stale", o)
    Srv.syncs[:] = [(200, {"next_batch": "s3", "rooms": {"join": {"!dm:localhost": room(count=0)}}})]
    check("nothing unread -> None (no output, pill hidden)", mod.status() is None)
    Srv.syncs[:] = [(401, {"errcode": "M_UNKNOWN_TOKEN"})]
    check("server error with nothing unread before -> None (no stale pill)", mod.status() is None)

    many = {"next_batch": "m1", "rooms": {"join": {"!r%d:localhost" % i: room([bridge(), {"type": "m.room.name", "state_key": "", "content": {"name": "Chat %d" % i}}],
                                                                           [msg("@p:localhost", "m%d" % i, 100 + i)], count=1) for i in range(8)}}}
    wfile(mod.STATE, "{corrupt")
    Srv.reqs.clear(); Srv.syncs[:] = [(200, many)]
    o = mod.status() or {}
    sync = [r for r in Srv.reqs if r[0].endswith("/sync")]
    check("a corrupt state file means a fresh initial sync", sync and "since" not in sync[0][1], sync)
    check("8 chats: all in rooms, 6 in the tooltip then 'and 2 more'",
          len(o.get("rooms", [])) == 8 and "and 2 more" in o.get("tooltip", "") and "Chat 1 " not in o.get("tooltip", ""), o.get("tooltip"))

    httpd.shutdown(); httpd.server_close()
    o = mod.status()
    check("Synapse down with chats unread before -> stale", isinstance(o, dict) and o.get("class") == "stale", o)
    os.remove(mod.STATE)
    check("Synapse down, nothing known -> None", mod.status() is None)
    mod.SESSIONS = HOME + "/nonexistent.el"
    check("no ement session -> None, nothing asked", mod.status() is None and mod.token() is None)

    case("teams-unread command line")
    tu = [sys.executable, os.path.join(BIN, "teams-unread")]
    os.remove(sessions)
    r = run(tu)
    check("no session: prints nothing, exit 0 (bar hides the pill)", r.returncode == 0 and r.stdout == "", (r.returncode, r.stdout, r.stderr[-200:]))
    wfile(mod.STATE, {"filter": mod.FILTER, "since": "s9", "rooms": {
        "!a:localhost": {"teams": True, "name": "A", "count": 2, "mentions": 1, "last": None, "names": {}},
        "!b:localhost": {"teams": True, "name": "B", "count": 3, "mentions": 0, "last": None, "names": {}}}})
    clear_calls()
    r = run(tu + ["open", "!a:localhost"])
    s = jparse(open(mod.STATE).read()) or {}
    check("open ROOM: counted read at once, others untouched, sync position kept",
          r.returncode == 0 and s["rooms"]["!a:localhost"]["count"] == 0 and s["rooms"]["!a:localhost"]["mentions"] == 0
          and s["rooms"]["!b:localhost"]["count"] == 3 and s["since"] == "s9", (r.stderr[-200:], s))
    c = calls()
    check("open ROOM: emacsclient --eval names that room, then Emacs is focused",
          any(x.startswith("emacsclient --eval") and '"!a:localhost"' in x for x in c) and any(x.startswith("hyprctl dispatch") for x in c), c)
    clear_calls()
    r = run(tu + ["open", '!a:localhost") (shell-command "rm -rf ~'])
    check("open with something that is not a room ID: refused, Emacs not asked", r.returncode != 0 and not any("emacsclient" in x for x in calls()), calls())
    clear_calls()
    run(tu + ["open"])
    check("open with no room: the oldest unread view", any(x == "emacsclient --eval (tsr/ement-view-unread)" for x in calls()), calls())
    clear_calls()
    run(tu + ["list"])
    check("list: the ement room list", any(x == "emacsclient --eval (tsr/ement-room-list)" for x in calls()), calls())
    r = run(tu + ["bogus"])
    check("unknown command: usage, exit non-zero, nothing on stdout", r.returncode != 0 and r.stdout == "", r.returncode)


# =====================================================================================
class FakeDate(_dt.date):
    frozen = _dt.date(2026, 11, 21)
    @classmethod
    def today(cls):
        return cls.frozen


def part_gameday():
    net = Net()
    urllib.request.urlopen = net
    real_date = _dt.date
    _dt.date = FakeDate
    cache = os.path.join(os.environ["XDG_CACHE_HOME"], "gameday.json")

    def team(tid, loc, name):
        t = {"id": tid, "displayName": name}
        if loc:
            t["location"] = loc
        return t
    def game(date, opp, home, timed=True):
        us = {"team": team("228", "Clemson", "Clemson Tigers"), "homeAway": "home" if home else "away"}
        them = {"team": opp, "homeAway": "away" if home else "home"}
        return {"date": date, "timeValid": timed, "competitions": [{"competitors": [them, us] if home else [us, them]}]}
    feed = {"events": [
        game("2026-11-14T20:00Z", team("52", "Florida State", "Florida State Seminoles"), False),
        game("2026-11-21T17:00Z", team("59", "Georgia Tech", "Georgia Tech Yellow Jackets"), True),
        game("2026-11-29T00:30Z", team("2579", "South Carolina", "South Carolina Gamecocks"), False),
        game("2026-12-05T17:00Z", team("999", None, "Mystery Bowl Opponent"), True, timed=False)]}

    def gd(day, routes):
        FakeDate.frozen = day
        net.routes = routes
        out, code, err = run_inproc("gameday")
        return jparse(out), code, out + err

    def shape(o):
        if not (isinstance(o, dict) and set(o) == {"today", "next"}):
            return False
        return all(g is None or (set(g) == {"date", "opponent", "home", "time"} and isinstance(g["home"], bool)
                                 and isinstance(g["opponent"], str) and re.fullmatch(r"(\d\d:\d\d)?", g["time"])) for g in o.values())
    try:
        case("gameday")
        o, code, raw = gd(_dt.date(2026, 11, 21), {"teams/228/schedule": feed})
        check("game today: valid JSON in the shape WallState.qml reads, exit 0", shape(o) and code == 0, raw)
        o = o or {"today": None, "next": None}
        check("today: Georgia Tech at home, kickoff in local time (17:00Z -> 12:00)",
              o["today"] == {"date": "2026-11-21", "opponent": "Georgia Tech", "home": True, "time": "12:00"}, o["today"])
        check("next: the evening game, local date (00:30Z on the 29th is the 28th here), away",
              o["next"] == {"date": "2026-11-28", "opponent": "South Carolina", "home": False, "time": "19:30"}, o["next"])
        check("schedule cached", os.path.exists(cache))
        n = len(net.calls)
        o, code, raw = gd(_dt.date(2026, 11, 28), {})
        check("evening kickoff counts as today's game; fresh cache used, nothing fetched",
              o and (o["today"] or {}).get("opponent") == "South Carolina" and len(net.calls) == n, (o, len(net.calls) - n))
        o, code, raw = gd(_dt.date(2026, 11, 22), {})
        check("no game today: today null, next game given", o and o["today"] is None and (o["next"] or {}).get("date") == "2026-11-28", o)
        o, code, raw = gd(_dt.date(2026, 12, 1), {})
        check("time not set yet (TBA): time empty; no location: display name",
              o and o["next"] == {"date": "2026-12-05", "opponent": "Mystery Bowl Opponent", "home": True, "time": ""}, o)
        o, code, raw = gd(_dt.date(2027, 1, 20), {})
        check("after the season: both null", o == {"today": None, "next": None}, o)
        old = time.time() - 13 * 3600
        os.utime(cache, (old, old))
        o, code, raw = gd(_dt.date(2026, 11, 21), {})
        check("ESPN down, 13-hour-old cache: the old copy is used", o and (o["today"] or {}).get("opponent") == "Georgia Tech" and code == 0, raw)
        os.utime(cache, (old, old))
        n = len(net.calls)
        o, code, raw = gd(_dt.date(2026, 11, 21), {"teams/228/schedule": {"events": []}})
        check("cache over 12 hours old is refetched", len(net.calls) == n + 1 and o == {"today": None, "next": None}, (len(net.calls) - n, o))
        for label, routes in (("ESPN down, no cache", {}), ("malformed JSON", {"teams/228/schedule": b"<!doctype html>"}),
                              ("an event without competitors", {"teams/228/schedule": {"events": [{"date": "2026-11-21T17:00Z"}]}}),
                              ("JSON that is a list", {"teams/228/schedule": [1, 2]})):
            os.path.exists(cache) and os.remove(cache)
            o, code, raw = gd(_dt.date(2026, 11, 21), routes)
            check("%s: valid JSON, both null, exit 0" % label, o == {"today": None, "next": None} and code == 0, raw)
        wfile(cache, "{broken")
        o, code, raw = gd(_dt.date(2026, 11, 21), {})
        check("corrupt cache and ESPN down: valid JSON, exit 0", o == {"today": None, "next": None} and code == 0, raw)
    finally:
        _dt.date = real_date


def part_petscore():
    net = Net()
    urllib.request.urlopen = net

    def feed(state, us_score, them_score):
        us = {"team": {"id": "228"}, "homeAway": "home"}
        them = {"team": {"id": "59"}, "homeAway": "away"}
        if us_score is not None:
            us["score"] = us_score
        if them_score is not None:
            them["score"] = them_score
        return {"team": {"id": "228", "nextEvent": [{"competitions": [{"competitors": [them, us], "status": {"type": {"state": state}}}]}]}}

    def ps(routes):
        net.routes = routes
        out, code, err = run_inproc("pet-score")
        return out, code, err

    case("pet-score")
    out, code, err = ps({"teams/228": feed("in", {"value": 14.0, "displayValue": "14"}, "7")})
    check("game on: {state, us, them} with Clemson's score as 'us', exit 0",
          jparse(out) == {"state": "in", "us": 14, "them": 7} and code == 0, out + err)
    check("asks ESPN's Clemson team feed", net.calls and net.calls[-1].endswith("/teams/228"), net.calls)
    out, _, _ = ps({"teams/228": feed("pre", None, None)})
    check("before kickoff, no scores yet: 0-0, state pre", jparse(out) == {"state": "pre", "us": 0, "them": 0}, out)
    out, _, _ = ps({"teams/228": feed("post", {"displayValue": "31"}, {"value": None, "displayValue": "abc"})})
    check("final; displayValue used; a score that is not a number counts 0", jparse(out) == {"state": "post", "us": 31, "them": 0}, out)
    for label, routes in (("ESPN down", {}), ("malformed JSON", {"teams/228": b"\xff\xfe"}),
                          ("no next event", {"teams/228": {"team": {"id": "228", "nextEvent": []}}}),
                          ("Clemson not among the teams", {"teams/228": {"team": {"nextEvent": [{"competitions": [{"competitors": [{"team": {"id": "1"}}], "status": {}}]}]}}})):
        out, code, err = ps(routes)
        check("%s: prints nothing, exit 0 (PetSecrets ignores it)" % label, out == "" and code == 0, (out, code, err[-200:]))


# =====================================================================================
class Ev:
    def __init__(self, t, type_, code, value):
        self.type, self.code, self.value, self._t = type_, code, value, t
    def timestamp(self):
        return self._t


class FakeDev:
    _fd = 100
    def __init__(self, path, name, caps):
        FakeDev._fd += 1
        self.path, self.name, self.caps, self.fd = path, name, caps, FakeDev._fd
        self.queue, self.fail, self.closed, self.opened = [], False, False, 0
    def capabilities(self):
        return self.caps
    def read(self):
        if self.fail:
            self.fail = False
            raise OSError(19, "No such device")
        q, self.queue = self.queue, []
        return q
    def close(self):
        self.closed = True


_real_sleep = time.sleep


class Driver:
    """Virtual clock + scripted select(): each select() returns the next step's readiness."""
    def __init__(self, steps, devs):
        self.steps, self.devs, self.t, self.socks, self.sleeps, self.stopped = list(steps), devs, 1000.0, [], 0, False

    def monotonic(self):
        return self.t

    def sleep(self, s):
        if sys._getframe(1).f_globals.get("__name__") != "__main__":
            return _real_sleep(s)                  # subprocess's own waiting: real time, not the script's
        self.t += s
        self.sleeps += 1
        if self.sleeps > 200:
            self.stop()

    def stop(self):
        self.stopped = True
        signal.getsignal(signal.SIGTERM)(signal.SIGTERM, None)       # the script's own handler: save, exit

    def select(self, r, w, x, timeout=None):
        while True:
            if not self.steps:
                self.stop()
            step = self.steps.pop(0)
            kind = step[0]
            if kind == "call":
                step[1]()
                continue
            if kind == "tick":
                self.t += step[1]
                return [], [], []
            if kind == "dev":
                dev, evs = step[1], step[2]
                self.t += step[3] if len(step) > 3 else 0.01
                dev.queue = [Ev(self.t, *e) for e in evs]
                return [dev.fd], [], []
            if kind == "fail":
                step[1].fail = True
                self.t += 0.01
                return [step[1].fd], [], []
            if kind == "hypr":
                self.t += step[2] if len(step) > 2 else 0.01
                s = self.socks[-1]
                s.queue.append(step[1])
                return [s], [], []
            if kind == "plug":
                self.devs[step[1].path] = step[1]
                continue
            raise RuntimeError("bad step " + kind)

    def fake_socket(self):
        drv = self
        class FakeSock:
            def __init__(self, *a, **k):
                self.queue, self.path, self.closed = [], None, False
                drv.socks.append(self)
            def connect(self, path):
                self.path = path
            def setblocking(self, b): pass
            def settimeout(self, t): pass
            def recv(self, n):
                if self.queue:
                    return self.queue.pop(0)
                raise BlockingIOError
            def close(self):
                self.closed = True
        return FakeSock

    def evdev(self):
        import evdev as real
        m = types.ModuleType("evdev")
        m.ecodes = real.ecodes
        m.list_devices = lambda: list(self.devs)
        def InputDevice(path):
            if path not in self.devs:
                raise OSError(2, "gone")
            d = self.devs[path]
            d.closed = False
            d.opened += 1
            return d
        m.InputDevice = InputDevice
        return m

    def run(self, name):
        saved = (sys.modules.get("evdev"), select_mod.select, time.monotonic, time.sleep, socket.socket)
        sys.modules["evdev"] = self.evdev()
        select_mod.select, time.monotonic, time.sleep, socket.socket = self.select, self.monotonic, self.sleep, self.fake_socket()
        try:
            return run_inproc(name)
        finally:
            ev, select_mod.select, time.monotonic, time.sleep, socket.socket = saved
            if ev is not None:
                sys.modules["evdev"] = ev
            signal.signal(signal.SIGTERM, signal.SIG_DFL)
            signal.signal(signal.SIGINT, signal.default_int_handler)


import select as select_mod


def part_keystats():
    from evdev import ecodes as E
    K, P, R, H = 1, 0, 2, E.EV_KEY            # value: press, release, autorepeat
    statef = HOME + "/.local/state/keystats/counts.json"
    os.makedirs(os.path.dirname(statef), exist_ok=True)
    os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = "datatest_fake"
    wfile(D + "/hypr/activewindow.json", {"class": "kitty", "title": "zsh"})

    def key(code, v):
        return (E.EV_KEY, code, v)
    ml = FakeDev("/dev/input/event20", "ZSA Technology Labs Moonlander Mark I", {E.EV_KEY: [E.KEY_A], E.EV_MSC: [4]})
    ml2 = FakeDev("/dev/input/event21", "ZSA Technology Labs Moonlander Mark I System Control", {E.EV_ABS: [0]})
    other = FakeDev("/dev/input/event22", "AT Translated Set 2 keyboard", {E.EV_KEY: [E.KEY_A]})
    devs = {d.path: d for d in (ml, ml2, other)}
    wfile(statef, {"since": "2026-01-01 00:00", "keys": {"KEY_A": 5}, "mods": {"Super": 2}, "timing": {"KEY_X KEY_Y": [0] * 15},
                   "apps": {"kitty": {"KEY_A": 5}}})
    checks_mid = {}
    steps = [
        ("call", lambda: checks_mid.update(closed=(ml.closed, ml2.closed, other.closed))),
        ("dev", ml, [key(E.KEY_LEFTMETA, K), key(E.KEY_LEFTSHIFT, K), (E.EV_MSC, 4, 7), key(E.KEY_GRAVE, K)]),
        ("dev", ml, [key(E.KEY_GRAVE, P), key(E.KEY_LEFTSHIFT, P), key(E.KEY_LEFTMETA, P)]),
        ("dev", ml, [key(E.KEY_LEFTMETA, K)]),
        ("dev", ml, [key(E.KEY_LEFTMETA, P)], 0.2),                         # Super tapped alone
        ("dev", ml, [key(E.KEY_H, K)], 5.0),
        ("dev", ml, [key(E.KEY_H, P), key(E.KEY_I, K)], 0.09),              # 90 ms after H
        ("dev", ml, [key(E.KEY_I, P)], 0.05),
        ("dev", ml, [key(E.KEY_J, K)], 10.0),                               # a pause: no timing
        ("dev", ml, [key(E.KEY_J, R), key(E.KEY_J, R), key(E.KEY_J, R), key(E.KEY_J, P)], 0.5),
        ("hypr", b"activewindow>>firefox,Some page\nworkspace>>2\n"),
        ("dev", ml, [key(E.KEY_A, K), key(E.KEY_A, P)], 3.0),
        ("hypr", b"activewin"), ("hypr", b"dow>>emacs,init.el\n"),           # one event split over two reads
        ("dev", ml, [key(E.KEY_RIGHTALT, K), key(E.KEY_E, K), key(E.KEY_E, P), key(E.KEY_RIGHTALT, P)], 3.0),
        ("fail", ml),                                                       # unplugged
        ("dev", ml, [key(E.KEY_B, K), key(E.KEY_B, P)], 0.2),               # replugged and typing again quickly
        ("dev", ml, [key(E.KEY_LEFTCTRL, K), key(E.KEY_C, K), key(E.KEY_C, P), key(E.KEY_LEFTCTRL, P)], 0.3),
    ]
    drv = Driver(steps, devs)
    case("keystats")
    out, code, err = drv.run("keystats")
    check("stops cleanly on SIGTERM (exit 0) after saving", code == 0 and drv.stopped, (code, err[-300:]))
    d = jparse(open(statef).read()) if os.path.exists(statef) else None
    check("counts file is JSON", isinstance(d, dict), statef)
    d = d or {}
    keys, bi, mods, rep, tim, apps = (d.get(k, {}) for k in ("keys", "bigrams", "mods", "repeats", "timing", "apps"))
    check("only the Moonlander device with keys is read; the others are closed",
          checks_mid.get("closed") == (False, True, True), checks_mid)
    check("a key with modifiers held: 'Super+Shift+KEY_GRAVE' (fixed modifier order)", keys.get("Super+Shift+KEY_GRAVE") == 1, keys)
    check("AltGr and Ctrl combos", keys.get("AltGr+KEY_E") == 1 and keys.get("Ctrl+KEY_C") == 1, keys)
    check("counts add to the saved ones, 'since' kept", keys.get("KEY_A") == 6 and d.get("since") == "2026-01-01 00:00", (keys.get("KEY_A"), d.get("since")))
    check("a modifier tapped alone counts under mods; one used in a combo does not", mods.get("Super") == 3 and not any(mods.get(m) for m in ("Shift", "Ctrl", "AltGr", "Alt")), mods)
    check("bigrams of consecutive keys", bi.get("KEY_H KEY_I") == 1 and bi.get("KEY_I KEY_J") == 1 and bi.get("KEY_GRAVE KEY_H") == 1, bi)
    check("no bigram across an unplug", "KEY_E KEY_B" not in bi and bi.get("KEY_B KEY_C") == 1, bi)
    check("no timing pair across an unplug", "KEY_E KEY_B" not in tim and "KEY_B KEY_C" in tim, sorted(tim))
    check("autorepeat counted per key, not as presses", rep.get("KEY_J") == 3 and keys.get("KEY_J") == 1, (rep, keys.get("KEY_J")))
    check("timing: 90 ms falls in the 80-100 ms bucket", tim.get("KEY_H KEY_I") == [0, 0, 0, 1] + [0] * 11, tim.get("KEY_H KEY_I"))
    check("timing: pairs more than 1.5 s apart are pauses, not typing", "KEY_I KEY_J" not in tim and "KEY_J KEY_A" not in tim, sorted(tim))
    check("timing_buckets lists the bucket edges in ms", d.get("timing_buckets") == [40, 60, 80, 100, 125, 150, 175, 200, 250, 300, 400, 500, 750, 1000, 1500], d.get("timing_buckets"))
    check("apps: per focused window class, following activewindow events (also split ones)",
          apps.get("kitty", {}).get("Super+Shift+KEY_GRAVE") == 1 and apps.get("kitty", {}).get("KEY_A") == 5
          and apps.get("firefox", {}).get("KEY_A") == 1 and apps.get("emacs", {}).get("AltGr+KEY_E") == 1, apps)
    check("asked hyprctl for the focused window at start", any(c == "hyprctl -j activewindow" for c in calls()), calls())
    check("only counts are written: no raw events or timestamps",
          set(d) == {"since", "saved", "keys", "bigrams", "repeats", "mods", "timing_buckets", "timing", "apps"}, sorted(d))

    case("keystats: corrupt counts, no Hyprland, no keyboard")
    wfile(statef, "{corrupt")
    del os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
    clear_calls()
    drv = Driver([("dev", ml, [key(E.KEY_Q, K)])], {ml.path: ml})
    out, code, err = drv.run("keystats")
    d = jparse(open(statef).read()) or {}
    check("corrupt counts file: starts afresh", code == 0 and d.get("keys") == {"KEY_Q": 1}, (code, d.get("keys"), err[-200:]))
    check("outside Hyprland: app '?' and hyprctl never asked", d.get("apps") == {"?": {"KEY_Q": 1}} and not calls(), (d.get("apps"), calls()))
    os.remove(statef)
    drv = Driver([], {other.path: other})
    out, code, err = drv.run("keystats")
    check("no Moonlander: waits (sleeps) instead of failing, still saves on SIGTERM", code == 0 and drv.sleeps > 0 and os.path.exists(statef), (code, err[-200:]))


def part_mousestats():
    from evdev import ecodes as E
    statef = HOME + "/.local/state/keystats/mouse.json"
    os.makedirs(os.path.dirname(statef), exist_ok=True)
    os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = "datatest_fake"
    hy = D + "/hypr/"
    wfile(hy + "monitors.json", [{"name": "eDP-1", "activeWorkspace": {"id": 1, "name": "1"}, "specialWorkspace": {"id": 0, "name": ""}},
                                 {"name": "DP-3", "activeWorkspace": {"id": 2, "name": "2"}, "specialWorkspace": {"name": "special:scratch"}}])
    layers = {"eDP-1": {"levels": {"0": [{"x": 0, "y": 0, "w": 1920, "h": 1200, "namespace": "qs-wallpaper"}],
                                                    "2": [{"x": 0, "y": 0, "w": 1920, "h": 40, "namespace": "qs-bar"}], "3": []}},
                               "DP-3": {"levels": {"3": [{"x": 3000, "y": 900, "w": 300, "h": 200, "namespace": "qs-osd"}]}}}
    wfile(hy + "layers.json", layers)
    def cl(cls, ws, at, size, fh, floating=False, hidden=False, mapped=True):
        return {"class": cls, "workspace": {"id": 9, "name": ws}, "at": at, "size": size, "focusHistoryID": fh,
                "floating": floating, "hidden": hidden, "mapped": mapped}
    wfile(hy + "clients.json", [cl("kitty", "1", [10, 50], [940, 1140], 2), cl("emacs", "1", [10, 50], [940, 1140], 0),
                                cl("firefox", "1", [960, 50], [950, 1140], 1), cl("pavucontrol", "1", [800, 300], [400, 300], 5, floating=True),
                                cl("slack", "5", [10, 50], [1900, 1100], 3), cl("scratchterm", "special:scratch", [2000, 100], [500, 500], 4),
                                cl("ghost", "2", [2600, 300], [200, 200], 6, floating=True, hidden=True),
                                cl("unmapped", "2", [2600, 700], [100, 80], 7, floating=True, mapped=False)])
    def at(x, y):
        return ("call", lambda: wfile(hy + "cursorpos.json", {"x": x, "y": y}))
    def btn(dev, code, dt=0.01):
        return ("dev", dev, [(E.EV_KEY, code, 1), (E.EV_SYN, 0, 0)], dt)
    tb = FakeDev("/dev/input/event30", "Kensington Expert Wireless TB Mouse",
                 {E.EV_KEY: [E.BTN_LEFT, E.BTN_RIGHT, E.BTN_MIDDLE, E.BTN_SIDE, E.BTN_EXTRA], E.EV_REL: [E.REL_X, E.REL_Y, E.REL_WHEEL]})
    tp = FakeDev("/dev/input/event31", "SynPS/2 Synaptics TouchPad",
                 {E.EV_KEY: [E.BTN_LEFT, E.BTN_TOUCH, E.BTN_TOOL_FINGER, E.BTN_TOOL_DOUBLETAP], E.EV_ABS: [0, 1]})
    ms = FakeDev("/dev/input/event32", "Logitech USB Optical Mouse", {E.EV_KEY: [E.BTN_LEFT, E.BTN_RIGHT], E.EV_REL: [E.REL_WHEEL]})
    ml = FakeDev("/dev/input/event33", "ZSA Technology Labs Moonlander Mark I Mouse", {E.EV_KEY: [E.BTN_LEFT, E.KEY_A]})
    kb = FakeDev("/dev/input/event34", "AT Translated Set 2 keyboard", {E.EV_KEY: [E.KEY_A, E.BTN_LEFT]})
    late = FakeDev("/dev/input/event35", "Kensington SlimBlade Trackball", {E.EV_KEY: [E.BTN_LEFT], E.EV_REL: [E.REL_WHEEL]})
    devs = {d.path: d for d in (tb, tp, ms, ml, kb)}
    wfile(statef, {"since": "2026-02-02 02:02", "actions": {"mouse left on desktop -> nothing": 4}, "targets": {}})
    mid = {}
    steps = [
        ("call", lambda: mid.update(closed={d.name: d.closed for d in (tb, tp, ms, ml, kb)})),
        at(100, 20), btn(tb, E.BTN_LEFT), ("tick", 0.5),                                    # bar, nothing happens
        at(900, 400), btn(tb, E.BTN_LEFT), ("hypr", b"activewindowv2>>55aa\n", 0.1),
        ("hypr", b"workspacev2>>2,2\nurgent>>77\n", 0.1), ("tick", 0.5),                     # floating over tiled
        at(100, 400), btn(tb, E.BTN_RIGHT), ("tick", 0.5), ("hypr", b"closewindow>>55aa\n"),   # effect too late
        at(2100, 200), btn(ms, E.BTN_MIDDLE), ("hypr", b"activespecialv2>>,,DP-3\n", 0.05), ("tick", 0.5),
        at(5, 1195), ("dev", ms, [(E.EV_REL, E.REL_WHEEL, 1)]), ("dev", ms, [(E.EV_REL, E.REL_WHEEL, -1)]), ("tick", 0.5),
        at(3100, 1000), btn(tb, E.BTN_SIDE), ("tick", 0.5),
        at(2650, 740), btn(tb, E.BTN_EXTRA), ("tick", 0.5),                                 # unmapped window: desktop
        at(2650, 350), btn(tb, E.BTN_LEFT), ("tick", 0.5),                                    # hidden window: desktop
        at(500, 600), ("dev", tp, [(E.EV_KEY, E.BTN_TOUCH, 1)]), ("dev", tp, [(E.EV_KEY, E.BTN_TOUCH, 0)], 0.1), ("tick", 0.5),
        ("dev", tp, [(E.EV_KEY, E.BTN_TOUCH, 1)]), ("dev", tp, [(E.EV_KEY, E.BTN_TOOL_DOUBLETAP, 1)], 0.02),
        ("dev", tp, [(E.EV_KEY, E.BTN_TOUCH, 0)], 0.05), ("tick", 0.5),
        ("dev", tp, [(E.EV_KEY, E.BTN_TOUCH, 1)]), ("dev", tp, [(E.EV_KEY, E.BTN_TOUCH, 0)], 0.6), ("tick", 0.5),   # a rest, not a tap
        ("call", lambda: wfile(hy + "cursorpos.json", "garbage")), btn(tb, E.BTN_LEFT), ("tick", 0.5),
        ("call", lambda: wfile(hy + "cursorpos.json", {})), btn(tb, E.BTN_RIGHT), ("tick", 0.5),
        at(100, 400), ("call", lambda: wfile(hy + "layers.json", {"eDP-1": {"levels": "oops"}})), btn(tb, E.BTN_MIDDLE), ("tick", 0.5),
        ("call", lambda: wfile(hy + "layers.json", layers)),
        ("plug", late), ("tick", 6.0),                                                       # dock attached
        at(100, 20), btn(late, E.BTN_LEFT), ("tick", 0.5),
    ]
    drv = Driver(steps, devs)
    case("mousestats")
    out, code, err = drv.run("mousestats")
    check("stops cleanly on SIGTERM after saving", code == 0 and drv.stopped, (code, err[-300:]))
    d = jparse(open(statef).read()) if os.path.exists(statef) else None
    check("mouse.json is JSON with since/saved/actions/targets only", isinstance(d, dict) and set(d) == {"since", "saved", "actions", "targets"}, d)
    d = d or {}
    A, T = d.get("actions", {}), d.get("targets", {})
    check("pointers kept, keyboards and the Moonlander closed",
          mid.get("closed") == {tb.name: False, tp.name: False, ms.name: False, ml.name: True, kb.name: True}, mid)
    want = {
        "trackball left on panel:qs-bar -> nothing": 2,
        "trackball left on window:pavucontrol -> desktop+focus": 1,
        "trackball right on window:emacs -> nothing": 1,
        "mouse middle on window:scratchterm -> special": 1,
        "mouse wheel-up on desktop -> nothing": 1, "mouse wheel-down on desktop -> nothing": 1,
        "trackball back on panel:qs-osd -> nothing": 1,
        "trackball forward on desktop -> nothing": 1,
        "trackball left on desktop -> nothing": 1,
        "touchpad tap on window:emacs -> nothing": 1, "touchpad tap2 on window:emacs -> nothing": 1,
        "trackball left on unknown -> nothing": 1, "trackball right on unknown -> nothing": 1, "trackball middle on unknown -> nothing": 1,
        "mouse left on desktop -> nothing": 4,
    }
    for k, v in want.items():
        check("action: " + k, A.get(k) == v, A.get(k))
    check("the bar layer beats the wallpaper layer; the wallpaper is not a panel", not any("qs-wallpaper" in k for k in A), sorted(A))
    check("a long touch is not a tap", sum(v for k, v in A.items() if k.startswith("touchpad")) == 2, sorted(A))
    check("targets: one count per click, no effect part", T.get("trackball left on window:pavucontrol") == 1 and all("->" not in k for k in T), T)
    check("a pointer plugged in later is picked up (second click on the bar)", T.get("trackball left on panel:qs-bar") == 2 and late.opened >= 1, (T.get("trackball left on panel:qs-bar"), late.opened))
    check("'since' from the old file kept", d.get("since") == "2026-02-02 02:02", d.get("since"))


# =====================================================================================
def part_cursorshake():
    os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = "datatest_fake"

    def tri(t, period, lo, hi):
        p = (t % period) / period
        return lo + (hi - lo) * (2 * p if p < 0.5 else 2 - 2 * p)

    def shake(path, end=3.0):
        """Run cursor-shake with the pointer at path(t); returns [(t, line)]."""
        class Clock:
            t = 0.0
        lines = []
        class Out(io.StringIO):
            def write(self, s):
                for l in s.splitlines():
                    if l:
                        lines.append((round(Clock.t, 3), l))
                return len(s)
        class Sock:
            def __init__(self, *a, **k): pass
            def settimeout(self, t): pass
            def connect(self, path_):
                if Clock.t > end:
                    raise FileNotFoundError(path_)
            def send(self, b): self.cmd = b
            def recv(self, n):
                x, y = path(Clock.t)
                return ("%d,%d" % (x, y)).encode()
            def close(self): pass
        def sleep(s):
            Clock.t += s
        saved = (time.monotonic, time.sleep, socket.socket)
        time.monotonic, time.sleep, socket.socket = (lambda: Clock.t), sleep, Sock
        try:
            out, code, err = run_inproc("cursor-shake", stdout=Out())
        finally:
            time.monotonic, time.sleep, socket.socket = saved
        return lines, code, err

    case("cursor-shake")
    lines, code, err = shake(lambda t: (500, 500))
    check("pointer at rest: says nothing; exits when Hyprland's socket goes", lines == [] and code == 0, (lines[:3], code, err[-200:]))
    class NoSock:
        def __init__(self, *a, **k): pass
        def settimeout(self, t): pass
        def connect(self, p): raise FileNotFoundError(p)
    saved = socket.socket
    socket.socket = NoSock
    try:
        out, code, err = run_inproc("cursor-shake")
    finally:
        socket.socket = saved
    check("no Hyprland socket at start: exits quietly, no traceback", code == 0 and out == "" and "Traceback" not in err, (code, err[-200:]))
    lines, _, _ = shake(lambda t: (100 + 400 * t, 300))
    check("a long steady move is not a shake", lines == [], lines[:3])
    lines, _, _ = shake(lambda t: (tri(t, 0.2, 440, 560), 500))
    check("small jitter (under 170 px a leg) is not a shake", lines == [], lines[:3])
    lines, _, _ = shake(lambda t: (tri(t, 1.0, 200, 800), 500), end=4.0)
    check("a slow back-and-forth (2 turns a second) is not a shake", lines == [], lines[:3])
    lines, code, _ = shake(lambda t: (tri(t - 0.5, 0.2, 250, 750), 400) if 0.5 <= t < 1.5 else (250, 400))
    S = [(t, l) for t, l in lines if l.startswith("S ")]
    check("a fast shake: 'S x y' lines at the pointer", S and all(re.fullmatch(r"S \d+ 400", l) and 250 <= int(l.split()[1]) <= 750 for _, l in S), lines[:4])
    check("starts during the shake, not before", S and 0.5 < S[0][0] < 1.5, S[:1])
    # The big pointer stays until the turns age out of the 1.1 s window, then HOLD (0.45 s) more
    check("'E' once, last, within WINDOW + HOLD (1.55 s) of the shaking stopping",
          lines and lines[-1][1] == "E" and [l for _, l in lines].count("E") == 1 and 1.5 <= lines[-1][0] <= 3.15, lines[-2:])
    lines, _, _ = shake(lambda t: (900, tri(t - 0.5, 0.2, 200, 700)) if 0.5 <= t < 1.5 else (900, 200))
    check("a vertical shake counts too", any(l.startswith("S 900 ") for _, l in lines) and lines[-1][1] == "E", lines[-2:])


# =====================================================================================
def part_droppreview():
    os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = "datatest_fake"
    hdir = os.path.join(os.environ["XDG_RUNTIME_DIR"], "hypr", "datatest_fake")
    os.makedirs(hdir, exist_ok=True)
    mod = load("drop-preview")
    check("socket paths come from the runtime directory and signature", mod.BASE == hdir + "/", mod.BASE)
    mon = {"x": 0, "y": 0, "width": 2560, "height": 1440, "scale": 1.0, "transform": 0, "reserved": [0, 40, 0, 0], "activeWorkspace": {"id": 1}}
    W = {"clients": [], "monitors": [mon], "workspaces": [{"id": 1, "tiledLayout": "dwindle"}], "cursor": (100, 100)}

    def win(addr, at, size, floating=False, ws=1, **kw):
        c = {"address": addr, "at": list(at), "size": list(size), "floating": floating, "workspace": {"id": ws}, "mapped": True, "hidden": False}
        c.update(kw)
        return c

    def ask(cmd):
        if cmd == "cursorpos":
            return "%d,%d" % W["cursor"]
        return json.dumps(W[{"j/clients": "clients", "j/monitors": "monitors", "j/workspaces": "workspaces"}[cmd]])
    mod.ask = ask

    def drag(cx, cy, others, layout="dwindle", ws=1, mons=None):
        W["cursor"] = (cx, cy)
        W["clients"] = [win("0xdrag", (cx - 200, cy - 150), (400, 300), floating=True, ws=ws)] + others
        W["workspaces"] = [{"id": ws, "tiledLayout": layout}]
        W["monitors"] = mons or [dict(mon, activeWorkspace={"id": ws})]
        z = mod.zone("0xdrag")
        return tuple(int(v) for v in z) if z else None

    case("drop-preview zone (dwindle)")
    check("empty desktop: the whole usable screen (bar reserved, edges)", drag(1000, 700, []) == (10, 50, 2540, 1380), drag(1000, 700, []))
    wide = win("0xa", (10, 50), (2540, 1380))
    check("wide window, pointer in its left half: left half", drag(600, 700, [wide]) == (10, 50, 1264, 1380), drag(600, 700, [wide]))
    check("wide window, right half: right half", drag(2000, 700, [wide]) == (1286, 50, 1264, 1380), drag(2000, 700, [wide]))
    tall = win("0xb", (1286, 50), (1264, 1380))
    check("tall window, top half: top half", drag(1800, 300, [tall]) == (1286, 50, 1264, 684), drag(1800, 300, [tall]))
    check("tall window, bottom half: bottom half", drag(1800, 1200, [tall]) == (1286, 746, 1264, 684), drag(1800, 1200, [tall]))
    check("pointer in the gap: the nearest window", (drag(1283, 700, [win("0xl", (10, 50), (1264, 1380)), tall]) or ())[:2] == (1286, 50), drag(1283, 700, [win("0xl", (10, 50), (1264, 1380)), tall]))
    grp = win("0xg", (10, 50), (2540, 1380), grouped=["0xg", "0xh"])
    check("a tab group: the whole window (joins the group)", drag(600, 700, [grp]) == (10, 50, 2540, 1380), drag(600, 700, [grp]))
    check("windows on other desktops, floating, hidden or unmapped are ignored",
          drag(1000, 700, [win("0xo", (10, 50), (2540, 1380), ws=2), win("0xf", (10, 50), (900, 900), floating=True),
                           win("0xh", (10, 50), (900, 900), hidden=True), win("0xu", (10, 50), (900, 900), mapped=False)]) == (10, 50, 2540, 1380))
    check("a fullscreen window on the desktop: no preview", drag(600, 700, [win("0xa", (0, 0), (2560, 1440), fullscreen=1)]) is None)
    check("scrolling / custom layouts: no preview", drag(600, 700, [wide], layout="scrolling") is None)
    check("pointer outside every monitor: no preview", drag(5000, 700, [wide]) is None)
    rot = dict(mon, width=2160, height=3840, scale=2.0, transform=1, x=2560, reserved=[0, 0, 0, 0], activeWorkspace={"id": 1})
    check("rotated, scaled monitor measured in layout pixels", drag(3000, 500, [], mons=[mon, rot]) == (2570, 10, 1900, 1060), drag(3000, 500, [], mons=[mon, rot]))
    W["clients"] = [win("0xdrag", (100, 100), (400, 300), floating=False)]
    check("the window is tiled (not being dragged): None", mod.zone("0xdrag") is None)
    W["cursor"] = (1000, 1000)
    W["clients"] = [win("0xdrag", (100, 100), (400, 300), floating=True)]
    check("floating but not riding the pointer: None", mod.zone("0xdrag") is None)
    check("unknown window: None", mod.zone("0xnone") is None)

    case("drop-preview zone (main-and-stack)")
    main = win("0xm", (10, 50), (1264, 1380))
    s1, s2 = win("0xs1", (1286, 50), (1264, 684)), win("0xs2", (1286, 746), (1264, 684))
    check("dropped on the main window: becomes the main window", drag(600, 700, [main, s1, s2], layout="master") == (10, 50, 1264, 1380))
    check("top half of the first stack window: first slot of three",
          drag(1800, 200, [main, s1, s2], layout="master") == (1286, 50, 1264, 452), drag(1800, 200, [main, s1, s2], layout="master"))
    check("bottom half of the last: last slot", drag(1800, 1300, [main, s1, s2], layout="master") == (1286, 978, 1264, 452), drag(1800, 1300, [main, s1, s2], layout="master"))
    st = os.path.join(os.environ["XDG_STATE_HOME"], "hypr-layouts")
    check("orientation defaults per desktop slot: 1 left, 2 top, 3 centre, 11 like 1",
          [mod.orientation(w) for w in (1, 2, 3, 11)] == ["left", "top", "center", "left"])
    wfile(st, "1 top\n4 centre\n1 centre\nbogus line\n")
    check("the layout menu's saved choice wins; the last line for a desktop counts",
          mod.orientation(1) == "center" and mod.orientation(4) == "center" and mod.orientation(2) == "top")
    wfile(st, "1 nonsense\n")
    check("an unknown saved layout falls back to left", mod.orientation(1) == "left")
    os.remove(st)

    case("drop-preview events")
    def serve(lines):
        path = mod.BASE + ".socket2.sock"
        if os.path.exists(path):
            os.remove(path)
        srv = socket.socket(socket.AF_UNIX)
        srv.bind(path)
        srv.listen(1)
        def go():
            c, _ = srv.accept()
            c.sendall("".join(l + "\n" for l in lines).encode())
            c.close()
            srv.close()
        threading.Thread(target=go, daemon=True).start()

    def main_run(lines, zones):
        seen, seq = [], list(zones)
        def zone(addr):
            seen.append(addr)
            z = seq.pop(0) if seq else None
            if isinstance(z, BaseException):
                raise z
            return z
        mod.zone = zone
        real_sleep = time.sleep
        time.sleep = lambda s: None
        serve(lines)
        out = io.StringIO()
        try:
            with contextlib.redirect_stdout(out):
                mod.main()
        finally:
            time.sleep = real_sleep
        return out.getvalue().splitlines(), seen
    out, seen = main_run(["openwindow>>abc,1,kitty,x", "changefloatingmode>>abc,0", "changefloatingmode>>abc,1"],
                         [(1, 2, 3, 4), (1.4, 2, 3, 4), (5, 6, 7, 8), None, OSError("socket"), None, None])
    check("a drag: 'Z x y w h' when the zone changes (not repeated), 'E' at the end", out == ["Z 1 2 3 4", "Z 5 6 7 8", "E"], out)
    check("only the floating-on event starts watching, for that window's address", seen and set(seen) == {"0xabc"}, seen[:3])
    out, seen = main_run(["changefloatingmode>>def,1"], [None, None, None, None])
    check("turned floating but never a drag: says nothing (no 'E')", out == [] and len(seen) == 4, (out, len(seen)))


# =====================================================================================
def part_keybind():
    real_chrome = next((c for c in ("/usr/bin/google-chrome", "/usr/bin/chromium-browser", "/usr/bin/chromium") if os.path.exists(c)), None)
    stubs = os.environ["DT_STUBS"]
    live = os.path.join(FIX, "binds.json")
    page = D + "/page.html"
    fake, wrap = D + "/fakechrome", D + "/chromewrap"
    wfile(fake + "/google-chrome", '#!/bin/sh\n# data-test: keep the page, write a stand-in PDF\n'
          'for a; do case "$a" in file://*) /bin/cp "${a#file://}" "%s";; --print-to-pdf=*) printf "%%%%PDF-1.4 stand-in\\n" > "${a#--print-to-pdf=}";; esac; done\n' % page)
    wfile(wrap + "/google-chrome", '#!/bin/sh\n# data-test: keep the page, then print with the real browser, kept off the network\n'
          'for a; do case "$a" in file://*) /bin/cp "${a#file://}" "%s";; esac; done\n'
          'exec "%s" --disable-background-networking --disable-component-update --disable-sync --disable-extensions '
          '--disable-default-apps --disable-domain-reliability --no-first-run --no-default-browser-check --metrics-recording-only '
          '--dns-prefetch-disable --proxy-server=127.0.0.1:9 "--proxy-bypass-list=<-loopback>" "$@"\n' % (page, real_chrome))
    for f in (fake + "/google-chrome", wrap + "/google-chrome"):
        os.chmod(f, 0o755)
    ks = [sys.executable, os.path.join(BIN, "keybind-sheet")]
    path_rest = stubs + ":/usr/bin:/bin"

    def html_text():
        try:
            return open(page).read()
        except OSError:
            return ""

    case("keybind-sheet from the live bindings")
    pdf = D + "/sheet.pdf"
    binds = json.load(open(live))
    if real_chrome:
        t0 = time.time()
        r = run(ks + [pdf], {"PATH": wrap + ":" + path_rest, "DT_BINDS": live}, timeout=100)
        check("makes a PDF (real headless browser, offline), exit 0", r.returncode == 0 and open(pdf, "rb").read(5) == b"%PDF-" if os.path.exists(pdf) else False,
              (r.returncode, r.stderr[-300:]))
        m = re.search(r"\((\d+) bindings, (\d+) under Other\)", r.stdout)
        check("reports the number of bindings it read", m and int(m.group(1)) == len({(b["modmask"], b["key"]) for b in binds}), r.stdout)
        if shutil.which("pdftotext") and os.path.exists(pdf):
            txt = " ".join(subprocess.run(["pdftotext", "-layout", pdf, "-"], capture_output=True, text=True).stdout.split())
            for want in ("Hyprland keybindings", "Emacs", "Terminal", "Close window", "Window switcher", "Screenshot: whole screen",
                         "Go to desktop 1–10", "Shake the pointer"):
                check("PDF text has '%s'" % want, want in txt, txt[:200])
            check("one page", re.search(r"^Pages:\s+1$", subprocess.run(["pdfinfo", pdf], capture_output=True, text=True).stdout, re.M) is not None
                  if shutil.which("pdfinfo") else True)
        else:
            print("SKIP pdftotext not installed: PDF text not checked")
        h = html_text()
        # every modifier combination in use is named, never shown as a bare modmask number
        bare = re.findall(r"<kbd>(\d+)</kbd><kbd>([^<]+)</kbd>", h)
        check("every modifier combination in the live binds is named (no bare modmask numbers like '9 Tab')", not bare, bare)
    else:
        print("SKIP no Chrome/Chromium: the real PDF is not made")

    case("keybind-sheet layout rules (stand-in browser)")
    small = [
        {"modmask": 64, "key": "Return", "description": "Emacs"},
        {"modmask": 64, "key": "Q", "description": "Close <window> & co"},
        {"modmask": 64, "key": "F12", "description": "Brand new thing"},
        {"modmask": 64, "key": "U", "description": ""},
        {"modmask": 0, "key": "XF86AudioMute", "description": "Mute"},
        {"modmask": 9, "key": "Tab", "description": "Back through windows"},
        {"modmask": 69, "key": "W", "description": "Webcam"},
        {"modmask": 64, "key": "left", "description": "l"}, {"modmask": 64, "key": "up", "description": "u"},
        {"modmask": 64, "key": "down", "description": "d"}, {"modmask": 64, "key": "right", "description": "r"},
    ] + [{"modmask": 64, "key": str(i), "description": "ws"} for i in (1, 2, 3, 4, 5, 6, 7, 8, 9, 0)]
    wfile(D + "/small.json", small)
    out2 = D + "/small.pdf"
    r = run(ks + [out2], {"PATH": fake + ":" + path_rest, "DT_BINDS": D + "/small.json"})
    h = html_text()
    check("runs, writes the PDF it was given", r.returncode == 0 and os.path.exists(out2) and "(21 bindings, 3 under Other)" in r.stdout, (r.stdout, r.stderr[-200:]))
    check("a bound key gets its live description", "<kbd>Super</kbd><kbd>Enter</kbd></div><div class=does>Emacs" in h, h[:0])
    check("descriptions are HTML-escaped", "Close &lt;window&gt; &amp; co" in h)
    check("a key no longer bound drops its row (no Terminal row without Super T)", "Terminal" not in h and "<kbd>T</kbd>" not in h)
    check("a new binding with a description goes under Other", re.search(r"<h2>Other</h2>.*Brand new thing", h) is not None)
    check("no description, or an XF86 key: not listed", "XF86" not in h and "<kbd>U</kbd>" not in h)
    check("the ten desktop keys share one row '1–0'; arrows share '←↑↓→'", "<kbd>1–0</kbd>" in h and "<kbd>←↑↓→</kbd>" in h)
    check("modifiers named from the mask bits: Alt+Shift (9) -> Shift Alt, 69 -> Super Shift Ctrl",
          "<kbd>Shift</kbd><kbd>Alt</kbd><kbd>Tab</kbd>" in h and "<kbd>Super</kbd><kbd>Shift</kbd><kbd>Ctrl</kbd><kbd>W</kbd>" in h)
    check("hand-written rows (laptop keys, mouse) are always there", "Shake the pointer" in h and "Laptop keys" in h)

    case("keybind-sheet failures")
    os.remove(out2)
    r = run(ks + [out2], {"PATH": fake + ":" + path_rest, "HYPRCTL_FAIL": "1"})
    check("hyprctl failing: exit non-zero, no PDF", r.returncode != 0 and not os.path.exists(out2), r.returncode)
    r = run(ks + [out2], {"PATH": stubs, "DT_BINDS": D + "/small.json"})
    check("no browser: says so, exit non-zero, no PDF", r.returncode != 0 and "no Chrome or Chromium" in r.stderr and not os.path.exists(out2), (r.returncode, r.stderr[-200:]))


PARTS = {"dashboard": part_dashboard, "shellstatus": part_shellstatus, "shelllog": part_shelllog, "teams": part_teams,
         "gameday": part_gameday, "petscore": part_petscore, "keystats": part_keystats, "mousestats": part_mousestats,
         "cursorshake": part_cursorshake, "droppreview": part_droppreview, "keybind": part_keybind}

if __name__ == "__main__":
    part = sys.argv[1] if len(sys.argv) > 1 else ""
    if part not in PARTS:
        sys.exit("usage: harness.py " + "|".join(PARTS))
    try:
        PARTS[part]()
    except Exception:
        print("FAIL %s: the harness itself crashed   [%s]" % (part, " ".join(traceback.format_exc().split())[-600:]), flush=True)
