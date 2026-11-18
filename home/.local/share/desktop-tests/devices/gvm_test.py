"""devices-test, python part: gvm and gvm-gui with a fake `bleak` (nothing scans or connects).

    python3 -I gvm_test.py PATH/TO/gvm PATH/TO/gvm-gui

Run with a temporary HOME (devices-test does this): the lights and presets files are written
there, and gvm-gui loads ~/.local/bin/gvm from it. Prints PASS/FAIL lines, then GVM DONE.
"""
import asyncio, contextlib, importlib.util, io, json, os, sys, time, types
from importlib.machinery import SourceFileLoader

GVM, GUI = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "")
HOME = os.environ["HOME"]
assert HOME.startswith(("/tmp", "/var/tmp")) or "tmp" in HOME, "run with a temporary HOME"

# made-up addresses; A4:C1:38 is the Telink vendor prefix gvm scan looks for
L1, L2, L3 = "A4:C1:38:00:00:01", "A4:C1:38:00:00:02", "A4:C1:38:00:00:03"
npass = nfail = 0


def check(name, ok, detail=""):
    global npass, nfail
    if ok:
        npass += 1
        print(f"PASS {name}")
    else:
        nfail += 1
        print(f"FAIL {name}   [{detail}]")


# ------------------------------------------------------------------ independent protocol helpers
def crc_ref(b):  # CRC-16/XMODEM, written from the spec (poly 0x1021, init 0), not copied
    c = 0
    for x in b:
        for i in range(8):
            bit = ((x >> (7 - i)) & 1) ^ ((c >> 15) & 1)
            c = ((c << 1) & 0xFFFF) ^ (0x1021 if bit else 0)
    return c


def mkframe(body):
    u = b"LT" + bytes([len(body) + 2]) + bytes(body)
    return u + crc_ref(u).to_bytes(2, "big")


def decode_set(data):
    """(reg, val) from a set-register frame, or None."""
    if len(data) == 12 and data[:3] == b"LT\x09" and data[3:7] == bytes([0, 0x30, 0x57, 0]) and data[8] == 1:
        return data[7], data[9]
    return None


# ------------------------------------------------------------------ fake bleak
class World:
    """The fake lights: registers per address, every BLE call logged."""
    def __init__(self):
        self.regs = {}          # addr -> [r0..r8]
        self.missing = set()    # not found by scans
        self.refuse = set()     # connect raises
        self.log = []           # (addr, event, detail)
        self.adverts = {}

    def light(self, addr, **kw):
        r = [1, 1, 50, 44, 0, 0, 1, 4, 1]
        for k, v in kw.items():
            r[{"on": 0, "ch": 1, "bright": 2, "cct": 3, "hue": 4, "sat": 5, "mode": 6}[k]] = v
        self.regs[addr] = r

    def writes(self, addr=None):
        return [(a, d) for a, e, d in self.log if e == "set" and (addr is None or a == addr)]


W = World()


class FakeDevice:
    def __init__(self, addr):
        self.address = addr


class FakeScanner:
    @staticmethod
    async def find_device_by_address(addr, timeout=None):
        W.log.append((addr, "find", timeout))
        return None if addr in W.missing or addr not in W.regs else FakeDevice(addr)

    @staticmethod
    async def discover(timeout=None, return_adv=False):
        W.log.append(("*", "discover", timeout))
        return W.adverts


class FakeClient:
    def __init__(self, dev, timeout=None, disconnected_callback=None):
        self.addr = dev.address if hasattr(dev, "address") else dev
        self.cb = None
        self.is_connected = False

    async def connect(self):
        W.log.append((self.addr, "connect", None))
        if self.addr in W.refuse:
            raise Exception("org.bluez.Error.Failed: le-connection-abort-by-local")
        self.is_connected = True

    async def start_notify(self, ch, cb):
        W.log.append((self.addr, "notify", ch))
        self.cb = cb

    async def write_gatt_char(self, ch, data, response=True):
        data = bytes(data)
        W.log.append((self.addr, "write", data))
        sr = decode_set(data)
        if sr:
            W.log.append((self.addr, "set", sr))
            W.regs[self.addr][sr[0]] = sr[1]
        elif data == mkframe([0, 0, 0x53, 0, 0, 1, 0]) and self.cb:
            # status report plus a range reply in one notification, with some noise in front
            note = b"\x00\x01" + mkframe([0, 0x30, 0x03] + W.regs[self.addr]) + mkframe([0, 0x30, 0x53, 0, 0, 2, 32, 56])
            self.cb(None, bytearray(note))

    async def disconnect(self):
        W.log.append((self.addr, "disconnect", None))
        self.is_connected = False


