// Test stand-in for Quickshell.Services.Pipewire's PwNodeType flags (qml-panels-test). QML type
// properties cannot start with a capital, so this is a JS library imported "as PwNodeType".
.pragma library
var Audio = 1, Video = 2, Source = 4, Sink = 8, Stream = 16
var AudioSource = 5, AudioSink = 9, AudioInStream = 21, AudioOutStream = 25, VideoSource = 6
