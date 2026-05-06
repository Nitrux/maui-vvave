import QtQuick
import QtQuick.Controls

import org.mauikit.controls as Maui
import org.mauikit.filebrowsing as FB

Maui.ContextualMenu
{
    id: control

    property int index
    property var titleInfo: ({})

    signal queueClicked()
    signal goToArtistClicked()
    signal goToAlbumClicked()
    signal copyPathClicked()
    signal selectClicked()
    signal infoClicked()
    signal deleteClicked()

    property alias menuItem : control.contentData

    MenuItem
    {
        text: i18n("Select")
        icon.name: "item-select"
        onTriggered:
        {
            selectionBar.addToSelection(listModel.get(control.index))
            selectionMode = Maui.Handy.isTouch
        }
    }

    MenuSeparator {}

    MenuItem
    {
        text: i18n("Play Next")
        icon.name: "view-media-recent"
        onTriggered:
        {
            queueClicked()
        }
    }

    MenuSeparator{}

    MenuItem
    {
        text: i18n("Go to Artist")
        icon.name: "view-media-artist"
        onTriggered: goToArtistClicked()
    }

    MenuItem
    {
        text: i18n("Go to Album")
        icon.name: "view-media-album-cover"
        onTriggered: goToAlbumClicked()
    }

    MenuSeparator {}

    MenuItem
    {
        text: i18n("Copy Path to Clipboard")
        icon.name: "edit-copy"
        onTriggered: copyPathClicked()
    }

    MenuSeparator {}



    //    Maui.MenuItem
    //    {
    //        text: i18n("Info...")
    //        onTriggered:
    //        {
    //            infoClicked()
    //            close()
    //        }
    //    }


    MenuItem
    {
        text: i18n("Delete")
        icon.name: "edit-delete"
        Maui.Controls.status: Maui.Controls.Negative
        onTriggered:
        {
            deleteClicked()
        }
    }
}
