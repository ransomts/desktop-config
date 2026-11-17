import json, os, subprocess, sys, time
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "kbtest.py")).read().split('if __name__ == "__main__":')[0])
def act():
    a = json.loads(h("activewindow", "-j")); return a.get("address", "?")[-4:], tuple(a.get("at", [0, 0]))
def order():
    return [ (c["address"][-4:], tuple(c["at"])) for c in sorted(json.loads(h("clients", "-j")), key=lambda c: (c["at"][0], c["at"][1])) ]
def notes():
    h("eval", "local f=io.open('%s/ev.out','w') local t={} local all=hl.notification.get() for k=math.max(1,#all-1),#all do local n=all[k] do t[#t+1]=tostring(n:get_text()) end f:write(table.concat(t,' | ')) f:close()" % SP)
    return open(os.path.join(SP, "ev.out")).read()
SUPER, SHIFT = 125, 42
def press(*codes):  # modifiers then key
    seq = []
    for c in codes[:-1]: seq += ["d", c]
    seq += ["t", codes[-1]]
    for c in reversed(codes[:-1]): seq += ["u", c]
    kb(*seq)
for layout in sys.argv[1:]:
    lua(layout); print("--", layout)
    ptr(60, 60); start = act(); print("focus", start, "order", order())
    press(SUPER, 37); a1 = act(); press(SUPER, 37); a2 = act(); press(SUPER, 35); a3 = act()
    print(f"  Super+K -> {a1}, Super+K -> {a2}, Super+H -> {a3}  ({'ok' if a1 != start and a2 != a1 and a3 == a1 else 'CHECK'})")
    before = order(); press(SUPER, 21); after = order(); press(SUPER, SHIFT, 21); back = order()
    print(f"  Super+Y moved: {before != after}; Super+Shift+Y put it back: {back == before}")
    press(SUPER, SHIFT, 50); print("  Super+Shift+M focus ->", act())
    j0 = order(); press(SUPER, 36); print("  Super+J changed layout:", order() != j0, "| notes:", notes()[-160:])
