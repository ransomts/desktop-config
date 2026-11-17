"""Shared pieces of session-save and session-restore (installed beside them in ~/.local/bin).

Nothing here stores or reads window titles for anything but a yes/no test (is this a
file dialog?) -- a title never reaches a file, a log line or a command.
"""
import configparser, glob, json, os, re, shlex, subprocess, sys, tempfile, time

DEFAULT_SKIP = [
    "firefox", "emacs",                          # restore themselves (session restore, the emacs daemon's desktop)
    "discord", "nm-applet", "blueman", "git-annex",   # autostarted at login (~/.config/autostart)
]
DEFAULTS = {
    "enabled": False,
    "skip": DEFAULT_SKIP,
    "allow": [],                  # when not empty, only these apps are reopened
    "terminalsRestoreCwd": True,
    "mode": "move",               # "move": launch, wait for the window, move it; "exec": hl.exec_cmd rules
    "delayMs": 600,
    "timeoutS": 10,
}
TERMINALS = {"com.mitchellh.ghostty"}              # classes whose working directory is saved

# never saved: shell and system helper windows, short-lived tools, anything on a special workspace
NEVER = re.compile(r"^(quickshell|hyprpolkitagent|polkit-gnome-authentication-agent-1|xdg-desktop-portal.*|"
                   r"org\.pulseaudio\.pavucontrol|pavucontrol|com\.saivert\.pwvucontrol|org\.gnome\.Calculator|"
                   r"nm-connection-editor|blueman-manager|keymapp|org\.tsr\.ncmpcpp)$", re.I)
# the same title tests hyprland.lua uses to float dialogs and picture-in-picture
DIALOG = re.compile(r"^(Open|Save|Select|Choose|Export|Import|Upload)( [A-Za-z]+)? "
                    r"(File|Files|Folder|Folders|Directory|As|Image|Document).*$|^Picture[- ]in[- ]picture$", re.I)


def state_dir():
    return os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "session")


def config_path():
    return os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "shell", "session.json")


def load_config():
    cfg = dict(DEFAULTS)
    try:
        with open(config_path(), encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            cfg.update({k: v for k, v in data.items() if k in DEFAULTS})
    except (OSError, ValueError):
        pass
    return cfg


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".tmp-")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)


def set_enabled(on):
    """Write "enabled" into the config, keeping every other key; create the file with defaults when missing."""
    path = config_path()
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            data = {}
    except (OSError, ValueError):
        data = dict(DEFAULTS)
    data["enabled"] = bool(on)
    write_json(path, data)


def hyprctl_json(what):
    r = subprocess.run(["hyprctl", "-j", what], capture_output=True, text=True, timeout=5)
    if r.returncode != 0:
        raise RuntimeError("hyprctl -j %s failed: %s" % (what, r.stderr.strip()))
    return json.loads(r.stdout)


