import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

// Built-in notification daemon: popups + history (bell in the bar) + do-not-disturb.
Scope {
    NotificationServer {
        id: server
        keepOnReload: true
        bodySupported: true
        actionsSupported: true
        imageSupported: true
        onNotification: n => {
            UiState.addNote({
                app: n.appName, summary: n.summary, body: n.body,
                time: Qt.formatDateTime(new Date(), "HH:mm"),
                critical: n.urgency === NotificationUrgency.Critical
            });
            if (UiState.dnd && n.urgency !== NotificationUrgency.Critical) return;   // kept in history only
            n.tracked = true;
        }
    }

    PanelWindow {
        id: win
        visible: server.trackedNotifications.values.length > 0
        anchors { top: true; right: true }
        margins { top: 56; right: 12 }
        implicitWidth: 380
        implicitHeight: col.implicitHeight + 8
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "qs-notifications"
        WlrLayershell.layer: WlrLayer.Overlay

        Column {
            id: col
            width: parent.width
            spacing: 10

            Repeater {
                model: server.trackedNotifications
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    width: col.width
                    implicitHeight: content.implicitHeight + 28
                    radius: Theme.radius + 2
                    color: Qt.alpha(Theme.surface, 0.96)
                    border.width: 1
                    border.color: modelData.urgency === NotificationUrgency.Critical ? Theme.error : Theme.outlineVariant

                    Timer {
                        interval: card.modelData.expireTimeout > 0 ? card.modelData.expireTimeout * 1000
                                : card.modelData.urgency === NotificationUrgency.Critical ? 0 : 6000
                        running: interval > 0
                        onTriggered: card.modelData.expire()
                    }

                    Rectangle {
                        width: 4; radius: 2
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; margins: 12 }
                        color: card.modelData.urgency === NotificationUrgency.Critical ? Theme.error : Theme.primary
                    }

                    ColumnLayout {
                        id: content
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14; leftMargin: 26 }
                        spacing: 4
                        Text {
                            Layout.fillWidth: true
                            text: card.modelData.appName
                            font.family: Theme.font; font.pixelSize: 11
                            color: Theme.textDim
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: card.modelData.summary
                            font.family: Theme.font; font.pixelSize: 14; font.bold: true
                            color: Theme.text
                            wrapMode: Text.Wrap
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: card.modelData.body
                            font.family: Theme.font; font.pixelSize: 12
                            color: Theme.textDim
                            wrapMode: Text.Wrap
                            maximumLineCount: 4
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: card.modelData.dismiss()
                    }
                }
            }
        }
    }
}
