import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.mauikit.controls as Maui

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

        onAlbumCoverClicked:(album, artist) => control.populateTable(album, artist)
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
            collapseRepeatedAlbumArt: control.currentAlbum.length === 0
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
                    ToolTip.text: control.prefix === "album" ? i18n("Back to albums") : i18n("Back to artists")
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

    function populateTable(album, artist)
    {
        control.push(_tracksTableComponent)

        currentAlbum = album === undefined ? "" : album
        currentArtist = artist

        var query
        if(currentAlbum && currentArtist)
        {
            query = Q.GET.albumTracks_.arg(encodeURIComponent(currentAlbum))
            query = query.arg(encodeURIComponent(currentArtist))

        }else if(currentArtist && !currentAlbum.length)
        {
            query = Q.GET.artistTracks_.arg(encodeURIComponent(currentArtist))
        }

        control.currentQuery = query
    }

    function getGoBackFunc()
    {
        if (control.depth > 1)
            return () => { control.pop() }
        else
            return null
    }
}