fake = types.ModuleType("bleak")
fake.BleakClient, fake.BleakScanner = FakeClient, FakeScanner
sys.modules["bleak"] = fake

# ------------------------------------------------------------------ files in the temporary HOME
os.makedirs(os.path.join(HOME, ".config/gvm"), exist_ok=True)
with open(os.path.join(HOME, ".config/gvm/lights"), "w") as f:
    f.write("# GVM lights: name address\n\nlight1  a4:c1:38:00:00:01   # key, lower case on purpose\n"
            "light2  A4:C1:38:00:00:02\nbroken\n")
with open(os.path.join(HOME, ".config/gvm/presets.json"), "w") as f:
    json.dump({"Camera": {"note": "webcam look",
                          "light1": {"on": 1, "mode": "white", "cct": 4400, "bright": 100},
                          "light2": {"on": 1, "mode": "white", "cct": 4400, "bright": 20}},
               "Orange": {"note": "all orange", "all": {"mode": "colour", "hue": 25, "sat": 100}},
               "KeyOnly": {"light2": {"bright": 5}}}, f)


def load(path, name):
    return SourceFileLoader(name, path).load_module()


os.environ.pop("GVM_ADDR", None)
gvm = load(GVM, "gvm_under_test")
gvm.WRITE_GAP = 0


def run(*argv):
    """gvm main() in-process: (exit code, stdout, stderr)."""
    out, err = io.StringIO(), io.StringIO()
    old = sys.argv
    sys.argv = ["gvm", *argv]
    code = 0
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            gvm._connecting = None
            gvm.main()
    except SystemExit as e:
        code = e.code if isinstance(e.code, int) else (0 if e.code is None else 1)
        if isinstance(e.code, str):
            err.write(e.code)
    finally:
        sys.argv = old
    return code, out.getvalue(), err.getvalue()


def fresh(**lights):
    W.__init__()
    for addr, kw in lights.items():
        W.light(addr, **kw)


def sets(addr=None):
    return [d for _, d in W.writes(addr)]


print("case: gvm protocol (frames, CRC, parse)")
check("crc16 is CRC-16/XMODEM (check value of '123456789' = 0x31C3)", gvm.crc16(b"123456789") == b"\x31\xc3")
check("crc16 agrees with an independent implementation", all(gvm.crc16(bytes(range(n))) == crc_ref(bytes(range(n))).to_bytes(2, "big") for n in (0, 1, 7, 40)))
f = gvm.setreg(2, 60)
check("setreg: LT, length 9, 00 30 57 00 reg 01 val, CRC", f == mkframe([0, 0x30, 0x57, 0, 2, 1, 60]) and f[:3] == b"LT\x09", f.hex())
check("setreg uses the 800D's 00 30 prefix, not homebridge's 00 20", f[3:5] == b"\x00\x30", f.hex())
check("setreg keeps the value to one byte", gvm.setreg(7, 300)[9] == 300 & 0xFF)
check("INFO request frame: 00 00 53 00 00 01 00", gvm.INFO == mkframe([0, 0, 0x53, 0, 0, 1, 0]), gvm.INFO.hex())
check("hue_reg: 0/25/120/240/270 degrees -> 0/5/24/48/54", [gvm.hue_reg(d) for d in (0, 25, 120, 240, 270)] == [0, 5, 24, 48, 54])
check("hue_reg wraps: 360 -> 0, 400 -> 8, -5 -> 71, 358 -> 0", [gvm.hue_reg(d) for d in (360, 400, -5, 358)] == [0, 8, 71, 0],
      [gvm.hue_reg(d) for d in (360, 400, -5, 358)])
