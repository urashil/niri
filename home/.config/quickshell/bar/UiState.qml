pragma Singleton
import Quickshell
import QtQuick

// Shared UI state: which overlays are open, notification history, and the dynamic-island event.
Singleton {
    id: root

    // overlays
    property bool power: false
    property bool wallpaper: false
    property bool quick: false
    property string quickPage: "main"
    property bool history: false
    property bool media: false
    property bool claude: false          // Claude usage card
    property real claudeCenter: 1300     // x of the Claude button, where the card opens under
    property bool songOpen: false        // the island expanded into the song's film
    property real statsCenter: 1100      // x of the CPU/RAM chip, where the media card opens under
    property real pillW: 200             // width of the center island, so the expanded one can grow out of it
    property bool launcher: false
    property bool focusOpen: false
    property string focusTab: "timer"
    function openFocus(tab) {
        if (focusOpen && focusTab === tab) { focusOpen = false; return; }
        focusTab = tab;
        focusOpen = true;
    }
    property bool monitor: false
    property real recStart: 0           // epoch seconds while a recording runs (written by the rec script)
    readonly property bool recording: recStart > 0
    property string monitorTab: "cpu"
    function openMonitor(tab) {
        if (monitor && monitorTab === tab) { monitor = false; return; }
        monitorTab = tab;
        monitor = true;
    }
    property bool switcher: false
    signal switcherStep(int dir)

    // light / dark (written by the theme-mode script)
    property string mode: "dark"
    property bool vpnPage: false

    // toggles
    property real brightness: 0.5
    property bool caffeine: false
    property bool superCaffeine: false     // blocks suspend
    // off -> caffeine -> super caffeine -> off
    function cycleCaffeine() {
        if (!caffeine) caffeine = true;
        else if (!superCaffeine) superCaffeine = true;
        else { superCaffeine = false; caffeine = false; }
    }
    onSuperCaffeineChanged: if (superCaffeine) caffeine = true
    property bool dnd: false

    // notification history (newest first)
    property var notes: []
    property int unread: 0
    function addNote(n) {
        notes = [n].concat(notes).slice(0, 60);
        unread += 1;
    }
    function clearNotes() { notes = []; unread = 0; }

    // dynamic island
    property bool islandActive: false
    property string islandKind: ""
    property string islandIcon: ""
    property string islandText: ""
    property real islandValue: -1
    property color islandColor: "#88c0d0"

    function pulse(kind, icon, text, value, color, ms) {
        islandKind = kind;
        islandIcon = icon;
        islandText = text;
        islandValue = value;
        islandColor = color;
        islandActive = true;
        islandTimer.interval = ms || 1800;
        islandTimer.restart();
    }
    Timer { id: islandTimer; onTriggered: root.islandActive = false }

    function openQuick(page) {
        quickPage = page || "main";
        quick = true;
    }
}
