// Dashboard (Super+I): one full-screen glance at the day. Clock and what is on
// now, weather, today's and tomorrow's events, unread mail, what is playing,
// the machine's state and the latest notifications. Escape, Q or a click on the
// backdrop closes it; Space plays / pauses.
//
// Nothing here runs while it is closed. Open, it asks ~/.local/bin/dashboard-data
// for the machine's state every 2 s and for the feeds (weather, mail, tomorrow)
// at once and then every 5 minutes. Mail senders and subjects are left out while
// Do Not Disturb is on (presenting, screen sharing): only the counts show.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower

PanelWindow {
    id: dash
    visible: false
    function toggle() { visible = !visible }
    // peek: show it without taking the keyboard (for a look or a screenshot from a script)
    property bool grab: true
    function peek() { grab = false; visible = true }

    property var sysState: ({})             // dashboard-data sys
    property var feeds: ({})                // dashboard-data feeds
    readonly property var wx: feeds.weather || ({})
    readonly property var mail: feeds.mail || ({ boxes: [], latest: [] })
    readonly property var tomorrow: feeds.tomorrow || ({ name: "Tomorrow", events: [] })
    readonly property bool wide: width >= 1340      // three columns side by side; else one stack (portrait screen)
    readonly property real colW: wide ? 420 : Math.min(width - 64, 560)

    onVisibleChanged: if (!visible) grab = true; else {
        clock.now = new Date()
        if (!sysProc.running) sysProc.running = true
        if (!feedProc.running) feedProc.running = true
        Sys.readBrightness()
        keys.forceActiveFocus()
    }

    Process {
        id: sysProc
        command: Sys.clean.concat([Sys.bin + "dashboard-data", "sys"])
        stdout: StdioCollector { onStreamFinished: { try { dash.sysState = JSON.parse(text) } catch (e) {} } }
    }
    Process {
        id: feedProc
        command: Sys.clean.concat([Sys.bin + "dashboard-data", "feeds"])
        stdout: StdioCollector { onStreamFinished: { try { dash.feeds = JSON.parse(text) } catch (e) {} } }
    }
    Timer { interval: 2000; running: dash.visible; repeat: true; onTriggered: if (!sysProc.running) sysProc.running = true }
    Timer { interval: 300000; running: dash.visible; repeat: true; onTriggered: if (!feedProc.running) feedProc.running = true }
    Timer {
        id: clock
        property date now: new Date()
        interval: 1000; running: dash.visible; repeat: true
        onTriggered: now = new Date()
    }

    screen: {
        const m = Hyprland.focusedMonitor
        return Quickshell.screens.find(s => m && s.name === m.name) || Quickshell.screens[0]
    }
    color: Theme.dark ? Qt.rgba(0, 0, 0, 0.55) : Qt.rgba(1, 1, 1, 0.45)   // dims and (with the blur rule) frosts the screen behind
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-dashboard"     // blurred by a layer rule in hyprland.lua
    WlrLayershell.keyboardFocus: grab ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    MouseArea { anchors.fill: parent; onClicked: dash.visible = false }
    Item {
        id: keys
        focus: true
        Keys.onEscapePressed: dash.visible = false
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Q) { dash.visible = false; event.accepted = true }
            else if (event.key === Qt.Key_Space && Sys.player && Sys.player.canTogglePlaying) { Sys.player.togglePlaying(); event.accepted = true }
        }
    }

    // ---- pieces ----
    component Card: Rectangle {
        id: cardRoot
        property string title: ""
        property string note: ""                // small text at the right of the title
        default property alias content: body.data
        Layout.fillWidth: true
        implicitHeight: col.implicitHeight + 32
        radius: 16
        color: Theme.panelBg
        border.width: 1
        border.color: Theme.line
        MouseArea { anchors.fill: parent }      // a click on a card is not a click on the backdrop
        ColumnLayout {
            id: col
            anchors { fill: parent; margins: 16 }
            spacing: 10
            RowLayout {
                visible: cardRoot.title !== ""
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: cardRoot.title.toUpperCase()
                    color: Theme.accent
                    font { family: Theme.font; pixelSize: 11; bold: true; letterSpacing: 1.5 }
                }
                Caption { text: cardRoot.note }
            }
            ColumnLayout { id: body; Layout.fillWidth: true; spacing: 8 }
        }
    }

    component Meter: ColumnLayout {
        id: meter
        property string label: ""
        property string value: ""
        property real level: 0                  // 0..1
        property bool alarm: false
        Layout.fillWidth: true
        spacing: 3
        RowLayout {
            Layout.fillWidth: true
            Caption { Layout.fillWidth: true; text: meter.label }
            Caption { color: meter.alarm ? Theme.warn : Theme.fg; text: meter.value }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 6
            radius: 3
            color: Theme.track
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, meter.level))
                height: parent.height
                radius: 3
                color: meter.alarm ? Theme.warn : Theme.accentBg
                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            }
        }
    }

    component EventRow: RowLayout {
        id: ev
        property var event: ({})
        property bool today: true
        readonly property bool past: today && !event.allday && event.end <= Sys.nowHM
        readonly property bool current: today && !event.allday && event.start <= Sys.nowHM && event.end > Sys.nowHM
        Layout.fillWidth: true
        spacing: 10
        Rectangle {
            implicitWidth: 3; implicitHeight: 18; radius: 2
            color: ev.current ? Theme.accentBg : ev.past ? "transparent" : Theme.line
        }
        Text {
            Layout.preferredWidth: 92
            text: ev.event.allday ? "all day" : ev.event.start + "-" + ev.event.end
            color: ev.current ? Theme.accent : ev.past ? Theme.dim : Theme.faint
            font { family: Theme.font; pixelSize: 12 }
        }
        Text {
            Layout.fillWidth: true
            text: ev.event.title || ""
            elide: Text.ElideRight
            color: ev.past ? Theme.dim : Theme.fg
            font { family: Theme.font; pixelSize: 13; bold: ev.current }
        }
    }

    // ---- the page ----
    Flickable {
        id: flick
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, page.implicitWidth)
        height: Math.min(parent.height - 48, page.implicitHeight)
        contentWidth: page.implicitWidth
        contentHeight: page.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        GridLayout {
            id: page
            columns: dash.wide ? 3 : 1
            columnSpacing: 20
            rowSpacing: 20

            // ---------- column 1: clock, weather, music ----------
            ColumnLayout {
                Layout.preferredWidth: dash.colW
                Layout.maximumWidth: dash.colW
                Layout.alignment: Qt.AlignTop
                spacing: 20

                Card {
                    Caption {
                        readonly property int h: clock.now.getHours()
                        text: h < 5 ? "Up late" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
                    }
                    Text {
                        text: Qt.formatDateTime(clock.now, "HH:mm")
                        color: Theme.accent
                        font { family: Theme.font; pixelSize: 76; bold: true }
                        Layout.topMargin: -10
                        Layout.bottomMargin: -8
                    }
                    Text {
                        text: Qt.formatDateTime(clock.now, "dddd, MMMM d")
                        color: Theme.fg
                        font { family: Theme.font; pixelSize: 16 }
                    }
                    Caption {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        elide: Text.ElideRight
                        text: Sys.currentEvent ? "Now: " + Sys.currentEvent.title + " (until " + Sys.currentEvent.end + ")"
                            : Sys.nextEvent ? "Next: " + Sys.nextEvent.start + "  " + Sys.nextEvent.title
                            : "Nothing else on the calendar today"
                    }
                }

                Card {
                    title: "Weather"
                    note: dash.wx.stale ? "offline, last known" : "Clemson"
                    Caption { visible: dash.wx.ok !== true; text: dash.feeds.weather === undefined ? "Loading..." : "No weather (offline?)" }
                    RowLayout {
                        visible: dash.wx.ok === true
                        Layout.fillWidth: true
                        spacing: 16
                        Text {
                            text: dash.wx.glyph || ""
                            color: Theme.accent
                            font { family: Theme.font; pixelSize: 52 }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                text: (dash.wx.temp === undefined ? "" : dash.wx.temp + "°") + "  " + (dash.wx.words || "")
                                color: Theme.fg
                                font { family: Theme.font; pixelSize: 24; bold: true }
                            }
                            Caption { text: "Feels " + dash.wx.feels + "°   Wind " + dash.wx.wind + " mph   Humidity " + dash.wx.humidity + "%" }
                            Caption { text: "Sun " + dash.wx.sunrise + " to " + dash.wx.sunset }
                        }
                    }
                    RowLayout {
                        visible: dash.wx.ok === true
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 8
                        Repeater {
                            model: dash.wx.days || []
                            Rectangle {
                                id: day
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: dayCol.implicitHeight + 16
                                radius: 10
                                color: Theme.track
                                ColumnLayout {
                                    id: dayCol
                                    anchors.centerIn: parent
                                    spacing: 2
                                    Caption { Layout.alignment: Qt.AlignHCenter; text: day.modelData.name }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: day.modelData.glyph
                                        color: Theme.fg
                                        font { family: Theme.font; pixelSize: 22 }
                                    }
                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: day.modelData.hi + "° " + day.modelData.lo + "°"
                                        color: Theme.fg
                                        font { family: Theme.font; pixelSize: 12 }
                                    }
                                    Caption {
                                        Layout.alignment: Qt.AlignHCenter
                                        color: day.modelData.rain >= 50 ? Theme.accent : Theme.faint
                                        text: day.modelData.rain + "% rain"
                                        font.pixelSize: 10
                                    }
                                }
                            }
                        }
                    }
                }

                Card {      // the bar pet (Pet.qml): how it is, and the three things it likes
                    title: Pet.name
                    note: "bond " + Pet.hearts
                    visible: Pet.enabled
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14
                        Item {
                            // The pet itself, four times life size. It answers the three buttons here too
                            // (the one on the bar is hidden under this overlay): a hop and a heart when
                            // patted, eating when fed, a pounce after a ball when played with. Stepped by
                            // one timer that only runs for the second or two an answer lasts.
                            id: petShow
                            implicitWidth: 96; implicitHeight: 76
                            readonly property bool asleep: Pet.mood === "asleep"
                            property int frame: asleep ? 5 : 4           // sprite sheet frames: 0 stand, 4 sit, 5 asleep, 9 pounce, 10 eat, 11 tail
                            property real lift: 0                        // px off the ground
                            property string bubble: ""
                            property real ballX: -1                      // < 0: no ball
                            property var steps: []                       // [{ f, y, b, ball }], one every 130 ms
                            property int at: 0
                            function act(list) { steps = list; at = 0; stepper.restart(); step() }
                            function step() {
                                if (at >= steps.length) { stepper.stop(); frame = Qt.binding(() => petShow.asleep ? 5 : 4); lift = 0; bubble = ""; ballX = -1; return }
                                const s = steps[at++]
                                frame = s.f; lift = s.y || 0; bubble = s.b || ""; ballX = s.ball === undefined ? -1 : s.ball
                            }
                            Timer { id: stepper; interval: 130; repeat: true; onTriggered: petShow.step() }
                            Connections {
                                target: Pet
                                enabled: dash.visible
                                function onPat(who) {
                                    const h = "♥"
                                    petShow.act([{ f: 0, y: 0, b: h }, { f: 0, y: 7, b: h }, { f: 11, y: 10, b: h }, { f: 0, y: 5, b: h }, { f: 0, y: 0, b: h },
                                                 { f: 11, y: 6, b: h }, { f: 11, y: 8, b: h }, { f: 0, y: 3, b: h }, { f: 4, y: 0, b: h }, { f: 1, y: 0, b: h }, { f: 4, y: 0, b: h }])
                                }
                                function onFeed() {
                                    const food = Pet.animal === "dog" || Pet.animal === "fox" ? Icons.bone : Pet.animal === "cat" ? Icons.fish : Pet.animal === "frog" || Pet.animal === "bird" ? Icons.bug : Icons.leaf
                                    const l = [{ f: 0, b: food }, { f: 0, b: food }]
                                    for (let i = 0; i < 5; i++) l.push({ f: 10, b: i < 3 ? food : "" }, { f: 4, b: i < 3 ? food : "" })
                                    l.push({ f: 4, b: "♥" }, { f: 1, b: "♥" }, { f: 4, b: "♥" })
                                    petShow.act(l)
                                }
                                function onPlay() {
                                    const l = []
                                    for (let i = 0; i < 6; i++) l.push({ f: i % 2 ? 11 : 0, ball: 84 - i * 9 })              // the ball rolls in, tail going
                                    l.push({ f: 9, y: 6, ball: 34 }, { f: 9, y: 12, ball: 40 }, { f: 9, y: 6, ball: 50 }, { f: 4, ball: 62 },
                                           { f: 9, y: 8, ball: 70 }, { f: 9, y: 10, ball: 80 }, { f: 0, ball: 92 }, { f: 11 }, { f: 0, b: "♪" }, { f: 4, b: "♪" })
                                    petShow.act(l)
                                }
                            }
                            Item {
                                x: 0; y: 12 - petShow.lift
                                width: 64; height: 64
                                clip: true
                                Image {
                                    readonly property bool fitOk: true     // a sprite sheet: cut to one frame on purpose (Fit.qml)
                                    x: -petShow.frame * 64
                                    width: sourceSize.width * 4; height: 64
                                    smooth: false; cache: false
                                    source: Qt.resolvedUrl("assets/pet-" + Pet.animal + "-" + Pet.coat + ".png")
                                }
                            }
                            Text {
                                x: 60; y: 0
                                visible: petShow.bubble !== ""
                                text: petShow.bubble
                                color: petShow.bubble === "♥" ? Theme.red : Theme.accent
                                font { family: Theme.font; pixelSize: 16 }
                            }
                            Rectangle {
                                visible: petShow.ballX >= 0
                                x: petShow.ballX; y: 66
                                width: 9; height: 9; radius: 4.5
                                color: Theme.accentBg; border.width: 1; border.color: Theme.altInk
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Caption { Layout.fillWidth: true; wrapMode: Text.Wrap; text: Pet.name + " is " + Pet.doing }
                            Caption { Layout.fillWidth: true; wrapMode: Text.Wrap; text: PetArc.summary }     // days together, the diary's last line
                            Row {
                                spacing: 6
                                Repeater {
                                    model: [{ label: "Pet", act: "pat" }, { label: Pet.hungry ? "Feed (peckish)" : "Feed", act: "feed" }, { label: "Play", act: "play" }]
                                    Rectangle {
                                        id: petBtn
                                        required property var modelData
                                        width: petBtnText.implicitWidth + 22; height: 24; radius: 7
                                        color: petBtnTap.containsMouse ? Theme.hover : Theme.track
                                        Text {
                                            id: petBtnText
                                            anchors.centerIn: parent
                                            text: petBtn.modelData.label
                                            color: Theme.fg
                                            font { family: Theme.font; pixelSize: 11 }
                                        }
                                        MouseArea {
                                            id: petBtnTap
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: {
                                                if (petBtn.modelData.act === "pat") Pet.petIt()
                                                else if (petBtn.modelData.act === "feed") Pet.giveFood()
                                                else Pet.playWith()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Card {
                    title: "Playing"
                    visible: Sys.player !== null && (Sys.player.trackTitle || "") !== ""
                    MediaCard { Layout.fillWidth: true }
                }
            }

            // ---------- column 2: today and tomorrow ----------
            ColumnLayout {
                Layout.preferredWidth: dash.colW
                Layout.maximumWidth: dash.colW
                Layout.alignment: Qt.AlignTop
                spacing: 20

                Card {
                    id: todayCard
                    title: "Today"
                    readonly property var rest: Sys.today.filter(e => e.allday || e.end > Sys.nowHM)
                    readonly property int cap: 11
                    // when the list is long, drop what is already over
                    readonly property var shownEvents: Sys.today.length <= cap ? Sys.today : rest.slice(0, cap)
                    note: Sys.today.length === 0 ? "" : rest.length === 0 ? "all done" : rest.length + " of " + Sys.today.length + " left"
                    Caption { visible: Sys.today.length === 0; text: "Nothing on the calendar" }
                    Repeater {
                        model: todayCard.shownEvents
                        EventRow { required property var modelData; event: modelData }
                    }
                    Caption {
                        visible: todayCard.rest.length > todayCard.cap && Sys.today.length > todayCard.cap
                        text: "and " + (todayCard.rest.length - todayCard.cap) + " more"
                    }
                }

                Card {
                    id: tomorrowCard
                    title: dash.tomorrow.name || "Tomorrow"
                    readonly property var events: dash.tomorrow.events || []
                    readonly property int cap: 7
                    note: events.length === 0 ? "" : events.length + (events.length === 1 ? " event" : " events")
                    Caption { visible: tomorrowCard.events.length === 0; text: dash.feeds.tomorrow === undefined ? "Loading..." : "Nothing on the calendar" }
                    Repeater {
                        model: tomorrowCard.events.slice(0, tomorrowCard.cap)
                        EventRow { required property var modelData; event: modelData; today: false }
                    }
                    Caption {
                        visible: tomorrowCard.events.length > tomorrowCard.cap
                        text: "and " + (tomorrowCard.events.length - tomorrowCard.cap) + " more"
                    }
                }
            }

            // ---------- column 3: mail, machine, notifications ----------
            ColumnLayout {
                Layout.preferredWidth: dash.colW
                Layout.maximumWidth: dash.colW
                Layout.alignment: Qt.AlignTop
                spacing: 20

                Card {
                    id: mailCard
                    title: "Unread mail"
                    readonly property bool hush: Notif.dnd
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Caption { visible: dash.mail.boxes.length === 0; text: dash.feeds.mail === undefined ? "Loading..." : "No mail index" }
                        Repeater {
                            model: dash.mail.boxes
                            Rectangle {
                                id: box
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: 54
                                radius: 10
                                color: Theme.track
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 10
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: box.modelData.unread
                                        color: box.modelData.unread > 0 ? Theme.accent : Theme.faint
                                        font { family: Theme.font; pixelSize: 26; bold: true }
                                    }
                                    Caption { anchors.verticalCenter: parent.verticalCenter; text: box.modelData.name }
                                }
                            }
                        }
                    }
                    Caption { visible: mailCard.hush && dash.mail.latest.length > 0; text: "Senders and subjects hidden while Do Not Disturb is on" }
                    Repeater {
                        model: mailCard.hush ? [] : dash.mail.latest.filter(m => m.box === "Clemson").slice(0, 4)
                                                      .concat(dash.mail.latest.filter(m => m.box !== "Clemson").slice(0, 2))
                        ColumnLayout {
                            id: msg
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 0
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    Layout.fillWidth: true
                                    text: msg.modelData.from
                                    elide: Text.ElideRight
                                    color: Theme.fg
                                    font { family: Theme.font; pixelSize: 12; bold: true }
                                }
                                Caption { text: msg.modelData.box; font.pixelSize: 10 }
                            }
                            Caption { Layout.fillWidth: true; elide: Text.ElideRight; text: msg.modelData.subject }
                        }
                    }
                }

                Card {
                    title: "Machine"
                    note: dash.sysState.uptime ? "up " + dash.sysState.uptime + "   load " + dash.sysState.load : ""
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 16
                        rowSpacing: 10
                        Meter {
                            label: "CPU"
                            level: dash.sysState.cpu || 0
                            value: Math.round((dash.sysState.cpu || 0) * 100) + "%"
                        }
                        Meter {
                            label: "Temperature"
                            level: ((dash.sysState.temp || 0) - 30) / 65
                            alarm: (dash.sysState.temp || 0) >= 85
                            value: (dash.sysState.temp || 0) + " °C"
                        }
                        Meter {
                            label: "Memory"
                            level: dash.sysState.mem || 0
                            alarm: (dash.sysState.mem || 0) > 0.9
                            value: (dash.sysState.mem_gb || 0) + " / " + (dash.sysState.mem_total_gb || 0) + " GB"
                        }
                        Meter {
                            readonly property var bat: UPower.displayDevice
                            label: "Battery" + (bat.state === UPowerDeviceState.Charging ? " (charging)" : UPower.onBattery ? "" : " (plugged in)")
                            level: bat.percentage
                            alarm: UPower.onBattery && bat.percentage < 0.15
                            value: Math.round(bat.percentage * 100) + "%"
                        }
                        Repeater {
                            model: dash.sysState.disks || []
                            Meter {
                                required property var modelData
                                label: modelData.name + " disk"
                                level: modelData.used
                                alarm: modelData.used > 0.92
                                value: modelData.free_gb + " GB free"
                            }
                        }
                    }
                    Caption {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: (Sys.netKind === "offline" ? "Offline" : (Sys.netKind === "wifi" ? "Wi-Fi " : "Wired ") + Sys.netName)
                            + "   Desktop " + Sys.desktop + (Notif.dnd ? "   Do Not Disturb" : "")
                    }
                }

                Card {
                    title: "Notifications"
                    visible: Notif.history.length > 0
                    note: Notif.history.length + " recent"
                    Repeater {
                        model: Notif.history.slice(0, 3)
                        ColumnLayout {
                            id: old
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 0
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    Layout.fillWidth: true
                                    text: (old.modelData.summary || old.modelData.app || "") + (old.modelData.repeat > 1 ? "  ×" + old.modelData.repeat : "")
                                    elide: Text.ElideRight
                                    textFormat: Text.PlainText
                                    color: old.modelData.critical ? Theme.red : Theme.fg
                                    font { family: Theme.font; pixelSize: 12; bold: true }
                                }
                                Caption { text: old.modelData.time || ""; font.pixelSize: 10 }
                            }
                            Caption {
                                Layout.fillWidth: true
                                visible: (old.modelData.body || "") !== ""
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                textFormat: Text.PlainText
                                text: (old.modelData.body || "").replace(/\s+/g, " ")
                            }
                        }
                    }
                }
            }
        }
    }
}
