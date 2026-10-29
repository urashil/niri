import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets

// Small shared controls for the quick-settings pages.
Item {
    id: root

    component Tile: Rectangle {
        id: tile
        property string icon
        property string title
        property string subtitle
        property bool on: false
        property bool chevron: false
        signal toggled()
        signal opened()
        height: 58; radius: 16
        color: on ? Theme.primaryContainer : Theme.surfaceContainer
        Behavior on color { ColorAnimation { duration: 200 } }
        Text {
            id: ic
            anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
            text: tile.icon; font.family: Theme.font; font.pixelSize: 18
            color: tile.on ? Theme.fgContainer : Theme.textDim
        }
        Column {
            anchors { left: ic.right; leftMargin: 12; right: parent.right; rightMargin: tile.chevron ? 34 : 10; verticalCenter: parent.verticalCenter }
            spacing: 1
            Text { width: parent.width; text: tile.title; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 12; font.bold: true; color: tile.on ? Theme.fgContainer : Theme.text }
            Text { width: parent.width; text: tile.subtitle; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 10; color: tile.on ? Qt.alpha(Theme.fgContainer, 0.8) : Theme.textDim }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tile.toggled() }
        Text {
            visible: tile.chevron
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            text: ""; font.family: Theme.font; font.pixelSize: 12
            color: tile.on ? Theme.fgContainer : Theme.textDim
            MouseArea { anchors.fill: parent; anchors.margins: -10; cursorShape: Qt.PointingHandCursor; onClicked: tile.opened() }
        }
    }

    component Slider: Item {
        id: sl
        property string icon
        property string image: ""          // an icon file (an app's icon) instead of the glyph
        property bool dim: false            // muted: grey track
        property real value: 0
        property color accent: Theme.primary
        signal moved(real v)
        signal iconClicked()
        height: 34
        Text {
            id: sic
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: 26; text: sl.image ? "" : sl.icon; font.family: Theme.font; font.pixelSize: 16; color: sl.accent
            height: 26; verticalAlignment: Text.AlignVCenter
            IconImage { visible: sl.image !== ""; anchors.centerIn: parent; implicitSize: 20; source: sl.image; opacity: sl.dim ? 0.4 : 1 }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sl.iconClicked() }
        }
        Rectangle {
            id: track
            anchors { left: sic.right; leftMargin: 8; right: parent.right; verticalCenter: parent.verticalCenter }
            height: 10; radius: 5; color: Theme.surfaceHigh
            Rectangle {
                width: Math.max(10, track.width * Math.max(0, Math.min(1, sl.value))); height: parent.height; radius: 5; color: sl.dim ? Theme.outline : sl.accent
                Behavior on width { enabled: !drag.pressed; NumberAnimation { duration: 120 } }
            }
            MouseArea {
                id: drag
                anchors.fill: parent; anchors.topMargin: -10; anchors.bottomMargin: -10
                cursorShape: Qt.PointingHandCursor
                function set(x) { sl.moved(Math.max(0, Math.min(1, x / track.width))); }
                onPressed: m => set(m.x)
                onPositionChanged: m => { if (pressed) set(m.x) }
            }
        }
    }

    component Chip: Rectangle {
        id: chip
        property string label
        property bool on: false
        property color accent: Theme.primary
        signal clicked()
        height: 30; radius: 15
        implicitWidth: t.implicitWidth + 28
        Layout.minimumWidth: implicitWidth      // never squeezed below its label in a row
        color: on ? Theme.primaryContainer : Theme.surfaceHigh
        border.width: on ? 1 : 0
        border.color: accent
        Behavior on color { ColorAnimation { duration: 160 } }
        Text { id: t; anchors.centerIn: parent; text: chip.label; font.family: Theme.font; font.pixelSize: 11; color: chip.on ? Theme.fgContainer : Theme.text }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }

    component Switch: Rectangle {
        id: sw
        property bool on: false
        signal toggled()
        width: 40; height: 22; radius: 11
        color: on ? Theme.primary : Theme.surfaceHigh
        Behavior on color { ColorAnimation { duration: 160 } }
        Rectangle {
            width: 16; height: 16; radius: 8; y: 3
            x: sw.on ? parent.width - width - 3 : 3
            color: sw.on ? Theme.fgPrimary : Theme.outline
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled() }
    }
}
