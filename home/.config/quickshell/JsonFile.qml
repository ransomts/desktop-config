// A small JSON settings file, read and written as one object, for things whose owner may or
// may not be loaded (the settings window, Profiles.qml). Not a source of truth of its own:
// the file is, and a hand edit is picked up at once (watched).
//   path       the file
//   defaults   what a missing key reads as; written as the whole file when `create` is set and the
//              file is missing, or together with the first change when it is not
//   values     defaults overlaid by what the file says (live)
//   set(k, v)  write one key; every other key in the file, known or not, is kept as it was
//   update(o)  write several keys at once
// A file that is not valid JSON is never overwritten: `error` says so and set() refuses.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {                                     // not an Item: it takes no place in a layout
    id: jf
    property string path: ""
    property var defaults: ({})
    property bool create: false
    property bool watch: true
    property var raw: ({})                  // what the file holds, exactly
    readonly property var values: Object.assign({}, defaults, raw)
    property bool loaded: false             // read once (or found missing)
    property bool missing: false
    property string error: ""
    signal written()

    function get(key) { return values[key] }
    function set(key, value) { const o = {}; o[key] = value; return update(o) }
    function update(o) {
        if (error !== "") return false
        const next = Object.assign({}, missing ? defaults : raw, o)
        raw = next
        missing = false
        file.setText(JSON.stringify(next, null, 2) + "\n")
        written()
        return true
    }
    function reload() { file.reload() }

    FileView {
        id: file
        path: jf.path
        watchChanges: jf.watch
        blockWrites: true           // written before set() returns: a read right after sees it
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let o = null
            try { o = JSON.parse(text()) } catch (e) { o = undefined }
            if (o && typeof o === "object" && !Array.isArray(o)) { jf.raw = o; jf.error = "" }
            else { jf.error = "not a JSON object: " + jf.path; console.warn("JsonFile:", jf.error) }
            jf.missing = false
            jf.loaded = true
        }
        onLoadFailed: err => {
            jf.raw = ({})
            jf.missing = err === FileViewError.FileNotFound
            jf.error = jf.missing ? "" : "cannot read " + jf.path
            jf.loaded = true
            if (jf.missing && jf.create) jf.update({})
        }
    }
}
