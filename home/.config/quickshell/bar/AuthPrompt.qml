import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Polkit
import QtQuick

// Replaces polkit-gnome: the password prompt for pkexec, mount, systemctl and friends.
PanelWindow {
    id: win
    readonly property var flow: agent.flow
    readonly property bool asking: flow !== null && flow.isResponseRequired
    visible: agent.isActive
    anchors { top: true; left: true; right: true; bottom: true }
    color: Qt.rgba(0, 0, 0, 0.4)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-polkit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: agent.isActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    BackgroundEffect.blurRegion: Region { item: card; radius: Theme.radius + 8 }

    PolkitAgent { id: agent }

    function cancel() { if (flow) flow.cancelAuthenticationRequest(); }
    function submit() {
        if (!asking || input.text === "") return;
        flow.submit(input.text);
        input.text = "";
    }
    onAskingChanged: if (asking) { input.text = ""; input.forceActiveFocus(); }
    onVisibleChanged: if (visible) { input.text = ""; input.forceActiveFocus(); }

    MouseArea { anchors.fill: parent }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 440
        height: col.implicitHeight + 56
        radius: Theme.radius + 8
        color: Qt.alpha(Theme.surface, 0.9)
        border.width: 1
        border.color: Theme.outlineVariant
        Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        Column {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 28 }
            spacing: 16

            Row {
                spacing: 14
                IconImage {
                    implicitSize: 40
                    anchors.verticalCenter: parent.verticalCenter
                    source: Quickshell.iconPath(win.flow && win.flow.iconName ? win.flow.iconName : "dialog-password", "dialog-password")
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text { text: "Authentication required"; font.family: Theme.font; font.pixelSize: 15; font.bold: true; color: Theme.text }
                    Text {
                        visible: text !== ""
                        text: win.flow && win.flow.selectedIdentity ? (win.flow.selectedIdentity.displayName || "") : ""
                        font.family: Theme.font; font.pixelSize: 11; color: Theme.textDim
                    }
                }
            }

            Text {
                width: parent.width
                text: win.flow ? win.flow.message : ""
                wrapMode: Text.WordWrap
                font.family: Theme.font; font.pixelSize: 12; color: Theme.text
            }

            Rectangle {
                width: parent.width; height: 42; radius: 12
                color: Theme.surfaceContainer
                border.width: 1
                border.color: input.activeFocus ? Theme.primary : Theme.outlineVariant
                Behavior on border.color { ColorAnimation { duration: 120 } }
                TextInput {
                    id: input
                    anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                    verticalAlignment: TextInput.AlignVCenter
                    enabled: win.asking
                    echoMode: win.flow && win.flow.responseVisible ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "•"
                    font.family: Theme.font; font.pixelSize: 14
                    color: Theme.text
                    selectionColor: Theme.primary; selectedTextColor: Theme.fgPrimary
                    clip: true
                    Keys.onEscapePressed: win.cancel()
                    Keys.onReturnPressed: win.submit()
                    Keys.onEnterPressed: win.submit()
                    Text {
                        visible: !input.text
                        text: win.flow && win.flow.inputPrompt ? win.flow.inputPrompt.replace(/:\s*$/, "") : "Password"
                        font: input.font; color: Theme.outline
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: win.flow ? (win.flow.failed ? "Wrong password, try again." : win.flow.supplementaryMessage) : ""
                wrapMode: Text.WordWrap
                font.family: Theme.font; font.pixelSize: 11
                color: win.flow && (win.flow.failed || win.flow.supplementaryIsError) ? Theme.red : Theme.textDim
            }

            Row {
                anchors.right: parent.right
                spacing: 10
                Repeater {
                    model: [{ label: "Cancel", primary: false }, { label: "Authenticate", primary: true }]
                    delegate: Rectangle {
                        id: btn
                        required property var modelData
                        width: lbl.implicitWidth + 36; height: 36; radius: 12
                        color: modelData.primary ? (hover.containsMouse ? Qt.lighter(Theme.primary, 1.1) : Theme.primary)
                                                 : (hover.containsMouse ? Theme.surfaceHigh : Theme.surfaceContainer)
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Text {
                            id: lbl
                            anchors.centerIn: parent
                            text: btn.modelData.label
                            font.family: Theme.font; font.pixelSize: 12; font.bold: true
                            color: btn.modelData.primary ? Theme.fgPrimary : Theme.text
                        }
                        MouseArea {
                            id: hover
                            anchors.fill: parent; hoverEnabled: true
                            onClicked: btn.modelData.primary ? win.submit() : win.cancel()
                        }
                    }
                }
            }
        }
    }
}
