import QtQuick
import QtQuick.Effects

import org.mauikit.controls as Maui

Item
{
    id: control

    property url imageSource
    property url fallbackSource: "qrc:/assets/cover_64x64.svg"
    property color fallbackColor: Maui.Theme.textColor
    property int iconSizeHint: Maui.Style.iconSizes.big
    property int imageSizeHint: -1
    property int fillMode: Image.PreserveAspectFit
    property int maskRadius: 0
    property int imageWidth: -1
    property int imageHeight: -1

    readonly property alias image: _artwork.image
    readonly property alias icon: _fallbackIcon
    readonly property bool showingFallback: _fallbackIcon.visible
    readonly property real fallbackBrightness: Maui.ColorUtils.grayForColor(fallbackColor)
                                               - Maui.ColorUtils.grayForColor("#4d4d4d")

    implicitWidth: Math.max(iconSizeHint, imageSizeHint)
    implicitHeight: implicitWidth

    Maui.IconItem
    {
        id: _artwork
        anchors.fill: parent
        imageSource: control.imageSource
        imageSizeHint: control.imageSizeHint
        fillMode: control.fillMode
        maskRadius: control.maskRadius
        imageWidth: control.imageWidth
        imageHeight: control.imageHeight
    }

    Maui.Icon
    {
        id: _fallbackIcon
        anchors.centerIn: parent
        width: Math.min(parent.width, control.iconSizeHint)
        height: width
        source: control.fallbackSource
        color: control.fallbackColor
        visible: _artwork.image.status !== Image.Ready
                 || _artwork.image.implicitWidth <= 0
                 || _artwork.image.implicitHeight <= 0

        layer.enabled: visible && GraphicsInfo.api !== GraphicsInfo.Software
        layer.effect: MultiEffect
        {
            colorization: 1
            brightness: control.fallbackBrightness
            colorizationColor: control.fallbackColor
        }
    }
}
