// Wi-Fi networks (NetworkManager). Click one to join it: known and open networks
// connect directly; one that needs a password hands over to wifi-menu, which asks.
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

ColumnLayout {
    id: wifi
    signal done()
    property var nets: []
    property bool busy: false
    spacing: 4

    function scan(rescan) {
        busy = true
        list.command = ["nmcli", "-t", "-f", "IN-USE,SIGNAL,SECURITY,SSID", "dev", "wifi", "list", "--rescan", rescan ? "yes" : "no"]
        list.running = true
    }
    Component.onCompleted: scan(false)

    Process {
        id: list
        stdout: StdioCollector {
            onStreamFinished: {
                const best = {}
                for (const line of text.split("\n")) {
                    // IN-USE:SIGNAL:SECURITY:SSID  (colons inside the SSID are backslash-escaped)
                    const f = line.replace(/\\:/g, "\u0001").split(":")
                    if (f.length < 4) continue
                    const ssid = f.slice(3).join(":").replace(/\u0001/g, ":")
                    if (ssid === "") continue
                    const n = { ssid: ssid, signal: parseInt(f[1]) || 0, secure: f[2] !== "" && f[2] !== "--", active: f[0] === "*" }
                    if (!best[ssid] || n.active || (!best[ssid].active && n.signal > best[ssid].signal)) best[ssid] = n
                }
                wifi.nets = Object.values(best).sort((a, b) => (b.active - a.active) || (b.signal - a.signal)).slice(0, 10)
                wifi.busy = false
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Caption { text: wifi.busy ? "Wi-Fi (scanning…)" : "Wi-Fi" }
        Item { Layout.fillWidth: true }
        Caption {
            text: "Rescan"
            color: rescanTap.containsMouse ? Theme.accent : Theme.faint
            MouseArea { id: rescanTap; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; onClicked: wifi.scan(true) }
        }
    }
    Repeater {
        model: wifi.nets
        MenuRow {
            required property var modelData
            label: modelData.ssid
            detail: (modelData.secure ? "locked  " : "") + modelData.signal + "%"
            current: modelData.active
            onClicked: {
                if (!modelData.active) {
                    const q = "'" + modelData.ssid.replace(/'/g, "'\\''") + "'"
                    Sys.run("nmcli -w 20 dev wifi connect " + q + " || " + Sys.bin + "wifi-menu")
                }
                wifi.done()
            }
        }
    }
    Caption { visible: !wifi.busy && wifi.nets.length === 0; text: "No networks found" }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.line; Layout.topMargin: 4; Layout.bottomMargin: 4 }

    // Share the connected network: a WIFI: QR a phone camera can scan to join.
    property string qrPath: ""
    property int qrStamp: 0
    property string qrPass: ""
    Process {
        id: qrGen
        command: [Sys.bin + "wifi-qr"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n")
                wifi.qrPass = lines.length > 1 ? lines[1] : ""
                wifi.qrPath = lines[0].trim(); wifi.qrStamp++
            }
        }
    }
    MenuRow {
        visible: Sys.netKind === "wifi"
        label: wifi.qrPath === "" ? "Share via QR" : "Hide QR"
        onClicked: { if (wifi.qrPath === "") qrGen.running = true; else { wifi.qrPath = ""; wifi.qrPass = "" } }
    }
    Rectangle {
        visible: wifi.qrPath !== ""
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: 216; implicitHeight: 216
        radius: 8
        color: "white"   // QR needs a light quiet zone in both themes
        Image {
            anchors { fill: parent; margins: 8 }
            source: wifi.qrPath === "" ? "" : "file://" + wifi.qrPath + "?" + wifi.qrStamp
            cache: false
            smooth: false
            fillMode: Image.PreserveAspectFit
        }
    }
    Caption { visible: wifi.qrPath !== ""; Layout.alignment: Qt.AlignHCenter; text: "Scan to join " + Sys.netName }
    TextEdit {   // read-only but selectable, so the password can be copied
        visible: wifi.qrPath !== ""
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: 216
        wrapMode: TextEdit.WrapAnywhere
        horizontalAlignment: TextEdit.AlignHCenter
        readOnly: true
        selectByMouse: true
        text: wifi.qrPass === "" ? "(open network, no password)" : wifi.qrPass
        color: Theme.fg
        font { family: Theme.font; pixelSize: 14 }
    }

    MenuRow { label: "More options…";       onClicked: { Sys.run(Sys.bin + "wifi-menu"); wifi.done() } }
    MenuRow { label: "Connection settings"; onClicked: { Sys.run("nm-connection-editor"); wifi.done() } }
}
