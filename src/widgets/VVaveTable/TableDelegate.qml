import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.mauikit.controls as Maui

import ".."

Maui.ListBrowserDelegate
{
    id: control

    property bool number : false
    property bool coverArt : false

    readonly property string artist : String(model.artist || "").trim()
    readonly property string album : String(model.album || "").trim()
    readonly property string title : model.title
    readonly property url url : model.url
    readonly property int track : model.track

    property bool sameAlbum : false
    maskRadius: Maui.Style.radiusV

    isCurrentItem: ListView.isCurrentItem || checked
    draggable: true
    iconSource: "qrc:/assets/cover_32x32.svg"
    template.iconComponent: ArtworkItem
    {
        fallbackSource: "qrc:/assets/cover_32x32.svg"
        imageSource: control.imageSource
        fallbackColor: Maui.ColorUtils.tintWithAlpha(control.effectiveForegroundColor, Maui.Theme.highlightColor, 0.2)
        iconSizeHint: control.iconSizeHint
        maskRadius: control.maskRadius
    }

    label1.text: control.number ? control.track + ". " + control.title :  control.title
    label2.text: control.artist + " • " + control.album
    label2.visible: control.coverArt ? !control.sameAlbum : true

    iconVisible: !control.sameAlbum && control.coverArt
    imageSource: coverArt ? "image://artwork/album:" + encodeURIComponent(String(control.artist || "")) + ":" + encodeURIComponent(String(control.album || "")) : ""

}
