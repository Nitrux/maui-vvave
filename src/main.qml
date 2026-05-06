import QtQuick
import QtCore

import QtQuick.Controls
import QtQuick.Window
import QtQuick.Layouts

import org.mauikit.controls as Maui
import org.mauikit.filebrowsing  as FB

import org.maui.vvave

import "widgets"
import "widgets/PlaylistsView"
import "widgets/MainPlaylist"
import "widgets/SettingsView"

import "utils/Player.js" as Player

Maui.ApplicationWindow
{
    id: root

    visible: !miniMode
    title: (currentTrack && currentTrack.url) ? currentTrack.title + " - " +  currentTrack.artist + " | " + currentTrack.album : ""
    color: "transparent"
    background: null

    Maui.WindowBlur
    {
        view: root
        geometry: Qt.rect(0, 0, root.width, root.height)
        windowRadius: Maui.Style.radiusV
        enabled: true
    }

    Rectangle
    {
        anchors.fill: parent
        color: Maui.Theme.backgroundColor
        opacity: 0.76
        radius: Maui.Style.radiusV
    }

    Maui.Style.styleType: focusView ? Maui.Style.Adaptive : undefined

    property QtObject tagsDialog : null

    /***************************************************/
    /******************** ALIASES ********************/
    /*************************************************/
    readonly property alias selectionBar: _selectionBar
    readonly property alias playlistManager : playlist

    /***************************************************/
    /******************** PLAYBACK ********************/
    /*************************************************/
    readonly property alias currentTrack : playlist.currentTrack
    readonly property alias currentTrackIndex: playlist.currentIndex

    readonly property alias isPlaying: player.playing
    readonly property alias mainPlaylist : _mainPlaylist
    readonly property bool mainlistEmpty: mainPlaylist ? mainPlaylist.listModel.list.count === 0 : false

    /***************************************************/
    /******************** HANDLERS ********************/
    /*************************************************/
    readonly property var viewsIndex: ({ tracks: 0,
                                           albums: 1,
                                           artists: 2,
                                           playlists: 3 })

    property string syncPlaylist: ""
    property bool sync: false
    property string lastUsedPlaylist

    readonly property bool focusView : _stackView.currentItem.objectName === "FocusView"
    readonly property bool miniMode : _miniModeComponent.visible

    property bool selectionMode : false
    property bool _forceClose: false
    property bool _outputSelectionReady: false

    /***************************************************/
    /******************** UI COLORS *******************/
    /*************************************************/
    readonly property color vvaveColor: "#f84172"

    /*HANDLE EVENTS*/
    signal contextualPlayNext()

    onClosing: (close) =>
               {
                   playlist.save()
                   close.accepted = true
               }

    onFocusViewChanged:
    {
        setAndroidStatusBarColor()
    }

    function currentCategoryName() : string
    {
        switch (swipeView ? swipeView.currentIndex : -1)
        {
        case viewsIndex.tracks: return "songs"
        case viewsIndex.albums: return "albums"
        case viewsIndex.artists: return "artists"
        case viewsIndex.playlists: return "tags"
        default: return "unknown"
        }
    }

    function resolveCurrentCategoryView() : Item
    {
        if (!swipeView)
            return null

        switch (swipeView.currentIndex)
        {
        case viewsIndex.tracks:
            return _tracksView
        case viewsIndex.albums:
            return _albumsView
        case viewsIndex.artists:
            return _artistsView
        case viewsIndex.playlists:
            return _playlistsView
        default:
            return null
        }
    }

    function focusCurrentSearch()
    {
        if (focusView)
            toggleFocusView()

        const view = resolveCurrentCategoryView()
        if (!view)
            return

        const target = view.currentItem ? view.currentItem : view
        if (target && target.focusSearch)
        {
            target.focusSearch()
            return
        }

        if (view.focusSearch)
            view.focusSearch()
    }

    Loader
    {
        id: _timerLoader
        active: false

        sourceComponent: Timer
        {
            onTriggered:
            {
                Player.stop()
                if(settings.closeAfterSleep)
                {
                    root._forceClose = true
                    root.close()
                }
            }
        }
    }

    // NOTE: Anything in `.dialogLabel` or `.dialogCategory` get dynamically passed to `i18n` in ShortcutsDialog.qml, and thus should have translations. They are not translated here in case that affects their uniqueness as object keys.
    property list<Shortcut> shortcuts: [
        Shortcut
        {
            readonly property string dialogLabel: "Play/Pause"
            readonly property string dialogCategory: "Playback"
            sequence: "Space"
            onActivated: {
                if(player.playing)
                    player.pause()
                else
                    player.play()
            }
        },

        Shortcut
        {
            readonly property string dialogLabel: "Previous"
            readonly property string dialogCategory: "Playback"
            sequence: "P"
            onActivated: Player.previousTrack()
        },

        Shortcut
        {
            readonly property string dialogLabel: "Next"
            readonly property string dialogCategory: "Playback"
            sequence: "N"
            onActivated: Player.nextTrack()
        },

        Shortcut
        {
            readonly property string dialogLabel: "Rewind 10 seconds"
            readonly property string dialogCategory: "Playback"
            sequence: "Left"
            enabled: !(activeFocusItem instanceof Maui.GridBrowser || activeFocusItem instanceof GridView)
            onActivated: player.pos -= 10000
        },

        Shortcut
        {
            readonly property string dialogLabel: "Skip 10 seconds"
            readonly property string dialogCategory: "Playback"
            sequence: "Right"
            enabled: !(activeFocusItem instanceof Maui.GridBrowser || activeFocusItem instanceof GridView)
            onActivated: player.pos += 10000
        },

        Shortcut
        {
            readonly property string dialogLabel: "Increase Volume"
            readonly property string dialogCategory: "Playback"
            sequence: "Volume Up"
            onActivated: player.volume += 5
        },

        Shortcut
        {
            readonly property string dialogLabel: "Decrease Volume"
            readonly property string dialogCategory: "Playback"
            sequence: "Volume Down"
            onActivated: player.volume -= 5
        }

    ]

    Shortcut
    {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: _sideBarView && _sideBarView.sideBar && _sideBarView.sideBar.position > 0
        onActivated: handleEscapeShortcut()
    }

    FloatingDisk
    {
        id: _floatingViewer
        active: (root.isPlaying && !root.mainlistEmpty) || item
        visible: !root.mainlistEmpty && !root.focusView

        DragHandler
        {
            target: _floatingViewer
            xAxis.maximum: root.width - _floatingViewer.width
            xAxis.minimum: 0

            yAxis.maximum : root.height - _floatingViewer.height
            yAxis.minimum: 0

            onActiveChanged:
            {
                if(!active)
                {
                    let newX = Math.abs(_floatingViewer.x - (root.width - _floatingViewer.implicitWidth - 20))
                    _floatingViewer.y = Qt.binding(()=> { return root.height - _floatingViewer.implicitHeight - 20 - _mainPage.footerContainer.implicitHeight})
                    _floatingViewer.x = Qt.binding(()=> { return (root.width - _floatingViewer.implicitWidth - 20 - newX) < 0 ? 20 : root.width - _floatingViewer.implicitWidth - 20 - newX})
                }
            }
        }
    }

    Settings
    {
        id: settings
        category: "Settings"
        property bool fetchArtwork: true
        property bool focusViewDefault: false
        property bool showArtwork: false
        property bool showTitles: true
        property string sleepOption : "none"
        property bool closeAfterSleep: false
        property double volume: 1.0
        property string preferredOutput: ""
        property bool preferredOutputUserSet: false
    }

    Mpris2
    {
        playListModel: playlist
        audioPlayer: player
        playerName: 'vvave'

        onRaisePlayer:
        {
            root.raise()
        }
    }

    Action
    {
        id: _missingFileAction
        text: i18n("Remove")
        Maui.Controls.status: Maui.Controls.Negative
        onTriggered:
        {
            mainPlaylist.table.list.removeMissing(mainPlaylist.table.currentIndex)
        }
    }

    Playlist
    {
        id: playlist

        model: mainPlaylist.listModel.list
        onCurrentTrackChanged: Player.playTrack()

        onMissingFile: (track) =>
                       {
                           var message = i18n("Missing file")
                           var messageBody = track.title + " by " + track.artist + " is missing.\nDo you want to remove it from your collection?"
                           notify("dialog-question", message, messageBody, [_missingFileAction])
                       }
    }

    Player
    {
        id: player
        volume: settings.volume
        onPreferredOutputChanged:
        {
            if (!root._outputSelectionReady)
                return

            if (settings.preferredOutput !== preferredOutput)
                settings.preferredOutput = preferredOutput
        }
        onFinished:
        {
            if (!mainlistEmpty)
            {
                if (currentTrack && currentTrack.url)
                {
                    mainPlaylist.listModel.list.countUp(currentTrackIndex)
                }

                switch(settings.sleepOption)
                {
                case "eot":
                {
                    Player.stop()
                    if(settings.closeAfterSleep)
                    {
                        root._forceClose = true
                        root.close()
                    }
                    break;
                }

                case "eop":
                {
                    if(currentTrackIndex === mainPlaylist.listView.count-1)
                    {
                        Player.stop();
                        if(settings.closeAfterSleep)
                        {
                            root._forceClose = true
                            root.close()
                        }
                    }else
                    {
                        Player.nextTrack();
                    }
                    break;
                }
                case "none":
                default:
                    Player.nextTrack();
                }
            }
        }
    }

    Component
    {
        id: _fileDialogComponent
        FB.FileDialog {onClosed: destroy()}
    }

    Component
    {
        id: _shortcutsDialogComponent
        ShortcutsDialog {onClosed: destroy()}
    }

    Component
    {
        id: _settingsDialogComponent
        SettingsDialog {onClosed: destroy()}
    }

    Component
    {
        id: _removeDialogComponent

        FB.FileListingDialog
        {
            id: _removeDialog
            onClosed: destroy()

            urls: selectionBar.uris

            title: i18np("Remove track", "Remove %1 tracks", urls.length)
            message: i18n("Are you sure you want to remove these files? This action can not be undone.")

            actions: [
                Action
                {
                    Maui.Controls.status: Maui.Controls.Negative
                    text: i18n("Remove")
                    onTriggered:
                    {
                        FB.FM.removeFiles(_removeDialog.urls)
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

    Component
    {
        id: _playlistDialogComponent

        FB.TagsDialog
        {
            Action
            {
                property string tag
                id: _openPlaylistAction
                text: tag
                onTriggered:
                {
                    goToPlaylist(tag)
                }
            }

            onTagsReady: (tags) =>
                         {
                             var actions = []
                             if(tags.length === 1)
                             {
                                 _openPlaylistAction.tag = tags[0]
                                 actions = [_openPlaylistAction]
                                 root.lastUsedPlaylist = tags[0]
                             }

                             Maui.App.rootComponent.notify("dialog-info", i18n("Saved"), i18n("Track added to playlist"), actions)
                             composerList.updateToUrls(tags)
                         }

            composerList.strict: false
        }
    }

    Component
    {
        id: _mainMenuComponent
        Maui.ToolButtonMenu
        {
            icon.name: "overflow-menu"

            MenuItem
            {
                text: i18n("Shortcuts")
                icon.name: "configure-shortcuts"
                onTriggered: openShortcutsDialog()
            }

            MenuItem
            {
                text: i18n("Settings")
                icon.name: "settings-configure"
                onTriggered: openSettingsDialog()
            }

            MenuItem
            {
                text: i18n("About")
                icon.name: "documentinfo"
                onTriggered: Maui.App.aboutDialog()
            }
        }
    }

    Maui.SideBarView
    {
        id: _sideBarView
        anchors.fill: parent
        background: null
        Maui.Theme.colorSet: Maui.Theme.View
        readonly property real topChromeOffset: (swipeView ? swipeView.headBar.height : 0) + Maui.Style.space.small
        sideBar.preferredWidth: Math.min(root.width * (root.height > root.width ? 0.84 : 0.38), Maui.Style.units.gridUnit * 24)
        sideBar.minimumWidth: Maui.Style.units.gridUnit * 14
        sideBar.maximumWidth: Maui.Style.units.gridUnit * 30
        sideBar.collapsed: root.height > root.width || root.width < Maui.Style.units.gridUnit * 42
        sideBar.floats: true
        sideBar.y: _sideBarView.topChromeOffset
        sideBar.height: Math.max(0, _sideBarView.height - _mainPage.footBar.height - _sideBarView.topChromeOffset - Maui.Style.space.small)
        sideBar.autoShow: false
        sideBar.autoHide: true

        sideBarContent: Maui.Page
        {
            id: _playlistPanel
            readonly property int panelMargin: Maui.Handy.isMobile ? Maui.Style.space.medium : Maui.Style.contentMargins
            x: panelMargin
            y: panelMargin
            width: Math.max(0, _sideBarView.sideBar.width - (panelMargin * 2))
            height: Math.max(0, _sideBarView.sideBar.height - (panelMargin * 2))
            clip: true
            opacity: _sideBarView.sideBar.position

            Behavior on opacity
            {
                NumberAnimation
                {
                    duration: 180
                    easing.type: Easing.InOutQuad
                }
            }

            layer.enabled: true
            Maui.Theme.colorSet: Maui.Theme.Window
            Maui.Theme.inherit: false

            background: Rectangle
            {
                clip: true
                color: Maui.Theme.alternateBackgroundColor
                radius: Maui.Style.radiusV
                border.color: Maui.Theme.backgroundColor
                border.width: 1
            }

            MainPlaylist
            {
                id: _mainPlaylist
                anchors.fill: parent
                background: null
            }
        }

        Maui.Page
        {
            id: _mainPage
            anchors.fill: parent
            background: null
            headBar.visible: false
            footerMargins: Maui.Style.contentMargins

        footBar.rightContent: ToolButton
        {
            visible: focusView
            icon.name: root.focusView ? "go-down" : "go-up"
            onClicked: toggleFocusView()
        }

        footBar.middleContent: [

            Maui.ToolActions
            {
                Layout.alignment: Qt.AlignCenter

                display: ToolButton.IconOnly
                expanded: true
                autoExclusive: false
                checkable: false

                Action
                {
                    icon.name: "media-skip-backward"
                    onTriggered: Player.previousTrack()
                }

                Action
                {
                    id: playIcon
                    text: i18n("Play and pause")
                    enabled: currentTrackIndex >= 0
                    icon.name: isPlaying ? "media-playback-pause" : "media-playback-start"
                    onTriggered: player.playing ? player.pause() : player.play()
                }

                Action
                {
                    text: i18n("Next")
                    icon.name: "media-skip-forward"
                    onTriggered: Player.nextTrack()
                }
            }
        ]

            StackView
            {
                id: _stackView
                focus: true
                anchors.fill: parent
                initialItem: settings.focusViewDefault ? _focusViewComponent : swipeView
                background: null

            pushExit: Transition
            {
                ParallelAnimation
                {
                    PropertyAnimation
                    {
                        property: "y"
                        from: 0
                        to:  _stackView.height
                        duration: 200
                        easing.type: Easing.InOutCubic
                    }

                    NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 300; easing.type: Easing.InOutCubic }
                }
            }

            pushEnter: null

            popExit: null

            popEnter: Transition
            {
                ParallelAnimation
                {
                    PropertyAnimation
                    {
                        property: "y"
                        from: _stackView.height
                        to: 0
                        duration: 200
                        easing.type: Easing.InOutCubic
                    }

                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
                }
            }

            Maui.SwipeView
            {
                id: swipeView
                maxViews: 4
                visible: StackView.status !== StackView.Inactive
                onCurrentIndexChanged:
                {
                }

                headerMargins: Maui.Style.contentMargins
                footerMargins: headerMargins

                floatingFooter: true
                flickable:
                {
                    const current = swipeView.currentItem
                    if (!current)
                        return null

                    if (current.flickable)
                        return current.flickable

                    return current.item ? current.item.flickable : null
                }
                altHeader: Maui.Handy.isMobile
                Maui.Controls.showCSD: true
                background: null

                headBar.forceCenterMiddleContent: true
                headBar.middleContent: [
                    RowLayout
                    {
                        spacing: Maui.Style.space.small
                        Layout.alignment: Qt.AlignCenter

                        ToolButton
                        {
                            text: i18n("Songs")
                            display: AbstractButton.IconOnly
                            icon.name: "view-media-track"
                            onClicked: showBrowserCategory(viewsIndex.tracks)
                        }

                        ToolButton
                        {
                            text: i18n("Albums")
                            display: AbstractButton.IconOnly
                            icon.name: "view-media-album-cover"
                            onClicked: showBrowserCategory(viewsIndex.albums)
                        }

                        ToolButton
                        {
                            text: i18n("Artists")
                            display: AbstractButton.IconOnly
                            icon.name: "view-media-artist"
                            onClicked: showBrowserCategory(viewsIndex.artists)
                        }

                        ToolButton
                        {
                            text: i18n("Tags")
                            display: AbstractButton.IconOnly
                            icon.name: "tag"
                            onClicked: showBrowserCategory(viewsIndex.playlists)
                        }
                    }
                ]
                headBar.leftContent: [
                    ToolButton
                    {
                        text: i18n("Toggle Sidebar")
                        display: AbstractButton.IconOnly
                        icon.name: (_sideBarView.sideBar.visible && _sideBarView.sideBar.position > 0) ? "sidebar-collapse" : "sidebar-expand"
                        checkable: true
                        checked: _sideBarView.sideBar.visible && _sideBarView.sideBar.position > 0
                        ToolTip.visible: hovered
                        ToolTip.text: i18n("Toggle sidebar")
                        onClicked: toggleSidebar()
                    },

                    ToolSeparator
                    {
                        bottomPadding: 10
                        topPadding: 10
                    }

                ]
                headBar.rightContent: [
                    ToolSeparator
                    {
                        bottomPadding: 10
                        topPadding: 10
                    },

                    Loader
                    {
                        asynchronous: true
                        sourceComponent: _mainMenuComponent
                    }
                ]

                footer: SelectionBar
                {
                    id: _selectionBar
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent ? Math.min(parent.width - (Maui.Style.space.medium * 2), implicitWidth) : implicitWidth

                    maxListHeight: swipeView.height - Maui.Style.space.medium
                    display: ToolButton.IconOnly

                    onExitClicked:
                    {
                        root.selectionMode = false
                        clear()
                    }

                    onVisibleChanged:
                    {
                        if(!visible)
                        {
                            root.selectionMode = false
                        }
                    }
                }

                TracksView
                {
                    id: _tracksView
                }

                AlbumsView
                {
                    id: _albumsView
                    holder.title : i18n("No Albums!")
                    holder.body: i18n("Add new music sources")
                    list.query: Albums.ALBUMS
                }

                AlbumsView
                {
                    id: _artistsView
                    holder.title : i18n("No Artists!")
                    holder.body: i18n("Add new music sources")
                    list.query : Albums.ARTISTS
                }

                PlaylistsView
                {
                    id: _playlistsView
                }

                data: Loader
                {
                    width: parent.width
                    anchors.bottom: parent.bottom
                    active: Vvave.scanning
                    visible: active
                    sourceComponent: Maui.ProgressIndicator {}
                }

                function getGoBackFunc()
                {
                    if (!currentItem)
                        return null

                    const viewItem = currentItem.item ? currentItem.item : currentItem
                    return (viewItem && ('getGoBackFunc' in viewItem)) ? viewItem.getGoBackFunc() : null
                }
            }

            Component
            {
                id: _focusViewComponent

                FocusView
                {
                    objectName: "FocusView"
                }
            }
        }
    }
    }

    Loader
    {
        id: _miniModeComponent
        visible: active
        active: false
        sourceComponent: MiniMode
        {
            onClosing: (close) =>
                       {
                           toggleMiniMode()
                           close.accepted = true
                       }
        }
    }

    Component.onCompleted:
    {
        root._outputSelectionReady = false

        Qt.callLater(() => _sideBarView.sideBar.close())

        const outputs = player.outputs
        const findOutput = (name) =>
        {
            const target = String(name || "").toLowerCase()
            if (target.length === 0)
                return ""

            for (const out of outputs)
            {
                if (String(out).toLowerCase() === target)
                    return out
            }

            return ""
        }

        const isRealtimeOutput = (name) =>
        {
            const key = String(name || "").toLowerCase()
            return key === "pipewire" || key === "pulse" || key === "pulseaudio" || key === "jack"
        }

        const isAutoSelectable = (name) =>
        {
            const key = String(name || "").toLowerCase()
            return key === "null" || isRealtimeOutput(key)
        }

        let selectedOutput = ""
        const bestRealtimeOutput = () =>
        {
            const preferredOrder = ["pipewire", "pulse", "pulseaudio", "jack"]
            for (const name of preferredOrder)
            {
                const candidate = findOutput(name)
                if (candidate.length > 0 && player.isOutputLikelyAvailable(candidate))
                    return candidate
            }
            return ""
        }

        const saved = findOutput(settings.preferredOutput)
        if (saved.length > 0 && player.isOutputLikelyAvailable(saved))
        {
            const savedKey = String(saved).toLowerCase()
            const bestRealtime = bestRealtimeOutput()
            const shouldAvoidStaleAlsa = !settings.preferredOutputUserSet && savedKey === "alsa" && bestRealtime.length > 0
            const shouldIgnoreUnsafeSaved = !settings.preferredOutputUserSet && !isAutoSelectable(savedKey)
            selectedOutput = shouldAvoidStaleAlsa || shouldIgnoreUnsafeSaved ? bestRealtime : saved
        }

        if (selectedOutput.length === 0 && String(settings.preferredOutput || "").length > 0)
        {
            const current = findOutput(player.preferredOutput)
            if (current.length > 0 && player.isOutputLikelyAvailable(current) && isAutoSelectable(current))
                selectedOutput = current
        }

        if (selectedOutput.length === 0)
        {
            selectedOutput = bestRealtimeOutput()
        }

        if (selectedOutput.length === 0)
        {
            const nullOutput = findOutput("null")
            if (nullOutput.length > 0)
                selectedOutput = nullOutput
        }

        if (selectedOutput.length === 0)
        {
            const preferredOrder = ["pipewire", "pulse", "pulseaudio", "jack", "null"]
            for (const name of preferredOrder)
            {
                const candidate = findOutput(name)
                if (candidate.length > 0)
                {
                    selectedOutput = candidate
                    break
                }
            }
        }

        // If nothing could be reliably detected, keep audio disabled instead
        // of forcing fragile backends like ALSA/OSS.
        if (selectedOutput.length === 0)
            selectedOutput = findOutput("null")

        if (selectedOutput.length > 0)
        {
            player.preferredOutput = selectedOutput
            settings.preferredOutput = selectedOutput
        }

        root._outputSelectionReady = true

        Vvave.fetchArtwork = settings.fetchArtwork
        Vvave.rescan()
    }

    function toggleFocusView()
    {
        if(focusView)
        {
            if (_stackView.depth > 1)
                _stackView.pop()
            else
                _stackView.push(swipeView)

        }else
        {
            _stackView.push(_focusViewComponent)
        }

        if(_stackView.currentItem)
            _stackView.currentItem.forceActiveFocus()
    }

    function toggleMiniMode()
    {
        if(Maui.Handy.isMobile)
        {
            return
        }

        if(miniMode)
        {
            _miniModeComponent.item.close()
            _miniModeComponent.active = false
        }else
        {
            _miniModeComponent.active = true
        }
    }

    function toggleSidebar()
    {
        _sideBarView.sideBar.toggle()
    }

    function handleEscapeShortcut()
    {
        if (!_sideBarView || !_sideBarView.sideBar || _sideBarView.sideBar.position === 0)
            return false

        _sideBarView.sideBar.close()
        Qt.callLater(() => {
            if (_stackView && _stackView.currentItem && _stackView.currentItem.forceActiveFocus)
                _stackView.currentItem.forceActiveFocus()
        })
        return true
    }

    function showBrowserCategory(index)
    {
        if(root.focusView)
        {
            toggleFocusView()
        }

        swipeView.currentIndex = index
    }

    function openShortcutsDialog()
    {
        var dialog = _shortcutsDialogComponent.createObject(root)
        dialog.open()
    }

    function openSettingsDialog()
    {
        var dialog = _settingsDialogComponent.createObject(root)
        dialog.open()
    }

    function goToAlbum(artist, album)
    {
        if(root.focusView)
        {
            toggleFocusView()
        }

        swipeView.currentIndex = viewsIndex.albums
        _albumsView.populateTable(album, artist)
    }

    function goToArtist(artist)
    {
        if(root.focusView)
        {
            toggleFocusView()
        }

        swipeView.currentIndex = viewsIndex.artists
        _artistsView.populateTable(undefined, artist)
    }

    function goToPlaylist(tag)
    {
        if(root.focusView)
        {
            toggleFocusView()
        }

        swipeView.currentIndex = viewsIndex.playlists
        _playlistsView.populate(tag)
    }

    function tagUrls(urls)
    {
        if(root.tagsDialog)
        {
            root.tagsDialog.composerList.urls = urls
        }else
        {
            root.tagsDialog =  _playlistDialogComponent.createObject(root, ({'composerList.urls' : urls}))
        }

        root.tagsDialog.open()
    }

    function openFiles(urls)
    {
        Player.appendUrlsAt(urls, 0)
        Player.playAt(0)
    }

    function isUrlOpen(url : string) : bool
    {
        if (!mainPlaylist || !mainPlaylist.listModel || !mainPlaylist.listModel.list)
            return false

        const playlistUrls = mainPlaylist.listModel.list.urls()
        const target = Qt.resolvedUrl(url)

        for (const playlistUrl of playlistUrls)
        {
            if (playlistUrl === url || Qt.resolvedUrl(playlistUrl) === target)
                return true
        }

        return false
    }

    function getGoBackFunc()
    {
        const currentItem = _stackView ? _stackView.currentItem : null
        if (!currentItem)
            return null

        return ('getGoBackFunc' in currentItem) ? currentItem.getGoBackFunc() : null
    }

    function setSleepTimer(option)
    {
        const timerFunc = (min) =>
                        {
            _timerLoader.active = true
            _timerLoader.item.interval = min * 60 * 1000
        };

        switch(option)
        {
        case "15m" :
            settings.sleepOption = "15m";
            timerFunc(15);
            break;
        case "30m" :
            settings.sleepOption = "30m";
            timerFunc(30);
            break;
        case "60m" :
            settings.sleepOption = "60m";
            timerFunc(60);
            break;
        case "eot" :
            settings.sleepOption = "eot";
            _timerLoader.active=false;
            break;
        case "eop" :
            settings.sleepOption = "eop";
            _timerLoader.active=false;
            break;
        case "none" :
        default:
            settings.sleepOption = "none";
            _timerLoader.active=false;
            break;
        }
    }
}
