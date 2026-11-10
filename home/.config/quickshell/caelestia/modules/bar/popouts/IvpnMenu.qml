pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

// The IVPN menu: everything the IVPN client can do, in the VPN popout when IVPN is the provider.
// Data and actions: services/Ivpn.qml. Connection options (protocol, port, server, Multi-Hop, IPv6, MTU) go through
// `vpnctl ivpn-set`, which keeps them and reconnects when the tunnel is up.
ColumnLayout {
    id: root

    spacing: Tokens.spacing.small

    Component.onCompleted: Ivpn.watchers++
    Component.onDestruction: Ivpn.watchers--

    property double now: Date.now()
    Timer { interval: 1000; running: Ivpn.connected; repeat: true; onTriggered: root.now = Date.now() }

    function dur(ms) {
        const s = Math.max(0, Math.floor(ms / 1000));
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60;
        return h > 0 ? h + "h " + m + "m" : m > 0 ? m + "m " + x + "s" : x + "s";
    }
    function portText(p) { return p ? p.replace(":", " ").toUpperCase() : ""; }
    readonly property int daysLeft: Ivpn.activeUntil > 0 ? Math.ceil((Ivpn.activeUntil - now) / 86400000) : -1

    // ══════════ status card ══════════
    StyledRect {
        id: card
        Layout.fillWidth: true
        implicitHeight: cardCol.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        color: Tunnel.blocked ? Colours.palette.m3errorContainer
            : Ivpn.connected ? Colours.palette.m3primaryContainer
            : Colours.tPalette.m3surfaceContainer
        readonly property color fg: Tunnel.blocked ? Colours.palette.m3onErrorContainer
            : Ivpn.connected ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface

        ColumnLayout {
            id: cardCol
            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            spacing: Tokens.spacing.small

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.medium

                StyledRect {
                    implicitWidth: 44
                    implicitHeight: 44
                    radius: Tokens.rounding.full
                    color: Ivpn.connected ? Colours.palette.m3primary : Tunnel.blocked ? Colours.palette.m3error : Colours.palette.m3secondaryContainer

                    MaterialIcon {
                        anchors.centerIn: parent
                        animate: true
                        text: Ivpn.connected ? "shield_lock" : Ivpn.paused ? "pause" : Ivpn.busy ? "sync" : Tunnel.blocked ? "block" : "shield"
                        fill: Ivpn.connected ? 1 : 0
                        fontStyle: Tokens.font.icon.medium
                        color: Ivpn.connected ? Colours.palette.m3onPrimary : Tunnel.blocked ? Colours.palette.m3onError : Colours.palette.m3onSecondaryContainer
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        font: Tokens.font.title.small
                        color: card.fg
                        text: Ivpn.vpn === "" ? Tr.tr("IVPN service not answering")
                            : Ivpn.connected ? Tr.tr("Protected")
                            : Ivpn.paused ? (Ivpn.pausedTill ? Tr.tr("Paused until %1").arg(Ivpn.pausedTill.replace(/^\S+ (\d\d:\d\d).*/, "$1")) : Tr.tr("Paused"))
                            : Ivpn.busy ? Tr.tr("Connecting…")
                            : Tunnel.blocked ? Tr.tr("Not connected · traffic blocked") : Tr.tr("Not protected")
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        color: card.fg
                        opacity: 0.85
                        text: {
                            const e = Ivpn.entry, x = Ivpn.exit;
                            if (Ivpn.connected && e)
                                return Ivpn.flag(e.cc) + " " + e.city + ", " + e.cc + (x ? "  →  " + Ivpn.flag(x.cc) + " " + x.city + ", " + x.cc : "");
                            const r = Ivpn.regionLabel(Ivpn.region);
                            return (Ivpn.exitKey ? r + "  →  " + Ivpn.regionLabel(Ivpn.exitKey) : r) + "  ·  " + Ivpn.methodLabel(Ivpn.method);
                        }
                    }
                }
            }

            // details while connected
            GridLayout {
                visible: Ivpn.connected
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Tokens.spacing.medium
                rowSpacing: 0

                Detail { fg: card.fg; k: Tr.tr("Protocol"); v: Ivpn.protocol + (Ivpn.serverPort ? " · " + root.portText(Ivpn.serverPort) : "") }
                Detail { fg: card.fg; k: Tr.tr("Uptime"); v: Ivpn.since > 0 ? root.dur(root.now - Ivpn.since) : "—" }
                Detail { fg: card.fg; k: Tr.tr("Tunnel IP"); v: Ivpn.localIp + (Ivpn.localIp6 ? " · v6" : "") }
                Detail { fg: card.fg; k: Tr.tr("Server"); v: Ivpn.serverIp }
                Detail { fg: card.fg; k: Tr.tr("DNS"); v: Ivpn.dnsLine || "—"; Layout.columnSpan: 2 }
            }

            StyledText {
                visible: Ivpn.unhealthy
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Colours.palette.m3error
                font: Tokens.font.label.small
                text: Tr.tr("No traffic through the tunnel for a while. Try reconnecting or another server.")
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.extraSmall
                spacing: Tokens.spacing.small

                IconTextButton {
                    Layout.fillWidth: true
                    icon: Ivpn.connected || Ivpn.busy ? "link_off" : Ivpn.paused ? "play_arrow" : "link"
                    text: Ivpn.connected || Ivpn.busy ? Tr.tr("Disconnect") : Ivpn.paused ? Tr.tr("Resume") : Tr.tr("Connect")
                    disabled: Ivpn.vpn === ""
                    onClicked: Ivpn.connected || Ivpn.busy ? Ivpn.disconnect() : Ivpn.paused ? Ivpn.resume() : Ivpn.connect()
                }
                IconButton {
                    visible: Ivpn.connected
                    icon: "pause"
                    type: ButtonBase.Tonal
                    isToggle: true
                    checked: root.pausePicker
                    onClicked: root.pausePicker = !root.pausePicker
                }
                IconButton {
                    visible: Ivpn.connected
                    icon: "refresh"
                    type: ButtonBase.Tonal
                    onClicked: Ivpn.reconnect()
                }
            }

            Flow {
                visible: root.pausePicker && Ivpn.connected
                Layout.fillWidth: true
                spacing: Tokens.spacing.small
                StyledText { text: Tr.tr("Pause for"); color: card.fg; font: Tokens.font.label.small; height: 28; verticalAlignment: Text.AlignVCenter }
                Repeater {
                    model: [[5, "5 m"], [15, "15 m"], [60, "1 h"], [240, "4 h"], [1440, "1 day"]]
                    delegate: Chip {
                        required property var modelData
                        text: modelData[1]
                        onClicked: { root.pausePicker = false; Ivpn.pause(modelData[0]); }
                    }
                }
            }
        }
    }
    property bool pausePicker: false

    // account + last action
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.small
        Layout.rightMargin: Tokens.padding.small
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: !Ivpn.loggedIn ? "person_off" : root.daysLeft >= 0 && root.daysLeft <= 7 ? "schedule" : "verified_user"
            color: !Ivpn.loggedIn || (root.daysLeft >= 0 && root.daysLeft <= 7) ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
        }
        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            font: Tokens.font.label.small
            color: Colours.palette.m3onSurfaceVariant
            text: !Ivpn.loggedIn ? Tr.tr("Not logged in: run `ivpn login <account id>`")
                : (Ivpn.plan || "IVPN") + (root.daysLeft >= 0 ? "  ·  " + (root.daysLeft > 0 ? Tr.tr("%1 days left").arg(root.daysLeft) : Tr.tr("expired")) : "")
        }
        CircularIndicator {
            visible: Ivpn.working !== ""
            running: visible
            implicitSize: 16
            strokeWidth: 2
            bgColour: "transparent"
        }
    }
    StyledText {
        visible: Ivpn.working !== "" || Ivpn.error !== "" || Ivpn.note !== ""
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.small
        wrapMode: Text.Wrap
        font: Tokens.font.label.small
        color: Ivpn.error !== "" ? Colours.palette.m3error : Ivpn.working !== "" ? Colours.palette.m3secondary : Colours.palette.m3primary
        text: Ivpn.error !== "" ? Ivpn.error : Ivpn.working !== "" ? Ivpn.working + "…" : Ivpn.note
    }

    // ══════════ server ══════════
    Section {
        id: serverSec
        title: Tr.tr("Server")
        icon: "public"
        summary: Ivpn.exitKey ? Ivpn.regionLabel(Ivpn.region) + " → " + Ivpn.regionLabel(Ivpn.exitKey) : Ivpn.regionLabel(Ivpn.region)
        expanded: true

        property string query: ""
        property bool countries: false
        property bool pickExit: false
        readonly property bool hop: Ivpn.exitKey !== "" || hopDraft
        property bool hopDraft: false
        readonly property bool ovpn: !Ivpn.wgMethod
        readonly property var rows: {
            const q = query.toLowerCase();
            const m = s => s.toLowerCase().indexOf(q) >= 0;
            if (countries && !hop)
                return Ivpn.countries.filter(c => !q || m(c.country) || m(c.cc)).map(c => ({
                    id: c.cc, flag: Ivpn.flag(c.cc), title: c.country,
                    sub: Ivpn.locations.filter(l => l.cc === c.cc).length + " " + Tr.tr("locations"),
                    ping: Math.min(...Ivpn.locations.filter(l => l.cc === c.cc).map(l => Ivpn.pings[l.key] || 99999)),
                    ok: Ivpn.locations.some(l => l.cc === c.cc && (ovpn ? l.ovpn : l.wg))
                }));
            let r = Ivpn.locations.filter(l => !q || m(l.city) || m(l.country) || m(l.cc) || m(l.key)).map(l => ({
                id: l.key, flag: Ivpn.flag(l.cc), title: l.city, sub: l.country + " · " + l.isp,
                ping: Ivpn.pings[l.key] || 99999, ok: ovpn ? l.ovpn : l.wg
            }));
            if (sortPing) r = r.slice().sort((a, b) => a.ping - b.ping);
            return r;
        }
        property bool sortPing: false

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            Chip {
                icon: "bolt"
                text: Tr.tr("Fastest")
                on: Ivpn.region === "auto" && !serverSec.hop
                onClicked: { serverSec.hopDraft = false; Ivpn.setExit(""); Ivpn.setRegion("auto"); }
            }
            Chip {
                text: Tr.tr("Cities")
                on: !serverSec.countries || serverSec.hop
                onClicked: serverSec.countries = false
            }
            Chip {
                text: Tr.tr("Countries")
                on: serverSec.countries && !serverSec.hop
                disabled: serverSec.hop
                onClicked: serverSec.countries = true
            }
            Item { Layout.fillWidth: true }
            IconButton {
                icon: "network_ping"
                type: ButtonBase.Text
                disabled: Ivpn.pinging
                onClicked: { Ivpn.ping(); serverSec.sortPing = true; }
            }
        }

        SwitchRow {
            label: Tr.tr("Multi-Hop")
            sub: Tr.tr("Enter through one server, leave through another")
            checked: serverSec.hop
            onToggled: on => {
                if (on) { serverSec.hopDraft = true; serverSec.pickExit = /^[a-z0-9-]+$/.test(Ivpn.region); serverSec.countries = false; }
                else { serverSec.hopDraft = false; serverSec.pickExit = false; Ivpn.setExit(""); }
            }
        }
        RowLayout {
            visible: serverSec.hop
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            Chip {
                Layout.fillWidth: true
                icon: "login"
                text: Tr.tr("Entry: %1").arg(/^[a-z0-9-]+$/.test(Ivpn.region) ? Ivpn.regionLabel(Ivpn.region) : "—")
                on: !serverSec.pickExit
                onClicked: serverSec.pickExit = false
            }
            Chip {
                Layout.fillWidth: true
                icon: "logout"
                text: Tr.tr("Exit: %1").arg(Ivpn.exitKey ? Ivpn.regionLabel(Ivpn.exitKey) : "—")
                on: serverSec.pickExit
                onClicked: serverSec.pickExit = true
            }
        }

        StyledTextField {
            Layout.fillWidth: true
            placeholderText: Tr.tr("Search %1 locations").arg(Ivpn.locations.length)
            leadingIcon: "search"
            onTextChanged: serverSec.query = text
        }

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: Math.max(1, Math.min(serverSec.rows.length, 7)) * 44
            radius: Tokens.rounding.small
            color: Colours.tPalette.m3surfaceContainer
            clip: true

            StyledText {
                visible: serverSec.rows.length === 0
                anchors.centerIn: parent
                color: Colours.palette.m3onSurfaceVariant
                text: Ivpn.locations.length === 0 ? Tr.tr("Loading servers…") : Tr.tr("No match")
            }

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                model: serverSec.rows
                boundsBehavior: Flickable.StopAtBounds

                delegate: StyledRect {
                    id: row
                    required property var modelData
                    readonly property bool sel: serverSec.pickExit ? modelData.id === Ivpn.exitKey : modelData.id === Ivpn.region
                    readonly property bool live: Ivpn.connected && Ivpn.entry && (modelData.id === Ivpn.entry.key || modelData.id === Ivpn.entry.cc)

                    width: list.width
                    implicitHeight: 44
                    color: sel ? Colours.palette.m3primaryContainer : "transparent"
                    opacity: modelData.ok ? 1 : 0.45

                    StateLayer {
                        disabled: !row.modelData.ok
                        onClicked: {
                            if (!serverSec.hop) { Ivpn.setRegion(row.modelData.id); return; }
                            if (serverSec.pickExit) {
                                if (row.modelData.id === Ivpn.region) return;
                                Ivpn.setExit(row.modelData.id);
                            } else {
                                if (row.modelData.id === Ivpn.exitKey) return;
                                Ivpn.setRegion(row.modelData.id);
                                serverSec.pickExit = Ivpn.exitKey === "";
                            }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.padding.medium
                        anchors.rightMargin: Tokens.padding.medium
                        spacing: Tokens.spacing.medium

                        StyledText { text: row.modelData.flag; font: Tokens.font.body.large }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: row.modelData.title
                                color: row.sel ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurface
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: row.modelData.ok ? row.modelData.sub : Tr.tr("no %1 servers here").arg(serverSec.ovpn ? "OpenVPN" : "WireGuard")
                                font: Tokens.font.label.small
                                color: row.sel ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
                            }
                        }
                        MaterialIcon {
                            visible: row.live
                            text: "check_circle"
                            fill: 1
                            color: Colours.palette.m3primary
                        }
                        StyledText {
                            visible: row.modelData.ping < 99999
                            text: row.modelData.ping + " ms"
                            font: Tokens.font.label.small
                            color: row.modelData.ping < 60 ? Colours.palette.m3primary : row.modelData.ping < 150 ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3error
                        }
                    }
                }
            }
        }
        StyledText {
            visible: Ivpn.pinging
            font: Tokens.font.label.small
            color: Colours.palette.m3secondary
            text: Tr.tr("Pinging every server…")
        }
    }

    // ══════════ protocol ══════════
    Section {
        id: protoSec
        title: Tr.tr("Protocol")
        icon: "swap_calls"
        summary: Ivpn.methodLabel(Ivpn.method) + " · " + (Ivpn.port ? root.portText(Ivpn.port) : Ivpn.defaultPort(Ivpn.method))
        expanded: true

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Tokens.spacing.small
            rowSpacing: Tokens.spacing.small

            Repeater {
                model: Ivpn.methods
                delegate: StyledRect {
                    id: tile
                    required property var modelData
                    readonly property bool on: Ivpn.method === modelData.id
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    implicitHeight: tileCol.implicitHeight + Tokens.padding.medium * 2
                    radius: Tokens.rounding.medium
                    color: on ? Colours.palette.m3secondaryContainer : Colours.tPalette.m3surfaceContainer
                    border.width: on ? 0 : 1
                    border.color: Colours.palette.m3outlineVariant

                    StateLayer { onClicked: if (!tile.on) Ivpn.setMethod(tile.modelData.id) }
                    ColumnLayout {
                        id: tileCol
                        anchors.fill: parent
                        anchors.margins: Tokens.padding.medium
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: tile.modelData.label
                            font: Tokens.font.body.small
                            color: tile.on ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                        }
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: tile.modelData.sub
                            font: Tokens.font.label.small
                            color: Colours.palette.m3onSurfaceVariant
                        }
                    }
                }
            }
        }

        Caption { visible: Ivpn.portsFor(Ivpn.method).length > 0; text: Tr.tr("Port") }
        Flow {
            visible: Ivpn.portsFor(Ivpn.method).length > 0
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            Repeater {
                model: Ivpn.portsFor(Ivpn.method)
                delegate: Chip {
                    required property string modelData
                    text: modelData === "" ? Ivpn.defaultPort(Ivpn.method) + " " + Tr.tr("(default)") : root.portText(modelData)
                    on: Ivpn.port === modelData
                    onClicked: Ivpn.set({ port: modelData }, Tr.tr("Port %1").arg(text))
                }
            }
        }
        Caption { visible: Ivpn.exitKey !== "" && !Ivpn.method.startsWith("stealth"); text: Tr.tr("Multi-Hop uses its own ports; only the TCP/UDP choice applies.") }

        SwitchRow {
            visible: Ivpn.wgMethod
            label: Tr.tr("IPv6 inside the tunnel")
            sub: Tr.tr("WireGuard only")
            checked: Ivpn.ipv6
            onToggled: on => Ivpn.set({ ipv6: on }, on ? Tr.tr("IPv6 on") : Tr.tr("IPv6 off"))
        }
        RowLayout {
            visible: Ivpn.wgMethod
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            StyledText { Layout.fillWidth: true; text: Tr.tr("MTU"); }
            Repeater {
                model: [[0, Tr.tr("Auto")], [1380, "1380"], [1280, "1280"]]
                delegate: Chip {
                    required property var modelData
                    text: modelData[1]
                    on: Ivpn.mtu === modelData[0]
                    onClicked: Ivpn.set({ mtu: modelData[0] }, Tr.tr("MTU %1").arg(modelData[1]))
                }
            }
        }
    }

    // ══════════ kill switch / firewall ══════════
    Section {
        title: Tr.tr("Kill switch & firewall")
        icon: "local_fire_department"
        summary: Tunnel.ksMode === "on" ? Tr.tr("Always on") : Tunnel.ksMode === "auto" ? Tr.tr("With VPN") : Tr.tr("Off")

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            Repeater {
                model: [["on", Tr.tr("Always on")], ["auto", Tr.tr("With VPN")], ["off", Tr.tr("Off")]]
                delegate: Chip {
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData[1]
                    on: Tunnel.ksMode === modelData[0]
                    onClicked: Tunnel.setKillswitch(modelData[0])
                }
            }
        }
        Caption {
            text: Tunnel.ksMode === "on" ? Tr.tr("Nothing leaves outside the VPN, even disconnected or before login (persistent firewall).")
                : Tunnel.ksMode === "auto" ? Tr.tr("The firewall is up while a connection is up or being made, so a drop doesn't leak.")
                : Tr.tr("No firewall: a dropped tunnel falls back to the open network.")
        }
        SwitchRow {
            label: Tr.tr("Allow LAN")
            sub: Tr.tr("Printers, NAS, the router page")
            checked: Ivpn.fwAllowLan
            onToggled: on => Ivpn.ivpn(["firewall", on ? "-lan_allow" : "-lan_block"], on ? Tr.tr("LAN allowed") : Tr.tr("LAN blocked"))
        }
        SwitchRow {
            label: Tr.tr("Allow IVPN servers")
            sub: Tr.tr("Lets the client reach IVPN while blocked")
            checked: Ivpn.fwAllowIvpn
            onToggled: on => Ivpn.ivpn(["firewall", on ? "-ivpn_access_allow" : "-ivpn_access_block"], Tr.tr("IVPN access"))
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            StyledTextField {
                id: exc
                Layout.fillWidth: true
                placeholderText: Tr.tr("Always allow: IPs / CIDRs")
                text: Ivpn.fwExceptions
            }
            IconButton {
                icon: "check"
                type: ButtonBase.Tonal
                onClicked: Ivpn.ivpn(["firewall", "-exceptions", exc.text.trim()], Tr.tr("Firewall exceptions"))
            }
        }
    }

    // ══════════ DNS & AntiTracker ══════════
    Section {
        title: Tr.tr("DNS & AntiTracker")
        icon: "dns"
        summary: Ivpn.atEnabled ? (Ivpn.atHardcore ? Tr.tr("AntiTracker hardcore") : Tr.tr("AntiTracker")) + (Ivpn.atList ? " · " + Ivpn.atList : "")
            : Ivpn.customDns ? Ivpn.customDns : Tr.tr("IVPN DNS")

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            Repeater {
                model: [["off", Tr.tr("Off")], ["on", Tr.tr("AntiTracker")], ["hardcore", Tr.tr("Hardcore")]]
                delegate: Chip {
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData[1]
                    on: modelData[0] === "off" ? !Ivpn.atEnabled : modelData[0] === "hardcore" ? Ivpn.atHardcore : Ivpn.atEnabled && !Ivpn.atHardcore
                    onClicked: Ivpn.setAntitracker(modelData[0])
                }
            }
        }
        Caption { text: Tr.tr("AntiTracker blocks ads, trackers and malware at DNS. Hardcore also blocks Google and Facebook domains.") }
        Caption { visible: Ivpn.atEnabled && Ivpn.blocklists.length > 0; text: Tr.tr("Block list") }
        Flow {
            visible: Ivpn.atEnabled && Ivpn.blocklists.length > 0
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            Repeater {
                model: Ivpn.blocklists
                delegate: Chip {
                    required property var modelData
                    text: modelData.details
                    on: (Ivpn.atList || "Basic") === modelData.name
                    onClicked: Ivpn.setAntitracker(Ivpn.atHardcore ? "hardcore" : "on", modelData.name)
                }
            }
        }

        Caption { text: Ivpn.atEnabled ? Tr.tr("Custom DNS (ignored while AntiTracker is on)") : Tr.tr("Custom DNS") }
        StyledTextField {
            id: dnsIp
            Layout.fillWidth: true
            placeholderText: Tr.tr("Server IP, e.g. 9.9.9.9")
            validate: /^[0-9a-fA-F:.]+$/
        }
        StyledTextField {
            id: dnsDoh
            Layout.fillWidth: true
            placeholderText: Tr.tr("DNS-over-HTTPS URL (optional)")
            validate: /^https:\/\/\S+$/
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
                text: Tr.tr("Now: %1").arg(Ivpn.customDns || Tr.tr("IVPN's own"))
            }
            TextButton {
                text: Tr.tr("Reset")
                type: ButtonBase.Text
                onClicked: Ivpn.setDns("")
            }
            TextButton {
                text: Tr.tr("Use")
                disabled: !dnsIp.text || !dnsIp.valid || !dnsDoh.valid
                onClicked: Ivpn.setDns(dnsIp.text.trim(), dnsDoh.text.trim())
            }
        }
    }

    // ══════════ split tunnel ══════════
    Section {
        title: Tr.tr("Split tunnel")
        icon: "call_split"
        summary: !Ivpn.splitOn ? Tr.tr("Off") : Ivpn.splitInverse ? Tr.tr("Only chosen apps use the VPN") : Tr.tr("Chosen apps skip the VPN")

        SwitchRow {
            label: Tr.tr("Split tunnel")
            checked: Ivpn.splitOn
            onToggled: on => Ivpn.ivpn(["splittun", on ? "-on" : "-off"], on ? Tr.tr("Split tunnel on") : Tr.tr("Split tunnel off"))
        }
        SwitchRow {
            visible: Ivpn.splitOn
            label: Tr.tr("Inverse")
            sub: Tr.tr("Only apps launched here use the VPN; everything else goes direct")
            checked: Ivpn.splitInverse
            onToggled: on => Ivpn.ivpn(["splittun", on ? "-inverse_on" : "-inverse_off"], Tr.tr("Inverse mode"))
        }
        RowLayout {
            visible: Ivpn.splitOn
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            StyledTextField {
                id: launch
                Layout.fillWidth: true
                placeholderText: Ivpn.splitInverse ? Tr.tr("Command to run through the VPN") : Tr.tr("Command to run outside the VPN")
                leadingIcon: "terminal"
                onAccepted: launchBtn.clicked()
            }
            IconButton {
                id: launchBtn
                icon: "play_arrow"
                type: ButtonBase.Tonal
                disabled: launch.text.trim() === ""
                onClicked: {
                    Quickshell.execDetached(["ivpn", "exclude"].concat(launch.text.trim().split(/\s+/)));
                    launch.text = "";
                    Ivpn.note = Tr.tr("Launched in the split tunnel");
                }
            }
        }
        Repeater {
            model: Ivpn.splitApps
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    font: Tokens.font.label.small
                    text: modelData.cmd + "  ·  pid " + modelData.pid
                }
                IconButton {
                    icon: "close"
                    type: ButtonBase.Text
                    onClicked: Ivpn.ivpn(["splittun", "-appremove", modelData.pid], Tr.tr("Removed from split tunnel"))
                }
            }
        }
    }

    // ══════════ trusted Wi-Fi ══════════
    Section {
        title: Tr.tr("Trusted Wi-Fi")
        icon: "wifi_lock"
        summary: !Ivpn.wifiControl ? Tr.tr("Off") : Ivpn.wifiNetwork ? Ivpn.wifiNetwork + " · " + (Ivpn.wifiNetworks[Ivpn.wifiNetwork] || Tr.tr("no status")) : Tr.tr("On")

        SwitchRow {
            label: Tr.tr("Act on trusted / untrusted networks")
            sub: Tr.tr("IVPN's own rules; the Network menu's per-network rules still run too")
            checked: Ivpn.wifiControl
            onToggled: on => Ivpn.ivpn(["wifi", "-trusted_control", on ? "on" : "off"], Tr.tr("Wi-Fi control"))
        }
        ColumnLayout {
            visible: Ivpn.wifiControl
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            Caption { visible: Ivpn.wifiNetwork !== ""; text: Tr.tr("This network (%1)").arg(Ivpn.wifiNetwork) }
            RowLayout {
                visible: Ivpn.wifiNetwork !== ""
                Layout.fillWidth: true
                spacing: Tokens.spacing.small
                Repeater {
                    model: [["trusted", Tr.tr("Trusted")], ["untrusted", Tr.tr("Untrusted")], ["none", Tr.tr("No status")]]
                    delegate: Chip {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData[1]
                        on: (Ivpn.wifiNetworks[Ivpn.wifiNetwork] || "none") === modelData[0]
                        onClicked: Ivpn.ivpn(["wifi", "-set_trusted_network", Ivpn.wifiNetwork + ":" + modelData[0]], Ivpn.wifiNetwork + " " + modelData[1].toLowerCase())
                    }
                }
            }
            Caption { text: Tr.tr("Networks without a status") }
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small
                Repeater {
                    model: [["trusted", Tr.tr("Trusted")], ["untrusted", Tr.tr("Untrusted")], ["none", Tr.tr("Nothing")]]
                    delegate: Chip {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData[1]
                        on: Ivpn.wifiDefault === modelData[0]
                        onClicked: Ivpn.ivpn(["wifi", "-default_trust_status", modelData[0]], Tr.tr("Default trust"))
                    }
                }
            }
            Caption { text: Tr.tr("On untrusted networks") }
            SwitchRow { label: Tr.tr("Connect the VPN"); checked: Ivpn.wifiUntrustedConnect; onToggled: on => root.wifiAction("untrusted_connect_vpn", on) }
            SwitchRow { label: Tr.tr("Turn the firewall on"); checked: Ivpn.wifiUntrustedFirewall; onToggled: on => root.wifiAction("untrusted_enable_firewall", on) }
            SwitchRow { label: Tr.tr("Block LAN"); checked: Ivpn.wifiUntrustedBlockLan; onToggled: on => root.wifiAction("untrusted_block_lan", on) }
            Caption { text: Tr.tr("On trusted networks") }
            SwitchRow { label: Tr.tr("Disconnect the VPN"); checked: Ivpn.wifiTrustedDisconnect; onToggled: on => root.wifiAction("trusted_disconnect_vpn", on) }
            SwitchRow { label: Tr.tr("Turn the firewall off"); checked: Ivpn.wifiTrustedFirewallOff; onToggled: on => root.wifiAction("trusted_disable_firewall", on) }
        }
    }
    function wifiAction(a, on) { Ivpn.ivpn(["wifi", "-set_trusted_action", a + ":" + (on ? "on" : "off")], Tr.tr("Wi-Fi action")); }

    // ══════════ advanced ══════════
    Section {
        title: Tr.tr("Advanced")
        icon: "tune"
        summary: Tr.tr("Keys rotate every %1 d").arg(Ivpn.keyRotationDays)

        SwitchRow {
            label: Tr.tr("Connect when the IVPN service starts")
            sub: Tr.tr("At boot, before you log in (the rice's own autoconnect runs at login)")
            checked: Ivpn.autoconnectLaunch
            onToggled: on => Ivpn.ivpn(["autoconnect", "-on_launch", on ? "on" : "off"], Tr.tr("Autoconnect"))
        }
        Caption { text: Tr.tr("WireGuard key rotation") }
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            Repeater {
                model: [1, 3, 7, 14, 30]
                delegate: Chip {
                    required property int modelData
                    Layout.fillWidth: true
                    text: modelData + " d"
                    on: Ivpn.keyRotationDays === modelData
                    onClicked: Ivpn.ivpn(["wgkeys", "-rotation_interval", String(modelData)], Tr.tr("Key rotation"))
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font: Tokens.font.label.small
                color: Colours.palette.m3onSurfaceVariant
                text: Tr.tr("Generated %1").arg(Ivpn.keyGenerated.replace(/:\d\d [+-]\d{4}.*/, "") || "—")
                    + (Ivpn.quantumResistant ? "  ·  " + Tr.tr("quantum resistant") : "")
            }
            TextButton {
                text: Tr.tr("New keys")
                type: ButtonBase.Tonal
                onClicked: Ivpn.ivpn(["wgkeys", "-regenerate"], Tr.tr("New WireGuard keys"))
            }
        }
    }

    // ───────── pieces ─────────
    component Caption: StyledText {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.extraSmall
        wrapMode: Text.Wrap
        font: Tokens.font.label.small
        color: Colours.palette.m3onSurfaceVariant
    }

    component Detail: ColumnLayout {
        id: det
        property string k
        property string v
        property color fg: Colours.palette.m3onSurface
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        spacing: 0
        StyledText { text: det.k; font: Tokens.font.label.small; color: det.fg; opacity: 0.7 }
        StyledText { Layout.fillWidth: true; elide: Text.ElideRight; text: det.v; color: det.fg; font: Tokens.font.body.small }
    }

    component Chip: IconTextButton {
        property bool on: false
        isToggle: true
        checked: on
        font: Tokens.font.label.small
        verticalPadding: Tokens.padding.small
    }

    component SwitchRow: RowLayout {
        id: sr
        required property string label
        property string sub: ""
        property bool checked
        signal toggled(bool on)
        Layout.fillWidth: true
        Layout.rightMargin: Tokens.padding.extraSmall
        spacing: Tokens.spacing.medium

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText { Layout.fillWidth: true; text: sr.label; wrapMode: Text.Wrap }
            StyledText { visible: sr.sub !== ""; Layout.fillWidth: true; text: sr.sub; wrapMode: Text.Wrap; font: Tokens.font.label.small; color: Colours.palette.m3onSurfaceVariant }
        }
        StyledSwitch {
            checked: sr.checked
            onClicked: sr.toggled(checked)
        }
    }

    // a collapsible block: header (icon, title, current value), children below when open
    component Section: ColumnLayout {
        id: sec
        required property string title
        property string icon
        property string summary
        property bool expanded: false
        default property alias content: body.data

        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.small
        spacing: Tokens.spacing.small

        StyledRect {
            Layout.fillWidth: true
            implicitHeight: head.implicitHeight + Tokens.padding.medium * 2
            radius: Tokens.rounding.medium
            color: Colours.tPalette.m3surfaceContainer

            StateLayer { onClicked: sec.expanded = !sec.expanded }
            RowLayout {
                id: head
                anchors.fill: parent
                anchors.leftMargin: Tokens.padding.medium
                anchors.rightMargin: Tokens.padding.medium
                spacing: Tokens.spacing.medium

                MaterialIcon { text: sec.icon; color: Colours.palette.m3primary }
                StyledText { text: sec.title; font: Tokens.font.body.medium }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    text: sec.summary
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurfaceVariant
                }
                MaterialIcon {
                    text: "expand_more"
                    rotation: sec.expanded ? 180 : 0
                    Behavior on rotation { Anim {} }
                }
            }
        }

        ColumnLayout {
            id: body
            visible: sec.expanded
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            Layout.rightMargin: Tokens.padding.small
            spacing: Tokens.spacing.small
        }
    }
}
