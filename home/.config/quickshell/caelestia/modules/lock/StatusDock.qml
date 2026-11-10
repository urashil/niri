pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services

// Lock screen right column: this month's calendar and connection status (replaces the notification dock).
ColumnLayout {
    id: root

    anchors.fill: parent
    anchors.margins: Tokens.padding.large
    spacing: Tokens.spacing.medium

    StyledText {
        Layout.fillWidth: true
        text: Qt.locale().toString(new Date(grid.year, grid.month, 1), "MMMM yyyy")
        color: Colours.palette.m3outline
        font: Tokens.font.mono.builders.small.weight(Font.Medium).build()
        elide: Text.ElideRight
    }

    DayOfWeekRow {
        Layout.fillWidth: true
        locale: grid.locale

        delegate: StyledText {
            required property var model

            horizontalAlignment: Text.AlignHCenter
            text: model.shortName
            font: Tokens.font.body.builders.small.weight(Font.Medium).build()
            color: (model.day === 0 || model.day === 6) ? Colours.palette.m3tertiary : Colours.palette.m3onSurface
        }
    }

    MonthGrid {
        id: grid

        readonly property date now: Time.date

        Layout.fillWidth: true
        month: now.getMonth()
        year: now.getFullYear()
        locale: Qt.locale()
        spacing: 3

        delegate: StyledRect {
            id: day

            required property var model

            implicitHeight: dayText.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.full
            color: model.today ? Colours.palette.m3primary : "transparent"

            StyledText {
                id: dayText

                anchors.centerIn: parent
                text: grid.locale.toString(day.model.day)
                font: Tokens.font.body.small
                opacity: day.model.month === grid.month ? 1 : 0.35
                color: {
                    if (day.model.today)
                        return Colours.palette.m3onPrimary;
                    const d = day.model.date.getDay();
                    return d === 0 || d === 6 ? Colours.palette.m3tertiary : Colours.palette.m3onSurfaceVariant;
                }
            }
        }
    }

    Item {
        Layout.fillHeight: true
    }

    StyledRect {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Colours.palette.m3outlineVariant
    }

    Row_ {
        icon: Tunnel.connected ? "vpn_lock" : "vpn_key_off"
        accent: Tunnel.connected ? Colours.palette.m3primary : Tunnel.blocked ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
        label: Tr.tr("VPN")
        value: Tunnel.connected ? Tunnel.pretty(Tunnel.region) + " · " + Tunnel.label : Tunnel.busy ? Tr.tr("Connecting…") : Tr.tr("Off")
    }

    Row_ {
        icon: Tunnel.blocked ? "block" : "shield"
        accent: Tunnel.blocked ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
        label: Tr.tr("Kill switch")
        value: Tunnel.blocked ? Tr.tr("Blocking") : Tunnel.ksMode === "on" ? Tr.tr("On") : Tunnel.ksMode === "auto" ? Tr.tr("Auto") : Tr.tr("Off")
    }

    Row_ {
        icon: Nmcli.activeEthernet ? "cable" : Nmcli.active ? "wifi" : "wifi_off"
        accent: Colours.palette.m3onSurfaceVariant
        label: Tr.tr("Network")
        value: Nmcli.activeEthernet ? Tr.tr("Ethernet") : Nmcli.active ? Nmcli.active.ssid : Tr.tr("Offline")
    }

    component Row_: RowLayout {
        property string icon
        property color accent
        property string label
        property string value

        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        MaterialIcon {
            text: parent.icon
            color: parent.accent
        }
        StyledText {
            text: parent.label
            color: Colours.palette.m3onSurfaceVariant
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: parent.value
        }
    }
}
