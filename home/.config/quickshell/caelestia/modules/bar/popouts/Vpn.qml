pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

Flickable {
    id: flick

    implicitWidth: 320
    implicitHeight: Math.min(root.implicitHeight, 620, Screen.height > 0 ? Math.round(Screen.height * 0.7) : 100000)
    contentWidth: width
    contentHeight: root.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

    ColumnLayout {
    id: root

    spacing: Tokens.spacing.small
    width: flick.width

    property string regionQuery: ""
    readonly property var regionModel: ["auto"].concat(Pia.regions).filter(r => Pia.pretty(r).toLowerCase().indexOf(regionQuery) >= 0)

    StyledText {
        text: Pia.connected ? Tr.tr("VPN connected") : Pia.busy ? Tr.tr("VPN connecting…") : Tr.tr("VPN off")
        font: Tokens.font.title.small
    }

    StyledText {
        Layout.fillWidth: true
        elide: Text.ElideRight
        color: Colours.palette.m3onSurfaceVariant
        text: Pia.pretty(Pia.region) + "  ·  " + Pia.label + (Pia.connected && Pia.vpnIp ? "  ·  " + Pia.vpnIp : "")
    }

    StyledText {
        visible: Pia.blocked
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Colours.palette.m3error
        text: Tr.tr("Kill switch is blocking traffic until the VPN connects")
    }

    IconTextButton {
        Layout.fillWidth: true
        icon: (Pia.connected || Pia.busy) ? "vpn_key_off" : "vpn_key"
        text: (Pia.connected || Pia.busy) ? Tr.tr("Disconnect") : Tr.tr("Connect")
        onClicked: Pia.toggle()
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: Tr.tr("Protocol")
        color: Colours.palette.m3onSurfaceVariant
    }
    Flow {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small
        Repeater {
            model: [["wireguard", "WireGuard"], ["school", "OpenVPN · TCP 443"], ["auto", "OpenVPN · auto"]]
            delegate: IconTextButton {
                required property var modelData
                isToggle: true
                checked: Pia.choice === modelData[0]
                text: modelData[1]
                font: Tokens.font.label.small
                verticalPadding: Tokens.padding.small
                onClicked: modelData[0] === "wireguard" ? Pia.useWireguard() : modelData[0] === "school" ? Pia.useSchool() : Pia.useOpenvpnAuto()
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: Tr.tr("Kill switch")
        color: Colours.palette.m3onSurfaceVariant
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small
        Repeater {
            model: [["on", Tr.tr("On")], ["auto", Tr.tr("Auto")], ["off", Tr.tr("Off")]]
            delegate: IconTextButton {
                required property var modelData
                Layout.fillWidth: true
                isToggle: true
                checked: Pia.ksMode === modelData[0]
                text: modelData[1]
                onClicked: Pia.setKillswitch(modelData[0])
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: Tr.tr("Region")
        color: Colours.palette.m3onSurfaceVariant
    }
    StyledTextField {
        Layout.fillWidth: true
        placeholderText: Tr.tr("Search regions")
        leadingIcon: "search"
        onTextChanged: root.regionQuery = text.toLowerCase()
    }
    StyledRect {
        Layout.fillWidth: true
        implicitHeight: Math.min(root.regionModel.length, 6) * 36
        radius: Tokens.rounding.small
        color: Colours.tPalette.m3surfaceContainer
        clip: true

        ListView {
            id: regionList
            anchors.fill: parent
            clip: true
            model: root.regionModel

            delegate: StyledRect {
                required property var modelData
                readonly property bool on: modelData === Pia.region

                width: regionList.width
                implicitHeight: 36
                color: on ? Colours.palette.m3primaryContainer : "transparent"

                StateLayer {
                    onClicked: Pia.setRegion(modelData)
                }

                StyledText {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Tokens.padding.medium
                    anchors.rightMargin: Tokens.padding.medium
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: Pia.pretty(modelData)
                    color: parent.on ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                }
            }
        }
    }

    // ───────── Wi-Fi privacy (net-helper) ─────────
    StyledRect {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.small
        Layout.bottomMargin: Tokens.spacing.small
        implicitHeight: 1
        color: Colours.palette.m3outlineVariant
    }

    RowLayout {
        Layout.fillWidth: true
        StyledText {
            Layout.fillWidth: true
            text: Tr.tr("Wi-Fi privacy")
            font: Tokens.font.title.small
        }
        StyledText {
            visible: Privacy.busy !== "" || Privacy.note !== ""
            text: Privacy.busy !== "" ? Privacy.busy + "…" : Privacy.note
            color: Privacy.busy !== "" ? Colours.palette.m3secondary : Privacy.noteErr ? Colours.palette.m3error : Colours.palette.m3primary
            font: Tokens.font.label.small
        }
    }
    StyledText {
        visible: !Privacy.installed
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Colours.palette.m3error
        text: Tr.tr("Helper not installed (/usr/local/lib/rice/net-helper)")
    }
    StyledText {
        Layout.fillWidth: true
        elide: Text.ElideRight
        color: Colours.palette.m3onSurfaceVariant
        text: "MAC " + (Privacy.s.mac || "—") + (Privacy.s.ssid ? "  ·  " + Privacy.s.ssid : "")
        font: Tokens.font.label.small
    }

    StyledText { text: Tr.tr("MAC randomization"); color: Colours.palette.m3onSurfaceVariant; font: Tokens.font.label.small }
    Flow {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small
        Chip { text: Tr.tr("Off"); on: Privacy.s.mode === "disabled"; onClicked: Privacy.run("Applying", ["mode", "disabled"]) }
        Chip { text: Tr.tr("Per network"); on: Privacy.s.mode === "network"; onClicked: Privacy.run("Applying", ["mode", "network"]) }
        Chip { text: Tr.tr("Per session"); on: Privacy.s.mode === "once"; onClicked: Privacy.run("Applying", ["mode", "once"]) }
        Chip { text: Tr.tr("Keep vendor prefix"); on: Privacy.s.range === "nic"; onClicked: Privacy.run("Applying", ["range", Privacy.s.range === "nic" ? "full" : "nic"]) }
        Chip { visible: Privacy.s.mode === "network" && Privacy.s.ssid; text: Tr.tr("New MAC each connect"); on: Privacy.s.always; onClicked: Privacy.run("Applying", ["always", Privacy.s.ssid, Privacy.s.always ? "off" : "on"]) }
        Chip { text: Tr.tr("Rotate now"); onClicked: Privacy.run("Rotating", ["rotate"]) }
    }

    StyledText { text: Tr.tr("DHCP identity (DUID)"); color: Colours.palette.m3onSurfaceVariant; font: Tokens.font.label.small; Layout.topMargin: Tokens.spacing.small / 2 }
    Flow {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small
        Chip { text: Tr.tr("New DUID now"); onClicked: Privacy.run("Rotating DUID", ["duid"]) }
        Chip { text: Tr.tr("New every start"); on: !!Privacy.s.duidRotate; onClicked: Privacy.run("Applying", ["duid-rotate", Privacy.s.duidRotate ? "off" : "on"]) }
    }

    StyledText { text: Tr.tr("Hostname shown to Wi-Fi"); color: Colours.palette.m3onSurfaceVariant; font: Tokens.font.label.small; Layout.topMargin: Tokens.spacing.small / 2 }
    Flow {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small
        Chip { text: Tr.tr("Random"); onClicked: Privacy.run("Randomizing", ["hostname", "random"]) }
        Chip { text: Tr.tr("Announce (DHCP)"); on: !!Privacy.s.dhcpHostname; onClicked: Privacy.run("Applying", ["dhcp-hostname", Privacy.s.dhcpHostname ? "off" : "on"]) }
        Chip { text: Tr.tr("New each boot"); on: Privacy.s.bootHostname; onClicked: Privacy.run("Applying", ["boot-hostname", Privacy.s.bootHostname ? "off" : "on"]) }
        Chip { text: Tr.tr("Quiet (no mDNS/LLMNR)"); on: Privacy.s.harden; onClicked: Privacy.run("Applying", ["harden", Privacy.s.harden ? "off" : "on"]) }
    }

    component Chip: IconTextButton {
        property bool on: false
        isToggle: true
        checked: on
        font: Tokens.font.label.small
        verticalPadding: Tokens.padding.small
    }
}
}