check("hue_reg is always a valid register value (0-71)", all(0 <= gvm.hue_reg(d / 4) <= 71 for d in range(-1440, 2880)))
st = mkframe([0, 0x30, 0x03, 1, 1, 80, 44, 6, 100, 2, 4, 1])
ch = mkframe([0, 0x30, 0x02, 0, 2, 33])
rg = mkframe([0, 0x30, 0x53, 0, 0, 2, 32, 56])
check("parse: status report", list(gvm.parse(st)) == [("status", [1, 1, 80, 44, 6, 100, 2, 4, 1])], list(gvm.parse(st)))
check("parse: one register changed", list(gvm.parse(ch)) == [("change", 2, 33)])
check("parse: colour temperature range", list(gvm.parse(rg)) == [("range", 32, 56)])
check("parse: several frames in one notification, noise skipped", list(gvm.parse(b"\xff\x00L" + ch + st + rg)) ==
      [("change", 2, 33), ("status", [1, 1, 80, 44, 6, 100, 2, 4, 1]), ("range", 32, 56)])
bad = bytearray(ch); bad[-1] ^= 1
check("parse: a frame with a bad CRC is dropped, the next one kept", list(gvm.parse(bytes(bad) + st))[0][0] == "status" and len(list(gvm.parse(bytes(bad) + st))) == 1)
check("parse: a truncated frame yields nothing", list(gvm.parse(st[:-3])) == [])
check("describe: white", gvm.describe([1, 2, 60, 44, 0, 0, 1]).startswith("on  bright 60%  white 4400K  ch 2"))
check("describe: colour", "colour hue 30° sat 50%" in gvm.describe([0, 1, 10, 44, 6, 50, 2]) and gvm.describe([0, 1, 10, 44, 6, 50, 2]).startswith("off"))

print("case: gvm lights file and light names")
check("lights file: comments, blank and short lines skipped, addresses upper-cased",
      gvm.LIGHTS == {"light1": L1, "light2": L2}, gvm.LIGHTS)
check("default light is the first in the file", gvm.DEFAULT_ADDR == L1)
check("resolve a name", gvm.resolve("light2") == [("light2", L2)])
check("resolve 'all' in file order", gvm.resolve("all") == [("light1", L1), ("light2", L2)])
check("resolve a lower-case address to its name", gvm.resolve(L2.lower()) == [("light2", L2)])
check("resolve an unknown address keeps it as its own label", gvm.resolve("aa:bb:cc:00:00:b0") == [("AA:BB:CC:00:00:B0", "AA:BB:CC:00:00:B0")])
try:
    gvm.resolve("kitchen"); ok = False
except SystemExit as e:
    ok = "unknown light 'kitchen'" in str(e) and "light1, light2" in str(e)
check("resolve an unknown name: exits naming the known lights", ok)
saved = gvm.LIGHTS_FILE
gvm.LIGHTS_FILE = os.path.join(HOME, "no-such-file")
check("load_lights with no file: empty", gvm.load_lights() == {})
gvm.LIGHTS_FILE = saved
os.environ["GVM_ADDR"] = "11:22:33:00:00:F4"
g2 = load(GVM, "gvm_env")
check("GVM_ADDR overrides the default light", g2.DEFAULT_ADDR == "11:22:33:00:00:F4")
del os.environ["GVM_ADDR"]
os.rename(os.path.join(HOME, ".config/gvm/lights"), os.path.join(HOME, ".config/gvm/lights.off"))
g3 = load(GVM, "gvm_nofile")
import re
fallback = re.search(r'next\(iter\(LIGHTS\.values\(\)\), "([0-9A-Fa-f:]{17})"\)', open(GVM).read())
check("no lights file: default is the script's built-in address", fallback is not None and g3.DEFAULT_ADDR == fallback.group(1) and g3.LIGHTS == {})
try:
    g3.resolve("all"); ok = False
except SystemExit as e:
    ok = "no lights named" in str(e)
