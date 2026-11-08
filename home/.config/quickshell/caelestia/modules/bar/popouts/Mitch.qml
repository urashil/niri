pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services

ColumnLayout {
    id: root

    spacing: Tokens.spacing.small
    width: 330

    RowLayout {
        Layout.fillWidth: true
        StyledText {
            Layout.fillWidth: true
            text: "mitch.pro"
            font: Tokens.font.title.small
        }
        IconTextButton {
            type: ButtonBase.Text
            text: Tr.tr("Repo")
            icon: "open_in_new"
            onClicked: MitchHub.open(MitchHub.repoUrl)
        }
    }

    StyledText {
        visible: MitchHub.error !== ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Colours.palette.m3error
        text: "GitHub: " + MitchHub.error
    }

    StyledText {
        visible: MitchHub.deployCount > 0
        text: Tr.tr("Deploys waiting on you")
        color: Colours.palette.m3onSurfaceVariant
    }
    Repeater {
        model: MitchHub.deploys
        delegate: StyledRect {
            id: drow
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: dcol.implicitHeight + Tokens.padding.medium
            radius: Tokens.rounding.medium
            color: Colours.tPalette.m3surfaceContainer

            ColumnLayout {
                id: dcol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.medium
                spacing: Tokens.spacing.small / 2

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: drow.modelData.env + "  ·  " + drow.modelData.branch
                    font: Tokens.font.body.small
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: Colours.palette.m3onSurfaceVariant
                    text: drow.modelData.title || drow.modelData.name || ""
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    IconTextButton {
                        visible: drow.modelData.canApprove
                        type: ButtonBase.Text
                        text: Tr.tr("Approve")
                        icon: "check"
                        onClicked: MitchHub.approve(drow.modelData.run_id, drow.modelData.env_id)
                    }
                    Item { Layout.fillWidth: true }
                    IconTextButton {
                        type: ButtonBase.Text
                        text: Tr.tr("View")
                        icon: "open_in_new"
                        onClicked: MitchHub.open(drow.modelData.url)
                    }
                }
            }
        }
    }

    StyledText {
        visible: MitchHub.failedRuns.length > 0
        Layout.topMargin: Tokens.spacing.small
        text: Tr.tr("Recent failures")
        color: Colours.palette.m3error
    }
    Repeater {
        model: MitchHub.failedRuns.slice(0, 4)
        delegate: StyledRect {
            id: frow
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: fcol.implicitHeight + Tokens.padding.medium
            radius: Tokens.rounding.medium
            color: Colours.tPalette.m3surfaceContainer

            StateLayer {
                radius: Tokens.rounding.medium
                onClicked: MitchHub.open(frow.modelData.url)
            }

            ColumnLayout {
                id: fcol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.medium
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: frow.modelData.name + "  ·  " + frow.modelData.conclusion
                        color: Colours.palette.m3error
                        font: Tokens.font.body.small
                    }
                    MaterialIcon {
                        text: "close"
                        color: Colours.palette.m3onSurfaceVariant
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: MitchHub.dismiss(frow.modelData.id)
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: Colours.palette.m3onSurfaceVariant
                    text: frow.modelData.branch + (frow.modelData.title ? "  ·  " + frow.modelData.title : "") + "  ·  " + MitchHub.ago(frow.modelData.at)
                    font: Tokens.font.body.small
                }
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: Tr.tr("Open PRs") + (MitchHub.prCount > 0 ? "  (" + MitchHub.prCount + ")" : "")
        color: Colours.palette.m3onSurfaceVariant
    }
    StyledText {
        visible: MitchHub.loaded && MitchHub.prCount === 0 && MitchHub.error === ""
        color: Colours.palette.m3onSurfaceVariant
        text: Tr.tr("No open pull requests.")
    }
    Repeater {
        model: MitchHub.prs
        delegate: StyledRect {
            id: prow
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: pcol.implicitHeight + Tokens.padding.medium
            radius: Tokens.rounding.medium
            color: Colours.tPalette.m3surfaceContainer

            StateLayer {
                radius: Tokens.rounding.medium
                onClicked: MitchHub.open(prow.modelData.url)
            }

            ColumnLayout {
                id: pcol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.medium
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    StyledText {
                        text: "#" + prow.modelData.number
                        color: Colours.palette.m3primary
                        font: Tokens.font.body.small
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: prow.modelData.title
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: Colours.palette.m3onSurfaceVariant
                    text: (prow.modelData.author ? prow.modelData.author.login : "?") + "  ·  " + MitchHub.ago(prow.modelData.createdAt)
                    font: Tokens.font.body.small
                }
            }
        }
    }
}
