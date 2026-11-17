// Settings > Health: the background jobs shell-health reports (Health.jobs) with their state, and
// "ignore until it recovers" (Health.ignore / unignore, health-ignore.json). A job that works
// again drops off the ignore list by itself (Health.qml). Also "Stop watching" (the `hidden` list)
// and the "Worth knowing" notices (updates, firmware, disk, restart) with their thresholds; both live in
// ~/.config/shell/health.json, which shell-health reads (through JsonFile, so other keys are kept).
import QtQuick
import QtQuick.Layouts
import Quickshell

SettingsPage {
    id: pg
    pageId: "health"
    title: "Health"
    intro: "Background jobs on this laptop (shell-health). A switch is on while the job counts for the bar's health pill; turning a failing one off ignores it until it works again."
    onShownChanged: if (shown) Health.refresh()
    // job ids, changed only when a job comes or goes (every poll gives a new jobs list): rows stay put
    property var ids: []
    readonly property string idKey: Health.jobs.map(j => j.id).join("\n")
    onIdKeyChanged: ids = Health.jobs.map(j => j.id)
    readonly property string cfgPath: Quickshell.env("HEALTH_CONFIG") || Quickshell.env("HOME") + "/.config/shell/health.json"
    JsonFile {
        id: cfg
        path: pg.cfgPath
        defaults: ({ updatesNag: 50, staleListDays: 14, diskPercent: 10, diskGB: 5, espMB: 20, hidden: [], notices: ({ updates: true, firmware: true, disk: true, reboot: true }) })
        watch: pg.shown
    }
    readonly property alias configFile: cfg
    readonly property var hidden: Array.isArray(cfg.values.hidden) ? cfg.values.hidden : []
    readonly property var kinds: (cfg.values.notices && typeof cfg.values.notices === "object") ? cfg.values.notices : ({})
    function setHidden(id, hide) {
        const l = hidden.filter(x => x !== id)
        if (hide) l.push(id)
        cfg.set("hidden", l)
        Health.refresh()
    }
    function setKind(k, on) {
        const o = Object.assign({ updates: true, firmware: true, disk: true, reboot: true }, kinds)
        o[k] = on
        cfg.set("notices", o)
        Health.refresh()
    }
    function num(k, v) { cfg.set(k, v); Health.refresh() }
    // every job there is, watched or not (a hidden one is not in Health.jobs)
    property var watchIds: []
    readonly property string watchKey: Health.jobs.map(j => j.id).concat(Health.hiddenJobs.map(j => j.id), hidden).join("\n")
    onWatchKeyChanged: watchIds = Array.from(new Set(Health.jobs.map(j => j.id).concat(Health.hiddenJobs.map(j => j.id))))
    Component.onCompleted: { ids = Health.jobs.map(j => j.id); watchIds = Array.from(new Set(Health.jobs.map(j => j.id).concat(Health.hiddenJobs.map(j => j.id)))) }
    function nameOf(id) {
        const j = Health.jobs.find(x => x.id === id) || Health.hiddenJobs.find(x => x.id === id)
        return j ? j.name : id
    }
    function stateText(j) { return j.state === "ok" ? "working" : j.state === "off" ? "off" : j.state === "stale" ? "behind" : j.state === "failed" ? "failing" : j.state }

    SettingsCard {
        title: "Jobs"
        note: !Health.loaded ? "asking…" : Health.bad.length === 0 ? "all well" : Health.bad.length + " need a look"
        Repeater {
            model: pg.ids
            SettingsSwitch {
                required property var modelData
                readonly property var job: Health.jobs.find(j => j.id === modelData) || ({ id: modelData, name: modelData, state: "" })
                readonly property bool isBad: job.state === "failed" || job.state === "stale"
                label: job.name + "  ·  " + pg.stateText(job)
                sub: isBad ? (Health.ignored[job.id] ? "Ignored until it recovers" : "") + (job.why ? (Health.ignored[job.id] ? "; " : "") + job.why : "") : (job.why || "")
                keywords: "health job " + job.id + " " + job.state
                enabled: isBad || !!Health.ignored[job.id]
                checked: !Health.ignored[job.id]
                onEdited: on => { if (on) Health.unignore(job.id); else Health.ignore(job.id) }
            }
        }
        Caption { visible: Health.jobs.length === 0; text: Health.loaded ? "shell-health listed no jobs." : "Asking shell-health…" }
        SettingsButton {
            label: "Look again now"
            keywords: "health refresh"
            text: Health.busy ? "Looking…" : "Refresh"
            onClicked: Health.refresh()
        }
    }

    SettingsCard {
        title: "Stop watching"
        note: hidden.length === 0 ? "all watched" : hidden.length + " hidden"
        Repeater {
            model: pg.watchIds
            SettingsSwitch {
                required property var modelData
                label: pg.nameOf(modelData)
                sub: pg.hidden.indexOf(modelData) >= 0 ? "Not watched: left out of the pill and the list" : ""
                keywords: "health stop watching hide job " + modelData
                checked: pg.hidden.indexOf(modelData) < 0
                onEdited: on => pg.setHidden(modelData, !on)
            }
        }
        Caption { visible: pg.watchIds.length === 0; text: "No jobs known yet." }
    }
    SettingsCard {
        title: "Worth knowing"
        note: Health.notices.length === 0 ? "nothing right now" : Health.notices.length + " listed"
        SettingsSwitch {
            label: "Software updates"
            sub: "Pending apt and Flatpak updates, from the lists already on disk"
            keywords: "health updates apt flatpak notice"
            checked: pg.kinds.updates !== false
            onEdited: on => pg.setKind("updates", on)
        }
        SettingsSwitch {
            label: "Firmware"
            sub: "Firmware updates fwupd already knows about"
            keywords: "health firmware fwupd notice"
            checked: pg.kinds.firmware !== false
            onEdited: on => pg.setKind("firmware", on)
        }
        SettingsSwitch {
            label: "Low disk space"
            sub: "A real disk with too little room left"
            keywords: "health disk space full notice"
            checked: pg.kinds.disk !== false
            onEdited: on => pg.setKind("disk", on)
        }
        SettingsSwitch {
            label: "Restart needed"
            sub: "After a kernel or library update; said once per boot"
            keywords: "health restart reboot notice"
            checked: pg.kinds.reboot !== false
            onEdited: on => pg.setKind("reboot", on)
        }
        SettingsStepper {
            label: "Nag above"
            sub: "Light the pill when more packages than this are waiting"
            keywords: "health updates nag count"
            from: 0; to: 500; stepSize: 10
            suffix: " packages"
            value: Number(cfg.values.updatesNag)
            onEdited: v => pg.num("updatesNag", v)
        }
        SettingsStepper {
            label: "Package lists too old after"
            keywords: "health apt lists stale days"
            from: 1; to: 90; stepSize: 1
            suffix: " days"
            value: Number(cfg.values.staleListDays)
            onEdited: v => pg.num("staleListDays", v)
        }
        SettingsStepper {
            label: "Low disk below"
            sub: "Percent free"
            keywords: "health disk percent"
            from: 1; to: 50; stepSize: 1
            suffix: " %"
            value: Number(cfg.values.diskPercent)
            onEdited: v => pg.num("diskPercent", v)
        }
        SettingsStepper {
            label: "or below"
            sub: "Gigabytes free"
            keywords: "health disk gigabytes"
            from: 1; to: 200; stepSize: 1
            suffix: " GB"
            value: Number(cfg.values.diskGB)
            onEdited: v => pg.num("diskGB", v)
        }
        SettingsStepper {
            label: "EFI partition below"
            sub: "Megabytes free (/boot/efi is nearly full here)"
            keywords: "health esp efi boot megabytes"
            from: 1; to: 500; stepSize: 5
            suffix: " MB"
            value: Number(cfg.values.espMB)
            onEdited: v => pg.num("espMB", v)
        }
    }
}
