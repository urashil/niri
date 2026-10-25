import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts

// Dropdown under the right side of the bar. Pages: main, wifi, bluetooth, audio, privacy.
PanelWindow {
    id: win
    visible: UiState.quick
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-quick"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: UiState.quick ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    BackgroundEffect.blurRegion: Region { item: card; radius: Theme.radius + 6 }
    readonly property string page: UiState.quickPage
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var bt: Bluetooth.defaultAdapter
    readonly property string helper: "/usr/local/lib/rice/net-helper"

    PwObjectTracker { objects: Pipewire.nodes.values }

    onVisibleChanged: {
        if (visible) { priv.refresh(); Wifi.refresh(); if (page === "wifi") Wifi.scan(); }
        else { UiState.quickPage = "main"; askSsid = ""; }
    }
    onPageChanged: { if (page === "wifi" && visible) Wifi.scan(); if (page === "privacy") priv.refresh(); }

    property string askSsid: ""
    property string detailSsid: ""
    property real nowSec: Math.floor(Date.now() / 1000)
    Timer { interval: 1000; running: win.visible; repeat: true; onTriggered: win.nowSec = Math.floor(Date.now() / 1000) }
    readonly property string recElapsed: {
        const t = Math.max(0, nowSec - UiState.recStart);
        return "\u25cf " + String(Math.floor(t / 60)).padStart(2, "0") + ":" + String(t % 60).padStart(2, "0");
    }

    function back() { UiState.quickPage = "main"; askSsid = ""; }

    MouseArea { anchors.fill: parent; onClicked: UiState.quick = false }
    Item { focus: win.visible; Keys.onEscapePressed: { if (win.page !== "main") win.back(); else UiState.quick = false; } }

    // ---- privacy backend ----
    QtObject {
        id: priv
        property var s: ({ mode: "disabled", range: "full", mac: "", permanent: "", ssid: null, always: false, hostname: "", bootHostname: false, harden: false })
        property bool installed: true
        property string busy: ""
        property string note: ""
        property bool noteErr: false
        property string hostInput: ""
        function refresh() { stat.running = true; }
        function run(label, args) {
            busy = label;
            note = "";
            act.command = ["pkexec", win.helper].concat(args);
            act.running = true;
        }
    }
    Process {
        id: stat
        command: [win.helper, "status"]
        stdout: StdioCollector {
            onStreamFinished: { try { priv.s = JSON.parse(text); priv.installed = true; } catch (e) { priv.installed = false; } }
        }
        onExited: code => { if (code !== 0) priv.installed = false; }
    }
    Process {
        id: act
        stdout: StdioCollector { id: actOut }
        stderr: StdioCollector { id: actErr }
        onExited: code => {
            priv.busy = "";
            if (code === 0) { priv.note = actOut.text.trim() ? "→ " + actOut.text.trim() : "Done"; priv.noteErr = false; }
            else if (code === 126 || code === 127) { priv.note = "Cancelled"; priv.noteErr = true; }
            else { priv.note = actErr.text.trim().split("\n").pop() || ("failed (" + code + ")"); priv.noteErr = true; }
            priv.refresh(); Wifi.refresh();
            burst.n = 0; burst.restart();
        }
    }
    // iwd restarts and the new MAC only shows after it reconnects: keep polling for a few seconds
    Timer {
        id: burst
        property int n: 0
        interval: 900; repeat: true
        onTriggered: { priv.refresh(); Wifi.refresh(); if (++n >= 8) stop(); }
    }
    Timer { id: noteClear; interval: 6000; running: priv.note !== ""; onTriggered: priv.note = "" }

    Process { id: bright }
    Process { id: prof }

    Rectangle {
        id: card
        anchors { top: parent.top; right: parent.right; topMargin: 56; rightMargin: 12 }
        width: 400
        height: Math.min(win.height - 80, body.implicitHeight + 36)
        radius: Theme.radius + 6
        color: Qt.alpha(Theme.surface, 0.82)
        border.width: 1
        border.color: Theme.outlineVariant
        clip: true
        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

        Item {
            id: body
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
            implicitHeight: win.page === "main" ? mainPage.implicitHeight
                          : win.page === "wifi" ? wifiPage.implicitHeight
                          : win.page === "bluetooth" ? btPage.implicitHeight
                          : win.page === "audio" ? audioPage.implicitHeight
                          : win.page === "vpn" ? vpnPage.implicitHeight
                          : win.page === "weather" ? weatherPage.implicitHeight
                          : privPage.implicitHeight

            // ================= main =================
            ColumnLayout {
                id: mainPage
                visible: win.page === "main"
                width: parent.width
                spacing: 12

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2; rowSpacing: 10; columnSpacing: 10

                    Controls.Tile {
                        Layout.fillWidth: true
                        icon: Wifi.powered ? (Wifi.connected ? "" : "") : ""
                        title: "Wi-Fi"
                        subtitle: !Wifi.powered ? "Off" : Wifi.connected ? Wifi.ssid : "Not connected"
                        on: Wifi.powered && Wifi.connected
                        chevron: true
                        onToggled: Wifi.setPowered(!Wifi.powered)
                        onOpened: UiState.quickPage = "wifi"
                    }
                    Controls.Tile {
                        Layout.fillWidth: true
                        icon: ""
                        title: "Bluetooth"
                        subtitle: !win.bt ? "No adapter" : !win.bt.enabled ? "Off" : "On"
                        on: win.bt ? win.bt.enabled : false
                        chevron: true
                        onToggled: if (win.bt) win.bt.enabled = !win.bt.enabled
                        onOpened: UiState.quickPage = "bluetooth"
                    }
                    Controls.Tile {
                        Layout.fillWidth: true
                        icon: Vpn.connected ? "\uf132" : "\udb82\udd9d"
                        title: "VPN"
                        subtitle: Vpn.connected ? Vpn.pretty(Vpn.region) + " · " + (Vpn.method === "openvpn" ? "OpenVPN" : "WireGuard") : Vpn.busy ? "Working…" : "Off"
                        on: Vpn.connected
                        chevron: true
                        onToggled: Vpn.toggle()
                        onOpened: UiState.quickPage = "vpn"
                    }
                    Controls.Tile {
                        Layout.fillWidth: true
                        icon: UiState.dnd ? "" : ""
                        title: "Do not disturb"
                        subtitle: UiState.dnd ? "On" : "Off"
                        on: UiState.dnd
                        onToggled: UiState.dnd = !UiState.dnd
                    }
                    Controls.Tile {
                        Layout.fillWidth: true
                        icon: UiState.superCaffeine ? "\uf023" : "\uf0f4"
                        title: UiState.superCaffeine ? "Super caffeine" : "Caffeine"
                        subtitle: UiState.superCaffeine ? "Lid close ignored" : UiState.caffeine ? "Screen stays on · tap for super" : "Idle lock on"
                        on: UiState.caffeine
                        onToggled: UiState.cycleCaffeine()
                    }
                    Controls.Tile {
                        Layout.fillWidth: true
                        icon: PowerProfiles.profile === PowerProfile.PowerSaver ? "" : PowerProfiles.profile === PowerProfile.Performance ? "" : ""
                        title: "Power profile"
                        subtitle: PowerProfiles.profile === PowerProfile.PowerSaver ? "Power saver" : PowerProfiles.profile === PowerProfile.Performance ? "Performance" : "Balanced"
                        on: PowerProfiles.profile !== PowerProfile.Balanced
                        onToggled: PowerProfiles.profile = PowerProfiles.profile === PowerProfile.Balanced ? PowerProfile.Performance
                                  : PowerProfiles.profile === PowerProfile.Performance ? PowerProfile.PowerSaver : PowerProfile.Balanced
                    }
                    Controls.Tile {
                        Layout.fillWidth: true
                        icon: ""
                        title: "Privacy"
                        subtitle: priv.s.mode === "disabled" ? "MAC: hardware" : "MAC: " + priv.s.mode
                        on: priv.s.mode !== "disabled"
                        chevron: true
                        onToggled: UiState.quickPage = "privacy"
                        onOpened: UiState.quickPage = "privacy"
                    }
                    Controls.Tile {
                        Layout.fillWidth: true
                        icon: UiState.mode === "dark" ? "\uf186" : "\uf185"
                        title: UiState.mode === "dark" ? "Dark mode" : "Light mode"
                        subtitle: "Tap to switch"
                        on: UiState.mode === "light"
                        onToggled: Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/theme-mode", "toggle"])
                    }
                    Controls.Tile {
                        Layout.fillWidth: true
                        Layout.columnSpan: 1
                        icon: Weather.configured && Weather.loaded ? Weather.icon : "\ue302"
                        title: Weather.configured ? (Weather.loaded ? Weather.tempText + "  " + Weather.desc : "Weather…") : "Weather"
                        subtitle: Weather.configured ? Weather.name : "Set a city"
                        on: false
                        chevron: true
                        onToggled: UiState.quickPage = "weather"
                        onOpened: UiState.quickPage = "weather"
                    }
                    Controls.Tile {
                        Layout.fillWidth: true
                        icon: UiState.recording ? "\uf04d" : "\uf03d"
                        title: UiState.recording ? "Stop recording" : "Record screen"
                        subtitle: UiState.recording ? win.recElapsed : "tap: screen · ›: region"
                        on: UiState.recording
                        chevron: !UiState.recording
                        onToggled: Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/rec", UiState.recording ? "stop" : "screen"])
                        onOpened: Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/rec", "region"])
                    }
                }

                Rectangle {
                    visible: Captive.status === "portal"
                    Layout.fillWidth: true
                    height: 44; radius: 14
                    color: Qt.alpha(Theme.yellow, 0.18)
                    border.width: 1; border.color: Theme.yellow
                    Text { anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter } text: "\uf0ac  Wi-Fi needs a sign-in"; font.family: Theme.font; font.pixelSize: 12; color: Theme.text }
                    Text { anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter } text: "Open login page"; font.family: Theme.font; font.pixelSize: 11; font.bold: true; color: Theme.yellow }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Captive.openLogin() }
                }

                Rectangle {
                    visible: Vpn.blocked && Wifi.connected
                    Layout.fillWidth: true
                    implicitHeight: bk.implicitHeight + 22
                    radius: 14
                    color: Qt.alpha(Theme.error, 0.16)
                    border.width: 1; border.color: Theme.error
                    ColumnLayout {
                        id: bk
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 11 }
                        spacing: 8
                        Text { text: "\uf071  Blocked by the VPN killswitch"; font.family: Theme.font; font.pixelSize: 12; font.bold: true; color: Theme.text }
                        Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "Traffic is cut until the VPN connects."; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                        RowLayout {
                            spacing: 8
                            Controls.Chip { label: Vpn.busy ? "Connecting…" : "Connect VPN"; on: Vpn.busy; onClicked: Vpn.connect() }
                            Controls.Chip { label: "Turn killswitch off"; accent: Theme.error; onClicked: Vpn.setKillswitch("off") }
                        }
                    }
                }

                Controls.Slider {
                    Layout.fillWidth: true
                    icon: win.sink && win.sink.audio && win.sink.audio.muted ? "󰖁" : ""
                    accent: Theme.blue
                    value: win.sink && win.sink.audio ? win.sink.audio.volume : 0
                    onMoved: v => { if (win.sink && win.sink.audio) { win.sink.audio.muted = false; win.sink.audio.volume = v; } }
                    onIconClicked: if (win.sink && win.sink.audio) win.sink.audio.muted = !win.sink.audio.muted
                }
                Controls.Slider {
                    Layout.fillWidth: true
                    icon: ""
                    accent: Theme.yellow
                    value: UiState.brightness
                    onMoved: v => { bright.command = ["brightnessctl", "--class=backlight", "set", Math.max(1, Math.round(v * 100)) + "%"]; bright.running = true; }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: win.sink ? "  " + (win.sink.description || win.sink.nickname || win.sink.name) : "No audio output"
                        elide: Text.ElideRight
                        font.family: Theme.font; font.pixelSize: 11; color: Theme.textDim
                    }
                    Controls.Chip { label: "Mixer"; onClicked: UiState.quickPage = "audio" }
                }
            }

            // ================= wifi =================
            ColumnLayout {
                id: wifiPage
                visible: win.page === "wifi"
                width: parent.width
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: ""; font.family: Theme.font; font.pixelSize: 14; color: Theme.textDim; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: win.back() } }
                    Text { text: "Wi-Fi  ·  iwd"; font.family: Theme.font; font.pixelSize: 14; font.bold: true; color: Theme.text; Layout.fillWidth: true }
                    Text { text: Wifi.scanning ? "scanning…" : ""; font.family: Theme.font; font.pixelSize: Wifi.scanning ? 11 : 13; color: Theme.textDim; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: Wifi.scan() } }
                    Controls.Switch { on: Wifi.powered; onToggled: Wifi.setPowered(!Wifi.powered) }
                }

                Text {
                    visible: Wifi.error !== ""
                    Layout.fillWidth: true
                    text: Wifi.error; wrapMode: Text.Wrap
                    font.family: Theme.font; font.pixelSize: 11; color: Theme.error
                }

                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 330)
                    clip: true; spacing: 6
                    model: Wifi.powered ? Wifi.networks : []
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        width: ListView.view.width
                        height: win.askSsid === modelData.ssid ? 96 : win.detailSsid === modelData.ssid ? 160 : 46
                        radius: 12
                        color: modelData.connected ? Theme.primaryContainer : Theme.surfaceContainer
                        Behavior on height { NumberAnimation { duration: 160 } }
                        clip: true

                        Text {
                            id: wi
                            anchors { left: parent.left; leftMargin: 14; top: parent.top; topMargin: 13 }
                            text: row.modelData.bars >= 3 ? "" : ""
                            opacity: 0.35 + row.modelData.bars * 0.16
                            font.family: Theme.font; font.pixelSize: 15
                            color: row.modelData.connected ? Theme.fgContainer : Theme.cyan
                        }
                        Text {
                            anchors { left: wi.right; leftMargin: 12; right: tag.left; rightMargin: 8; top: parent.top; topMargin: 6 }
                            text: row.modelData.ssid
                            elide: Text.ElideRight
                            font.family: Theme.font; font.pixelSize: 12; font.bold: row.modelData.connected
                            color: row.modelData.connected ? Theme.fgContainer : Theme.text
                        }
                        Text {
                            anchors { left: wi.right; leftMargin: 12; top: parent.top; topMargin: 24 }
                            readonly property var rule: Wifi.rules[row.modelData.ssid]
                            text: (row.modelData.connected ? "Connected" : row.modelData.security === "8021x" ? "802.1X (enterprise)" : (row.modelData.known ? "Saved · " : "") + (row.modelData.security === "open" ? "Open" : "Secured"))
                                  + (rule ? (rule.override ? " · custom MAC" : rule.always ? " · random MAC" : "") : "")
                            font.family: Theme.font; font.pixelSize: 10
                            color: row.modelData.connected ? Qt.alpha(Theme.fgContainer, 0.8) : Theme.textDim
                        }
                        Text {
                            id: tag
                            anchors { right: parent.right; rightMargin: 14; top: parent.top; topMargin: 14 }
                            text: row.modelData.security === "open" ? "" : ""
                            font.family: Theme.font; font.pixelSize: 11; color: Theme.textDim
                        }
                        MouseArea {
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            height: 46
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                const n = row.modelData;
                                if (mouse.button === Qt.RightButton) { if (n.known) win.detailSsid = win.detailSsid === n.ssid ? "" : n.ssid; return; }
                                if (n.connected) { Wifi.disconnect(); return; }
                                if (n.security === "8021x" && !n.known) { Wifi.error = "802.1X networks need a profile in /var/lib/iwd/" + n.ssid + ".8021x (see iwd.network(5))"; return; }
                                if (n.security === "open" || n.known) Wifi.connectTo(n.ssid, "");
                                else { win.askSsid = n.ssid; pass.text = ""; pass.forceActiveFocus(); }
                            }
                        }
                        // saved-network options (right-click): MAC policy + what happens when you connect
                        Flow {
                            visible: win.detailSsid === row.modelData.ssid
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
                            spacing: 6
                            readonly property var rule: Wifi.rules[row.modelData.ssid]
                            Controls.Chip { label: "Random MAC"; on: parent.rule ? parent.rule.always && !parent.rule.override : false; onClicked: priv.run("Applying", ["rule", row.modelData.ssid, "random"]) }
                            Controls.Chip { label: "Stable MAC"; on: parent.rule ? !parent.rule.always && !parent.rule.override : false; onClicked: priv.run("Applying", ["rule", row.modelData.ssid, "stable"]) }
                            Controls.Chip { label: "Forget"; accent: Theme.error; onClicked: { Wifi.forget(row.modelData.ssid); win.detailSsid = ""; } }
                            Text { height: 30; verticalAlignment: Text.AlignVCenter; text: "on connect:"; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                            Controls.Chip { label: "WireGuard"; on: Automation.rule(row.modelData.ssid).vpn === "wg"; onClicked: Automation.set(row.modelData.ssid, "vpn", Automation.rule(row.modelData.ssid).vpn === "wg" ? "" : "wg") }
                            Controls.Chip { label: "TCP 443"; accent: Theme.yellow; on: Automation.rule(row.modelData.ssid).vpn === "443"; onClicked: Automation.set(row.modelData.ssid, "vpn", Automation.rule(row.modelData.ssid).vpn === "443" ? "" : "443") }
                            Controls.Chip { label: "VPN off"; on: Automation.rule(row.modelData.ssid).vpn === "off"; onClicked: Automation.set(row.modelData.ssid, "vpn", Automation.rule(row.modelData.ssid).vpn === "off" ? "" : "off") }
                            Controls.Chip { label: "Quiet"; on: Automation.rule(row.modelData.ssid).dnd; onClicked: Automation.set(row.modelData.ssid, "dnd", !Automation.rule(row.modelData.ssid).dnd) }
                        }

                        // password prompt
                        Rectangle {
                            visible: win.askSsid === row.modelData.ssid
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
                            height: 32; radius: 10; color: Theme.surfaceHigh
                            TextInput {
                                id: pass
                                anchors { fill: parent; leftMargin: 12; rightMargin: 70 }
                                verticalAlignment: TextInput.AlignVCenter
                                echoMode: TextInput.Password
                                color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                                selectionColor: Theme.primary
                                Keys.onReturnPressed: { Wifi.connectTo(row.modelData.ssid, pass.text); win.askSsid = ""; }
                                Keys.onEscapePressed: win.askSsid = ""
                                Text { visible: !pass.text; text: "Password"; color: Theme.outline; font: pass.font; anchors.verticalCenter: parent.verticalCenter }
                            }
                            Text {
                                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                text: "Connect"; font.family: Theme.font; font.pixelSize: 11; font.bold: true; color: Theme.primary
                                MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: { Wifi.connectTo(row.modelData.ssid, pass.text); win.askSsid = ""; } }
                            }
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: "click: connect · click connected: disconnect · right-click saved: MAC policy / forget"
                    font.family: Theme.font; font.pixelSize: 9; color: Theme.outline
                    wrapMode: Text.Wrap
                }
            }

            // ================= bluetooth =================
            ColumnLayout {
                id: btPage
                visible: win.page === "bluetooth"
                width: parent.width
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: ""; font.family: Theme.font; font.pixelSize: 14; color: Theme.textDim; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: win.back() } }
                    Text { text: "Bluetooth"; font.family: Theme.font; font.pixelSize: 14; font.bold: true; color: Theme.text; Layout.fillWidth: true }
                    Controls.Chip { visible: win.bt && win.bt.enabled; label: win.bt && win.bt.discovering ? "Stop scan" : "Scan"; onClicked: if (win.bt) win.bt.discovering = !win.bt.discovering }
                    Controls.Switch { on: win.bt ? win.bt.enabled : false; onToggled: if (win.bt) win.bt.enabled = !win.bt.enabled }
                }
                Text { visible: !win.bt; text: "No Bluetooth adapter"; font.family: Theme.font; font.pixelSize: 12; color: Theme.textDim }
                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 300)
                    clip: true; spacing: 6
                    model: win.bt && win.bt.enabled ? Bluetooth.devices : null
                    delegate: Rectangle {
                        required property var modelData
                        width: ListView.view.width; height: 44; radius: 12
                        color: modelData.connected ? Theme.primaryContainer : Theme.surfaceContainer
                        Text {
                            anchors { left: parent.left; leftMargin: 14; right: st.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            text: modelData.name || modelData.address
                            elide: Text.ElideRight
                            font.family: Theme.font; font.pixelSize: 12; color: modelData.connected ? Theme.fgContainer : Theme.text
                        }
                        Text {
                            id: st
                            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            text: modelData.connected ? "Connected" : modelData.paired ? "Paired" : ""
                            font.family: Theme.font; font.pixelSize: 10; color: modelData.connected ? Theme.fgContainer : Theme.textDim
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (modelData.connected) modelData.disconnect(); else modelData.connect(); } }
                    }
                }
            }

            // ================= audio =================
            ColumnLayout {
                id: audioPage
                visible: win.page === "audio"
                width: parent.width
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: ""; font.family: Theme.font; font.pixelSize: 14; color: Theme.textDim; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: win.back() } }
                    Text { text: "Audio"; font.family: Theme.font; font.pixelSize: 14; font.bold: true; color: Theme.text; Layout.fillWidth: true }
                }
                Repeater {
                    model: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream)
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true; height: 44; radius: 12
                        readonly property bool cur: win.sink && win.sink.id === modelData.id
                        color: cur ? Theme.primaryContainer : Theme.surfaceContainer
                        Text {
                            anchors { left: parent.left; leftMargin: 14; right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                            text: modelData.description || modelData.nickname || modelData.name
                            elide: Text.ElideRight
                            font.family: Theme.font; font.pixelSize: 12; color: parent.cur ? Theme.fgContainer : Theme.text
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Pipewire.preferredDefaultAudioSink = modelData }
                    }
                }

                Text { text: "Apps"; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim; Layout.topMargin: 6 }
                Repeater {
                    id: mixer
                    model: Pipewire.nodes.values.filter(n => n.isStream && !n.isSink && n.audio && n.properties && n.properties["media.class"] === "Stream/Output/Audio")
                    delegate: ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 0
                        Text { text: modelData.properties["application.name"] || modelData.description || modelData.name; elide: Text.ElideRight; Layout.fillWidth: true; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                        Controls.Slider {
                            Layout.fillWidth: true
                            icon: modelData.audio.muted ? "\udb81\udd81" : "\uf028"
                            accent: Theme.primary
                            value: modelData.audio.volume
                            onMoved: v => { modelData.audio.muted = false; modelData.audio.volume = v; }
                            onIconClicked: modelData.audio.muted = !modelData.audio.muted
                        }
                    }
                }
                Text { visible: mixer.count === 0; text: "Nothing is playing"; font.family: Theme.font; font.pixelSize: 11; color: Theme.outline }
            }

            // ================= vpn (PIA) =================
            ColumnLayout {
                id: vpnPage
                visible: win.page === "vpn"
                width: parent.width
                spacing: 10
                onVisibleChanged: if (visible) Vpn.loadRegions()

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "\uf053"; font.family: Theme.font; font.pixelSize: 14; color: Theme.textDim; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: win.back() } }
                    Text { text: "VPN  ·  PIA"; font.family: Theme.font; font.pixelSize: 14; font.bold: true; color: Theme.text; Layout.fillWidth: true }
                    Controls.Switch { on: Vpn.connected || Vpn.busy; onToggled: Vpn.toggle() }
                }

                Rectangle {
                    visible: Vpn.blocked && Wifi.connected
                    Layout.fillWidth: true
                    implicitHeight: bk2.implicitHeight + 22
                    radius: 14
                    color: Qt.alpha(Theme.error, 0.16)
                    border.width: 1; border.color: Theme.error
                    ColumnLayout {
                        id: bk2
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 11 }
                        spacing: 8
                        Text { text: "\uf071  Blocked by the VPN killswitch"; font.family: Theme.font; font.pixelSize: 12; font.bold: true; color: Theme.text }
                        Text { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "Traffic is cut until the VPN connects."; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                        RowLayout {
                            spacing: 8
                            Controls.Chip { label: Vpn.busy ? "Connecting…" : "Connect VPN"; on: Vpn.busy; onClicked: Vpn.connect() }
                            Controls.Chip { label: "Turn killswitch off"; accent: Theme.error; onClicked: Vpn.setKillswitch("off") }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: vcol.implicitHeight + 24
                    radius: 14
                    color: Vpn.connected ? Qt.alpha(Theme.green, 0.16) : Vpn.busy ? Qt.alpha(Theme.yellow, 0.16) : Theme.surfaceContainer
                    border.width: 1
                    border.color: Vpn.connected ? Theme.green : Vpn.busy ? Theme.yellow : Theme.outlineVariant
                    ColumnLayout {
                        id: vcol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 3
                        Text { text: (Vpn.connected ? "Connected" : Vpn.busy ? Vpn.state : Vpn.state === "Interrupted" ? "Interrupted" : "Disconnected") + "  ·  " + Vpn.pretty(Vpn.region); font.family: Theme.font; font.pixelSize: 13; font.bold: true; color: Theme.text }
                        Text { text: Vpn.label; font.family: Theme.font; font.pixelSize: 11; color: Theme.textDim }
                        Text { visible: Vpn.vpnIp !== ""; text: "VPN IP  " + Vpn.vpnIp; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                        Text { visible: Vpn.pubIp !== ""; text: "Public  " + Vpn.pubIp; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                        Text { visible: Vpn.forwardedPort !== "Inactive"; text: "Forwarded port  " + Vpn.forwardedPort; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                    }
                }

                Text { text: "Connection"; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                Flow {
                    Layout.fillWidth: true; spacing: 8
                    Controls.Chip { label: "WireGuard"; on: Vpn.choice === "wireguard"; onClicked: Vpn.useWireguard() }
                    Controls.Chip { label: "OpenVPN · TCP 443"; on: Vpn.choice === "school"; accent: Theme.yellow; onClicked: Vpn.useSchool() }
                    Controls.Chip { label: "OpenVPN · auto"; on: Vpn.choice === "auto"; onClicked: Vpn.useOpenvpnAuto() }
                }
                Text {
                    visible: !Vpn.schoolConfigured
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "The first time you pick TCP 443 it is pinned in PIA's daemon settings (piactl has no port option), which restarts the PIA service for a second. After that, switching is instant."
                    font.family: Theme.font; font.pixelSize: 9; color: Theme.outline
                }
                Text { visible: Vpn.lastError !== ""; Layout.fillWidth: true; wrapMode: Text.Wrap; text: Vpn.lastError; font.family: Theme.font; font.pixelSize: 10; color: Theme.error }

                Flow {
                    Layout.fillWidth: true; spacing: 8
                    Controls.Chip { label: "Allow LAN"; on: Vpn.allowLan; onClicked: Vpn.setAllowLan(!Vpn.allowLan) }
                    Controls.Chip { label: "Port forwarding"; on: Vpn.requestPortForward; onClicked: Vpn.setPortForward(!Vpn.requestPortForward) }
                }

                Text { text: "Killswitch"; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                Flow {
                    Layout.fillWidth: true; spacing: 8
                    Controls.Chip { label: "Always on"; on: Vpn.ksMode === "on"; onClicked: Vpn.setKillswitch("on") }
                    Controls.Chip { label: "Auto"; on: Vpn.ksMode === "auto"; onClicked: Vpn.setKillswitch("auto") }
                    Controls.Chip { label: "Off"; accent: Theme.error; on: Vpn.ksMode === "off"; onClicked: Vpn.setKillswitch("off") }
                }
                Text {
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: Vpn.ksMode === "on" ? "Always on: nothing leaves this machine while the VPN is down." : Vpn.ksMode === "auto" ? "Auto: traffic is blocked only if the tunnel drops while it should be up." : "Off: traffic flows normally when the VPN is disconnected."
                    font.family: Theme.font; font.pixelSize: 9; color: Theme.outline
                }

                Text { text: "Region"; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                Rectangle {
                    Layout.fillWidth: true; height: 30; radius: 10; color: Theme.surfaceHigh
                    TextInput {
                        id: regionFilter
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                        selectionColor: Theme.primary
                        Text { visible: !regionFilter.text; text: "filter regions"; color: Theme.outline; font: regionFilter.font; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(contentHeight, 190)
                    clip: true; spacing: 4
                    model: ["auto"].concat(Vpn.regions).filter(r => !regionFilter.text || Vpn.pretty(r).toLowerCase().indexOf(regionFilter.text.toLowerCase()) >= 0)
                    delegate: Rectangle {
                        required property string modelData
                        width: ListView.view.width; height: 34; radius: 10
                        color: Vpn.region === modelData ? Theme.primaryContainer : Theme.surfaceContainer
                        Text { anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } text: Vpn.pretty(modelData); font.family: Theme.font; font.pixelSize: 11; color: Vpn.region === modelData ? Theme.fgContainer : Theme.text }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Vpn.setRegion(modelData) }
                    }
                }
            }

            // ================= weather =================
            ColumnLayout {
                id: weatherPage
                visible: win.page === "weather"
                width: parent.width
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "\uf053"; font.family: Theme.font; font.pixelSize: 14; color: Theme.textDim; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: win.back() } }
                    Text { text: "Weather"; font.family: Theme.font; font.pixelSize: 14; font.bold: true; color: Theme.text; Layout.fillWidth: true }
                    Controls.Chip { label: "°F"; on: Weather.unit === "f"; onClicked: Weather.setUnit("f") }
                    Controls.Chip { label: "°C"; on: Weather.unit === "c"; onClicked: Weather.setUnit("c") }
                }
                Rectangle {
                    visible: Weather.configured
                    Layout.fillWidth: true
                    implicitHeight: wcol.implicitHeight + 28
                    radius: 16; color: Theme.surfaceContainer
                    RowLayout {
                        id: wcol
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 16 }
                        Text { text: Weather.icon; font.family: Theme.font; font.pixelSize: 44; color: Weather.color }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 2
                            Text { text: Weather.loaded ? Weather.tempText : "…"; font.family: Theme.font; font.pixelSize: 26; font.bold: true; color: Theme.text }
                            Text { text: Weather.desc + (Weather.loaded ? "  ·  feels " + Math.round(Weather.feels) + "°" : ""); font.family: Theme.font; font.pixelSize: 12; color: Theme.textDim }
                            Text { text: Weather.name; font.family: Theme.font; font.pixelSize: 10; color: Theme.outline; elide: Text.ElideRight; Layout.fillWidth: true }
                        }
                        ColumnLayout {
                            spacing: 2
                            Text { text: "\uf062 " + Math.round(Weather.high) + "°"; font.family: Theme.font; font.pixelSize: 12; color: Theme.red }
                            Text { text: "\uf063 " + Math.round(Weather.low) + "°"; font.family: Theme.font; font.pixelSize: 12; color: Theme.blue }
                            Text { text: "\ue31b " + Math.round(Weather.wind); font.family: Theme.font; font.pixelSize: 11; color: Theme.textDim }
                        }
                    }
                }
                Text { text: Weather.configured ? "Change city" : "Pick your city"; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Rectangle {
                        Layout.fillWidth: true; height: 30; radius: 10; color: Theme.surfaceHigh
                        TextInput {
                            id: cityIn
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                            selectionColor: Theme.primary
                            onAccepted: Weather.search(text)
                            Text { visible: !cityIn.text; text: "city name"; color: Theme.outline; font: cityIn.font; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                    Controls.Chip { label: "Search"; onClicked: Weather.search(cityIn.text) }
                }
                Repeater {
                    model: Weather.results
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true; height: 38; radius: 10; color: Theme.surfaceContainer
                        Text { anchors { left: parent.left; leftMargin: 12; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } text: modelData.name + (modelData.admin1 ? ", " + modelData.admin1 : "") + (modelData.country ? " · " + modelData.country : ""); elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 11; color: Theme.text }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Weather.choose(modelData) }
                    }
                }
                Text { text: "Open-Meteo · no account, your city name goes to geocoding-api.open-meteo.com"; font.family: Theme.font; font.pixelSize: 9; color: Theme.outline; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }

            // ================= privacy =================
            ColumnLayout {
                id: privPage
                visible: win.page === "privacy"
                width: parent.width
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: ""; font.family: Theme.font; font.pixelSize: 14; color: Theme.textDim; MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: win.back() } }
                    Text { text: "Network privacy"; font.family: Theme.font; font.pixelSize: 14; font.bold: true; color: Theme.text; Layout.fillWidth: true }
                    Text { visible: priv.busy !== ""; text: priv.busy + "…"; font.family: Theme.font; font.pixelSize: 11; color: Theme.yellow }
                    Text { visible: priv.busy === "" && priv.note !== ""; text: priv.note; font.family: Theme.font; font.pixelSize: 11; color: priv.noteErr ? Theme.error : Theme.green }
                }

                Text {
                    visible: !priv.installed
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "Helper not installed. Run: sudo bash ~/deps.sh"
                    font.family: Theme.font; font.pixelSize: 12; color: Theme.error
                }

                // identity card
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: idCol.implicitHeight + 24
                    radius: 14; color: Theme.surfaceContainer
                    ColumnLayout {
                        id: idCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 4
                        Text { text: "MAC  " + (priv.s.mac || "—"); font.family: Theme.font; font.pixelSize: 12; color: Theme.text }
                        Text { text: "Wi-Fi sees  " + (priv.s.wifiHostname ? priv.s.wifiHostname : "no hostname"); font.family: Theme.font; font.pixelSize: 12; color: Theme.text }
                        Text { text: "System host  " + (priv.s.hostname || "—") + "  (never changed)"; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                        Text { text: priv.s.ssid ? "Network  " + priv.s.ssid : "Not connected"; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                    }
                }

                Text { text: "MAC randomization (iwd)"; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim }
                Flow {
                    Layout.fillWidth: true; spacing: 8
                    Controls.Chip { label: "Off"; on: priv.s.mode === "disabled"; onClicked: priv.run("Applying", ["mode", "disabled"]) }
                    Controls.Chip { label: "Per network"; on: priv.s.mode === "network"; onClicked: priv.run("Applying", ["mode", "network"]) }
                    Controls.Chip { label: "Per session"; on: priv.s.mode === "once"; onClicked: priv.run("Applying", ["mode", "once"]) }
                }
                Flow {
                    Layout.fillWidth: true; spacing: 8
                    Controls.Chip { label: "Keep vendor prefix"; on: priv.s.range === "nic"; onClicked: priv.run("Applying", ["range", priv.s.range === "nic" ? "full" : "nic"]) }
                    Controls.Chip { label: "New MAC every connect"; on: priv.s.always; visible: priv.s.mode === "network" && priv.s.ssid !== null
                             onClicked: priv.run("Applying", ["always", priv.s.ssid, priv.s.always ? "off" : "on"]) }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Controls.Chip { label: "Rotate MAC now"; accent: Theme.yellow; onClicked: priv.run("Rotating", ["rotate"]) }
                    Text { Layout.fillWidth: true; text: "reconnects with a fresh address"; font.family: Theme.font; font.pixelSize: 10; color: Theme.outline }
                }

                Text { text: "Hostname shown to Wi-Fi networks (system hostname stays as is)"; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim; Layout.topMargin: 4 }
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Rectangle {
                        Layout.fillWidth: true; height: 30; radius: 10; color: Theme.surfaceHigh
                        TextInput {
                            id: hostIn
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            verticalAlignment: TextInput.AlignVCenter
                            color: Theme.text; font.family: Theme.font; font.pixelSize: 12
                            selectionColor: Theme.primary
                            onAccepted: if (text) priv.run("Setting Wi-Fi hostname", ["hostname", text])
                            Text { visible: !hostIn.text; text: "custom name"; color: Theme.outline; font: hostIn.font; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                    Controls.Chip { label: "Set"; onClicked: if (hostIn.text) priv.run("Setting Wi-Fi hostname", ["hostname", hostIn.text]) }
                    Controls.Chip { label: "Random"; accent: Theme.yellow; onClicked: priv.run("Randomizing", ["hostname", "random"]) }
                }
                Flow {
                    Layout.fillWidth: true; spacing: 8
                    Controls.Chip { label: "Announce it (DHCP)"; on: !!priv.s.dhcpHostname; onClicked: priv.run("Applying", ["dhcp-hostname", priv.s.dhcpHostname ? "off" : "on"]) }
                    Controls.Chip { label: "New one every boot"; on: priv.s.bootHostname; onClicked: priv.run("Applying", ["boot-hostname", priv.s.bootHostname ? "off" : "on"]) }
                    Controls.Chip { label: "Quiet network (no mDNS/LLMNR)"; on: priv.s.harden; onClicked: priv.run("Applying", ["harden", priv.s.harden ? "off" : "on"]) }
                }
                Text {
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "Only iwd gets the spoofed name (it runs in its own hostname namespace), so your real hostname, shell prompt and other apps are untouched. With nothing set, iwd sends no hostname at all. Changes restart iwd, so Wi-Fi drops for a second."
                    font.family: Theme.font; font.pixelSize: 9; color: Theme.outline
                }
            }
        }
    }
}
