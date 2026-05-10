import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

import org.mauikit.controls as Maui

import org.maui.vvave

Maui.AltBrowser
{
    id: control
    property alias list: _albumsList
    property alias listModel: _albumsModel

    readonly property string prefix : list.query === Albums.ALBUMS ? "album" : "artist"
    readonly property string primarySortRole: prefix === "album" ? "album" : "artist"
    readonly property string secondarySortRole: prefix === "album" ? "artist" : "album"


    signal albumCoverClicked(string album, string artist)
    signal playAll(string album, string artist)

    function searchRole()
    {
        return prefix === "album" ? "album" : "artist"
    }

    function syncSearchRole()
    {
        listModel.filterRole = searchRole()
    }

    function applyPrimarySort(index)
    {
        listModel.sort = primarySortRole
        listModel.sortOrder = index === 0 ? Qt.AscendingOrder : Qt.DescendingOrder
    }

    function applySecondarySort(index)
    {
        listModel.sort = secondarySortRole
        listModel.sortOrder = index === 0 ? Qt.AscendingOrder : Qt.DescendingOrder
    }

    function focusSearch()
    {
        if (headBar.visible)
            _searchField.forceActiveFocus()
    }

    function artworkSourceFor(artist, album)
    {
        const safeArtist = encodeURIComponent(String(artist || ""))
        const safeAlbum = encodeURIComponent(String(album || ""))
        const payload = control.prefix === "album" ? (safeArtist + ":" + safeAlbum) : safeArtist
        return "image://artwork/" + control.prefix + ":" + payload
    }

    Maui.Controls.level : Maui.Controls.Secondary

    Maui.Theme.colorSet: Maui.Theme.View
    Maui.Theme.inherit: false
    headBar.visible: listModel.list.count > 0
    onPrefixChanged: syncSearchRole()

    headerContainer.margins: Maui.Style.contentMargins
    headerContainer.topMargin: 0

    floatingHeader: false

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
            model: prefix === "album"
                   ? [i18n("Album Ascending"), i18n("Album Descending")]
                   : [i18n("Artist Ascending"), i18n("Artist Descending")]
            currentIndex: 0
            onActivated: applyPrimarySort(currentIndex)
        }

        ComboBox
        {
            id: _secondarySortCombo
            implicitWidth: 170
            model: prefix === "album"
                   ? [i18n("Artist Ascending"), i18n("Artist Descending")]
                   : [i18n("Album Ascending"), i18n("Album Descending")]
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
        placeholderText: prefix === "album" ? i18n("Search albums") : i18n("Search artists")
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

    viewType: root.isWide ? Maui.AltBrowser.ViewType.Grid : Maui.AltBrowser.ViewType.List

    gridView.itemSize: 180
    gridView.itemHeight: 180
    gridView.flickable.reuseItems: true
    listView.flickable.reuseItems: true
    holder.visible: listModel.list.count === 0

    property string typingQuery

    Maui.Chip
    {
        z: control.z + 99999
        Maui.Theme.colorSet:Maui.Theme.Complementary
        visible: _typingTimer.running
        label.text: typingQuery
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        showCloseButton: false
        anchors.margins: Maui.Style.space.medium
    }

    Timer
    {
        id: _typingTimer
        interval: 250
        onTriggered:
        {
            const index = _albumsList.indexOfName(typingQuery)
            if(index > -1)
            {
                control.currentIndex = _albumsModel.mappedFromSource(index)
            }

            typingQuery = ""
        }
    }

    Connections
    {
        target: control.currentView
        ignoreUnknownSignals: true
        function onKeyPress(event)
        {
            const index = control.currentIndex
            const item = _albumsModel.get(index)

            var pat = /^([a-zA-Z0-9 _-]+)$/
            if(event.count === 1 && pat.test(event.text))
            {
                typingQuery += event.text
                _typingTimer.restart()
            }

            //shortcut for opening
            if(event.key === Qt.Key_Return)
            {
                albumCoverClicked(item.album, item.artist)
            }
        }
    }

    model: Maui.BaseModel
    {
        id: _albumsModel
        recursiveFilteringEnabled: true
        sortCaseSensitivity: Qt.CaseInsensitive
        filterCaseSensitivity: Qt.CaseInsensitive
        list: Albums
        {
            id: _albumsList
        }
    }

    Component.onCompleted: syncSearchRole()

    listDelegate: Maui.ListBrowserDelegate
    {
        width: ListView.view.width

        label1.text: model.album ? model.album : model.artist
        label2.text: model.artist && model.album ? model.artist : ""
        iconSource: control.prefix === "album" ? "" : "folder-music"
        imageSource: artworkSourceFor(model.artist, model.album)
        maskRadius: Maui.Style.radiusV

        onClicked:
        {
            control.currentIndex = index
            if(Maui.Handy.singleClick)
            {
                albumCoverClicked(model.album, model.artist)
            }
        }

        onDoubleClicked:
        {
            control.currentIndex = index
            if(!Maui.Handy.singleClick)
            {
                albumCoverClicked(model.album, model.artist)
            }
        }
    }


    gridDelegate: Item
    {
        height: GridView.view.cellHeight
        width: GridView.view.cellWidth

        Maui.GridBrowserDelegate
        {
            id: _template
            anchors.centerIn: parent

            width: control.gridView.itemSize - Maui.Style.space.medium
            height: control.gridView.itemHeight  - Maui.Style.space.medium

            isCurrentItem: parent.GridView.isCurrentItem
            maskRadius: Maui.Style.radiusV

            tooltipText: label1.text
            label1.text: model.album ? model.album : model.artist
            label2.text: model.artist && model.album ? model.artist : ""

            imageSource: artworkSourceFor(model.artist, model.album)

            iconSource: control.prefix === "album" ? "" : "view-media-artist"

            template.labelsVisible: settings.showTitles
            template.alignment: Qt.AlignLeft
            template.fillMode: Image.PreserveAspectFit

            onClicked:
            {
                control.currentIndex = index
                if(Maui.Handy.singleClick)
                {
                    albumCoverClicked(model.album, model.artist)
                }
            }

            onDoubleClicked:
            {
                control.currentIndex = index
                if(!Maui.Handy.singleClick)
                {
                    albumCoverClicked(model.album, model.artist)
                }
            }

            Loader
            {
                active: !Maui.Handy.isMobile
                asynchronous: false
                parent: _template.template.iconItem
                anchors.centerIn: parent
                sourceComponent: ToolButton
                {
                    icon.name: "media-playback-start"
                    icon.color: "white"
                    icon.height: 32
                    icon.width: 32
                    padding: Maui.Style.space.big
                    visible: _template.hovered

                    onClicked: control.playAll(model.album, model.artist)

                    background: Rectangle
                    {
                        color: "black"
                        radius: height
                        opacity: hovered ? 0.8 : 0.5
                    }
                }
            }
        }
    }

    }
