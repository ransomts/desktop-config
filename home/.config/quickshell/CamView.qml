// What the webcam bubble window (CamBubble.qml) holds: a screen-sized, see-through Item with the
// round, mirrored camera picture in it. Drag the bubble to move it, scroll on it to resize it,
// middle-click for the next camera, right-click to choose the camera or hide it (`cams pick`). Its place is remembered per screen (CamState).
// The picture: the latest frame ffmpeg wrote (CamState.frameFile), loaded by the Canvas itself
// at 15 Hz (a new ?N on the URL each time; at most 3 loads in flight; the newest loaded one is
// drawn and every older one unloaded, so nothing piles up) and painted clipped to a circle.
// Canvas, not a shader mask, so it looks the same in the offscreen test renderer. (Canvas
// drawImage(ImageItem) looks the item's URL up in the Canvas's own cache, which never holds a
// fresh URL, so Image items cannot feed it.) Nothing runs while the bubble is hidden.
import QtQuick

Item {
    id: view
    property string screenName: CamState.screenName
    readonly property int size: CamState.cfg.size
    readonly property alias bubble: bubble
    readonly property bool live: CamState.shown && visible && CamState.error === ""
    property int frames: 0                  // frames drawn since shown (tests read it)
    property string current: ""             // URL of the frame on show
    property var pending: []                // URLs asked for, oldest first
    property int tick: 0
    function dropFrames() {
        for (const u of pending) canvas.unloadImage(u)
        if (current !== "") canvas.unloadImage(current)
        pending = []; current = ""; frames = 0
        canvas.requestPaint()
    }

    function clampX(x) { return Math.max(0, Math.min(width - size, x)) }
    function clampY(y) { return Math.max(0, Math.min(height - size, y)) }
    // put the bubble where it was on this screen, else in the bottom-right corner
    function place() {
        if (width <= 0 || height <= 0) return
        const p = CamState.posFor(screenName)
        if (p) {
            bubble.x = clampX(p[0] * width - size / 2)
            bubble.y = clampY(p[1] * height - size / 2)
        } else {
            bubble.x = clampX(width - size - 32)
            bubble.y = clampY(height - size - 32)
        }
    }
    function remember() {
        if (width > 0 && height > 0 && screenName !== "")
            CamState.savePos(screenName, (bubble.x + size / 2) / width, (bubble.y + size / 2) / height)
    }
    // a new size (scroll here, or `cam size PX`) keeps the bubble's centre where it was
    property int lastSize: size
    onSizeChanged: {
        bubble.x = clampX(bubble.x + (lastSize - size) / 2)
        bubble.y = clampY(bubble.y + (lastSize - size) / 2)
        lastSize = size
    }
    function resize(px) { CamState.setSize(px); remember() }
    onWidthChanged: place()
    onHeightChanged: place()
    onScreenNameChanged: place()
    onLiveChanged: if (!live) dropFrames(); else place()

    Timer {
        interval: Math.round(1000 / CamState.fps)
        running: view.live
        repeat: true
        onTriggered: {
            // forget loads that failed (no frame written yet)
            const keep = view.pending.filter(u => !canvas.isImageError(u))
            for (const u of view.pending) if (canvas.isImageError(u)) canvas.unloadImage(u)
            if (keep.length >= 3) { view.pending = keep; return }       // loading is behind: skip a frame
            view.tick++
            const url = "file://" + CamState.frameFile + "?" + view.tick
            view.pending = keep.concat([url])
            canvas.loadImage(url)
        }
    }

    Item {
        id: bubble
        width: view.size; height: view.size

        Rectangle {     // under the picture: shows before the first frame and when there is no camera
            anchors.fill: parent
            radius: width / 2
            color: Theme.solidBg
            Text {
                anchors.centerIn: parent
                width: parent.width * 0.7
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: CamState.error !== "" ? 13 : Math.max(18, parent.width / 6)
                text: CamState.error !== "" ? "󰗟\nNo camera" : "󰄀"
            }
        }
        Canvas {
            id: canvas
            anchors.fill: parent
            visible: view.current !== ""
            onWidthChanged: requestPaint()
            onImageLoaded: {
                if (!view.live) return
                const p = view.pending
                let i = p.length - 1
                while (i >= 0 && !isImageLoaded(p[i])) i--
                if (i < 0) return
                for (let k = 0; k < i; k++) unloadImage(p[k])
                if (view.current !== "") unloadImage(view.current)
                view.current = p[i]
                view.pending = p.slice(i + 1)
                view.frames++
                requestPaint()
            }
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const img = view.current
                if (img === "" || !isImageLoaded(img)) return
                const w = width, h = height
                ctx.save()
                ctx.beginPath()
                ctx.arc(w / 2, h / 2, w / 2, 0, 2 * Math.PI)
                ctx.closePath()
                ctx.clip()
                ctx.translate(w, 0); ctx.scale(-1, 1)     // mirrored, like a mirror
                ctx.drawImage(img, 0, 0, w, h)
                ctx.restore()
            }
        }
        Rectangle {     // which camera, for a moment after a switch
            visible: CamState.notice !== ""
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: parent.height * 0.12 }
            width: Math.min(parent.width * 0.86, noticeText.implicitWidth + 16)
            height: noticeText.implicitHeight + 8
            radius: height / 2
            color: Theme.solidBg
            Text {
                id: noticeText
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.parent.width * 0.86 - 16)
                elide: Text.ElideRight
                text: CamState.notice
                color: Theme.fg
                font { family: Theme.font; pixelSize: 12 }
            }
        }
        Rectangle {     // the rim
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.width: mouse.containsMouse || mouse.drag.active ? 3 : 2
            border.color: mouse.containsMouse || mouse.drag.active ? Theme.accent : Theme.line
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            drag.target: bubble
            drag.minimumX: 0; drag.maximumX: view.width - bubble.width
            drag.minimumY: 0; drag.maximumY: view.height - bubble.height
            onReleased: mouse => { if (mouse.button === Qt.LeftButton) view.remember() }
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) Sys.run(Sys.bin + "cams pick")
                else if (mouse.button === Qt.MiddleButton) CamState.next()
            }
            onWheel: wheel => view.resize(view.size + (wheel.angleDelta.y > 0 ? 20 : wheel.angleDelta.y < 0 ? -20 : 0))
        }
    }
}
