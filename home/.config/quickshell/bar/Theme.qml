pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Colors come from colors.json, which `wallpaper` regenerates with matugen.
// The defaults below are Nordic-darker, used until the file is first read.
Singleton {
    id: root

    property color primary: "#88c0d0"
    property color fgPrimary: "#191d24"
    property color primaryContainer: "#3b4a5a"
    property color fgContainer: "#d8dee9"
    property color secondary: "#81a1c1"
    property color tertiary: "#b48ead"
    property color error: "#bf616a"
    property color surface: "#191d24"
    property color surfaceLow: "#1e222a"
    property color surfaceContainer: "#242933"
    property color surfaceHigh: "#2e3440"
    property color text: "#d8dee9"
    property color textDim: "#aab1c0"
    property color outline: "#616e88"
    property color outlineVariant: "#3b4252"
    property color red: "#bf616a"
    property color green: "#a3be8c"
    property color yellow: "#ebcb8b"
    property color blue: "#81a1c1"
    property color magenta: "#b48ead"
    property color cyan: "#88c0d0"

    readonly property string font: "JetBrainsMono Nerd Font"
    readonly property int radius: 14
    readonly property int islandHeight: 34

    FileView {
        path: Quickshell.shellPath("colors.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const j = JSON.parse(text());
                for (const k in j) if (k in root) root[k] = j[k];
            } catch (e) {
                console.warn("Theme: bad colors.json:", e);
            }
        }
    }
}
