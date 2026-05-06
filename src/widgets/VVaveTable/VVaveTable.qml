import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.mauikit.controls as Maui
import org.mauikit.filebrowsing as FB

import org.maui.vvave

import "../../utils/Player.js" as Player

import "../../widgets"

Maui.Page
{
    id: control
    background: null

    readonly property alias listBrowser : _listBrowser
    readonly property alias listView : _listBrowser.flickable

    readonly property alias listModel : _listModel
    readonly property alias list : _tracksList

    property alias delegate : _listBrowser.delegate

    readonly property alias count : _listBrowser.count
    property alias currentIndex : _listBrowser.currentIndex
    readonly property alias currentItem : _listBrowser.currentItem

    readonly property alias holder : _listBrowser.holder
    readonly property alias section : _listBrowser.section

    property bool trackNumberVisible : false
    property bool coverArtVisible : false
    property bool allowMenu: true
    property bool showQuickActions : true
    property bool group : false
    property bool enforceDefaultTitleSort: false
    property bool _defaultSortApplied: false

    readonly property alias contextMenu : contextMenu
    property alias contextMenuItems : contextMenu.contentData

    signal rowClicked(int index)
    signal rowDoubleClicked(int index)
    signal rowPressed(int index)
    signal queueTrack(int index)
    signal appendTrack(int index)

    signal playAll()
    signal appendAll()
    signal shuffleAll()

    function focusSearch()
    {
        if (headBar.visible)
            _searchField.forceActiveFocus()
    }

    function applyAlphabeticalSort(index)
    {
        listModel.sort = "title"
        listModel.sortOrder = index === 0 ? Qt.AscendingOrder : Qt.DescendingOrder
    }

    function applyGenreSort(index)
    {
        listModel.sort = "genre"
        listModel.sortOrder = index === 0 ? Qt.AscendingOrder : Qt.DescendingOrder
    }

    function applyDefaultSortIfNeeded()
    {
        if (!enforceDefaultTitleSort || _defaultSortApplied || count <= 0)
            return

        // Force an actual resort on first population, even if bindings already
        // hold title/ascending and would otherwise not emit changes.
        listModel.sort = "title"
        if (listModel.sortOrder === Qt.AscendingOrder)
            listModel.sortOrder = Qt.DescendingOrder
        listModel.sortOrder = Qt.AscendingOrder
        _alphaSortCombo.currentIndex = 0
        _genreSortCombo.currentIndex = 0
        _defaultSortApplied = true
    }

    Maui.Theme.colorSet: Maui.Theme.Window
    Maui.Theme.inherit: false

    Maui.Controls.level : Maui.Controls.Secondary

    flickable: _listBrowser.flickable

    headBar.visible: control.list.count > 0
    headerContainer.margins: Maui.Style.contentMargins
    headerContainer.topMargin: 0

    onCountChanged: applyDefaultSortIfNeeded()

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
            id: _alphaSortCombo
            implicitWidth: 170
            model: [i18n("Title Ascending"), i18n("Title Descending")]
            currentIndex: 0
            onActivated: applyAlphabeticalSort(currentIndex)
        }

        ComboBox
        {
            id: _genreSortCombo
            implicitWidth: 170
            model: [i18n("Genre Ascending"), i18n("Genre Descending")]
            currentIndex: 0
            onActivated: applyGenreSort(currentIndex)
        }
    }

    headBar.middleContent: Item {}

    headBar.rightContent: Maui.SearchField
    {
        id: _searchField
        Layout.preferredWidth: 320
        Layout.maximumWidth: 360
        Layout.alignment: Qt.AlignRight
        placeholderText: i18n("Search tracks")
        inputMethodHints: Qt.ImhNoAutoUppercase
        enabled: headBar.visible

        onTextChanged:
        {
            const query = text.trim()
            if (query.length === 0)
                listModel.clearFilters()
            else
                listModel.filters = [query]
        }

        onCleared: listModel.clearFilters()

        Keys.onPressed: (event) =>
        {
            if (event.key === Qt.Key_Escape && text.length > 0)
            {
                clear()
                event.accepted = true
            }
        }
    }

    Component
    {
        id: _metadataDialogComponent

        MetadataDialog
        {
            model: listModel
            onClosed: destroy()
            onEdited: (data, index) =>
                      {
                          control.list.updateMetadata(data, model.mappedToSource(index))
                      }
        }
    }

    Component
    {
        id: _removeDialogComponent

        FB.FileListingDialog
        {
            title: i18n("Remove track")
            message: i18n("Are you sure you want to delete the file from your computer? This action can not be undone.")
            onClosed: destroy()
            actions: [
                Action
                {
                    Maui.Controls.status: Maui.Controls.Negative
                    text: i18n("Remove")
                    onTriggered:
                    {
                        if(FB.FM.removeFiles(urls))
                        {
                            listModel.list.erase(listModel.mappedToSource(control.currentIndex))
                        }
                        close()
                    }
                },

                Action
                {
                    text: i18n("Cancel")
                    onTriggered: close()
                }]
        }
    }

    TableMenu
    {
        id: contextMenu

        MenuSeparator {}

        MenuItem
        {
            text: i18n("Go to Artist")
            icon.name: "view-media-artist"
            onTriggered: goToArtist(listModel.get(control.currentIndex).artist)
        }

        MenuItem
        {
            text: i18n("Go to Album")
            icon.name: "view-media-album-cover"
            onTriggered:
            {
                let item = listModel.get(control.currentIndex)
                goToAlbum(item.artist, item.album)
            }
        }

        onFavClicked:
        {
            listModel.list.fav(listModel.mappedToSource(contextMenu.index), !FB.Tagging.isFav(listModel.get(contextMenu.index).url))
        }

        onQueueClicked: Player.queueTracks([listModel.get(contextMenu.index)])

        onSaveToClicked:
        {
            tagUrls(filterSelection(listModel.get(contextMenu.index).url))
        }

        onOpenWithClicked: FB.FM.openLocation(filterSelection(listModel.get(contextMenu.index).url))

        onDeleteClicked:
        {
            var dialog = _removeDialogComponent.createObject(control, ({'urls' : filterSelection(listModel.get(contextMenu.index).url)}))
            dialog.open()
        }

        onInfoClicked:
        {
            //            infoView.show(listModel.get(control.currentIndex))
        }

        onEditClicked:
        {
            var dialog = _metadataDialogComponent.createObject(control, ({'index': contextMenu.index}))
            dialog.open()
        }

        onShareClicked:
        {
            const url = listModel.get(contextMenu.index).url
            Maui.Platform.shareFiles([url])
        }
    }

    Maui.ListBrowser
    {
        id: _listBrowser
        anchors.fill: parent
        holder.visible: control.count === 0 || control.listModel.list.count === 0
        enableLassoSelection: true
        selectionMode: root.selectionMode
        currentIndex: -1
        flickable.reuseItems: true

        onItemsSelected: (indexes) =>
                         {
                             for(var i in indexes)
                             {
                                 selectionBar.addToSelection(listModel.get(indexes[i]))
                             }
                         }

        Keys.onPressed: (event) =>
                    {
                        if(event.key === Qt.Key_Return)
                        {
                            control.rowClicked(_listBrowser.currentIndex)
                        }
                    }

        section.property: control.group ? control.listModel.sort : ""
        section.criteria: control.listModel.sort === "title" ?  ViewSection.FirstCharacter : ViewSection.FullString
        section.delegate: Maui.LabelDelegate
        {
            isSection: true
            width: ListView.view.width
            //            iconSource: "view-media-artist"
            text: control.listModel.sort === "adddate" || control.listModel.sort === "releasedate" ? Maui.Handy.formatDate(Date(section), "MM/dd/yyyy") : String(section)

        }

        model: Maui.BaseModel
        {
            id: _listModel
            list: Tracks
            {
                id: _tracksList
            }
            recursiveFilteringEnabled: true
            sortCaseSensitivity: Qt.CaseInsensitive
            filterCaseSensitivity: Qt.CaseInsensitive
        }

        delegate: TableDelegate
        {
            id: delegate
            width: ListView.view.width
            height: Math.max(implicitHeight, Maui.Style.rowHeight)
            number: trackNumberVisible
            coverArt: coverArtVisible ? (control.width > 200) : coverArtVisible
            appendButton: control.showQuickActions && (Maui.Handy.isTouch ? true : delegate.hovered)

            onPressAndHold:
            {
                if(Maui.Handy.isTouch)
                    tryOpenContextMenu()
            }

            onRightClicked: tryOpenContextMenu()

            function tryOpenContextMenu()
            {
                if (allowMenu) openItemMenu(index)
            }

            onToggled: (state) => selectionBar.addToSelection(control.listModel.get(index))

            checked: selectionBar.contains(model.url)
            checkable: selectionMode || checked

            Drag.keys: ["text/uri-list"]
            Drag.mimeData: {
                "text/uri-list": control.filterSelectedItems(model.url)
            }

            sameAlbum:
            {
                const item = listModel.get(index-1)
                return coverArt && item && item.album === album && item.artist === artist
            }

            onAppendClicked:{
                currentIndex = index
                appendTrack(index)
            }

            onClicked: (mouse) =>
                       {
                           _listBrowser.forceActiveFocus()
                           currentIndex = index

                           if(selectionMode)
                           {
                               selectionBar.addToSelection(model)
                               return
                           }

                           if ((mouse.button === Qt.LeftButton) && (mouse.modifiers & Qt.ControlModifier))
                           _listBrowser.itemsSelected([index])

                           if(Maui.Handy.isTouch)
                           rowClicked(index)
                       }

            onDoubleClicked:
            {
                currentIndex = index

                if(!Maui.Handy.isTouch)
                    rowClicked(index)
            }

            Connections
            {
                target: selectionBar
                ignoreUnknownSignals: true

                function onUriRemoved(uri)
                {
                    if(uri === model.url)
                        delegate.checked = false
                }

                function onUriAdded(uri)
                {
                    if(uri === model.url)
                        delegate.checked = true
                }

                function onCleared()
                {
                    delegate.checked = false
                }
            }
        }

        Connections
        {
            target: root

            function onContextualPlayNext(event) {
                if (_listBrowser.activeFocus)
                    Player.queueTracks([listModel.get(_listBrowser.currentIndex)])
            }
        }
    }

    function openItemMenu(index)
    {
        currentIndex = index
        contextMenu.index = index
        contextMenu.fav = FB.Tagging.isFav(listModel.get(contextMenu.index).url)
        contextMenu.titleInfo = listModel.get(contextMenu.index)
        contextMenu.show()
        rowPressed(index)
    }

    function filterSelectedItems(path)
    {
        if(selectionBar && selectionBar.count > 0 && selectionBar.contains(path))
        {
            const uris = selectionBar.uris
            return uris
        }

        return [path]
    }

    function filterSelection(url)
    {
        if(selectionBar.contains(url))
        {
            return selectionBar.uris
        }else
        {
            return [url]
        }
    }

    function forceActiveFocus()
    {
        _listBrowser.forceActiveFocus()
    }

}
