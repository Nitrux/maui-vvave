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

    onFocusViewChanged: setAndroidStatusBarColor()

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
            sequence: "+"
            sequences: ["="]
            onActivated: player.volume += 5
        },

        Shortcut
        {
            readonly property string dialogLabel: "Decrease Volume"
            readonly property string dialogCategory: "Playback"
            sequence: "-"
            onActivated: player.volume -= 5
        },

        Shortcut
        {
            readonly property string dialogLabel: "Filter"
            readonly property string dialogCategory: "Navigation"
            sequences: [StandardKey.Find]
            onActivated: toggleFilterFocus()
        },

        Shortcut
        {
            readonly property string dialogLabel: "Go Back"
            readonly property string dialogCategory: "Navigation"
            sequences: [StandardKey.Back]
            onActivated: {
                // I couldn't get Keys.onShortcutOverride in each view to work. I guess this is more dynamic anyway.
                let func = getGoBackFunc()
                if (func) {
                    func()
                    return
                }
            }
        },

        Shortcut
        {
            readonly property string dialogLabel: "Queue Track"
            readonly property string dialogCategory: "Navigation"
            sequences: ["Shift+Return", "Shift+Enter"]
            // StandardKey.InsertLineSeparator only gets "Enter", not "Return".
            onActivated: contextualPlayNext()
        },

        Shortcut
        {
            readonly property string dialogLabel: "Shortcuts"
            readonly property string dialogCategory: "Navigation"
            sequence: "Ctrl+/"
            onActivated: openShortcutsDialog()
        },

        Shortcut
        {
            readonly property string dialogLabel: "Settings"
            readonly property string dialogCategory: "Navigation"
            sequence: "Ctrl+,"
            onActivated: openSettingsDialog()
        },

        Shortcut
        {
            readonly property string dialogLabel: "Context Actions"
            readonly property string dialogCategory: "Navigation"
            sequence: "Menu"
            onActivated: {
                if (activeFocusItem) {
                    let func = (activeFocusItem.currentItem ?? activeFocusItem).tryOpenContextMenu
                    if (func) {
                        func()
                        return
                    }
                }
                console.log("NO CONTEXT MENU", activeFocusItem, activeFocusItem.currentItem)
            }
        }]

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
            console.log("REMOVE TIU MSISING", mainPlaylist.table.currentIndex)
            mainPlaylist.table.list.removeMissing(mainPlaylist.table.currentIndex)
            console.log("REMOVE TIU MSISING 2", mainPlaylist.table.currentIndex)
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
                    console.log("Open playlist view", tag)
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

        sideBar.autoShow: true
        sideBar.autoHide: true
        sideBar.resizeable: !Maui.Handy.isMobile
        sideBar.preferredWidth: Math.max(Maui.Style.units.gridUnit * 14, Math.min(root.width * 0.32, Maui.Style.units.gridUnit * 24))
        sideBar.background: Rectangle
        {
            color: Maui.Theme.alternateBackgroundColor
            radius: Maui.Style.radiusV
            opacity: 0.94
        }

        sideBarContent: MainPlaylist
        {
            id: _mainPlaylist
            anchors.fill: parent

            background: Rectangle
            {
                color: Maui.Theme.alternateBackgroundColor
                radius: Maui.Style.radiusV
                opacity: 0.94
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
                initialItem: _focusViewComponent
                background: null

            Component.onCompleted:
            {
                if(!settings.focusViewDefault)
                {
                    toggleFocusView()
                }
            }

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

                headBar.middleContent: []
                headBar.leftContent: [
                    ToolButton
                    {
                        text: i18n("Toggle Sidebar")
                        display: AbstractButton.IconOnly
                        icon.name: _sideBarView.sideBar.visible ? "sidebar-collapse" : "sidebar-expand"
                        onClicked: toggleSidebar()
                    },

                    ToolSeparator
                    {
                        bottomPadding: 10
                        topPadding: 10
                    },

                    ToolButton
                    {
                        text: i18n("Songs")
                        display: AbstractButton.IconOnly
                        icon.name: "view-media-track"
                        checkable: true
                        checked: swipeView.currentIndex === viewsIndex.tracks
                        onClicked: showBrowserCategory(viewsIndex.tracks)
                    },

                    ToolButton
                    {
                        text: i18n("Albums")
                        display: AbstractButton.IconOnly
                        icon.name: "view-media-album-cover"
                        checkable: true
                        checked: swipeView.currentIndex === viewsIndex.albums
                        onClicked: showBrowserCategory(viewsIndex.albums)
                    },

                    ToolButton
                    {
                        text: i18n("Artists")
                        display: AbstractButton.IconOnly
                        icon.name: "view-media-artist"
                        checkable: true
                        checked: swipeView.currentIndex === viewsIndex.artists
                        onClicked: showBrowserCategory(viewsIndex.artists)
                    },

                    ToolButton
                    {
                        text: i18n("Tags")
                        display: AbstractButton.IconOnly
                        icon.name: "tag"
                        checkable: true
                        checked: swipeView.currentIndex === viewsIndex.playlists
                        onClicked: showBrowserCategory(viewsIndex.playlists)
                    },

                    ToolSeparator
                    {
                        bottomPadding: 10
                        topPadding: 10
                    },

                    ToolButton
                    {
                        text: i18n("Search")
                        display: AbstractButton.IconOnly
                        icon.name: "edit-find"
                        checkable: true
                        checked: !!getFilterField() && getFilterField().activeFocus
                        onClicked: toggleFilterFocus()
                    },

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
                headBar.rightContent: []

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

                Maui.SwipeViewLoader
                {
                    Maui.Controls.title: i18n("Songs")
                    Maui.Controls.iconName: "view-media-track"

                TracksView
                {
                    id: _tracksView
                }
            }

                Maui.SwipeViewLoader
                {
                    id: _albumsViewLoader

                    Maui.Controls.title: i18n("Albums")
                    Maui.Controls.iconName: "view-media-album-cover"

                    property var pendingAlbum : ({})

                    AlbumsView
                    {
                        holder.title : i18n("No Albums!")
                        holder.body: i18n("Add new music sources")
                        list.query: Albums.ALBUMS

                        Component.onCompleted:
                        {
                            if(Object.keys(_albumsViewLoader.pendingAlbum).length)
                            {
                                populateTable(_albumsViewLoader.pendingAlbum.album, _albumsViewLoader.pendingAlbum.artist)
                            }
                        }
                    }
                }

                Maui.SwipeViewLoader
                {
                    id: _artistViewLoader
                    Maui.Controls.title: i18n("Artists")
                    Maui.Controls.iconName: "view-media-artist"

                    property string pendingArtist

                    AlbumsView
                    {
                        holder.title : i18n("No Artists!")
                        holder.body: i18n("Add new music sources")
                        list.query : Albums.ARTISTS

                        Component.onCompleted:
                        {
                            if(_artistViewLoader.pendingArtist.length)
                            {
                                populateTable(undefined, _artistViewLoader.pendingArtist)

                            }
                        }
                    }
                }

                Maui.SwipeViewLoader
                {
                    id: _playlistsViewLoader
                    Maui.Controls.title: i18n("Tags")
                    Maui.Controls.iconName: "tag"
                    property string pendingTag

                    PlaylistsView {}
                }

                data: Loader
                {
                    width: parent.width
                    anchors.bottom: parent.bottom
                    active: Vvave.scanning
                    visible: active
                    sourceComponent: Maui.ProgressIndicator {}
                }

                function getFilterField() : Item
                {
                    if (!currentItem || !currentItem.item || !currentItem.item.getFilterField)
                        return null

                    return currentItem.item.getFilterField()
                }

                function getGoBackFunc()
                {
                    if (!currentItem || !currentItem.item)
                        return null

                    return 'getGoBackFunc' in currentItem.item ? currentItem.item.getGoBackFunc() : null
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
        Vvave.fetchArtwork = settings.fetchArtwork
        Vvave.rescan()
    }

    function toggleFocusView()
    {
        if(focusView)
        {
            _stackView.push(swipeView)

        }else
        {
            _stackView.pop()
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

    function showBrowserCategory(index)
    {
        if(root.focusView)
        {
            toggleFocusView()
        }

        swipeView.currentIndex = index
    }

    function toggleFilterFocus()
    {
        let filterField = getFilterField()
        if (!filterField)
            return

        if (!filterField.activeFocus)
            filterField.forceActiveFocus()
        else
            filterField.focus = false
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
        if(_albumsViewLoader.item)
        {
            _albumsViewLoader.item.populateTable(album, artist)
        }else
        {
            _albumsViewLoader.pendingAlbum = ({'artist': artist, 'album': album})
        }
    }

    function goToArtist(artist)
    {
        if(root.focusView)
        {
            toggleFocusView()
        }

        swipeView.currentIndex = viewsIndex.artists
        if(_artistViewLoader.item)
        {
            _artistViewLoader.item.populateTable(undefined, artist)
        }else
        {
            _artistViewLoader.pendingArtist = artist
        }
    }

    function goToPlaylist(tag)
    {
        if(root.focusView)
        {
            toggleFocusView()
        }

        swipeView.currentIndex = viewsIndex.playlists
        if(_playlistsViewLoader.item)
        {
            _playlistsViewLoader.item.populate(tag)
        }else
        {
            _playlistsViewLoader.pendingTag = tag
        }
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
        console.log("APPEND URLS", urls)
        Player.appendUrlsAt(urls, 0)
        Player.playAt(0)
    }

    function isUrlOpen(url : string) : bool
    {
        return false;
    }

    function getFilterField() : Item
    {
        return ('getFilterField' in _stackView.currentItem) ?
                    _stackView.currentItem.getFilterField() :
                    null
    }

    function getGoBackFunc()
    {
        let filterField = getFilterField()
        if (filterField && filterField.activeFocus) {
            return () => { filterField.focus = false }
        } else {
            return ('getGoBackFunc' in _stackView.currentItem) ?
                        _stackView.currentItem.getGoBackFunc() :
                        null
        }
    }

    function setSleepTimer(option)
    {
        console.log("Setting sleep timer to ", option)
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