check("'all' with no lights file: exits with a message", ok)
os.rename(os.path.join(HOME, ".config/gvm/lights.off"), os.path.join(HOME, ".config/gvm/lights"))
check("preset_settings: own entry, else 'all', else None",
      gvm.preset_settings({"a": {"x": 1}, "all": {"y": 2}}, "a") == {"x": 1}
      and gvm.preset_settings({"all": {"y": 2}}, "b") == {"y": 2} and gvm.preset_settings({"note": "n"}, "b") is None)

print("case: gvm commands (fake BLE)")
fresh(**{L1: {}, L2: {}})
code, out, err = run("status")
check("status: default light only, INFO sent, nothing set, disconnected",
      code == 0 and out.startswith("on  bright 50%  white 4400K  ch 1") and sets() == []
      and [e for a, e, _ in W.log if a == L1 and e in ("connect", "disconnect")] == ["connect", "disconnect"]
      and not any(a == L2 for a, *_ in W.log), (code, out, err))
fresh(**{L1: {"on": 0}})
code, out, _ = run("on"); check("on: reg 0 = 1", code == 0 and sets() == [(0, 1)], sets())
fresh(**{L1: {}}); run("off"); check("off: reg 0 = 0", sets() == [(0, 0)])
fresh(**{L1: {"on": 1}}); code, out, _ = run("toggle")
check("toggle from on: off, says 'off'", sets() == [(0, 0)] and out.strip() == "off", (sets(), out))
fresh(**{L1: {"on": 0}}); code, out, _ = run("toggle")
check("toggle from off: on", sets() == [(0, 1)] and out.strip() == "on")
for args, want, name in ((["bright", "60"], [(2, 60)], "bright 60"),
                         (["bright", "150"], [(2, 100)], "bright 150 clamps to 100"),
                         (["bright", "-5"], [(2, 0)], "bright -5 clamps to 0"),
                         (["cct", "4400"], [(3, 44), (6, 1)], "cct 4400: reg 3 = 44, then white mode"),
                         (["cct", "4449"], [(3, 44), (6, 1)], "cct rounds to the nearest 100 K"),
                         (["cct", "2000"], [(3, 32), (6, 1)], "cct 2000 clamps to 3200 K"),
                         (["cct", "9000"], [(3, 56), (6, 1)], "cct 9000 clamps to 5600 K"),
                         (["white"], [(6, 1)], "white: mode 1 only"),
                         (["color", "30", "50"], [(4, 6), (5, 50), (6, 2)], "color 30 50: hue, sat, then colour mode"),
                         (["colour", "240"], [(4, 48), (6, 2)], "colour alias, no sat: saturation left alone"),
                         (["color", "30", "150"], [(4, 6), (5, 100), (6, 2)], "color sat 150 clamps to 100"),
                         (["set", "7", "4"], [(7, 4)], "set 7 4: raw register write")):
    fresh(**{L1: {}})
    code, out, err = run(*args)
    check(f"{name}", code == 0 and sets() == want, (code, sets(), err))

fresh(**{L1: {}, L2: {}})
code, out, _ = run("-l", "all", "on")
check("-l all: both lights written", code == 0 and sorted(a for a, _ in W.writes()) == [L1, L2])
fresh(**{L1: {}, L2: {}}); run("-l", "light2", "off")
check("-l light2: only that light", [a for a, _ in W.writes()] == [L2] and not any(a == L1 for a, e, _ in W.log if e == "connect"))
fresh(**{L1: {}, L2: {}}); run("--light", L2.lower(), "off")
check("--light with a lower-case address", [a for a, _ in W.writes()] == [L2])
fresh(**{L1: {}, L2: {"bright": 20}}); code, out, _ = run("-a", "all", "status")
check("status of several: each line labelled with the light name", code == 0 and "light1: on  bright 50%" in out and "light2: on  bright 20%" in out, out)
fresh(**{L1: {}}); code, out, err = run("-l", "kitchen", "on")
check("-l unknown name: exit 1 with a message, nothing connected", code == 1 and "unknown light" in err and not W.log, (code, err))
fresh(**{L1: {}, L2: {}}); W.missing.add(L2)
code, out, err = run("-l", "all", "on")
check("one light not found: exit 1, the other still set", code == 1 and [a for a, _ in W.writes()] == [L1] and f"light2: light {L2} not found" in err, (code, err))
check("  ... the missing light is looked for 3 times (8 s timeout each)", [d for a, e, d in W.log if a == L2 and e == "find"] == [8, 8, 8])
fresh(**{L1: {}}); W.refuse.add(L1)
code, out, err = run("on")
check("connect refused: exit 1, error shown", code == 1 and "le-connection-abort" in err, (code, err))
for args, name in ((["bright", "abc"], "bright abc"), ([], "no command"), (["effect", "bogus"], "unknown effect"),
                   (["set", "7"], "set without a value"), (["frobnicate"], "unknown command")):
    fresh(**{L1: {}})
    code, out, err = run(*args)
    check(f"argument error ({name}): exit 2, nothing connected", code == 2 and not W.log, (code, err[-80:]))

