#!/usr/bin/env python3
"""Parser and `add` tests for bin/quick-event. Run by bin/events-test:
    test_quick_event.py PATH_TO_QUICK_EVENT
Prints "PASS ..." / "FAIL ..." lines and "RESULT pass N fail M". The real exchange tool is never run:
`add` gets a fake through QUICK_EVENT_TOOL, notify-send and systemctl are fakes on PATH."""
import datetime as dt
import importlib.machinery
import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile

SCRIPT = sys.argv[1]
loader = importlib.machinery.SourceFileLoader("quick_event", SCRIPT)
spec = importlib.util.spec_from_loader("quick_event", loader)
qe = importlib.util.module_from_spec(spec)
loader.exec_module(qe)

passed = failed = 0


def check(what, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
    print(("PASS " if ok else "FAIL ") + what + ("" if ok or not detail else "   [%s]" % detail))


def at(s):
    return dt.datetime.fromisoformat(s).replace(tzinfo=qe.ET)


SAT = "2026-11-14T10:36"          # a Saturday
# (now, line, subject, start, end, location)
GOOD = [
    (SAT, "Lunch with Sam tomorrow 12-1 at Esso Club", "Lunch with Sam", "2026-11-15T12:00", "2026-11-15T13:00", "Esso Club"),
    (SAT, "Faculty meeting Fri 2:30pm 90m McAdams 114", "Faculty meeting McAdams 114", "2026-11-20T14:30", "2026-11-20T16:00", ""),
    (SAT, "Faculty meeting Fri 2:30pm 90m at McAdams 114", "Faculty meeting", "2026-11-20T14:30", "2026-11-20T16:00", "McAdams 114"),
    (SAT, "Dentist 11/20 9am", "Dentist", "2026-11-20T09:00", "2026-11-20T10:00", ""),
    (SAT, "Office hours Mon 10-11:30", "Office hours", "2026-11-16T10:00", "2026-11-16T11:30", ""),
    (SAT, "Review today 4pm", "Review", "2026-11-14T16:00", "2026-11-14T17:00", ""),
    (SAT, "Review today 11am", "Review", "2026-11-14T11:00", "2026-11-14T12:00", ""),
    # relative days and weekday names
    (SAT, "Meeting Sat 3pm", "Meeting", "2026-11-21T15:00", "2026-11-21T16:00", ""),
    (SAT, "Meeting this Sat 3pm", "Meeting", "2026-11-14T15:00", "2026-11-14T16:00", ""),
    (SAT, "Meeting next Tue 3pm", "Meeting", "2026-11-17T15:00", "2026-11-17T16:00", ""),
    (SAT, "Meeting wed 3pm", "Meeting", "2026-11-18T15:00", "2026-11-18T16:00", ""),
    (SAT, "Meeting Thursday 3pm", "Meeting", "2026-11-19T15:00", "2026-11-19T16:00", ""),
    (SAT, "Meeting thurs 3pm", "Meeting", "2026-11-19T15:00", "2026-11-19T16:00", ""),
    ("2026-11-16T08:00", "Meeting Tue 3pm", "Meeting", "2026-11-17T15:00", "2026-11-17T16:00", ""),
    ("2026-11-16T08:00", "Meeting next Tue 3pm", "Meeting", "2026-11-24T15:00", "2026-11-24T16:00", ""),
    ("2026-11-16T08:00", "Meeting this Mon 3pm", "Meeting", "2026-11-16T15:00", "2026-11-16T16:00", ""),
    ("2026-11-16T08:00", "Meeting Mon 3pm", "Meeting", "2026-11-23T15:00", "2026-11-23T16:00", ""),
    # week, month and year rollovers
    ("2026-11-15T23:00", "Standup tomorrow 9", "Standup", "2026-11-16T09:00", "2026-11-16T10:00", ""),
    ("2026-11-30T20:00", "Call tomorrow 10am", "Call", "2026-12-01T10:00", "2026-12-01T11:00", ""),
    ("2026-12-31T22:00", "Party tomorrow 8pm", "Party", "2027-01-01T20:00", "2027-01-01T21:00", ""),
    ("2026-12-28T09:00", "Review Fri 1pm", "Review", "2027-01-01T13:00", "2027-01-01T14:00", ""),
    (SAT, "Trip 1/5 2pm", "Trip", "2027-01-05T14:00", "2027-01-05T15:00", ""),
    (SAT, "Meeting Nov 20 2pm", "Meeting", "2026-11-20T14:00", "2026-11-20T15:00", ""),
    (SAT, "Meeting November 20th, 2027 3pm", "Meeting", "2027-11-20T15:00", "2027-11-20T16:00", ""),
    (SAT, "Meeting 2026-11-20 3pm 2h", "Meeting", "2026-11-20T15:00", "2026-11-20T17:00", ""),
    (SAT, "Meeting 11/20/27 3pm", "Meeting", "2027-11-20T15:00", "2027-11-20T16:00", ""),
    ("2028-02-28T12:00", "Meeting 2/29 3pm", "Meeting", "2028-02-29T15:00", "2028-02-29T16:00", ""),
    ("2026-11-14T10:36", "Meeting 11/14 3pm", "Meeting", "2026-11-14T15:00", "2026-11-14T16:00", ""),
    # 12-hour ambiguities
    (SAT, "X Fri 12", "X", "2026-11-20T12:00", "2026-11-20T13:00", ""),
    (SAT, "X Fri 9", "X", "2026-11-20T09:00", "2026-11-20T10:00", ""),
    (SAT, "X Fri 6", "X", "2026-11-20T18:00", "2026-11-20T19:00", ""),
    (SAT, "X Fri 8", "X", "2026-11-20T08:00", "2026-11-20T09:00", ""),
    (SAT, "X Fri 11:30", "X", "2026-11-20T11:30", "2026-11-20T12:30", ""),
    (SAT, "X Fri 2:30", "X", "2026-11-20T14:30", "2026-11-20T15:30", ""),
    (SAT, "X Fri 14:00", "X", "2026-11-20T14:00", "2026-11-20T15:00", ""),
    (SAT, "X Fri at 14", "X", "2026-11-20T14:00", "2026-11-20T15:00", ""),
    (SAT, "X Fri 12am", "X", "2026-11-20T00:00", "2026-11-20T01:00", ""),
    (SAT, "X Fri 12pm", "X", "2026-11-20T12:00", "2026-11-20T13:00", ""),
    (SAT, "X Fri noon", "X", "2026-11-20T12:00", "2026-11-20T13:00", ""),
    (SAT, "X Fri 9pm", "X", "2026-11-20T21:00", "2026-11-20T22:00", ""),
    (SAT, "Coffee tomorrow at 3", "Coffee", "2026-11-15T15:00", "2026-11-15T16:00", ""),
    (SAT, "Coffee tomorrow at 9", "Coffee", "2026-11-15T09:00", "2026-11-15T10:00", ""),
    (SAT, "Coffee at 3pm tomorrow", "Coffee", "2026-11-15T15:00", "2026-11-15T16:00", ""),
    # ranges, also across noon
    (SAT, "X Fri 12-1", "X", "2026-11-20T12:00", "2026-11-20T13:00", ""),
    (SAT, "X Fri 11-1", "X", "2026-11-20T11:00", "2026-11-20T13:00", ""),
    (SAT, "X Fri 11-12", "X", "2026-11-20T11:00", "2026-11-20T12:00", ""),
    (SAT, "X Fri 7-9", "X", "2026-11-20T19:00", "2026-11-20T21:00", ""),
    (SAT, "X Fri 8-10", "X", "2026-11-20T08:00", "2026-11-20T10:00", ""),
    (SAT, "X Fri 9 to 5", "X", "2026-11-20T09:00", "2026-11-20T17:00", ""),
    (SAT, "X Fri 11am-1pm", "X", "2026-11-20T11:00", "2026-11-20T13:00", ""),
    (SAT, "X Fri 11-1pm", "X", "2026-11-20T11:00", "2026-11-20T13:00", ""),
    (SAT, "X Fri 11:30-12:30", "X", "2026-11-20T11:30", "2026-11-20T12:30", ""),
    (SAT, "X Fri 10-noon", "X", "2026-11-20T10:00", "2026-11-20T12:00", ""),
    (SAT, "X Fri noon-1", "X", "2026-11-20T12:00", "2026-11-20T13:00", ""),
    (SAT, "X Fri 9am-noon", "X", "2026-11-20T09:00", "2026-11-20T12:00", ""),
    (SAT, "X Fri from 2 until 3:30", "X", "2026-11-20T14:00", "2026-11-20T15:30", ""),
    (SAT, "X Fri 2:30-4pm", "X", "2026-11-20T14:30", "2026-11-20T16:00", ""),
    (SAT, "X Fri 9am-10am", "X", "2026-11-20T09:00", "2026-11-20T10:00", ""),
    (SAT, "X Fri 9am - 10am", "X", "2026-11-20T09:00", "2026-11-20T10:00", ""),
    (SAT, "X Fri 7pm-9", "X", "2026-11-20T19:00", "2026-11-20T21:00", ""),
    # lengths
    (SAT, "X Fri 3pm 1.5h", "X", "2026-11-20T15:00", "2026-11-20T16:30", ""),
    (SAT, "X Fri 3pm 45m", "X", "2026-11-20T15:00", "2026-11-20T15:45", ""),
    (SAT, "X Fri 3pm for 2 hours", "X", "2026-11-20T15:00", "2026-11-20T17:00", ""),
    (SAT, "X Fri 11pm 3h", "X", "2026-11-20T23:00", "2026-11-21T02:00", ""),
    # places
    (SAT, "Coffee tomorrow 3pm @ Starbucks on Main", "Coffee", "2026-11-15T15:00", "2026-11-15T16:00", "Starbucks on Main"),
    (SAT, "Dinner at Joe's tomorrow 6pm", "Dinner", "2026-11-15T18:00", "2026-11-15T19:00", "Joe's"),
    (SAT, "Meet tomorrow 3pm at 114 McAdams", "Meet", "2026-11-15T15:00", "2026-11-15T16:00", "114 McAdams"),
    (SAT, "Meet tomorrow 3pm at Room 5", "Meet", "2026-11-15T15:00", "2026-11-15T16:00", "Room 5"),
    (SAT, "Meet @ noon tomorrow", "Meet", "2026-11-15T12:00", "2026-11-15T13:00", ""),
    (SAT, "Meet at 3pm at Esso tomorrow", "Meet", "2026-11-15T15:00", "2026-11-15T16:00", "Esso"),
    (SAT, "Drive to Greenville Sat 3pm", "Drive to Greenville", "2026-11-21T15:00", "2026-11-21T16:00", ""),
    # daylight saving, America/New_York (2027: spring forward 3/14 02:00, fall back 11/7 02:00)
    ("2027-03-01T09:00", "Early 3/14 1:30am 1h", "Early", "2027-03-14T01:30", "2027-03-14T03:30", ""),
    ("2027-03-01T09:00", "Night 3/13 11pm 3h", "Night", "2027-03-13T23:00", "2027-03-14T03:00", ""),
    ("2027-03-01T09:00", "Morning 3/14 3am-4am", "Morning", "2027-03-14T03:00", "2027-03-14T04:00", ""),
    ("2027-03-01T09:00", "Afternoon 3/14 2-3", "Afternoon", "2027-03-14T14:00", "2027-03-14T15:00", ""),
    ("2027-10-01T09:00", "Late 11/7 3am", "Late", "2027-11-07T03:00", "2027-11-07T04:00", ""),
    ("2027-10-01T09:00", "Day 11/7 11pm 2h", "Day", "2027-11-07T23:00", "2027-11-08T01:00", ""),
]
# (now, line, [substrings every one of which must be in some problem])
BAD = [
    (SAT, "Review today 9am", ["already passed"]),
    (SAT, "Review today 10:30am", ["already passed"]),
    (SAT, "Lunch 12-1", ["Which day?"]),
    (SAT, "Review 4pm", ["Which day?"]),
    (SAT, "Lunch tomorrow", ["What time?"]),
    (SAT, "Lunch tomorrow all day", ["All-day", "What time?"]),
    (SAT, "tomorrow 3pm", ["What is it called?"]),
    (SAT, "", ["Nothing to add"]),
    (SAT, "   ", ["Nothing to add"]),
    (SAT, "Lunch tomorrow Fri 3pm", ["More than one day"]),
    (SAT, "Lunch 2/30 3pm", ["not a date"]),
    (SAT, "Lunch 13/5 3pm", ["not a date"]),
    ("2027-02-28T12:00", "Meeting 2/29 3pm", ["not a date"]),
    (SAT, "Lunch next week 3pm", ["Which day?"]),
    (SAT, "Meeting 2025-01-01 3pm", ["in the past"]),
    (SAT, "Meeting 11/20/2025 3pm", ["in the past"]),
    (SAT, "X Fri 3pm 4pm", ["More than one time"]),
    (SAT, "X Fri 3pm-4pm 90m", ["range and a length"]),
    (SAT, "X Fri 3pm 4-5pm", ["A time and a range"]),
    (SAT, "X Fri 13pm", ["not a time"]),
    (SAT, "X Fri 25:00", ["not an hour"]),
    (SAT, "X Fri 9:75am", ["Minutes"]),
    (SAT, "X Fri 3pm 30m 1h", ["More than one length"]),
    (SAT, "X Fri 10pm-1am", ["not after the start"]),
    (SAT, "X Fri 5pm-4pm", ["not after the start"]),
    ("2027-03-01T09:00", "Gap 3/14 2:30am", ["does not exist"]),
    ("2027-03-01T09:00", "Gap 3/14 2am-3am", ["does not exist"]),
    ("2027-10-01T09:00", "Fold 11/7 1:30am", ["happens twice"]),
    ("2027-10-01T09:00", "Fold 11/7 12:30am 2h", ["happens twice"]),
]

for now, line, subj, s, e, loc in GOOD:
    r = qe.parse(line, at(now))
    got = (r["subject"], r["start"], r["end"], r["location"])
    check("%-48s -> %s %s-%s%s" % (line, subj, s[5:], e[11:], " @" + loc if loc else ""),
          got == (subj, s, e, loc) and not r["problems"] and r["human"], "%s %s" % (got, r["problems"]))
for now, line, wants in BAD:
    r = qe.parse(line, at(now))
    ok = r["problems"] and all(any(w in p for p in r["problems"]) for w in wants) and r["human"] == ""
    check("problem: %-40r %s" % (line, wants), bool(ok), json.dumps(r))

# the human line, as the brief spells it
r = qe.parse("Faculty meeting Fri 2:30pm 90m at McAdams 114", at(SAT))
check("human: 'Fri Nov 20, 2:30 to 4:00 pm, McAdams 114'", r["human"] == "Fri Nov 20, 2:30 to 4:00 pm, McAdams 114", r["human"])
r = qe.parse("X Fri 11am-1pm", at(SAT))
check("human: am to pm", r["human"] == "Fri Nov 20, 11:00 am to 1:00 pm", r["human"])
r = qe.parse("X Fri 11pm 3h", at(SAT))
check("human: across midnight", r["human"] == "Fri Nov 20, 11:00 pm to Sat Nov 21, 2:00 am", r["human"])
r = qe.parse("Trip 1/5 2pm", at(SAT))
check("human: other year shows it", r["human"] == "Tue Jan 5 2027, 2:00 to 3:00 pm", r["human"])
r = qe.parse("X Fri 12-1", at(SAT))
check("human: noon hour", r["human"] == "Fri Nov 20, 12:00 to 1:00 pm", r["human"])

# the command line: parse prints one JSON object, QUICK_EVENT_NOW is honoured
env = dict(os.environ, QUICK_EVENT_NOW=SAT)
p = subprocess.run([sys.executable, SCRIPT, "parse", "Dentist 11/20 9am"], capture_output=True, text=True, env=env)
try:
    j = json.loads(p.stdout)
except ValueError:
    j = {}
check("cli parse: JSON with the five keys", p.returncode == 0 and sorted(j) == ["end", "human", "location", "problems", "start", "subject"] and j["start"] == "2026-11-20T09:00", p.stdout + p.stderr)
p = subprocess.run([sys.executable, SCRIPT, "parse", "Lunch with Sam", "tomorrow", "12-1"], capture_output=True, text=True, env=env)
check("cli parse: words may arrive as separate arguments", json.loads(p.stdout)["start"] == "2026-11-15T12:00", p.stdout)
p = subprocess.run([sys.executable, SCRIPT], capture_output=True, text=True, env=env)
check("no mode: usage, exit 2", p.returncode == 2 and "quick-event parse" in p.stderr)

# ---- add, with a fake tool, notify-send and systemctl --------------------------------------------
work = tempfile.mkdtemp(prefix="events-test-")
stubs = os.path.join(work, "stubs"); os.makedirs(stubs)
run = os.path.join(work, "run"); os.makedirs(run, mode=0o700)
log = os.path.join(work, "log")          # one JSON line per fake call
def script(name, body):
    path = os.path.join(stubs, name)
    with open(path, "w") as f:
        f.write(body)
    os.chmod(path, 0o755)
    return path
fake_tool = script("exchange-rules.py", '''#!/usr/bin/env python3
import json, os, sys
argv = sys.argv[1:]
spec = argv[-1]
st = os.stat(spec)
with open(spec) as f:
    text = f.read()
with open(%r, "a") as f:
    f.write(json.dumps({"who": "tool", "argv": argv, "spec_text": text, "mode": oct(st.st_mode & 0o777), "dir": os.path.dirname(spec)}) + "\\n")
mode = os.environ.get("FAKE_TOOL_MODE", "ok")
d = json.loads(text)
if mode == "fail":
    sys.stderr.write("Traceback (most recent call last):\\nGraphError: 401 token expired\\n"); sys.exit(1)
start, end = d["start"], d["end"]
if mode == "shifted":
    start = start[:11] + "09:00"
print("%%s\\n  %%s -> %%s (Eastern Standard Time)\\n  location: %%s\\n  attendees: none\\n  id: AAMk" %% (d["subject"], start, end, d.get("location")))
if "--dry-run" in argv:
    print("dry run: nothing created, nothing sent")
''' % log)
script("notify-send", '#!/bin/sh\nprintf \'%%s\\n\' "$(python3 -c \'import json,sys; print(json.dumps({"who":"notify","argv":sys.argv[1:]}))\' "$@")" >> %s\n' % log)
script("systemctl", '#!/bin/sh\nprintf \'%%s\\n\' "$(python3 -c \'import json,sys; print(json.dumps({"who":"systemctl","argv":sys.argv[1:]}))\' "$@")" >> %s\n' % log)

def add(line, *flags, mode="ok"):
    open(log, "w").close()
    e = dict(os.environ, PATH=stubs + os.pathsep + os.environ["PATH"], XDG_RUNTIME_DIR=run, QUICK_EVENT_NOW=SAT,
             QUICK_EVENT_TOOL=fake_tool, FAKE_TOOL_MODE=mode)
    p = subprocess.run([sys.executable, SCRIPT, "add", *flags, line], capture_output=True, text=True, env=e)
    calls = [json.loads(l) for l in open(log) if l.strip()]
    return p, calls
def of(calls, who): return [c for c in calls if c["who"] == who]

p, calls = add("Faculty meeting Fri 2:30pm 90m at McAdams 114")
t = of(calls, "tool")
check("add: the tool is run once", p.returncode == 0 and len(t) == 1, p.stderr)
if t:
    argv = t[0]["argv"]
    check("add: arguments are `event SPEC` and nothing else", len(argv) == 2 and argv[0] == "event" and argv[1].endswith(".json"), argv)
    check("add: no --invite, no --dry-run", "--invite" not in argv and "--dry-run" not in argv)
    want = {"subject": "Faculty meeting", "start": "2026-11-20T14:30", "end": "2026-11-20T16:00", "location": "McAdams 114"}
    check("add: spec content exact", json.loads(t[0]["spec_text"]) == want, t[0]["spec_text"])
    check("add: spec text is one compact JSON object", t[0]["spec_text"] == json.dumps(want, ensure_ascii=False), t[0]["spec_text"])
    check("add: spec has no attendees, optional or teams", not ({"attendees", "optional", "teams"} & set(json.loads(t[0]["spec_text"]))))
    check("add: spec lives under $XDG_RUNTIME_DIR, private (0600), and is removed afterwards",
          t[0]["dir"].startswith(run) and t[0]["mode"] == "0o600" and not os.listdir(t[0]["dir"]), "%s %s %s" % (t[0]["dir"], t[0]["mode"], os.listdir(t[0]["dir"])))
n = of(calls, "notify")
check("add: one notification with the read-back time", len(n) == 1 and "Event added" in n[0]["argv"] and any("Fri Nov 20, 2:30 to 4:00 pm, McAdams 114" in a for a in n[0]["argv"]) and "critical" not in n[0]["argv"], n)
s = of(calls, "systemctl")
check("add: calendar pull started (user, no-block)", len(s) == 1 and s[0]["argv"] == ["--user", "start", "--no-block", "pull-calendars.service"], s)

p, calls = add("Lunch tomorrow 12-1", mode="ok")
t = of(calls, "tool")
check("add: a spec without a place has no location key", t and json.loads(t[0]["spec_text"]) == {"subject": "Lunch", "start": "2026-11-15T12:00", "end": "2026-11-15T13:00"}, t and t[0]["spec_text"])
p, calls = add("Attendees meeting tomorrow 3pm at bob@example.org")
t = of(calls, "tool")
check("add: words like attendees or an address in the line never become attendees", t and "attendees" not in json.loads(t[0]["spec_text"]) and json.loads(t[0]["spec_text"])["subject"] == "Attendees meeting")

p, calls = add("Lunch tomorrow 12-1", "--dry-run")
t = of(calls, "tool")
check("add --dry-run: the flag is passed to the tool, before the spec", len(t) == 1 and t[0]["argv"][:2] == ["event", "--dry-run"] and len(t[0]["argv"]) == 3, t)
check("add --dry-run: says it is a dry run, starts no calendar pull", any("Would add (dry run)" in n["argv"] for n in of(calls, "notify")) and not of(calls, "systemctl") and p.returncode == 0)
p, calls = add("--dry-run", "Lunch tomorrow 12-1")
check("add --dry-run before the line works the same", len(of(calls, "tool")) == 1 and "--dry-run" in of(calls, "tool")[0]["argv"])

p, calls = add("Lunch tomorrow 12-1", mode="fail")
n = of(calls, "notify")
check("failure: exit 1, the tool's message in a critical notification", p.returncode == 1 and len(n) == 1 and "critical" in n[0]["argv"] and "Event not added" in n[0]["argv"]
      and any("token expired" in a for a in n[0]["argv"]), "%s %s" % (p.returncode, n))
check("failure: no calendar pull", not of(calls, "systemctl"))
check("failure: the spec file is still removed", not os.listdir(os.path.join(run, "quick-event")))

p, calls = add("Lunch tomorrow", mode="ok")
check("problem line: refused with exit 2, the tool never runs", p.returncode == 2 and not of(calls, "tool") and not of(calls, "systemctl"), calls)
n = of(calls, "notify")
check("problem line: notification says why", n and "critical" in n[0]["argv"] and any("What time?" in a for a in n[0]["argv"]), n)
p, calls = add("Lunch 12-1 at Esso")
check("problem line (no day): refused", p.returncode == 2 and not of(calls, "tool"))

p, calls = add("Lunch tomorrow 12-1", mode="shifted")
n = of(calls, "notify")
check("read-back differs from what was sent: said so, critical", p.returncode == 0 and n and "Saved, but the read-back differs" in n[0]["argv"] and "critical" in n[0]["argv"], n)

# the tool is only ever called as `TOOL event [--dry-run] SPEC`: look at the source, too
src = open(SCRIPT).read()
check("source: the exchange tool is only ever started as [tool, \"event\", ...]", src.count("[tool, \"event\"]") == 1 and src.count("QUICK_EVENT_TOOL") == 2)
check("source: never builds an attendees key", '"attendees"' not in src and "'attendees'" not in src)

print("RESULT pass %d fail %d" % (passed, failed))
sys.exit(1 if failed else 0)
