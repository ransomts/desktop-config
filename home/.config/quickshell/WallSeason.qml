// Seasonal touches over the wallpaper (effect "season"): a few things drifting
// across whatever scene is showing, chosen by the date (WallState.seasonKind):
//   leaves     autumn, mid-October to the end of November
//   snow       winter, December to February (a light flurry; real snow is the weather effect)
//   petals     spring, mid-March to the end of April
//   fireflies  summer nights, mid-May to the end of August, after dusk only
// and, on a Clemson football game day (~/.local/bin/gameday), a faint paw print
// in the corner with the opponent and kickoff.
//
// Every position is a plain function of `time`, the wallpaper's own clock: nothing
// here has a timer, so it moves exactly when the wallpaper moves and holds still
// with it (battery, heat guard, a covered screen).
//   qs ipc call wallpaper season leaves|snow|petals|fireflies|none|auto     (try one)
//   qs ipc call wallpaper gameday true|false                                 (try the paw)
import QtQuick

Item {
    id: season
    property real time: 0                   // seconds, from WallState.clock
    property bool dark: true
    readonly property string kind: WallState.seasonKind
    readonly property var game: WallState.gameShown

    // repeatable pseudo-random number in 0..1 for item i, property k
    function rnd(i, k) { const v = Math.sin(i * 127.1 + k * 311.7) * 43758.5453; return v - Math.floor(v) }
    function wrap(v, span) { return ((v % span) + span) % span }

    readonly property var leafInk: ["#f56600", "#c8501e", "#e0a030", "#8c3b1a", "#b5651d"]
    readonly property var petalInk: dark ? ["#e8b7c4", "#f3d3da", "#d99aae"] : ["#c9778f", "#d99aae", "#b8607a"]
    readonly property string leafGlyph: "󰌪"      // nf-md-leaf
    readonly property string flakeGlyph: "󰜗"     // nf-md-snowflake

    // ---- falling things: leaves, snow, petals ----
    Repeater {
        model: season.kind === "leaves" ? 16 : season.kind === "snow" ? 24 : season.kind === "petals" ? 14 : 0
        Item {
            id: bit
            required property int index
            readonly property real fall: season.kind === "snow" ? 14 + season.rnd(index, 1) * 16 : 16 + season.rnd(index, 1) * 26     // px a second
            readonly property real sway: 24 + season.rnd(index, 2) * 46
            readonly property real swing: 0.25 + season.rnd(index, 3) * 0.5
            readonly property real phase: season.rnd(index, 4) * 6.283
            readonly property real px: season.kind === "snow" ? 8 + season.rnd(index, 5) * 8 : 13 + season.rnd(index, 5) * 12
            readonly property real spin: (season.rnd(index, 6) - 0.5) * 50
            x: season.wrap(season.rnd(index, 7) * season.width + Math.sin(season.time * swing + phase) * sway + season.time * 5, season.width + 60) - 30
            y: season.wrap(season.rnd(index, 8) * (season.height + 80) + season.time * fall, season.height + 80) - 40
            rotation: season.kind === "snow" ? season.time * spin * 0.4 : Math.sin(season.time * swing * 1.7 + phase) * 55 + season.time * spin * 0.3
            opacity: (season.dark ? 0.5 : 0.6) + season.rnd(index, 9) * 0.3

            Text {      // leaf or snowflake
                visible: season.kind !== "petals"
                anchors.centerIn: parent
                text: season.kind === "snow" ? season.flakeGlyph : season.leafGlyph
                color: season.kind === "snow" ? (season.dark ? "#e6e1dc" : "#8c8782")
                                              : season.leafInk[bit.index % season.leafInk.length]
                font { family: Theme.font; pixelSize: bit.px }
            }
            Rectangle {     // petal: a small soft oval
                visible: season.kind === "petals"
                anchors.centerIn: parent
                width: bit.px * 0.7; height: bit.px * 0.42; radius: height / 2
                color: season.petalInk[bit.index % season.petalInk.length]
            }
        }
    }

    // ---- fireflies: slow wandering lights that glow and fade ----
    Repeater {
        model: season.kind === "fireflies" ? 14 : 0
        Item {
            id: fly
            required property int index
            readonly property real a: 0.05 + season.rnd(index, 1) * 0.07
            readonly property real b: 0.04 + season.rnd(index, 2) * 0.06
            readonly property real phase: season.rnd(index, 3) * 6.283
            readonly property real blink: 0.5 + season.rnd(index, 4) * 0.6
            readonly property real glow: Math.pow(Math.max(0, Math.sin(season.time * blink + phase)), 2)
            // the lower two thirds of the screen, where a field would be
            x: (0.5 + 0.46 * Math.sin(season.time * a + phase) * Math.cos(season.time * b * 0.7 + index)) * season.width
            y: (0.62 + 0.3 * Math.sin(season.time * b + phase * 2) * Math.cos(season.time * a * 0.6 + index * 2)) * season.height
            opacity: glow * 0.9
            Rectangle { anchors.centerIn: parent; width: 18; height: 18; radius: 9; color: "#e9f27a"; opacity: 0.12 }
            Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "#e9f27a"; opacity: 0.3 }
            Rectangle { anchors.centerIn: parent; width: 3; height: 3; radius: 1.5; color: "#f8ffc0" }
        }
    }

    // ---- game day ----
    Item {
        visible: season.game !== null
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 70; bottomMargin: 90 }
        width: 240; height: 250
        Image {             // the official Tiger Paw (Clemson's own logo file), already tilted to one o'clock
            id: paw
            anchors.horizontalCenter: parent.horizontalCenter
            y: 8
            width: 190; height: 190
            source: Qt.resolvedUrl("assets/tiger-paw.png")
            sourceSize: Qt.size(380, 380)
            fillMode: Image.PreserveAspectFit
            opacity: season.dark ? 0.16 : 0.22
        }
        Text {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            horizontalAlignment: Text.AlignHCenter
            text: season.game ? "Game day\n" + (season.game.home ? season.game.opponent + " at Clemson" : "Clemson at " + season.game.opponent)
                                + (season.game.time ? "  " + season.game.time : "") : ""
            color: Theme.fg
            opacity: 0.55
            font { family: Theme.font; pixelSize: 13 }
        }
    }
}