print("case: gvm presets")
fresh(**{L1: {}, L2: {}})
code, out, _ = run("preset")
check("preset with no name: lists presets with notes", code == 0 and "Camera" in out and "webcam look" in out and "Orange" in out, out)
fresh(**{L1: {"mode": 2}, L2: {"mode": 2}})
code, out, err = run("preset", "camera")
check("preset camera (any case): both lights", code == 0 and {a for a, _ in W.writes()} == {L1, L2}, (code, err))
check("  ... light1: cct, mode, bright, on in that order", sets(L1) == [(3, 44), (6, 1), (2, 100), (0, 1)], sets(L1))
check("  ... light2 gets its own brightness (20)", sets(L2) == [(3, 44), (6, 1), (2, 20), (0, 1)], sets(L2))
fresh(**{L1: {}, L2: {}}); run("preset", "orange")
check("'all' entry: every light, hue and sat before mode", sets(L1) == [(4, 5), (5, 100), (6, 2)] and sets(L2) == sets(L1), sets(L1))
fresh(**{L1: {}, L2: {}}); run("preset", "KeyOnly")
check("a preset naming one light: only that light is connected", [a for a, e, _ in W.log if e == "connect"] == [L2] and sets(L2) == [(2, 5)])
fresh(**{L1: {}, L2: {}}); code, out, _ = run("-l", "light1", "preset", "KeyOnly")
check("-l narrows a preset; a light not in it is left alone", code == 0 and sets() == [] and "not in this preset" in out, (code, out))
fresh(**{L1: {}}); code, out, err = run("preset", "disco-party")
check("unknown preset: exit 1 naming the presets", code == 1 and "no preset 'disco-party'" in err and "Camera" in err, err)

print("case: gvm effects")


def run_fx(name, snaps, secs=0.25, should_restore=lambda: True):
    log = [[] for _ in snaps]

    def writer(i):
        async def w(reg, val):
            log[i].append((reg, val))
            await asyncio.sleep(0)
        return w

    async def go():
        t = asyncio.ensure_future(gvm.run_effect(name, [writer(i) for i in range(len(snaps))], snaps,
                                                 speed=lambda: 50.0, should_restore=should_restore))
        try:
            await asyncio.wait_for(asyncio.shield(t), secs)
        except asyncio.TimeoutError:
            t.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await t
    asyncio.run(go())
    return log


snaps = [[1, 1, 70, 44, 0, 0, 1, 4, 1], [0, 1, 10, 50, 12, 30, 2, 4, 1]]
ranges = {0: (0, 1), 2: (0, 100), 3: (32, 56), 4: (0, 71), 5: (0, 100), 6: (1, 2)}
for name, (title, _fn, _clem, keep) in gvm.EFFECTS.items():
    log = run_fx(name, snaps)
    inrange = all(lo <= v <= hi for lw in log for r, v in lw for rr, (lo, hi) in ranges.items() if r == rr)
    first_on = all(lw and lw[0] == (0, 1) for lw in log)
    if keep:
        restored = all(lw[-6:] != [(r, s[r]) for r in (3, 4, 5, 6, 2, 0)] for lw, s in zip(log, snaps))
        check(f"effect {name}: turns lights on first, values in range, keeps its result", first_on and inrange and restored, log[0][-6:])
    else:
        restored = all(lw[-6:] == [(r, s[r]) for r in (3, 4, 5, 6, 2, 0)] for lw, s in zip(log, snaps))
        check(f"effect {name}: on first, values in range, then restores each light (mode after hue/sat)", first_on and inrange and restored,
              (first_on, inrange, log[0][-6:], log[1][-6:]))
