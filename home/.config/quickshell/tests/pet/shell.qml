// Pointer tests for the bar pet. NOT part of the shell: ~/.local/bin/pet-test copies the
// real Pet*.qml files next to this one and the stub Sys / Notif / WallState, then runs it
// in Quickshell's offscreen mode, so there is no window, the real cursor never moves, and
// nothing is written to ~/.local/state.
//
// A mock bar (34 px, a hover handler, three real pills, the pet and its friend wired as in
// Bar.qml) and a mock desktop (the two of them at scale 2, as in Wallpaper.qml) are driven
// with synthetic mouse events (QtTest's TestEvent). Each case logs PASS or FAIL; the last
// line is "PETTEST RESULT pass N fail M". A picture of the window is saved to $PET_TEST_OUT.
//
// Adding a case: append { name, run } to `cases`. `run` does its events and checks and
// returns how many milliseconds to wait before the next case; split a case in two when a
// check has to wait for something (the second half is just the next entry).
import QtQuick
import QtQuick.Layouts
import QtTest
import Quickshell

ShellRoot {
    id: root
    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 1200; implicitHeight: 560
        color: Theme.dark ? "#16161a" : "#44266c"      // light mode: the wallpaper's purple top strip is what is behind the bar

        property bool onDesk: false             // which surface the pets are on
        property int menus: 0                   // times a pet asked for its menu
        property int steps: 0                   // Pill scroll steps (signed)
        property int passed: 0
        property int failed: 0
        function check(what, ok, detail) {
            if (ok) passed++; else failed++
            console.log("PETTEST " + (ok ? "PASS " : "FAIL ") + what + (ok || detail === undefined ? "" : "   [" + detail + "]"))
        }
        function state(s) { return "x=" + Math.round(s.x) + (s.walking ? " to=" + Math.round(s.walkTarget) : "") + " mood=" + s.mood + " lured=" + s.lured + " ptr=" + Math.round(s.ptr) + " busy=" + s.busy + " walking=" + s.walking + " carried=" + s.carried + " frame=" + s.frame + " bubble=" + s.bubble }
        function findRow(item, label) {         // a MenuRow by its label, anywhere under item
            if (!item) return null
            if (item.label === label && item.visible) return item
            const kids = item.children || []
            for (let i = 0; i < kids.length; i++) { const r = findRow(kids[i], label); if (r) return r }
            return null
        }
        function clickRow(label) {
            const r = findRow(menu, label)
            if (!r) return false
            ev.mouseClick(r, r.width / 2, r.height / 2, Qt.LeftButton, Qt.NoModifier, 0)
            return true
        }

        TestEvent { id: ev }

        // everything drawn sits in one item, so one picture of it can be saved at the end
        Item {
        id: stage
        anchors.fill: parent
        Rectangle { anchors.fill: parent; z: -10; color: win.color }      // so the saved picture has the background too

        // ---------------- the mock bar ----------------
        Item {
            id: bar
            x: 0; y: 8; width: 1200; height: 34
            HoverHandler { id: barHover }
            Row {
                id: leftRow
                height: parent.height
                Pill { id: leftPill; text: "1  2  3"; onScrolled: d => win.steps += d }
            }
            Pill { id: clockPill; anchors.horizontalCenter: parent.horizontalCenter; text: "Wed Nov 11  14:00" }
            Row {
                id: rightRow
                anchors.right: parent.right
                height: parent.height
                Pill { id: bellPill; text: "bell" }
            }
            PetSprite {
                id: pet
                screenName: "test"
                shown: !win.onDesk
                pointerX: barHover.hovered ? barHover.point.position.x : -1
                onMenuRequested: win.menus++
                gaps: [{ from: leftRow.width + 10, to: clockPill.x - 10 }, { from: clockPill.x + clockPill.width + 10, to: rightRow.x - 10 }]
                bellX: rightRow.x - 10 - 32
                clockX: clockPill.x - 10 - 32
                musicX: clockPill.x + clockPill.width + 12
                spans: ({ bell: { from: rightRow.x + bellPill.x, to: rightRow.x + bellPill.x + bellPill.width }, clock: { from: clockPill.x, to: clockPill.x + clockPill.width } })
            }
            PetSprite {
                id: friend
                who: 1
                screenName: "test"
                shown: !win.onDesk
                pointerX: barHover.hovered ? barHover.point.position.x : -1
                onMenuRequested: win.menus++
                gaps: pet.gaps
                bellX: pet.bellX; clockX: pet.clockX; musicX: pet.musicX
            }
        }

        // ---------------- the mock desktop ----------------
        Rectangle {
            id: desk
            x: 0; y: 60; width: 880; height: 200
            color: Theme.dark ? "#1e1e22" : "#583392"
            HoverHandler { id: deskHover }
            PetSprite {
                id: deskPet
                k: 2; baseZ: 5; floorGap: 10; spotTag: "#desk"; screenName: "test"
                shown: win.onDesk
                gaps: [{ from: 24, to: desk.width - 24 }]
                bellX: desk.width - 24 - size; musicX: desk.width / 2; clockX: desk.width / 2 - size
                pointerX: deskHover.hovered ? deskHover.point.position.x : -1
                onMenuRequested: win.menus++
            }
            PetSprite {
                id: deskFriend
                who: 1
                k: 2; baseZ: 5; floorGap: 10; spotTag: "#desk"; screenName: "test"
                shown: win.onDesk
                gaps: deskPet.gaps
                bellX: deskPet.bellX; musicX: deskPet.musicX; clockX: deskPet.clockX
                pointerX: deskHover.hovered ? deskHover.point.position.x : -1
                onMenuRequested: win.menus++
            }
            // as in Wallpaper.qml: over the pets, finds the pet among its siblings
            PetGame { id: deskGame; anchors.fill: parent; z: 6; here: win.onDesk; pointerX: deskHover.hovered ? deskHover.point.position.x : -1 }
        }

        // ---------------- its menu, laid out as in the popup ----------------
        Rectangle {
            x: 894; y: 60; width: 290 + 12; height: 490
            color: Theme.solidBg
            PetMenu { id: menu; x: 6; y: 6; width: 290; screenKey: "test" }
        }

        }       // stage

        // ---------------- the cases ----------------
        property real mark: 0
        // put a pet at a known open spot, doing nothing, and take the pointer off the bar
        function park(s, at) { s.reset(); s.x = s.nearestSpot(at); s.rest() }
        function away() { ev.mouseMove(win.contentItem, 890, 400, 0, Qt.NoButton, Qt.NoModifier) }
        // play cases: run this case again until cond() holds (or maxMs has gone by); false while still waiting
        property double pollAt: 0
        property var playKeep: [0, 0]
        function until(cond, maxMs) {
            if (pollAt === 0) pollAt = Date.now()
            if (cond() || Date.now() - pollAt > maxMs) { pollAt = 0; return true }
            at--
            return false
        }
        function playDone(maxMs) { return until(() => PetPlay.scene === "" && !pet.busy && !friend.busy && !deskPet.busy && !deskFriend.busy, maxMs) }
        function checkClear(what) {
            check("play: " + what + ": both free", !pet.busy && !friend.busy, state(pet) + "  /  " + state(friend))
            check("play: " + what + ": nothing left drawn", !pet.ballOut && !friend.ballOut && !pet.carrying && !friend.carrying && pet.lift === 0 && friend.lift === 0)
        }
        // ---- helpers: animals ----
        function sheetOf(item) {                // the sprite sheet Image inside a PetSprite
            const kids = item.children || []
            for (let i = 0; i < kids.length; i++) {
                const c = kids[i]
                if (c.sourceSize !== undefined && String(c.source).indexOf("/pet-") >= 0) return c
                const r = sheetOf(c)
                if (r) return r
            }
            return null
        }
        property int batted: 0                  // frames of a pounce/bat while the ball was out
        property bool grabbed: false            // the ball was carried
        Connections {
            target: pet
            function onFrameChanged() { if (pet.ballOut && pet.frame === 9) win.batted++ }
            function onCarryingChanged() { if (pet.carrying) win.grabbed = true }
        }
        // ---- end helpers: animals ----
        // ---- helpers: secrets ----
        function anticsOf(s) { const kids = s.children; for (let i = 0; i < kids.length; i++) if (kids[i].dozeMs !== undefined) return kids[i]; return null }
        property bool muteStars: false
        Timer { interval: 100; repeat: true; running: win.muteStars; onTriggered: if (PetArc.pending.length) PetArc.pending = [] }
        property int rings: 0
        property int pushes: 0
        property int maxPrints: 0
        Connections { target: pet; function onRang() { win.rings++ } function onPushed() { win.pushes++ } }
        // ---- end helpers: secrets ----
        property var cases: [
            { name: "start", run: function() {
                away()          // the offscreen cursor starts at the window's corner, which is on the bar
                PetSecrets.dayDemo = "2026-07-01"       // an ordinary day, whatever today is (no costume, no joke)
                return 3000
            } },
            { name: "settles in an open stretch of the bar", run: function() {
                check("pet is shown on the bar", pet.active && pet.visible, state(pet))
                check("it stands clear of the pills", pet.inGaps(pet.x) && !pet.walking, state(pet) + " gaps " + JSON.stringify(pet.gaps))
                check("no friend until it is given one", !friend.active)
                return 100
            } },
            { name: "a click pets it", run: function() {
                away(); park(pet, 300)
                ev.mouseClick(pet, 16, 16, Qt.LeftButton, Qt.NoModifier, 0)
                check("click: it is busy being petted", pet.busy, state(pet))
                check("click: a heart or a purr beside it", pet.bubble === "♥" || pet.bubble === "purr", state(pet))
                return 1800
            } },
            { name: "the pat ends by itself", run: function() {
                check("pat over: free again", !pet.busy, state(pet))
                return 100
            } },
            { name: "right and middle click ask for the menu", run: function() {
                away(); park(pet, 300)
                const before = menus
                ev.mouseClick(pet, 16, 16, Qt.RightButton, Qt.NoModifier, 0)
                check("right-click asks for the menu", menus === before + 1, state(pet))
                check("right-click is not a pat", !pet.busy, state(pet))
                ev.mouseClick(pet, 16, 16, Qt.MiddleButton, Qt.NoModifier, 0)
                check("middle-click asks for the menu", menus === before + 2, state(pet))
                check("middle-click opens it on the briefing", Pet.menuPage === "say", Pet.menuPage)
                Pet.menuPage = ""
                return 100
            } },
            { name: "scrolling", run: function() {
                away(); park(pet, 300)
                ev.mouseWheel(pet, 16, 16, Qt.NoButton, Qt.NoModifier, 0, 0, 0)
                check("a scroll with no vertical part starts nothing", !pet.busy && !pet.ballOut, state(pet))
                ev.mouseWheel(pet, 16, 16, Qt.NoButton, Qt.NoModifier, 0, 120, 0)
                check("a wheel notch starts the ball game", pet.busy && pet.ballOut, state(pet))
                return 400
            } },
            { name: "picked up in the middle of the ball game", run: function() {
                check("ball game: it is running after the ball", pet.walking && pet.ballOut, state(pet))
                check("ball game: a running pet takes no clicks", !pet.carried)
                pet.stopMoving(); pet.walking = false        // it pauses, as between two throws: now it can be taken
                const at = pet.x + 16
                ev.mousePress(pet, 16, 16, Qt.LeftButton, Qt.NoModifier, 0)
                check("press alone does not pick it up", !pet.carried)
                ev.mouseMove(bar, at + 30, 17, 0, Qt.LeftButton, Qt.NoModifier)
                check("drag: it is carried", pet.carried, state(pet))
                check("drag: the ball game is dropped", !pet.ballOut && !pet.walking, state(pet))
                mark = pet.x
                return 900
            } },
            { name: "held still, it stays put", run: function() {
                check("held: no jitter while carried", Math.abs(pet.x - mark) < 1 && pet.carried && pet.busy, state(pet) + " was x=" + Math.round(mark))
                ev.mouseMove(bar, mark + 16 - 60, 17, 0, Qt.LeftButton, Qt.NoModifier)
                check("drag: it follows the pointer", Math.abs(pet.x - pet.nearestSpot(mark - 60)) < 6, state(pet))
                ev.mouseRelease(bar, mark + 16 - 60, 17, Qt.LeftButton, Qt.NoModifier, 0)
                check("release: put down", !pet.carried, state(pet))
                return 800
            } },
            { name: "after being put down", run: function() {
                check("put down: free again", !pet.busy && !pet.carried, state(pet))
                check("put down: still clear of the pills", pet.inGaps(pet.x), state(pet))
                return 100
            } },
            { name: "a drag is not a click", run: function() {
                away(); park(pet, 300)
                ev.mousePress(pet, 16, 16, Qt.LeftButton, Qt.NoModifier, 0)
                ev.mouseMove(bar, 300 + 16 + 40, 17, 0, Qt.LeftButton, Qt.NoModifier)
                ev.mouseRelease(bar, 300 + 16 + 40, 17, Qt.LeftButton, Qt.NoModifier, 0)
                check("drag then release: no heart", pet.bubble !== "♥" && pet.bubble !== "purr", state(pet))
                return 900
            } },
            { name: "the pointer close by: it sits and watches, it does not shuffle", run: function() {
                away(); park(pet, 300)
                mark = pet.x
                ev.mouseMove(bar, mark + 16 + 12, 17, 0, Qt.NoButton, Qt.NoModifier)
                return 500
            } },
            { name: "slow pointer near a sitting pet", run: function() {
                check("hover: the bar sees the pointer", barHover.hovered)
                check("near pointer: it is lured", pet.lured, state(pet))
                ev.mouseMove(bar, mark + 16 + 20, 17, 0, Qt.NoButton, Qt.NoModifier)
                return 400
            } },
            { name: "still sitting", run: function() {
                check("near pointer: it has not moved", Math.abs(pet.x - mark) < 1 && !pet.walking, state(pet) + " was x=" + Math.round(mark))
                ev.mouseMove(bar, mark + 150, 17, 0, Qt.NoButton, Qt.NoModifier)
                return 450
            } },
            { name: "the pointer far off: it gets up and goes", run: function() {
                check("far pointer: it walks, in the walking pose", pet.walking && (pet.frame === 2 || pet.frame === 3), state(pet))
                return 2500
            } },
            { name: "tooltip", run: function() {
                away(); park(pet, 300)
                ev.mouseMove(pet, 16, 16, 0, Qt.NoButton, Qt.NoModifier)
                return 1300
            } },
            { name: "tooltip shows, and goes when it walks off", run: function() {
                check("hover: tooltip is the pet's", Sys.tipTarget === pet, String(Sys.tipTarget) + " " + state(pet))
                check("hover: it names the pet", Sys.tipText.indexOf(Pet.name) >= 0, Sys.tipText)
                Pet.pointDemo = 450                      // send it away from under the pointer
                return 600
            } },
            { name: "tooltip gone", run: function() {
                check("walking away clears the tooltip", Sys.tipTarget !== pet, state(pet))
                Pet.pointDemo = -1
                away()
                return 300
            } },
            { name: "a pill's scroll: one step per wheel notch", run: function() {
                steps = 0
                ev.mouseWheel(leftPill, 10, 10, Qt.NoButton, Qt.NoModifier, 0, 0, 0)
                ev.mouseWheel(leftPill, 10, 10, Qt.NoButton, Qt.NoModifier, 40, 0, 0)
                check("pill: no vertical part, no step", steps === 0, steps)
                for (let i = 0; i < 7; i++) ev.mouseWheel(leftPill, 10, 10, Qt.NoButton, Qt.NoModifier, 0, 15, 0)
                check("pill: seven small touchpad events are not yet a step", steps === 0, steps)
                ev.mouseWheel(leftPill, 10, 10, Qt.NoButton, Qt.NoModifier, 0, 15, 0)
                check("pill: the eighth makes one step up", steps === 1, steps)
                ev.mouseWheel(leftPill, 10, 10, Qt.NoButton, Qt.NoModifier, 0, -120, 0)
                check("pill: a notch down is one step down", steps === 0, steps)
                away()
                return 100
            } },
            // the menu lays itself out again after each page change: one click per step
            { name: "menu: Tricks", run: function() {
                check("menu: starts on the main page", menu.page === "", menu.page)
                check("menu: Tricks row found and clicked", clickRow("Tricks"))
                return 150
            } },
            { name: "menu: Back", run: function() {
                check("menu: now on the tricks page", menu.page === "tricks", menu.page)
                clickRow("Back")
                return 150
            } },
            { name: "menu: Looks", run: function() {
                check("menu: Back returns to the main page", menu.page === "", menu.page)
                clickRow("Looks")
                return 150
            } },
            { name: "menu: Animal", run: function() {
                check("menu: Looks page", menu.page === "looks", menu.page)
                mark = Pet.coatsOf ? Object.keys(Pet.coatsOf).indexOf(Pet.animal) : -1
                clickRow("Animal")
                return 150
            } },
            { name: "menu: Settings", run: function() {
                check("menu: Animal steps to the next animal", Object.keys(Pet.coatsOf).indexOf(Pet.animal) !== mark, Pet.animal)
                Pet.setAnimal("cat")
                clickRow("Back")
                return 150
            } },
            { name: "menu: Settings page", run: function() { clickRow("Settings"); return 150 } },
            { name: "menu: Habits", run: function() {
                check("menu: Settings page", menu.page === "settings", menu.page)
                clickRow("Habits")
                return 150
            } },
            { name: "menu: Back from Habits", run: function() {
                check("menu: Habits page", menu.page === "habits", menu.page)
                clickRow("Back")
                return 150
            } },
            { name: "menu: back on Settings", run: function() {
                check("menu: Back from Habits lands on Settings", menu.page === "settings", menu.page)
                clickRow("Back")
                return 150
            } },
            // ---- cases: remind ----
            { name: "remind: reading WHEN", run: function() {
                const now = new Date(2026, 10, 11, 14, 0, 0).getTime()
                const at = (h, m, dayOff) => { const d = new Date(2026, 10, 11 + (dayOff || 0), h, m, 0); return d.getTime() }
                const want = [
                    ["20m", now + 20 * 60000], ["20 min", now + 20 * 60000], ["in 20 minutes", now + 20 * 60000], ["20", now + 20 * 60000],
                    ["1h30", now + 90 * 60000], ["1h 30m", now + 90 * 60000], ["1 hour 30 min", now + 90 * 60000], ["1.5h", now + 90 * 60000],
                    ["90s", now + 90000], ["14:45", at(14, 45)], ["at 14:45", at(14, 45)], ["9:05", at(9, 5, 1)], ["2:30pm", at(14, 30)],
                    ["2pm", at(14, 0, 1)], ["12am", at(0, 0, 1)], ["noon", at(12, 0, 1)], ["11:59 PM", at(23, 59)]
                ]
                for (const w of want) {
                    const p = PetRemind.parseWhen(w[0], now)
                    check("parse \"" + w[0] + "\"", !p.error && p.at === w[1], JSON.stringify(p) + " wanted " + new Date(w[1]))
                }
                check("parse: a past time says tomorrow", PetRemind.parseWhen("9:05", now).label === "at 09:05 tomorrow", PetRemind.parseWhen("9:05", now).label)
                check("parse: today's time says only the time", PetRemind.parseWhen("14:45", now).label === "at 14:45", PetRemind.parseWhen("14:45", now).label)
                for (const bad of ["banana", "", "25:00", "13pm", "14:75", "2 days", "0m", "30m1h", "20x", "1h30m10s5m", "48h"]) {
                    const p = PetRemind.parseWhen(bad, now)
                    check("parse rejects \"" + bad + "\"", !!p.error && p.error.length > 5, JSON.stringify(p))
                }
                return 100
            } },
            { name: "remind: a reminder in 1 s", run: function() {
                away(); park(pet, 300)
                Sys.ran = []
                mark = Pet.mood === "remind" ? 1 : 0
                const said = PetRemind.add("1s", "it's \"urgent\" $(touch /tmp/pwned) `id`; rm -rf ~")
                check("add: says what it understood", said.indexOf("in 1 s") === 0 && said.indexOf("urgent") > 0, said)
                check("add: pending, not yet due", PetRemind.count === 1 && !PetRemind.ringing && Pet.mood !== "remind", PetRemind.list())
                check("add: a nonsense time is refused", PetRemind.add("whenever", "x").indexOf("error: ") === 0 && PetRemind.count === 1)
                return 1500
            } },
            { name: "remind: it comes due", run: function() {
                check("due: mood is remind", Pet.mood === "remind", Pet.mood + " " + PetRemind.list())
                check("due: it heads for the clock", (pet.walking && Math.abs(pet.walkTarget - pet.nearestSpot(pet.clockX)) < 2) || Math.abs(pet.x - pet.nearestSpot(pet.clockX)) < 2, state(pet) + " clock=" + pet.clockX)
                check("due: the note is in its tooltip text", Pet.doing.indexOf("urgent") >= 0, Pet.doing)
                const cmd = Sys.ran.find(c => c.indexOf("notify-send") === 0) || ""
                check("due: a notify-send went out", cmd !== "", JSON.stringify(Sys.ran))
                // read the command as sh would: nothing special may stand outside quotes, and the last word is the note
                let words = [], w = "", inWord = false, bare = "", i = 0
                while (i < cmd.length) {
                    const c = cmd[i]
                    if (c === "'") { const j = cmd.indexOf("'", i + 1); if (j < 0) { bare += "UNTERMINATED"; break } w += cmd.slice(i + 1, j); inWord = true; i = j + 1; continue }
                    if (c === "\\") { w += cmd[i + 1]; inWord = true; i += 2; continue }
                    if (c === " ") { if (inWord) words.push(w); w = ""; inWord = false; i++; continue }
                    if ("$`;|&()<>\"".indexOf(c) >= 0) bare += c
                    w += c; inWord = true; i++
                }
                if (inWord) words.push(w)
                check("due: nothing in the note reaches the shell unquoted", bare === "", "bare=" + bare + " cmd=" + cmd)
                check("due: the note arrives whole", words[words.length - 1] === "it's \"urgent\" $(touch /tmp/pwned) `id`; rm -rf ~", JSON.stringify(words))
                check("due: it fires once", Sys.ran.filter(c => c.indexOf("notify-send") === 0).length === 1, JSON.stringify(Sys.ran))
                return 3000
            } },
            { name: "remind: it waits at the clock until clicked", run: function() {
                check("waits: sitting by the clock with a mark", !pet.walking && Math.abs(pet.x - pet.nearestSpot(pet.clockX)) < 2 && pet.bubble.indexOf("!") >= 0, state(pet))
                check("waits: still reminding", Pet.mood === "remind")
                ev.mouseClick(pet, 16, 16, Qt.LeftButton, Qt.NoModifier, 0)
                check("click: acknowledged", !PetRemind.ringing && PetRemind.count === 0 && Pet.mood !== "remind", Pet.mood + " " + PetRemind.list())
                check("click: a line in the diary", PetArc.entries.length > 0 && PetArc.entries[0].t.indexOf("Reminded you: it's") === 0, JSON.stringify(PetArc.entries[0]))
                Sys.ran = []
                PetRemind.add("1s", "never")
                check("cancel: by number", PetRemind.cancelNth("1").indexOf("cancelled") === 0 && PetRemind.count === 0)
                return 1800
            } },
            { name: "remind: a cancelled one never fires; the menu page", run: function() {
                check("cancelled: no notification, no remind mood", Sys.ran.length === 0 && Pet.mood !== "remind", JSON.stringify(Sys.ran) + " " + Pet.mood)
                PetRemind.add("30m", "tea")
                check("menu: Reminders row", clickRow("Reminders"))
                return 150
            } },
            { name: "remind: on the page", run: function() {
                check("menu: Reminders page", menu.page === "remind", menu.page)
                check("menu: quick rows", findRow(menu, "In 10 minutes") !== null && findRow(menu, "At a time...") !== null)
                check("menu: the pending one is listed", clickRow("tea"))
                return 150
            } },
            { name: "remind: cancelled from the page", run: function() {
                check("menu: a click cancels it", PetRemind.count === 0, PetRemind.list())
                Sys.ran = []
                check("menu: a quick row runs pet-remind", clickRow("In 30 minutes") && Sys.ran.length === 1 && /pet-remind 30m$/.test(Sys.ran[0]), JSON.stringify(Sys.ran))
                menu.page = ""
                Pet.napping = true
                PetRemind.add("1s", "wake up")
                return 1500
            } },
            { name: "remind: it gets up from a nap", run: function() {
                check("nap: a due reminder wakes it", Pet.mood === "remind", Pet.mood)
                check("ipc: reminddone", PetRemind.done().indexOf("done") === 0)
                check("nap: back to sleep after, nap untouched", Pet.mood === "asleep" && Pet.napping, Pet.mood)
                Pet.napping = false
                // two that came due while the shell was down: one at a time
                const t = Date.now()
                PetRemind.save([{ id: "a", at: t - 60000, note: "first" }, { id: "b", at: t - 30000, note: "second" }])
                PetRemind.gapUntil = 0                   // as at start, once the start-up pause is over
                PetRemind.arm()
                return 400
            } },
            { name: "remind: overdue ones, one at a time", run: function() {
                check("overdue: the older one first", PetRemind.ringing && PetRemind.current.note === "first", PetRemind.list())
                check("overdue: the other is still waiting", PetRemind.count === 2)
                PetRemind.done()
                check("overdue: not in the same breath", !PetRemind.ringing, PetRemind.list())
                return 3400
            } },
            { name: "remind: then the next", run: function() {
                check("overdue: the second after a pause", PetRemind.ringing && PetRemind.current.note === "second", PetRemind.list())
                PetRemind.cancelNth("all")
                check("cancel all", PetRemind.count === 0 && !PetRemind.ringing && Pet.mood !== "remind", Pet.mood)
                return 1500
            } },
            // ---- end cases: remind ----
            // ---- cases: game ----
            { name: "game: not from the bar", run: function() {
                const r = PetScore.start()
                check("game: no game while the pet is on the bar", !PetScore.running && !deskGame.running && !PetScore.here, r)
                check("game: it says why", r.indexOf("desktop") >= 0, r)
                check("game: the menu does not offer it on the bar", findRow(menu, "Play a game") === null)
                deskGame.autoSpawn = false; deskGame.length = 2500; deskGame.fallMs = 800
                onDesk = true
                return 1200
            } },
            { name: "game: starts on the desktop", run: function() {
                away(); park(deskPet, 300)
                check("game: the menu offers it on the desktop", findRow(menu, "Play a game") !== null)
                const r = PetScore.start()
                check("game: started", PetScore.running && deskGame.running, r)
                check("game: the pet is held by it", deskPet.busy && deskPet.inGame, state(deskPet))
                check("game: the menu row now stops it", findRow(menu, "Stop the game") !== null)
                mark = deskPet.x
                ev.mouseMove(desk, mark + 32 + 20, 150, 0, Qt.NoButton, Qt.NoModifier)      // inside the idle chase's dead zone
                return 400
            } },
            { name: "game: a treat above the pet", run: function() {
                check("game: it goes for the pointer with no dead zone", Math.abs(deskPet.x - (mark + 20)) < 3, state(deskPet) + " was x=" + Math.round(mark))
                away()
                check("game: a treat can be placed", deskGame.drop(deskPet.x + 32, "own"))
                return 1000
            } },
            { name: "game: caught", run: function() {
                check("game: its own food caught for 3", deskGame.score === 3 && deskGame.live() === 0, "score " + deskGame.score + " live " + deskGame.live())
                return 1900
            } },
            { name: "game: ends by itself", run: function() {
                check("game: over after its length", !deskGame.running && !PetScore.running, "running " + deskGame.running)
                check("game: the pet is let go", !deskPet.inGame, state(deskPet))
                check("game: a new best is kept", PetScore.best === 3 && deskGame.resultText.indexOf("New best") === 0, PetScore.best + " / " + deskGame.resultText)
                check("game: a new best is celebrated", deskPet.bubble === "★", state(deskPet))
                return 1600
            } },
            { name: "game: the frog", run: function() {
                check("game: free again after the celebration", !deskPet.busy, state(deskPet))
                Pet.setAnimal("frog")
                deskGame.length = 5000
                away()
                check("game: the frog plays too", PetScore.start().indexOf("treat catch") === 0, Pet.mood)
                mark = deskPet.x
                deskGame.drop(deskPet.x + 32 + 120, "bug")     // well to one side
                return 1000
            } },
            { name: "game: the frog's tongue, then leaving the desktop", run: function() {
                check("game: the frog snaps a treat from the side", deskGame.score === 3 && Math.abs(deskPet.x - mark) < 2, "score " + deskGame.score + " " + state(deskPet))
                deskGame.drop(deskPet.x + 32, "fish")
                onDesk = false                  // a window opens
                return 400
            } },
            { name: "game: left the desktop", run: function() {
                check("game: leaving ends it", !deskGame.running && !PetScore.running && !PetScore.here)
                check("game: and frees the pet", !deskPet.busy && !deskPet.inGame && !deskPet.walking, state(deskPet))
                check("game: no treat left falling", deskGame.live() === 0)
                check("game: a lower score keeps the best", PetScore.best === 3, PetScore.best)
                Pet.setAnimal("cat")
                Pet.napping = true
                onDesk = true
                return 1200
            } },
            { name: "game: not while asleep; a second call stops it", run: function() {
                const r = PetScore.start()
                check("game: not while asleep", !PetScore.running && r.indexOf("asleep") >= 0, r)
                Pet.napping = false
                check("game: starts once awake", PetScore.toggle().indexOf("treat catch") === 0 && deskGame.running)
                const r2 = PetScore.toggle()
                check("game: a second call stops it", !deskGame.running && r2.indexOf("stopped") === 0, r2)
                check("game: stopped with no points, it is free at once", !deskPet.busy && !deskPet.inGame, state(deskPet))
                Pet.setAnimal("bird")           // shy of the pointer at a low bond, but not in a game
                park(deskPet, 100)
                PetScore.start()
                ev.mouseMove(desk, 700, 150, 0, Qt.NoButton, Qt.NoModifier)
                return 250
            } },
            { name: "game: the bird flies to the pointer", run: function() {
                check("game: the bird flies the long way", deskPet.flying && deskPet.x > 110 && !deskPet.faceLeft, state(deskPet))
                PetScore.stop()
                check("game: stopped in flight, it is down and free", !deskPet.flying && !deskPet.walking && !deskPet.busy, state(deskPet))
                away()
                Pet.setAnimal("cat")
                onDesk = false
                return 900
            } },
            // ---- end cases: game ----
            // ---- cases: sign ----
            { name: "sign: nothing by default", run: function() {
                const t = (pet.children || []).find(c => c.font && c.font.pixelSize === 9 && c.text !== undefined)
                check("sign: the pet has a sign item", !!t)
                check("sign: the default is none", PetSign.choice === "none", PetSign.choice)
                check("sign: by default it shows nothing", PetSign.text === "" && !t.visible, PetSign.text)
                PetSign.batteryDemo = 87
                check("sign: ipc-style set returns the choice", PetSign.setSign("battery") === "battery")
                check("sign: an unknown name changes nothing", PetSign.setSign("weather") === "battery")
                return 100
            } },
            { name: "sign: battery", run: function() {
                const t = pet.children.find(c => c.font && c.font.pixelSize === 9 && c.text !== undefined)
                const ft = friend.children.find(c => c.font && c.font.pixelSize === 9 && c.text !== undefined)
                check("sign: battery shows a percentage", PetSign.text === "87%" && t.visible && t.text === "87%", PetSign.text + " visible=" + t.visible)
                check("sign: muted colour when all is well", PetSign.level === "" && Qt.colorEqual(t.color, Theme.faint), PetSign.level)
                pet.faceLeft = false
                check("sign: facing right, it is on the left, clear of the bubble", t.x + t.width <= 0, "x=" + t.x + " w=" + t.width)
                pet.faceLeft = true
                check("sign: facing left, it moves to the right", t.x >= pet.box, "x=" + t.x)
                check("sign: the friend carries none", !ft.visible)
                PetSign.batteryDemo = 12
                check("sign: low battery turns it red", PetSign.level === "bad" && Qt.colorEqual(t.color, Theme.red), PetSign.level)
                Pet.napping = true
                return 500         // not 300: a state file write in flight undoes a change made as it lands
            } },
            { name: "sign: hidden while asleep", run: function() {
                const t = pet.children.find(c => c.font && c.font.pixelSize === 9 && c.text !== undefined)
                check("sign: asleep, no sign", pet.mood === "asleep" && !t.visible, "mood=" + pet.mood + " visible=" + t.visible)
                Pet.napping = false
                PetSign.mailDemo = 4
                PetSign.setSign("mail")
                return 500
            } },
            { name: "sign: mail, and Do Not Disturb", run: function() {
                const t = pet.children.find(c => c.font && c.font.pixelSize === 9 && c.text !== undefined)
                check("sign: mail shows the unread count", t.visible && PetSign.text === Icons.envelope + " 4", PetSign.text + " visible=" + t.visible + " " + state(pet))
                Notif.setDnd(true)
                check("sign: the mail count hides under Do Not Disturb", PetSign.text === "" && !t.visible, PetSign.text)
                Notif.setDnd(false)
                Sys.nextEvent = { title: "Office hours", start: "14:08", end: "15:00" }
                PetSign.setSign("event")
                check("sign: next event in minutes", PetSign.text === Icons.clock + " 8m", PetSign.text)
                check("sign: within 10 minutes it stands out", PetSign.level === "soon", PetSign.level)
                Sys.nextEvent = { title: "Lab", start: "15:25", end: "16:00" }
                check("sign: over an hour away", PetSign.text === Icons.clock + " 1h25" && PetSign.level === "", PetSign.text)
                Sys.nextEvent = null
                check("sign: no event, no sign", PetSign.text === "")
                PetSign.tempDemo = 88
                PetSign.setSign("temp")
                check("sign: CPU temperature", PetSign.text === "88°" && PetSign.level === "warn", PetSign.text + " " + PetSign.level)
                PetSign.setSign("none")
                PetSign.mailDemo = -1; PetSign.batteryDemo = -1; PetSign.tempDemo = -1
                clickRow("Settings")
                return 150
            } },
            { name: "sign: menu row steps through the choices", run: function() {
                check("sign: Settings page has a Sign row", findRow(menu, "Sign") !== null && findRow(menu, "Sign").detail === "none ›", "page=" + menu.page + " choice=" + PetSign.choice)
                clickRow("Sign")
                check("sign: a click steps to the next choice", PetSign.choice === "mail", PetSign.choice)
                PetSign.setSign("none")
                clickRow("Back")
                return 150
            } },
            // ---- end cases: sign ----
            // ---- cases: cycles ----
            // work and break cycles (PetFocus.qml): seconds-long periods (fractions of a minute) and a fast tick
            { name: "cycles: a cycle starts and the pet turns Do Not Disturb on", run: function() {
                away()
                PetFocus.tickMs = 150
                PetPrefs.setHabit("focusdnd", "on")
                Notif.setDnd(false)
                mark = PetArc.counts.focus
                PetFocus.startCycle(2 / 60, 2 / 60, 3 / 60)
                check("cycles: focusing, round 1", PetFocus.focusing && Pet.focusing && PetFocus.round === 1, PetFocus.status())
                check("cycles: Do Not Disturb turned on", Notif.dnd)
                check("cycles: awake in its own Do Not Disturb", Pet.mood === "focus", Pet.mood)
                check("cycles: minutes left for the sprite", Pet.focusLeft === 1, Pet.focusLeft)
                return 2600
            } },
            { name: "cycles: focus over, a break", run: function() {
                check("cycles: on a break", PetFocus.onBreak && !PetFocus.longBreak && !Pet.focusing, PetFocus.status())
                check("cycles: Do Not Disturb back off", !Notif.dnd)
                check("cycles: mood break", Pet.mood === "break" && pet.mood === "break", Pet.mood)
                check("cycles: counted once today and once in the journal", PetFocus.doneToday === 1 && PetArc.counts.focus === mark + 1, PetFocus.doneToday + " " + PetArc.counts.focus + " was " + mark)
                check("cycles: announced", Sys.ran.length > 0 && Sys.ran[Sys.ran.length - 1].indexOf("Focus time is up") >= 0, Sys.ran[Sys.ran.length - 1])
                return 2000
            } },
            { name: "cycles: after the break it waits for you", run: function() {
                check("cycles: waiting for round 2", PetFocus.waiting && PetFocus.round === 2 && Pet.mood !== "break", PetFocus.status() + " mood " + Pet.mood)
                check("cycles: break over announced", Sys.ran[Sys.ran.length - 1].indexOf("Break is over") >= 0, Sys.ran[Sys.ran.length - 1])
                PetFocus.resume()
                check("cycles: resumed: focus, Do Not Disturb on again", PetFocus.focusing && Notif.dnd && Pet.mood === "focus", PetFocus.status())
                PetFocus.stop()
                check("cycles: stopped mid-focus: Do Not Disturb restored", !PetFocus.active && !Notif.dnd, PetFocus.status())
                Notif.setDnd(true)                  // the user's own Do Not Disturb
                Pet.startFocus(2 / 60)
                check("cycles: the user's Do Not Disturb still means asleep", Pet.mood === "asleep" && Pet.focusing, Pet.mood)
                PetFocus.stop()
                check("cycles: and stop leaves the user's Do Not Disturb on", Notif.dnd)
                Notif.setDnd(false)
                PetPrefs.setHabit("carryon", "auto")
                PetFocus.startCycle(2 / 60, 4 / 60, 3 / 60)
                return 2400
            } },
            { name: "cycles: auto: the break begins", run: function() {
                check("cycles: auto: on a break", PetFocus.onBreak, PetFocus.status())
                return 2000
            } },
            { name: "cycles: a ball game on the break", run: function() {
                check("cycles: it plays on its break", pet.ballOut, state(pet))
                return 2400
            } },
            { name: "cycles: auto: round 2 starts by itself", run: function() {
                check("cycles: auto: focusing in round 2", PetFocus.focusing && PetFocus.round === 2, PetFocus.status())
                PetFocus.stop()
                PetFocus.startCycle(2 / 60, 2 / 60, 3 / 60, 4)
                return 2400
            } },
            { name: "cycles: the fourth round gives the long break", run: function() {
                check("cycles: long break", PetFocus.onBreak && PetFocus.longBreak && PetFocus.status().indexOf("longbreak") === 0, PetFocus.status())
                return 3000
            } },
            { name: "cycles: after the long break, round 1", run: function() {
                check("cycles: back to round 1", PetFocus.focusing && PetFocus.round === 1, PetFocus.status())
                PetFocus.stop()
                PetFocus.startCycle(1, 1, 1)
                menu.page = "focus"
                return 200
            } },
            { name: "cycles: menu: Skip to break", run: function() {
                mark = PetFocus.doneToday
                check("cycles: menu: round shown", findRow(menu, "Round") !== null && findRow(menu, "25 minutes") === null)
                check("cycles: menu: Skip to break clicked", clickRow("Skip to break"))
                check("cycles: skipped to the break, not counted", PetFocus.onBreak && PetFocus.doneToday === mark, PetFocus.status())
                return 200
            } },
            { name: "cycles: menu: Stop", run: function() {
                check("cycles: menu: Stop clicked", clickRow("Stop"))
                check("cycles: stopped", !PetFocus.active, PetFocus.status())
                return 200
            } },
            { name: "cycles: menu: the cycle row", run: function() {
                check("cycles: menu: lengths and the cycle row are back", findRow(menu, "25 minutes") !== null && findRow(menu, "Cycle: 25 / 5") !== null)
                menu.page = ""
                Pet.startFocus(2 / 60)              // a single timer: no break after it
                return 2400
            } },
            { name: "cycles: a single timer is as it was", run: function() {
                check("cycles: single timer over, no break", !PetFocus.active, PetFocus.status())
                check("cycles: the old notification", Sys.ran[Sys.ran.length - 1].indexOf("Stand up, stretch") >= 0, Sys.ran[Sys.ran.length - 1])
                PetPrefs.reset()
                PetFocus.tickMs = 5000
                Notif.setDnd(false)
                return 1500
            } },
            // ---- end cases: cycles ----
            // ---- cases: play ----
            // the pet and its friend playing together (PetPlay.qml); scenes made short, none by themselves
            { name: "play: a friend comes to play", run: function() {
                PetPlay.chance = 0; PetPlay.tagSwaps = 1; PetPlay.ballKnocks = 2; PetPlay.rideMs = 1500; PetPlay.eatMs = 600
                away()
                Pet.setFriend("dog")
                return 1500
            } },
            { name: "play: tag, when asked", run: function() {
                check("play: no perch for a cat and a dog", PetPlay.start("perch").indexOf("no:") === 0, PetPlay.start("perch"))
                check("play: an unknown scene is refused", PetPlay.start("chess").indexOf("no:") === 0)
                Pet.setCalm(true)
                check("play: not in calm mode", PetPlay.start("tag").indexOf("calm") >= 0, PetPlay.start("tag"))
                Pet.setCalm(false)
                park(pet, pet.home.from + 60); park(friend, pet.home.from + 220)
                const r = PetPlay.start("tag")
                check("play: tag starts", r === "ok tag" && PetPlay.scene === "tag" && pet.busy && friend.busy, r + "  pet " + state(pet) + "  friend " + state(friend))
                return 300
            } },
            { name: "play: tag plays out", run: function() {
                if (!playDone(15000)) return 400
                check("play: tag ends by itself", PetPlay.last === "tag done", PetPlay.last)
                checkClear("tag")
                return 100
            } },
            { name: "play: a scroll with a friend there is the ball for two", run: function() {
                away(); park(pet, pet.home.from + 60); park(friend, pet.home.from + 260)
                ev.mouseWheel(pet, 16, 16, Qt.NoButton, Qt.NoModifier, 0, 120, 0)
                check("play: the shared ball game", PetPlay.scene === "ball" && pet.busy && friend.busy && (pet.ballOut || friend.ballOut), PetPlay.last + "  pet " + state(pet))
                return 400
            } },
            { name: "play: the ball plays out", run: function() {
                if (!playDone(15000)) return 400
                check("play: the ball game ends by itself", PetPlay.last === "ball done", PetPlay.last)
                checkClear("ball")
                return 100
            } },
            { name: "play: fed, they eat side by side", run: function() {
                park(pet, pet.home.from + 60); park(friend, pet.home.from + 300)
                Pet.giveFood()
                check("play: the food scene", PetPlay.scene === "food" && friend.walking && pet.frame === pet.fSit, PetPlay.last + "  friend " + state(friend))
                return 400
            } },
            { name: "play: eating", run: function() {
                if (!playDone(8000)) return 400
                check("play: they ate together", PetPlay.last === "food done" && Math.abs(pet.x - friend.x) <= 40, PetPlay.last + "  pet " + state(pet) + "  friend " + state(friend))
                checkClear("food")
                return 100
            } },
            { name: "play: an alert in the middle of tag", run: function() {
                park(pet, pet.home.from + 60); park(friend, pet.home.from + 220)
                check("play: tag again", PetPlay.start("tag") === "ok tag")
                return 600
            } },
            { name: "play: the alert arrives", run: function() {
                Notif.arrive("mail", "test")
                return 150
            } },
            { name: "play: alert ends the scene", run: function() {
                check("play: alert: scene over at once", PetPlay.scene === "" && PetPlay.last.indexOf("tag ended") === 0, PetPlay.last)
                check("play: alert: both free", !pet.busy && !friend.busy && pet.lift === 0 && friend.lift === 0, state(pet) + "  /  " + state(friend))
                return 3000
            } },
            { name: "play: both at the bell", run: function() {
                const bell = pet.nearestSpot(pet.bellX), beside = friend.nearestSpot(friend.bellX - 38)
                check("play: alert: the pet goes to the bell", Math.abs((pet.walking ? pet.walkTarget : pet.x) - bell) < 6, state(pet) + " bell " + Math.round(bell))
                check("play: alert: the friend beside it", Math.abs((friend.walking ? friend.walkTarget : friend.x) - beside) < 6, state(friend) + " beside " + Math.round(beside))
                Notif.markSeen()
                return 1200
            } },
            { name: "play: picked up in the middle of a scene", run: function() {
                away(); park(pet, pet.home.from + 60); park(friend, pet.home.from + 300)
                check("play: food scene for the pick-up", PetPlay.start("food") === "ok food")
                ev.mousePress(pet, 16, 16, Qt.LeftButton, Qt.NoModifier, 0)
                ev.mouseMove(bar, pet.x + 16 + 40, 17, 0, Qt.LeftButton, Qt.NoModifier)
                check("play: pick-up: carried, scene over", pet.carried && PetPlay.scene === "", PetPlay.last + "  " + state(pet))
                check("play: pick-up: the friend is free", !friend.busy && friend.lift === 0, state(friend))
                ev.mouseRelease(bar, pet.x + 16, 17, Qt.LeftButton, Qt.NoModifier, 0)
                away()
                return 900
            } },
            { name: "play: put down again", run: function() {
                check("play: pick-up: both free afterwards", !pet.busy && !pet.carried && !friend.busy, state(pet))
                park(pet, pet.home.from + 60); park(friend, pet.home.from + 260)
                check("play: ball for the send-off", PetPlay.start("ball") === "ok ball")
                return 400
            } },
            { name: "play: the friend sent away mid-game", run: function() {
                Pet.setFriend("")
                check("play: sent away: scene over", PetPlay.scene === "", PetPlay.last)
                check("play: sent away: the pet is free, no ball left", !pet.busy && !pet.ballOut && !friend.ballOut, state(pet))
                Pet.setFriend("dog")
                return 1200
            } },
            { name: "play: a new coat mid-game", run: function() {
                park(pet, pet.home.from + 60); park(friend, pet.home.from + 220)
                check("play: tag for the coat change", PetPlay.start("tag") === "ok tag")
                Pet.nextFriendCoat()
                check("play: coat change: scene over, both free", PetPlay.scene === "" && !pet.busy && !friend.busy, PetPlay.last)
                Pet.setFriend("bird")
                onDesk = true
                return 1500
            } },
            { name: "play: a perch at twice the size", run: function() {
                playKeep = [deskPet.x, deskFriend.x]          // put back afterwards, for the desktop cases that follow
                away(); park(deskPet, 200); park(deskFriend, 520)
                const r = PetPlay.start("perch")
                check("play: perch starts (bird on the cat)", r === "ok perch" && PetPlay.rider === deskFriend, r)
                return 400
            } },
            { name: "play: riding", run: function() {
                if (!until(() => PetPlay.riding || PetPlay.scene === "", 6000)) return 300
                const c = deskPet, r = deskFriend, mid = r.x + r.size / 2
                check("play: perch: aboard", PetPlay.riding && r.lift > 0, PetPlay.last + "  " + state(r))
                check("play: perch: the rider within the carrier's width", mid > c.x && mid < c.x + c.size, "rider mid " + Math.round(mid) + " carrier " + Math.round(c.x) + ".." + Math.round(c.x + c.size))
                check("play: perch: the rider above its floor", r.y + r.box <= c.y + c.box - 8 * c.k, "rider bottom " + Math.round(r.y + r.box) + " carrier floor " + Math.round(c.y + c.box))
                return 1200
            } },
            { name: "play: riding along", run: function() {
                const c = deskPet, r = deskFriend, mid = r.x + r.size / 2
                check("play: perch: still aboard as it walks", !PetPlay.riding || (mid > c.x && mid < c.x + c.size && r.lift > 0), "rider mid " + Math.round(mid) + " carrier " + state(c))
                return 300
            } },
            { name: "play: the perch plays out", run: function() {
                if (!playDone(10000)) return 400
                check("play: the perch ends by itself", PetPlay.last === "perch done", PetPlay.last)
                check("play: perch: both back on the floor", deskPet.lift === 0 && deskFriend.lift === 0 && deskFriend.hop === 0, state(deskFriend))
                check("play: perch: both free", !deskPet.busy && !deskFriend.busy)
                park(deskPet, playKeep[0]); park(deskFriend, playKeep[1])
                onDesk = false
                Pet.setFriend("")
                PetPlay.chance = 1; PetPlay.tagSwaps = 0; PetPlay.ballKnocks = 0; PetPlay.rideMs = 7000; PetPlay.eatMs = 1600
                return 900
            } },
            // ---- end cases: play ----
            // ---- cases: animals ----
            { name: "animals: turtle and fox, every coat loads", run: function() {
                let bad = []
                for (const a of ["turtle", "fox"]) {
                    check("animals: " + a + " can be chosen", Pet.setAnimal(a) === a && Pet.kind === Pet.kinds[a], Pet.animal)
                    for (const c of Pet.coatsOf[a]) {
                        Pet.setCoat(c)
                        const img = sheetOf(pet)
                        if (!img || img.status !== Image.Ready || String(img.source).indexOf("pet-" + a + "-" + c + ".png") < 0) bad.push(a + "/" + c + " " + (img ? img.status + " " + img.source : "no image"))
                    }
                }
                check("animals: all six sheets load", bad.length === 0, bad.join(", "))
                Pet.setAnimal("cat"); Pet.setFriend("turtle")
                return 900          // the state file is written 300 ms after a change and read back: let that settle
            } },
            { name: "animals: the turtle as the friend", run: function() {
                const img = sheetOf(friend)
                check("animals: the friend turtle is shown, its sheet loaded", friend.active && img && img.status === Image.Ready && String(img.source).indexOf("pet-turtle-") >= 0, img ? img.source : "none")
                Pet.setFriend("")
                Pet.setAnimal("turtle")
                return 900
            } },
            { name: "animals: a notification: the turtle goes into its shell", run: function() {
                check("turtle: it is the pet now", pet.animal === "turtle" && pet.kind.shell === true, pet.animal)
                away(); park(pet, 300)
                mark = pet.x
                Notif.arrive("test", "hello")
                return 400
            } },
            { name: "animals: in its shell, not off to the bell", run: function() {
                check("turtle: mood is alert", pet.mood === "alert", pet.mood)
                check("turtle: in the shell (frame 9), not walking", pet.frame === 9 && !pet.walking && pet.busy, state(pet))
                check("turtle: it has not moved", Math.abs(pet.x - mark) < 1, state(pet))
                return 2500
            } },
            { name: "animals: still in its shell a while later", run: function() {
                check("turtle: still in the shell after 3 s", pet.frame === 9 && !pet.walking, state(pet))
                return 2000
            } },
            { name: "animals: then it plods over to the bell", run: function() {
                check("turtle: out again and walking to the bell", pet.walking && Math.abs(pet.walkTarget - pet.nearestSpot(pet.bellX)) < 2 && !pet.busy, state(pet))
                Notif.markSeen()
                return 400
            } },
            { name: "animals: picked up and put down, the turtle stays in its shell", run: function() {
                check("turtle: the alert is over", pet.mood === "idle", pet.mood)
                park(pet, 300)
                ev.mousePress(pet, 16, 16, Qt.LeftButton, Qt.NoModifier, 0)
                ev.mouseMove(bar, pet.x + 16 + 40, 17, 0, Qt.LeftButton, Qt.NoModifier)
                check("turtle: carried, in its shell", pet.carried && pet.frame === 9, state(pet))
                ev.mouseRelease(bar, pet.x + 16, 17, Qt.LeftButton, Qt.NoModifier, 0)
                away()
                return 1000
            } },
            { name: "animals: set down, still in its shell", run: function() {
                check("turtle: put down but still in the shell", !pet.carried && pet.busy && pet.frame === 9, state(pet))
                return 2800
            } },
            { name: "animals: the pointer darts at the turtle", run: function() {
                check("turtle: out of its shell again", !pet.busy, state(pet))
                away(); park(pet, 300)
                Pet.pointDemo = pet.x + 16 + 200
                return 400
            } },
            { name: "animals: startled", run: function() {
                Pet.pointDemo = pet.x + 16
                return 400
            } },
            { name: "animals: startled into its shell", run: function() {
                check("turtle: a darting pointer sends it into its shell", pet.busy && pet.frame === 9 && !pet.walking, state(pet))
                Pet.pointDemo = -1
                return 3800
            } },
            { name: "animals: the fox and the ball", run: function() {
                check("turtle: out after the startle", !pet.busy, state(pet))
                Pet.setAnimal("fox")
                return 900
            } },
            { name: "animals: the fox plays ball", run: function() {
                check("fox: it is the pet now", pet.animal === "fox" && pet.kind.steals === true, pet.animal)
                away(); park(pet, 300)
                batted = 0; grabbed = false
                pet.playBall()
                check("fox: the ball game starts", pet.busy && pet.ballOut, state(pet))
                return 6000
            } },
            { name: "animals: the fox has kept the ball", run: function() {
                check("fox: it grabbed the ball and carried it", grabbed, state(pet))
                check("fox: it never batted it", batted === 0, "batted " + batted)
                check("fox: the game is over, no ball left", !pet.ballOut && !pet.carrying && !pet.busy, state(pet))
                Pet.setAnimal("cat")
                away(); park(pet, 300)
                return 900
            } },
            // ---- end cases: animals ----
            // ---- cases: together ----
            // Features meeting each other: each was built and tested alone, by a different hand.
            { name: "together: a turtle in a game of tag", run: function() {
                away(); PetPlay.chance = 0; PetPlay.tagSwaps = 1; PetPlay.rideMs = 1500; PetPlay.ballKnocks = 2
                Pet.setAnimal("cat"); Pet.setFriend("turtle")
                return 900
            } },
            { name: "together: tag with the turtle starts", run: function() {
                park(pet, pet.home.from + 60); park(friend, pet.home.from + 200)
                const r = PetPlay.start("tag")
                check("together: tag with a turtle starts", r === "ok tag", r)
                return 400
            } },
            { name: "together: tag with the turtle ends", run: function() {
                if (!playDone(28000)) return 400
                check("together: tag with a turtle ends one way or another", PetPlay.scene === "", PetPlay.last)
                console.log("PETTEST note: tag with a turtle ended as: " + PetPlay.last)
                checkClear("tag with a turtle")
                Pet.setAnimal("turtle"); Pet.setFriend("bird")
                return 900
            } },
            { name: "together: the bird rides the turtle", run: function() {
                park(pet, pet.home.from + 80); park(friend, pet.home.from + 200)
                const r = PetPlay.start("perch")
                check("together: a bird can perch on a turtle", r === "ok perch", r)
                return 3000
            } },
            { name: "together: aboard the turtle", run: function() {
                check("together: the bird is up on the shell", PetPlay.scene === "perch" ? friend.lift > 0 : true, "lift " + friend.lift + " scene " + PetPlay.scene + " last " + PetPlay.last)
                return 300
            } },
            { name: "together: the perch on the turtle ends", run: function() {
                if (!playDone(20000)) return 400
                checkClear("perch on a turtle")
                Pet.setAnimal("fox"); Pet.setFriend("dog")
                return 900
            } },
            { name: "together: a fox, a dog and the ball", run: function() {
                away(); park(pet, pet.home.from + 60); park(friend, pet.home.from + 240)
                ev.mouseWheel(pet, 16, 16, Qt.NoButton, Qt.NoModifier, 0, 120, 0)
                check("together: the ball is out for the fox and the dog", pet.busy && (pet.ballOut || friend.ballOut), "scene " + PetPlay.scene + "  " + state(pet))
                return 400
            } },
            { name: "together: the fox and dog's ball game ends", run: function() {
                if (!until(() => !pet.busy && !friend.busy && PetPlay.scene === "", 24000)) return 400
                checkClear("fox and dog ball")
                Pet.setAnimal("cat")
                return 900
            } },
            { name: "together: a reminder comes due in the middle of tag", run: function() {
                park(pet, pet.home.from + 60); park(friend, pet.home.from + 220)
                PetPlay.tagSwaps = 6
                check("together: tag starts again", PetPlay.start("tag") === "ok tag")
                PetRemind.add("1s", "together test")
                return 2200
            } },
            { name: "together: the reminder wins", run: function() {
                check("together: the reminder is showing", Pet.mood === "remind" && PetRemind.ringing, Pet.mood)
                check("together: the scene gave way to it", PetPlay.scene === "", PetPlay.scene + " / " + PetPlay.last)
                check("together: nothing left drawn after the scene", !pet.ballOut && !friend.ballOut && pet.lift === 0 && friend.lift === 0)
                return 2500
            } },
            { name: "together: both at the clock for the reminder", run: function() {
                check("together: the pet is at the clock", !pet.walking && Math.abs(pet.x - pet.nearestSpot(pet.clockX)) < 6, state(pet) + " clock " + Math.round(pet.clockX))
                check("together: the friend is not stuck busy", !friend.busy, state(friend))
                PetRemind.done()
                return 600
            } },
            { name: "together: a focus timer started in the middle of tag", run: function() {
                check("together: reminder acknowledged", Pet.mood === "idle", Pet.mood)
                park(pet, pet.home.from + 60); park(friend, pet.home.from + 220)
                PetPlay.start("tag")
                Pet.startFocus(1)
                return 700
            } },
            { name: "together: focus stops the game of tag", run: function() {
                check("together: it is focusing", Pet.mood === "focus", Pet.mood)
                check("together: tag stopped for the focus timer", PetPlay.scene === "" && !pet.busy && !friend.busy, PetPlay.last + "  " + state(pet) + " / " + state(friend))
                check("together: no scene will start during focus", PetPlay.start("tag").indexOf("no:") === 0, PetPlay.last)
                Pet.startFocus(0)
                return 600
            } },
            { name: "together: the sign, a nap and a reminder", run: function() {
                PetSign.batteryDemo = 50; PetSign.setSign("battery")
                Pet.napping = true
                PetRemind.add("1s", "wake up")
                return 2200
            } },
            { name: "together: a reminder wakes it, sign and all", run: function() {
                check("together: the reminder got it up from its nap", Pet.mood === "remind", Pet.mood)
                PetRemind.done()
                return 600
            } },
            { name: "together: back to its nap", run: function() {
                check("together: asleep again once acknowledged", Pet.mood === "asleep", Pet.mood)
                Pet.napping = false; PetSign.setSign("none"); PetSign.batteryDemo = -1
                return 600
            } },
            { name: "together: a turtle that is the pet hears a notification, with a friend there", run: function() {
                Pet.setAnimal("turtle"); Pet.setFriend("dog")
                return 900
            } },
            { name: "together: the notification arrives", run: function() {
                park(pet, pet.home.from + 60); park(friend, pet.home.from + 220)
                Notif.arrive("mu4e", "together test")
                return 1500
            } },
            { name: "together: turtle in its shell, dog on its way", run: function() {
                check("together: the turtle is in its shell", pet.frame === 9 && !pet.walking, state(pet))
                check("together: the dog friend heads for the bell", friend.walking || Math.abs(friend.x - friend.nearestSpot(friend.bellX - 38)) < 8, state(friend))
                Notif.markSeen()
                return 5000
            } },
            { name: "together: the turtle comes out when it is over", run: function() {
                check("together: out of the shell and free after the alert", !pet.busy && pet.frame !== 9, state(pet))
                Pet.setAnimal("cat"); Pet.setFriend("dog")
                onDesk = true
                return 1300
            } },
            { name: "together: treat catch with a friend about", run: function() {
                away(); park(deskPet, 200); park(deskFriend, 500)
                deskGame.autoSpawn = false; deskGame.length = 6000
                const r = PetScore.start()
                check("together: the game starts with a friend there", PetScore.running, r)
                check("together: no scene while the game holds the pet", PetPlay.start("tag").indexOf("no:") === 0, PetPlay.last)
                const at = deskPet.x
                ev.mousePress(deskPet, 16, 16, Qt.LeftButton, Qt.NoModifier, 0)
                ev.mouseMove(desk, at + 32 + 120, 150, 0, Qt.LeftButton, Qt.NoModifier)
                ev.mouseRelease(desk, at + 32 + 120, 150, Qt.LeftButton, Qt.NoModifier, 0)
                return 900
            } },
            { name: "together: picked up during the game", run: function() {
                check("together: not left carried", !deskPet.carried, state(deskPet))
                check("together: game and pet agree", PetScore.running ? (deskPet.inGame && deskPet.busy) : !deskPet.inGame, "running " + PetScore.running + "  " + state(deskPet) + " inGame " + deskPet.inGame)
                PetScore.stop()
                return 2000
            } },
            { name: "together: after the game", run: function() {
                check("together: the pet is free after the game", !deskPet.busy && !deskPet.inGame, state(deskPet))
                onDesk = false
                return 900
            } },
            { name: "together: the animal changes in the middle of a ball game", run: function() {
                Pet.setFriend("")
                away(); park(pet, pet.home.from + 60)
                ev.mouseWheel(pet, 16, 16, Qt.NoButton, Qt.NoModifier, 0, 120, 0)
                Pet.setAnimal("frog")
                return 400
            } },
            { name: "together: the ball game survives a change of animal", run: function() {
                if (!until(() => !pet.busy, 20000)) return 400
                check("together: free after the game, as a frog", !pet.busy && !pet.ballOut && !pet.carrying, state(pet))
                Pet.setAnimal("cat")
                PetPlay.chance = 1; PetPlay.tagSwaps = 0; PetPlay.rideMs = 7000; PetPlay.ballKnocks = 0
                return 900
            } },
            // ---- end cases: together ----
            // ---- cases: secrets ----
            { name: "secrets: costumes", run: function() {
                away(); Pet.setFriend(""); Pet.setCoat("tiger"); park(pet, 300)
                PetSecrets.ready = true; PetSecrets.quietUntil = 0
                muteStars = true        // a found secret is celebrated with a star a moment later: not in the middle of the next check
                check("secrets: an ordinary day has no costume", PetSecrets.costume === "" && !PetSecrets.fool, PetSecrets.costume)
                for (const s of [pet, friend, deskPet, deskFriend]) anticsOf(s).pushChance = 0
                check("secrets: none found to begin with", PetSecrets.count === 0, PetSecrets.report())
                PetSecrets.costumeDemo = "ghost"
                check("costume: the ghost sheet is drawn", String(sheetOf(pet).source).indexOf("pet-cat-ghost.png") >= 0, String(sheetOf(pet).source))
                PetSecrets.costumeDemo = "shadow"
                check("costume: the cat's shadow is its panther coat", String(sheetOf(pet).source).indexOf("pet-cat-panther.png") >= 0, String(sheetOf(pet).source))
                Pet.setAnimal("dog")
                check("costume: the dog's shadow is its own sheet", String(sheetOf(pet).source).indexOf("pet-dog-shadow.png") >= 0, String(sheetOf(pet).source))
                PetSecrets.costumeDemo = "shiny"
                return 300
            } },
            { name: "secrets: costume sheets load, and come off", run: function() {
                check("costume: the gold sheet loaded", sheetOf(pet).status === Image.Ready, String(sheetOf(pet).source))
                const was = Pet.coat
                Pet.nextCoat()
                check("costume: stepping Coat takes it off and keeps the coat", PetSecrets.costume === "" && Pet.coat === was, PetSecrets.costume + " " + Pet.coat)
                Pet.setCoat("tiger")
                PetSecrets.dayDemo = "2026-10-31"
                check("date: a ghost on 31 October", PetSecrets.costume === "ghost", PetSecrets.costume)
                return 200
            } },
            { name: "secrets: other dates", run: function() {
                check("date: and the ghost is found", PetSecrets.has("ghost"), PetSecrets.report())
                PetSecrets.dayDemo = "2026-11-13"
                check("date: a shadow on Friday the 13th", PetSecrets.costume === "shadow", PetSecrets.costume)
                PetSecrets.dayDemo = "2026-11-14"
                check("date: nothing the day after", PetSecrets.costume === "", PetSecrets.costume)
                PetSecrets.dayDemo = "2027-04-01"
                check("1 April: it is not itself", PetSecrets.fool && pet.animal !== Pet.animal && pet.animal !== "", pet.animal)
                return 400
            } },
            { name: "secrets: 1 April, seen through", run: function() {
                check("1 April: the other animal's sheet loaded", sheetOf(pet).status === Image.Ready, String(sheetOf(pet).source))
                ev.mouseClick(pet, 16, 16, Qt.LeftButton, Qt.NoModifier, 0)
                check("1 April: a pat and it is itself again", !PetSecrets.fool && pet.animal === "cat", pet.animal)
                check("1 April: found", PetSecrets.has("fool"))
                Pet.setFriend("dog")
                PetSecrets.foolDemo = true
                check("1 April with a friend: they have swapped", pet.animal === "dog" && friend.animal === "cat", pet.animal + " " + friend.animal)
                PetSecrets.foolDemo = false
                Pet.setFriend("")
                PetSecrets.dayDemo = "2026-07-01"
                return 4300             // longer than the four seconds ten pats must fit in
            } },
            { name: "secrets: ten quick pats", run: function() {
                away(); park(pet, 300)
                for (let i = 0; i < 9; i++) ev.mouseClick(pet, 16, 16, Qt.LeftButton, Qt.NoModifier, 0)
                check("dizzy: nine pats are just pats", anticsOf(pet).act === "", anticsOf(pet).act)
                ev.mouseClick(pet, 16, 16, Qt.LeftButton, Qt.NoModifier, 0)
                check("dizzy: the tenth sets it spinning", anticsOf(pet).act === "dizzy" && pet.busy, state(pet))
                return 1300
            } },
            { name: "secrets: on its back", run: function() {
                check("dizzy: over on its back", pet.upside && pet.frame === pet.fLoaf, state(pet))
                return 3600
            } },
            { name: "secrets: up again", run: function() {
                check("dizzy: right way up and free", !pet.upside && !pet.busy && anticsOf(pet).act === "", state(pet))
                check("dizzy: found", PetSecrets.has("dizzy"))
                return 100
            } },
            { name: "secrets: the pointer rests on it", run: function() {
                away(); park(pet, 300)
                anticsOf(pet).dozeMs = 1200
                ev.mouseMove(pet, 16, 20, 0, Qt.NoButton, Qt.NoModifier)
                return 300
            } },
            { name: "secrets: it dozes off under the pointer", run: function() {
                if (!until(() => anticsOf(pet).dozing, 6000)) return 150
                check("doze: asleep under the pointer", anticsOf(pet).dozing && pet.frame === pet.fSleep && pet.bubble === "z", state(pet))
                return 2200
            } },
            { name: "secrets: and wakes when the pointer moves", run: function() {
                check("doze: still asleep two seconds on", anticsOf(pet).dozing && pet.busy, state(pet))
                ev.mouseMove(pet, 19, 20, 0, Qt.NoButton, Qt.NoModifier)
                check("doze: a move wakes it", !anticsOf(pet).dozing, state(pet))
                away()
                anticsOf(pet).dozeMs = 60000
                return 2600
            } },
            { name: "secrets: put down on the bell", run: function() {
                check("doze: free again", !pet.busy, state(pet))
                check("doze: found", PetSecrets.has("doze"))
                away(); park(pet, pet.bellX - 60)
                const bell = (pet.spans.bell.from + pet.spans.bell.to) / 2
                ev.mousePress(pet, 16, 16, Qt.LeftButton, Qt.NoModifier, 0)
                ev.mouseMove(bar, bell - 20, 17, 0, Qt.LeftButton, Qt.NoModifier)
                ev.mouseMove(bar, bell, 17, 0, Qt.LeftButton, Qt.NoModifier)
                check("bell: carried no further than the open bar", pet.carried && pet.inGaps(pet.x), state(pet))
                ev.mouseRelease(bar, bell, 17, Qt.LeftButton, Qt.NoModifier, 0)
                check("bell: it rings it", rings === 1 && anticsOf(pet).act === "bell" && pet.bubble === "ding!", "rings " + rings + " " + state(pet))
                check("bell: up against the bell, in front of it", pet.atop && Math.abs(pet.x + 16 - bell) < 3 && pet.z >= 3, state(pet) + " z " + pet.z)
                away()
                return 3200
            } },
            { name: "secrets: back from the bell", run: function() {
                check("bell: free, and out in the open again", !pet.busy && !pet.atop && pet.inGaps(pet.x), state(pet))
                check("bell: found", PetSecrets.has("bell"))
                park(pet, pet.clockX - 80)
                const mid = (pet.spans.clock.from + pet.spans.clock.to) / 2
                ev.mousePress(pet, 16, 16, Qt.LeftButton, Qt.NoModifier, 0)
                ev.mouseMove(bar, mid - 30, 17, 0, Qt.LeftButton, Qt.NoModifier)
                ev.mouseMove(bar, mid, 17, 0, Qt.LeftButton, Qt.NoModifier)
                ev.mouseRelease(bar, mid, 17, Qt.LeftButton, Qt.NoModifier, 0)
                check("clock: it sits on the clock, which sinks", pet.weigh && pet.atop && Math.abs(pet.x + 16 - mid) < 3 && pet.frame === pet.fSit, state(pet))
                away()
                return 3000
            } },
            { name: "secrets: still on the clock", run: function() {
                check("clock: still there three seconds on", pet.weigh && pet.busy, state(pet))
                return 5200
            } },
            { name: "secrets: off the clock", run: function() {
                check("clock: off again, nothing held down", !pet.weigh && !pet.atop && !pet.busy && pet.inGaps(pet.x), state(pet))
                check("clock: found", PetSecrets.has("clock"))
                // an ordinary put-down still is one
                park(pet, 300)
                ev.mousePress(pet, 16, 16, Qt.LeftButton, Qt.NoModifier, 0)
                ev.mouseMove(bar, pet.x + 16 + 60, 17, 0, Qt.LeftButton, Qt.NoModifier)
                ev.mouseRelease(bar, pet.x + 16, 17, Qt.LeftButton, Qt.NoModifier, 0)
                check("carry: put down in the open, nothing rings", rings === 1 && anticsOf(pet).act === "" && !pet.atop, state(pet))
                return 900
            } },
            { name: "secrets: a Clemson name", run: function() {
                away(); park(pet, pet.home.from + 20)
                Pet.setName("Dabo")
                check("name: Dabo is a Clemson name", PetSecrets.clemson)
                maxPrints = 0
                pet.walkTo(pet.home.from + 220, 120)
                return 150
            } },
            { name: "secrets: paw prints", run: function() {
                maxPrints = Math.max(maxPrints, anticsOf(pet).prints.length)
                if (!until(() => !pet.walking, 6000)) return 120
                check("name: it left paw prints as it walked", maxPrints >= 2, "most at once " + maxPrints)
                check("name: found", PetSecrets.has("clemson"))
                return 3400
            } },
            { name: "secrets: named after its own kind", run: function() {
                check("name: the prints have faded", anticsOf(pet).prints.length === 0, anticsOf(pet).prints.length)
                park(pet, 300)
                Pet.setName("Cat")
                return 200
            } },
            { name: "secrets: it sulks", run: function() {
                check("name: called Cat, the cat turns its back", anticsOf(pet).act === "sulk" && pet.bubble === "..." && pet.busy, state(pet))
                return 4400
            } },
            { name: "secrets: a shooting star", run: function() {
                check("name: over it", !pet.busy, state(pet))
                check("name: found", PetSecrets.has("species"))
                Pet.setName("Cub")
                away(); park(pet, 300)
                PetSecrets.startSky("star")
                check("star: it sits and watches", anticsOf(pet).act === "star" && pet.bubble === "★" && pet.frame === pet.fSit, state(pet))
                return 700
            } },
            { name: "secrets: the star crosses", run: function() {
                check("star: on its way across", PetSecrets.sky === "star" && PetSecrets.skyT > 0.2 && PetSecrets.skyT < 1, PetSecrets.skyT)
                return 3200
            } },
            { name: "secrets: something else in the sky", run: function() {
                check("star: gone, and the pet is free", PetSecrets.sky === "" && !pet.busy, state(pet))
                Pet.setCalm(true)
                PetSecrets.startSky("star")
                check("star: in calm mode it takes no notice", anticsOf(pet).act === "" && !pet.busy, state(pet))
                Pet.setCalm(false)
                return 1600
            } },
            { name: "secrets: the saucer", run: function() {
                Pet.setFriend("turtle")
                return 900
            } },
            { name: "secrets: they duck", run: function() {
                park(pet, 300); park(friend, 500)
                PetSecrets.startSky("ufo")
                check("ufo: the cat is flat on the floor", anticsOf(pet).act === "ufo" && pet.frame === pet.fLoaf && pet.bubble === "!", state(pet))
                check("ufo: the turtle is in its shell", friend.frame === friend.fPounce && friend.busy, state(friend))
                return 9800
            } },
            { name: "secrets: all clear", run: function() {
                check("ufo: it has gone", PetSecrets.sky === "", PetSecrets.sky)
                return 1700
            } },
            { name: "secrets: touchdown", run: function() {
                check("ufo: both free", !pet.busy && !friend.busy, state(pet) + " / " + state(friend))
                check("sky: both found", PetSecrets.has("star") && PetSecrets.has("ufo"))
                Pet.setFriend("")
                park(pet, 300)
                PetSecrets.score('{"state": "in", "us": 7, "them": 0}')
                check("score: the first reading is only a start", anticsOf(pet).act === "")
                PetSecrets.score('{"state": "in", "us": 10, "them": 0}')
                check("score: a field goal is not a touchdown", anticsOf(pet).act === "")
                PetSecrets.score('{"state": "in", "us": 16, "them": 0}')
                check("score: six more and it jumps", anticsOf(pet).act === "td" && pet.busy && pet.frame === pet.fPounce, state(pet))
                PetSecrets.score('{"state": "post", "us": 16, "them": 0}')
                return 4200
            } },
            { name: "secrets: the cat and the clock", run: function() {
                check("score: over and free", !pet.busy && PetSecrets.has("touchdown"), state(pet))
                check("score: no more asking once the game has ended", PetSecrets.gameOver === PetSecrets.dayStr)
                park(pet, 300)
                check("push: not before the bond is 60", !anticsOf(pet).maybePush())
                pushes = 0
                anticsOf(pet).push()
                return 200
            } },
            { name: "secrets: it knocks the clock off", run: function() {
                if (!until(() => pushes > 0, 9000)) return 150
                check("push: beside the clock, a paw out", pushes === 1 && Math.abs(pet.x - pet.nearestSpot(pet.clockX)) < 4, "pushes " + pushes + " " + state(pet))
                return 5200
            } },
            { name: "secrets: the dragon", run: function() {
                check("push: done and free", !pet.busy && PetSecrets.has("push"), state(pet))
                check("dragon: not there to begin with", Pet.coatsOf.dragon === undefined && Pet.setAnimal("dragon") === "cat")
                Pet.bump("feed", 50)
                check("bond: one day adds no more than bondPerDay", Pet.bond === Pet.bondPerDay, "bond " + Pet.bond)
                Pet.bondPerDay = 1000            // the days it would really take
                Pet.bump("feed", 100)
                check("dragon: at a bond of 80 it has hatched", PetSecrets.has("dragon") && Pet.coatsOf.dragon !== undefined, PetSecrets.report())
                check("dragon: and can be chosen", Pet.setAnimal("dragon") === "dragon" && Pet.coat === "ember", Pet.animal + " " + Pet.coat)
                return 500
            } },
            { name: "secrets: fire", run: function() {
                check("dragon: its sheet loaded", sheetOf(pet).status === Image.Ready && String(sheetOf(pet).source).indexOf("pet-dragon-ember.png") >= 0, String(sheetOf(pet).source))
                park(pet, 300)
                Pet.trick("breathe fire")
                check("dragon: it breathes fire", anticsOf(pet).fire && pet.frame === 8 && pet.busy, state(pet))
                return 3400
            } },
            { name: "secrets: the count", run: function() {
                check("dragon: the fire is out", !anticsOf(pet).fire && !pet.busy, state(pet))
                Pet.setAnimal("cat"); Pet.setCoat("tiger")
                check("secrets: the journal counts them", PetSecrets.count >= 12 && PetSecrets.summary === PetSecrets.count + " of 17", PetSecrets.report())
                check("secrets: each made a diary line", PetArc.entries.filter(e => e.t.indexOf("secret") >= 0 || e.t.indexOf("hatched") >= 0).length >= 10, PetArc.entries.length)
                PetSecrets.quietUntil = Date.now() + 1e9
                muteStars = false
                return 3600
            } },
            // ---- end cases: secrets ----
            { name: "down on the desktop with a friend", run: function() {
                check("menu: and Back again lands on the main page", menu.page === "", menu.page)
                Pet.setFriend("dog")
                onDesk = true
                return 1200
            } },
            { name: "desktop: both shown, twice the size", run: function() {
                check("desktop: the bar's pets are gone", !pet.active && !friend.active)
                check("desktop: pet and friend are there", deskPet.active && deskFriend.active)
                check("desktop: drawn at twice the size", deskPet.size === 64, deskPet.size)
                Pet.pointDemo = 500
                return 5000
            } },
            { name: "desktop: side by side at the pointer", run: function() {
                const apart = Math.abs(deskPet.x - deskFriend.x)
                check("desktop: they do not stand on each other", apart >= 60, "apart " + Math.round(apart) + "  pet " + state(deskPet) + "  friend " + state(deskFriend))
                Pet.pointDemo = -1
                return 1900
            } },
            { name: "desktop: click and drag at scale 2", run: function() {
                away(); park(deskPet, 200); park(deskFriend, 600)
                ev.mouseClick(deskPet, 16, 16, Qt.LeftButton, Qt.NoModifier, 0)
                check("desktop: a click pets the pet, not the friend", deskPet.busy && !deskFriend.busy, state(deskPet))
                park(deskPet, 200)
                mark = deskPet.x
                ev.mousePress(deskPet, 16, 16, Qt.LeftButton, Qt.NoModifier, 0)
                ev.mouseMove(desk, mark + 32 + 100, 150, 0, Qt.LeftButton, Qt.NoModifier)
                check("desktop: carried to the pointer", deskPet.carried && Math.abs(deskPet.x - (mark + 100)) < 8, state(deskPet) + " was x=" + Math.round(mark))
                ev.mouseRelease(desk, mark + 32 + 100, 150, Qt.LeftButton, Qt.NoModifier, 0)
                check("desktop: put down", !deskPet.carried)
                return 800
            } },
            { name: "back up to the bar", run: function() {
                away()
                onDesk = false
                Pet.setFriend("")
                return 900
            } },
            { name: "bar again", run: function() {
                check("bar: the pet is back and free", pet.active && !pet.busy && !deskPet.active, state(pet))
                check("friend sent away", !friend.active && !deskFriend.active)
                return 100
            } },
            // the last thing before the picture is saved: a scene with as much drawn as possible,
            // so the picture (pet-test -o, with or without -l) shows colours worth looking at
            { name: "a full scene for the picture", run: function() {
                away()
                Pet.setFriend("frog")
                WallState.wxKind = "rain"                       // the cat's umbrella
                PetSign.batteryDemo = 12; PetSign.setSign("battery")     // a red sign
                return 900
            } },
            { name: "posed", run: function() {
                park(pet, pet.home.from + 120); park(friend, pet.home.from + 260)
                pet.bubble = "12m"
                pet.ballX = pet.x + 70; pet.ballOut = true
                friend.patted()
                menu.page = "say"
                return 500
            } }
        ]

        property int at: 0
        Timer {
            id: stepper
            interval: 1200; running: true       // let the bar lay out and the pet settle first
            onTriggered: {
                if (win.at >= win.cases.length) {
                    console.log("PETTEST RESULT pass " + win.passed + " fail " + win.failed)
                    const out = Quickshell.env("PET_TEST_OUT")
                    if (!out) { Qt.quit(); return }
                    stage.grabToImage(function(res) { res.saveToFile(out); Qt.quit() })
                    giveUp.start()
                    return
                }
                // PET_TEST_POSE (pet-test -p): skip the checks and go straight to the posed scene for the picture
                if (Quickshell.env("PET_TEST_POSE") && win.at === 1) win.at = win.cases.length - 2
                const c = win.cases[win.at++]
                console.log("PETTEST case: " + c.name)
                let wait = 100
                try { wait = c.run() } catch (e) { win.failed++; console.log("PETTEST FAIL " + c.name + " threw: " + e) }
                interval = Math.max(20, wait || 100)
                restart()
            }
        }
        Timer { id: giveUp; interval: 3000; onTriggered: Qt.quit() }
    }
}