# ---- .desktop resolution (same idea as hypr-window-list: file name, then StartupWMClass) ----
def app_dirs():
    env = os.environ.get("SESSION_APP_DIRS")
    if env:
        return [d for d in env.split(os.pathsep) if d]
    home_data = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    dirs = [home_data + "/applications"]
    for d in (os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share").split(":"):
        if d:
            dirs.append(d + "/applications")
    dirs += ["/var/lib/flatpak/exports/share/applications", home_data + "/flatpak/exports/share/applications"]
    return dirs


def desktop_table():
    """lowercase class or file stem -> (desktop id without .desktop, display name). First directory wins."""
    table = {}
    for d in app_dirs():
        for f in sorted(glob.glob(d + "/*.desktop")):
            cp = configparser.RawConfigParser(strict=False, interpolation=None)
            try:
                cp.read(f, encoding="utf-8")
                e = cp["Desktop Entry"]
            except Exception:
                continue
            if e.get("Type", "Application") != "Application":
                continue
            stem = os.path.basename(f)[:-8]
            val = (stem, e.get("Name") or stem)
            table.setdefault(stem.lower(), val)
            if e.get("StartupWMClass"):
                table.setdefault(e["StartupWMClass"].lower(), val)
    return table


def resolve(table, cls):
    c = (cls or "").lower()
    return table.get(c) or table.get(c.split(".")[-1])


# ---- terminal working directories ----
def _children(proc, pid):
    out = []
    for p in os.listdir(proc):
        if not p.isdigit():
            continue
        try:
            with open("%s/%s/stat" % (proc, p), encoding="utf-8", errors="replace") as f:
                st = f.read()
            ppid = int(st.rsplit(")", 1)[1].split()[1])
        except (OSError, ValueError, IndexError):
            continue
        if ppid == pid:
            out.append(int(p))
    return sorted(out)


def terminal_cwds(clients, proc=None):
    """window address -> cwd or None, for terminal windows.

    Ghostty runs every window (and tab) in ONE process (--gtk-single-instance=true) and hyprctl only
    gives that pid, so a window cannot be tied to its own shell. The cwd is therefore saved only when
    it is unambiguous: every shell that is a direct child of the process has the same working
    directory (the common case of one window with one shell). Otherwise the cwd is None.
    """
    proc = proc or os.environ.get("SESSION_PROC") or "/proc"
    by_pid = {}
    for c in clients:
        by_pid.setdefault(c.get("pid"), []).append(c)
    result = {}
    for pid, wins in by_pid.items():
        cwds = set()
        try:
            for ch in _children(proc, pid):
                try:
                    cwds.add(os.readlink("%s/%d/cwd" % (proc, ch)))
                except OSError:
                    cwds.add(None)
        except (OSError, TypeError):
            cwds = {None}
        cwd = next(iter(cwds)) if len(cwds) == 1 else None
        for w in wins:
            result[w["address"]] = cwd
    return result


# ---- the snapshot ----
def snapshot(clients, monitors, table, proc=None):
    """Return (entries, skipped_counts). No titles, no addresses, no pids in the entries."""
    order = sorted(monitors, key=lambda m: (m.get("x", 0), m.get("y", 0)))
    slot_of = {m["id"]: i + 1 for i, m in enumerate(order)}
    skipped = {"special": 0, "plain-workspace": 0, "helper": 0, "dialog": 0, "unknown": 0, "unmapped": 0}
    cand = []
    for c in clients:
        ws = c.get("workspace") or {}
        wid = ws.get("id", 0)
        cls = c.get("class") or ""
        if not c.get("mapped", True):
            skipped["unmapped"] += 1
        elif ws.get("type") == "special" or str(ws.get("name", "")).startswith("special") or wid < 0:
            skipped["special"] += 1
        elif wid < 11:
            skipped["plain-workspace"] += 1
        elif not cls or NEVER.match(cls):
            skipped["helper"] += 1
        elif DIALOG.match(c.get("title") or ""):
            skipped["dialog"] += 1
        elif not resolve(table, cls):
            skipped["unknown"] += 1
        else:
            cand.append(c)
    cwds = terminal_cwds([c for c in cand if c["class"] in TERMINALS], proc) if any(c["class"] in TERMINALS for c in cand) else {}
    entries = []
    for c in cand:
        app, _ = resolve(table, c["class"])
        wid = c["workspace"]["id"]
        e = {"app": app, "class": c["class"], "desktop": wid // 10,
             "slot": slot_of.get(c.get("monitor"), wid % 10 or 1), "floating": bool(c.get("floating"))}
        if e["floating"] and c.get("size"):
            e["size"] = [int(c["size"][0]), int(c["size"][1])]
        if c["class"] in TERMINALS:
            e["cwd"] = cwds.get(c["address"])
        entries.append(e)
    entries.sort(key=lambda e: (e["desktop"], e["slot"], e["app"], e.get("cwd") or ""))
    return entries, {k: v for k, v in skipped.items() if v}


# ---- what restore does with a saved session ----
def _names(e):
    a = e["app"].lower()
    return {a, a.split(".")[-1], (e.get("class") or "").lower()}


def filtered(entries, cfg):
    """(restorable, [(entry, reason)])"""
    skip = {s.lower() for s in cfg.get("skip") or []}
    allow = {s.lower() for s in cfg.get("allow") or []}
    keep, dropped = [], []
    for e in entries:
        n = _names(e)
        if n & skip:
            dropped.append((e, "skip list"))
        elif allow and not (n & allow):
            dropped.append((e, "not on the allow list"))
        else:
            keep.append(e)
    return keep, dropped


def running_counts(clients, table):
    counts = {}
    for c in clients:
        r = resolve(table, c.get("class"))
        if r and c.get("mapped", True):
            counts[r[0]] = counts.get(r[0], 0) + 1
    return counts


def plan(entries, cfg, clients, table):
    """(to_open, [(entry, reason)]): applies the skip and allow lists, then drops as many entries of
    an app as it already has windows open (all of them when it has at least as many)."""
    keep, dropped = filtered(entries, cfg)
    run = running_counts(clients, table)
    groups = {}
    for e in keep:
        groups.setdefault(e["app"], []).append(e)
    to_open = []
    for app, g in groups.items():
        r = run.get(app, 0)
        for e in g[:r]:
            dropped.append((e, "already running"))
        to_open += g[r:]
    to_open.sort(key=lambda e: (e["desktop"], e["slot"], e["app"]))
    return to_open, dropped


def workspace_of(e, nmon):
    return e["desktop"] * 10 + max(1, min(int(e["slot"]), max(1, nmon)))


def launch_argv(e, cfg, mode="move"):
    if e.get("class") in TERMINALS and cfg.get("terminalsRestoreCwd") and e.get("cwd") and os.path.isdir(e["cwd"]):
        # exec mode wants a process of its own: a single-instance ghostty window is made by the old process,
        # which Hyprland's exec rule (matched by the process it started) would never see
        single = "true" if mode == "move" else "false"
        return ["uwsm", "app", "--", "ghostty", "--gtk-single-instance=" + single, "--working-directory=" + e["cwd"]]
    if not re.fullmatch(r"[A-Za-z0-9._+-]+", e["app"]):
        raise ValueError("odd desktop id")
    return ["uwsm", "app", "--", e["app"] + ".desktop"]


def lua_q(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def exec_lua(e, cfg, nmon):
    """The `hyprctl eval` code for the exec-rule form."""
    cmd = shlex.join(launch_argv(e, cfg, "exec"))
    rules = "workspace = %s" % lua_q("%d silent" % workspace_of(e, nmon))
    if e.get("floating") and e.get("size"):
        rules += ", float = true, size = %s" % lua_q("%d %d" % tuple(e["size"]))
    return "hl.exec_cmd(%s, { %s })" % (lua_q(cmd), rules)


def move_lua(address, ws):
    return 'hl.dispatch(hl.dsp.window.move({ workspace = %d, window = hl.get_window(%s), follow = false }))' % (ws, lua_q("address:" + address))


def summary(entries):
    names = {}
    for e in entries:
        label = e["app"].split(".")[-1]
        names[label] = names.get(label, 0) + 1
    parts = ["%s x%d" % (k, v) if v > 1 else k for k, v in sorted(names.items(), key=lambda kv: -kv[1])]
    return ", ".join(parts[:4]) + (", ..." if len(parts) > 4 else "")


def load_last():
    try:
        with open(os.path.join(state_dir(), "last.json"), encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) and isinstance(d.get("entries"), list) else None
    except (OSError, ValueError):
        return None
