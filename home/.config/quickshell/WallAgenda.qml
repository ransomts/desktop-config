// The day as a thin band along the bottom of the wallpaper: it fills as the day passes,
// today's calendar events (Sys.today, from ~/.local/bin/agenda-day) sit on it as soft
// blocks, and pointing at one shows its time, title and place. Left-click joins the
// meeting when the event has an online link (else opens its Org entry in Emacs);
// right-click always opens the Org entry. Events that overlap (in time, or
// on screen once a short one is widened to its minimum) stack into lanes above the track.
import QtQuick
import Quickshell

Item {
    id: band
    implicitHeight: 26 + (laneCount - 1) * lanePitch
    readonly property int lanePitch: 10
    function mins(hm) { const p = hm.split(":"); return parseInt(p[0]) * 60 + parseInt(p[1]) }
    readonly property var events: Sys.today.filter(e => !e.allday && e.start && e.end)
    readonly property int from: Math.min(8 * 60, events.length ? mins(events[0].start) - 30 : 8 * 60)
    readonly property int to: Math.max(18 * 60, events.length ? Math.max.apply(null, events.map(e => mins(e.end))) + 30 : 18 * 60)
    readonly property int nowMin: mins(Sys.nowHM)
    function xOf(m) { return Math.max(0, Math.min(1, (m - from) / (to - from))) * width }
    readonly property bool inDay: nowMin >= from && nowMin <= to
    function evLeft(e) { return xOf(mins(e.start)) }
    function evRight(e) { const l = evLeft(e); return l + Math.max(6, xOf(mins(e.end)) - l - 2) }
    // greedy interval packing: each event, earliest first, takes the lowest lane it fits in
    readonly property var lanes: {
        const order = events.map((e, i) => i).sort((i, j) => mins(events[i].start) - mins(events[j].start))
        const ends = [], out = []
        for (const i of order) {
            const l = evLeft(events[i])
            let k = ends.findIndex(r => r + 2 <= l)
            if (k < 0) { k = ends.length; ends.push(0) }
            ends[k] = evRight(events[i]); out[i] = k
        }
        return out
    }
    // clicks go out through Sys.launch (argv, no shell), so the test stand-in can record them
    function join(e) { Sys.launch(["xdg-open", e.url]) }
    function openEntry(e) { Sys.launch([Sys.bin + "agenda-open", e.date || "", e.start, e.title, e.id || ""]) }
    function act(e, button) { if (button === Qt.LeftButton && e.url) join(e); else openEntry(e) }
    readonly property int laneCount: Math.max(1, ...lanes.map(k => k + 1))

    Rectangle {                                   // the day
        id: track
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 2; radius: 1
        color: Qt.rgba(1, 1, 1, 0.14)
    }
    Rectangle {                                   // the part of it that has passed
        anchors { left: track.left; bottom: track.bottom }
        height: 2; radius: 1
        width: band.xOf(band.nowMin)
        color: Theme.accentBg; opacity: 0.75
    }
    Repeater {
        model: band.events
        // Each event is a hit area as tall as its lane (so stacked lanes tile with no dead
        // gap between them) and 1 px wider than its block on each side (filling the 2 px gap
        // left between neighbours); the visible block sits inside it.
        Item {
            id: ev
            required property var modelData
            required property int index
            readonly property int a: band.mins(modelData.start)
            readonly property int b: band.mins(modelData.end)
            readonly property int lane: band.lanes[index] || 0
            readonly property bool current: band.nowMin >= a && band.nowMin < b
            readonly property bool past: band.nowMin >= b
            readonly property bool hovered: h.hovered
            readonly property string place: (modelData.location || "").replace(/https?:\/\/\S+/g, "").replace(/[\s:]+$/, "")
            readonly property string tipText: tip.text
            x: band.xOf(a) - 1
            width: block.width + 2
            height: band.lanePitch
            anchors.bottom: parent.bottom; anchors.bottomMargin: -4 + lane * band.lanePitch
            z: hovered ? 5 : 0                    // lift the hovered event so its tip clears other lanes
            Rectangle {
                id: block
                x: 1; anchors.verticalCenter: parent.verticalCenter
                width: Math.max(6, band.xOf(ev.b) - band.xOf(ev.a) - 2)
                height: 8; radius: 4
                color: ev.current ? Theme.accentBg : Qt.rgba(1, 1, 1, ev.past ? 0.16 : 0.42)
            }
            HoverHandler { id: h; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onTapped: (pt, button) => band.act(ev.modelData, button)
            }
            Rectangle {
                id: tipBox
                objectName: "tip"
                visible: ev.hovered
                // centred over the block, but slid sideways to stay inside the band
                x: Math.max(-ev.x, Math.min(band.width - ev.x - width, (ev.width - width) / 2))
                anchors { bottom: parent.top; bottomMargin: 5 }
                width: Math.min(tip.implicitWidth + 16, band.width); height: tip.implicitHeight + 8; radius: 8
                color: Theme.solidBg; border.color: Theme.line
                Text {
                    id: tip; anchors.centerIn: parent
                    width: Math.min(implicitWidth, band.width - 16); elide: Text.ElideRight
                    text: ev.modelData.start + "–" + ev.modelData.end + "  " + ev.modelData.title
                          + (ev.place ? "  · " + ev.place : "") + (ev.modelData.url ? "  ↗ join" : "")
                    color: Theme.fg; font.family: Theme.font; font.pixelSize: 12
                }
            }
        }
    }
    Rectangle {                                   // now
        visible: band.inDay
        x: band.xOf(band.nowMin) - 3; width: 6; height: 6; radius: 3
        anchors.bottom: parent.bottom; anchors.bottomMargin: -2
        color: Theme.accentBg
    }
}
