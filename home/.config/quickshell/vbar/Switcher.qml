import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick

// Alt+Tab. Opens on the first press, Tab cycles, releasing Alt switches.
PanelWindow {
    id: win
    visible: UiState.switcher
    anchors { top: true; left: true; right: true; bottom: true }
    color: Qt.rgba(0, 0, 0, 0.2)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: UiState.switcher ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { item: card; radius: Theme.radius + 8 }

    property var wins: []
    property int index: 0
    property double openedAt: 0

    function ts(w) { return w.focus_timestamp ? w.focus_timestamp.secs * 1e9 + w.focus_timestamp.nanos : 0; }
    function open(dir) {
        if (!UiState.switcher) {
            wins = Niri.windows.slice().sort((a, b) => ts(b) - ts(a));
            if (wins.length === 0) return;
            index = wins.length > 1 ? (dir < 0 ? wins.length - 1 : 1) : 0;
            openedAt = Date.now();
            UiState.switcher = true;
            keys.forceActiveFocus();
        } else {
            index = (index + dir + wins.length) % wins.length;
        }
    }
    function commit() {
        UiState.switcher = false;
        const w = wins[index];
        if (w) Quickshell.execDetached(["niri", "msg", "action", "focus-window", "--id", String(w.id)]);
    }
    Connections { target: UiState; function onSwitcherStep(dir) { win.open(dir); } }

    // committing when Alt is no longer held (covers a release that happened before we got focus)
    Timer {
        interval: 70; running: UiState.switcher; repeat: true
        onTriggered: if (Date.now() - win.openedAt > 250 && !(Qt.application.keyboardModifiers & Qt.AltModifier)) win.commit()
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: win.visible
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) { UiState.switcher = false; }
            else if (e.key === Qt.Key_Tab || e.key === Qt.Key_Right) win.open(1);
            else if (e.key === Qt.Key_Backtab || e.key === Qt.Key_Left) win.open(-1);
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) win.commit();
        }
        Keys.onReleased: e => { if (e.key === Qt.Key_Alt) win.commit(); }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(win.width - 80, row.implicitWidth + 40)
        height: 190
        radius: Theme.radius + 8
        color: Qt.alpha(Theme.surface, 0.84)
        border.width: 1
        border.color: Theme.outlineVariant

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 12
            Repeater {
                model: win.wins
                delegate: Rectangle {
                    id: c
                    required property var modelData
                    required property int index
                    readonly property bool cur: index === win.index
                    width: 138; height: 140; radius: 16
                    color: cur ? Theme.primaryContainer : Theme.surfaceContainer
                    border.width: cur ? 2 : 0
                    border.color: Theme.primary
                    scale: cur ? 1.04 : 1
                    Behavior on scale { NumberAnimation { duration: 100 } }
                    IconImage {
                        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 22 }
                        implicitSize: 54
                        source: Quickshell.iconPath((DesktopEntries.heuristicLookup(c.modelData.app_id || "") || {}).icon || c.modelData.app_id || "", "application-x-executable")
                    }
                    Text {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
                        text: c.modelData.title || c.modelData.app_id
                        elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Theme.font; font.pixelSize: 11
                        color: c.cur ? Theme.fgContainer : Theme.text
                    }
                    MouseArea { anchors.fill: parent; onClicked: { win.index = c.index; win.commit(); } }
                }
            }
        }
    }
}
