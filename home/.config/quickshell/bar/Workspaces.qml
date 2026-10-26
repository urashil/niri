import Quickshell
import QtQuick
import Quickshell.Widgets

// Workspace pills; occupied ones show the icons of the apps inside.
Island {
    id: root
    required property string screenName
    readonly property var list: Niri.byOutput(screenName)
    spacing: 6
    pad: 10

    function iconFor(appId) {
        const e = DesktopEntries.heuristicLookup(appId);
        return Quickshell.iconPath(e && e.icon ? e.icon : appId, "application-x-executable");
    }

    Repeater {
        model: root.list.length
        delegate: Rectangle {
            id: pill
            required property int index
            readonly property var ws: root.list[index]
            readonly property bool active: ws ? ws.is_active : false
            readonly property var wins: ws ? Niri.windowsOn(ws.id) : []
            readonly property int shown: Math.min(wins.length, 3)

            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            height: 24
            radius: 12
            width: wins.length === 0 ? (active ? 24 : 10) : shown * 20 + 10 + (wins.length > 3 ? 14 : 0)
            color: active ? Theme.primaryContainer : wins.length > 0 ? Theme.surfaceHigh : "transparent"
            border.width: active ? 1 : 0
            border.color: Theme.primary

            Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
            Behavior on color { ColorAnimation { duration: 260 } }

            // empty workspace: a dot
            Rectangle {
                visible: pill.wins.length === 0
                anchors.centerIn: parent
                width: 10; height: 10; radius: 5
                color: pill.active ? Theme.primary : Qt.alpha(Theme.outline, 0.55)
            }

            Row {
                anchors.centerIn: parent
                spacing: 4
                visible: pill.wins.length > 0
                Repeater {
                    model: pill.shown
                    delegate: IconImage {
                        required property int index
                        implicitSize: 16
                        source: root.iconFor(pill.wins[index].app_id || "")
                        opacity: pill.active ? 1 : 0.7
                    }
                }
                Text {
                    visible: pill.wins.length > 3
                    text: "+" + (pill.wins.length - 3)
                    font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -3
                cursorShape: Qt.PointingHandCursor
                onClicked: if (pill.ws) Niri.focusWorkspace(pill.ws.idx)
            }
        }
    }
}
