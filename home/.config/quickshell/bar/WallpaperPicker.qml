import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Mod+Shift+W: thumbnail grid. Arrows move, Enter applies, Esc closes, click applies.
PanelWindow {
    id: win
    visible: UiState.wallpaper
    anchors { top: true; left: true; right: true; bottom: true }
    color: Qt.rgba(0, 0, 0, 0.55)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-wallpapers"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: UiState.wallpaper ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property string dir: Quickshell.env("HOME") + "/Pictures/Wallpapers"
    property var files: []
    property string current: ""

    Process {
        id: lister
        command: ["sh", "-c", "find -L \"" + win.dir + "\" -maxdepth 2 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\) | sort"]
        stdout: StdioCollector {
            onStreamFinished: {
                win.files = text.trim() === "" ? [] : text.trim().split("\n");
                const i = win.files.indexOf(win.current);
                grid.currentIndex = i >= 0 ? i : 0;
            }
        }
    }
    FileView {
        id: cur
        path: Quickshell.env("HOME") + "/.cache/rice/current"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: win.current = text().trim()
    }
    Process { id: apply }

    function choose(path) {
        UiState.wallpaper = false;
        apply.command = [Quickshell.env("HOME") + "/.local/bin/wallpaper", "set", path];
        apply.running = true;
    }
    onVisibleChanged: if (visible) { cur.reload(); lister.running = true; grid.forceActiveFocus(); }

    MouseArea { anchors.fill: parent; onClicked: UiState.wallpaper = false }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width - 120, 1100)
        height: Math.min(parent.height - 160, 100 + Math.max(1, Math.ceil(win.files.length / Math.max(1, Math.floor((width - 32) / 300)))) * 190)
        radius: Theme.radius + 6
        color: Qt.alpha(Theme.surface, 0.99)
        border.width: 1
        border.color: Theme.outlineVariant

        MouseArea { anchors.fill: parent }

        Text {
            id: title
            anchors { top: parent.top; left: parent.left; margins: 22 }
            text: "Wallpapers"
            font.family: Theme.font; font.pixelSize: 15; font.bold: true; color: Theme.text
        }
        Text {
            anchors { verticalCenter: title.verticalCenter; right: parent.right; rightMargin: 22 }
            text: "↵ apply   esc close"
            font.family: Theme.font; font.pixelSize: 11; color: Theme.outline
        }

        GridView {
            id: grid
            anchors { top: title.bottom; topMargin: 14; left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
            clip: true
            focus: true
            model: win.files
            cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 300)))
            cellHeight: 190
            keyNavigationEnabled: true
            highlightMoveDuration: 0
            Keys.onEscapePressed: UiState.wallpaper = false
            Keys.onReturnPressed: if (currentIndex >= 0 && win.files[currentIndex]) win.choose(win.files[currentIndex])
            Keys.onEnterPressed: Keys.onReturnPressed

            delegate: Item {
                id: cell
                required property string modelData
                required property int index
                width: grid.cellWidth
                height: grid.cellHeight
                readonly property bool selected: GridView.isCurrentItem
                readonly property bool active: modelData === win.current

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 8
                    radius: 14
                    color: Theme.surfaceHigh
                    border.width: cell.selected ? 3 : cell.active ? 2 : 1
                    border.color: cell.selected ? Theme.primary : cell.active ? Theme.tertiary : Theme.outlineVariant
                    scale: cell.selected ? 1.03 : 1
                    Behavior on scale { NumberAnimation { duration: 120 } }

                    Image {
                        anchors.fill: parent
                        anchors.margins: 4
                        source: "file://" + cell.modelData
                        sourceSize.width: 520
                        sourceSize.height: 300
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        smooth: true
                    }
                    Rectangle {
                        anchors { left: parent.left; bottom: parent.bottom; margins: 10 }
                        height: 22; radius: 11
                        width: label.implicitWidth + 18
                        color: Qt.alpha(Theme.surface, 0.85)
                        Text {
                            id: label
                            anchors.centerIn: parent
                            text: cell.modelData.split("/").pop().replace(/\.[^.]+$/, "")
                            font.family: Theme.font; font.pixelSize: 11; color: Theme.text
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: grid.currentIndex = cell.index
                        onClicked: win.choose(cell.modelData)
                    }
                }
            }
        }
    }
}
