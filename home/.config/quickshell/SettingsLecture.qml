// Settings > Lecture tools: the live values in Lecture.qml. None of them are saved by Lecture
// (a shell reload goes back to its defaults), which the page says.
import QtQuick
import QtQuick.Layouts

SettingsPage {
    id: pg
    pageId: "lecture"
    title: "Lecture tools"
    intro: "These hold until the shell reloads. The lecture menu is Super+Z."

    SettingsCard {
        title: "Spotlight"
        SettingsSlider {
            label: "Spotlight size"
            sub: "Radius of the lit circle"
            keywords: "lecture spot radius"
            from: 40; to: 800; stepSize: 10
            value: Lecture.spotRadius
            text: Lecture.spotRadius + " px"
            onEdited: v => Lecture.setSpotSize(v)
        }
    }
    SettingsCard {
        title: "Ink"
        SettingsChoice {
            label: "Tool"
            keywords: "lecture draw pen marker arrow"
            below: true
            options: Lecture.tools.map(t => [t, t.charAt(0).toUpperCase() + t.slice(1)])
            value: Lecture.tool
            onEdited: v => Lecture.setTool(v)
        }
        SettingsChoice {
            label: "Colour"
            keywords: "lecture draw ink colour color"
            options: Lecture.colorNames.map((c, i) => [i, c])
            value: Lecture.colorIndex
            onEdited: v => Lecture.colorIndex = v
        }
        SettingsChoice {
            label: "Line width"
            keywords: "lecture draw weight thickness"
            options: Lecture.weights.map((w, i) => [i, String(w)])
            value: Lecture.weightIndex
            onEdited: v => Lecture.weightIndex = v
        }
    }
    SettingsCard {
        title: "On screen"
        SettingsSwitch {
            label: "Show keys pressed"
            sub: Lecture.keysProblem !== "" ? Lecture.keysProblem : "For the audience; nothing is recorded"
            keywords: "lecture keys keystrokes display"
            checked: Lecture.keysOn
            onEdited: on => { if (on !== Lecture.keysOn) Lecture.toggleKeys() }
        }
        SettingsInfo {
            label: "Zoom"
            keywords: "lecture magnify"
            value: Lecture.zoomFactor + "×  (Super+Z menu, or lecture zoomin / zoomout)"
        }
    }
}
