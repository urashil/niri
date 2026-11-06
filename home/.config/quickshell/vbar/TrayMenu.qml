import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

// Styled replacement for the native tray context menu.
PopupWindow {
    id: pop
    required property var menu
    required property Item target
    required property var parentWindow

    anchor.window: parentWindow
    anchor.item: target
    anchor.edges: Edges.Bottom | Edges.Right
    anchor.gravity: Edges.Bottom | Edges.Left
    anchor.margins.top: 6
    color: "transparent"
    grabFocus: true
    implicitWidth: 260
    implicitHeight: col.implicitHeight + 16

    QsMenuOpener { id: root; menu: pop.menu }

    Rectangle {
        id: box
        anchors.fill: parent
        radius: 14
        color: Qt.alpha(Theme.surface, 0.97)
        border.width: 1
        border.color: Theme.outlineVariant

        ColumnLayout {
            id: col
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 2

            Repeater {
                model: root.children
                delegate: ColumnLayout {
                    id: item
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 2
                    property bool open: false

                    Rectangle {
                        visible: item.modelData.isSeparator
                        Layout.fillWidth: true; Layout.topMargin: 3; Layout.bottomMargin: 3
                        height: 1; color: Theme.outlineVariant
                    }
                    Rectangle {
                        visible: !item.modelData.isSeparator
                        Layout.fillWidth: true
                        height: 32; radius: 9
                        color: hit.containsMouse && item.modelData.enabled ? Theme.primaryContainer : "transparent"
                        opacity: item.modelData.enabled ? 1 : 0.45
                        IconImage {
                            id: ic
                            visible: item.modelData.icon !== ""
                            implicitSize: 16
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            source: item.modelData.icon
                        }
                        Text {
                            anchors { left: ic.visible ? ic.right : parent.left; leftMargin: ic.visible ? 8 : 12; right: mark.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                            text: item.modelData.text.replace(/&/g, "")
                            elide: Text.ElideRight
                            font.family: Theme.font; font.pixelSize: 12
                            color: hit.containsMouse && item.modelData.enabled ? Theme.fgContainer : Theme.text
                        }
                        Text {
                            id: mark
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: item.modelData.hasChildren ? (item.open ? "" : "") : item.modelData.buttonType !== QsMenuButtonType.None && item.modelData.checkState === Qt.Checked ? "" : ""
                            font.family: Theme.font; font.pixelSize: 11; color: Theme.primary
                        }
                        MouseArea {
                            id: hit
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!item.modelData.enabled) return;
                                if (item.modelData.hasChildren) { item.open = !item.open; return; }
                                item.modelData.triggered();
                                pop.visible = false;
                            }
                        }
                    }

                    // one level of submenu, inline
                    QsMenuOpener { id: sub; menu: item.modelData.hasChildren ? item.modelData : null }
                    Repeater {
                        model: item.open ? sub.children : null
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true; Layout.leftMargin: 14
                            height: modelData.isSeparator ? 1 : 28; radius: 8
                            color: modelData.isSeparator ? Theme.outlineVariant : sh.containsMouse ? Theme.primaryContainer : "transparent"
                            Text {
                                visible: !parent.modelData.isSeparator
                                anchors { left: parent.left; leftMargin: 10; right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                text: parent.modelData.text.replace(/&/g, "")
                                elide: Text.ElideRight
                                font.family: Theme.font; font.pixelSize: 11; color: Theme.textDim
                            }
                            MouseArea { id: sh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (!parent.modelData.isSeparator) { parent.modelData.triggered(); pop.visible = false; } } }
                        }
                    }
                }
            }
        }
    }
}
