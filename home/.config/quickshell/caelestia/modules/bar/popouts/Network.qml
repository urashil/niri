pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils

// Scrolls once the list (or an expanded network) is taller than 70% of the screen, so it never runs off
// a small display.
Flickable {
    id: flick

    required property PopoutState popouts
    property alias view: root.view
    readonly property alias passwordNetwork: root.passwordNetwork

    implicitWidth: root.width
    implicitHeight: Math.min(root.implicitHeight, Screen.height > 0 ? Math.round(Screen.height * 0.7) : 100000)
    contentWidth: width
    contentHeight: root.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height

ColumnLayout {
    id: root

    readonly property PopoutState popouts: flick.popouts

    property string connectingToSsid: ""
    property string view: "wireless" // "wireless" or "ethernet"
    property var passwordNetwork: null
    property bool showPasswordDialog: false

    spacing: Tokens.spacing.small
    width: Tokens.sizes.bar.networkWidth

    // Wireless section
    StyledText {
        visible: root.view === "wireless"
        Layout.preferredHeight: visible ? implicitHeight : 0
        Layout.topMargin: visible ? Tokens.padding.medium : 0
        Layout.rightMargin: Tokens.padding.extraSmall
        text: Tr.tr("Wireless")
        font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
    }

    Toggle {
        visible: root.view === "wireless"
        Layout.preferredHeight: visible ? implicitHeight : 0
        label: Tr.trCtx("Enabled", "toggle label")
        checked: Nmcli.wifiEnabled
        toggle.onToggled: Nmcli.enableWifi(checked)
    }

    StyledText {
        visible: root.view === "wireless"
        Layout.preferredHeight: visible ? implicitHeight : 0
        Layout.topMargin: visible ? Tokens.spacing.small : 0
        Layout.rightMargin: Tokens.padding.extraSmall
        text: Tr.trN("%n network available", "%n networks available", Nmcli.networks.length) // qmllint disable missing-property
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    Repeater {
        visible: root.view === "wireless"
        model: ScriptModel {
            values: [...Nmcli.networks].sort((a, b) => {
                if (a.active !== b.active)
                    return b.active - a.active;
                return b.strength - a.strength;
            }).slice(0, 8)
        }

        ColumnLayout {
            id: networkItem

            required property Nmcli.AccessPoint modelData
            readonly property bool isConnecting: root.connectingToSsid === modelData.ssid
            readonly property bool loading: networkItem.isConnecting
            property bool expanded: false
            readonly property var rule: Privacy.ruleFor(modelData.ssid)

            visible: root.view === "wireless"
            Layout.fillWidth: true
            Layout.rightMargin: Tokens.padding.extraSmall
            spacing: Tokens.spacing.extraSmall

            opacity: 0
            scale: 0.7
            Component.onCompleted: { opacity = 1; scale = 1; }
            Behavior on opacity { Anim { type: Anim.DefaultEffects } }
            Behavior on scale { Anim {} }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: Icons.getNetworkIcon(networkItem.modelData.strength)
                    color: networkItem.modelData.active ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                }
                MaterialIcon {
                    visible: networkItem.modelData.isSecure
                    text: "lock"
                    fontStyle: Tokens.font.icon.small
                }
                StyledText {
                    Layout.leftMargin: Tokens.spacing.extraSmall
                    Layout.fillWidth: true
                    text: networkItem.modelData.ssid
                    elide: Text.ElideRight
                    font: Tokens.font.body.builders.medium.weight(networkItem.modelData.active ? Font.Medium : Font.Normal).build()
                    color: networkItem.modelData.active ? Colours.palette.m3primary : Colours.palette.m3onSurface
                    MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: networkItem.expanded = !networkItem.expanded }
                }
                MaterialIcon {
                    text: networkItem.expanded ? "expand_less" : "tune"
                    fontStyle: Tokens.font.icon.small
                    color: Colours.palette.m3onSurfaceVariant
                    MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: networkItem.expanded = !networkItem.expanded }
                }
                StyledRect {
                    implicitWidth: implicitHeight
                    implicitHeight: wirelessConnectIcon.implicitHeight + Tokens.padding.extraSmall
                    radius: Tokens.rounding.full
                    color: Qt.alpha(Colours.palette.m3primary, networkItem.modelData.active ? 1 : 0)

                    CircularIndicator { anchors.fill: parent; running: networkItem.loading }

                    StateLayer {
                        color: networkItem.modelData.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                        disabled: networkItem.loading || !Nmcli.wifiEnabled
                        onClicked: {
                            if (networkItem.modelData.active) {
                                Nmcli.disconnectFromNetwork();
                            } else {
                                root.connectingToSsid = networkItem.modelData.ssid;
                                NetworkConnection.handleConnect(networkItem.modelData, null, network => {
                                    root.passwordNetwork = network;
                                    root.showPasswordDialog = true;
                                    root.popouts.currentName = "wirelesspassword";
                                });
                            }
                        }
                    }

                    MaterialIcon {
                        id: wirelessConnectIcon
                        anchors.centerIn: parent
                        animate: true
                        text: networkItem.modelData.active ? "link_off" : "link"
                        color: networkItem.modelData.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                        opacity: networkItem.loading ? 0 : 1
                        Behavior on opacity { Anim { type: Anim.DefaultEffects } }
                    }
                }
            }

            // per-network options (click the name): MAC policy + automation (VPN / sign-in / quiet / kill switch)
            ColumnLayout {
                id: opts

                readonly property string ssid: networkItem.modelData.ssid
                readonly property var ar: Automation.rule(ssid)       // tracks Automation.rules
                function setAuto(key, val) { Automation.set(ssid, key, opts.ar[key] === val ? "" : val); }

                visible: networkItem.expanded
                Layout.fillWidth: true
                Layout.leftMargin: Tokens.padding.large
                Layout.bottomMargin: Tokens.spacing.small
                spacing: Tokens.spacing.extraSmall

                component Lbl: StyledText { color: Colours.palette.m3onSurfaceVariant; font: Tokens.font.label.small; Layout.topMargin: Tokens.spacing.extraSmall }
                component Ch: IconTextButton { isToggle: true; font: Tokens.font.label.small; verticalPadding: Tokens.padding.small }

                Lbl { text: Tr.tr("MAC address") }
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    Ch { checked: networkItem.rule.always && !networkItem.rule.override; text: Tr.tr("Random"); onClicked: Privacy.run("Applying", ["rule", opts.ssid, "random"]) }
                    Ch { checked: !networkItem.rule.always && !networkItem.rule.override; text: Tr.tr("Stable"); onClicked: Privacy.run("Applying", ["rule", opts.ssid, "stable"]) }
                }

                Lbl { text: Tr.tr("VPN on connect") }
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    Ch { checked: opts.ar.vpn === "wg"; text: Tr.tr("WireGuard"); onClicked: opts.setAuto("vpn", "wg") }
                    Ch { checked: opts.ar.vpn === "443"; text: Tunnel.methodLabel("school"); onClicked: opts.setAuto("vpn", "443") }
                    Ch { checked: opts.ar.vpn === "off"; text: Tr.tr("Off"); onClicked: opts.setAuto("vpn", "off") }
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacing.extraSmall
                    spacing: Tokens.spacing.small
                    Ch { checked: opts.ar.login; icon: "login"; text: Tr.tr("Auto sign-in"); onClicked: Automation.set(opts.ssid, "login", !opts.ar.login) }
                    Ch { checked: opts.ar.dnd; icon: "notifications_off"; text: Tr.tr("Quiet"); onClicked: Automation.set(opts.ssid, "dnd", !opts.ar.dnd) }
                }

                Lbl { text: Tr.tr("Kill switch") }
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    Ch { checked: opts.ar.ks === "on"; text: Tr.tr("On"); onClicked: opts.setAuto("ks", "on") }
                    Ch { checked: opts.ar.ks === "auto"; text: Tr.tr("Auto"); onClicked: opts.setAuto("ks", "auto") }
                    Ch { checked: opts.ar.ks === "off"; text: Tr.tr("Off"); onClicked: opts.setAuto("ks", "off") }
                }

                IconTextButton {
                    Layout.topMargin: Tokens.spacing.small
                    type: ButtonBase.Text
                    font: Tokens.font.label.small
                    verticalPadding: Tokens.padding.small
                    icon: "delete"
                    text: Tr.tr("Forget network")
                    onClicked: { Nmcli.forgetNetwork(opts.ssid, () => {}); networkItem.expanded = false; }
                }
            }
        }
    }

    StyledRect {
        visible: root.view === "wireless"
        Layout.preferredHeight: visible ? implicitHeight : 0
        Layout.topMargin: visible ? Tokens.spacing.small : 0
        Layout.fillWidth: true
        implicitHeight: rescanBtn.implicitHeight + Tokens.padding.small

        radius: Tokens.rounding.full
        color: Colours.palette.m3primaryContainer

        StateLayer {
            color: Colours.palette.m3onPrimaryContainer
            disabled: Nmcli.scanning || !Nmcli.wifiEnabled
            onClicked: Nmcli.rescanWifi()
        }

        RowLayout {
            id: rescanBtn

            anchors.centerIn: parent
            spacing: Tokens.spacing.small
            opacity: Nmcli.scanning ? 0 : 1

            MaterialIcon {
                id: scanIcon

                Layout.topMargin: Math.round(fontInfo.pointSize * 0.0575)
                animate: true
                text: "wifi_find"
                color: Colours.palette.m3onPrimaryContainer
            }

            StyledText {
                Layout.topMargin: -Math.round(scanIcon.fontInfo.pointSize * 0.0575)
                text: Tr.tr("Rescan networks")
                color: Colours.palette.m3onPrimaryContainer
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        CircularIndicator {
            anchors.centerIn: parent
            strokeWidth: Tokens.padding.extraSmall / 2
            bgColour: "transparent"
            implicitSize: parent.implicitHeight - Tokens.padding.large
            running: Nmcli.scanning
        }
    }

    // Ethernet section
    StyledText {
        visible: root.view === "ethernet"
        Layout.preferredHeight: visible ? implicitHeight : 0
        Layout.topMargin: visible ? Tokens.padding.medium : 0
        Layout.rightMargin: Tokens.padding.extraSmall
        text: Tr.tr("Ethernet")
        font: Tokens.font.body.builders.medium.weight(Font.Medium).build()
    }

    StyledText {
        visible: root.view === "ethernet"
        Layout.preferredHeight: visible ? implicitHeight : 0
        Layout.topMargin: visible ? Tokens.spacing.small : 0
        Layout.rightMargin: Tokens.padding.extraSmall
        text: Tr.trN("%n device available", "%n devices available", Nmcli.ethernetDevices.length)
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    Repeater {
        visible: root.view === "ethernet"
        model: ScriptModel {
            values: [...Nmcli.ethernetDevices].sort((a, b) => {
                if (a.connected !== b.connected)
                    return b.connected - a.connected;
                return (a.iface || "").localeCompare(b.iface || "");
            }).slice(0, 8)
        }

        RowLayout {
            id: ethernetItem

            required property var modelData
            readonly property bool loading: false

            visible: root.view === "ethernet"
            Layout.preferredHeight: visible ? implicitHeight : 0
            Layout.fillWidth: true
            Layout.rightMargin: Tokens.padding.extraSmall
            spacing: Tokens.spacing.small

            opacity: 0
            scale: 0.7

            Component.onCompleted: {
                opacity = 1;
                scale = 1;
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }

            Behavior on scale {
                Anim {}
            }

            MaterialIcon {
                text: "cable"
                color: ethernetItem.modelData.connected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            }

            StyledText {
                Layout.leftMargin: Tokens.spacing.extraSmall
                Layout.rightMargin: Tokens.spacing.extraSmall
                Layout.fillWidth: true
                text: ethernetItem.modelData.iface || Tr.trCtx("Unknown", "unknown network interface")
                elide: Text.ElideRight
                font: Tokens.font.body.builders.medium.weight(ethernetItem.modelData.connected ? Font.Medium : Font.Normal).build()
                color: ethernetItem.modelData.connected ? Colours.palette.m3primary : Colours.palette.m3onSurface
            }

            StyledRect {
                implicitWidth: implicitHeight
                implicitHeight: connectIcon.implicitHeight + Tokens.padding.extraSmall

                radius: Tokens.rounding.full
                color: Qt.alpha(Colours.palette.m3primary, ethernetItem.modelData.connected ? 1 : 0)

                CircularIndicator {
                    anchors.fill: parent
                    running: ethernetItem.loading
                }

                StateLayer {
                    color: ethernetItem.modelData.connected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface
                    disabled: ethernetItem.loading

                    onClicked: {
                        if (ethernetItem.modelData.connected && ethernetItem.modelData.connection) {
                            Nmcli.disconnectEthernet(ethernetItem.modelData.connection, () => {});
                        } else {
                            Nmcli.connectEthernet(ethernetItem.modelData.connection || "", ethernetItem.modelData.iface || "", () => {});
                        }
                    }
                }

                MaterialIcon {
                    id: connectIcon

                    anchors.centerIn: parent
                    animate: true
                    text: ethernetItem.modelData.connected ? "link_off" : "link"
                    color: ethernetItem.modelData.connected ? Colours.palette.m3onPrimary : Colours.palette.m3onSurface

                    opacity: ethernetItem.loading ? 0 : 1

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }
            }
        }
    }

    Connections {
        function onActiveChanged(): void {
            if (Nmcli.active && root.connectingToSsid === Nmcli.active.ssid) {
                root.connectingToSsid = "";
                // Close password dialog if we successfully connected
                if (root.showPasswordDialog && root.passwordNetwork && Nmcli.active.ssid === root.passwordNetwork.ssid) {
                    root.showPasswordDialog = false;
                    root.passwordNetwork = null;
                    if (root.popouts.currentName === "wirelesspassword") {
                        root.popouts.currentName = "network";
                    }
                }
            }
        }

        function onScanningChanged(): void {
            if (!Nmcli.scanning)
                scanIcon.rotation = 0;
        }

        target: Nmcli
    }

    Connections {
        function onCurrentNameChanged(): void {
            // Clear password network when leaving password dialog
            if (root.popouts.currentName !== "wirelesspassword" && root.showPasswordDialog) {
                root.showPasswordDialog = false;
                root.passwordNetwork = null;
            }
        }

        target: root.popouts
    }

    component Toggle: RowLayout {
        required property string label
        property alias checked: toggle.checked
        property alias toggle: toggle

        Layout.fillWidth: true
        Layout.rightMargin: Tokens.padding.extraSmall
        spacing: Tokens.spacing.medium

        StyledText {
            Layout.fillWidth: true
            text: parent.label
        }

        StyledSwitch {
            id: toggle
        }
    }
}
}
