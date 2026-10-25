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

    function back() { UiState.quickPage = "main"; askSsid = ""; }

    MouseArea { anchors.fill: parent; onClicked: UiState.quick = false }
    Item { focus: win.visible; Keys.onEscapePressed: { if (win.page !== "main") win.back(); else UiState.quick = false; } }

    // ---- privacy backend ----
    QtObject {
        id: priv
        property var s: ({ mode: "disabled", range: "full", mac: "", permanent: "", ssid: null, always: false, hostname: "", bootHostname: false, harden: false })
        property bool installed: true
        property string busy: ""
        property string hostInput: ""
        function refresh() { stat.running = true; }
        function run(label, args) {
            busy = label;
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
        onExited: { priv.busy = ""; settle.restart(); }
    }
    Timer { id: settle; interval: 3500; onTriggered: { priv.refresh(); Wifi.refresh(); } }

    Process { id: bright }
    Process { id: prof }

    Rectangle {
        id: card
        anchors { top: parent.top; right: parent.right; topMargin: 56; rightMargin: 12 }
        width: 400
        height: Math.min(win.height - 80, body.implicitHeight + 36)
        radius: Theme.radius + 6
        color: Qt.alpha(Theme.surface, 0.985)
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
                        icon: UiState.dnd ? "" : ""
                        title: "Do not disturb"
                        subtitle: UiState.dnd ? "On" : "Off"
                        on: UiState.dnd
                        onToggled: UiState.dnd = !UiState.dnd
                    }
                    Controls.Tile {
                        Layout.fillWidth: true
                        icon: ""
                        title: "Caffeine"
                        subtitle: UiState.caffeine ? "Screen stays on" : "Idle lock on"
                        on: UiState.caffeine
                        onToggled: UiState.caffeine = !UiState.caffeine
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
                    Controls.Chip { label: "Outputs"; onClicked: UiState.quickPage = "audio" }
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
                        height: win.askSsid === modelData.ssid ? 96 : 46
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
                            text: row.modelData.connected ? "Connected" : row.modelData.security === "8021x" ? "802.1X (enterprise)" : (row.modelData.known ? "Saved · " : "") + (row.modelData.security === "open" ? "Open" : "Secured")
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
                                if (mouse.button === Qt.RightButton) { if (n.known) Wifi.forget(n.ssid); return; }
                                if (n.connected) { Wifi.disconnect(); return; }
                                if (n.security === "8021x" && !n.known) { Wifi.error = "802.1X networks need a profile in /var/lib/iwd/" + n.ssid + ".8021x (see iwd.network(5))"; return; }
                                if (n.security === "open" || n.known) Wifi.connectTo(n.ssid, "");
                                else { win.askSsid = n.ssid; pass.text = ""; pass.forceActiveFocus(); }
                            }
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
                    text: "click: connect · click connected: disconnect · right-click saved: forget"
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
                    Text { text: "Audio output"; font.family: Theme.font; font.pixelSize: 14; font.bold: true; color: Theme.text; Layout.fillWidth: true }
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
                        Text { text: "Host  " + (priv.s.hostname || "—"); font.family: Theme.font; font.pixelSize: 12; color: Theme.text }
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

                Text { text: "Hostname"; font.family: Theme.font; font.pixelSize: 10; color: Theme.textDim; Layout.topMargin: 4 }
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
                            onAccepted: if (text) priv.run("Setting hostname", ["hostname", text])
                            Text { visible: !hostIn.text; text: "custom name"; color: Theme.outline; font: hostIn.font; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                    Controls.Chip { label: "Set"; onClicked: if (hostIn.text) priv.run("Setting hostname", ["hostname", hostIn.text]) }
                    Controls.Chip { label: "Random"; accent: Theme.yellow; onClicked: priv.run("Randomizing", ["hostname", "random"]) }
                }
                Flow {
                    Layout.fillWidth: true; spacing: 8
                    Controls.Chip { label: "Random hostname at boot"; on: priv.s.bootHostname; onClicked: priv.run("Applying", ["boot-hostname", priv.s.bootHostname ? "off" : "on"]) }
                    Controls.Chip { label: "Quiet network (no mDNS/LLMNR)"; on: priv.s.harden; onClicked: priv.run("Applying", ["harden", priv.s.harden ? "off" : "on"]) }
                }
                Text {
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: "Changes ask for your password once, then stay unlocked for a few minutes. iwd restarts when the MAC settings change, so Wi-Fi drops for a second."
                    font.family: Theme.font; font.pixelSize: 9; color: Theme.outline
                }
            }
        }
    }
}
