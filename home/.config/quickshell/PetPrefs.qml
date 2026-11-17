// The bar pet's habits (Pet.qml, PetSprite.qml): the few things about its day you may want
// different, kept apart from its mind so they can be changed without editing any QML.
// Change them in its menu (Settings > Habits: each click steps to the next choice) or from a script:
//   qs ipc call pet set KEY VALUE     prints KEY=VALUE as stored, or why the value was refused
//   qs ipc call pet get KEY           prints the value
//   qs ipc call pet habits            every key, its value and what it accepts
//   qs ipc call pet resethabits       all back to the defaults
// Keys (the default first; the menu steps through the listed choices, a script may give any
// value the key accepts):
//   bedtime   23:00    when it goes to sleep for the night: 21:00 22:00 23:00 00:00 01:00 never,
//                      or any HH:MM. "never": it stays up all night. It lies down more in the
//                      two hours before (and the hour after, for an animal that stays up).
//   wake      06:00    when it wakes: 05:00 06:00 07:00 08:00 09:00, or any HH:MM
//                      (the same time as bedtime means it never sleeps)
//   meeting   5        minutes before an event that it runs to the clock: off 2 5 10 15, or 1 to 60
//   lively    normal   quiet | normal | lively: how often it does some small thing when idle, how
//                      much it wanders, and how often a moth or a seasonal leaf turns up
//   bell      25       seconds it waits by the bell after a notification: 10 25 60 300 read,
//                      or 5 to 3600; "read": until the notifications are read
//   hunger    5        hours after a meal before it thinks of food again: 3 5 8 12, or 1 to 48
//   work      25       minutes of focus in a cycle (PetFocus.qml): 15 25 45 50 60, or 1 to 240
//   shortbreak 5       minutes of the break after each focus period: 3 5 10 15, or 1 to 60
//   longbreak 15       minutes of the break after every fourth: 10 15 20 30, or 1 to 120
//   carryon   wait     after a break: wait (for you to start the next round) | auto (it starts by itself)
//   focusdnd  off      Do Not Disturb while focusing: off | on (turned back as it was afterwards)
// Kept in ~/.local/state/pet-habits.json (a value it cannot make sense of counts as the default).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: prefs

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/pet-habits.json"
        blockLoading: true
        blockWrites: true           // a change made while an unfinished write was in flight used to be undone when it landed
        printErrors: false
        onAdapterUpdated: saveSoon.restart()
        JsonAdapter {
            id: store
            property string bedtime: "23:00"
            property string wake: "06:00"
            property string meeting: "5"
            property string lively: "normal"
            property string bell: "25"
            property string hunger: "5"
            property string work: "25"
            property string shortbreak: "5"
            property string longbreak: "15"
            property string carryon: "wait"
            property string focusdnd: "off"
        }
    }
    Timer { id: saveSoon; interval: 300; onTriggered: file.writeAdapter() }

    readonly property var keys: ["bedtime", "wake", "meeting", "lively", "bell", "hunger", "work", "shortbreak", "longbreak", "carryon", "focusdnd"]
    readonly property var defaults: ({ bedtime: "23:00", wake: "06:00", meeting: "5", lively: "normal", bell: "25", hunger: "5",
                                    work: "25", shortbreak: "5", longbreak: "15", carryon: "wait", focusdnd: "off" })
    readonly property var choices: ({
        bedtime: ["21:00", "22:00", "23:00", "00:00", "01:00", "never"],
        wake: ["05:00", "06:00", "07:00", "08:00", "09:00"],
        meeting: ["off", "2", "5", "10", "15"],
        lively: ["quiet", "normal", "lively"],
        bell: ["10", "25", "60", "300", "read"],
        hunger: ["3", "5", "8", "12"],
        work: ["15", "25", "45", "50", "60"], shortbreak: ["3", "5", "10", "15"], longbreak: ["10", "15", "20", "30"],
        carryon: ["wait", "auto"], focusdnd: ["off", "on"]
    })
    readonly property var accepts: ({
        bedtime: "HH:MM or never", wake: "HH:MM", meeting: "off or 1 to 60 (minutes)",
        lively: "quiet normal lively", bell: "5 to 3600 (seconds) or read", hunger: "1 to 48 (hours)",
        work: "1 to 240 (minutes)", shortbreak: "1 to 60 (minutes)", longbreak: "1 to 120 (minutes)", carryon: "wait auto", focusdnd: "off on"
    })

    // ---- what a value means: the stored form of something typed, or "" when it makes no sense ----
    function hm(v) {
        const m = /^(\d{1,2})(?::(\d{2}))?$/.exec(v)
        if (!m) return ""
        const h = parseInt(m[1]), mi = m[2] === undefined ? 0 : parseInt(m[2])
        if (h > 23 || mi > 59) return ""
        return (h < 10 ? "0" : "") + h + ":" + (mi < 10 ? "0" : "") + mi
    }
    function within(v, lo, hi) {
        if (!/^\d+$/.test(v)) return ""
        const n = parseInt(v)
        return n >= lo && n <= hi ? String(n) : ""
    }
    function norm(key, value) {
        const v = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
        if (key === "bedtime") return v === "never" || v === "off" || v === "none" ? "never" : hm(v)
        if (key === "wake") return hm(v)
        if (key === "meeting") return v === "off" || v === "0" || v === "none" ? "off" : within(v, 1, 60)
        if (key === "lively") return choices.lively.indexOf(v) >= 0 ? v : ""
        if (key === "bell") return v === "read" || v === "until read" || v === "0" ? "read" : within(v, 5, 3600)
        if (key === "hunger") return within(v, 1, 48)
        if (key === "work") return within(v, 1, 240)
        if (key === "shortbreak") return within(v, 1, 60)
        if (key === "longbreak") return within(v, 1, 120)
        if (key === "carryon") return v === "auto" || v === "on" || v === "true" ? "auto" : v === "wait" || v === "off" || v === "false" ? "wait" : ""
        if (key === "focusdnd") return v === "on" || v === "true" ? "on" : v === "off" || v === "false" ? "off" : ""
        return ""
    }

    // ---- the habits as they stand (a bad value in the file falls back to the default) ----
    readonly property string bedtime: norm("bedtime", store.bedtime) || defaults.bedtime
    readonly property string wake: norm("wake", store.wake) || defaults.wake
    readonly property string meeting: norm("meeting", store.meeting) || defaults.meeting
    readonly property string lively: norm("lively", store.lively) || defaults.lively
    readonly property string bell: norm("bell", store.bell) || defaults.bell
    readonly property string hunger: norm("hunger", store.hunger) || defaults.hunger
    readonly property string work: norm("work", store.work) || defaults.work
    readonly property string shortbreak: norm("shortbreak", store.shortbreak) || defaults.shortbreak
    readonly property string longbreak: norm("longbreak", store.longbreak) || defaults.longbreak
    readonly property string carryon: norm("carryon", store.carryon) || defaults.carryon
    readonly property string focusdnd: norm("focusdnd", store.focusdnd) || defaults.focusdnd
    readonly property bool isDefault: keys.every(k => prefs[k] === defaults[k])

    // ---- what Pet.qml and PetSprite.qml read ----
    function mins(t) { const p = t.split(":"); return parseInt(p[0]) * 60 + parseInt(p[1]) }
    function inWindow(m, from, to) {       // minutes since midnight; the window may run past midnight
        from = ((from % 1440) + 1440) % 1440; to = ((to % 1440) + 1440) % 1440
        return from <= to ? m >= from && m < to : m >= from || m < to
    }
    // asleep for the night at minute `m` of the day
    function asleepAt(m) { return bedtime !== "never" && inWindow(m, mins(bedtime), mins(wake)) }
    // evenings it lies down more: the two hours before bedtime and the hour after (that hour
    // only shows in an animal that stays up at night). With no bedtime it keeps 21:00 to midnight.
    function sleepyAt(m) { const b = bedtime === "never" ? 23 * 60 : mins(bedtime); return inWindow(m, b - 120, b + 60) }
    // how many minutes ahead of an event it goes to the clock; -1: it does not
    readonly property int meetingLead: meeting === "off" ? -1 : parseInt(meeting)
    // how long it waits by the bell; "read" is a day, which in practice means until they are read
    readonly property int bellWaitMs: bell === "read" ? 86400000 : parseInt(bell) * 1000
    readonly property double hungryAfterMs: parseInt(hunger) * 3600000
    // work and break cycles (PetFocus.qml)
    readonly property bool carryOn: carryon === "auto"
    readonly property bool focusDnd: focusdnd === "on"
    // liveliness: one setting scales several chances together. Normal is how it always was.
    //   idleMs        how often it does one small thing while idle (sits, washes, wanders)
    //   roamScale     times its own nature's chance to wander on each of those
    //   ambientMs     how often there is a chance of a moth or a seasonal leaf
    //   ambientChance that chance
    readonly property var levels: ({
        quiet:  { idleMs: 6000, roamScale: 0.5, ambientMs: 15 * 60000, ambientChance: 0.5 },
        normal: { idleMs: 4200, roamScale: 1,   ambientMs: 7 * 60000,  ambientChance: 0.6 },
        lively: { idleMs: 3000, roamScale: 1.6, ambientMs: 4 * 60000,  ambientChance: 0.8 }
    })
    readonly property var level: levels[lively]
    readonly property int idleMs: level.idleMs
    readonly property real roamScale: level.roamScale
    readonly property int ambientMs: level.ambientMs
    readonly property real ambientChance: level.ambientChance

    // ---- for the menu and scripts ----
    function label(key, v) {               // short enough for the menu's right-hand side
        if (key === "meeting") return v === "off" ? "off" : v + " min"
        if (key === "bell") {
            if (v === "read") return "until read"
            const s = parseInt(v)
            return s >= 60 && s % 60 === 0 ? s / 60 + " min" : s + " s"
        }
        if (key === "hunger") return v + " h"
        if (key === "work" || key === "shortbreak" || key === "longbreak") return v + " min"
        if (key === "carryon") return v === "auto" ? "by itself" : "waits for you"
        return v
    }
    function setHabit(key, value) {
        if (keys.indexOf(key) < 0) return "unknown habit " + key + " (" + keys.join(" ") + ")"
        const v = norm(key, value)
        if (v === "") return "not a value for " + key + ": " + value + " (" + accepts[key] + ")"
        store[key] = v
        return key + "=" + v
    }
    function getHabit(key) {
        if (keys.indexOf(key) < 0) return "unknown habit " + key + " (" + keys.join(" ") + ")"
        return prefs[key]
    }
    function nextHabit(key) {               // the menu: on to the next listed choice
        const cs = choices[key]
        return setHabit(key, cs[(cs.indexOf(prefs[key]) + 1) % cs.length])
    }
    function list() {
        return keys.map(k => k + "=" + prefs[k] + "    choices: " + choices[k].join(" ") + "    accepts: " + accepts[k]
                             + (prefs[k] === defaults[k] ? "" : "    default: " + defaults[k])).join("\n")
    }
    function reset() { for (const k of keys) store[k] = defaults[k]; return list() }
}
