import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.mauikit.controls as Maui
import org.maui.vvave

import "VVaveGrid"
import "VVaveTable"

import "../db/Queries.js" as Q
import "../utils/Player.js" as Player

StackView
{
    id: control
    background: null

    property alias list : albumsViewGrid.list

    property string currentQuery: ""
    property string currentAlbum: ""
    property string currentArtist: ""

    property alias holder: albumsViewGrid.holder
    property alias prefix: albumsViewGrid.prefix

    property Flickable flickable : currentItem.flickable

    initialItem: VVaveGrid
    {
        id: albumsViewGrid
        background: null
        holder.emoji: "folder-music"
        holder.actions: []

        onAlbumCoverClicked:(album, artist) => control.openSelection(album, artist)
        onPlayAll: (album, artist) =>
        {
            const albumName = String(album || "").trim()
            const artistName = String(artist || "").trim()
            var query = ""

            if (albumName.length > 0 && artistName.length > 0)
            {
                query = Q.GET.albumTracks_.arg(encodeURIComponent(albumName))
                query = query.arg(encodeURIComponent(artistName))
            } else if (artistName.length > 0 && albumName.length === 0)
            {
                query = Q.GET.artistTracks_.arg(encodeURIComponent(artistName))
            }

            if (query.length > 0)
                Player.playQuery(query)
        }
    }

    Component
    {
        id: _tracksTableComponent

        VVaveTable
        {
            list.query: control.currentQuery
            trackNumberVisible: true
            coverArtVisible: settings.fetchArtwork
            collapseRepeatedAlbumArt: false
            focus: true

            holder.emoji: "qrc:/assets/media-album-track.svg"
            holder.title : "Oops!"
            holder.body: i18n("This list is empty")

            headBar.visible: true
            headBar.farLeftContent: RowLayout
            {
                spacing: Maui.Style.space.small

                ToolButton
                {
                    icon.name: "go-previous"
                    display: AbstractButton.IconOnly
                    ToolTip.visible: hovered
                    ToolTip.text: control.depth > 2 ? i18n("Back to artist") : (control.prefix === "album" ? i18n("Back to albums") : i18n("Back to artists"))
                    onClicked: control.pop()
                }

                ToolSeparator
                {
                    topPadding: 10
                    bottomPadding: 10
                }
            }

            onQueueTrack: (index) => Player.queueTracks([listModel.get(index)], index)
            onRowClicked: (index) => Player.quickPlay(listModel.get(index))
            onAppendTrack: (index) => Player.addTrack(listModel.get(index))

            onPlayAll:
            {
                control.pop()
                Player.playAllModel(listModel.list)
            }

            onAppendAll:
            {
                control.pop()
                Player.appendAllModel(listModel.list)
            }

            onShuffleAll:
            {
                control.pop()
                Player.shuffleAllModel(listModel.list)
            }
        }
    }

    Component
    {
        id: _artistDetailsComponent

        VVaveGrid
        {
            id: artistDetailsGrid
            background: null
            list.query: Albums.ALBUMS
            holder.emoji: "folder-music"
            holder.actions: []

            function applyArtistFilter()
            {
                const artistName = String(control.currentArtist || "").trim()
                if (artistName.length === 0)
                    return

                listModel.filterRole = "artist"
                listModel.filters = [artistName]
            }

            headBar.visible: true
            headBar.farLeftContent: RowLayout
            {
                spacing: Maui.Style.space.small

                ToolButton
                {
                    icon.name: "go-previous"
                    display: AbstractButton.IconOnly
                    ToolTip.visible: hovered
                    ToolTip.text: i18n("Back to artists")
                    onClicked: control.pop()
                }

                ToolSeparator
                {
                    topPadding: 10
                    bottomPadding: 10
                }

                Label
                {
                    text:
                    {
                        const artistName = String(control.currentArtist || "")
                        return artistName.length > 12 ? `${artistName.slice(0, 11)}…` : artistName
                    }
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.maximumWidth: Maui.Style.units.gridUnit * 12
                }
            }
            headBar.leftContent: Item {}
            headBar.middleContent: Item {}
            headBar.rightContent: Item {}

            Connections
            {
                target: control
                function onCurrentArtistChanged()
                {
                    artistDetailsGrid.applyArtistFilter()
                }
            }

            onAlbumCoverClicked: (album, artist) => control.populateTable(album, artist)
            onPlayAll: (album, artist) =>
            {
                const albumName = String(album || "").trim()
                const artistName = String(artist || "").trim()
                var query = ""

                if (albumName.length > 0 && artistName.length > 0) {
                    query = Q.GET.albumTracks_.arg(encodeURIComponent(albumName))
                    query = query.arg(encodeURIComponent(artistName))
                } else if (artistName.length > 0) {
                    query = Q.GET.artistTracks_.arg(encodeURIComponent(artistName))
                }

                if (query.length > 0)
                    Player.playQuery(query)
            }

            Component.onCompleted: applyArtistFilter()
        }
    }

    function openSelection(album, artist)
    {
        const albumName = String(album || "").trim()
        const artistName = String(artist || "").trim()

        if (artistName.length === 0)
            return

        if (control.prefix === "artist" || albumName.length === 0)
        {
            populateArtist(artistName)
            return
        }

        populateTable(albumName, artistName)
    }

    function populateArtist(artist)
    {
        currentAlbum = ""
        currentArtist = String(artist || "").trim()
        currentQuery = Q.GET.artistTracks_.arg(encodeURIComponent(currentArtist))
        control.push(_artistDetailsComponent)
    }

    function populateTable(album, artist)
    {
        currentAlbum = String(album || "").trim()
        currentArtist = String(artist || "").trim()

        var query
        if (currentAlbum.length > 0 && currentArtist.length > 0)
        {
            query = Q.GET.albumTracks_.arg(encodeURIComponent(currentAlbum))
            query = query.arg(encodeURIComponent(currentArtist))
        }
        else if (currentArtist.length > 0 && currentAlbum.length === 0)
        {
            query = Q.GET.artistTracks_.arg(encodeURIComponent(currentArtist))
        }

        control.currentQuery = query
        control.push(_tracksTableComponent)
    }

    function getGoBackFunc()
    {
        if (control.depth > 1)
            return () => { control.pop() }
        else
            return null
    }
}
