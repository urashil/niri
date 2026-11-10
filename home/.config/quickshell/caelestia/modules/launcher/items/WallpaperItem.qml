import QtQuick
import Quickshell
import Caelestia.Config
import Caelestia.Models
import qs.components
import qs.components.effects
import qs.components.images
import qs.services

Item {
    id: root

    required property FileSystemEntry modelData
    required property ScreenState screenState

    scale: 0.5
    opacity: 0
    z: PathView.z ?? 0 // qmllint disable missing-property

    Component.onCompleted: {
        scale = Qt.binding(() => PathView.isCurrentItem ? 1 : PathView.onPath ? 0.8 : 0);
        opacity = Qt.binding(() => PathView.onPath ? 1 : 0);
    }

    implicitWidth: image.width + Tokens.padding.medium * 2
    implicitHeight: image.height + label.height + Tokens.spacing.extraSmall + Tokens.padding.large + Tokens.padding.medium

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: {
            Wallpapers.setWallpaper(root.modelData.path);
            root.screenState.launcher = false;
        }
    }

    Elevation {
        anchors.fill: image
        radius: image.radius
        opacity: root.PathView.isCurrentItem ? 1 : 0
        level: 4

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    StyledClippingRect {
        id: image

        anchors.horizontalCenter: parent.horizontalCenter
        y: Tokens.padding.large
        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.large

        implicitWidth: Tokens.sizes.launcher.wallpaperWidth
        implicitHeight: implicitWidth / 16 * 9

        MaterialIcon {
            anchors.centerIn: parent
            text: "image"
            color: Colours.tPalette.m3outline
            fontStyle: Tokens.font.icon.builders.extraLarge.scale(2).weight(Font.DemiBold).build()
        }

        CachingImage {
            anchors.fill: parent
            path: root.modelData.path
            smooth: !root.PathView.view.moving
            sourceSize: {
                const dpr = (QsWindow.window as QsWindow)?.devicePixelRatio ?? 1;
                return Qt.size(image.implicitWidth * dpr, image.implicitHeight * dpr);
            }
        }

        // light / dark this wallpaper comes up in; click: auto -> light -> dark
        StyledRect {
            id: modeBadge

            readonly property string mode: Colours.wallMode(root.modelData.path)

            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Tokens.padding.small
            visible: root.PathView.isCurrentItem || mode !== "auto"
            implicitWidth: badgeRow.implicitWidth + Tokens.padding.medium * 2
            implicitHeight: badgeRow.implicitHeight + Tokens.padding.small * 2
            radius: Tokens.rounding.full
            color: Qt.alpha(Colours.palette.m3surfaceContainerHighest, 0.85)

            StateLayer {
                radius: Tokens.rounding.full
                onClicked: Colours.cycleWallMode(root.modelData.path)
            }

            Row {
                id: badgeRow

                anchors.centerIn: parent
                spacing: Tokens.spacing.extraSmall

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modeBadge.mode === "light" ? "light_mode" : modeBadge.mode === "dark" ? "dark_mode" : "brightness_auto"
                    color: modeBadge.mode === "auto" ? Colours.palette.m3onSurfaceVariant : Colours.palette.m3primary
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modeBadge.mode === "light" ? qsTr("Light") : modeBadge.mode === "dark" ? qsTr("Dark") : qsTr("Auto")
                    font: Tokens.font.label.small
                }
            }
        }
    }

    StyledText {
        id: label

        anchors.top: image.bottom
        anchors.topMargin: Tokens.spacing.extraSmall
        anchors.horizontalCenter: parent.horizontalCenter

        width: image.width - Tokens.padding.medium * 2
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        renderType: Text.QtRendering
        text: root.modelData.relativePath
        font: Tokens.font.label.medium
    }

    Behavior on scale {
        Anim {}
    }

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }
}
