import Quickshell
import QtQuick
import Quickshell.Widgets

// Vertical workspace indicators for niri: active = tall pill, occupied = app icon, empty = dot.
Column {
    id: root
    required property string screenName
    readonly property var list: Niri.byOutput(screenName)
    spacing: 6

    function iconFor(appId) {
        const e = DesktopEntries.heuristicLookup(appId);
        return Quickshell.iconPath(e && e.icon ? e.icon : appId, "application-x-executable");
    }

    Repeater {
        model: root.list.length
        delegate: Rectangle {
            id: cell
            required property int index
            readonly property var ws: root.list[index]
            readonly property bool active: ws ? ws.is_active : false
            readonly property var wins: ws ? Niri.windowsOn(ws.id) : []

            anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
            width: 30
            height: active ? 30 : wins.length > 0 ? 24 : 12
            radius: 9
            color: active ? Theme.primaryContainer : wins.length > 0 ? Theme.surfaceHigh : "transparent"
            border.width: active ? 1 : 0
            border.color: Theme.primary

            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
            Behavior on color { ColorAnimation { duration: 200 } }

            Rectangle {
                visible: cell.wins.length === 0
                anchors.centerIn: parent
                width: 8; height: 8; radius: 4
                color: cell.active ? Theme.primary : Qt.alpha(Theme.outline, 0.55)
            }
            IconImage {
                visible: cell.wins.length > 0
                anchors.centerIn: parent
                implicitSize: 16
                source: cell.wins.length > 0 ? root.iconFor(cell.wins[0].app_id || "") : ""
                opacity: cell.active ? 1 : 0.7
            }
            Text {
                visible: cell.wins.length > 1
                text: cell.wins.length
                anchors { right: parent.right; bottom: parent.bottom; rightMargin: 1; bottomMargin: 0 }
                font.family: Theme.font; font.pixelSize: 8; color: Theme.textDim
            }

            MouseArea {
                anchors.fill: parent; anchors.margins: -3
                cursorShape: Qt.PointingHandCursor
                onClicked: if (cell.ws) Niri.focusWorkspace(cell.ws.idx)
            }
        }
    }
}
