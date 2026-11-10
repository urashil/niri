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

    Component.onCompleted: MitchHub.watchers++
    Component.onDestruction: MitchHub.watchers--

    RowLayout {
        Layout.fillWidth: true
        StyledText {
            Layout.fillWidth: true
            text: "mitch.pro"
            font: Tokens.font.title.small
        }
        StyledText {
            text: MitchHub.fetching && !MitchHub.loaded ? Tr.tr("loading…")
                : MitchHub.lastUpdate > 0 ? MitchHub.ago(new Date(MitchHub.lastUpdate).toISOString()) : ""
            color: Colours.palette.m3outline
            font: Tokens.font.label.small
        }
        MaterialIcon {
            text: "refresh"
            color: MitchHub.fetching ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            RotationAnimation on rotation {
                running: MitchHub.fetching
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 900
                onRunningChanged: if (!running) parent.rotation = 0
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: MitchHub.refresh()
            }
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
        visible: MitchHub.actionError !== ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Colours.palette.m3error
        text: MitchHub.actionError
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
                        enabled: !MitchHub.busyIds[drow.modelData.run_id]
                        type: ButtonBase.Text
                        text: MitchHub.busyIds[drow.modelData.run_id] ? Tr.tr("Approving…") : Tr.tr("Approve")
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
        visible: MitchHub.activeRuns.length > 0
        Layout.topMargin: Tokens.spacing.small
        text: Tr.tr("Running")
        color: Colours.palette.m3primary
    }
    Repeater {
        model: MitchHub.activeRuns.slice(0, 5)
        delegate: StyledRect {
            id: rrow
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: rcol.implicitHeight + Tokens.padding.medium
            radius: Tokens.rounding.medium
            color: Colours.tPalette.m3surfaceContainer

            StateLayer {
                radius: Tokens.rounding.medium
                onClicked: MitchHub.open(rrow.modelData.url)
            }

            ColumnLayout {
                id: rcol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.padding.medium
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small
                    MaterialIcon {
                        text: rrow.modelData.status === "in_progress" ? "progress_activity" : "schedule"
                        color: Colours.palette.m3primary
                        RotationAnimation on rotation {
                            running: rrow.modelData.status === "in_progress"
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 1200
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: rrow.modelData.name
                        font: Tokens.font.body.small
                    }
                    StyledText {
                        text: rrow.modelData.status === "in_progress" ? MitchHub.dur(rrow.modelData.started) : rrow.modelData.status
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                    MaterialIcon {
                        text: "stop_circle"
                        color: MitchHub.busyIds[rrow.modelData.id] ? Colours.palette.m3outline : Colours.palette.m3onSurfaceVariant
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            enabled: !MitchHub.busyIds[rrow.modelData.id]
                            onClicked: MitchHub.cancel(rrow.modelData.id)
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: Colours.palette.m3onSurfaceVariant
                    text: rrow.modelData.branch + (rrow.modelData.title ? "  ·  " + rrow.modelData.title : "")
                    font: Tokens.font.body.small
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
                        text: "replay"
                        color: MitchHub.busyIds[frow.modelData.id] ? Colours.palette.m3outline : Colours.palette.m3onSurfaceVariant
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            enabled: !MitchHub.busyIds[frow.modelData.id]
                            onClicked: MitchHub.rerun(frow.modelData.id)
                        }
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
        text: Tr.tr("Open PRs") + (MitchHub.prCount > 0 ? "  (" + MitchHub.prCount + ")  ·  click to review" : "")
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
                onClicked: MitchHub.review(prow.modelData.number)
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
                    StyledRect {
                        visible: prow.modelData.checks !== ""
                        implicitWidth: 8
                        implicitHeight: 8
                        radius: 4
                        color: prow.modelData.checks === "fail" ? Colours.palette.m3error
                             : prow.modelData.checks === "pending" ? Colours.palette.m3tertiary : Colours.palette.m3primary
                    }
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
                    MaterialIcon {
                        text: "open_in_new"
                        color: Colours.palette.m3onSurfaceVariant
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: MitchHub.open(prow.modelData.url)
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: Colours.palette.m3onSurfaceVariant
                    text: (prow.modelData.author ? prow.modelData.author.login : "?") + "  ·  " + (prow.modelData.isDraft ? Tr.tr("draft") + "  ·  " : "")
                          + (prow.modelData.reviewDecision === "APPROVED" ? Tr.tr("approved") + "  ·  " : prow.modelData.reviewDecision === "CHANGES_REQUESTED" ? Tr.tr("changes requested") + "  ·  " : "")
                          + Tr.tr("updated ") + MitchHub.ago(prow.modelData.updatedAt || prow.modelData.createdAt)
                    font: Tokens.font.body.small
                }
            }
        }
    }
}