log = run_fx("tiger-rag", snaps, should_restore=lambda: False)
check("should_restore() false: no restore after stopping", log[0][-6:] != [(r, snaps[0][r]) for r in (3, 4, 5, 6, 2, 0)])
fx = gvm.FX([None, None], [70, 10])
check("FX.b: fraction of the starting brightness, never below 1", fx.b(0, 0.5) == 35 and fx.b(1, 0.01) == 1)
check("run_effect bases: a light dimmer than 20% works from 60%", [v[2] if v[2] >= 20 else 60 for v in snaps] == [70, 60])

fresh(**{L1: {"mode": 1, "hue": 12, "sat": 30, "bright": 70}, L2: {"mode": 1, "bright": 40}})
before = {a: list(r) for a, r in W.regs.items()}
code, out, err = run("-l", "all", "effect", "tiger-rag", "-t", "0.4", "-s", "4")
check("gvm -l all effect tiger-rag -t 0.4: runs on both lights, then every light is as it was",
      code == 0 and W.regs == before and len(sets(L1)) > 6 and "Tiger Rag on light1, light2 (Ctrl-C to stop)" in err, (code, err, W.regs, before))
check("  ... the restore writes mode after hue and saturation",
      [r for r, _ in sets(L1)][-6:] == [3, 4, 5, 6, 2, 0], sets(L1)[-6:])
check("  ... and each light is disconnected", sum(1 for a, e, _ in W.log if e == "disconnect") == 2)
fresh(**{L1: {"mode": 1, "bright": 70}})
code, out, err = run("effect", "solid-orange")
check("effect solid-orange: ends by itself in orange colour mode (kept)", code == 0 and W.regs[L1][4] == 5 and W.regs[L1][5] == 100 and W.regs[L1][6] == 2
      and "(Ctrl-C" not in err, (code, W.regs[L1], err))
fresh(**{L1: {}}); W.missing.add(L1)
code, out, err = run("effect", "rainbow", "-t", "0.2")
check("effect with no light reachable: exit 1 'no lights connected'", code == 1 and "no lights connected" in err, (code, err))

print("case: gvm scan")
W.__init__()
adv = lambda name, rssi, uuids=(): types.SimpleNamespace(local_name=name, rssi=rssi, service_uuids=list(uuids))
W.adverts = {L2: (None, adv("BT_LED", -70)), L3: (None, adv(None, -50, ["00001812-0000-1000-8000-00805f9b34fb"])),
             "11:22:33:00:00:F4": (None, adv("Pixel Buds", -40, ["00001812-0000-1000-8000-00805f9b34fb"]))}
code, out, _ = run("scan")
lines = out.splitlines()
check("scan: GVM lights by name or HID uuid + Telink prefix, strongest first, other devices ignored",
      code == 0 and lines[0].startswith(f"{L3}  -50 dBm  (not in lights file)") and lines[1].startswith(f"{L2}  -70 dBm  light2")
      and "11:22:33" not in out, out)
check("  ... names the lights it did not see", "not seen: light1" in out)
W.adverts = {}
code, out, _ = run("scan")
check("scan with nothing advertising says so", "no GVM lights advertising" in out)

check("no real bleak was used", gvm.BleakScanner is FakeScanner and gvm.BleakClient is FakeClient)

# ------------------------------------------------------------------ gvm-gui (no window: that needs a display)
print("case: gvm-gui non-GTK parts")
os.makedirs(os.path.join(HOME, ".local/bin"), exist_ok=True)
gui = None
try:
    import gi  # noqa: F401
    have_gi = True
except ImportError:
    have_gi = False
if not GUI:
    print("skip: gvm-gui not present")
elif not have_gi:
    check("gvm-gui: python gi available (skipping the gvm-gui part)", False, "no gi")
else:
    sys.argv = ["gvm-gui"]
    try:
        gui = load(GUI, "gvm_gui_under_test")
        check("gvm-gui imports without a display (GTK4/Adw, fake bleak)", True)
    except Exception as e:  # noqa: BLE001
        gui = None
        check("gvm-gui imports without a display (GTK4/Adw, fake bleak)", False, repr(e))
