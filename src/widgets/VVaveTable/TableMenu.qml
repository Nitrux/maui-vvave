import QtQuick
import QtQuick.Controls

import org.mauikit.controls as Maui
import org.mauikit.filebrowsing as FB

Maui.ContextualMenu
{
    id: control

    property bool fav : false
    property int index
    property var titleInfo: ({})

    signal favClicked()
    signal queueClicked()
    signal saveToClicked()
    signal openWithClicked()
    signal editClicked()
    signal shareClicked()
    signal selectClicked()
    signal infoClicked()
    signal deleteClicked()

    property alias menuItem : control.contentData

    title: (control.titleInfo && control.titleInfo.title) ? control.titleInfo.title : ""
    Maui.Controls.subtitle: (control.titleInfo && control.titleInfo.artist) ? control.titleInfo.artist : ""
    icon.source: "image://artwork/album:" + ((control.titleInfo && control.titleInfo.artist) ? control.titleInfo.artist : "") + ":" + ((control.titleInfo && control.titleInfo.album) ? control.titleInfo.album : "")

    Maui.MenuItemActionRow
    {
        Action
        {
            text: !fav ? i18n("Fav it"): i18n("UnFav it")
            checked: control.fav
            checkable: true
            icon.name: "love"
            onTriggered: favClicked()
        }


        Action
        {
            text: i18n("Edit")
            icon.name: "document-edit"
            onTriggered:
            {
                editClicked()
            }
        }

        Action
        {
            text: i18n("Share")
            icon.name: "document-share"
            onTriggered: shareClicked()
        }
    }

    MenuItem
    {
        visible: root.lastUsedPlaylist.length > 0
        height: visible ? implicitHeight : -control.spacing
        text: i18n("Add to '%1'", root.lastUsedPlaylist)
        icon.name: "tag"
        onTriggered:
        {
            if(control.titleInfo && control.titleInfo.url)
                FB.Tagging.tagUrl(control.titleInfo.url, root.lastUsedPlaylist)
        }
    }

    Action
    {
        text: i18n("Add to playlist")
        icon.name: "tag"
        onTriggered: saveToClicked()
        shortcut: "Ctrl+S"
    }

    MenuSeparator {}

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
        text: i18n("Show in Folder")
        icon.name: "folder-open"
        enabled: !Maui.Handy.isAndroid
        onTriggered:
        {
            openWithClicked()
        }
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
