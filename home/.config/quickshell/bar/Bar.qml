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

        Process { id: launcher; command: ["fuzzel"] }

        Item {
            id: content
            // room for the left row before it would touch the island; the window title shrinks first, the weather chip steps aside last
            readonly property real leftRoom: (content.width - island.width) / 2 - 14
            readonly property real leftFixed: launcherIsland.width + wsPill.width + 2 * leftRow.spacing
            readonly property bool weatherShown: Weather.configured && Weather.loaded && Weather.showInBar
                && (leftRoom - leftFixed - weatherChip.width - leftRow.spacing) > 110
            readonly property real titleRoom: leftRoom - leftFixed - leftRow.spacing - (weatherShown ? weatherChip.width + leftRow.spacing : 0) - 28
            anchors.fill: parent
            anchors.topMargin: 8
            anchors.leftMargin: 12
            anchors.rightMargin: 12

            // ---- left ----
            Row {
                id: leftRow
                anchors.left: parent.left
                spacing: 8

                Island {
                    id: launcherIsland
                    pad: 12
                    Glyph { text: ""; color: Theme.primary; font.pixelSize: 17 }
                    overlay: MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: launcher.running = true
                    }
                }
                Workspaces { id: wsPill; screenName: win.modelData.name }
                Island {
                    id: weatherChip
                    // off by choice (weather page, "In bar"), and hidden when there is no room before the island
                    visible: content.weatherShown
                    spacing: 6
                    Glyph { text: Weather.icon; color: Weather.color; font.pixelSize: 16 }
                    Label { text: Weather.tempText }
                    overlay: MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: UiState.openQuick("weather")
                    }
                }
                Island {
                    visible: Niri.title !== "" && content.titleRoom > 50
                    Label {
                        text: Niri.title
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 340, content.titleRoom)
                        color: Theme.textDim
                    }
                }
            }

            // ---- center ----
            DynamicIsland {
                id: island
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.top
                anchors.verticalCenterOffset: Theme.islandHeight / 2
            }

            // ---- right ----
            Row {
                id: rightRow
                anchors.right: parent.right
                spacing: 8

                Island {
                    // only while the island shows the player in place of the clock: then this slot is just the time
                    visible: Song.shown
                    spacing: 8
                    Glyph { text: "\uf017"; color: Theme.primary; font.pixelSize: 13 }
                    Label { text: Qt.formatDateTime(clock.date, "HH:mm"); font.weight: Font.Bold }
                }

                // Claude usage: ring-less glyph, tints as the limits fill up
                Island {
                    id: claudeChip
                    spacing: 6
                    function publish() { UiState.claudeCenter = claudeChip.mapToItem(null, claudeChip.width / 2, 0).x; }
                    onXChanged: publish()
                    onWidthChanged: publish()
                    Component.onCompleted: publish()
                    Glyph { text: "\uf0e7"; font.pixelSize: 14; color: ClaudeUsage.hot >= 90 ? Theme.error : ClaudeUsage.hot >= 70 ? Theme.yellow : Theme.primary }
                    Label { visible: ClaudeUsage.loaded; text: Math.round(ClaudeUsage.session) + "%" }
                    overlay: MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: UiState.claude = !UiState.claude
                    }
                }

                Stats {
                    id: stats
                    // the media card opens right under this chip
                    function publish() { UiState.statsCenter = stats.mapToItem(null, stats.width / 2, 0).x; }
                    onXChanged: publish()
                    onWidthChanged: publish()
                    Component.onCompleted: publish()
                }

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
                            Loader {
                                id: menuLoader
                                active: false
                                sourceComponent: TrayMenu {
                                    menu: trayItem.modelData.menu
                                    target: trayItem
                                    parentWindow: win
                                    visible: true
                                    onVisibleChanged: if (!visible) menuLoader.active = false
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    if (mouse.button === Qt.LeftButton) trayItem.modelData.activate();
                                    else if (mouse.button === Qt.MiddleButton) trayItem.modelData.secondaryActivate();
                                    else if (trayItem.modelData.hasMenu) menuLoader.active = !menuLoader.active;
                                }
                            }
                        }
                    }
                }

                Island {
                    spacing: 14

                    // screen recording timer (click to stop)
                    Row {
                        visible: UiState.recording
                        spacing: 6
                        readonly property int secs: Math.max(0, Math.floor(clock.date.getTime() / 1000) - UiState.recStart)
                        Glyph {
                            text: "\uf111"; color: Theme.red; font.pixelSize: 11
                            SequentialAnimation on opacity { running: UiState.recording; loops: Animation.Infinite; NumberAnimation { to: 0.25; duration: 600 } NumberAnimation { to: 1; duration: 600 } }
                        }
                        Label { text: String(Math.floor(parent.secs / 60)).padStart(2, "0") + ":" + String(parent.secs % 60).padStart(2, "0"); color: Theme.red }
                        TapHandler { onTapped: Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/rec", "stop"]) }
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                    }

                    // caffeine (only while on)
                    Glyph {
                        visible: UiState.caffeine
                        text: UiState.superCaffeine ? "\uf023" : "\uf0f4"
                        color: UiState.superCaffeine ? Theme.red : Theme.yellow
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onClicked: mouse => { if (mouse.button === Qt.MiddleButton) { UiState.superCaffeine = false; UiState.caffeine = false; } else UiState.openQuick("caffeine"); }
                        }
                    }

                    // vpn (PIA): left = page, middle = connect/disconnect
                    Glyph {
                        text: Vpn.connected ? "\uf132" : Vpn.busy ? "\uf132" : "\udb82\udd9d"
                        color: Vpn.connected ? Theme.green : Vpn.busy ? Theme.yellow : (Vpn.blocked && Wifi.connected) || Vpn.state === "Interrupted" ? Theme.error : Theme.outline
                        SequentialAnimation on opacity {
                            running: Vpn.busy; loops: Animation.Infinite
                            NumberAnimation { to: 0.35; duration: 500 }
                            NumberAnimation { to: 1; duration: 500 }
                        }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onClicked: mouse => { if (mouse.button === Qt.MiddleButton) Vpn.toggle(); else UiState.openQuick("vpn"); }
                        }
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
                        // nothing to show at zero or when muted
                        visible: win.sink !== null && win.sink.audio !== null && Math.round(win.sink.audio.volume * 100) > 0 && !win.sink.audio.muted
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
                        Label { visible: Math.round(parent.pct) < 100; text: Math.round(parent.pct) + "%" }
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
