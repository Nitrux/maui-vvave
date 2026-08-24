import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

import org.mauikit.controls as Maui
import org.mauikit.filebrowsing as FB
import org.maui.vvave

import "../db/Queries.js" as Q
import "../utils/Player.js" as Player

Maui.Page
{
    id: control

    readonly property int songsMode: 0
    readonly property int albumsMode: 1
    readonly property int artistsMode: 2
    readonly property int favoritesMode: 3
    readonly property int artistAlbumsMode: 4
    readonly property int detailTracksMode: 5
    readonly property int focusModeValue: 6

    property bool focusMode: false
    property bool sidebarOpen: false
    property Component menuComponent
    property int mode: control.songsMode
    property int lastBrowserMode: control.songsMode
    property int returnMode: control.songsMode
    property string currentArtist: ""
    property string currentAlbum: ""
    property string detailQuery: ""
    property int _transitionSerial: 0
    property bool _ready: false
    property bool _songsActivated: false
    property bool _favoritesActivated: false
    property bool _detailTracksActivated: false
    property bool _albumsActivated: false
    property bool _artistAlbumsActivated: false
    property bool _artistsActivated: false
    property bool resultFilterExpanded: false
    property string _pendingResultFilter: ""

    readonly property Item currentItem: mode === control.songsMode
                                        ? _songsLoader.item
                                        : _contentLoader.item
    readonly property bool isTrackMode: mode === control.songsMode
                                        || mode === control.favoritesMode
                                        || mode === control.detailTracksMode
    readonly property bool isCollectionMode: mode === control.albumsMode
                                             || mode === control.artistsMode
                                             || mode === control.artistAlbumsMode
    readonly property var currentTracksModel: mode === control.songsMode
                                              ? _songsModel
                                              : (mode === control.favoritesMode
                                                 ? _favoritesModel
                                                 : _detailTracksModel)
    readonly property var currentTracksSource: mode === control.songsMode
                                               ? _songsSource
                                               : (mode === control.favoritesMode
                                                  ? _favoritesSource
                                                  : _detailTracksSource)
    readonly property var currentCollectionModel: mode === control.albumsMode
                                                  ? _albumsModel
                                                  : (mode === control.artistsMode
                                                     ? _artistsModel
                                                     : _artistAlbumsModel)
    readonly property var currentResultModel: control.isTrackMode
                                              ? control.currentTracksModel
                                              : (control.isCollectionMode ? control.currentCollectionModel : null)
    readonly property bool resultFilterAvailable: control.currentResultModel !== null
    readonly property string categoryName:
    {
        switch (mode)
        {
        case control.albumsMode:
        case control.artistAlbumsMode:
            return "albums"
        case control.artistsMode:
            return "artists"
        case control.favoritesMode:
            return "favorites"
        case control.detailTracksMode:
        case control.songsMode:
            return "songs"
        case control.focusModeValue:
            return "focus"
        default:
            return "unknown"
        }
    }

    signal toggleSidebarRequested()

    background: null
    focus: true
    floatingHeader: false
    floatingFooter: true
    altHeader: Maui.Handy.isMobile
    headerMargins: Maui.Style.contentMargins
    footerMargins: headerMargins
    Maui.Controls.showCSD: true

    flickable: currentItem && currentItem.flickable ? currentItem.flickable : null

    function encodeQueryPart(value)
    {
        return encodeURIComponent(String(value || "").trim()).replace(/\//g, "%2F")
    }

    function applyResultFilter(query)
    {
        if (!currentResultModel)
            return

        if (query.length === 0)
            currentResultModel.clearFilters()
        else
            currentResultModel.filters = [query]
    }

    function clearResultFilter()
    {
        _resultFilterTimer.stop()
        _pendingResultFilter = ""
        if (_resultFilterField.text.length > 0)
            _resultFilterField.clear()
        if (currentResultModel)
            currentResultModel.clearFilters()
        resultFilterExpanded = false
    }

    function toggleResultFilter()
    {
        if (!resultFilterAvailable)
            return

        resultFilterExpanded = !resultFilterExpanded
        if (resultFilterExpanded)
            Qt.callLater(() => _resultFilterField.forceActiveFocus())
        else
            clearResultFilter()
    }

    function componentForMode(targetMode)
    {
        if (targetMode === control.focusModeValue)
            return _focusComponent
        if (targetMode === control.albumsMode
                || targetMode === control.artistsMode
                || targetMode === control.artistAlbumsMode)
            return _collectionComponent
        return _tracksComponent
    }

    function enforceAscendingTitle(model)
    {
        if (!model)
            return

        model.sort = "title"
        model.sortOrder = Qt.DescendingOrder
        model.sortOrder = Qt.AscendingOrder
    }

    function ensureModeSource(targetMode)
    {
        switch (targetMode)
        {
        case control.songsMode:
            _songsActivated = true
            break
        case control.favoritesMode:
            _favoritesActivated = true
            break
        case control.detailTracksMode:
            _detailTracksActivated = true
            break
        case control.albumsMode:
            _albumsActivated = true
            break
        case control.artistAlbumsMode:
            _artistAlbumsActivated = true
            break
        case control.artistsMode:
            _artistsActivated = true
            break
        }
    }

    function requestMode(targetMode)
    {
        const nextMode = Number(targetMode)
        if (nextMode !== mode)
            clearResultFilter()
        if (!_ready)
        {
            mode = nextMode
            return
        }

        if (_contentLoader.active && mode === nextMode)
        {
            forceActiveFocus()
            return
        }

        const serial = ++_transitionSerial
        _contentLoader.active = false
        _contentLoader.sourceComponent = null

        Qt.callLater(() => {
            if (serial !== control._transitionSerial)
                return

            mode = nextMode
            control.ensureModeSource(nextMode)

            if (nextMode === control.songsMode)
            {
                Qt.callLater(() => {
                    if (serial === control._transitionSerial)
                        control.forceActiveFocus()
                })
                return
            }

            Qt.callLater(() => {
                if (serial !== control._transitionSerial)
                    return

                _contentLoader.sourceComponent = control.componentForMode(nextMode)
                _contentLoader.active = true
                Qt.callLater(() => {
                    if (serial === control._transitionSerial)
                        control.forceActiveFocus()
                })
            })
        })
    }

    function showCategory(index)
    {
        if (focusMode)
            root.focusView = false

        switch (Number(index))
        {
        case 1:
            currentArtist = ""
            currentAlbum = ""
            returnMode = control.albumsMode
            requestMode(control.albumsMode)
            break
        case 2:
            currentArtist = ""
            currentAlbum = ""
            returnMode = control.artistsMode
            requestMode(control.artistsMode)
            break
        case 3:
            requestMode(control.favoritesMode)
            break
        default:
            requestMode(control.songsMode)
            break
        }
    }

    function openAlbum(album, artist)
    {
        const albumName = String(album || "").trim()
        const artistName = String(artist || "").trim()
        if (albumName.length === 0 || artistName.length === 0)
            return

        currentAlbum = albumName
        currentArtist = artistName
        returnMode = mode === control.artistAlbumsMode
                     ? control.artistAlbumsMode
                     : control.albumsMode
        detailQuery = "vvave://album/" + encodeQueryPart(albumName) + "/" + encodeQueryPart(artistName)
        _detailTracksSource.query = detailQuery
        requestMode(control.detailTracksMode)
    }

    function openArtist(artist)
    {
        const artistName = String(artist || "").trim()
        if (artistName.length === 0)
            return

        currentArtist = artistName
        currentAlbum = ""
        returnMode = control.artistsMode
        requestMode(control.artistAlbumsMode)
    }

    function openArtistTracks(artist)
    {
        const artistName = String(artist || "").trim()
        if (artistName.length === 0)
            return

        currentArtist = artistName
        currentAlbum = ""
        returnMode = control.artistsMode
        detailQuery = "vvave://artist/" + encodeQueryPart(artistName)
        _detailTracksSource.query = detailQuery
        requestMode(control.detailTracksMode)
    }

    function activateCollection(index)
    {
        if (!currentCollectionModel || index < 0 || index >= currentCollectionModel.count)
            return

        const item = currentCollectionModel.get(index)
        if (!item)
            return

        if (mode === control.artistsMode)
            openArtist(item.artist)
        else
            openAlbum(item.album, item.artist)
    }

    function activateTrack(index)
    {
        if (!currentTracksModel || index < 0 || index >= currentTracksModel.count)
            return

        const item = currentTracksModel.get(index)
        if (item)
            Player.quickPlay(item)
    }

    function queueTrack(index)
    {
        if (!currentTracksModel || index < 0 || index >= currentTracksModel.count)
            return

        const item = currentTracksModel.get(index)
        if (item)
            Player.queueTracks([item])
    }

    function openContextMenu(index)
    {
        if (!currentTracksModel || index < 0 || index >= currentTracksModel.count)
        {
            return
        }

        const item = currentTracksModel.get(index)
        if (!item)
        {
            return
        }

        _contextMenu.index = index
        _contextMenu.track = item
        _contextMenu.favorite = item.url ? FB.Tagging.isFav(item.url) : false
        _contextMenu.show()
    }

    function openMetadataDialog(index)
    {
        if (!currentTracksModel || index < 0 || index >= currentTracksModel.count)
        {
            return
        }

        const item = currentTracksModel.get(index)
        if (!item || !item.url)
        {
            return
        }

        _metadataDialog.openFor(item, currentTracksModel,
                                currentTracksSource, index)
    }

    function refreshFavorites()
    {
        _favoritesSource.refresh()
    }

    function setFavorite(index, favorite)
    {
        if (!currentTracksModel || index < 0 || index >= currentTracksModel.count)
            return

        const item = currentTracksModel.get(index)
        if (item && item.url)
            root.setFavorite(item.url, favorite)
    }

    function playCurrentModel()
    {
        if (currentTracksSource && currentTracksSource.count > 0)
            Player.playAllModel(currentTracksSource)
    }

    function goBack()
    {
        if (mode === control.focusModeValue)
        {
            root.focusView = false
            return
        }

        if (mode === control.artistAlbumsMode
                || (mode === control.albumsMode
                    && currentArtist.length > 0
                    && returnMode === control.artistsMode))
        {
            requestMode(control.artistsMode)
            return
        }

        if (mode === control.detailTracksMode)
            requestMode(returnMode)
    }

    function getGoBackFunc()
    {
        return mode === control.artistAlbumsMode
                || mode === control.detailTracksMode
                || mode === control.focusModeValue
                || (mode === control.albumsMode
                    && currentArtist.length > 0
                    && returnMode === control.artistsMode)
                ? () => control.goBack()
                : null
    }

    function focusSearch()
    {
        forceActiveFocus()
    }

    function forceActiveFocus()
    {
        if (currentItem && currentItem.forceActiveFocus)
            currentItem.forceActiveFocus(Qt.OtherFocusReason)
        else
            _contentLoader.forceActiveFocus(Qt.OtherFocusReason)
    }

    onFocusModeChanged:
    {
        if (!_ready)
            return

        if (focusMode)
        {
            if (mode !== control.focusModeValue)
                lastBrowserMode = mode
            requestMode(control.focusModeValue)
        }
        else if (mode === control.focusModeValue)
        {
            requestMode(lastBrowserMode)
        }
    }

    Maui.ContextualMenu
    {
        id: _contextMenu
        property int index: -1
        property var track: null
        property bool favorite: false

        MenuItem
        {
            text: i18n("Select")
            icon.name: "item-select"
            onTriggered:
            {
                if (_contextMenu.track)
                    selectionBar.addToSelection(_contextMenu.track)
                _contextMenu.close()
            }
        }

        MenuSeparator {}

        MenuItem
        {
            text: i18n("Play Next")
            icon.name: "view-media-recent"
            onTriggered:
            {
                if (_contextMenu.track)
                    Player.queueTracks([_contextMenu.track])
                _contextMenu.close()
            }
        }

        MenuItem
        {
            text: _contextMenu.favorite ? i18n("Remove from Favorites") : i18n("Add to Favorites")
            icon.name: "love"
            onTriggered:
            {
                const index = _contextMenu.index
                const favorite = !_contextMenu.favorite
                _contextMenu.close()
                control.setFavorite(index, favorite)
            }
        }

        MenuSeparator {}

        MenuItem
        {
            text: i18n("Go to Artist")
            icon.name: "view-media-artist"
            onTriggered:
            {
                if (_contextMenu.track)
                    control.openArtistTracks(_contextMenu.track.artist)
                _contextMenu.close()
            }
        }

        MenuItem
        {
            text: i18n("Go to Album")
            icon.name: "view-media-album-cover"
            onTriggered:
            {
                if (_contextMenu.track)
                    control.openAlbum(_contextMenu.track.album, _contextMenu.track.artist)
                _contextMenu.close()
            }
        }

        MenuSeparator {}

        MenuItem
        {
            text: i18n("Edit Metadata")
            icon.name: "document-edit"
            onTriggered:
            {
                const metadataIndex = _contextMenu.index
                _contextMenu.close()
                Qt.callLater(() => {
                    control.openMetadataDialog(metadataIndex)
                })
            }
        }

        MenuItem
        {
            text: i18n("Copy Path to Clipboard")
            icon.name: "edit-copy"
            onTriggered:
            {
                if (_contextMenu.track && _contextMenu.track.url)
                {
                    const raw = String(_contextMenu.track.url)
                    const path = raw.startsWith("file://") ? decodeURIComponent(raw.replace("file://", "")) : raw
                    Maui.Handy.copyTextToClipboard(path)
                }
                _contextMenu.close()
            }
        }
    }

    MetadataDialog
    {
        id: _metadataDialog

        onEdited: (data, index, proxyModel, source) =>
        {
            if (!source || typeof source.updateMetadata !== "function" || !data)
            {
                return
            }

            const sourceIndex = proxyModel && typeof proxyModel.mappedToSource === "function"
                               ? proxyModel.mappedToSource(index)
                               : index
            if (sourceIndex < 0)
            {
                return
            }

            const editingPlayingTrack = root.isPlaying
                    && root.currentTrack
                    && String(root.currentTrack.url) === String(data.url)
            const playbackElapsed = editingPlayingTrack ? root.playbackElapsed : 0

            if (editingPlayingTrack)
                root.suspendPlaybackForMetadataEdit()

            source.updateMetadata(data, sourceIndex)

            if (editingPlayingTrack)
                root.resumePlaybackAfterMetadataEdit(playbackElapsed)
        }
    }

    headBar.forceCenterMiddleContent: true
    headBar.leftContent: [
        ToolButton
        {
            text: i18n("Toggle Sidebar")
            display: AbstractButton.IconOnly
            icon.name: control.sidebarOpen ? "sidebar-collapse" : "sidebar-expand"
            checkable: true
            checked: control.sidebarOpen
            ToolTip.visible: hovered
            ToolTip.text: i18n("Toggle sidebar")
            onClicked: control.toggleSidebarRequested()
        },

        ToolSeparator
        {
            bottomPadding: 10
            topPadding: 10
        },

        ToolButton
        {
            visible: control.mode === control.focusModeValue
                     || control.mode === control.artistAlbumsMode
                     || control.mode === control.detailTracksMode
                     || (control.mode === control.albumsMode
                         && control.currentArtist.length > 0
                         && control.returnMode === control.artistsMode)
            text: i18n("Back")
            display: AbstractButton.IconOnly
            icon.name: "go-previous"
            ToolTip.visible: hovered
            ToolTip.text: i18n("Back")
            onClicked: control.goBack()
        },

        ToolSeparator
        {
            visible: control.mode === control.detailTracksMode
                     && control.currentTracksSource
                     && control.currentTracksSource.count > 0
            bottomPadding: 10
            topPadding: 10
        },

        ToolButton
        {
            visible: control.isTrackMode && control.currentTracksSource && control.currentTracksSource.count > 0
            text: i18n("Play all")
            display: AbstractButton.IconOnly
            icon.name: "media-playback-start"
            ToolTip.visible: hovered
            ToolTip.text: i18n("Play all")
            onClicked: control.playCurrentModel()
        }
    ]

    headBar.middleContent: RowLayout
    {
        spacing: Maui.Style.space.small
        Layout.alignment: Qt.AlignCenter

        ToolSeparator
        {
            visible: !control.resultFilterExpanded
            bottomPadding: 10
            topPadding: 10
        }

        ToolButton
        {
            visible: !control.resultFilterExpanded
            text: i18n("Songs")
            display: AbstractButton.IconOnly
            icon.name: "view-media-track"
            checkable: true
            checked: control.mode === control.songsMode
            onClicked: control.showCategory(0)
        }

        ToolButton
        {
            visible: !control.resultFilterExpanded
            text: i18n("Albums")
            display: AbstractButton.IconOnly
            icon.name: "view-media-album-cover"
            checkable: true
            checked: control.mode === control.albumsMode
                     || control.mode === control.artistAlbumsMode
                     || (control.mode === control.detailTracksMode
                         && control.returnMode !== control.artistsMode)
            onClicked: control.showCategory(1)
        }

        ToolButton
        {
            visible: !control.resultFilterExpanded
            text: i18n("Artists")
            display: AbstractButton.IconOnly
            icon.name: "view-media-artist"
            checkable: true
            checked: control.mode === control.artistsMode
                     || (control.mode === control.detailTracksMode
                         && control.returnMode === control.artistsMode)
            onClicked: control.showCategory(2)
        }

        ToolButton
        {
            visible: !control.resultFilterExpanded
            text: i18n("Favorites")
            display: AbstractButton.IconOnly
            icon.name: "love"
            checkable: true
            checked: control.mode === control.favoritesMode
            onClicked: control.showCategory(3)
        }

        ToolSeparator
        {
            visible: !control.resultFilterExpanded
            bottomPadding: 10
            topPadding: 10
        }

        Maui.SearchField
        {
            id: _resultFilterField
            visible: control.resultFilterExpanded
            Layout.preferredWidth: 320
            Layout.maximumWidth: 360
            Layout.alignment: Qt.AlignCenter
            placeholderText: i18n("Filter results")
            inputMethodHints: Qt.ImhNoAutoUppercase

            onTextChanged:
            {
                const query = text.trim()
                control._pendingResultFilter = query
                if (query.length === 0)
                {
                    _resultFilterTimer.stop()
                    control.applyResultFilter("")
                }
                else
                {
                    _resultFilterTimer.restart()
                }
            }

            onCleared:
            {
                control._pendingResultFilter = ""
                _resultFilterTimer.stop()
                control.applyResultFilter("")
            }

            Keys.onPressed: (event) =>
            {
                if (event.key === Qt.Key_Escape)
                {
                    control.clearResultFilter()
                    event.accepted = true
                }
            }
        }
    }

    headBar.rightContent: [
        ToolButton
        {
            visible: control.resultFilterAvailable
            text: i18n("Search")
            display: AbstractButton.IconOnly
            icon.name: "edit-find"
            checkable: true
            checked: control.resultFilterExpanded
            ToolTip.visible: hovered
            ToolTip.text: i18n("Search")
            onClicked: control.toggleResultFilter()
        },

        ToolSeparator
        {
            bottomPadding: 10
            topPadding: 10
        },

        Loader
        {
            asynchronous: false
            sourceComponent: control.menuComponent
        }
    ]

    Timer
    {
        id: _resultFilterTimer
        interval: 180
        repeat: false
        onTriggered: control.applyResultFilter(control._pendingResultFilter)
    }

    Tracks
    {
        id: _songsSource
        query: Q.GET.allTracks
        autoPopulate: control._songsActivated
    }

    Maui.BaseModel
    {
        id: _songsModel
        list: _songsSource
        sort: "title"
        sortOrder: Qt.AscendingOrder
        recursiveFilteringEnabled: true
        sortCaseSensitivity: Qt.CaseInsensitive
        filterCaseSensitivity: Qt.CaseInsensitive
    }

    Tracks
    {
        id: _favoritesSource
        query: Q.GET.playlistTracks_.arg("fav")
        autoPopulate: control._favoritesActivated
    }

    Maui.BaseModel
    {
        id: _favoritesModel
        list: _favoritesSource
        sort: "title"
        sortOrder: Qt.AscendingOrder
        recursiveFilteringEnabled: true
        sortCaseSensitivity: Qt.CaseInsensitive
        filterCaseSensitivity: Qt.CaseInsensitive
    }

    Tracks
    {
        id: _detailTracksSource
        query: control.detailQuery
        autoPopulate: control._detailTracksActivated
    }

    Maui.BaseModel
    {
        id: _detailTracksModel
        list: _detailTracksSource
        sort: "title"
        sortOrder: Qt.AscendingOrder
        recursiveFilteringEnabled: true
        sortCaseSensitivity: Qt.CaseInsensitive
        filterCaseSensitivity: Qt.CaseInsensitive
    }

    Albums
    {
        id: _albumsSource
        query: Albums.ALBUMS
        autoPopulate: control._albumsActivated
    }

    Maui.BaseModel
    {
        id: _albumsModel
        list: _albumsSource
        sort: "album"
        sortOrder: Qt.AscendingOrder
        recursiveFilteringEnabled: true
        sortCaseSensitivity: Qt.CaseInsensitive
        filterCaseSensitivity: Qt.CaseInsensitive
    }

    Albums
    {
        id: _artistAlbumsSource
        query: Albums.ALBUMS
        artist: control.currentArtist
        autoPopulate: control._artistAlbumsActivated
    }

    Albums
    {
        id: _artistsSource
        query: Albums.ARTISTS
        autoPopulate: control._artistsActivated
    }

    Maui.BaseModel
    {
        id: _artistsModel
        list: _artistsSource
        sort: "artist"
        sortOrder: Qt.AscendingOrder
        recursiveFilteringEnabled: true
        sortCaseSensitivity: Qt.CaseInsensitive
        filterCaseSensitivity: Qt.CaseInsensitive
    }

    Maui.BaseModel
    {
        id: _artistAlbumsModel
        list: _artistAlbumsSource
        sort: "album"
        sortOrder: Qt.AscendingOrder
        recursiveFilteringEnabled: true
        sortCaseSensitivity: Qt.CaseInsensitive
        filterCaseSensitivity: Qt.CaseInsensitive
    }

    Connections
    {
        target: _songsSource
        function onCountChanged() { control.enforceAscendingTitle(_songsModel) }
    }

    Connections
    {
        target: _favoritesSource
        function onCountChanged() { control.enforceAscendingTitle(_favoritesModel) }
    }

    Connections
    {
        target: _detailTracksSource
        function onCountChanged() { control.enforceAscendingTitle(_detailTracksModel) }
    }

    Loader
    {
        id: _songsLoader
        anchors.fill: parent
        active: true
        visible: control.mode === control.songsMode
        asynchronous: false
        focus: visible
        sourceComponent: _tracksComponent

        onLoaded:
        {
            item.browserModel = _songsModel
            item.favoritesView = false
        }
    }

    Loader
    {
        id: _contentLoader
        anchors.fill: parent
        active: false
        asynchronous: false
        focus: true

        onLoaded:
        {
            if (item && (control.mode === control.favoritesMode || control.mode === control.detailTracksMode))
            {
                item.browserModel = control.currentTracksModel
                item.favoritesView = control.mode === control.favoritesMode
            }
        }
    }

    Component
    {
        id: _tracksComponent

        Maui.ListBrowser
        {
            id: _tracksBrowser
            property var browserModel: null
            property bool favoritesView: false
            property bool emptyStateReady: false
            focus: true
            clip: true
            model: _tracksBrowser.browserModel
            enableLassoSelection: false
            selectionMode: false
            spacing: Maui.Style.space.small
            leftPadding: Maui.Style.contentMargins
            rightPadding: Maui.Style.contentMargins
            topPadding: Maui.Style.space.small
            bottomPadding: Maui.Style.space.small

            holder.visible: _tracksBrowser.emptyStateReady && _tracksBrowser.count === 0
            holder.emoji: "folder-music"
            holder.title: _tracksBrowser.favoritesView
                          ? i18n("No Favorites!")
                          : i18n("No Tracks!")
            holder.body: _tracksBrowser.favoritesView
                         ? i18n("Mark tracks as favorites to see them here")
                         : i18n("Add new music sources")

            Timer
            {
                interval: 150
                running: true
                onTriggered: _tracksBrowser.emptyStateReady = true
            }

            function activateTrack(index)
            {
                if (!browserModel || index < 0 || index >= browserModel.count)
                    return

                const item = browserModel.get(index)
                if (item)
                    Player.quickPlay(item)
            }

            function queueTrack(index)
            {
                if (!browserModel || index < 0 || index >= browserModel.count)
                    return

                const item = browserModel.get(index)
                if (item)
                    Player.queueTracks([item])
            }

            delegate: Maui.ListBrowserDelegate
            {
                id: _trackDelegate
                width: ListView.view.width
                height: Math.max(implicitHeight, Maui.Style.rowHeight)

                isCurrentItem: ListView.isCurrentItem
                label1.text: model.title
                label2.text: {
                    const artist = String(model.artist || "")
                    const album = String(model.album || "")
                    return artist + (artist.length > 0 && album.length > 0 ? " - " : "") + album
                }
                label3.text: model.genre
                iconSource: "qrc:/assets/cover_32x32.svg"
                template.iconComponent: ArtworkItem
                {
                    fallbackSource: "qrc:/assets/cover_32x32.svg"
                    imageSource: _trackDelegate.imageSource
                    fallbackColor: Maui.ColorUtils.tintWithAlpha(_trackDelegate.effectiveForegroundColor, Maui.Theme.highlightColor, 0.2)
                    iconSizeHint: _trackDelegate.iconSizeHint
                    maskRadius: _trackDelegate.maskRadius
                }
                imageSource: model.artwork || control.artworkSourceFor(model.artist, model.album)
                maskRadius: Maui.Style.radiusV

                onClicked:
                {
                    _tracksBrowser.currentIndex = index
                    if (Maui.Handy.singleClick)
                        _tracksBrowser.activateTrack(index)
                }

                onDoubleClicked:
                {
                    _tracksBrowser.currentIndex = index
                    if (!Maui.Handy.singleClick)
                        _tracksBrowser.activateTrack(index)
                }

                onRightClicked:
                {
                    _tracksBrowser.currentIndex = index
                    control.openContextMenu(index)
                }

                onPressAndHold:
                {
                    if (Maui.Handy.isTouch)
                    {
                        _tracksBrowser.currentIndex = index
                        control.openContextMenu(index)
                    }
                }
            }
        }
    }

    Component
    {
        id: _collectionComponent

        Maui.GridBrowser
        {
            id: _collectionBrowser
            property bool emptyStateReady: false
            focus: true
            clip: true
            model: control.currentCollectionModel
            itemSize: Math.max(140, Math.min(190, width / Math.max(1, Math.floor(width / 170))))
            itemHeight: itemSize
            adaptContent: true
            enableLassoSelection: false
            selectionMode: false

            holder.visible: _collectionBrowser.emptyStateReady && _collectionBrowser.count === 0
            holder.emoji: "folder-music"
            holder.title: control.mode === control.artistsMode
                          ? i18n("No Artists!")
                          : i18n("No Albums!")
            holder.body: i18n("Add new music sources")

            Timer
            {
                interval: 150
                running: true
                onTriggered: _collectionBrowser.emptyStateReady = true
            }

            delegate: Item
            {
                width: GridView.view.cellWidth
                height: GridView.view.cellHeight

                Maui.GridBrowserDelegate
                {
                    id: _collectionDelegate
                    width: Math.min(_collectionBrowser.itemWidth, parent.width - (Maui.Style.space.small * 2))
                    height: Math.min(_collectionBrowser.itemHeight, parent.height - (Maui.Style.space.small * 2))
                    anchors.centerIn: parent

                    isCurrentItem: parent.GridView.isCurrentItem
                    label1.text: model.album ? model.album : model.artist
                    label2.text: model.album && model.artist ? model.artist : ""
                    iconSource: "qrc:/assets/cover_64x64.svg"
                    iconSizeHint: Maui.Style.iconSizes.huge
                    template.iconComponent: ArtworkItem
                    {
                        imageSource: _collectionDelegate.imageSource
                        fallbackColor: Maui.ColorUtils.tintWithAlpha(_collectionDelegate.effectiveForegroundColor, Maui.Theme.highlightColor, 0.2)
                        iconSizeHint: _collectionDelegate.iconSizeHint
                        imageSizeHint: _collectionDelegate.imageSizeHint
                        fillMode: _collectionDelegate.fillMode
                        maskRadius: _collectionDelegate.maskRadius
                        imageWidth: _collectionDelegate.imageWidth
                        imageHeight: _collectionDelegate.imageHeight
                    }
                    imageSource: control.artworkSourceFor(model.artist, model.album)
                    maskRadius: Maui.Style.radiusV
                    template.labelsVisible: true
                    template.fillMode: Image.PreserveAspectFit

                    onClicked:
                    {
                        _collectionBrowser.currentIndex = index
                        if (Maui.Handy.singleClick)
                            control.activateCollection(index)
                    }

                    onDoubleClicked:
                    {
                        _collectionBrowser.currentIndex = index
                        if (!Maui.Handy.singleClick)
                            control.activateCollection(index)
                    }
                }
            }
        }
    }

    Component
    {
        id: _focusComponent

        Item
        {
            focus: true
            property Flickable flickable: null

            Maui.Holder
            {
                anchors.fill: parent
                visible: !root.currentTrack || !root.currentTrack.url
                emoji: "qrc:/assets/cover_64x64.svg"
                title: i18n("Nothing to play!")
                body: i18n("Start putting together your playlist.")
            }

            ColumnLayout
            {
                anchors.fill: parent
                anchors.margins: Maui.Style.contentMargins
                spacing: Maui.Style.space.medium
                visible: root.currentTrack && root.currentTrack.url

                Item
                {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Rectangle
                    {
                        id: _focusArtworkFrame
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height) * 0.9
                        height: width
                        radius: Maui.Style.radiusV
                        color: Maui.Theme.alternateBackgroundColor
                        clip: true

                        Image
                        {
                            id: _focusArtworkPreview
                            anchors.fill: parent
                            anchors.margins: Maui.Style.space.small
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            source: control.artworkSourceFor(root.currentTrack.artist, root.currentTrack.album)
                            visible: !_focusArtwork.visible
                        }

                        Image
                        {
                            id: _focusArtwork
                            anchors.fill: parent
                            anchors.margins: Maui.Style.space.small
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            sourceSize.width: Math.ceil(width * Screen.devicePixelRatio)
                            sourceSize.height: Math.ceil(height * Screen.devicePixelRatio)
                            source: control.artworkSourceFor(root.currentTrack.artist, root.currentTrack.album, true)
                            visible: status === Image.Ready && paintedWidth > 0 && paintedHeight > 0
                        }

                        Maui.Icon
                        {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height) * 0.45
                            height: width
                            source: "qrc:/assets/cover_64x64.svg"
                            visible: !_focusArtwork.visible
                                     && (_focusArtworkPreview.status !== Image.Ready
                                         || _focusArtworkPreview.paintedWidth <= 0
                                         || _focusArtworkPreview.paintedHeight <= 0)
                        }
                    }
                }

                Label
                {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.currentTrack && root.currentTrack.title ? root.currentTrack.title : ""
                    font.weight: Font.Bold
                    font.pointSize: Maui.Style.fontSizes.huge
                    elide: Text.ElideMiddle
                }

                Label
                {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    Layout.bottomMargin: Maui.Style.space.big
                    text: root.currentTrack && root.currentTrack.artist ? root.currentTrack.artist : ""
                    font.pointSize: Maui.Style.fontSizes.big
                    opacity: 0.7
                    elide: Text.ElideMiddle
                }
            }
        }
    }

    function artworkSourceFor(artist, album, highResolution)
    {
        const artistName = String(artist || "").trim()
        const albumName = String(album || "").trim()

        const artistKnown = artistName.length > 0 && artistName.toUpperCase() !== "UNKNOWN"
        const albumKnown = albumName.length > 0 && albumName.toUpperCase() !== "UNKNOWN"

        if (artistKnown && albumKnown)
            return "image://artwork/" + (highResolution ? "focusAlbum:" : "album:") + encodeURIComponent(artistName) + ":" + encodeURIComponent(albumName)
        if (artistKnown)
            return "image://artwork/" + (highResolution ? "focusArtist:" : "artist:") + encodeURIComponent(artistName)
        return ""
    }

    Component.onCompleted:
    {
        _ready = true
        if (focusMode)
        {
            lastBrowserMode = control.songsMode
            requestMode(control.focusModeValue)
        }
        else
        {
            requestMode(mode)
        }
    }
}
