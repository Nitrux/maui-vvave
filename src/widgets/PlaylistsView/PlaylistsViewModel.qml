import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.mauikit.controls  as Maui
import org.maui.vvave as Vvave

Maui.AltBrowser
{
    id: control
    background: null

    readonly property alias list: _playlistsList

    function applyPrimarySort(index)
    {
        _playlistsModel.sort = "playlist"
        _playlistsModel.sortOrder = index === 0 ? Qt.AscendingOrder : Qt.DescendingOrder
    }

    function applySecondarySort(index)
    {
        _playlistsModel.sort = "key"
        _playlistsModel.sortOrder = index === 0 ? Qt.AscendingOrder : Qt.DescendingOrder
    }

    function focusSearch()
    {
        if (headBar.visible)
            _searchField.forceActiveFocus()
    }

    Maui.Theme.colorSet: Maui.Theme.View
    Maui.Theme.inherit: false
    Maui.Controls.level : Maui.Controls.Secondary

    viewType: root.isWide ? Maui.AltBrowser.ViewType.Grid : Maui.AltBrowser.ViewType.List

    gridView.itemSize: 140
    gridView.itemHeight: 180

    holder.emoji: "folder-music"
    holder.title : i18n("No Playlists!")
    holder.body: i18n("Start creating new custom playlists")

    holder.visible: _playlistsModel.count === 0

    Component
    {
        id: _removeTagDialogComponent
        Maui.InfoDialog
        {
            onClosed: destroy()
            title: i18n("Remove '%1'?", currentPlaylist)
            message: i18n("Are you sure you want to remove this tag? This operation can not be undone.")
            onAccepted:
            {
                _playlistsList.removePlaylist(control.model.mappedToSource(control.currentIndex))
                close()
            }

            onRejected: close()
        }
    }

    Maui.ContextualMenu
    {
        id: _tagMenu

        MenuItem
        {
            text: i18n("Edit")
            icon.name: "document-edit"
            onTriggered:
            {}
        }

        MenuItem
        {
            text: i18n("Remove")
            icon.name: "edit-delete"
            onTriggered:
            {
                var dialog = _removeTagDialogComponent.createObject(control)
                dialog.open()
            }
        }
    }

    model: Maui.BaseModel
    {
        id: _playlistsModel
        list: Vvave.Playlists
        {
            id: _playlistsList
        }

        filterRole: "playlist"
        recursiveFilteringEnabled: true
        sortCaseSensitivity: Qt.CaseInsensitive
        filterCaseSensitivity: Qt.CaseInsensitive
    }

    footBar.visible: false
    headerContainer.margins: Maui.Style.contentMargins
    headerContainer.topMargin: 0
    headBar.visible: _playlistsModel.count > 0

    headBar.leftContent: RowLayout
    {
        spacing: Maui.Style.space.small
        enabled: headBar.visible

        Label
        {
            text: i18n("Filter")
            font.weight: Font.DemiBold
            verticalAlignment: Text.AlignVCenter
        }

        ComboBox
        {
            id: _primarySortCombo
            implicitWidth: 170
            model: [i18n("Playlist Ascending"), i18n("Playlist Descending")]
            currentIndex: 0
            onActivated: applyPrimarySort(currentIndex)
        }

        ComboBox
        {
            id: _secondarySortCombo
            implicitWidth: 170
            model: [i18n("Identifier Ascending"), i18n("Identifier Descending")]
            currentIndex: 0
            onActivated: applySecondarySort(currentIndex)
        }
    }

    headBar.middleContent: Item {}

    headBar.rightContent: Maui.SearchField
    {
        id: _searchField
        Layout.preferredWidth: 320
        Layout.maximumWidth: 360
        Layout.alignment: Qt.AlignRight
        placeholderText: i18n("Search playlists")
        inputMethodHints: Qt.ImhNoAutoUppercase
        enabled: headBar.visible

        onTextChanged:
        {
            const query = text.trim()
            if (query.length === 0)
                _playlistsModel.clearFilters()
            else
                _playlistsModel.filters = [query]
        }

        onCleared: _playlistsModel.clearFilters()

        Keys.onPressed: (event) =>
        {
            if (event.key === Qt.Key_Escape && text.length > 0)
            {
                clear()
                event.accepted = true
            }
        }
    }

    headBar.farRightContent: ToolButton
    {
        icon.name: "list-add"
        onClicked:
        {
           var dialog = newPlaylistDialogComponent.createObject(control)
            dialog.open()
        }
    }

    listDelegate: Maui.ListBrowserDelegate
    {
        width: ListView.view.width
        isCurrentItem: ListView.isCurrentItem

        label1.text: model.playlist

        iconSource: model.icon
        iconVisible: true
        iconSizeHint: Maui.Style.iconSizes.big

        template.iconComponent: Maui.GalleryRollTemplate
        {
            implicitHeight: Maui.Style.iconSizes.big
            implicitWidth: Maui.Style.iconSizes.big
            orientation: Qt.Horizontal
            radius: Maui.Style.radiusV
            images: model.preview.split(",")
        }

        onClicked :
        {
            control.currentIndex = index
            if(Maui.Handy.singleClick)
            {
                populate(model.key, true)
            }
        }

        onDoubleClicked :
        {
            control.currentIndex = index
            if(!Maui.Handy.singleClick)
            {
                populate(model.key, true)
            }
        }

        onRightClicked: tryOpenContextMenu()

        onPressAndHold: tryOpenContextMenu()

        function tryOpenContextMenu()
        {
            control.currentIndex = index
            currentPlaylist = model.key
            _tagMenu.show()
        }
    }

    gridDelegate : Item
    {
        height: GridView.view.cellHeight
        width: GridView.view.cellWidth

        Maui.GalleryRollItem
        {
            id: _collageDelegate
            anchors.fill: parent
            anchors.margins: Maui.Handy.isMobile ? Maui.Style.space.small : Maui.Style.space.medium
            orientation: Qt.Vertical
            imageWidth: 120
            imageHeight: 120

            isCurrentItem: parent.GridView.isCurrentItem
            images: model.preview.split(",")

            label1.text: model.playlist
            iconSource: model.icon
            template.labelSizeHint: 24

            onClicked :
            {
                control.currentIndex = index
                if(Maui.Handy.singleClick)
                {
                    populate(model.key, true)
                }
            }

            onDoubleClicked :
            {
                control.currentIndex = index
                if(!Maui.Handy.singleClick)
                {
                    populate(model.key, true)
                }
            }

            onRightClicked: tryOpenContextMenu()

            onPressAndHold: tryOpenContextMenu()

        }

        function tryOpenContextMenu()
        {
            control.currentIndex = index
            currentPlaylist = model.key
            _tagMenu.show()
        }
    }

}
