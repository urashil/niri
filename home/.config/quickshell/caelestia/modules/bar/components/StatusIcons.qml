pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.bar.components.status

StyledRect {
    id: root

    property color colour: Colours.palette.m3secondary
    readonly property alias items: iconColumn

    readonly property int spacing: Tokens.spacing.medium / 2

    // Index of the first/last entry that isn't collapsed, for edge margin gating
    readonly property int firstPresent: {
        const values = model.values;
        for (let i = 0; i < values.length; i++)
            if (!collapsed(values[i]))
                return i;
        return -1;
    }
    readonly property int lastPresent: {
        const values = model.values;
        for (let i = values.length - 1; i >= 0; i--)
            if (!collapsed(values[i]))
                return i;
        return -1;
    }

    // Entries that can shrink to nothing, spacing included
    function collapsed(entry: var): bool {
        if (entry.id === "lockStatus")
            return !Hypr.capsLock && !Hypr.numLock;
        return false;
    }

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.full

    clip: true
    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: iconColumn.implicitHeight + Tokens.padding.medium * 2

    ColumnLayout {
        id: iconColumn

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.padding.medium

        spacing: 0

        Repeater {
            model: ScriptModel {
                id: model

                values: root.Config.bar.statusIcons.values.filter(e => e.enabled)
            }

            DelegateChooser {
                role: "id"

                DelegateChoice {
                    roleValue: "lockStatus"
                    delegate: EntryWrapper {
                        LockStatus {
                            colour: root.colour
                            parentSpacing: root.spacing
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "audio"
                    delegate: EntryWrapper {
                        margin: Tokens.spacing.extraSmall / 2

                        MaterialIcon {
                            animate: true
                            text: Icons.getVolumeIcon(Audio.volume, Audio.muted)
                            color: root.colour
                            fontStyle: Tokens.font.icon.medium
                            fill: 1
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "microphone"
                    delegate: EntryWrapper {
                        margin: Tokens.spacing.extraSmall / 2
                        name: "audio" // Mic opens audio popout

                        MaterialIcon {
                            animate: true
                            text: Icons.getMicVolumeIcon(Audio.sourceVolume, Audio.sourceMuted)
                            color: root.colour
                            fontStyle: Tokens.font.icon.medium
                            fill: 1
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "kbLayout"
                    delegate: EntryWrapper {
                        StyledText {
                            animate: true
                            text: Hypr.kbLayout
                            color: root.colour
                            font: Tokens.font.mono.medium
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "network"
                    delegate: EntryWrapper {
                        MaterialIcon {
                            animate: true
                            text: Nmcli.activeEthernet ? "cable" : Nmcli.active ? Icons.getNetworkIcon(Nmcli.active.strength ?? 0) : "wifi_off"
                            color: root.colour
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "bluetooth"
                    delegate: EntryWrapper {
                        BluetoothStatus {
                            colour: root.colour
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "battery"
                    delegate: EntryWrapper {
                        BatteryStatus {
                            colour: root.colour
                        }
                    }
                }
            }
        }

        // VPN (PIA / Mullvad / IVPN) — sits with the other status icons; hover for details, click to connect/disconnect
        MaterialIcon {
            property string name: "vpn"
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: root.spacing
            animate: true
            text: Tunnel.connected || Tunnel.busy ? "vpn_key" : "vpn_key_off"
            fill: Tunnel.connected ? 1 : 0
            color: Tunnel.connected ? Colours.palette.m3primary : root.colour
            opacity: Tunnel.connected || Tunnel.busy ? 1 : 0.55

            SequentialAnimation on opacity {
                running: Tunnel.busy
                loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 500 }
                NumberAnimation { to: 1; duration: 500 }
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: Tunnel.toggle()
            }
        }

        // Claude usage — colour by limit; dot when a session needs you; hover for the card
        MaterialIcon {
            property string name: "claude"
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: root.spacing
            animate: true
            text: "asterisk"
            color: ClaudeUsage.hot >= 90 ? Colours.palette.m3error : ClaudeUsage.hot >= 70 || ClaudeUsage.waiting > 0 ? Colours.palette.m3secondary : root.colour

            StyledRect {
                visible: ClaudeUsage.waiting > 0
                implicitWidth: 7
                implicitHeight: 7
                radius: 4
                color: Colours.palette.m3secondary
                anchors { right: parent.right; top: parent.top; rightMargin: -1; topMargin: -1 }
            }
        }

        // mitch.pro GitHub — real GitHub mark tinted to the theme; dot when a deploy needs approval
        Item {
            id: ghIcon
            property string name: "mitch"
            readonly property color tint: MitchHub.needsYou ? Colours.palette.m3secondary : MitchHub.prCount > 0 || MitchHub.deployCount > 0 ? root.colour : Colours.palette.m3outline
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: root.spacing
            implicitWidth: 18
            implicitHeight: 18

            Image {
                id: ghImg
                anchors.fill: parent
                source: Qt.resolvedUrl("../../../assets/github.svg")
                sourceSize.width: 40
                sourceSize.height: 40
                smooth: true
                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1
                    colorizationColor: ghIcon.tint
                }
            }

            StyledRect {
                visible: MitchHub.needsYou
                implicitWidth: 7
                implicitHeight: 7
                radius: 4
                color: Colours.palette.m3secondary
                anchors { right: parent.right; top: parent.top; rightMargin: -1; topMargin: -1 }
            }
        }

        // recording timer — blinking red dot + elapsed mm:ss; click to stop
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: root.spacing
            visible: Recorder.running
            spacing: 0

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: "fiber_manual_record"
                fill: 1
                color: Colours.palette.m3error

                SequentialAnimation on opacity {
                    running: Recorder.running && !Recorder.paused
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 600 }
                    NumberAnimation { to: 1; duration: 600 }
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                readonly property int s: Math.floor(Recorder.elapsed)
                text: Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
                font: Tokens.font.mono.small
                color: root.colour
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: Recorder.stop()
            }
        }

    }

    component EntryWrapper: Item {
        required property var modelData
        required property int index
        property int margin: root.spacing / 2
        readonly property bool present: !root.collapsed(modelData)
        property real topGap: present && index !== root.firstPresent ? margin : 0
        property real bottomGap: present && index !== root.lastPresent ? margin : 0
        default property Item item
        property string name: modelData.id.toLowerCase()

        Layout.topMargin: Math.round(topGap)
        Layout.bottomMargin: Math.round(bottomGap)
        Layout.alignment: Qt.AlignHCenter

        implicitWidth: item?.implicitWidth ?? 0
        implicitHeight: item?.implicitHeight ?? 0

        children: item

        Behavior on topGap {
            Anim {
                type: Anim.SlowEffects
            }
        }

        Behavior on bottomGap {
            Anim {
                type: Anim.SlowEffects
            }
        }
    }
}
