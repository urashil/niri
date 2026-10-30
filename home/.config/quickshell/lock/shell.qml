//@ pragma UseQApplication
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

// Session lock: blurred wallpaper, big clock, PAM password field, status chips.
// LOCK_TEST=1 auto-unlocks after 6 s (used while developing). ~/.local/bin/lock falls back to swaylock if this never engages.
ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property bool test: Quickshell.env("LOCK_TEST") === "1"
    readonly property string user: Quickshell.env("USER")
    property string wall: ""
    property string pwd: ""
    property string status: "idle"        // idle | checking | wrong
    property real intro: 0
    property bool leaving: false
    readonly property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
    readonly property var bat: UPower.displayDevice

    FileView {
        path: root.home + "/.cache/rice/current"
        onLoaded: root.wall = text().trim()
    }
    SystemClock { id: clock; precision: SystemClock.Seconds }
    Process { id: flag }

    NumberAnimation { id: introAnim; target: root; property: "intro"; from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }

    function engaged() {
        flag.command = ["sh", "-c", "touch \"$HOME/.cache/rice/locked\""];
        flag.running = true;
        introAnim.start();
    }
    function unlock() {
        leaving = true;
        flag.command = ["sh", "-c", "rm -f \"$HOME/.cache/rice/locked\""];
        flag.running = true;
        lock.locked = false;
        quit.start();
    }
    Timer { id: quit; interval: 250; onTriggered: Qt.quit() }
    Timer { running: root.test; interval: 6000; onTriggered: root.unlock() }

    function submit() {
        if (status === "checking" || pwd === "") return;
        status = "checking";
        pam.start();
    }

    PamContext {
        id: pam
        config: "swaylock"
        user: root.user
        onPamMessage: { if (responseRequired) respond(root.pwd); }
        onCompleted: result => {
            if (result === PamResult.Success) root.unlock();
            else { root.status = "wrong"; root.pwd = ""; }
        }
        onError: { root.status = "wrong"; root.pwd = ""; }
    }

    Component {
        id: content
            Item {
                id: scr
                anchors.fill: parent

                // ---- background ----
                Image {
                    id: bg
                    anchors.fill: parent
                    source: root.wall ? "file://" + root.wall : ""
                    fillMode: Image.PreserveAspectCrop
                    visible: false
                    asynchronous: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: bg
                    blurEnabled: true
                    blurMax: 64
                    blur: 0.15 + 0.85 * root.intro
                    brightness: -0.12 * root.intro
                    saturation: 0.1
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.alpha(Theme.surface, 0.55 * root.intro) }
                        GradientStop { position: 0.5; color: Qt.alpha(Theme.surface, 0.30 * root.intro) }
                        GradientStop { position: 1.0; color: Qt.alpha(Theme.surface, 0.70 * root.intro) }
                    }
                }

                // ---- clock ----
                Column {
                    id: clockCol
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * 0.12 - 30 * (1 - root.intro)
                    opacity: root.intro
                    spacing: 0
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        font.family: Theme.font; font.pixelSize: 150; font.weight: Font.Bold
                        color: Theme.text
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
                        font.family: Theme.font; font.pixelSize: 22; font.weight: Font.Medium
                        color: Theme.primary
                    }
                }

                // ---- login ----
                Column {
                    id: login
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height * 0.52 + 30 * (1 - root.intro)
                    opacity: root.intro
                    spacing: 18

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 96; height: 96; radius: 48
                        color: Theme.primaryContainer
                        border.width: 3
                        border.color: root.status === "wrong" ? Theme.error : Theme.primary
                        Behavior on border.color { ColorAnimation { duration: 200 } }
                        Image {
                            id: face
                            anchors.fill: parent; anchors.margins: 3
                            // the same picture as the login screen: ~/.face, else SDDM's copy, else the one in the dotfiles
                            readonly property var tries: [root.home + "/.face", "/usr/share/sddm/faces/" + root.user + ".face.icon",
                                                          root.home + "/dotfiles/root/usr/share/sddm/faces/" + root.user + ".face.icon"]
                            property int at: 0
                            source: "file://" + tries[at]
                            fillMode: Image.PreserveAspectCrop
                            visible: false
                            onStatusChanged: {
                                if (status === Image.Ready) faceMask.visible = true;
                                else if (status === Image.Error && at < tries.length - 1) at++;
                            }
                        }
                        MultiEffect { id: faceMask; visible: false; anchors.fill: face; source: face; maskEnabled: true; maskSource: mask; }
                        Item { id: mask; anchors.fill: face; layer.enabled: true; visible: false; Rectangle { anchors.fill: parent; radius: width / 2 } }
                        Text {
                            anchors.centerIn: parent
                            visible: face.status !== Image.Ready
                            text: root.user.charAt(0).toUpperCase()
                            font.family: Theme.font; font.pixelSize: 40; font.bold: true
                            color: Theme.fgContainer
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.user
                        font.family: Theme.font; font.pixelSize: 18; font.weight: Font.Medium
                        color: Theme.text
                    }

                    // password pill
                    Rectangle {
                        id: pill
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 340; height: 54; radius: 27
                        color: Qt.alpha(Theme.surface, 0.72)
                        border.width: 2
                        border.color: root.status === "wrong" ? Theme.error : root.status === "checking" ? Theme.yellow : root.pwd.length > 0 ? Theme.primary : Theme.outlineVariant
                        Behavior on border.color { ColorAnimation { duration: 180 } }

                        SequentialAnimation on x {
                            id: shake
                            running: false
                            NumberAnimation { to: pill.x - 14; duration: 50 }
                            NumberAnimation { to: pill.x + 14; duration: 80 }
                            NumberAnimation { to: pill.x - 10; duration: 70 }
                            NumberAnimation { to: pill.x + 8; duration: 60 }
                            NumberAnimation { to: pill.x; duration: 50 }
                        }
                        Connections { target: root; function onStatusChanged() { if (root.status === "wrong") shake.restart(); } }

                        Text {
                            anchors { left: parent.left; leftMargin: 22; verticalCenter: parent.verticalCenter }
                            text: ""; font.family: Theme.font; font.pixelSize: 16
                            color: root.pwd.length > 0 ? Theme.primary : Theme.outline
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: root.pwd.length === 0
                            text: root.status === "checking" ? "Checking…" : "Password"
                            font.family: Theme.font; font.pixelSize: 15
                            color: Theme.outline
                        }
                        Row {
                            anchors.centerIn: parent
                            spacing: 8
                            Repeater {
                                model: Math.min(root.pwd.length, 18)
                                delegate: Rectangle {
                                    width: 11; height: 11; radius: 6; color: Theme.primary
                                    scale: 0
                                    Component.onCompleted: scale = 1
                                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2 } }
                                }
                            }
                        }
                        Text {
                            anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
                            text: root.status === "checking" ? "" : ""
                            font.family: Theme.font; font.pixelSize: 15
                            color: root.pwd.length > 0 ? Theme.primary : Theme.outlineVariant
                            RotationAnimation on rotation { running: root.status === "checking"; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: 18
                        text: root.status === "wrong" ? "Wrong password" : root.test ? "test mode: unlocking in a few seconds" : "Enter to unlock"
                        font.family: Theme.font; font.pixelSize: 12
                        color: root.status === "wrong" ? Theme.error : Theme.textDim
                    }
                }

                // ---- bottom bar ----
                Rectangle {
                    id: media
                    visible: root.player !== null
                    anchors { left: parent.left; bottom: parent.bottom; leftMargin: 36; bottomMargin: 32 }
                    opacity: root.intro
                    height: 48; radius: 24
                    width: mrow.implicitWidth + 36
                    color: Qt.alpha(Theme.surface, 0.62)
                    border.width: 1; border.color: Theme.outlineVariant
                    Row {
                        id: mrow
                        anchors.centerIn: parent
                        spacing: 12
                        Text { anchors.verticalCenter: parent.verticalCenter; text: root.player && root.player.isPlaying ? "" : ""; font.family: Theme.font; font.pixelSize: 14; color: Theme.tertiary }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, 380)
                            elide: Text.ElideRight
                            text: root.player ? (root.player.trackArtist ? root.player.trackArtist + " – " : "") + root.player.trackTitle : ""
                            font.family: Theme.font; font.pixelSize: 13; color: Theme.text
                        }
                    }
                }
                Row {
                    anchors { right: parent.right; bottom: parent.bottom; rightMargin: 36; bottomMargin: 32 }
                    spacing: 10
                    opacity: root.intro

                    component Chip: Rectangle {
                        property string icon
                        property string label
                        property color accent: Theme.text
                        height: 48; radius: 24
                        width: crow.implicitWidth + 32
                        color: Qt.alpha(Theme.surface, 0.62)
                        border.width: 1; border.color: Theme.outlineVariant
                        Row {
                            id: crow
                            anchors.centerIn: parent
                            spacing: 8
                            Text { anchors.verticalCenter: parent.verticalCenter; text: icon; font.family: Theme.font; font.pixelSize: 15; color: accent }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: label; font.family: Theme.font; font.pixelSize: 13; color: Theme.text }
                        }
                    }
                    Chip { visible: Weather.configured && Weather.loaded; icon: Weather.icon; label: Weather.tempText; accent: Weather.color }
                    Chip { icon: Vpn.connected ? "" : "󰦝"; label: Vpn.connected ? "VPN" : "No VPN"; accent: Vpn.connected ? Theme.green : Theme.outline }
                    Chip { icon: Wifi.connected ? "" : ""; label: Wifi.connected ? Wifi.ssid : "offline"; accent: Wifi.connected ? Theme.cyan : Theme.error }
                    Chip {
                        visible: root.bat && root.bat.isLaptopBattery
                        readonly property bool charging: root.bat && (root.bat.state === UPowerDeviceState.Charging || root.bat.state === UPowerDeviceState.FullyCharged)
                        icon: charging ? "" : ""
                        label: root.bat ? Math.round(root.bat.percentage * 100) + "%" : ""
                        accent: charging ? Theme.green : Theme.text
                    }
                }

                // ---- keyboard ----
                TextInput {
                    id: capture
                    width: 1; height: 1; opacity: 0
                    focus: true
                    echoMode: TextInput.Password
                    onTextChanged: { root.pwd = text; if (root.status === "wrong" && text.length > 0) root.status = "idle"; }
                    Keys.onReturnPressed: root.submit()
                    Keys.onEnterPressed: root.submit()
                    Keys.onEscapePressed: { text = ""; root.pwd = ""; }
                    Connections { target: root; function onPwdChanged() { if (root.pwd === "") capture.text = ""; } }
                    Component.onCompleted: forceActiveFocus()
                }
                MouseArea { anchors.fill: parent; onClicked: capture.forceActiveFocus() }
            }
    }

    // LOCK_PREVIEW=1: same UI in an ordinary overlay window (screenshots are blocked while truly locked)
    readonly property bool preview: Quickshell.env("LOCK_PREVIEW") === "1"
    Component {
        id: previewWin
        PanelWindow {
            anchors { top: true; left: true; right: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "black"
            Loader { anchors.fill: parent; sourceComponent: content }
        }
    }
    Loader { active: root.preview; sourceComponent: previewWin; onLoaded: root.engaged() }

    WlSessionLock {
        id: lock
        locked: !root.preview
        onSecureChanged: if (secure) root.engaged()

        WlSessionLockSurface {
            id: surface
            color: Theme.surface

            Loader { anchors.fill: parent; sourceComponent: content }
        }
    }
}
