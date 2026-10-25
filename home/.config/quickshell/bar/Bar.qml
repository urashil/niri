import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: win
        required property var modelData
        screen: modelData

        anchors { top: true; left: true; right: true }
        implicitHeight: 52
        color: "transparent"
        WlrLayershell.namespace: "qs-bar"

        PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
        IdleInhibitor { window: win; enabled: UiState.caffeine }

        readonly property var sink: Pipewire.defaultAudioSink
        readonly property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
        readonly property var bat: UPower.displayDevice

        SystemClock { id: clock; precision: SystemClock.Seconds }

        Process { id: wp; command: [Quickshell.env("HOME") + "/.local/bin/wallpaper", "next"] }
        Process { id: launcher; command: ["fuzzel"] }

        Item {
            anchors.fill: parent
            anchors.topMargin: 8
            anchors.leftMargin: 12
            anchors.rightMargin: 12

            // ---- left ----
            Row {
                anchors.left: parent.left
                spacing: 8

                Island {
                    pad: 12
                    Glyph { text: ""; color: Theme.primary; font.pixelSize: 17 }
                    overlay: MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: launcher.running = true
                    }
                }
                Workspaces { screenName: win.modelData.name }
                Island {
                    visible: Niri.title !== ""
                    Label {
                        text: Niri.title
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 340)
                        color: Theme.textDim
                    }
                }
            }

            // ---- center ----
            DynamicIsland {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.top
                anchors.verticalCenterOffset: Theme.islandHeight / 2
            }

            // ---- right ----
            Row {
                anchors.right: parent.right
                spacing: 8

                Island {
                    visible: win.player !== null
                    spacing: 8
                    Glyph {
                        text: win.player && win.player.isPlaying ? "" : ""
                        color: Theme.tertiary
                        font.pixelSize: 12
                    }
                    Label {
                        text: win.player ? (win.player.trackArtist ? win.player.trackArtist + " – " : "") + win.player.trackTitle : ""
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 240)
                    }
                    overlay: MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                        onClicked: mouse => {
                            if (!win.player) return;
                            if (mouse.button === Qt.RightButton) win.player.next();
                            else if (mouse.button === Qt.MiddleButton) win.player.togglePlaying();
                            else UiState.media = !UiState.media;
                        }
                    }
                }

                Stats {}

                Island {
                    visible: SystemTray.items.values.length > 0
                    spacing: 10
                    Repeater {
                        model: SystemTray.items
                        delegate: Item {
                            id: trayItem
                            required property var modelData
                            width: 18
                            height: Theme.islandHeight
                            IconImage {
                                anchors.centerIn: parent
                                implicitSize: 18
                                source: trayItem.modelData.icon
                            }
                            QsMenuAnchor {
                                id: menu
                                menu: trayItem.modelData.menu
                                anchor.window: win
                                anchor.rect.x: trayItem.mapToItem(null, 0, 0).x
                                anchor.rect.y: win.height
                                anchor.rect.width: 18
                                anchor.rect.height: 1
                            }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    if (mouse.button === Qt.LeftButton) trayItem.modelData.activate();
                                    else if (mouse.button === Qt.MiddleButton) trayItem.modelData.secondaryActivate();
                                    else if (trayItem.modelData.hasMenu) menu.open();
                                }
                            }
                        }
                    }
                }

                Island {
                    spacing: 14

                    // wallpaper: left = picker, right = next
                    Glyph {
                        text: ""
                        color: Theme.secondary
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) wp.running = true;
                                else UiState.wallpaper = true;
                            }
                        }
                    }

                    // caffeine (only while on)
                    Glyph {
                        visible: UiState.caffeine
                        text: ""
                        color: Theme.yellow
                        MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: UiState.caffeine = false }
                    }

                    // wifi (iwd) -> quick settings, wifi page
                    Glyph {
                        text: !Wifi.powered ? "" : ""
                        opacity: !Wifi.powered ? 1 : Wifi.connected ? 0.35 + Wifi.bars * 0.16 : 0.4
                        color: !Wifi.powered ? Theme.error : Wifi.connected ? Theme.cyan : Theme.outline
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: UiState.openQuick("wifi")
                        }
                    }

                    // volume
                    Row {
                        visible: win.sink !== null && win.sink.audio !== null
                        spacing: 6
                        Glyph {
                            readonly property real v: win.sink && win.sink.audio ? win.sink.audio.volume : 0
                            readonly property bool m: win.sink && win.sink.audio ? win.sink.audio.muted : true
                            text: m ? "󰖁" : v > 0.5 ? "" : v > 0 ? "" : "󰖁"
                            color: m ? Theme.outline : Theme.blue
                        }
                        Label {
                            text: win.sink && win.sink.audio ? Math.round(win.sink.audio.volume * 100) + "%" : "--"
                        }
                        WheelHandler {
                            onWheel: e => {
                                if (!win.sink || !win.sink.audio) return;
                                const d = e.angleDelta.y > 0 ? 0.03 : -0.03;
                                win.sink.audio.volume = Math.max(0, Math.min(1, win.sink.audio.volume + d));
                            }
                        }
                        TapHandler { acceptedButtons: Qt.LeftButton; onTapped: UiState.openQuick("main") }
                        TapHandler {
                            acceptedButtons: Qt.MiddleButton
                            onTapped: if (win.sink && win.sink.audio) win.sink.audio.muted = !win.sink.audio.muted
                        }
                    }

                    // battery
                    Row {
                        visible: win.bat && win.bat.isLaptopBattery
                        spacing: 6
                        readonly property real pct: win.bat ? win.bat.percentage * 100 : 0
                        readonly property bool charging: win.bat && (win.bat.state === UPowerDeviceState.Charging || win.bat.state === UPowerDeviceState.FullyCharged)
                        Glyph {
                            text: parent.charging ? "" : parent.pct > 87 ? "" : parent.pct > 62 ? "" : parent.pct > 37 ? "" : parent.pct > 12 ? "" : ""
                            color: parent.charging ? Theme.green : parent.pct <= 15 ? Theme.error : Theme.text
                        }
                        Label { text: Math.round(parent.pct) + "%" }
                        TapHandler { onTapped: UiState.openQuick("main") }
                    }

                    // notifications
                    Item {
                        width: bell.implicitWidth
                        height: Theme.islandHeight
                        Glyph {
                            id: bell
                            text: UiState.dnd ? "" : ""
                            color: UiState.dnd ? Theme.outline : Theme.text
                        }
                        Rectangle {
                            visible: UiState.unread > 0
                            width: 8; height: 8; radius: 4
                            color: Theme.primary
                            anchors { right: parent.right; rightMargin: -2; top: parent.top; topMargin: 8 }
                        }
                        MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: UiState.history = !UiState.history }
                    }

                    // power
                    Glyph {
                        text: ""
                        color: Theme.red
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: UiState.power = true
                        }
                    }
                }
            }
        }
    }
}
