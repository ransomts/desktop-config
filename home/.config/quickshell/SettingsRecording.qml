// Settings > Recording and camera: screen-record's remembered choice ($XDG_STATE_HOME/screen-record.json,
// mic / system / cam; the plain record keys reuse it) through JsonFile (its "last" key is kept), and
// the webcam bubble (CamState.cfg: size, device; shown).
import QtQuick
import QtQuick.Layouts
import Quickshell

SettingsPage {
    id: pg
    pageId: "recording"
    title: "Recording and camera"
    JsonFile {
        id: rec
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/screen-record.json"
        defaults: ({ mic: false, system: false, cam: false })
        watch: pg.shown
    }
    readonly property alias file: rec

    SettingsCard {
        title: "Screen recording"
        note: "Super+R region · Super+Shift+R screen · Super+Ctrl+R pick"
        SettingsSwitch {
            label: "Microphone"
            keywords: "record mic sound audio"
            checked: rec.values.mic === true
            onEdited: on => rec.set("mic", on)
        }
        SettingsSwitch {
            label: "What the speakers play"
            keywords: "record system audio sound"
            checked: rec.values.system === true
            onEdited: on => rec.set("system", on)
        }
        SettingsSwitch {
            label: "Webcam bubble while recording"
            keywords: "record cam camera"
            checked: rec.values.cam === true
            onEdited: on => rec.set("cam", on)
        }
    }
    SettingsCard {
        title: "Webcam bubble"
        note: CamState.error !== "" ? CamState.error : CamState.shown ? "camera on" : ""
        SettingsSwitch {
            label: "Show the bubble"
            sub: "The camera runs only while it shows"
            keywords: "webcam camera cam bubble"
            checked: CamState.shown
            onEdited: on => { if (on) CamState.on(); else CamState.off() }
        }
        SettingsSlider {
            label: "Size"
            sub: "Scrolling on the bubble changes it too"
            keywords: "webcam bubble diameter"
            from: CamState.minSize; to: CamState.maxSize; stepSize: 10
            value: CamState.cfg.size
            text: CamState.cfg.size + " px"
            onEdited: v => CamState.setSize(v)
        }
        SettingsChoice {
            label: "Camera"
            sub: "Also Super+Ctrl+Shift+W, or right-click the bubble (middle-click: the next one)"
            keywords: "webcam device video4linux camera choose pick"
            below: true
            options: CamState.cameras.length ? CamState.cameras.map(c => [c.path, c.name]) : [[CamState.cfg.device, "No camera found"]]
            value: CamState.camIndex >= 0 ? CamState.cameras[CamState.camIndex].path : CamState.cfg.device
            onEdited: v => { if (CamState.cameras.length) { if (CamState.shown) CamState.use(v); else CamState.cfg.device = v } }
            Component.onCompleted: CamState.scan()
        }
    }
}
