// Nerd Font glyphs for the bar (carried over from the waybar config this bar
// replaced), written as escapes so editors can't mangle them.
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property string playerFirefox: "\uDB80\uDE39"
    readonly property string playerRhythmbox: "\uDB81\uDCC3"
    readonly property string playerDefault: "\uDB80\uDF86"
    readonly property string playing: "\uDB81\uDC0A"
    readonly property string paused: "\uDB80\uDFE4"
    readonly property string awake: "\uDB80\uDD76"
    readonly property string sleepy: "\uDB83\uDFAA"
    readonly property string mic: "\uDB80\uDF6C"
    readonly property string micMuted: "\uDB80\uDF6D"
    readonly property string keyboard: "\uDB80\uDF0C"
    readonly property string lightOn: "\uDB81\uDEE8"      // md lightbulb-on: the GVM lights, last known on
    readonly property string lightOff: "\uDB80\uDF36"     // md lightbulb-outline: off, or not known
    readonly property string volLow: "\uDB81\uDD7F"
    readonly property string volMid: "\uDB81\uDD80"
    readonly property string volHigh: "\uDB81\uDD7E"
    readonly property string volMuted: "\uDB81\uDF5F"
    readonly property string headphones: "\uDB80\uDECB"
    readonly property string wifi: "\uDB81\uDDA9"
    readonly property string wired: "\uDB80\uDE00"
    readonly property string offline: "\uDB81\uDDAA"
    readonly property string batCharging: "\uDB80\uDC84"
    readonly property string batPlugged: "\uDB81\uDEA5"
    readonly property string umbrella: "\uDB81\uDD4A"
    readonly property string flake: "\uDB81\uDF17"
    readonly property string sun: "\uDB81\uDD99"
    readonly property string drop: "\uDB81\uDD8C"
    readonly property string disk: "\uDB80\uDECA"
    readonly property string warn: "\uDB80\uDC26"
    readonly property string envelope: "\uF0E0"
    readonly property string calendar: "\uF073"
    readonly property string terminal: "\uF120"
    readonly property string chat: "\uF075"
    readonly property string leaf: "\uDB80\uDF2A"
    readonly property string bug: "\uF188"
    readonly property string bone: "\uDB80\uDCD1"
    readonly property string paw: "\uf1b0"
    readonly property string fish: "\uDB80\uDE3A"
    readonly property string clock: "\uF017"
    readonly property string bell: "\uDB80\uDC9A"
    readonly property string bellOff: "\uDB80\uDC9B"
    readonly property string power: "\u23FB"
    readonly property var battery: ["\uDB80\uDC7A", "\uDB80\uDC7C", "\uDB80\uDC7E", "\uDB80\uDC80", "\uDB80\uDC79"]
}