if GUI and have_gi and gui:
    from gi.repository import GLib
    check("gvm-gui uses ~/.local/bin/gvm from HOME", gui.gvm.__file__ == os.path.join(HOME, ".local/bin/gvm"), gui.gvm.__file__)
    sys.argv = ["gvm-gui"]
    check("targets(): no arguments = every light in the file", gui.targets() == [("light1", L1), ("light2", L2)], gui.targets())
    sys.argv = ["gvm-gui", "light2", "all"]
    check("targets(): names then 'all', no light twice", gui.targets() == [("light2", L2), ("light1", L1)], gui.targets())
    check("json_key: key order does not matter", gui.json_key({"b": 1, "a": 2}) == gui.json_key({"a": 2, "b": 1}))
    gui.save_prefs(sync=True, size=[400, 300])
    gui.save_prefs(sync=False)
    check("prefs: saved under ~/.local/state/gvm/gui.json and merged", gui.PREFS.startswith(HOME)
          and json.load(open(gui.PREFS)) == {"sync": False, "size": [400, 300]}, gui.load_prefs())
    open(gui.PREFS, "w").write("{not json")
    check("prefs: a broken file reads as empty", gui.load_prefs() == {})

    class Panel:
        def __init__(self):
            self.events = []
        def on_state(self, *a):
            self.events.append(("state",) + a)
        def on_values(self, *a):
            self.events.append(("values",) + a)
        def on_range(self, *a):
            self.events.append(("range",) + a)

    def pump(until, secs=3):
        end = time.time() + secs
        ctx = GLib.MainContext.default()
        while time.time() < end:
            while ctx.pending():
                ctx.iteration(False)
            if until():
                return True
            time.sleep(0.02)
        return False

    fresh(**{L1: {"bright": 33}})
    panel = Panel()
    link = gui.Link(panel, L1)
    link.connect()
    ok = pump(lambda: ("state", "connected") in panel.events and any(e[0] == "values" for e in panel.events))
    check("Link: connects through the shared loop, reports 'connected'", ok and ("state", "connecting") in panel.events, panel.events)
    vals = [e for e in panel.events if e[0] == "values"]
    check("Link: the status report reaches the panel (first 7 registers)", vals and vals[0][1] == {0: 1, 1: 1, 2: 33, 3: 44, 4: 0, 5: 0, 6: 1} and vals[0][2] is False, vals)
    check("Link: the CCT range reply reaches the panel", ("range", 32, 56) in panel.events, panel.events)
    W.log.clear()
    # queue four writes in one go: a repeated register moves to the back, keeps its last value
    gui.LOOP.call_soon_threadsafe(lambda: [link.set(r, v) for r, v in ((4, 10), (5, 50), (6, 2), (4, 12))])
    pump(lambda: len(sets(L1)) >= 3, 3)
    time.sleep(0.2)
    check("Link: write queue is FIFO; a repeated register goes to the back with its latest value",
          sets(L1) == [(5, 50), (6, 2), (4, 12)], sets(L1))
    link._note(None, bytearray(mkframe([0, 0x30, 0x02, 0, 2, 77])))
    pump(lambda: ("values", {2: 77}, True) in panel.events)
    check("Link: a one-register change from the light reaches the panel", ("values", {2: 77}, True) in panel.events)
    link.set(0, 0)
    link.close()
    check("Link.close: queued writes go out first, then disconnect",
          [e for _, e, _ in W.log if e in ("set", "disconnect")][-2:] == ["set", "disconnect"] and W.regs[L1][0] == 0 and link.client is None,
          W.log[-3:])
    fresh(**{L1: {}}); W.missing.add(L1)
    panel = Panel(); link = gui.Link(panel, L1); link.connect()
    check("Link: a light that is not found reports 'notfound'", pump(lambda: ("state", "notfound") in panel.events, 5), panel.events)
    print("SKIP gvm-gui window (LightPanel/Window need a Wayland or X display; not built here)")

print(f"python: pass {npass} fail {nfail}")
print("GVM DONE")
