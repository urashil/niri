import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

// Vertical bar (left edge) — port of the top bar. WIP: dynamic island + stats/media chip
// still to come. Popouts open to the right of the bar (see the *Popup/QuickSettings edits).
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: win
        required property var modelData
        screen: modelData

        anchors { top: true; left: true; bottom: true }
        implicitWidth: 52
        color: "transparent"
        WlrLayershell.namespace: "qs-vbar"

        PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
        IdleInhibitor { window: win; enabled: UiState.caffeine }

        readonly property var sink: Pipewire.defaultAudioSink
        readonly property var bat: UPower.displayDevice
        SystemClock { id: clock; precision: SystemClock.Minutes }

        // screen-y of a glyph's centre, so its popout opens next to it (bar and popouts share screen origin)
        function cy(item) { return item.mapToItem(null, item.width / 2, item.height / 2).y; }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 6
            radius: Theme.radius + 8
            color: Qt.alpha(Theme.surface, 0.92)
            border.width: 1
            border.color: Theme.outlineVariant
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.topMargin: 14
            anchors.bottomMargin: 14
            spacing: 12

            // ── top: launcher + workspaces ──
            Glyph {
                Layout.alignment: Qt.AlignHCenter
                text: ""
                color: Theme.primary
                font.pixelSize: 18
                MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: UiState.launcher = true }
            }
            Workspaces { Layout.alignment: Qt.AlignHCenter; screenName: win.modelData.name }

            // weather (stacked glyph + temp)
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                visible: Weather.configured && Weather.loaded
                spacing: -2
                Glyph { Layout.alignment: Qt.AlignHCenter; text: Weather.icon; color: Weather.color; font.pixelSize: 15 }
                Label { Layout.alignment: Qt.AlignHCenter; text: Weather.tempText; font.pixelSize: 9; color: Theme.textDim }
                TapHandler { onTapped: UiState.openQuick("weather", win.cy(parent)) }
                HoverHandler { cursorShape: Qt.PointingHandCursor; onHoveredChanged: hovered ? UiState.hoverOpenQuick("weather", win.cy(parent)) : UiState.hoverRelease() }
            }

            Item { Layout.fillHeight: true; Layout.fillWidth: true } // spacer

            // ── bottom: status cluster ──
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 15

                // tray
                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 12
                    visible: SystemTray.items.values.length > 0
                    Repeater {
                        model: SystemTray.items
                        delegate: Item {
                            id: trayItem
                            required property var modelData
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 18; implicitHeight: 18
                            IconImage { anchors.centerIn: parent; implicitSize: 18; source: trayItem.modelData.icon }
                            Loader {
                                id: menuLoader
                                active: false
                                sourceComponent: TrayMenu { menu: trayItem.modelData.menu; target: trayItem; parentWindow: win; visible: true; onVisibleChanged: if (!visible) menuLoader.active = false }
                            }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -3
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

                // rec timer
                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    visible: UiState.recording
                    spacing: 2
                    readonly property int secs: Math.max(0, Math.floor(clock.date.getTime() / 1000) - UiState.recStart)
                    Glyph {
                        Layout.alignment: Qt.AlignHCenter
                        text: ""; color: Theme.red; font.pixelSize: 11
                        SequentialAnimation on opacity { running: UiState.recording; loops: Animation.Infinite; NumberAnimation { to: 0.25; duration: 600 } NumberAnimation { to: 1; duration: 600 } }
                    }
                    TapHandler { onTapped: Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/rec", "stop"]) }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }

                // caffeine
                Glyph {
                    Layout.alignment: Qt.AlignHCenter
                    visible: UiState.caffeine
                    text: UiState.superCaffeine ? "" : ""
                    color: UiState.superCaffeine ? Theme.red : Theme.yellow
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: mouse => { if (mouse.button === Qt.MiddleButton) { UiState.superCaffeine = false; UiState.caffeine = false; } else UiState.openQuick("caffeine", win.cy(parent)); }
                    }
                    HoverHandler { onHoveredChanged: hovered ? UiState.hoverOpenQuick("caffeine", win.cy(parent)) : UiState.hoverRelease() }
                }

                // Claude usage
                Glyph {
                    id: claudeGlyph
                    Layout.alignment: Qt.AlignHCenter
                    text: ""
                    color: ClaudeUsage.hot >= 90 ? Theme.error : ClaudeUsage.hot >= 70 ? Theme.yellow : Theme.primary
                    function publish() { UiState.claudeCenter = claudeGlyph.mapToItem(null, claudeGlyph.width / 2, claudeGlyph.height / 2).y; }
                    onYChanged: publish()
                    Component.onCompleted: publish()
                    Rectangle { visible: ClaudeUsage.waiting > 0; width: 7; height: 7; radius: 4; color: Theme.yellow; anchors { right: parent.right; rightMargin: -3; top: parent.top; topMargin: 6 } }
                    MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: { claudeGlyph.publish(); UiState.claude = !UiState.claude; } }
                    HoverHandler { onHoveredChanged: { if (hovered) { claudeGlyph.publish(); UiState.hoverOpen("claude"); } else UiState.hoverRelease(); } }
                }

                // mitch.pro
                Glyph {
                    id: mitchGlyph
                    Layout.alignment: Qt.AlignHCenter
                    text: ""
                    color: MitchHub.needsYou ? Theme.yellow : MitchHub.prCount > 0 ? Theme.primary : Theme.outline
                    function publish() { UiState.mitchCenter = mitchGlyph.mapToItem(null, mitchGlyph.width / 2, mitchGlyph.height / 2).y; }
                    onYChanged: publish()
                    Component.onCompleted: publish()
                    Rectangle { visible: MitchHub.needsYou; width: 7; height: 7; radius: 4; color: Theme.yellow; anchors { right: parent.right; rightMargin: -3; top: parent.top; topMargin: 6 } }
                    MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: { mitchGlyph.publish(); UiState.mitch = !UiState.mitch; } }
                    HoverHandler { onHoveredChanged: { if (hovered) { mitchGlyph.publish(); UiState.hoverOpen("mitch"); } else UiState.hoverRelease(); } }
                }

                // vpn
                Glyph {
                    Layout.alignment: Qt.AlignHCenter
                    text: Vpn.connected ? "" : Vpn.busy ? "" : "󰦝"
                    color: Vpn.connected ? Theme.green : Vpn.busy ? Theme.yellow : (Vpn.blocked && Wifi.connected) || Vpn.state === "Interrupted" ? Theme.error : Theme.outline
                    SequentialAnimation on opacity { running: Vpn.busy; loops: Animation.Infinite; NumberAnimation { to: 0.35; duration: 500 } NumberAnimation { to: 1; duration: 500 } }
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: mouse => { if (mouse.button === Qt.MiddleButton) Vpn.toggle(); else UiState.openQuick("vpn", win.cy(parent)); }
                    }
                    HoverHandler { onHoveredChanged: hovered ? UiState.hoverOpenQuick("vpn", win.cy(parent)) : UiState.hoverRelease() }
                }

                // wifi
                Glyph {
                    Layout.alignment: Qt.AlignHCenter
                    text: !Wifi.powered ? "" : ""
                    opacity: !Wifi.powered ? 1 : Wifi.connected ? 0.35 + Wifi.bars * 0.16 : 0.4
                    color: !Wifi.powered ? Theme.error : Wifi.connected ? Theme.cyan : Theme.outline
                    MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: UiState.openQuick("wifi", win.cy(parent)) }
                    HoverHandler { onHoveredChanged: hovered ? UiState.hoverOpenQuick("wifi", win.cy(parent)) : UiState.hoverRelease() }
                }

                // volume (icon only; wheel to adjust, middle-click mute)
                Glyph {
                    Layout.alignment: Qt.AlignHCenter
                    visible: win.sink !== null && win.sink.audio !== null
                    readonly property real v: win.sink && win.sink.audio ? win.sink.audio.volume : 0
                    readonly property bool m: win.sink && win.sink.audio ? win.sink.audio.muted : true
                    text: m ? "󰖁" : v > 0.5 ? "" : v > 0 ? "" : "󰖁"
                    color: m ? Theme.outline : Theme.blue
                    WheelHandler {
                        onWheel: e => {
                            if (!win.sink || !win.sink.audio) return;
                            const d = e.angleDelta.y > 0 ? 0.03 : -0.03;
                            win.sink.audio.volume = Math.max(0, Math.min(1, win.sink.audio.volume + d));
                        }
                    }
                    TapHandler { acceptedButtons: Qt.LeftButton; onTapped: UiState.openQuick("main", win.cy(parent)) }
                    TapHandler { acceptedButtons: Qt.MiddleButton; onTapped: if (win.sink && win.sink.audio) win.sink.audio.muted = !win.sink.audio.muted }
                    HoverHandler { onHoveredChanged: hovered ? UiState.hoverOpenQuick("main", win.cy(parent)) : UiState.hoverRelease() }
                }

                // battery
                Glyph {
                    Layout.alignment: Qt.AlignHCenter
                    visible: win.bat && win.bat.isLaptopBattery
                    readonly property real pct: win.bat ? win.bat.percentage * 100 : 0
                    readonly property bool charging: win.bat && (win.bat.state === UPowerDeviceState.Charging || win.bat.state === UPowerDeviceState.FullyCharged)
                    text: charging ? "" : pct > 87 ? "" : pct > 62 ? "" : pct > 37 ? "" : pct > 12 ? "" : ""
                    color: charging ? Theme.green : pct <= 15 ? Theme.error : Theme.text
                    TapHandler { onTapped: UiState.openQuick("main", win.cy(parent)) }
                    HoverHandler { onHoveredChanged: hovered ? UiState.hoverOpenQuick("main", win.cy(parent)) : UiState.hoverRelease() }
                }

                // notifications
                Glyph {
                    Layout.alignment: Qt.AlignHCenter
                    text: UiState.dnd ? "" : ""
                    color: UiState.dnd ? Theme.outline : Theme.text
                    Rectangle { visible: UiState.unread > 0; width: 8; height: 8; radius: 4; color: Theme.primary; anchors { right: parent.right; rightMargin: -2; top: parent.top; topMargin: 6 } }
                    MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: { UiState.hoverCenter = win.cy(parent); UiState.history = !UiState.history; } }
                    HoverHandler { onHoveredChanged: hovered ? UiState.hoverOpen("history", win.cy(parent)) : UiState.hoverRelease() }
                }

                // clock (stacked)
                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: -1
                    Label { Layout.alignment: Qt.AlignHCenter; text: Qt.formatDateTime(clock.date, "HH"); font.weight: Font.Bold; font.pixelSize: 15 }
                    Label { Layout.alignment: Qt.AlignHCenter; text: Qt.formatDateTime(clock.date, "mm"); color: Theme.textDim; font.pixelSize: 15 }
                }

                // power
                Glyph {
                    Layout.alignment: Qt.AlignHCenter
                    text: ""
                    color: Theme.red
                    MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: UiState.power = true }
                }
            }
        }
    }
}
