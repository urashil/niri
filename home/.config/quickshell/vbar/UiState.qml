pragma Singleton
import Quickshell
import QtQuick

// Shared UI state: which overlays are open, notification history, and the dynamic-island event.
Singleton {
    id: root

    // overlays
    property bool power: false
    property bool quitAsk: false        // Mod+Shift+E: "log out?" (QuitPrompt)
    property bool wallpaper: false
    property bool quick: false
    property string quickPage: "main"
    property bool history: false
    property bool media: false
    property bool claude: false          // Claude usage card
    property bool ask: false             // Ask Claude card
    signal askRequested(string q, string image)
    function askClaude(q, image) { ask = true; askRequested(q || "", image || ""); }
    property real claudeCenter: 1300     // x of the Claude button, where the card opens under
    property bool mitch: false           // mitch.pro GitHub card
    property real mitchCenter: 1300      // x of the mitch.pro button, where the card opens under

    // ---- hover-open popouts ----
    // Glyphs open their popout on hover; it closes after a debounce once neither the
    // glyph nor the popout is hovered. Click-open leaves hoverPopout "" so it stays put.
    property string hoverPopout: ""
    property real hoverCenter: 540       // y the active bar popout centers on (set from the glyph that opened it)
    Timer { id: hoverCloseTimer; interval: 350; onTriggered: root.closeHover() }
    function hoverOpen(name, cy) { if (cy !== undefined) hoverCenter = cy; hoverCloseTimer.stop(); hoverPopout = name; applyPopout(name, true); }
    function hoverOpenQuick(page, cy) { quickPage = page; hoverOpen("quick", cy); }
    function hoverKeep() { if (hoverPopout !== "") hoverCloseTimer.stop(); }
    function hoverRelease() { if (hoverPopout !== "") hoverCloseTimer.restart(); }
    function closeHover() { if (hoverPopout !== "") { applyPopout(hoverPopout, false); hoverPopout = ""; } }
    function applyPopout(name, v) {
        if (name === "claude") claude = v;
        else if (name === "mitch") mitch = v;
        else if (name === "media") media = v;
        else if (name === "history") history = v;
        else if (name === "quick") quick = v;
        else if (name === "monitor") monitor = v;
    }
    property bool songOpen: false        // the island expanded into the song's film
    property real statsCenter: 1100      // x of the CPU/RAM chip, where the media card opens under
    property real pillW: 200             // width of the center island, so the expanded one can grow out of it
    property bool launcher: false
    property string launcherText: ""   // what the launcher opens with ("c " for clipboard search)
    property bool drill: false           // password practice card
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

    function openQuick(page, cy) {
        if (cy !== undefined) hoverCenter = cy;
        quickPage = page || "main";
        quick = true;
    }
}
